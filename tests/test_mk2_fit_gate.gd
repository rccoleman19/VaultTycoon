extends "res://tests/test_runner.gd"

# Every Mk II purchase, including the fixture inspector, needs finished and powered air support.


func _run() -> void:
	_run_case("no Air Recycler blocks the inspector and Mk II purchase", _test_no_air)
	_run_case("an unfinished Air Recycler still blocks the fit", _test_unfinished_air)
	_run_case("a finished but disabled Air Recycler still blocks the fit", _test_disabled_air)
	_run_case("a finished powered Air Recycler permits the fit for 18 salvage", _test_powered_air)
	print("")
	if _failure_count == 0:
		print("MK2 FIT GATE TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("MK2 FIT GATE TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _sealed_game() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(22, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(24, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(24, 14))
	game.day_cycle.deserialize({"elapsed_seconds": 70.0, "current_day": 2, "completed": false})
	game.breach_system.advance(0.0, 70.0)
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.apply_patch_work(100.0)
	game.job_system.rebuild_from_state()
	game.power_grid.recalculate(game.buildings)
	game.food_system.salvage = 60
	return game


func _select_tray(game: VaultGame) -> VaultBuilding:
	var tray := game.get_building_at(Vector2i(22, 12))
	_assert_true(game.breach_system.is_sealed(), "hatch sealed")
	_assert_true(game.is_upgrade_unlocked(VaultBuilding.Kind.GROW_TRAY), "Grow Mk II unlocked")
	_assert_true(tray.complete, "Grow Tray finished")
	_assert_equal(tray.upgrade_tier, 1, "Grow Tray starts at tier 1")
	_assert_equal(game.food_system.salvage, 60, "plenty of salvage for the fit")
	game.select_building(tray.building_id)
	game.player_orders.refresh()
	_assert_true(game.player_orders.fixture_upgrade_row.visible, "inspector keeps the fit row visible")
	_assert_equal(game.player_orders.fixture_upgrade_button.text, "FIT MK II · 18 SALVAGE", "inspector shows the fit price")
	return tray


func _assert_fit_refused(game: VaultGame, why: String) -> void:
	var tray := _select_tray(game)
	var salvage_before := game.food_system.salvage
	var tier_before := tray.upgrade_tier
	_assert_false((game.get_powered_building_count(VaultBuilding.Kind.AIR_RECYCLER) > 0), "air not ready %s" % why)
	_assert_false(game.player_orders._air_ready(), "offer uses the same air rule %s" % why)
	_assert_false(game.can_upgrade_building(tray.building_id), "fit unavailable %s" % why)
	_assert_false(game.upgrade_building(tray.building_id), "purchase refused %s" % why)
	_assert_equal(game.food_system.salvage, salvage_before, "salvage unchanged %s" % why)
	_assert_equal(tray.upgrade_tier, tier_before, "tier unchanged %s" % why)
	_assert_true(game.player_orders.fixture_upgrade_button.disabled, "inspector fit disabled %s" % why)
	_assert_equal(game.player_orders.fixture_upgrade_button.tooltip_text, "Needs a powered Air Recycler", "inspector explains the air requirement %s" % why)


func _test_no_air() -> void:
	var game := _sealed_game()
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.AIR_RECYCLER), 0, "no powered Air Recycler")
	_assert_fit_refused(game, "with no Air Recycler")
	_dispose(game)


func _test_unfinished_air() -> void:
	var game := _sealed_game()
	_assert_true(game.place_blueprint(VaultBuilding.Kind.AIR_RECYCLER, Vector2i(26, 12)), "Air Recycler blueprint placed")
	var air := game.get_building_at(Vector2i(26, 12))
	_assert_false(air.complete, "Air Recycler unfinished")
	game.power_grid.recalculate(game.buildings)
	_assert_fit_refused(game, "with an unfinished Air Recycler")
	_dispose(game)


func _test_disabled_air() -> void:
	var game := _sealed_game()
	var air := _add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(26, 12))
	air.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	_assert_true(air.complete, "Air Recycler finished")
	_assert_false(air.powered, "Air Recycler switched off")
	_assert_fit_refused(game, "with a disabled Air Recycler")
	_dispose(game)


func _test_powered_air() -> void:
	var game := _sealed_game()
	var air := _add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(26, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_true(air.complete and air.powered, "Air Recycler finished and powered")
	_assert_true((game.get_powered_building_count(VaultBuilding.Kind.AIR_RECYCLER) > 0), "air ready")
	_assert_true(game.player_orders._air_ready(), "offer uses the same air rule")
	var tray := _select_tray(game)
	_assert_true(game.can_upgrade_building(tray.building_id), "fit available")
	_assert_false(game.player_orders.fixture_upgrade_button.disabled, "inspector fit enabled")
	_assert_equal(game.player_orders.fixture_upgrade_button.tooltip_text, game.player_orders._upgrade_benefit_text(tray), "inspector shows the fit benefit")
	var salvage_before := game.food_system.salvage
	_assert_true(game.upgrade_building(tray.building_id), "purchase succeeds")
	_assert_equal(game.food_system.salvage, salvage_before - 18, "exactly 18 salvage spent")
	_assert_equal(tray.upgrade_tier, 2, "Grow Tray fitted to tier 2")
	_dispose(game)
