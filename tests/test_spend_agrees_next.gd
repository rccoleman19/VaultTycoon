extends "res://tests/test_runner.gd"

const REPRO_NEXT := "Next: food runway short · YOU place a Nutrient Station · THEY cook"
const NAMED_NEXT := "Next: Ari starving · YOU place a Nutrient Station · THEY cook"


func _run() -> void:
	_run_case("05/4242 at Day 4 cannot spend against the food-runway build", _test_repro)
	_run_case("an affordable urgent named build permits only the same spend nudge", _test_affordable_urgent)
	_run_case("a non-urgent build keeps the old spend nudge unchanged", _test_non_urgent)
	print("SPEND AGREES NEXT TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _test_repro() -> void:
	var game := _spawn_game()
	game.new_game(false, 4242, 5)
	# Isolate the spend/Next agreement from the Cook's auto food step (as if each Cook blueprint was cancelled).
	for kind in VaultGame.COOK_AUTO_CHAIN:
		game.cook_auto_vetoed[kind] = true
	game.begin_shift()
	# Only begin and acknowledge the warning, as in the idle player replay.
	# Keep the Day 4 cache and all ordinary simulation work enabled. At 123.4 s
	# the clock reads Day 4 02:02; no inventories or needs are staged here.
	var warnings := 0
	for _tick in range(1234):
		if game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged:
			game.acknowledge_breach_warning(true)
			warnings += 1
		game._simulation_step(VaultGame.SIMULATION_TICK)
		game.player_orders.refresh()
		if game.ended or game.outcome == "death":
			break
	var orders := game.player_orders
	_assert_approximately(game.day_cycle.elapsed_seconds, 123.4, 0.0001, "real simulation reaches the reported moment")
	_assert_equal(game.day_cycle.current_day, 4, "replay reaches Day 4")
	_assert_equal(warnings, 1, "replay acknowledges the actual breach warning")
	_assert_true(game.breach_system.is_sealed(), "crew patch the hatch through ordinary work")
	_assert_equal(game.get_alive_count(), 4, "all four residents reach the repro")
	_assert_equal(game.food_system.meals, 0, "repro has zero meals")
	_assert_equal(game.food_system.salvage, 26, "repro has 26 salvage")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.KITCHEN), 0, "repro still needs its first kitchen")
	_assert_equal(orders.objective_label.text, REPRO_NEXT, "Next retains the unnamed urgent food-runway advice")
	_assert_nudge_agrees(game, "Nutrient Station", "kitchen")
	_dispose(game)


func _sealed_healthy_game() -> VaultGame:
	var game := _spawn_game()
	game.new_game(false, 4242, 5)
	game.begin_shift()
	game.user_paused = true
	game.breach_system._enter_sealed(true)
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
	game.food_system.meals = 100
	game.food_system.raw_food = 4
	game.food_system.salvage = 26
	return game


func _test_affordable_urgent() -> void:
	var game := _sealed_healthy_game()
	game.food_system.meals = 0
	game.residents[0].needs.food = 19.0
	game.player_orders.refresh()
	_assert_true(game.food_system.salvage >= int(VaultBuilding.COSTS[VaultBuilding.Kind.KITCHEN]), "the requested kitchen is affordable")
	_assert_equal(game.player_orders.objective_label.text, NAMED_NEXT, "constructed urgency names the kitchen and starving resident")
	_assert_nudge_agrees(game, "Nutrient Station", "kitchen")
	# Agreement is already possible when the raw pile selects the same kitchen.
	# Both the named and unnamed urgent prefixes must obey the same UI rule.
	game.food_system.raw_food = 6
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, NAMED_NEXT, "a raw pile preserves the urgent kitchen advice")
	_assert_nudge_agrees(game, "Nutrient Station", "kitchen")
	_dispose(game)


func _test_non_urgent() -> void:
	var game := _sealed_healthy_game()
	game.residents[0].needs.rest = 28.0
	game.player_orders.refresh()
	var orders := game.player_orders
	_assert_equal(orders.objective_label.text, "Next: YOU place bunks · THEY craft", "non-urgent Next names a different build")
	_assert_true(orders.upgrade_offer_button.visible, "the old nudge still shows when Next is not urgent")
	_assert_equal(orders.upgrade_offer_button.text, "Spend 26: build Rec Console", "non-urgent nudge text stays exactly unchanged")
	orders.upgrade_offer_button.pressed.emit()
	_assert_equal(game.active_tool, "rec", "the unchanged nudge still selects its original build tool")
	# Return to urgency in the same HUD, then back, to catch stale urgency state.
	game.food_system.meals = 0
	game.residents[0].needs.food = 19.0
	orders.refresh()
	_assert_equal(orders.objective_label.text, NAMED_NEXT, "food urgency replaces the calm bunk advice")
	_assert_nudge_agrees(game, "Nutrient Station", "kitchen")
	game.food_system.meals = 100
	game.residents[0].needs.food = 100.0
	orders.refresh()
	_assert_equal(orders.objective_label.text, "Next: YOU place bunks · THEY craft", "feeding the crew clears urgent Next")
	_assert_true(orders.upgrade_offer_button.visible, "the old nudge returns as urgency clears")
	_assert_equal(orders.upgrade_offer_button.text, "Spend 26: build Rec Console", "the restored nudge keeps its original wording")
	_dispose(game)


func _assert_nudge_agrees(game: VaultGame, build_name: String, tool: String) -> void:
	var orders := game.player_orders
	var button := orders.upgrade_offer_button
	var expected := "Spend %d: build %s" % [game.food_system.salvage, build_name]
	_assert_true(not button.visible or button.text == expected,
		"spend nudge must agree with [%s] or hide; visible=%s text=[%s]" % [orders.objective_label.text, button.visible, button.text])
	var previous_tool := game.active_tool
	button.pressed.emit()
	_assert_equal(game.active_tool, tool if button.visible else previous_tool, "the offer's click follows the same agreement guard")
