extends "res://tests/test_runner.gd"

# NX37: after the seal, no Mk II fit and no second-tray nudge until an Air Recycler is finished and
# powered (05/4242 GROW NOOK engaged: two tray fits took the Air Recycler's salvage, O2 out t=229).


func _run() -> void:
	_run_case("no Mk II fit or second-tray nudge before an Air Recycler", _test_no_air)
	_run_case("a finished but unpowered Air Recycler still holds them back", _test_unpowered_air)
	_run_case("a finished, powered Air Recycler brings them back", _test_air_powered)
	print("")
	if _failure_count == 0:
		print("MK2 AIR GATE TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("MK2 AIR GATE TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _sealed_game() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(22, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(24, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(24, 14))
	_add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(22, 16))
	game.day_cycle.deserialize({"elapsed_seconds": 70.0, "current_day": 2, "completed": false})
	game.breach_system.advance(0.0, 70.0)
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.apply_patch_work(100.0)
	game.job_system.rebuild_from_state()
	game.power_grid.recalculate(game.buildings)
	game.start_reclamation()
	game.food_system.raw_food = 0
	game.food_system.salvage = 60
	return game


func _assert_gated(game: VaultGame, why: String) -> void:
	game.player_orders.refresh()
	var po = game.player_orders
	_assert_false(po.also_text().begins_with("Also: fit"), "no 'Also: fit' line %s (got '%s')" % [why, po.also_text()])
	_assert_true(po._upgrade_offer_target() == null, "no Mk II offer %s" % why)
	_assert_true(po.salvage_nudge_kind() != VaultBuilding.Kind.GROW_TRAY, "no second-tray nudge %s" % why)


func _test_no_air() -> void:
	var game := _sealed_game()
	_assert_true(game.breach_system.is_sealed(), "wing sealed")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.AIR_RECYCLER), 0, "no Air Recycler yet")
	_assert_gated(game, "with no Air Recycler")
	_dispose(game)


func _test_unpowered_air() -> void:
	var game := _sealed_game()
	var air := _add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(26, 12))
	air.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	_assert_false(air.powered, "Air Recycler finished but off")
	_assert_gated(game, "with the Air Recycler unpowered")
	_dispose(game)


func _test_air_powered() -> void:
	var game := _sealed_game()
	_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(26, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.AIR_RECYCLER), 1, "Air Recycler powered")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.also_text(), "Also: fit Grow Tray Mk II · 18", "the Grow Tray Mk II fit is back")
	_assert_equal(game.player_orders.salvage_nudge_kind(), VaultBuilding.Kind.GROW_TRAY, "the second-tray nudge is back")
	_dispose(game)
