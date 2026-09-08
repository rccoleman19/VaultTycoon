class_name LightingSystem
extends Node2D

signal coverage_changed

const LUMEN_RADIUS := 5
const DARKNESS_COLOR := Color(0.015, 0.025, 0.035, 0.66)
const COVERAGE_FILL_COLOR := Color(1.0, 0.78, 0.28, 0.13)
const COVERAGE_EDGE_COLOR := Color(1.0, 0.82, 0.38, 0.48)

var map_grid: MapGrid

var _lit_floor_cells: Dictionary = {}
var _floor_cells: Array[Vector2i] = []
var _completed_lumens: Array[VaultBuilding] = []
var _powered_lumens: Array[VaultBuilding] = []
var _coverage_signature := ""
var _coverage_overlay_visible := false


func setup(grid: MapGrid) -> void:
	map_grid = grid
	reset()


func reset() -> void:
	_lit_floor_cells.clear()
	_floor_cells.clear()
	_completed_lumens.clear()
	_powered_lumens.clear()
	_coverage_signature = ""
	_coverage_overlay_visible = false
	queue_redraw()


func refresh(buildings: Array[VaultBuilding], force := false) -> bool:
	if map_grid == null:
		return false
	var next_signature := _build_coverage_signature(buildings)
	if not force and next_signature == _coverage_signature:
		return false

	_coverage_signature = next_signature
	_lit_floor_cells.clear()
	_floor_cells = map_grid.get_floor_cells()
	_completed_lumens.clear()
	_powered_lumens.clear()
	for building: VaultBuilding in buildings:
		if not is_instance_valid(building) or building.kind != VaultBuilding.Kind.LAMP or not building.complete:
			continue
		_completed_lumens.append(building)
		if building.powered:
			_powered_lumens.append(building)

	for cell: Vector2i in _floor_cells:
		for lumen: VaultBuilding in _powered_lumens:
			if is_cell_in_lumen_range(cell, lumen.cell):
				_lit_floor_cells[cell] = true
				break

	queue_redraw()
	coverage_changed.emit()
	return true


func is_cell_lit(cell: Vector2i) -> bool:
	return _lit_floor_cells.has(cell)


func is_floor_dark(cell: Vector2i) -> bool:
	return map_grid != null and map_grid.is_walkable(cell) and not is_cell_lit(cell)


func get_lit_floor_count() -> int:
	return _lit_floor_cells.size()


func get_dark_floor_count() -> int:
	return maxi(0, _floor_cells.size() - _lit_floor_cells.size())


func get_floor_coverage_percent() -> float:
	if _floor_cells.is_empty():
		return 0.0
	return float(_lit_floor_cells.size()) / float(_floor_cells.size()) * 100.0


func get_powered_lumen_count() -> int:
	return _powered_lumens.size()


func get_completed_lumen_count() -> int:
	return _completed_lumens.size()


func get_lumen_lit_floor_count(lumen: VaultBuilding) -> int:
	if lumen == null or not is_instance_valid(lumen) or lumen.kind != VaultBuilding.Kind.LAMP:
		return 0
	var count := 0
	for cell: Vector2i in _floor_cells:
		if is_cell_in_lumen_range(cell, lumen.cell):
			count += 1
	return count


func set_coverage_overlay_visible(visible: bool) -> bool:
	if _coverage_overlay_visible != visible:
		_coverage_overlay_visible = visible
		queue_redraw()
	return _coverage_overlay_visible


func toggle_coverage_overlay() -> bool:
	return set_coverage_overlay_visible(not _coverage_overlay_visible)


func is_coverage_overlay_visible() -> bool:
	return _coverage_overlay_visible


static func is_cell_in_lumen_range(cell: Vector2i, lumen_cell: Vector2i) -> bool:
	return maxi(absi(cell.x - lumen_cell.x), absi(cell.y - lumen_cell.y)) <= LUMEN_RADIUS


func _build_coverage_signature(buildings: Array[VaultBuilding]) -> String:
	var parts := PackedStringArray([str(map_grid.topology_revision)])
	for building: VaultBuilding in buildings:
		if not is_instance_valid(building) or building.kind != VaultBuilding.Kind.LAMP:
			continue
		parts.append("%d:%d:%d:%s:%s" % [
			building.building_id,
			building.cell.x,
			building.cell.y,
			str(building.complete),
			str(building.powered),
		])
	return "|".join(parts)


func _draw() -> void:
	if map_grid == null:
		return
	var tile_size := float(MapGrid.TILE_SIZE)
	for cell: Vector2i in _floor_cells:
		var rect := Rect2(Vector2(cell * MapGrid.TILE_SIZE), Vector2.ONE * tile_size)
		if not is_cell_lit(cell):
			draw_rect(rect, DARKNESS_COLOR)
		elif _coverage_overlay_visible:
			var inset := rect.grow(-1.5)
			draw_rect(inset, COVERAGE_FILL_COLOR)
			draw_rect(inset, COVERAGE_EDGE_COLOR, false, 1.0)
