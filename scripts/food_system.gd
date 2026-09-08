class_name FoodSystem
extends Node

signal inventory_changed
signal raw_food_produced(source_cell: Vector2i, amount: int)

const GROW_SECONDS := 9.0
const GROW_YIELD := 1
const COOK_INPUT := 1
const COOK_OUTPUT := 1
const STARTING_MEALS := 12
const STARTING_RAW_FOOD := 4
const STARTING_SALVAGE := 48

var meals := STARTING_MEALS
var raw_food := STARTING_RAW_FOOD
var salvage := STARTING_SALVAGE


func reset() -> void:
	meals = STARTING_MEALS
	raw_food = STARTING_RAW_FOOD
	salvage = STARTING_SALVAGE
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
	inventory_changed.emit()
	return true


func add_raw_food(amount: int) -> void:
	if amount <= 0:
		return
	raw_food += amount
	inventory_changed.emit()


func add_meals(amount: int) -> void:
	if amount <= 0:
		return
	meals += amount
	inventory_changed.emit()


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
	for building in buildings:
		if not building.complete or building.kind != VaultBuilding.Kind.GROW_TRAY or not building.powered:
			continue
		building.production_progress += delta_seconds
		while building.production_progress >= GROW_SECONDS:
			building.production_progress -= GROW_SECONDS
			raw_food_produced.emit(building.cell, GROW_YIELD)
		building.queue_redraw()


func serialize() -> Dictionary:
	return {"meals": meals, "raw_food": raw_food, "salvage": salvage}


func deserialize(data: Dictionary) -> void:
	meals = maxi(0, int(data.get("meals", STARTING_MEALS)))
	raw_food = maxi(0, int(data.get("raw_food", STARTING_RAW_FOOD)))
	salvage = maxi(0, int(data.get("salvage", STARTING_SALVAGE)))
	inventory_changed.emit()
