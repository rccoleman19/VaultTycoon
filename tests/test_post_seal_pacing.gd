extends "res://tests/test_runner.gd"

# Post-seal pacing (QA-d #2/#3/#4): life support is supplied first after the seal.


func _run() -> void:
	_run_case("after the seal, life-support blueprints are supplied before others", _test_life_support_rule)
	_run_case("a second Grow Tray cannot take the Air Recycler's salvage", _test_life_support_sim)
	_finish()


func _finish() -> void:
	print("")
	if _failure_count == 0:
		print("POST-SEAL TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("POST-SEAL TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _seal(game: VaultGame) -> void:
	game.breach_system._enter_sealed(true)


func _blueprint(game: VaultGame, kind: int, cell: Vector2i) -> VaultBuilding:
	_assert_true(game.place_blueprint(kind, cell), "%s blueprint placed at %s" % [VaultBuilding.KIND_NAMES[kind], cell])
	for building: VaultBuilding in game.buildings:
		if building.cell == cell and building.kind == kind:
			return building
	return null


func _test_life_support_rule() -> void:
	var game := _spawn_game()
	game.begin_shift()
	var air := _blueprint(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(24, 12))
	var tray := _blueprint(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12))
	var charge := _blueprint(game, VaultBuilding.Kind.GENERATOR, Vector2i(21, 12))
	_assert_false(game.job_system._life_support_waiting(tray), "pre-seal: the tray never waits")
	_seal(game)
	_assert_true(game.job_system._life_support_waiting(tray), "sealed: the tray waits for life support")
	_assert_false(game.job_system._life_support_waiting(air), "the Air Recycler never waits")
	_assert_false(game.job_system._life_support_waiting(charge), "a Charge Node never waits")
	air.delivered = air.get_cost()
	_assert_true(game.job_system._life_support_waiting(tray), "an unsupplied Charge Node still holds the tray")
	charge.delivered = charge.get_cost()
	_assert_false(game.job_system._life_support_waiting(tray), "all life support supplied: the tray may take salvage")
	_dispose(game)


func _test_life_support_sim() -> void:
	var game := _spawn_game()
	game.begin_shift()
	_seal(game)
	var tray := _blueprint(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12))
	var air := _blueprint(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(24, 12))
	game.food_system.salvage = 14
	game.step_simulation(40.0)
	_assert_equal(air.delivered, 14, "the Air Recycler gets all 14 salvage")
	_assert_equal(tray.delivered, 0, "the earlier-placed tray gets none")
	_dispose(game)
