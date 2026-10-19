extends "res://tests/test_runner.gd"

# North star slice 5: surplus meals become a feast (+mood) at each keep-running day rollover.


func _run() -> void:
	_run_case("a day rollover with surplus meals holds a feast", _test_feast)
	_run_case("no feast below the threshold, with hungry crew, or before the win", _test_guards)
	_run_case("feasts keep the stock near the threshold", _test_self_limiting)
	_run_case("the feast status fits the command bar", _test_fit)
	print("")
	if _failure_count == 0:
		print("FEAST TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("FEAST TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _running() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	game.day_cycle.deserialize({"elapsed_seconds": 70.0, "current_day": 2, "completed": false})
	game.breach_system.advance(0.0, 70.0)
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.apply_patch_work(100.0)
	game.job_system.rebuild_from_state()
	game.day_cycle.deserialize({"elapsed_seconds": 279.5, "current_day": 7, "completed": false})
	game.oxygen_system.oxygen = 100.0
	game.step_simulation(1.0)
	game.start_keep_running()
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 50.0
		resident.needs.health = 100.0
	return game


# Crosses one keep-running day rollover without the rest of the simulation.
func _rollover(game: VaultGame) -> void:
	game.annex_done = true
	var left := 40.0 - fmod(game.keep_running_seconds, 40.0) + 0.05
	game._advance_keep_running(left)


func _test_feast() -> void:
	var game := _running()
	var alive := game.get_alive_count()
	_assert_equal(game.feast_threshold(), game.annex_reserve + maxi(30, 2 * alive), "threshold = reserve + max(30, 2 per crew)")
	game.food_system.meals = game.feast_threshold()
	_rollover(game)
	_assert_equal(game.food_system.meals, game.feast_threshold() - 2 * alive, "2 meals per living resident")
	for resident: VaultResident in game.residents:
		_assert_approximately(resident.needs.mood, 62.0, 0.5, "+12 mood for %s" % resident.resident_name)
	_assert_equal(game.status_message, VaultGame.FEAST_STATUS % [2 * alive, 12], "status names the feast")
	var meals := game.food_system.meals
	game._advance_keep_running(1.0)
	_assert_equal(game.food_system.meals, meals, "only at the rollover")
	game.residents[0].needs.mood = 95.0
	game.food_system.meals = 200
	_rollover(game)
	_assert_approximately(game.residents[0].needs.mood, 100.0, 0.01, "mood caps at 100")
	_dispose(game)


func _test_guards() -> void:
	var game := _running()
	game.food_system.meals = game.feast_threshold() - 1
	_rollover(game)
	_assert_equal(game.food_system.meals, game.feast_threshold() - 1, "below the threshold: no feast")
	game.food_system.meals = 200
	game.residents[0].needs.food = 20.0
	_rollover(game)
	_assert_equal(game.food_system.meals, 200, "a hungry resident eats first: no feast")
	_assert_false(game._maybe_feast(), "and the direct call agrees")
	_dispose(game)
	game = _spawn_game()
	game.begin_shift()
	game.food_system.meals = 200
	_assert_false(game._maybe_feast(), "never before the win")
	_assert_equal(game.food_system.meals, 200, "pre-win meals untouched")
	_dispose(game)


func _test_self_limiting() -> void:
	var game := _running()
	game.food_system.meals = 300
	for day in 40:
		_rollover(game)
	_assert_true(game.food_system.meals < game.feast_threshold() + 2 * game.get_alive_count(), "a 300-meal pile drains to the threshold band (%d)" % game.food_system.meals)
	_assert_true(game.food_system.meals >= game.feast_threshold() - 2 * game.get_alive_count(), "and not below one feast under it")
	_dispose(game)


func _text_width(control: Control, text: String) -> float:
	return control.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, control.get_theme_font_size("font_size")).x


func _test_fit() -> void:
	var game := _running()
	var orders := game.player_orders
	var select_line := "SELECT // Select a living resident, then [R] to draft/undraft. Right-click: drafted = move; undrafted = force context job."
	var room := _text_width(orders.tool_status, select_line) - _text_width(orders.tool_status, "SELECT // " + VaultGame.FEAST_STATUS % [10, 12])
	_assert_true(room >= 12.0, "feast status is %.0f px shorter than the select help the bar fits" % room)
	_dispose(game)
