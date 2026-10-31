extends "res://tests/test_air_early_warning.gd"

# QA playtest 3 (2026-10-31). 03 s8 at 144.7 s showed "Next: Cyra starving · nothing lands in
# time · keep crew fed where possible" while Air was affordable (spend 14) and the alert read
# BUILD AIR NOW 0:44: Next named a dead end over a fix that still lands. 03 s1234 at 137.7-145.1 s
# and 03 s8 at 203 s showed "<name> starving · YOU place a Rec Console", the name flipping between
# residents on a step that feeds nobody. Now a hopeless food rescue yields Next to the reachable
# Air step and starving stays on the alert line; the "<name> starving" prefix rides only on a
# food action. Assertions read Next and the alert list.

const HOPELESS := "nothing lands in time"


func _run() -> void:
	_run_case("hopeless food + live air warning: Next names Air, STARVING moves to the alert", _test_air_over_hopeless_food)
	_run_case("hopeless food with no other reachable step still says so", _test_hopeless_alone)
	_run_case("a Rec Console step for a food crisis carries no starving name", _test_rec_unnamed)
	_run_case("a food action for the same crisis keeps the starving name", _test_food_action_named)
	print("")
	if _failure_count == 0:
		print("NEXT NO HOPELESS FOOD TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("NEXT NO HOPELESS FOOD TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
			_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _starve_first(game: VaultGame) -> VaultResident:
	# A powered kitchen with nothing to cook: no food fix can land in the runway.
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(20, 12))
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(21, 12))
	game.power_grid.recalculate(game.buildings)
	game.food_system.meals = 0
	game.food_system.raw_food = 0
	for resident: VaultResident in game.residents:
		resident.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
	var resident: VaultResident = game.residents[0]
	resident.needs.food = 0.0
	resident.needs.health = 20.0
	return resident


func _test_air_over_hopeless_food() -> void:
	var game := _game(30, true)
	var cyra := _starve_first(game)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.oxygen_system.oxygen = OxygenSystem.LOW_OXYGEN_THRESHOLD + (-game.oxygen_system.net_rate) * 40.0
	game.player_orders.refresh()
	var chain: Dictionary = game.player_orders._primary_next_step_chain({})
	_assert_true(HOPELESS in str(chain.get("text", "")), "the fixture's food rescue cannot land (%s)" % chain.get("text", ""))
	_assert_true(not _early_alert(game).is_empty() or _has_alert(game, "OXYGEN LOW"), "the air warning is live")
	var next := _next(game)
	_assert_true(not HOPELESS in next, "Next does not show the dead end: %s" % next)
	_assert_true("Air Recycler" in next, "Next names the reachable Air step: %s" % next)
	_assert_true(not "starving" in next, "the Air step carries no starving name: %s" % next)
	_assert_true(_has_alert(game, "STARVING: " + cyra.resident_name), "%s's starvation moves to the alert line: %s" % [cyra.resident_name, str(game.player_orders.all_alerts)])
	_dispose(game)


func _test_hopeless_alone() -> void:
	var game := _game(30, false)
	_starve_first(game)
	game.player_orders.refresh()
	_assert_true(HOPELESS in _next(game), "with nothing else reachable Next still names the missed runway: %s" % _next(game))
	_dispose(game)


func _break_crisis() -> VaultGame:
	var game := _game(30, false)
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(20, 12))
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(21, 12))
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.health = 100.0
		resident.needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD
	game.food_system.meals = 0
	game.food_system.raw_food = 1
	game.residents[0].needs.food = 0.0
	return game


func _test_rec_unnamed() -> void:
	var game := _break_crisis()
	var ari: VaultResident = game.residents[0]
	game.player_orders.refresh()
	var next := _next(game)
	_assert_equal(next, "Next: YOU place a Rec Console · THEY recover mood", "the Rec step names no starving resident")
	_assert_true(_has_alert(game, "STARVING: " + ari.resident_name), "starving stays on the alert line: %s" % str(game.player_orders.all_alerts))
	# A second resident starving harder does not put a name on the Rec step either.
	var bo: VaultResident = game.residents[1]
	bo.needs.food = 0.0
	bo.needs.health = 5.0
	game.step_simulation(5.0)
	game.player_orders.refresh()
	_assert_true(not "starving" in _next(game), "no name appears on the Rec step later: %s" % _next(game))
	_dispose(game)


func _test_food_action_named() -> void:
	var game := _break_crisis()
	for resident: VaultResident in game.residents:
		resident.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
	game.player_orders.refresh()
	_assert_equal(_next(game), "Next: %s starving · YOU enable Cook · THEY cook" % game.residents[0].resident_name, "a food action keeps the name")
	_dispose(game)
