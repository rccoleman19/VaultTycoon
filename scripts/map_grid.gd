class_name MapGrid
extends Node2D

signal tile_changed(cell: Vector2i)
signal rubble_created(cell: Vector2i, amount: int)
signal dig_orders_removed(cells: Array[Vector2i])

enum Tile { ROCK, FLOOR }

const WIDTH := 50
const HEIGHT := 36
# TILE_SIZE remains the approximate horizontal center spacing (~legacy square size).
# Pointy-top odd-r offset hex: HEX_SIZE is center-to-vertex so flat-to-flat X == TILE_SIZE.
const TILE_SIZE := 24
const HEX_SIZE := 13.856406460551018  # TILE_SIZE / sqrt(3); flat-to-flat X == TILE_SIZE
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
# Wing-seed slice 2: the seed whose layout this map carries (0 = the legacy, hand-made wing).
var layout_seed := 0
var layout_pocket_count := 0
var vein_cells: Dictionary = {}


func _ready() -> void:
	if cells.is_empty():
		new_wing()


func setup(cancel_check: Callable, reserved_check := Callable(), zone_check := Callable()) -> void:
	cancel_preview_check = cancel_check
	reserved_cell_check = reserved_check
	stockpile_cell_check = zone_check


func new_wing(wing_seed := 0) -> void:
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
	if wing_seed != 0:
		for cell: Vector2i in generate_layout(wing_seed)["pockets"]:
			cells[_index(cell)] = Tile.FLOOR
	apply_layout_seed(wing_seed)
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
	rubble_created.emit(cell, get_dig_yield(cell))
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
# cargo. Equal-distance ties follow get_neighbors() order: W, E, NW, NE, SW, SE.
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
	# Pointy-top odd-r. W-first keeps equal-distance BFS ties left-preferring.
	if cell.y & 1:
		return [
			cell + Vector2i(-1, 0),
			cell + Vector2i(1, 0),
			cell + Vector2i(0, -1),
			cell + Vector2i(1, -1),
			cell + Vector2i(0, 1),
			cell + Vector2i(1, 1),
		]
	return [
		cell + Vector2i(-1, 0),
		cell + Vector2i(1, 0),
		cell + Vector2i(-1, -1),
		cell + Vector2i(0, -1),
		cell + Vector2i(-1, 1),
		cell + Vector2i(0, 1),
	]


## World position of an odd-r offset cell center (pointy-top).
static func offset_cell_to_world(cell: Vector2i) -> Vector2:
	var x := HEX_SIZE * sqrt(3.0) * (float(cell.x) + 0.5 * float(cell.y & 1))
	var y := HEX_SIZE * 1.5 * float(cell.y)
	return Vector2(x, y)


func cell_to_world(cell: Vector2i) -> Vector2:
	return offset_cell_to_world(cell)


func world_to_cell(world_position: Vector2) -> Vector2i:
	var q := (sqrt(3.0) / 3.0 * world_position.x - 1.0 / 3.0 * world_position.y) / HEX_SIZE
	var r := (2.0 / 3.0 * world_position.y) / HEX_SIZE
	return _axial_round_to_oddr(q, r)


## Prefer a walkable hex when a world sample lands on a shared edge / rock seam.
func snap_to_walkable(world_position: Vector2, hint := Vector2i(-1, -1)) -> Vector2i:
	var sampled := world_to_cell(world_position)
	if is_walkable(sampled):
		return sampled
	if is_walkable(hint):
		return hint
	var best := sampled
	var best_dist := INF
	var candidates: Array[Vector2i] = [sampled]
	candidates.append_array(get_neighbors(sampled))
	if is_inside(hint):
		candidates.append(hint)
		candidates.append_array(get_neighbors(hint))
	for candidate: Vector2i in candidates:
		if not is_walkable(candidate):
			continue
		var dist := world_position.distance_squared_to(cell_to_world(candidate))
		if dist < best_dist:
			best_dist = dist
			best = candidate
	return best


static func _axial_round_to_oddr(q: float, r: float) -> Vector2i:
	var s := -q - r
	var rq := roundf(q)
	var rr := roundf(r)
	var rs := roundf(s)
	var q_diff := absf(rq - q)
	var r_diff := absf(rr - r)
	var s_diff := absf(rs - s)
	if q_diff > r_diff and q_diff > s_diff:
		rq = -rr - rs
	elif r_diff > s_diff:
		rr = -rq - rs
	var row := int(rr)
	var col := int(rq + float(row - (row & 1)) / 2.0)
	return Vector2i(col, row)


func hex_polygon(cell: Vector2i, inset := 0.0) -> PackedVector2Array:
	var center := cell_to_world(cell)
	var radius := maxf(0.5, HEX_SIZE - inset)
	var points := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * float(i) - 30.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


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
			var poly := hex_polygon(cell)
			if get_tile(cell) == Tile.ROCK:
				var variation := float((x * 17 + y * 31) % 9) / 255.0
				var rock_color := Color(0.145 + variation, 0.13 + variation, 0.12 + variation)
				if is_border(cell):
					rock_color = Color("202b32")
				draw_colored_polygon(poly, rock_color)
				if (x * 3 + y * 5) % 7 == 0:
					var center := cell_to_world(cell)
					draw_line(center + Vector2(-6, -3), center + Vector2(6, 4), Color(0.24, 0.21, 0.18), 1.0)
			else:
				draw_colored_polygon(poly, Color("26343c"))
				draw_colored_polygon(hex_polygon(cell, 2.0), Color("2d414b"))
			draw_polyline(poly + PackedVector2Array([poly[0]]), Color(0.08, 0.11, 0.13, 0.52), 1.0, true)
	for cell: Vector2i in dig_marks:
		var mark := hex_polygon(cell, 2.0)
		draw_colored_polygon(mark, Color(0.96, 0.65, 0.20, 0.18))
		draw_polyline(mark + PackedVector2Array([mark[0]]), Color("e8a13b"), 2.0, true)
		var center := cell_to_world(cell)
		draw_line(center + Vector2(-5, -5), center + Vector2(5, 5), Color("e8a13b"), 1.5)
		draw_line(center + Vector2(5, -5), center + Vector2(-5, 5), Color("e8a13b"), 1.5)
	for cell: Vector2i in stockpile_cells:
		var zone := hex_polygon(cell, 3.0)
		draw_colored_polygon(zone, Color(0.3, 0.75, 0.85, 0.20))
		draw_polyline(zone + PackedVector2Array([zone[0]]), Color("64bdcd"), 1.5, true)
	if is_inside(hover_cell) and preview_tool != "select":
		var hover := hex_polygon(hover_cell, 1.0)
		var valid := is_preview_valid(preview_tool, hover_cell)
		draw_colored_polygon(hover, Color(0.35, 0.9, 0.68, 0.16) if valid else Color(0.95, 0.25, 0.22, 0.16))
		draw_polyline(hover + PackedVector2Array([hover[0]]), Color("71d6b7") if valid else Color("ef5a54"), 2.0, true)


# Wing-seed slice 2: seeded map layout. A seeded wing opens 2-3 rock pockets: small cleared
# chambers reached by a short corridor off the left, right or bottom chamber wall. Pure function
# of the seed (BreachSystem.seed_hash, salts >= 100), so the same seed always draws the same map.
# The protected opening (the chamber, the border and the twelve rock cells of row y=10 above the
# chamber, plus a two-row buffer) is never touched, so every seed keeps the legacy 12-dig path.
const PROTECTED_ROW_Y := 10
const POCKET_BUFFER_ROWS := Vector2i(8, 10)


static func is_layout_protected(cell: Vector2i) -> bool:
	if cell.x <= 0 or cell.y <= 0 or cell.x >= WIDTH - 1 or cell.y >= HEIGHT - 1:
		return true
	if CHAMBER.has_point(cell):
		return true
	if absi(cell.x - BreachSystem.HATCH_CELL.x) <= 2 and absi(cell.y - BreachSystem.HATCH_CELL.y) <= 1:
		return true
	return cell.y >= POCKET_BUFFER_ROWS.x and cell.y <= POCKET_BUFFER_ROWS.y and cell.x >= CHAMBER.position.x - 2 and cell.x <= CHAMBER.end.x + 1


static func get_protected_dig_path() -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	for x in range(CHAMBER.position.x, CHAMBER.end.x):
		path.append(Vector2i(x, PROTECTED_ROW_Y))
	return path


static func _offset_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var odd := cell.y & 1
	var deltas := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1 + odd, -1), Vector2i(odd, -1), Vector2i(-1 + odd, 1), Vector2i(odd, 1)]
	var result: Array[Vector2i] = []
	for delta: Vector2i in deltas:
		result.append(cell + delta)
	return result


static func generate_layout(wing_seed: int) -> Dictionary:
	var pockets: Array[Vector2i] = []
	if wing_seed == 0:
		return {"pockets": pockets}
	var opened: Dictionary = {}
	var walls := ["left", "right", "bottom"]
	var count := 2 + BreachSystem.seed_hash(wing_seed, 100) % 2
	var first_wall := BreachSystem.seed_hash(wing_seed, 101) % walls.size()
	for index in count:
		var salt := 110 + index * 20
		var wall: String = walls[(first_wall + index) % walls.size()]
		var start: Vector2i
		var step: Vector2i
		match wall:
			"left":
				start = Vector2i(CHAMBER.position.x - 1, CHAMBER.position.y + 1 + BreachSystem.seed_hash(wing_seed, salt) % (CHAMBER.size.y - 2))
				step = Vector2i(-1, 0)
			"right":
				# Rows 14-16 stay clear of the hatch at (28, 15).
				var rows := [12, 13, 17, 18, 19]
				start = Vector2i(CHAMBER.end.x, rows[BreachSystem.seed_hash(wing_seed, salt) % rows.size()])
				step = Vector2i(1, 0)
			_:
				start = Vector2i(CHAMBER.position.x + 1 + BreachSystem.seed_hash(wing_seed, salt) % (CHAMBER.size.x - 2), CHAMBER.end.y)
				step = Vector2i(0, 1)
		var corridor_length := 2 + BreachSystem.seed_hash(wing_seed, salt + 1) % 3
		var cursor := start
		for _step in corridor_length:
			if is_layout_protected(cursor):
				break
			opened[cursor] = true
			cursor += step
		var blob: Array[Vector2i] = []
		if not is_layout_protected(cursor):
			blob.append(cursor)
			opened[cursor] = true
		var size := 3 + BreachSystem.seed_hash(wing_seed, salt + 2) % 4
		var grow := 0
		while not blob.is_empty() and blob.size() < size and grow < 24:
			var candidates: Array[Vector2i] = []
			for cell: Vector2i in blob:
				for neighbor in _offset_neighbors(cell):
					if not opened.has(neighbor) and not is_layout_protected(neighbor) and not candidates.has(neighbor):
						candidates.append(neighbor)
			if candidates.is_empty():
				break
			candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y * WIDTH + a.x < b.y * WIDTH + b.x)
			var pick := candidates[BreachSystem.seed_hash(wing_seed, salt + 3 + grow) % candidates.size()]
			blob.append(pick)
			opened[pick] = true
			grow += 1
	for cell: Vector2i in opened:
		pockets.append(cell)
	pockets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y * WIDTH + a.x < b.y * WIDTH + b.x)
	return {"pockets": pockets, "veins": _generate_veins(wing_seed, opened)}


# Salvage veins: 2-3 short runs (3-5 rock cells) of richer rock that yield VEIN_SALVAGE_YIELD
# rubble when dug instead of 3. Derived from the seed, never saved; a dug vein is simply floor.
# They start beside a pocket or within a few cells of the chamber, never on protected rock.
const VEIN_SALVAGE_YIELD := 6
const VEIN_REACH := 6


static func _generate_veins(wing_seed: int, opened: Dictionary) -> Array[Vector2i]:
	var veins: Dictionary = {}
	var starts: Array[Vector2i] = []
	for y in range(CHAMBER.position.y - VEIN_REACH, CHAMBER.end.y + VEIN_REACH):
		for x in range(CHAMBER.position.x - VEIN_REACH, CHAMBER.end.x + VEIN_REACH):
			var cell := Vector2i(x, y)
			if not is_layout_protected(cell) and not opened.has(cell):
				starts.append(cell)
	var count := 2 + BreachSystem.seed_hash(wing_seed, 200) % 2
	for index in count:
		var salt := 210 + index * 20
		var cursor := starts[BreachSystem.seed_hash(wing_seed, salt) % starts.size()]
		var length := 3 + BreachSystem.seed_hash(wing_seed, salt + 1) % 3
		var placed := 0
		var walk := 0
		while placed < length and walk < 16:
			if not veins.has(cursor):
				veins[cursor] = true
				placed += 1
			var options: Array[Vector2i] = []
			for neighbor in _offset_neighbors(cursor):
				if not is_layout_protected(neighbor) and not opened.has(neighbor) and not veins.has(neighbor):
					options.append(neighbor)
			if options.is_empty():
				break
			cursor = options[BreachSystem.seed_hash(wing_seed, salt + 2 + walk) % options.size()]
			walk += 1
	var result: Array[Vector2i] = []
	for cell: Vector2i in veins:
		result.append(cell)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y * WIDTH + a.x < b.y * WIDTH + b.x)
	return result


# Re-derives the seeded layers after new_wing or a load. The saved cells stay authoritative.
func apply_layout_seed(wing_seed: int) -> void:
	layout_seed = wing_seed
	var layout := generate_layout(wing_seed)
	layout_pocket_count = layout["pockets"].size()
	vein_cells.clear()
	for cell: Vector2i in layout.get("veins", []):
		vein_cells[cell] = true
	topology_revision += 1
	queue_redraw()


# Floor a fresh wing of this layout starts with: the chamber plus any seeded pockets. Excavation
# progress (the 12-dig objective) counts floor beyond this, so pockets never count as digging.
func get_initial_floor_count() -> int:
	return CHAMBER.size.x * CHAMBER.size.y + layout_pocket_count


func is_vein(cell: Vector2i) -> bool:
	return vein_cells.has(cell) and get_tile(cell) == Tile.ROCK


# Rubble a dug cell leaves: veins are tracked by cell, so this holds before and after the dig.
func get_dig_yield(cell: Vector2i) -> int:
	return VEIN_SALVAGE_YIELD if vein_cells.has(cell) else 3
