class_name PowerGrid
extends Node

signal brownout_started(shed_count: int, shed_demand: int)
signal brownout_cleared

var supply := 0
var demand := 0
var served := 0
var shed_demand := 0
var shed_count := 0
var brownout_active := false
var disabled_demand := 0
var powered_consumers: Array[VaultBuilding] = []
var shed_consumers: Array[VaultBuilding] = []
var disabled_consumers: Array[VaultBuilding] = []


func reset() -> void:
	supply = 0
	demand = 0
	served = 0
	shed_demand = 0
	shed_count = 0
	brownout_active = false
	disabled_demand = 0
	powered_consumers.clear()
	shed_consumers.clear()
	disabled_consumers.clear()


func recalculate(buildings: Array[VaultBuilding]) -> void:
	var was_brownout := brownout_active
	var previous_states := {}
	supply = 0
	demand = 0
	served = 0
	shed_demand = 0
	shed_count = 0
	disabled_demand = 0
	powered_consumers.clear()
	shed_consumers.clear()
	disabled_consumers.clear()

	for building in buildings:
		previous_states[building.building_id] = building.powered
		building.powered = false
		if building.complete:
			supply += building.get_power_output()
			if building.is_power_consumer() and building.manually_disabled:
				disabled_demand += building.get_base_power_demand()
				disabled_consumers.append(building)
			else:
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
			powered_consumers.append(building)
		else:
			shed_demand += needed
			shed_count += 1
			shed_consumers.append(building)

	for building in buildings:
		if bool(previous_states.get(building.building_id, false)) != building.powered:
			building.queue_redraw()

	brownout_active = shed_count > 0
	if brownout_active and not was_brownout:
		brownout_started.emit(shed_count, shed_demand)
	elif was_brownout and not brownout_active:
		brownout_cleared.emit()


func is_cell_lit(cell: Vector2i, buildings: Array[VaultBuilding]) -> bool:
	for building in buildings:
		if building.complete and building.kind == VaultBuilding.Kind.LAMP and building.powered:
			if maxi(absi(cell.x - building.cell.x), absi(cell.y - building.cell.y)) <= 5:
				return true
	return false


func get_status_text() -> String:
	if brownout_active:
		return "PWR %d/%d used · %d shed · BROWNOUT" % [served, supply, shed_demand]
	if disabled_demand > 0:
		return "PWR %d/%d used · %d disabled" % [served, supply, disabled_demand]
	return "PWR %d/%d used" % [served, supply]


func is_building_shed(building_id: int) -> bool:
	for building in shed_consumers:
		if building.building_id == building_id:
			return true
	return false


func get_shed_summary() -> String:
	return _consumer_summary(shed_consumers)


func get_disabled_summary() -> String:
	return _consumer_summary(disabled_consumers)


func get_shed_order_text() -> String:
	return "Grow Trays -> Nutrient Stations -> Lumens -> Air Recyclers; newer fixtures shed first within each priority."


func get_shed_order(buildings: Array[VaultBuilding]) -> Array[VaultBuilding]:
	var consumers: Array[VaultBuilding] = []
	for building in buildings:
		if building.complete and building.is_power_consumer() and not building.manually_disabled:
			consumers.append(building)
	consumers.sort_custom(_consumer_after)
	return consumers


func _consumer_summary(consumers: Array[VaultBuilding]) -> String:
	if consumers.is_empty():
		return "None"
	var counts := {}
	for building in consumers:
		var display_name := building.get_display_name()
		counts[display_name] = int(counts.get(display_name, 0)) + 1
	var names: Array[String] = []
	for key: Variant in counts:
		names.append(str(key))
	names.sort()
	var parts: Array[String] = []
	for display_name in names:
		var count := int(counts[display_name])
		parts.append("%s x%d" % [display_name, count] if count > 1 else display_name)
	return ", ".join(parts)


func _consumer_before(a: VaultBuilding, b: VaultBuilding) -> bool:
	if a.get_power_priority() == b.get_power_priority():
		return a.building_id < b.building_id
	return a.get_power_priority() < b.get_power_priority()


func _consumer_after(a: VaultBuilding, b: VaultBuilding) -> bool:
	if a.get_power_priority() == b.get_power_priority():
		return a.building_id > b.building_id
	return a.get_power_priority() > b.get_power_priority()
