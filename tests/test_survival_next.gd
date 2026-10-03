extends "res://tests/test_runner.gd"

const DIG_NEXT := "Next: YOU mark rock [E] · THEY dig on Dig defaults"
const KITCHEN_NEXT := "Next: YOU place a Nutrient Station · THEY cook"
const POWER_NEXT := "Next: YOU power the Nutrient Station · THEY cook"
const REC_NEXT := "Next: YOU place a Rec Console · THEY recover mood"
const MED_NEXT := "Next: YOU place a Med Bed · THEY treat"
const BUNK_NEXT := "Next: YOU place bunks · THEY craft"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_interrupts_and_priority()
	_test_kitchen_guards()
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
	kitchen.powered = false
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
