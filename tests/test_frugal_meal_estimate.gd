extends "res://tests/test_runner.gd"


func _run() -> void:
	_run_case("HUD days reflect one FRUGAL resident in the same crew", _test_displayed_days)
	_run_case("Next food runway warning uses the same crew drain", _test_next_warning)
	_run_case("pending meals and cookable raw keep their existing scopes", _test_pending_and_raw)
	_run_case("dead residents contribute neither drain nor belly food", _test_dead_residents)
	_run_case("estimated consumption matches a simulated day with real eating", _test_simulated_consumption)
	print("FRUGAL MEAL ESTIMATE TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _crew(frugal := true) -> VaultGame:
	var game := _spawn_game()
	# Seed 8 deals FRUGAL, CALM, DIGGER, PATCHER. Only remove FRUGAL for
	# the control, preserving the same residents and all other traits.
	game.new_game(false, 8)
	game.begin_shift()
	game.user_paused = true
	if not frugal:
		game.residents[0].set_trait("")
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
	return game


func _test_displayed_days() -> void:
	for frugal in [false, true]:
		var game := _crew(frugal)
		game.player_orders.refresh()
		_assert_equal(game.player_orders.resource_label.text,
			"MEALS 12 (+0) · %s DAYS  RAW 4 (+0)  SALVAGE 48" % ("3.1" if frugal else "3.0"),
			"12 meals feed this crew at %.2f meals/day" % (3.85 if frugal else 4.0))
		_assert_true("FRUGAL" in game.player_orders.resource_label.tooltip_text,
			"tooltip explains the trait's effect on DAYS")
		game.food_system.meals = 0
		game.player_orders.refresh()
		_assert_true("MEALS 0 (+0) · 0.0 DAYS" in game.player_orders.resource_label.text,
			"empty larder still shows zero days")
		_dispose(game)


func _test_next_warning() -> void:
	for frugal in [false, true]:
		var game := _crew(frugal)
		game.food_system.meals = 7
		game.food_system.salvage = 24
		_assert_true(game.place_blueprint(VaultBuilding.Kind.KITCHEN, Vector2i(28, 11)),
			"real unfinished Nutrient Station sets the food production lead")
		# This fixture's food lead + margin is about 70.07 seconds. Seven
		# meals cover 70 s without FRUGAL, 72.73 s with one FRUGAL resident.
		# Fresh games keep the existing forecast hold out of the comparison.
		game.player_orders.refresh()
		_assert_true("MEALS 7 (+0) · %s DAYS" % ("1.8" if frugal else "1.7") in game.player_orders.resource_label.text,
			"visible DAYS and Next use the same rate at the warning boundary")
		_assert_equal(game.player_orders.objective_label.text,
			"Next: YOU mark rock [E] · THEY dig on Dig defaults" if frugal else
			"Next: food runway short · YOU leave Haul + Craft on · THEY finish the Nutrient Station",
			"visible Next warning changes at seven meals when FRUGAL changes consumption")
		_assert_approximately(game.player_orders._food_runway_seconds(),
			7.0 * 40.0 / (3.85 if frugal else 4.0), 0.0001,
			"Next's runway uses the same per-resident rate as HUD DAYS")
		_dispose(game)


func _test_pending_and_raw() -> void:
	var game := _crew()
	game.food_system.meals = 5
	game.food_system.raw_food = 3
	game.job_system.queue_meals(Vector2i(21, 12), 2)
	game.job_system.queue_raw_food(Vector2i(21, 12), 2)
	game.player_orders.refresh()
	_assert_true("MEALS 5 (+2) · 1.8 DAYS  RAW 3 (+2)" in game.player_orders.resource_label.text,
		"HUD floors seven stored + pending meals / 3.85, excluding raw")
	_assert_approximately(game.player_orders._food_runway_seconds(), 7.0 * 40.0 / 3.85, 0.0001,
		"uncookable raw remains outside the pantry forecast")
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(22, 12))
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(24, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.KITCHEN), 1, "raw is cookable")
	game.player_orders.refresh()
	_assert_true("· 1.8 DAYS" in game.player_orders.resource_label.text, "HUD still excludes raw with a kitchen")
	_assert_approximately(game.player_orders._food_runway_seconds(), 12.0 * 40.0 / 3.85, 0.0001,
		"forecast includes stored + pending raw once with the same FRUGAL rate")
	_dispose(game)


func _test_dead_residents() -> void:
	var game := _crew()
	game.food_system.meals = 5
	game.residents[1].alive = false
	game.residents[2].alive = false
	game.player_orders.refresh()
	_assert_true("· 2.7 DAYS" in game.player_orders.resource_label.text,
		"one FRUGAL and one normal living resident drain 1.85 meals/day")
	_assert_approximately(game.player_orders._food_runway_seconds(), 5.0 * 40.0 / 1.85, 0.0001,
		"dead normal residents do not consume the forecast")
	_assert_approximately(game.player_orders._crew_food_days(), (200.0 / 60.0 + 5.0) / 1.85, 0.0001,
		"dead residents' full bellies do not contribute reserve")
	game.residents[0].alive = false
	game.player_orders.refresh()
	_assert_true("· 5.0 DAYS" in game.player_orders.resource_label.text, "dead FRUGAL grants no discount to the survivor")
	_assert_approximately(game.player_orders._food_runway_seconds(), 200.0, 0.0001, "only the normal survivor drains meals")
	game.residents[3].alive = false
	game.player_orders.refresh()
	_assert_false("DAYS" in game.player_orders.resource_label.text, "no crew hides HUD days")
	_assert_equal(game.player_orders._food_runway_seconds(), INF, "no crew has infinite pantry runway")
	_assert_equal(game.player_orders._crew_food_days(), INF, "no crew has infinite food reserve")
	_dispose(game)


func _belly_food(game: VaultGame) -> float:
	var total := 0.0
	for resident: VaultResident in game.residents:
		if resident.alive:
			total += resident.needs.food
	return total


func _test_simulated_consumption() -> void:
	var game := _crew()
	for resident: VaultResident in game.residents:
		resident.needs.food = 60.0
		for work: String in VaultResident.WORK_TYPES:
			resident.set_work_priority(work, VaultResident.PRIORITY_DISABLED)
	var starting_meals := game.food_system.meals
	var starting_belly := _belly_food(game)
	var pantry_days := game.player_orders._food_runway_seconds() / 40.0
	var reserve_days := game.player_orders._crew_food_days()
	# Full simulation ticks exercise advance_needs -> JobSystem survival ->
	# consume_meal -> eat. Stop before the 45 s hatch interruption; no food
	# production, feast or Annex spending changes stock during this day.
	for _tick in 400:
		game.step_simulation(0.1)
	_assert_approximately(game.day_cycle.elapsed_seconds, 40.0, 0.0001, "one full simulated day elapsed")
	_assert_equal(game.get_alive_count(), 4, "all consumers survived")
	_assert_equal(starting_meals - game.food_system.meals, 4, "each resident really consumed a ration")
	# Include the belly remainder: meals are discrete but drain is continuous.
	var consumed_meals := starting_meals - game.food_system.meals + (starting_belly - _belly_food(game)) / 60.0
	_assert_approximately(consumed_meals, 3.85, 0.0001, "real drain is three normal meals + 0.85 FRUGAL meals/day")
	_assert_approximately(float(starting_meals) / pantry_days, consumed_meals, 0.0001,
		"pantry estimate matches measured ration-equivalent consumption")
	_assert_approximately(reserve_days, (starting_meals + starting_belly / 60.0) / consumed_meals, 0.0001,
		"belly + stored estimate matches the simulated rate")
	_assert_approximately(reserve_days - game.player_orders._crew_food_days(), 1.0, 0.0001,
		"one simulated day spends exactly one estimated day of total food")
	_dispose(game)
