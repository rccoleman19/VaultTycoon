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
}

@onready var map_grid: MapGrid = $MapGrid
@onready var building_root: Node2D = $Buildings
@onready var resident_root: Node2D = $Colonists
@onready var job_system: JobSystem = $JobSystem
@onready var power_grid: PowerGrid = $PowerGrid
@onready var food_system: FoodSystem = $FoodSystem
@onready var day_cycle: DayCycle = $DayCycle
@onready var save_load: SaveLoad = $SaveLoad
@onready var world_camera: Camera2D = $Camera2D
@onready var player_orders: PlayerOrders = $PlayerOrders

var buildings: Array[VaultBuilding] = []
var residents: Array[VaultResident] = []
var next_building_id := 1
var active_tool := "select"
var selected_resident_id := -1
var selected_building_id := -1
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
	map_grid.setup(Callable(self, "_has_cancelable_blueprint_at"))
	job_system.setup(self)
	map_grid.rubble_created.connect(_on_rubble_created)
	map_grid.dig_orders_removed.connect(_on_dig_orders_removed)
	day_cycle.day_started.connect(_on_day_started)
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
	player_orders.refresh()


func new_game(show_tutorial := false) -> void:
	for building in buildings:
		building.free()
	for resident in residents:
		resident.free()
	buildings.clear()
	residents.clear()
	next_building_id = 1
	map_grid.new_wing()
	job_system.reset()
	food_system.reset()
	day_cycle.reset()
	ended = false
	outcome = ""
	active_tool = "select"
	selected_resident_id = -1
	selected_building_id = -1
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
	world_camera.position = map_grid.cell_to_world(map_grid.get_chamber_center())
	world_camera.zoom = Vector2.ONE
	tutorial_open = show_tutorial
	user_paused = true
	status_message = "Wing initialized. Stabilize it through seven full days."
	status_message_left = 5.0
	player_orders.show_briefing(show_tutorial)
	player_orders.hide_outcome()
	game_started.emit()


func begin_shift() -> void:
	tutorial_open = false
	user_paused = false
	player_orders.show_briefing(false)
	status_message = "Shift running. Dig, furnish, power, and feed the wing."
	status_message_left = 5.0


func _simulation_step(delta_seconds: float) -> void:
	if ended:
		return
	power_grid.recalculate(buildings)
	for resident in residents:
		if not resident.alive:
			continue
		var resident_cell := resident.get_cell(map_grid)
		var lit := power_grid.is_cell_lit(resident_cell, buildings)
		var assigned_bed := get_building_by_id(resident.bed_id)
		var in_bed := assigned_bed != null and assigned_bed.complete and resident_cell == assigned_bed.cell
		resident.advance_needs(delta_seconds / DayCycle.SECONDS_PER_DAY, lit, in_bed)
	job_system.advance(delta_seconds)
	food_system.advance(delta_seconds, buildings)
	power_grid.recalculate(buildings)
	if get_alive_count() <= 0:
		_finish_loss()
		return
	day_cycle.advance(delta_seconds)
	if day_cycle.completed:
		_finish_win()


func step_simulation(seconds: float) -> void:
	var steps := floori(maxf(0.0, seconds) / SIMULATION_TICK)
	for _index in steps:
		_simulation_step(SIMULATION_TICK)


func is_simulation_paused() -> bool:
	return user_paused or tutorial_open or ended


func toggle_pause() -> void:
	if tutorial_open or ended:
		return
	user_paused = not user_paused


func set_speed(speed: int) -> void:
	simulation_speed = clampi(speed, 1, 3)
	if not tutorial_open and not ended:
		user_paused = false


func set_tool(tool: String) -> void:
	active_tool = tool if tool in ["select", "dig", "cancel", "bed", "lamp", "generator", "grow", "kitchen", "stockpile"] else "select"
	status_message = _tool_help(active_tool)
	status_message_left = 4.0
	map_grid.preview_tool = active_tool
	map_grid.queue_redraw()


func issue_order(cell: Vector2i) -> bool:
	if ended or tutorial_open or not map_grid.is_inside(cell):
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
	if active_tool == "cancel":
		if map_grid.cancel_dig(cell):
			status_message = "Excavation order canceled. Any disconnected designations were cleared."
			status_message_left = 2.0
			return true
		var blueprint := get_building_at(cell)
		if blueprint != null and not blueprint.complete:
			food_system.add_salvage(blueprint.delivered)
			job_system.cancel_building(blueprint.building_id)
			buildings.erase(blueprint)
			blueprint.free()
			status_message = "Blueprint canceled; delivered salvage refunded."
			status_message_left = 3.0
			return true
		return false
	if BUILD_KIND_BY_TOOL.has(active_tool):
		return place_blueprint(int(BUILD_KIND_BY_TOOL[active_tool]), cell)
	return false


func place_blueprint(kind: int, cell: Vector2i) -> bool:
	if not map_grid.is_walkable(cell):
		status_message = "Carve this tile before placing a fixture."
		status_message_left = 3.0
		return false
	if get_building_at(cell) != null:
		status_message = "That floor tile is already occupied."
		status_message_left = 3.0
		return false
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


func select_resident(resident_id: int) -> void:
	selected_resident_id = resident_id
	selected_building_id = -1
	for resident in residents:
		resident.selected = resident.resident_id == resident_id
		resident.queue_redraw()


func select_building(building_id: int) -> void:
	selected_building_id = building_id
	selected_resident_id = -1
	for resident in residents:
		resident.selected = false
		resident.queue_redraw()


func toggle_work(resident_id: int, work_type: String) -> void:
	var resident := get_resident_by_id(resident_id)
	if resident == null or not resident.work_allowed.has(work_type):
		return
	resident.work_allowed[work_type] = not bool(resident.work_allowed[work_type])
	if resident.current_job_id >= 0 and not job_system._resident_allows(resident, resident.current_job_type):
		job_system.release_resident(resident)


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
		"day": day_cycle.serialize(),
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
	day_cycle.deserialize(snapshot.get("day", {}))
	next_building_id = int(snapshot.get("next_building_id", 1))
	ended = bool(snapshot.get("ended", false))
	outcome = str(snapshot.get("outcome", ""))
	var camera_data: Array = snapshot.get("camera", [])
	if camera_data.size() >= 3:
		world_camera.position = Vector2(float(camera_data[0]), float(camera_data[1]))
		world_camera.zoom = Vector2.ONE * clampf(float(camera_data[2]), 0.75, 1.8)
	job_system.rebuild_from_state(snapshot.get("jobs", {}))
	power_grid.recalculate(buildings)
	selected_resident_id = -1
	selected_building_id = -1
	active_tool = "select"
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
	if not map_data is Dictionary or not resident_data is Array or not building_data is Array:
		return false
	if resident_data.is_empty() or resident_data.size() > 5:
		return false
	var saved_cells: Variant = map_data.get("cells")
	if not saved_cells is Array or saved_cells.size() != MapGrid.WIDTH * MapGrid.HEIGHT:
		return false
	for entry: Variant in resident_data:
		if not entry is Dictionary or not entry.get("position") is Array or not entry.get("needs") is Dictionary:
			return false
		if entry.position.size() < 2:
			return false
	for entry: Variant in building_data:
		if not entry is Dictionary or not entry.get("cell") is Array or entry.cell.size() < 2:
			return false
	return true


func _spawn_starting_fixture(kind: int, cell: Vector2i, core: bool) -> void:
	var building := VaultBuilding.new()
	building_root.add_child(building)
	building.configure(next_building_id, kind as VaultBuilding.Kind, cell, true)
	building.is_emergency_core = core
	building.queue_redraw()
	next_building_id += 1
	buildings.append(building)


func _select_at(cell: Vector2i) -> bool:
	for resident in residents:
		if resident.alive and resident.get_cell(map_grid) == cell:
			select_resident(resident.resident_id)
			return true
	var building := get_building_at(cell)
	if building != null:
		select_building(building.building_id)
		return true
	selected_resident_id = -1
	selected_building_id = -1
	for resident in residents:
		resident.selected = false
		resident.queue_redraw()
	return false


func _unhandled_input(event: InputEvent) -> void:
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
			set_tool("select")
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			issue_order(map_grid.world_to_cell(get_global_mouse_position()))
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging_camera:
			world_camera.position -= motion.relative / world_camera.zoom.x
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and active_tool in ["dig", "cancel"]:
			if motion.position.x < get_viewport_rect().size.x - RIGHT_PANEL_WIDTH:
				issue_order(map_grid.world_to_cell(get_global_mouse_position()))
		map_grid.hover_cell = map_grid.world_to_cell(get_global_mouse_position())
		map_grid.queue_redraw()


func recenter_camera() -> void:
	var selected := get_resident_by_id(selected_resident_id)
	world_camera.position = selected.position if selected != null else map_grid.cell_to_world(map_grid.get_chamber_center())


func _update_camera(delta: float) -> void:
	var direction := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	world_camera.position += direction * 360.0 * delta / world_camera.zoom.x
	world_camera.position.x = clampf(world_camera.position.x, 300.0, MapGrid.WIDTH * MapGrid.TILE_SIZE - 260.0)
	world_camera.position.y = clampf(world_camera.position.y, 220.0, MapGrid.HEIGHT * MapGrid.TILE_SIZE - 180.0)


func _on_rubble_created(cell: Vector2i, amount: int) -> void:
	job_system.queue_rubble(cell, amount)


func _on_dig_orders_removed(cells: Array[Vector2i]) -> void:
	for cell in cells:
		job_system.cancel_dig(cell)


func _has_cancelable_blueprint_at(cell: Vector2i) -> bool:
	var building := get_building_at(cell)
	return building != null and not building.complete


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
		status_message = "Cycle checkpoint saved locally."
		status_message_left = 3.0


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
		"select": return "SELECT: inspect a resident or fixture."
		"dig": return "DIG: click or drag across rock to designate excavation."
		"cancel": return "CANCEL: remove dig orders or unfinished blueprints."
		"bed": return "BUNK: place on carved floor (8 salvage)."
		"lamp": return "LUMEN: powered light improves mood (5 salvage, 1 power)."
		"generator": return "CHARGE NODE: adds 7 power (18 salvage)."
		"grow": return "GROW TRAY: produces raw food when powered (12 salvage, 3 power)."
		"kitchen": return "NUTRIENT STATION: cooks %d raw food into %d meal (10 salvage, 2 power)." % [FoodSystem.COOK_INPUT, FoodSystem.COOK_OUTPUT]
		"stockpile": return "SALVAGE BAY: hauling destination (4 salvage)."
	return ""
