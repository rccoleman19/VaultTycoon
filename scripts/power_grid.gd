class_name PowerGrid
extends Node

var supply := 0
var demand := 0
var served := 0


func recalculate(buildings: Array[VaultBuilding]) -> void:
	supply = 0
	demand = 0
	served = 0
	for building in buildings:
		building.powered = false
		if building.complete:
			supply += building.get_power_output()
			demand += building.get_power_demand()
	var consumers: Array[VaultBuilding] = []
	for building in buildings:
		if building.complete and building.get_power_demand() > 0:
			consumers.append(building)
	consumers.sort_custom(_consumer_before)
	var available := supply
	for building in consumers:
		var needed := building.get_power_demand()
		if available >= needed:
			building.powered = true
			available -= needed
			served += needed
		building.queue_redraw()


func is_cell_lit(cell: Vector2i, buildings: Array[VaultBuilding]) -> bool:
	for building in buildings:
		if building.complete and building.kind == VaultBuilding.Kind.LAMP and building.powered:
			if maxi(absi(cell.x - building.cell.x), absi(cell.y - building.cell.y)) <= 5:
				return true
	return false


func get_status_text() -> String:
	if demand > supply:
		return "%d/%d ⚡  OVERLOAD" % [served, supply]
	return "%d/%d ⚡" % [demand, supply]


func _consumer_before(a: VaultBuilding, b: VaultBuilding) -> bool:
	var priorities := {
		VaultBuilding.Kind.LAMP: 0,
		VaultBuilding.Kind.KITCHEN: 1,
		VaultBuilding.Kind.GROW_TRAY: 2,
	}
	var a_priority: int = priorities.get(a.kind, 10)
	var b_priority: int = priorities.get(b.kind, 10)
	if a_priority == b_priority:
		return a.building_id < b.building_id
	return a_priority < b_priority

