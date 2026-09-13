class_name MapGrid
extends Node2D

signal tile_changed(cell: Vector2i)
signal rubble_created(cell: Vector2i, amount: int)
signal dig_orders_removed(cells: Array[Vector2i])

enum Tile { ROCK, FLOOR }

const WIDTH := 50
const HEIGHT := 36
const TILE_SIZE := 24
const CHAMBER := Rect2i(17, 11, 12, 10)

var cells: Array[int] = []
var topology_revision := 0
var stockpile_cells: Dictionary = {}
var stockpile_cell_check := Callable()
var dig_marks: Dictionary = {}
var dig_progress: Dictionary = {}
var hover_cell := Vector2i(-1, -1)
var preview_tool := "select"
var cancel_preview_check := Callable()
var reserved_cell_check := Callable()


func _ready() -> void:
	if cells.is_empty():
		new_wing()


func setup(cancel_check: Callable, reserved_check := Callable(), zone_check := Callable()) -> void:
	cancel_preview_check = cancel_check
	reserved_cell_check = reserved_check
	stockpile_cell_check = zone_check


func new_wing() -> void:
	topology_revision += 1
	cells.clear()
	cells.resize(WIDTH * HEIGHT)
	cells.fill(Tile.ROCK)
	dig_marks.clear()
	dig_progress.clear()
	stockpile_cells.clear()
	for y in range(CHAMBER.position.y, CHAMBER.end.y):
		for x in range(CHAMBER.position.x, CHAMBER.end.x):
			cells[_index(Vector2i(x, y))] = Tile.FLOOR
	queue_redraw()


func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < WIDTH and cell.y < HEIGHT


func is_border(cell: Vector2i) -> bool:
	return cell.x == 0 or cell.y == 0 or cell.x == WIDTH - 1 or cell.y == HEIGHT - 1


func get_tile(cell: Vector2i) -> int:
	if not is_inside(cell):
		return Tile.ROCK
	return cells[_index(cell)]


func is_walkable(cell: Vector2i) -> bool:
	return is_inside(cell) and get_tile(cell) == Tile.FLOOR


func is_diggable(cell: Vector2i) -> bool:
	return is_inside(cell) and not is_border(cell) and get_tile(cell) == Tile.ROCK


func can_queue_dig(cell: Vector2i) -> bool:
	if not is_diggable(cell) or dig_marks.has(cell):
		return false
	return _dig_component_reaches_floor(cell)


func queue_dig(cell: Vector2i) -> bool:
	if not can_queue_dig(cell):
		return false
	dig_marks[cell] = true
	dig_progress[cell] = 0.0
	queue_redraw()
	return true


func cancel_dig(cell: Vector2i) -> bool:
	if not dig_marks.has(cell):
		return false
	var removed: Array[Vector2i] = [cell]
	dig_marks.erase(cell)
	dig_progress.erase(cell)
	removed.append_array(_remove_stranded_dig_marks())
	queue_redraw()
	dig_orders_removed.emit(removed)
	return true


func apply_dig_work(cell: Vector2i, amount: float) -> bool:
	if not dig_marks.has(cell) or not is_diggable(cell):
		return false
	dig_progress[cell] = float(dig_progress.get(cell, 0.0)) + amount
	if float(dig_progress[cell]) < 8.0:
		queue_redraw()
		return false
	cells[_index(cell)] = Tile.FLOOR
	topology_revision += 1
	dig_marks.erase(cell)
	dig_progress.erase(cell)
	tile_changed.emit(cell)
	rubble_created.emit(cell, 3)
	queue_redraw()
	return true


func has_walkable_neighbor(cell: Vector2i) -> bool:
	for neighbor in get_neighbors(cell):
		if is_walkable(neighbor):
			return true
	return false


func is_preview_valid(tool: String, cell: Vector2i) -> bool:
	if not is_inside(cell):
		return false
	if tool == "zone":
		return can_paint_stockpile(cell) and not stockpile_cells.has(cell)
	if tool == "dig":
		return can_queue_dig(cell)
	if tool == "cancel":
		return stockpile_cells.has(cell) or dig_marks.has(cell) or (cancel_preview_check.is_valid() and bool(cancel_preview_check.call(cell)))
	return is_walkable(cell) and not (reserved_cell_check.is_valid() and bool(reserved_cell_check.call(cell)))


func can_paint_stockpile(cell: Vector2i) -> bool:
	return is_walkable(cell) and not (reserved_cell_check.is_valid() and bool(reserved_cell_check.call(cell))) and (not stockpile_cell_check.is_valid() or bool(stockpile_cell_check.call(cell)))


func paint_stockpile(cell: Vector2i) -> bool:
	if not can_paint_stockpile(cell) or stockpile_cells.has(cell):
		return false
	stockpile_cells[cell] = true
	queue_redraw()
	return true


func clear_stockpile(cell: Vector2i) -> bool:
	if not stockpile_cells.erase(cell):
		return false
	queue_redraw()
	return true


# One breadth-first traversal selects the closest reachable zone for any inbound
# cargo. Equal-distance ties follow get_neighbors() order: left, right, up, down.
# Zones remain destination markers rather than per-cell inventories.
func nearest_stockpile(from_cell: Vector2i) -> Vector2i:
	if stockpile_cells.is_empty() or not is_walkable(from_cell):
		return Vector2i(-1, -1)
	var frontier: Array[Vector2i] = [from_cell]
	var visited: Dictionary = {from_cell: true}
	var cursor := 0
	while cursor < frontier.size():
		var cell := frontier[cursor]
		cursor += 1
		if stockpile_cells.has(cell) and can_paint_stockpile(cell):
			return cell
		for neighbor: Vector2i in get_neighbors(cell):
			if is_walkable(neighbor) and not visited.has(neighbor):
				visited[neighbor] = true
				frontier.append(neighbor)
	return Vector2i(-1, -1)


static func is_stockpile_data_valid(data: Dictionary) -> bool:
	var zones: Variant = data.get("stockpile_cells", [])
	var saved_cells: Variant = data.get("cells", [])
	if not zones is Array or zones.size() > WIDTH * HEIGHT or not saved_cells is Array or saved_cells.size() != WIDTH * HEIGHT:
		return false
	var seen := {}
	for entry: Variant in zones:
		if not entry is Array or entry.size() != 2:
			return false
		for value: Variant in entry:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != floorf(float(value)):
				return false
		if entry[0] < 0 or entry[0] >= WIDTH or entry[1] < 0 or entry[1] >= HEIGHT:
			return false
		var cell := Vector2i(int(entry[0]), int(entry[1]))
		if seen.has(cell) or saved_cells[cell.y * WIDTH + cell.x] != Tile.FLOOR:
			return false
		seen[cell] = true
	return true


func nearest_walkable_neighbor(cell: Vector2i, from_cell: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_length := 1_000_000
	for neighbor in get_neighbors(cell):
		if not is_walkable(neighbor):
			continue
		var path := find_path(from_cell, neighbor)
		if not path.is_empty() and path.size() < best_length:
			best = neighbor
			best_length = path.size()
	return best


func find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not is_walkable(from_cell) or not is_walkable(to_cell):
		return empty
	if from_cell == to_cell:
		return [from_cell]
	var frontier: Array[Vector2i] = [from_cell]
	var cursor := 0
	var parents: Dictionary = {from_cell: from_cell}
	while cursor < frontier.size():
		var current := frontier[cursor]
		cursor += 1
		for next_cell in get_neighbors(current):
			if parents.has(next_cell) or not is_walkable(next_cell):
				continue
			parents[next_cell] = current
			if next_cell == to_cell:
				var path: Array[Vector2i] = [to_cell]
				var step := to_cell
				while step != from_cell:
					step = parents[step]
					path.push_front(step)
				return path
			frontier.append(next_cell)
	return empty


func get_neighbors(cell: Vector2i) -> Array[Vector2i]:
	return [cell + Vector2i.LEFT, cell + Vector2i.RIGHT, cell + Vector2i.UP, cell + Vector2i.DOWN]


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell * TILE_SIZE) + Vector2(TILE_SIZE, TILE_SIZE) * 0.5


func world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / TILE_SIZE), floori(world_position.y / TILE_SIZE))


func get_chamber_center() -> Vector2i:
	return CHAMBER.position + CHAMBER.size / 2


func get_floor_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in HEIGHT:
		for x in WIDTH:
			var cell := Vector2i(x, y)
			if is_walkable(cell):
				result.append(cell)
	return result


func serialize() -> Dictionary:
	var marks: Array = []
	for cell: Vector2i in dig_marks:
		marks.append([cell.x, cell.y, float(dig_progress.get(cell, 0.0))])
	marks.sort_custom(func(a: Array, b: Array) -> bool: return a[1] * WIDTH + a[0] < b[1] * WIDTH + b[0])
	var zones: Array = []
	for cell: Vector2i in stockpile_cells:
		zones.append([cell.x, cell.y])
	zones.sort_custom(func(a: Array, b: Array) -> bool: return a[1] * WIDTH + a[0] < b[1] * WIDTH + b[0])
	return {"cells": cells.duplicate(), "dig_marks": marks, "stockpile_cells": zones}


func deserialize(data: Dictionary) -> bool:
	if not is_stockpile_data_valid(data):
		return false
	var loaded_cells: Array = data.get("cells", [])
	if loaded_cells.size() != WIDTH * HEIGHT:
		return false
	cells.clear()
	for value: Variant in loaded_cells:
		cells.append(int(value))
	dig_marks.clear()
	dig_progress.clear()
	for entry: Variant in data.get("dig_marks", []):
		if entry is Array and entry.size() >= 3:
			var cell := Vector2i(int(entry[0]), int(entry[1]))
			if is_diggable(cell):
				dig_marks[cell] = true
				dig_progress[cell] = float(entry[2])
	stockpile_cells.clear()
	for entry: Array in data.get("stockpile_cells", []):
		stockpile_cells[Vector2i(int(entry[0]), int(entry[1]))] = true
	_remove_stranded_dig_marks()
	topology_revision += 1
	queue_redraw()
	return true


func _index(cell: Vector2i) -> int:
	return cell.y * WIDTH + cell.x


func _dig_component_reaches_floor(start: Vector2i) -> bool:
	var frontier: Array[Vector2i] = [start]
	var visited: Dictionary = {start: true}
	var cursor := 0
	while cursor < frontier.size():
		var current := frontier[cursor]
		cursor += 1
		if has_walkable_neighbor(current):
			return true
		for neighbor in get_neighbors(current):
			if not visited.has(neighbor) and dig_marks.has(neighbor):
				visited[neighbor] = true
				frontier.append(neighbor)
	return false


func _remove_stranded_dig_marks() -> Array[Vector2i]:
	var connected: Dictionary = {}
	var frontier: Array[Vector2i] = []
	for cell: Vector2i in dig_marks:
		if has_walkable_neighbor(cell):
			connected[cell] = true
			frontier.append(cell)
	var cursor := 0
	while cursor < frontier.size():
		var current := frontier[cursor]
		cursor += 1
		for neighbor in get_neighbors(current):
			if dig_marks.has(neighbor) and not connected.has(neighbor):
				connected[neighbor] = true
				frontier.append(neighbor)
	var removed: Array[Vector2i] = []
	for cell: Vector2i in dig_marks.keys():
		if connected.has(cell):
			continue
		dig_marks.erase(cell)
		dig_progress.erase(cell)
		removed.append(cell)
	return removed


func _draw() -> void:
	for y in HEIGHT:
		for x in WIDTH:
			var cell := Vector2i(x, y)
			var rect := Rect2(Vector2(cell * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE))
			if get_tile(cell) == Tile.ROCK:
				var variation := float((x * 17 + y * 31) % 9) / 255.0
				var rock_color := Color(0.145 + variation, 0.13 + variation, 0.12 + variation)
				if is_border(cell):
					rock_color = Color("202b32")
				draw_rect(rect, rock_color)
				if (x * 3 + y * 5) % 7 == 0:
					draw_line(rect.position + Vector2(5, 7), rect.position + Vector2(17, 14), Color(0.24, 0.21, 0.18), 1.0)
			else:
				draw_rect(rect, Color("26343c"))
				draw_rect(rect.grow(-2.0), Color("2d414b"))
			draw_rect(rect, Color(0.08, 0.11, 0.13, 0.52), false, 1.0)
	for cell: Vector2i in dig_marks:
		var rect := Rect2(Vector2(cell * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE)).grow(-2.0)
		draw_rect(rect, Color(0.96, 0.65, 0.20, 0.18))
		draw_rect(rect, Color("e8a13b"), false, 2.0)
		draw_line(rect.position + Vector2(4, 4), rect.end - Vector2(4, 4), Color("e8a13b"), 1.5)
		draw_line(Vector2(rect.end.x - 4, rect.position.y + 4), Vector2(rect.position.x + 4, rect.end.y - 4), Color("e8a13b"), 1.5)
	for cell: Vector2i in stockpile_cells:
		var zone_rect := Rect2(Vector2(cell * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE)).grow(-3.0)
		draw_rect(zone_rect, Color(0.3, 0.75, 0.85, 0.20))
		draw_rect(zone_rect, Color("64bdcd"), false, 1.5)
	if is_inside(hover_cell) and preview_tool != "select":
		var hover_rect := Rect2(Vector2(hover_cell * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE)).grow(-1.0)
		var valid := is_preview_valid(preview_tool, hover_cell)
		draw_rect(hover_rect, Color(0.35, 0.9, 0.68, 0.16) if valid else Color(0.95, 0.25, 0.22, 0.16))
		draw_rect(hover_rect, Color("71d6b7") if valid else Color("ef5a54"), false, 2.0)
