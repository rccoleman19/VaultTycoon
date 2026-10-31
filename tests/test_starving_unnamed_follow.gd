extends "res://tests/test_runner.gd"
# Codex 6539075741 on #143. Natural route: seed 4242 / SL3, Charge + Air queued,
# every Haul priority OFF, warning acknowledged. At 119.4 s Cyra is starving but
# Next names the hatch response without her name: "YOU enable Haul [P] · THEY patch hatch".
# The STARVING alert comes from the starvation state, and the follow driver acts
# on that urgent unnamed YOU step (and still ignores passive tips).

const FollowDriver := preload("res://tools/playtest/follow_driver.gd")
const SAMPLE_S := 0.2
const NEXT_HAUL := "Next: YOU enable Haul [P] · THEY patch hatch"


func _run() -> void:
	_run_case("starving alert follows the state while Next stays unnamed", _test_alert)
	_run_case("follow driver enables Haul on the urgent unnamed step", _test_follow)
	_run_case("passive YOU tips stay unfollowed", _test_passive)
	print("STARVING UNNAMED FOLLOW: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _route() -> VaultGame:
	var game := _spawn_game()
	game.new_game(false, 4242, 3)
	game.begin_shift()
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(20, 12)), "Charge queued at (20,12)")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.AIR_RECYCLER, Vector2i(21, 12)), "Air queued at (21,12)")
	var haul_off := false
	while game.day_cycle.elapsed_seconds < 119.4 and not game.ended:
		if not haul_off and game.get_completed_building_count(VaultBuilding.Kind.AIR_RECYCLER) > 0:
			for resident: VaultResident in game.residents:
				game.set_work_priority(resident.resident_id, "haul", VaultResident.PRIORITY_DISABLED)
			haul_off = true
		if game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged:
			game.acknowledge_breach_warning(false)
		game.step_simulation(SAMPLE_S)
	game.player_orders.refresh()
	_assert_true(haul_off, "jobs powered the Air Recycler before Haul went OFF")
	return game


func _cyra(game: VaultGame) -> VaultResident:
	for resident: VaultResident in game.residents:
		if resident.resident_name == "Cyra":
			return resident
	return null


func _test_alert() -> void:
	var game := _route()
	var cyra := _cyra(game)
	print("ROUTE t=%.1f next=%s food=%.1f meals=%d alerts=%s" % [game.day_cycle.elapsed_seconds, game.player_orders.objective_label.text, cyra.needs.food, game.food_system.meals, str(game.player_orders.all_alerts)])
	_assert_true(cyra.alive and cyra.needs.food < 20.0 and game.food_system.meals == 0, "Cyra is starving at 119.4 s")
	_assert_equal(game.player_orders.objective_label.text, NEXT_HAUL, "Next stays the unnamed hatch response")
	_assert_true("STARVING: Cyra" in game.player_orders.all_alerts, "STARVING: Cyra is in all alerts (%s)" % str(game.player_orders.all_alerts))
	_assert_true("STARVING: Cyra" in game.player_orders.alert_list, "STARVING: Cyra is on the alert line (%s)" % str(game.player_orders.alert_list))
	_dispose(game)


func _haul_on(game: VaultGame) -> int:
	var on := 0
	for resident: VaultResident in game.residents:
		if resident.alive and resident.get_work_priority("haul") > VaultResident.PRIORITY_DISABLED:
			on += 1
	return on


func _drive(game: VaultGame) -> void:
	# A real driver instance, used synchronously and freed before its deferred start runs.
	var driver = FollowDriver.new()
	driver.game = game
	driver.logf = FileAccess.open("user://follow_test.log", FileAccess.WRITE)
	driver._follow_next()
	driver.logf.close()
	driver.free()


func _test_follow() -> void:
	var game := _route()
	_assert_equal(game.player_orders.objective_label.text, NEXT_HAUL, "the driver sees the urgent unnamed step")
	_assert_equal(_haul_on(game), 0, "every Haul is OFF before the driver acts")
	_drive(game)
	_assert_true(_haul_on(game) > 0, "the driver enables a Haul priority (%d on)" % _haul_on(game))
	_dispose(game)


func _test_passive() -> void:
	_assert_equal(FollowDriver.followed_action("Next: YOU place bunks · THEY craft", []), "", "a passive tip is not followed")
	_assert_equal(FollowDriver.followed_action("Next: YOU leave Haul + Craft on · THEY finish the bunks", []), "", "a passive leave-on tip is not followed")
