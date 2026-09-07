class_name FoodSystem
extends Node

signal inventory_changed

const GROW_SECONDS := 46.0
const GROW_YIELD := 6
const COOK_INPUT := 2
const COOK_OUTPUT := 4

var meals := 10
var raw_food := 6
var salvage := 52


func reset() -> void:
	meals = 10
	raw_food = 6
	salvage = 52
	inventory_changed.emit()


func consume_meal() -> bool:
	if meals <= 0:
		return false
	meals -= 1
	inventory_changed.emit()
	return true


func can_cook() -> bool:
	return raw_food >= COOK_INPUT


func finish_cooking() -> bool:
	if not can_cook():
		return false
	raw_food -= COOK_INPUT
	meals += COOK_OUTPUT
	inventory_changed.emit()
	return true


func add_salvage(amount: int) -> void:
	salvage += amount
	inventory_changed.emit()


func take_salvage(amount: int) -> int:
	var taken := mini(amount, salvage)
	salvage -= taken
	if taken > 0:
		inventory_changed.emit()
	return taken


func advance(delta_seconds: float, buildings: Array[VaultBuilding]) -> void:
	var inventory_was_changed := false
	for building in buildings:
		if not building.complete or building.kind != VaultBuilding.Kind.GROW_TRAY or not building.powered:
			continue
		building.production_progress += delta_seconds
		while building.production_progress >= GROW_SECONDS:
			building.production_progress -= GROW_SECONDS
			raw_food += GROW_YIELD
			inventory_was_changed = true
		building.queue_redraw()
	if inventory_was_changed:
		inventory_changed.emit()


func serialize() -> Dictionary:
	return {"meals": meals, "raw_food": raw_food, "salvage": salvage}


func deserialize(data: Dictionary) -> void:
	meals = maxi(0, int(data.get("meals", 10)))
	raw_food = maxi(0, int(data.get("raw_food", 6)))
	salvage = maxi(0, int(data.get("salvage", 52)))
	inventory_changed.emit()

