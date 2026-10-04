extends "res://tests/test_runner.gd"

const DIG_NEXT := "Next: YOU mark rock [E] · THEY dig on Dig defaults"
const KITCHEN_NEXT := "Next: YOU place a Nutrient Station · THEY cook"
const POWER_NEXT := "Next: YOU power the Nutrient Station · THEY cook"
const CHARGE_NEXT := "Next: YOU place a Charge Node · THEY power the kitchen"
const CHARGE_HELP := "The grid lacks available power for the Nutrient Station. Place a Charge Node to add 7 power."
const REC_NEXT := "Next: YOU place a Rec Console · THEY recover mood"
const MED_NEXT := "Next: YOU place a Med Bed · THEY treat"
const BUNK_NEXT := "Next: YOU place bunks · THEY craft"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_interrupts_and_priority()
	_test_kitchen_guards()
	_test_enabled_kitchen_shed()
	_test_disabled_kitchens()
	_test_mixed_kitchen_power()
	_test_unfinished_kitchens()
	_test_powered_kitchen()
	_test_existing_charge_node_insufficient()
	_test_medical_availability()
	_test_bunk_shortage()
	_test_living_residents_only()
	print("Survival next tests: %d assertions, %d failures" % [_assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _healthy_game() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
		resident.drafted = false
		resident.sleeping = false
		resident.bed_id = -1
		resident.medical_bed_id = -1
	return game


func _assert_step(game: VaultGame, text: String, tool: String, help: String) -> void:
	var step: Dictionary = game.player_orders._primary_next_step()
	_assert_equal(step["text"], text, "recommendation text")
	_assert_equal(step["tool"], tool, "recommendation highlights the expected tool")
	_assert_equal(step["help"], help, "recommendation help")


func _assert_dig(game: VaultGame, message: String) -> void:
	_assert_equal(game.player_orders._primary_next_step()["text"], DIG_NEXT, message)


func _test_interrupts_and_priority() -> void:
	var game := _healthy_game()
	_assert_dig(game, "healthy day-one crew still get the dig hint, including in darkness")
	var resident: VaultResident = game.residents[0]
	resident.needs.food = 19.0
	game.food_system.meals = 0
	_assert_step(game, KITCHEN_NEXT, "kitchen", "Place and power a Nutrient Station so Cook can turn raw food into meals.")
	resident.needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD
	_assert_equal(game.player_orders._primary_next_step()["text"], KITCHEN_NEXT, "missing kitchen beats missing recreation")
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	kitchen.manually_disabled = true
	_assert_step(game, POWER_NEXT, "select", "Power the Nutrient Station so Cook can run.")
	_assert_equal(game.player_orders._primary_next_step()["text"], POWER_NEXT, "kitchen power beats recreation")
	resident.needs.food = 100.0
	game.food_system.meals = 12
	_assert_step(game, REC_NEXT, "rec", "Place a Rec Console so crew can recover mood.")
	resident.needs.health = 99.0
	_assert_equal(game.player_orders._primary_next_step()["text"], REC_NEXT, "recreation beats medical care")
	resident.needs.mood = 100.0
	_assert_step(game, MED_NEXT, "medical", "Place a Med Bed so the injured can be treated.")
	resident.needs.rest = 28.0
	_assert_equal(game.player_orders._primary_next_step()["text"], MED_NEXT, "medical care beats bunks")
	resident.needs.health = 100.0
	_assert_step(game, BUNK_NEXT, "bed", "Place bunks so tired undrafted crew have a bed.")
	# Refresh the highest-priority recommendation without changing the player's tool.
	resident.needs.food = 19.0
	game.food_system.meals = 0
	game.active_tool = "dig"
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "refresh preserves the active dig tool during a crisis")
	_assert_equal(game.player_orders.objective_label.text, POWER_NEXT, "refresh displays the crisis recommendation")
	_dispose(game)


func _test_kitchen_guards() -> void:
	var game := _healthy_game()
	var resident: VaultResident = game.residents[0]
	game.food_system.meals = 0
	_assert_dig(game, "low meals alone do not interrupt digging")
	resident.needs.food = 20.0
	resident.needs.rest = 15.0
	resident.drafted = true
	_assert_dig(game, "critical food and rest thresholds are strict")
	resident.needs.rest = 14.0
	_assert_equal(game.player_orders._primary_next_step()["text"], KITCHEN_NEXT, "critical rest also triggers kitchen placement")
	game.food_system.meals = game.get_alive_count()
	_assert_dig(game, "meals equal to living count do not trigger a kitchen interrupt")
	game.food_system.meals = 0
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	kitchen.powered = true
	var spare := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(21, 12))
	spare.powered = false
	_assert_true(game.player_orders._primary_next_step()["text"] != POWER_NEXT, "offline spare does not interrupt a powered kitchen")
	_assert_dig(game, "powered kitchen plus offline spare leaves the dig hint")
	_dispose(game)


func _critical_game() -> VaultGame:
	var game := _healthy_game()
	game.residents[0].needs.food = 19.0
	game.food_system.meals = 0
	return game


func _test_enabled_kitchen_shed() -> void:
	var game := _critical_game()
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.power_grid.supply, 2, "Emergency Core supplies two power")
	_assert_equal(game.power_grid.served, 1, "starting Lumen consumes one power")
	_assert_true(game.power_grid.is_building_shed(kitchen.building_id), "enabled kitchen is shed by starter grid")
	_assert_step(game, CHARGE_NEXT, "generator", CHARGE_HELP)
	_dispose(game)


func _test_disabled_kitchens() -> void:
	var game := _critical_game()
	var first := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	var second := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(21, 12))
	first.manually_disabled = true
	second.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, POWER_NEXT, "select", "Power the Nutrient Station so Cook can run.")
	first.manually_disabled = false
	game.power_grid.recalculate(game.buildings)
	_assert_true(game.power_grid.is_building_shed(first.building_id), "reenabled kitchen is shed")
	_assert_step(game, CHARGE_NEXT, "generator", CHARGE_HELP)
	_dispose(game)


func _test_mixed_kitchen_power() -> void:
	var game := _critical_game()
	var disabled := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	var enabled := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(21, 12))
	disabled.manually_disabled = true
	var starting_lumen: VaultBuilding
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.LAMP:
			starting_lumen = building
			starting_lumen.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	_assert_true(enabled.powered, "starter grid powers enabled kitchen with Lumen disabled")
	_assert_true(not disabled.powered, "disabled spare stays unpowered")
	_assert_true(game.player_orders._primary_next_step()["text"] != POWER_NEXT, "powered kitchen skips Select power line")
	_assert_true(game.player_orders._primary_next_step()["text"] != CHARGE_NEXT, "powered kitchen skips Charge Node power line")
	_assert_dig(game, "powered kitchen with disabled spare leaves dig hint")
	starting_lumen.manually_disabled = false
	game.power_grid.recalculate(game.buildings)
	_assert_true(game.power_grid.is_building_shed(enabled.building_id), "Lumen demand sheds enabled kitchen beside disabled spare")
	_assert_step(game, CHARGE_NEXT, "generator", CHARGE_HELP)
	_dispose(game)


func _test_unfinished_kitchens() -> void:
	var game := _critical_game()
	var completed := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	completed.manually_disabled = true
	var unfinished := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(21, 12))
	unfinished.complete = false
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, POWER_NEXT, "select", "Power the Nutrient Station so Cook can run.")
	completed.complete = false
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.KITCHEN), 0, "unfinished kitchens do not count as completed")
	_assert_step(game, KITCHEN_NEXT, "kitchen", "Place and power a Nutrient Station so Cook can turn raw food into meals.")
	_dispose(game)


func _test_powered_kitchen() -> void:
	var game := _critical_game()
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(21, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_true(kitchen.powered, "recalculated grid powers the kitchen")
	_assert_true(game.player_orders._primary_next_step()["text"] != POWER_NEXT, "powered kitchen skips Select power line")
	_assert_true(game.player_orders._primary_next_step()["text"] != CHARGE_NEXT, "powered kitchen skips Charge Node power line")
	_assert_dig(game, "powered kitchen leaves dig hint")
	_dispose(game)


func _test_existing_charge_node_insufficient() -> void:
	var game := _critical_game()
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(21, 12))
	# Three higher-priority Air Recyclers consume all nine available power.
	for index in 3:
		_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(22 + index, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.power_grid.supply, 9, "extra completed Charge Node adds seven power")
	_assert_true(game.power_grid.is_building_shed(kitchen.building_id), "higher-priority demand sheds kitchen despite existing Charge Node")
	_assert_step(game, CHARGE_NEXT, "generator", CHARGE_HELP)
	_dispose(game)


func _test_medical_availability() -> void:
	var game := _healthy_game()
	var resident: VaultResident = game.residents[0]
	resident.needs.health = 99.0
	var bed := _add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(20, 12))
	bed.complete = true
	bed.manually_disabled = false
	bed.reserved_by = -1
	_assert_dig(game, "free usable medical bed avoids the medical interrupt")
	bed.complete = false
	_assert_equal(game.player_orders._primary_next_step()["text"], MED_NEXT, "unfinished medical bed is not usable")
	bed.complete = true
	bed.manually_disabled = true
	_assert_equal(game.player_orders._primary_next_step()["text"], MED_NEXT, "disabled medical bed is not usable")
	bed.manually_disabled = false
	bed.reserved_by = resident.resident_id
	_assert_equal(game.player_orders._primary_next_step()["text"], MED_NEXT, "reserved medical bed is not free")
	resident.medical_bed_id = bed.building_id
	_assert_dig(game, "only injured resident already reserved does not request a med bed")
	game.residents[1].needs.health = 99.0
	_assert_equal(game.player_orders._primary_next_step()["text"], MED_NEXT, "another unreserved injured resident still needs a med bed")
	_dispose(game)


func _test_bunk_shortage() -> void:
	var game := _healthy_game()
	var resident: VaultResident = game.residents[0]
	resident.needs.rest = 28.0
	_assert_equal(game.player_orders._primary_next_step()["text"], BUNK_NEXT, "rest at 28 needs a bunk")
	resident.drafted = true
	_assert_dig(game, "drafted tired residents do not count toward bunk shortage")
	resident.drafted = false
	resident.needs.rest = 29.0
	_assert_dig(game, "rest above 28 does not need a bunk")
	resident.sleeping = true
	_assert_equal(game.player_orders._primary_next_step()["text"], BUNK_NEXT, "sleeping without a bed needs a bunk even above 28 rest")
	resident.sleeping = false
	resident.needs.rest = 28.0
	var bunk := _add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(20, 12))
	_assert_dig(game, "one free completed bunk satisfies one tired resident")
	bunk.complete = false
	_assert_equal(game.player_orders._primary_next_step()["text"], BUNK_NEXT, "unfinished bunk does not count as free")
	bunk.complete = true
	var sleeper: VaultResident = game.residents[1]
	sleeper.sleeping = true
	sleeper.bed_id = bunk.building_id
	_assert_equal(game.player_orders._primary_next_step()["text"], BUNK_NEXT, "occupied bunk is unavailable to another tired resident")
	sleeper.sleeping = false
	game.residents[2].needs.rest = 28.0
	_assert_equal(game.player_orders._primary_next_step()["text"], BUNK_NEXT, "two residents needing bunks outnumber one free bunk")
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(21, 12))
	_assert_dig(game, "free bunks equal to need prevent shortage")
	_dispose(game)


func _test_living_residents_only() -> void:
	var game := _healthy_game()
	var resident: VaultResident = game.residents[0]
	resident.alive = false
	resident.needs.food = 0.0
	resident.needs.rest = 0.0
	resident.needs.mood = 0.0
	resident.needs.health = 0.0
	game.food_system.meals = 0
	_assert_dig(game, "dead residents do not trigger survival interrupts")
	_dispose(game)
