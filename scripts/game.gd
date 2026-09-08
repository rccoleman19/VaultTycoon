class_name VaultGame
extends Node2D

signal game_started
signal game_won(survivors: int)
signal game_lost

const SIMULATION_TICK := 0.1
const RIGHT_PANEL_WIDTH := 310.0
const BUILD_KIND_BY_TOOL := {
	"bed": VaultBuilding.Kind.BED,
	"lamp": VaultBuilding.Kind.LAMP,
	"generator": VaultBuilding.Kind.GENERATOR,
	"grow": VaultBuilding.Kind.GROW_TRAY,
	"kitchen": VaultBuilding.Kind.KITCHEN,
	"stockpile": VaultBuilding.Kind.STOCKPILE,
	"air": VaultBuilding.Kind.AIR_RECYCLER,
	"rec": VaultBuilding.Kind.RECREATION_CONSOLE,
	"medical": VaultBuilding.Kind.MEDICAL_BED,
}

@onready var map_grid: MapGrid = $MapGrid
@onready var building_root: Node2D = $Buildings
@onready var resident_root: Node2D = $Colonists
@onready var job_system: JobSystem = $JobSystem
@onready var power_grid: PowerGrid = $PowerGrid
@onready var lighting_system: LightingSystem = $LightingSystem
@onready var food_system: FoodSystem = $FoodSystem
@onready var oxygen_system: OxygenSystem = $OxygenSystem
@onready var day_cycle: DayCycle = $DayCycle
@onready var breach_system: BreachSystem = $BreachSystem
@onready var save_load: SaveLoad = $SaveLoad
@onready var world_camera: Camera2D = $Camera2D
@onready var player_orders: PlayerOrders = $PlayerOrders

var buildings: Array[VaultBuilding] = []
var residents: Array[VaultResident] = []
var next_building_id := 1
var active_tool := "select"
var selected_resident_id := -1
var selected_building_id := -1
var selected_breach := false
var simulation_speed := 1
var user_paused := true
var tutorial_open := true
var ended := false
var outcome := ""
var status_message := "Select DIG and mark rock beside the chamber."
var status_message_left := 0.0

var _simulation_accumulator := 0.0
var _dragging_camera := false


func _ready() -> void:
	map_grid.setup(
		Callable(self, "_has_cancelable_blueprint_at"),
		Callable(self, "_is_reserved_cell"),
		Callable(self, "_is_stockpile_floor"),
	)
	lighting_system.setup(map_grid)
	breach_system.setup(self)
	job_system.setup(self)
	map_grid.tile_changed.connect(_on_map_topology_changed)
	map_grid.rubble_created.connect(_on_rubble_created)
	map_grid.dig_orders_removed.connect(_on_dig_orders_removed)
	food_system.raw_food_produced.connect(_on_raw_food_produced)
	day_cycle.day_started.connect(_on_day_started)
	power_grid.brownout_started.connect(_on_power_brownout_started)
	power_grid.brownout_cleared.connect(_on_power_brownout_cleared)
	power_grid.allocation_changed.connect(_on_power_allocation_changed)
	breach_system.warning_started.connect(_on_breach_warning_started)
	breach_system.breach_opened.connect(_on_breach_opened)
	breach_system.breach_sealed.connect(_on_breach_sealed)
	player_orders.setup(self)
	new_game(true)


func _process(delta: float) -> void:
	_update_camera(delta)
	status_message_left = maxf(0.0, status_message_left - delta)
	if not is_simulation_paused():
		_simulation_accumulator += delta * float(simulation_speed)
		var steps := 0
		while _simulation_accumulator >= SIMULATION_TICK and steps < 40:
			_simulation_step(SIMULATION_TICK)
			_simulation_accumulator -= SIMULATION_TICK
			steps += 1
			if is_simulation_paused():
				_simulation_accumulator = 0.0
				break
	player_orders.refresh()


func new_game(show_tutorial := false) -> void:
	player_orders.show_work_priorities(false)
	for building in buildings:
		building.free()
	for resident in residents:
		resident.free()
	buildings.clear()
	residents.clear()
	next_building_id = 1
	map_grid.new_wing()
	job_system.reset()
	power_grid.reset()
	lighting_system.reset()
	food_system.reset()
	oxygen_system.reset()
	day_cycle.reset()
	breach_system.reset()
	ended = false
	outcome = ""
	active_tool = "select"
	selected_resident_id = -1
	selected_building_id = -1
	selected_breach = false
	_simulation_accumulator = 0.0
	_spawn_starting_fixture(VaultBuilding.Kind.GENERATOR, Vector2i(24, 15), true)
	_spawn_starting_fixture(VaultBuilding.Kind.LAMP, Vector2i(22, 14), false)
	_spawn_starting_fixture(VaultBuilding.Kind.STOCKPILE, Vector2i(19, 17), false)
	var names := ["Ari", "Bo", "Cyra", "Dax"]
	var cells := [Vector2i(20, 15), Vector2i(21, 16), Vector2i(22, 17), Vector2i(23, 18)]
	var starting_food := [65.0, 72.0, 79.0, 86.0]
	var starting_rest := [55.0, 70.0, 82.0, 94.0]
	for index in names.size():
		var resident := VaultResident.new()
		resident_root.add_child(resident)
		resident.configure(index + 1, names[index], cells[index], map_grid)
		resident.needs.food = starting_food[index]
		resident.needs.rest = starting_rest[index]
		resident.died.connect(_on_resident_died)
		residents.append(resident)
	power_grid.recalculate(buildings)
	refresh_lighting(true)
	oxygen_system.refresh_rates(residents, buildings, false)
	world_camera.position = map_grid.cell_to_world(map_grid.get_chamber_center())
	world_camera.zoom = Vector2.ONE
	tutorial_open = show_tutorial
	user_paused = true
	status_message = "Wing initialized. Stabilize supplies, oxygen, and the pressure hatch."
	status_message_left = 5.0
	player_orders.show_briefing(show_tutorial, show_tutorial)
	player_orders.show_breach_warning(
		breach_system.phase == BreachSystem.Phase.WARNING and not breach_system.warning_acknowledged
	)
	player_orders.hide_outcome()
	game_started.emit()


func begin_shift() -> void:
	tutorial_open = false
	user_paused = false
	player_orders.show_briefing(false)
	status_message = "Shift running. Dig, furnish, sustain mood and life support, and watch the seal monitor."
	status_message_left = 5.0


func _simulation_step(delta_seconds: float) -> void:
	if ended:
		return
	power_grid.recalculate(buildings)
	refresh_lighting()
	job_system.reconcile_recreation_state()
	for resident in residents:
		if not resident.alive:
			continue
		var resident_cell := resident.get_cell(map_grid)
		var lit := lighting_system.is_cell_lit(resident_cell)
		var assigned_bed := get_building_by_id(resident.bed_id)
		var in_bed := assigned_bed != null and assigned_bed.complete and resident_cell == assigned_bed.cell
		resident.advance_needs(
			delta_seconds / DayCycle.SECONDS_PER_DAY,
			lit,
			in_bed,
			job_system.is_actively_recreating(resident),
			oxygen_system.is_low(),
		)
	var next_elapsed := minf(
		day_cycle.elapsed_seconds + delta_seconds,
		DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE,
	)
	var phase_before_step := breach_system.phase
	var open_boundary := BreachSystem.WARNING_AT_SECONDS + BreachSystem.GRACE_SECONDS
	var opening_at_step_end := (
		phase_before_step == BreachSystem.Phase.WARNING
		and next_elapsed >= open_boundary
	)
	# Give patch work performed during 79.9-80.0 its complete interval before
	# deciding whether the hatch is still unsealed at the opening boundary.
	var breach_elapsed := open_boundary - 0.000001 if opening_at_step_end else next_elapsed
	breach_system.advance(delta_seconds, breach_elapsed)
	# A hatch that reaches the OPEN boundary at the end of this fixed tick only
	# starts venting on the following tick. This preserves the exact 80-second
	# grace boundary while keeping oxygen loss deterministic.
	oxygen_system.advance(
		delta_seconds,
		residents,
		buildings,
		phase_before_step == BreachSystem.Phase.OPEN,
	)
	if get_alive_count() <= 0:
		_finish_loss()
		return
	var warning_paused_this_step := (
		phase_before_step == BreachSystem.Phase.DORMANT
		and breach_system.phase == BreachSystem.Phase.WARNING
		and user_paused
	)
	if warning_paused_this_step:
		day_cycle.advance(delta_seconds)
		return
	job_system.advance(delta_seconds)
	if opening_at_step_end:
		breach_system.advance(0.0, next_elapsed)
	food_system.advance(delta_seconds, buildings)
	power_grid.recalculate(buildings)
	refresh_lighting()
	job_system.reconcile_recreation_state()
	oxygen_system.refresh_rates(residents, buildings, breach_system.is_open())
	day_cycle.advance(delta_seconds)
	if day_cycle.completed and breach_system.is_sealed() and oxygen_system.is_breathable():
		_finish_win()


func step_simulation(seconds: float) -> void:
	var steps := floori(maxf(0.0, seconds) / SIMULATION_TICK)
	for _index in steps:
		_simulation_step(SIMULATION_TICK)


func is_simulation_paused() -> bool:
	return (
		user_paused
		or tutorial_open
		or ended
		or (player_orders != null and player_orders.is_briefing_open())
	)


func toggle_pause() -> void:
	if tutorial_open or ended or player_orders.is_help_open():
		return
	if user_paused and breach_system.phase == BreachSystem.Phase.WARNING and not breach_system.warning_acknowledged:
		acknowledge_breach_warning(true)
		return
	user_paused = not user_paused


func set_speed(speed: int) -> void:
	if player_orders.is_briefing_open():
		return
	simulation_speed = clampi(speed, 1, 3)
	if not tutorial_open and not ended:
		if breach_system.phase == BreachSystem.Phase.WARNING and not breach_system.warning_acknowledged:
			breach_system.warning_acknowledged = true
			player_orders.show_breach_warning(false)
		user_paused = false


func set_tool(tool: String) -> void:
	active_tool = tool if tool in ["select", "dig", "cancel", "bed", "lamp", "generator", "grow", "kitchen", "stockpile", "air", "rec", "medical", "zone"] else "select"
	status_message = _tool_help(active_tool)
	status_message_left = 4.0
	map_grid.preview_tool = active_tool
	map_grid.queue_redraw()


func issue_order(cell: Vector2i) -> bool:
	if ended or tutorial_open or player_orders.is_help_open() or not map_grid.is_inside(cell):
		return false
	if active_tool == "select":
		return _select_at(cell)
	if active_tool == "dig":
		if map_grid.queue_dig(cell):
			job_system.queue_dig(cell)
			status_message = "Excavation queued. A resident with DIG enabled will claim it."
			status_message_left = 3.0
			return true
		if map_grid.is_diggable(cell) and not map_grid.dig_marks.has(cell):
			status_message = "Connect excavation orders to carved floor or an anchored dig chain."
		else:
			status_message = "Dig orders require undesignated rock inside the steel boundary."
		status_message_left = 3.0
		return false
	if active_tool == "zone":
		var painted := map_grid.paint_stockpile(cell)
		status_message = "Stockpile cell painted. Salvage, raw food, and meal haulers prefer reachable zones." if painted else "Zones need empty carved floor; keep fixtures and the hatch clear."
		status_message_left = 3.0
		return painted
	if active_tool == "cancel":
		if map_grid.clear_stockpile(cell):
			status_message = "Stockpile cell cleared. Haulers will choose another destination."
			status_message_left = 3.0
			return true
		if map_grid.cancel_dig(cell):
			status_message = "Excavation order canceled. Any disconnected designations were cleared."
			status_message_left = 2.0
			return true
		var blueprint := get_building_at(cell)
		if blueprint != null and not blueprint.complete:
			return _remove_building(blueprint, blueprint.delivered, "Blueprint canceled; delivered salvage refunded.")
		return false
	if BUILD_KIND_BY_TOOL.has(active_tool):
		return place_blueprint(int(BUILD_KIND_BY_TOOL[active_tool]), cell)
	return false


func place_blueprint(kind: int, cell: Vector2i) -> bool:
	if cell == BreachSystem.HATCH_CELL:
		status_message = "Keep the marked pressure hatch clear for emergency access."
		status_message_left = 3.0
		return false
	if not map_grid.is_walkable(cell):
		status_message = "Carve this tile before placing a fixture."
		status_message_left = 3.0
		return false
	if get_building_at(cell) != null:
		status_message = "That floor tile is already occupied."
		status_message_left = 3.0
		return false
	map_grid.clear_stockpile(cell)
	var building := VaultBuilding.new()
	building_root.add_child(building)
	building.configure(next_building_id, kind as VaultBuilding.Kind, cell)
	next_building_id += 1
	buildings.append(building)
	job_system.queue_building(building)
	status_message = "%s blueprint placed (%d salvage)." % [building.get_display_name(), building.get_cost()]
	status_message_left = 3.0
	return true


func get_building_at(cell: Vector2i) -> VaultBuilding:
	for building in buildings:
		if building.cell == cell:
			return building
	return null


func get_powered_building_count(kind: int) -> int:
	var count := 0
	for building in buildings:
		if building.complete and building.powered and building.kind == kind:
			count += 1
	return count


func refresh_lighting(force := false) -> bool:
	return lighting_system.refresh(buildings, force)


func is_resident_lit(resident: VaultResident) -> bool:
	return (
		resident != null
		and resident.alive
		and lighting_system.is_cell_lit(resident.get_cell(map_grid))
	)


func get_dark_resident_count() -> int:
	var count := 0
	for resident: VaultResident in residents:
		if resident.alive and not is_resident_lit(resident):
			count += 1
	return count


func toggle_lighting_overlay() -> bool:
	var visible := lighting_system.toggle_coverage_overlay()
	status_message = (
		"LIGHT MAP ON: amber cells are lit; shaded floor is dark."
		if visible
		else "LIGHT MAP OFF: darkness remains visible; coverage guides hidden."
	)
	status_message_left = 4.0
	return visible


func toggle_building_enabled(building_id: int) -> bool:
	var building := get_building_by_id(building_id)
	if building == null or not building.complete or (not building.is_power_consumer() and building.kind != VaultBuilding.Kind.MEDICAL_BED):
		return false
	building.manually_disabled = not building.manually_disabled
	if building.kind == VaultBuilding.Kind.MEDICAL_BED and building.manually_disabled:
		for resident: VaultResident in residents:
			if resident.medical_bed_id == building_id:
				job_system.release_resident(resident)
	power_grid.recalculate(buildings)
	refresh_lighting()
	job_system.reconcile_recreation_state()
	oxygen_system.refresh_rates(residents, buildings, breach_system.is_open())
	var state := "disabled" if building.manually_disabled else "enabled"
	status_message = "%s %s. Power grid recalculated." % [building.get_display_name(), state]
	status_message_left = 4.0
	return true


func deconstruct_building(building_id: int) -> bool:
	var building := get_building_by_id(building_id)
	if building == null or not building.complete or building.is_emergency_core:
		return false
	var refund := building.get_deconstruct_refund()
	return _remove_building(
		building,
		refund,
		"%s deconstructed; %d salvage recovered." % [building.get_display_name(), refund],
	)


func get_building_by_id(building_id: int) -> VaultBuilding:
	for building in buildings:
		if building.building_id == building_id:
			return building
	return null


func get_resident_by_id(resident_id: int) -> VaultResident:
	for resident in residents:
		if resident.resident_id == resident_id:
			return resident
	return null


func toggle_resident_draft(resident_id: int) -> bool:
	if tutorial_open or ended or player_orders.is_help_open() or player_orders.is_work_priorities_open():
		return false
	if breach_system.phase == BreachSystem.Phase.WARNING and not breach_system.warning_acknowledged:
		return false
	var resident := get_resident_by_id(resident_id)
	if resident == null or not resident.alive:
		return false
	if resident.drafted:
		resident.drafted = false
		resident.clear_manual_move_order()
		resident.clear_forced_order()
		resident.state = "Idle"
		status_message = "%s undrafted; automatic work and self-care resumed." % resident.resident_name
	else:
		job_system.release_resident(resident)
		resident.drafted = true
		resident.sleeping = false
		resident.bed_id = -1
		resident.recreating = false
		resident.recreation_id = -1
		resident.stress_break_left = 0.0
		resident.state = "Drafted"
		status_message = "%s drafted. Right-click reachable carved floor to move; undraft to resume autonomy." % resident.resident_name
	status_message_left = 4.0
	resident.queue_redraw()
	return resident.drafted


func issue_selected_resident_context_order(cell: Vector2i) -> bool:
	if ended or tutorial_open or player_orders.is_help_open() or player_orders.is_work_priorities_open() or not map_grid.is_inside(cell):
		return false
	var resident := get_resident_by_id(selected_resident_id)
	if resident == null or not resident.alive:
		return false
	if resident.drafted:
		return _issue_drafted_move(resident, cell)
	var result := job_system.force_job_at(resident, cell)
	status_message = str(result.message)
	status_message_left = 4.0
	return bool(result.ok)


func issue_context_order(cell: Vector2i) -> bool:
	return issue_selected_resident_context_order(cell)


func cancel_selected_resident_command() -> bool:
	var resident := get_resident_by_id(selected_resident_id)
	if resident == null or not resident.alive:
		return false
	if not resident.drafted and not resident.is_forced_job and resident.current_job_id < 0:
		status_message = "%s has no manual command to cancel." % resident.resident_name
		status_message_left = 3.0
		return false
	var canceled := false
	if resident.drafted:
		if resident.has_manual_move_order():
			resident.clear_manual_move_order()
			canceled = true
	else:
		canceled = job_system.cancel_manual_command(resident)
	status_message = "%s manual command canceled." % resident.resident_name if canceled else "%s has no manual command to cancel." % resident.resident_name
	status_message_left = 3.0
	return canceled


func select_resident(resident_id: int) -> void:
	selected_resident_id = resident_id
	selected_building_id = -1
	selected_breach = false
	breach_system.queue_redraw()
	for resident in residents:
		resident.selected = resident.resident_id == resident_id
		resident.queue_redraw()


func select_building(building_id: int) -> void:
	selected_building_id = building_id
	selected_resident_id = -1
	selected_breach = false
	breach_system.queue_redraw()
	for resident in residents:
		resident.selected = false
		resident.queue_redraw()


func set_work_priority(resident_id: int, work_type: String, priority: int) -> bool:
	var resident := get_resident_by_id(resident_id)
	if resident == null or not resident.set_work_priority(work_type, priority):
		return false
	if priority == VaultResident.PRIORITY_DISABLED and resident.current_job_id >= 0 and not resident.is_forced_job and not job_system._resident_allows(resident, resident.current_job_type):
		job_system.release_resident(resident)
	status_message = "%s %s priority: %s." % [resident.resident_name, work_type.capitalize(), resident.get_work_priority_label(work_type)]
	status_message_left = 3.0
	return true


func cycle_work_priority(resident_id: int, work_type: String) -> int:
	var resident := get_resident_by_id(resident_id)
	if resident == null or work_type not in VaultResident.WORK_TYPES:
		return -1
	var priority := resident.cycle_work_priority(work_type)
	if priority == VaultResident.PRIORITY_DISABLED and resident.current_job_id >= 0 and not resident.is_forced_job and not job_system._resident_allows(resident, resident.current_job_type):
		job_system.release_resident(resident)
	status_message = "%s %s priority: %s." % [resident.resident_name, work_type.capitalize(), resident.get_work_priority_label(work_type)]
	status_message_left = 3.0
	return priority


func toggle_work(resident_id: int, work_type: String) -> void:
	var resident := get_resident_by_id(resident_id)
	if resident == null or work_type not in VaultResident.WORK_TYPES:
		return
	var priority := (
		VaultResident.PRIORITY_DISABLED
		if resident.get_work_priority(work_type) != VaultResident.PRIORITY_DISABLED
		else VaultResident.DEFAULT_WORK_PRIORITY
	)
	set_work_priority(resident_id, work_type, priority)


func get_alive_count() -> int:
	var alive_count := 0
	for resident in residents:
		if resident.alive:
			alive_count += 1
	return alive_count


func get_completed_building_count(kind: int, exclude_core := false) -> int:
	var count := 0
	for building in buildings:
		if building.complete and building.kind == kind and (not exclude_core or not building.is_emergency_core):
			count += 1
	return count


func save_game(show_message := true, path := SaveLoad.DEFAULT_PATH) -> bool:
	var result := save_load.save_snapshot(create_snapshot(), path)
	if show_message:
		status_message = str(result.message)
		status_message_left = 4.0
	return bool(result.ok)


func load_game(path := SaveLoad.DEFAULT_PATH) -> bool:
	var result := save_load.load_snapshot(path)
	status_message = str(result.message)
	status_message_left = 5.0
	if not bool(result.ok):
		return false
	if not apply_snapshot(result.snapshot):
		status_message = "The save did not contain a valid vault wing."
		return false
	player_orders.show_work_priorities(false)
	tutorial_open = false
	user_paused = true
	player_orders.show_briefing(false)
	if ended:
		player_orders.show_outcome(outcome == "win", get_alive_count())
	else:
		player_orders.hide_outcome()
	return true


func create_snapshot() -> Dictionary:
	var building_data: Array = []
	for building in buildings:
		building_data.append(building.serialize())
	var resident_data: Array = []
	for resident in residents:
		resident_data.append(resident.serialize())
	return {
		"map": map_grid.serialize(),
		"buildings": building_data,
		"residents": resident_data,
		"food": food_system.serialize(),
		"oxygen": oxygen_system.serialize(),
		"day": day_cycle.serialize(),
		"breach": breach_system.serialize(),
		"jobs": job_system.serialize(),
		"next_building_id": next_building_id,
		"camera": [world_camera.position.x, world_camera.position.y, world_camera.zoom.x],
		"ended": ended,
		"outcome": outcome,
	}


func apply_snapshot(snapshot: Dictionary) -> bool:
	if not _is_snapshot_shape_valid(snapshot):
		return false
	if not map_grid.deserialize(snapshot.map):
		return false
	lighting_system.reset()
	for building in buildings:
		building.free()
	for resident in residents:
		resident.free()
	buildings.clear()
	residents.clear()
	for data: Variant in snapshot.buildings:
		if not data is Dictionary:
			continue
		var building := VaultBuilding.new()
		building_root.add_child(building)
		building.deserialize(data)
		buildings.append(building)
	for data: Variant in snapshot.residents:
		if not data is Dictionary:
			continue
		var resident := VaultResident.new()
		resident_root.add_child(resident)
		resident.deserialize(data)
		resident.died.connect(_on_resident_died)
		residents.append(resident)
	if residents.is_empty():
		return false
	food_system.deserialize(snapshot.get("food", {}))
	oxygen_system.deserialize(snapshot.get("oxygen", {}))
	day_cycle.deserialize(snapshot.get("day", {}))
	breach_system.deserialize(snapshot.get("breach", {}), day_cycle.elapsed_seconds)
	next_building_id = int(snapshot.get("next_building_id", 1))
	ended = bool(snapshot.get("ended", false))
	outcome = str(snapshot.get("outcome", ""))
	var camera_data: Array = snapshot.get("camera", [])
	if camera_data.size() >= 3:
		world_camera.position = Vector2(float(camera_data[0]), float(camera_data[1]))
		world_camera.zoom = Vector2.ONE * clampf(float(camera_data[2]), 0.75, 1.8)
	power_grid.reset()
	power_grid.recalculate(buildings)
	refresh_lighting(true)
	job_system.rebuild_from_state(snapshot.get("jobs", {}))
	job_system.restore_manual_orders()
	job_system.reconcile_recreation_state()
	oxygen_system.refresh_rates(residents, buildings, breach_system.is_open())
	selected_resident_id = -1
	selected_building_id = -1
	selected_breach = false
	breach_system.queue_redraw()
	active_tool = "select"
	_simulation_accumulator = 0.0
	player_orders.show_breach_warning(
		breach_system.phase == BreachSystem.Phase.WARNING and not breach_system.warning_acknowledged
	)
	if ended:
		if outcome == "win":
			player_orders.show_outcome(true, get_alive_count())
		else:
			player_orders.show_outcome(false, 0)
	return true


func _is_snapshot_shape_valid(snapshot: Dictionary) -> bool:
	var map_data: Variant = snapshot.get("map")
	var resident_data: Variant = snapshot.get("residents")
	var building_data: Variant = snapshot.get("buildings")
	var day_data: Variant = snapshot.get("day", {})
	var breach_data: Variant = snapshot.get("breach", {})
	var oxygen_data: Variant = snapshot.get("oxygen", {})
	var jobs_data: Variant = snapshot.get("jobs", {})
	if not map_data is Dictionary or not resident_data is Array or not building_data is Array:
		return false
	if not MapGrid.is_stockpile_data_valid(map_data):
		return false
	if not job_system.is_serialized_food_haul_data_valid(jobs_data, map_data):
		return false
	for entry: Array in map_data.get("stockpile_cells", []):
		var zone_cell := Vector2i(int(entry[0]), int(entry[1]))
		if zone_cell == BreachSystem.HATCH_CELL:
			return false
		for fixture: Variant in building_data:
			if fixture is Dictionary and fixture.get("cell") == entry:
				return false
	if snapshot.has("ended") and typeof(snapshot.ended) != TYPE_BOOL:
		return false
	if snapshot.has("outcome") and typeof(snapshot.outcome) != TYPE_STRING:
		return false
	if snapshot.has("breach"):
		if not day_data is Dictionary:
			return false
		if not breach_system.is_serialized_data_valid(breach_data, day_data.get("elapsed_seconds")):
			return false
	if snapshot.has("oxygen") and not oxygen_system.is_serialized_data_valid(oxygen_data):
		return false
	if resident_data.is_empty() or resident_data.size() > 5:
		return false
	var saved_cells: Variant = map_data.get("cells")
	if not saved_cells is Array or saved_cells.size() != MapGrid.WIDTH * MapGrid.HEIGHT:
		return false
	var living_residents := 0
	for entry: Variant in resident_data:
		if not entry is Dictionary or not entry.get("position") is Array or not ResidentNeeds.is_serialized_data_valid(entry.get("needs")):
			return false
		if not VaultResident.is_serialized_work_data_valid(entry):
			return false
		if not _is_serialized_manual_control_semantically_valid(entry, map_data, building_data, jobs_data, breach_data):
			return false
		if entry.position.size() < 2:
			return false
		if entry.has("recreating") and typeof(entry.recreating) != TYPE_BOOL:
			return false
		if entry.has("recreation_id") and not _is_integer_in_range(entry.recreation_id, -1, 2_147_483_647):
			return false
		if entry.has("recreation_sessions") and not _is_integer_in_range(entry.recreation_sessions, 0, 2_147_483_647):
			return false
		if bool(entry.get("recreating", false)):
			if not bool(entry.get("alive", true)) or int(entry.get("recreation_id", -1)) <= 0 or bool(entry.get("sleeping", false)):
				return false
		if bool(entry.get("alive", true)):
			living_residents += 1
	for entry: Variant in building_data:
		if not entry is Dictionary or not entry.get("cell") is Array or entry.cell.size() < 2:
			return false
		if not _is_integer_in_range(entry.get("kind"), VaultBuilding.Kind.BED, VaultBuilding.Kind.MEDICAL_BED):
			return false
		if entry.has("manually_disabled") and typeof(entry.manually_disabled) != TYPE_BOOL:
			return false
	if not job_system.is_serialized_breach_data_valid(jobs_data, breach_data, resident_data):
		return false

	var saved_ended := bool(snapshot.get("ended", false))
	var saved_outcome := str(snapshot.get("outcome", ""))
	if saved_ended != (saved_outcome in ["win", "loss"]):
		return false
	if saved_outcome == "loss" and living_residents > 0:
		return false
	if saved_outcome == "win":
		if living_residents <= 0 or not day_data is Dictionary:
			return false
		var elapsed_value: Variant = day_data.get("elapsed_seconds")
		if typeof(elapsed_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(elapsed_value)):
			return false
		if float(elapsed_value) < DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE:
			return false
		if snapshot.has("breach") and int(breach_data.phase) != BreachSystem.Phase.SEALED:
			return false
		var saved_oxygen := OxygenSystem.STARTING_OXYGEN
		if snapshot.has("oxygen"):
			saved_oxygen = float(oxygen_data.oxygen)
		if saved_oxygen < OxygenSystem.CRITICAL_OXYGEN_THRESHOLD:
			return false
	return true


func _is_serialized_manual_control_semantically_valid(
	resident_data: Dictionary,
	map_data: Dictionary,
	building_data: Array,
	jobs_data: Dictionary,
	breach_data: Variant,
) -> bool:
	var saved_cells: Array = map_data.get("cells", [])
	var destination: Array = resident_data.get("manual_destination", [])
	if destination.size() == 2:
		var destination_cell := Vector2i(int(destination[0]), int(destination[1]))
		if int(saved_cells[destination_cell.y * MapGrid.WIDTH + destination_cell.x]) != MapGrid.Tile.FLOOR:
			return false
	var order: Dictionary = resident_data.get("forced_order", {})
	if order.is_empty():
		return true
	var type := int(order.type)
	var target_data: Array = order.target
	var target := Vector2i(int(target_data[0]), int(target_data[1]))
	var building_id := int(order.building_id)
	match type:
		JobSystem.JobType.DIG:
			return building_id == -1 and _serialized_cell_entry_exists(map_data.get("dig_marks", []), target, 0, 1)
		JobSystem.JobType.HAUL_RUBBLE:
			return building_id == -1 and _serialized_cell_entry_exists(jobs_data.get("rubble", []), target, 0, 1)
		JobSystem.JobType.HAUL_RAW_FOOD:
			return building_id == -1 and _serialized_cell_entry_exists(jobs_data.get("raw_food", []), target, 0, 1)
		JobSystem.JobType.HAUL_MEAL:
			return building_id == -1 and _serialized_cell_entry_exists(jobs_data.get("meals", []), target, 0, 1)
		JobSystem.JobType.SUPPLY_BUILD:
			return building_id > 0 and _serialized_supply_entry_exists(jobs_data.get("supplies", []), building_id, target)
		JobSystem.JobType.BUILD:
			var blueprint := _serialized_building_by_id(building_data, building_id)
			if blueprint.is_empty() or bool(blueprint.get("complete", false)) or blueprint.get("cell", []) != target_data:
				return false
			var kind := int(blueprint.get("kind", -1))
			return int(blueprint.get("delivered", 0)) >= int(VaultBuilding.COSTS.get(kind, 2_147_483_647))
		JobSystem.JobType.COOK:
			var kitchen := _serialized_building_by_id(building_data, building_id)
			return (
				not kitchen.is_empty()
				and bool(kitchen.get("complete", false))
				and int(kitchen.get("kind", -1)) == VaultBuilding.Kind.KITCHEN
				and kitchen.get("cell", []) == target_data
			)
		JobSystem.JobType.SUPPLY_BREACH, JobSystem.JobType.PATCH_BREACH:
			if building_id != -1 or target != BreachSystem.HATCH_CELL or not breach_data is Dictionary:
				return false
			var phase := int(breach_data.get("phase", BreachSystem.Phase.DORMANT))
			var delivered := int(breach_data.get("patch_delivered", 0))
			if phase not in [BreachSystem.Phase.WARNING, BreachSystem.Phase.OPEN]:
				return false
			if type == JobSystem.JobType.SUPPLY_BREACH:
				return delivered < BreachSystem.PATCH_COST and not (jobs_data.get("breach_supply", []) as Array).is_empty()
			return delivered >= BreachSystem.PATCH_COST and not (jobs_data.get("breach_patch", []) as Array).is_empty()
	return false


func _serialized_cell_entry_exists(entries: Variant, target: Vector2i, x_index: int, y_index: int) -> bool:
	if not entries is Array:
		return false
	for entry: Variant in entries:
		if entry is Array and entry.size() > maxi(x_index, y_index):
			if int(entry[x_index]) == target.x and int(entry[y_index]) == target.y:
				return true
	return false


func _serialized_supply_entry_exists(entries: Variant, building_id: int, target: Vector2i) -> bool:
	if not entries is Array:
		return false
	for entry: Variant in entries:
		if (
			entry is Array
			and entry.size() >= 3
			and int(entry[0]) == building_id
			and int(entry[1]) == target.x
			and int(entry[2]) == target.y
		):
			return true
	return false


func _serialized_building_by_id(building_data: Array, building_id: int) -> Dictionary:
	for entry: Variant in building_data:
		if entry is Dictionary and int(entry.get("id", -1)) == building_id:
			return entry
	return {}


func _spawn_starting_fixture(kind: int, cell: Vector2i, core: bool) -> void:
	var building := VaultBuilding.new()
	building_root.add_child(building)
	building.configure(next_building_id, kind as VaultBuilding.Kind, cell, true)
	building.is_emergency_core = core
	building.queue_redraw()
	next_building_id += 1
	buildings.append(building)


func _select_at(cell: Vector2i) -> bool:
	if cell == BreachSystem.HATCH_CELL:
		# Version-one saves could legally contain a fixture here. Preserve and
		# keep that fixture selectable; the dedicated focus control still opens
		# the breach inspector.
		var legacy_hatch_building := get_building_at(cell)
		if legacy_hatch_building != null:
			select_building(legacy_hatch_building.building_id)
			return true
	if cell == BreachSystem.HATCH_CELL and breach_system.phase != BreachSystem.Phase.DORMANT:
		selected_resident_id = -1
		selected_building_id = -1
		selected_breach = true
		for resident in residents:
			resident.selected = false
			resident.queue_redraw()
		breach_system.queue_redraw()
		return true
	var building := get_building_at(cell)
	var residents_at_cell: Array[VaultResident] = []
	for resident: VaultResident in residents:
		if resident.alive and resident.get_cell(map_grid) == cell:
			residents_at_cell.append(resident)
	if not residents_at_cell.is_empty():
		for index in residents_at_cell.size():
			if residents_at_cell[index].resident_id != selected_resident_id:
				continue
			if index + 1 < residents_at_cell.size():
				select_resident(residents_at_cell[index + 1].resident_id)
			elif building != null:
				select_building(building.building_id)
			else:
				select_resident(residents_at_cell[0].resident_id)
			return true
		select_resident(residents_at_cell[0].resident_id)
		return true
	if building != null:
		select_building(building.building_id)
		return true
	selected_resident_id = -1
	selected_building_id = -1
	selected_breach = false
	breach_system.queue_redraw()
	for resident in residents:
		resident.selected = false
		resident.queue_redraw()
	return false


func _issue_drafted_move(resident: VaultResident, cell: Vector2i) -> bool:
	if not map_grid.is_walkable(cell):
		status_message = "%s cannot move there; choose carved floor." % resident.resident_name
		status_message_left = 3.0
		return false
	if map_grid.find_path(resident.get_cell(map_grid), cell).is_empty():
		status_message = "%s cannot reach that floor cell." % resident.resident_name
		status_message_left = 3.0
		return false
	job_system.release_resident(resident)
	resident.drafted = true
	resident.set_manual_move_order(cell)
	status_message = "%s manual move set to %d,%d." % [resident.resident_name, cell.x, cell.y]
	status_message_left = 4.0
	return true


func _input(event: InputEvent) -> void:
	if player_orders != null and player_orders.is_briefing_open():
		if player_orders.is_help_open() and event.is_action_pressed("cancel_order"):
			player_orders.show_briefing(false)
		if event.is_action_pressed("cancel_order") or event.is_action_pressed("pause_game"):
			get_viewport().set_input_as_handled()
			return
	# Space is both the global pause shortcut and Godot's default button accept
	# key. Handle it before GUI focus while this modal is open so it cannot
	# silently change the focused work-priority cell.
	if (
		player_orders != null
		and player_orders.is_work_priorities_open()
		and event.is_action_pressed("pause_game")
	):
		toggle_pause()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if player_orders.is_briefing_open():
		if player_orders.is_help_open() and event.is_action_pressed("cancel_order"):
			player_orders.show_briefing(false)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("work_priorities"):
		player_orders.toggle_work_priorities()
		get_viewport().set_input_as_handled()
		return
	if player_orders.is_work_priorities_open():
		if event.is_action_pressed("cancel_order"):
			player_orders.show_work_priorities(false)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("lighting_overlay"):
		var repeated_key: bool = event is InputEventKey and (event as InputEventKey).echo
		var warning_blocked: bool = (
			breach_system.phase == BreachSystem.Phase.WARNING
			and not breach_system.warning_acknowledged
		)
		if not repeated_key and not tutorial_open and not ended and not warning_blocked:
			toggle_lighting_overlay()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause_game"):
		toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("cancel_order"):
		set_tool("select")
		return
	if event.is_action_pressed("tool_dig"):
		set_tool("dig")
		return
	if event.is_action_pressed("draft_selected"):
		var repeated_draft_key: bool = event is InputEventKey and (event as InputEventKey).echo
		if not repeated_draft_key:
			toggle_resident_draft(selected_resident_id)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: set_speed(1)
			KEY_2: set_speed(2)
			KEY_3: set_speed(3)
			KEY_X: set_tool("cancel")
			KEY_HOME, KEY_F: recenter_camera()
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging_camera = mouse_event.pressed
			return
		if mouse_event.position.x >= get_viewport_rect().size.x - RIGHT_PANEL_WIDTH:
			return
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			world_camera.zoom = Vector2.ONE * minf(1.8, world_camera.zoom.x + 0.12)
			return
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			world_camera.zoom = Vector2.ONE * maxf(0.75, world_camera.zoom.x - 0.12)
			return
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			var selected_resident := get_resident_by_id(selected_resident_id)
			if selected_resident != null and selected_resident.alive:
				issue_selected_resident_context_order(map_grid.world_to_cell(get_global_mouse_position()))
				return
			set_tool("select")
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			issue_order(map_grid.world_to_cell(get_global_mouse_position()))
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging_camera:
			world_camera.position -= motion.relative / world_camera.zoom.x
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and active_tool in ["dig", "cancel", "zone"]:
			if motion.position.x < get_viewport_rect().size.x - RIGHT_PANEL_WIDTH:
				issue_order(map_grid.world_to_cell(get_global_mouse_position()))
		map_grid.hover_cell = map_grid.world_to_cell(get_global_mouse_position())
		map_grid.queue_redraw()


func recenter_camera() -> void:
	var selected := get_resident_by_id(selected_resident_id)
	if selected != null:
		world_camera.position = selected.position
	elif selected_breach:
		world_camera.position = map_grid.cell_to_world(BreachSystem.HATCH_CELL)
	else:
		world_camera.position = map_grid.cell_to_world(map_grid.get_chamber_center())


func focus_breach() -> void:
	selected_resident_id = -1
	selected_building_id = -1
	selected_breach = true
	for resident in residents:
		resident.selected = false
		resident.queue_redraw()
	breach_system.queue_redraw()
	world_camera.position = map_grid.cell_to_world(BreachSystem.HATCH_CELL)


func acknowledge_breach_warning(resume_response: bool) -> void:
	breach_system.warning_acknowledged = true
	player_orders.show_breach_warning(false)
	focus_breach()
	if resume_response and not tutorial_open and not ended:
		user_paused = false


func _update_camera(delta: float) -> void:
	if player_orders != null and (
		player_orders.is_work_priorities_open() or player_orders.is_briefing_open()
	):
		_dragging_camera = false
		return
	var direction := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	world_camera.position += direction * 360.0 * delta / world_camera.zoom.x
	world_camera.position.x = clampf(world_camera.position.x, 300.0, MapGrid.WIDTH * MapGrid.TILE_SIZE - 260.0)
	world_camera.position.y = clampf(world_camera.position.y, 220.0, MapGrid.HEIGHT * MapGrid.TILE_SIZE - 180.0)


func _on_rubble_created(cell: Vector2i, amount: int) -> void:
	job_system.queue_rubble(cell, amount)


func _on_map_topology_changed(_cell: Vector2i) -> void:
	refresh_lighting()


func _on_raw_food_produced(cell: Vector2i, amount: int) -> void:
	job_system.queue_raw_food(cell, amount)


func _on_dig_orders_removed(cells: Array[Vector2i]) -> void:
	for cell in cells:
		job_system.cancel_dig(cell)


func _has_cancelable_blueprint_at(cell: Vector2i) -> bool:
	var building := get_building_at(cell)
	return building != null and not building.complete


func _remove_building(building: VaultBuilding, salvage_refund: int, message: String) -> bool:
	if building == null:
		return false
	food_system.add_salvage(maxi(0, salvage_refund))
	job_system.cancel_building(building.building_id)
	for resident: VaultResident in residents:
		if resident.medical_bed_id == building.building_id:
			job_system.release_resident(resident)
		if resident.bed_id == building.building_id:
			resident.bed_id = -1
			resident.sleeping = false
		if resident.recreation_id == building.building_id:
			job_system.release_resident(resident)
		if resident.current_job_id >= 0:
			var target_job := job_system._find_job(resident.current_job_id)
			if not target_job.is_empty() and int(target_job.get("building_id", -1)) == building.building_id:
				job_system.release_resident(resident)
	if selected_building_id == building.building_id:
		selected_building_id = -1
	buildings.erase(building)
	building.free()
	power_grid.recalculate(buildings)
	refresh_lighting()
	job_system.reconcile_recreation_state()
	oxygen_system.refresh_rates(residents, buildings, breach_system.is_open())
	status_message = message
	status_message_left = 3.0
	return true


func _is_stockpile_floor(cell: Vector2i) -> bool:
	return get_building_at(cell) == null


func _is_reserved_cell(cell: Vector2i) -> bool:
	return cell == BreachSystem.HATCH_CELL


func _on_resident_died(resident: VaultResident) -> void:
	job_system.release_resident(resident)
	user_paused = true
	status_message = "%s has died. The shift has been paused." % resident.resident_name
	status_message_left = 8.0
	if get_alive_count() <= 0:
		_finish_loss()


func _on_day_started(_day: int) -> void:
	if not ended:
		save_game(false)
		if breach_system.is_response_active() or (breach_system.is_sealed() and status_message_left > 0.0):
			return
		status_message = "Cycle checkpoint saved locally."
		status_message_left = 3.0


func _on_power_brownout_started(new_shed_count: int, new_shed_demand: int) -> void:
	var fixture_word := "fixture" if new_shed_count == 1 else "fixtures"
	status_message = "POWER BROWNOUT: shedding %d power across %d %s. Disable or deconstruct optional load, or add capacity." % [
		new_shed_demand,
		new_shed_count,
		fixture_word,
	]
	status_message_left = 8.0


func _on_power_brownout_cleared() -> void:
	status_message = "POWER STABLE: all completed fixtures are served."
	status_message_left = 5.0


func _on_power_allocation_changed() -> void:
	refresh_lighting()


func _on_breach_warning_started() -> void:
	job_system.start_breach_response()
	simulation_speed = 1
	user_paused = true
	active_tool = "select"
	map_grid.preview_tool = active_tool
	focus_breach()
	player_orders.show_breach_warning(true)
	status_message = "PRESSURE WARNING: patch the hatch before it starts venting vault oxygen."
	status_message_left = BreachSystem.GRACE_SECONDS


func _on_breach_opened() -> void:
	player_orders.show_breach_warning(false)
	status_message = "BREACH OPEN: vault oxygen is venting until the hatch is patched."
	status_message_left = 12.0


func _on_breach_sealed() -> void:
	player_orders.show_breach_warning(false)
	status_message = "FIRST BREACH CONTAINED: oxygen loss stopped; verify life support recovery."
	status_message_left = 8.0


func _finish_win() -> void:
	if ended:
		return
	ended = true
	outcome = "win"
	user_paused = true
	save_game(false)
	player_orders.show_outcome(true, get_alive_count())
	game_won.emit(get_alive_count())


func _finish_loss() -> void:
	if ended:
		return
	ended = true
	outcome = "loss"
	user_paused = true
	player_orders.show_outcome(false, 0)
	game_lost.emit()


func _tool_help(tool: String) -> String:
	match tool:
		"select": return "SELECT: inspect a resident or fixture; use HELP to reopen the checklist."
		"zone": return "STOCKPILE: paint drop-offs for salvage, raw food, and meals. CANCEL [X] clears cells; Esc exits. No cost."
		"dig": return "DIG: click or drag connected rock; hauled rubble yields 3 salvage per tile."
		"cancel": return "CANCEL: clear stockpile cells, dig orders, or unfinished blueprints."
		"medical": return "MEDICAL BED: 8 salvage, 8s assembly, no power. Residents at 95 HP or below claim care automatically (+2 HP/s); hatch repair first. Disable to deny care."
		"bed": return "BUNK: residents sleep here automatically (8 salvage)."
		"lamp": return "LUMEN: lights floor within %d tiles while powered; prevents the 30 mood/day darkness penalty (5 salvage, 1 power)." % LightingSystem.LUMEN_RADIUS
		"generator": return "CHARGE NODE: adds 7 power for food and life support (18 salvage)."
		"grow": return "GROW TRAY: produces raw food for Haul delivery when powered (12 salvage, 3 power)."
		"kitchen": return "NUTRIENT STATION: Cook turns %d stored raw into %d meal for Haul delivery (10 salvage, 2 power)." % [FoodSystem.COOK_INPUT, FoodSystem.COOK_OUTPUT]
		"stockpile": return "SALVAGE BAY: fallback destination for salvage and food hauling (4 salvage)."
		"air": return "AIR RECYCLER: restores vault oxygen; build a Charge Node to supply its 3 power (14 salvage)."
		"rec": return "REC CONSOLE: optional one-seat mood recovery; it sheds first in a brownout (8 salvage, 1 power)."
	return ""


func _is_integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number == floorf(number) and number >= minimum and number <= maximum
