class_name VaultResident
extends Node2D

signal died(resident: VaultResident)

const MOVE_SPEED := 3.4 * MapGrid.TILE_SIZE

var resident_id := 0
var resident_name := "Resident"
var needs := ResidentNeeds.new()
var alive := true
var selected := false
var state := "Idle"
var work_allowed := {"dig": true, "haul": true, "craft": true, "cook": true}

var current_job_id := -1
var current_job_type := -1
var job_phase := ""
var carrying := 0
var work_accumulator := 0.0
var sleeping := false
var bed_id := -1
var recreating := false
var recreation_id := -1
var recreation_sessions := 0
var stress_break_left := 0.0

var _path: Array[Vector2i] = []
var _path_index := 0
var _path_destination := Vector2i(-999, -999)
var _recreation_effect_was_running := false


func configure(new_id: int, new_name: String, spawn_cell: Vector2i, map_grid: MapGrid) -> void:
	resident_id = new_id
	resident_name = new_name
	position = map_grid.cell_to_world(spawn_cell)
	queue_redraw()


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
	needs.advance(day_fraction, lit, sleeping, in_bed, recreation_active, low_oxygen)
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


func clear_job() -> void:
	current_job_id = -1
	current_job_type = -1
	job_phase = ""
	work_accumulator = 0.0
	clear_path()
	if alive and not sleeping and not recreating and stress_break_left <= 0.0:
		state = "Idle"


func begin_recreation(building_id: int) -> void:
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
	died.emit(self)
	recreating = false
	recreation_id = -1
	state = "Deceased"
	modulate = Color(0.42, 0.42, 0.42, 0.8)
	queue_redraw()


func serialize() -> Dictionary:
	return {
		"id": resident_id,
		"name": resident_name,
		"position": [position.x, position.y],
		"needs": needs.serialize(),
		"alive": alive,
		"work_allowed": work_allowed.duplicate(),
		"sleeping": sleeping,
		"bed_id": bed_id,
		"recreating": recreating,
		"recreation_id": recreation_id,
		"recreation_sessions": recreation_sessions,
		"stress_break_left": stress_break_left,
	}


func deserialize(data: Dictionary) -> void:
	resident_id = int(data.get("id", 0))
	resident_name = str(data.get("name", "Resident"))
	var saved_position: Array = data.get("position", [0.0, 0.0])
	position = Vector2(float(saved_position[0]), float(saved_position[1]))
	needs.deserialize(data.get("needs", {}))
	alive = bool(data.get("alive", true))
	var saved_work: Dictionary = data.get("work_allowed", {})
	for key: String in work_allowed:
		work_allowed[key] = bool(saved_work.get(key, true))
	sleeping = bool(data.get("sleeping", false)) and alive
	bed_id = int(data.get("bed_id", -1))
	recreating = bool(data.get("recreating", false)) and alive and not sleeping
	recreation_id = int(data.get("recreation_id", -1)) if recreating else -1
	recreation_sessions = maxi(0, int(data.get("recreation_sessions", 0)))
	stress_break_left = maxf(0.0, float(data.get("stress_break_left", 0.0))) if alive and not recreating else 0.0
	state = (
		"Sleeping" if sleeping
		else ("Seeking recreation" if recreating else ("Idle" if alive else "Deceased"))
	)
	if not alive:
		modulate = Color(0.42, 0.42, 0.42, 0.8)
	clear_job()
	queue_redraw()


func _draw() -> void:
	var body_color := Color("71c7b5") if alive else Color("62696a")
	if selected:
		draw_circle(Vector2.ZERO, 11.0, Color(0.96, 0.77, 0.25, 0.28))
		draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 24, Color("f6c64e"), 2.0)
	draw_circle(Vector2(0, -3), 5.5, body_color)
	draw_rect(Rect2(-6, 2, 12, 7), body_color)
	if carrying > 0:
		draw_rect(Rect2(4, 1, 6, 6), Color("bd8f52"))
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
