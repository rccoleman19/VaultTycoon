class_name VaultResident
extends Node2D

signal died(resident: VaultResident)

const MOVE_SPEED := 3.4 * MapGrid.TILE_SIZE
const WORK_TYPES: Array[String] = ["dig", "haul", "craft", "cook"]
const PRIORITY_DISABLED := 0
const PRIORITY_HIGHEST := 1
const PRIORITY_LOWEST := 4
const DEFAULT_WORK_PRIORITY := 3
const NO_MANUAL_DESTINATION := Vector2i(-1, -1)
# Public aliases make the numeric contract unambiguous to UI, tests, and future systems.
const PRIORITY_OFF := PRIORITY_DISABLED
const WORK_PRIORITY_OFF := PRIORITY_DISABLED
const MIN_WORK_PRIORITY := PRIORITY_HIGHEST
const MAX_WORK_PRIORITY := PRIORITY_LOWEST

var resident_id := 0
var resident_name := "Resident"
var needs := ResidentNeeds.new()
var alive := true
var selected := false
var state := "Idle"
var work_allowed := {"dig": true, "haul": true, "craft": true, "cook": true}
var work_priorities := {"dig": 3, "haul": 3, "craft": 3, "cook": 3}

var current_job_id := -1
var current_job_type := -1
var job_phase := ""
var carrying := 0
var carrying_kind := ""
var work_accumulator := 0.0
var medical_bed_id := -1
var sleeping := false
var bed_id := -1
var recreating := false
var recreation_id := -1
var recreation_sessions := 0
var stress_break_left := 0.0
var drafted := false
var manual_destination := NO_MANUAL_DESTINATION
var is_forced_job := false
var forced_order: Dictionary = {}

var _path: Array[Vector2i] = []
var _path_index := 0
var _path_destination := Vector2i(-999, -999)
var _recreation_effect_was_running := false


func configure(new_id: int, new_name: String, spawn_cell: Vector2i, map_grid: MapGrid) -> void:
	resident_id = new_id
	resident_name = new_name
	_apply_starting_work_priorities()
	drafted = false
	manual_destination = NO_MANUAL_DESTINATION
	clear_forced_order()
	position = map_grid.cell_to_world(spawn_cell)
	queue_redraw()


func get_work_priority(work_type: String) -> int:
	if not work_allowed.has(work_type) or not bool(work_allowed[work_type]):
		return PRIORITY_DISABLED
	return _get_stored_work_priority(work_type)


func _get_stored_work_priority(work_type: String) -> int:
	var saved_priority: Variant = work_priorities.get(work_type, DEFAULT_WORK_PRIORITY)
	if typeof(saved_priority) not in [TYPE_INT, TYPE_FLOAT]:
		return DEFAULT_WORK_PRIORITY
	var priority := int(saved_priority)
	# A direct legacy `work_allowed = true` write must still re-enable work even
	# when the canonical numeric value was previously OFF.
	return priority if priority >= PRIORITY_HIGHEST and priority <= PRIORITY_LOWEST else DEFAULT_WORK_PRIORITY


func set_work_priority(work_type: String, priority: int) -> bool:
	if work_type not in WORK_TYPES or priority < PRIORITY_DISABLED or priority > PRIORITY_LOWEST:
		return false
	work_priorities[work_type] = priority
	work_allowed[work_type] = priority != PRIORITY_DISABLED
	return true


func cycle_work_priority(work_type: String) -> int:
	if work_type not in WORK_TYPES:
		return -1
	var current := get_work_priority(work_type)
	var next := current + 1 if current >= PRIORITY_HIGHEST and current < PRIORITY_LOWEST else PRIORITY_DISABLED
	if current == PRIORITY_DISABLED:
		next = PRIORITY_HIGHEST
	set_work_priority(work_type, next)
	return next


func get_work_priority_label(work_type: String) -> String:
	var priority := get_work_priority(work_type)
	return "OFF" if priority == PRIORITY_DISABLED else str(priority)


static func is_serialized_work_data_valid(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var saved: Dictionary = data
	if saved.has("work_priorities"):
		var priorities: Variant = saved.work_priorities
		if not priorities is Dictionary or priorities.size() != WORK_TYPES.size():
			return false
		for work_type: String in WORK_TYPES:
			if not priorities.has(work_type) or not _is_serialized_priority(priorities[work_type]):
				return false
	if saved.has("work_allowed"):
		var permissions: Variant = saved.work_allowed
		if not permissions is Dictionary:
			return false
		for work_type: Variant in permissions:
			if work_type not in WORK_TYPES or typeof(permissions[work_type]) != TYPE_BOOL:
				return false
		if saved.has("work_priorities"):
			var priorities: Dictionary = saved.work_priorities
			for work_type: String in WORK_TYPES:
				if permissions.has(work_type) and bool(permissions[work_type]) != (int(priorities[work_type]) != PRIORITY_DISABLED):
					return false
	return is_serialized_manual_order_data_valid(saved)


static func is_serialized_manual_order_data_valid(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var saved: Dictionary = data
	if saved.has("drafted") and typeof(saved.drafted) != TYPE_BOOL:
		return false
	var drafted_value := bool(saved.get("drafted", false))
	var alive_value := bool(saved.get("alive", true))
	var destination: Variant = saved.get("manual_destination", [])
	if not destination is Array or destination.size() not in [0, 2]:
		return false
	if destination.size() == 2:
		if (
			not drafted_value
			or not alive_value
			or not _is_integer_in_range(destination[0], 0, MapGrid.WIDTH - 1)
			or not _is_integer_in_range(destination[1], 0, MapGrid.HEIGHT - 1)
		):
			return false
	var order: Variant = saved.get("forced_order", {})
	if not order is Dictionary:
		return false
	if not order.is_empty():
		if drafted_value or not alive_value or order.size() != 3:
			return false
		# JobSystem currently has nine stable serialized kinds (0 through 8).
		# Keep validation local to avoid a circular class dependency while loading.
		if not order.has("type") or not _is_integer_in_range(order.type, 0, 8):
			return false
		if not order.has("building_id") or not _is_integer_in_range(order.building_id, -1, 2_147_483_647):
			return false
		var target: Variant = order.get("target", [])
		if (
			not target is Array
			or target.size() != 2
			or not _is_integer_in_range(target[0], 0, MapGrid.WIDTH - 1)
			or not _is_integer_in_range(target[1], 0, MapGrid.HEIGHT - 1)
		):
			return false
	if drafted_value and (bool(saved.get("sleeping", false)) or bool(saved.get("recreating", false))):
		return false
	return true


func get_cell(map_grid: MapGrid) -> Vector2i:
	return map_grid.world_to_cell(position)


func advance_needs(
	day_fraction: float,
	lit: bool,
	in_bed: bool,
	recreation_active := false,
	low_oxygen := false,
) -> void:
	if not alive:
		return
	var medical_rest := medical_bed_id >= 0 and state == "Rest-Medical"
	needs.advance(day_fraction, lit, sleeping or medical_rest, in_bed or medical_rest, recreation_active, low_oxygen)
	if needs.health <= 0.0:
		kill()
	queue_redraw()


func apply_damage(amount: float) -> void:
	if not alive or amount <= 0.0:
		return
	needs.health = clampf(needs.health - amount, 0.0, 100.0)
	if needs.health <= 0.0:
		kill()
	queue_redraw()


func get_work_multiplier() -> float:
	var multiplier := 1.0
	if needs.food < 30.0:
		multiplier *= 0.75
	if needs.rest < 25.0:
		multiplier *= 0.65
	if needs.mood < ResidentNeeds.LOW_MOOD_THRESHOLD:
		multiplier *= 0.70
	return maxf(0.35, multiplier)


func move_to(target_cell: Vector2i, map_grid: MapGrid, delta_seconds: float) -> bool:
	if get_cell(map_grid) == target_cell and position.distance_to(map_grid.cell_to_world(target_cell)) < 1.0:
		position = map_grid.cell_to_world(target_cell)
		return true
	if target_cell != _path_destination or _path.is_empty():
		_path_destination = target_cell
		_path = map_grid.find_path(get_cell(map_grid), target_cell)
		_path_index = 1 if _path.size() > 1 else 0
	if _path.is_empty():
		return false
	if _path_index >= _path.size():
		return true
	var target_position := map_grid.cell_to_world(_path[_path_index])
	position = position.move_toward(target_position, MOVE_SPEED * delta_seconds)
	if position.distance_to(target_position) < 0.5:
		position = target_position
		_path_index += 1
	return _path_index >= _path.size()


func clear_path() -> void:
	_path.clear()
	_path_index = 0
	_path_destination = Vector2i(-999, -999)


func has_manual_move_order() -> bool:
	return drafted and manual_destination != NO_MANUAL_DESTINATION


func set_manual_move_order(target_cell: Vector2i) -> void:
	manual_destination = target_cell
	clear_path()
	if alive and drafted:
		state = "Drafted · Moving"
	queue_redraw()


func clear_manual_move_order() -> void:
	manual_destination = NO_MANUAL_DESTINATION
	clear_path()
	if alive and drafted:
		state = "Drafted"
	queue_redraw()


func set_forced_order(job_type: int, target_cell: Vector2i, building_id := -1) -> void:
	is_forced_job = true
	forced_order = {
		"type": job_type,
		"target": [target_cell.x, target_cell.y],
		"building_id": building_id,
	}
	queue_redraw()


func clear_forced_order() -> void:
	is_forced_job = false
	forced_order = {}
	queue_redraw()


func clear_job() -> void:
	current_job_id = -1
	current_job_type = -1
	job_phase = ""
	work_accumulator = 0.0
	clear_forced_order()
	clear_path()
	if alive and not sleeping and not recreating and stress_break_left <= 0.0:
		state = "Drafted" if drafted else "Idle"


func begin_recreation(building_id: int) -> void:
	drafted = false
	manual_destination = NO_MANUAL_DESTINATION
	clear_forced_order()
	recreating = true
	recreation_id = building_id
	sleeping = false
	bed_id = -1
	stress_break_left = 0.0
	state = "Seeking recreation"
	clear_path()
	queue_redraw()


func stop_recreation() -> void:
	recreating = false
	recreation_id = -1
	clear_path()
	if alive and not sleeping and stress_break_left <= 0.0:
		state = "Idle"
	queue_redraw()


func kill() -> void:
	if not alive:
		return
	alive = false
	sleeping = false
	drafted = false
	manual_destination = NO_MANUAL_DESTINATION
	clear_forced_order()
	clear_path()
	died.emit(self)
	recreating = false
	recreation_id = -1
	state = "Deceased"
	modulate = Color(0.42, 0.42, 0.42, 0.8)
	queue_redraw()


func serialize() -> Dictionary:
	var saved_priorities := {}
	var saved_permissions := {}
	for work_type: String in WORK_TYPES:
		var priority := get_work_priority(work_type)
		saved_priorities[work_type] = priority
		saved_permissions[work_type] = priority != PRIORITY_DISABLED
	var saved_manual_destination: Array = []
	if has_manual_move_order():
		saved_manual_destination = [manual_destination.x, manual_destination.y]
	var saved_forced_order: Dictionary = forced_order.duplicate(true) if is_forced_job else {}
	return {
		"id": resident_id,
		"name": resident_name,
		"position": [position.x, position.y],
		"needs": needs.serialize(),
		"alive": alive,
		# Keep the boolean map for schema-one readers while the numeric map carries
		# the Slice 6 ordering information.
		"work_allowed": saved_permissions,
		"work_priorities": saved_priorities,
		"sleeping": sleeping,
		"bed_id": bed_id,
		"recreating": recreating,
		"recreation_id": recreation_id,
		"recreation_sessions": recreation_sessions,
		"stress_break_left": stress_break_left,
		"drafted": drafted,
		"manual_destination": saved_manual_destination,
		"forced_order": saved_forced_order,
	}


func deserialize(data: Dictionary) -> void:
	resident_id = int(data.get("id", 0))
	resident_name = str(data.get("name", "Resident"))
	_apply_starting_work_priorities()
	var saved_position: Array = data.get("position", [0.0, 0.0])
	position = Vector2(float(saved_position[0]), float(saved_position[1]))
	needs.deserialize(data.get("needs", {}))
	alive = bool(data.get("alive", true))
	var saved_work: Variant = data.get("work_allowed", {})
	if data.has("work_priorities") and data.work_priorities is Dictionary:
		var saved_priorities: Dictionary = data.work_priorities
		for work_type: String in WORK_TYPES:
			set_work_priority(work_type, int(saved_priorities.get(work_type, DEFAULT_WORK_PRIORITY)))
	else:
		for work_type: String in WORK_TYPES:
			var legacy_allowed := bool(saved_work.get(work_type, true)) if saved_work is Dictionary else true
			set_work_priority(work_type, DEFAULT_WORK_PRIORITY if legacy_allowed else PRIORITY_DISABLED)
	sleeping = bool(data.get("sleeping", false)) and alive
	bed_id = int(data.get("bed_id", -1))
	recreating = bool(data.get("recreating", false)) and alive and not sleeping
	recreation_id = int(data.get("recreation_id", -1)) if recreating else -1
	recreation_sessions = maxi(0, int(data.get("recreation_sessions", 0)))
	stress_break_left = maxf(0.0, float(data.get("stress_break_left", 0.0))) if alive and not recreating else 0.0
	drafted = bool(data.get("drafted", false)) and alive
	if drafted:
		sleeping = false
		bed_id = -1
		recreating = false
		recreation_id = -1
		stress_break_left = 0.0
	manual_destination = NO_MANUAL_DESTINATION
	var saved_manual_destination: Variant = data.get("manual_destination", [])
	if drafted and saved_manual_destination is Array and saved_manual_destination.size() == 2:
		manual_destination = Vector2i(int(saved_manual_destination[0]), int(saved_manual_destination[1]))
	state = (
		("Drafted · Moving" if has_manual_move_order() else "Drafted") if drafted
		else ("Sleeping" if sleeping
		else ("Seeking recreation" if recreating else ("Idle" if alive else "Deceased")))
	)
	if not alive:
		modulate = Color(0.42, 0.42, 0.42, 0.8)
	clear_job()
	var saved_forced_order: Variant = data.get("forced_order", {})
	if alive and not drafted and saved_forced_order is Dictionary and not saved_forced_order.is_empty():
		is_forced_job = true
		forced_order = saved_forced_order.duplicate(true)
	queue_redraw()


func _apply_starting_work_priorities() -> void:
	for work_type: String in WORK_TYPES:
		set_work_priority(work_type, DEFAULT_WORK_PRIORITY)


static func _is_serialized_priority(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return (
		is_finite(number)
		and number == floorf(number)
		and number >= PRIORITY_DISABLED
		and number <= PRIORITY_LOWEST
	)


static func _is_integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number == floorf(number) and number >= minimum and number <= maximum


func _draw() -> void:
	var body_color := Color("71c7b5") if alive else Color("62696a")
	if selected:
		draw_circle(Vector2.ZERO, 11.0, Color(0.96, 0.77, 0.25, 0.28))
		draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 24, Color("f6c64e"), 2.0)
	if alive and drafted:
		draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 32, Color("efc56b"), 2.0)
		draw_line(Vector2(-8, -9), Vector2(8, -9), Color("efc56b"), 2.0)
	draw_circle(Vector2(0, -3), 5.5, body_color)
	draw_rect(Rect2(-6, 2, 12, 7), body_color)
	if carrying > 0:
		var cargo_color := Color("bd8f52")
		if carrying_kind == "raw_food":
			cargo_color = Color("74b76c")
		elif carrying_kind == "meal":
			cargo_color = Color("efc56b")
		draw_rect(Rect2(4, 1, 6, 6), cargo_color)
	if alive:
		var mood_color := Color("ef5a54") if needs.mood <= ResidentNeeds.BREAK_MOOD_THRESHOLD else (Color("efc56b") if needs.mood < 70.0 else Color("75d4b4"))
		draw_rect(Rect2(-8, 10, 16, 2), Color("17242b"))
		draw_rect(Rect2(-8, 10, 16.0 * needs.mood / 100.0, 2), mood_color)
		if _is_recreation_effect_running():
			var pulse := 0.55 + 0.25 * sin(float(Time.get_ticks_msec()) * 0.008)
			draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 24, Color(0.46, 0.88, 0.76, pulse), 1.5)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-11, -12), resident_name.left(2).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("e8f0ef"))


func _process(_delta: float) -> void:
	var recreation_effect_running := _is_recreation_effect_running()
	if recreation_effect_running or recreation_effect_running != _recreation_effect_was_running:
		queue_redraw()
	_recreation_effect_was_running = recreation_effect_running


func _is_recreation_effect_running() -> bool:
	if not alive or not recreating or state != "Recreating":
		return false
	var game_node := get_parent().get_parent() as VaultGame
	return game_node != null and not game_node.is_simulation_paused()
