class_name VaultBuilding
extends Node2D

enum Kind { BED, LAMP, GENERATOR, GROW_TRAY, KITCHEN, STOCKPILE, AIR_RECYCLER }

const KIND_NAMES := {
	Kind.BED: "Bunk",
	Kind.LAMP: "Lumen",
	Kind.GENERATOR: "Charge Node",
	Kind.GROW_TRAY: "Grow Tray",
	Kind.KITCHEN: "Nutrient Station",
	Kind.STOCKPILE: "Salvage Bay",
	Kind.AIR_RECYCLER: "Air Recycler",
}
const COSTS := {
	Kind.BED: 8,
	Kind.LAMP: 5,
	Kind.GENERATOR: 18,
	Kind.GROW_TRAY: 12,
	Kind.KITCHEN: 10,
	Kind.STOCKPILE: 4,
	Kind.AIR_RECYCLER: 14,
}
const POWER_DEMAND := {
	Kind.BED: 0,
	Kind.LAMP: 1,
	Kind.GENERATOR: 0,
	Kind.GROW_TRAY: 3,
	Kind.KITCHEN: 2,
	Kind.STOCKPILE: 0,
	Kind.AIR_RECYCLER: 3,
}

var building_id := 0
var kind: Kind = Kind.BED
var cell := Vector2i.ZERO
var complete := false
var delivered := 0
var construction_left := 6.0
var powered := false
var is_emergency_core := false
var production_progress := 0.0
var reserved_by := -1


func configure(new_id: int, new_kind: Kind, new_cell: Vector2i, built := false) -> void:
	building_id = new_id
	kind = new_kind
	cell = new_cell
	position = Vector2(cell * MapGrid.TILE_SIZE) + Vector2.ONE * MapGrid.TILE_SIZE * 0.5
	complete = built
	delivered = get_cost() if built else 0
	construction_left = 0.0 if built else get_build_time()
	queue_redraw()


func get_display_name() -> String:
	if is_emergency_core:
		return "Emergency Core"
	return KIND_NAMES.get(kind, "Fixture")


func get_cost() -> int:
	return int(COSTS.get(kind, 0))


func get_build_time() -> float:
	return 5.0 if kind in [Kind.LAMP, Kind.STOCKPILE] else 8.0


func get_power_demand() -> int:
	if not complete:
		return 0
	return int(POWER_DEMAND.get(kind, 0))


func get_power_output() -> int:
	if not complete or kind != Kind.GENERATOR:
		return 0
	return 2 if is_emergency_core else 7


func needs_supply() -> bool:
	return not complete and delivered < get_cost()


func is_supplied() -> bool:
	return delivered >= get_cost()


func add_delivery(amount: int) -> int:
	var accepted: int = mini(amount, get_cost() - delivered)
	delivered += accepted
	queue_redraw()
	return accepted


func apply_build_work(amount: float) -> bool:
	if complete or not is_supplied():
		return false
	construction_left = maxf(0.0, construction_left - amount)
	if construction_left <= 0.0:
		complete = true
		reserved_by = -1
	queue_redraw()
	return complete


func serialize() -> Dictionary:
	return {
		"id": building_id,
		"kind": int(kind),
		"cell": [cell.x, cell.y],
		"complete": complete,
		"delivered": delivered,
		"construction_left": construction_left,
		"powered": powered,
		"is_emergency_core": is_emergency_core,
		"production_progress": production_progress,
	}


func deserialize(data: Dictionary) -> void:
	var saved_cell: Array = data.get("cell", [0, 0])
	configure(int(data.get("id", 0)), int(data.get("kind", Kind.BED)) as Kind, Vector2i(int(saved_cell[0]), int(saved_cell[1])), bool(data.get("complete", false)))
	delivered = int(data.get("delivered", 0))
	construction_left = float(data.get("construction_left", get_build_time()))
	powered = bool(data.get("powered", false))
	is_emergency_core = bool(data.get("is_emergency_core", false))
	production_progress = float(data.get("production_progress", 0.0))
	queue_redraw()


func _draw() -> void:
	var size := float(MapGrid.TILE_SIZE)
	var rect := Rect2(Vector2(-size * 0.42, -size * 0.42), Vector2.ONE * size * 0.84)
	var base_color := _kind_color()
	if not complete:
		draw_rect(rect, Color(base_color, 0.24))
		draw_rect(rect, Color(base_color, 0.85), false, 2.0)
		var ratio := float(delivered) / maxf(1.0, float(get_cost()))
		draw_rect(Rect2(rect.position + Vector2(2, rect.size.y - 4), Vector2((rect.size.x - 4) * ratio, 2)), base_color)
		return
	draw_rect(rect, Color("17242b"))
	draw_rect(rect, base_color, false, 2.0)
	match kind:
		Kind.BED:
			draw_rect(Rect2(-8, -7, 16, 14), Color("6f91a3"))
			draw_rect(Rect2(-7, -6, 5, 12), Color("d8dde0"))
		Kind.LAMP:
			draw_circle(Vector2.ZERO, 6.0, Color("ffe49a") if powered else Color("665f4c"))
			draw_circle(Vector2.ZERO, 8.0, Color(1.0, 0.88, 0.45, 0.2) if powered else Color.TRANSPARENT)
		Kind.GENERATOR:
			draw_circle(Vector2.ZERO, 7.0, Color("68d7c2"))
			draw_line(Vector2(-5, 0), Vector2(5, 0), Color("102026"), 2.0)
			draw_line(Vector2(0, -5), Vector2(0, 5), Color("102026"), 2.0)
		Kind.GROW_TRAY:
			draw_rect(Rect2(-8, -6, 16, 12), Color("466c55"))
			draw_circle(Vector2(-4, 0), 2.5, Color("8dcc76"))
			draw_circle(Vector2(4, 0), 2.5, Color("8dcc76"))
		Kind.KITCHEN:
			draw_rect(Rect2(-7, -7, 14, 14), Color("b7c3c6"))
			draw_circle(Vector2.ZERO, 4.0, Color("3a555e"))
		Kind.STOCKPILE:
			draw_rect(Rect2(-8, -7, 7, 6), Color("b78b52"))
			draw_rect(Rect2(1, 1, 7, 6), Color("b78b52"))
		Kind.AIR_RECYCLER:
			draw_circle(Vector2.ZERO, 8.0, Color("8fcbd3"))
			draw_circle(Vector2.ZERO, 3.0, Color("24434a"))
			for direction in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
				draw_line(direction * 3.0, direction * 7.0, Color("24434a"), 2.0)
	if get_power_demand() > 0 and not powered:
		draw_line(Vector2(-7, -7), Vector2(7, 7), Color("ef5a54"), 2.0)
		draw_line(Vector2(7, -7), Vector2(-7, 7), Color("ef5a54"), 2.0)


func _kind_color() -> Color:
	match kind:
		Kind.BED: return Color("78a3b8")
		Kind.LAMP: return Color("f0ca68")
		Kind.GENERATOR: return Color("62cdb9")
		Kind.GROW_TRAY: return Color("74b76c")
		Kind.KITCHEN: return Color("d5d9d7")
		Kind.STOCKPILE: return Color("b78b52")
		Kind.AIR_RECYCLER: return Color("8fcbd3")
	return Color.WHITE
