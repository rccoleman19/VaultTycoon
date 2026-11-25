extends "res://tests/test_air_early_warning.gd"

# Codex review of #138 (6511091017). Player-visible checks:
# 1 pressing Spend "build Air Recycler" arms the Air tool (it raised an index error);
# 2 a queued Charge Node moves Next and Spend on to the Air Recycler;
# 3 an urgent resident step that wins Next also keeps Spend off the air build;
# 4 the same save bytes show the same air warning in a fresh and a reused game, and Retry recomputes it.


func _run() -> void:
	_run_case("idle 05 s8 at ~144 s: pressing Spend arms the Air Recycler tool", _test_spend_press)
	_run_case("power short with a Charge Node queued: Next and Spend move on to the Air Recycler", _test_queued_charge)
	_run_case("an urgent resident step wins Next and Spend alike", _test_urgent_spend)
	_run_case("LOAD and Retry give the same air warning as a fresh game", _test_latch_reload)
	print("")
	if _failure_count == 0:
		print("AIR CODEX FIX TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("AIR CODEX FIX TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
			_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _test_spend_press() -> void:
	var game := _idle_05_s8()
	_to_first_warning(game)
	while game.day_cycle.elapsed_seconds < 144.0:
		game.step_simulation(SAMPLE_S)
		game.player_orders.refresh()
	_assert_true("Air Recycler" in _spend_text(game), "Spend offers the Air Recycler: %s" % _spend_text(game))
	_assert_true(_press_spend_queues(game, VaultBuilding.Kind.AIR_RECYCLER), "pressing Spend queues an Air Recycler")
	_dispose(game)


func _power_short_game() -> VaultGame:
	var game := _game(40, true)
	while game.player_orders._planned_power_spare() >= int(VaultBuilding.POWER_DEMAND[VaultBuilding.Kind.AIR_RECYCLER]):
		_add_complete(game, VaultBuilding.Kind.GROW_TRAY)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.oxygen_system.oxygen = OxygenSystem.LOW_OXYGEN_THRESHOLD + (-game.oxygen_system.net_rate) * 30.0
	game.player_orders.refresh()
	return game


func _test_queued_charge() -> void:
	var game := _power_short_game()
	_assert_true("Charge Node" in _next(game), "the fixture first asks for a Charge Node: %s" % _next(game))
	var cells: Array[Vector2i] = game._annex_free_cells(1)
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, cells[0]), "a Charge Node blueprint is queued")
	game.player_orders.refresh()
	var next := _next(game)
	_assert_true("Air Recycler" in next and not next.contains("YOU place a Charge Node") and not next.contains("build Charge Node"), "Next moves on to the Air Recycler: %s" % next)
	_assert_true(not "Charge Node" in _spend_text(game), "Spend no longer offers another Charge Node: %s" % _spend_text(game))
	_dispose(game)


func _test_urgent_spend() -> void:
	var game := _game(30, true)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.oxygen_system.oxygen = OxygenSystem.LOW_OXYGEN_THRESHOLD + (-game.oxygen_system.net_rate) * 40.0
	var resident: VaultResident = game.residents[0]
	resident.needs.rest = 0.0
	resident.needs.health = 0.75
	game.player_orders.refresh()
	var chain: Dictionary = game.player_orders._primary_next_step_chain({})
	_assert_true(bool(chain.get("urgent", false)) and not "Rec Console" in str(chain.get("text", "")), "the fixture's own urgent step is not Rec Console (%s)" % chain.get("text", ""))
	var next := _next(game)
	_assert_true(_resident_step(game, next) and not "Air Recycler" in next, "the urgent resident step wins Next: %s" % next)
	var spend := _spend_text(game)
	_assert_true(not "Air Recycler" in spend and not "Charge Node" in spend, "Spend does not offer the air build over it: %s" % spend)
	_dispose(game)


func _test_latch_reload() -> void:
	var game := _idle_05_s8()
	_to_first_warning(game)
	_assert_true(not _early_alert(game).is_empty(), "the warning latched")
	# Healthy bytes: LOW is now 3+ minutes out, still draining.
	game.oxygen_system.oxygen = OxygenSystem.LOW_OXYGEN_THRESHOLD + (-game.oxygen_system.net_rate) * 200.0
	var snapshot: Dictionary = game.create_snapshot()
	var fresh := _spawn_game()
	fresh.new_game(false, 8, 5)
	fresh.apply_snapshot(snapshot.duplicate(true))
	fresh.player_orders.refresh()
	var fresh_alert := _early_alert(fresh)
	_dispose(fresh)
	game.apply_snapshot(snapshot.duplicate(true))
	game.player_orders.refresh()
	_assert_equal(_early_alert(game), fresh_alert, "LOAD into the latched game matches a fresh game")
	_assert_equal(fresh_alert, "", "a 200 s runway shows no early warning")
	# Retry: back to the day checkpoint before the warning was due.
	_to_first_warning(game)
	if game.can_retry_day_checkpoint():
		_assert_true(game.retry_day_checkpoint(), "Retry restores the day checkpoint")
		game.player_orders.refresh()
		var to_low: float = game.oxygen_system.get_seconds_to_low()
		_assert_equal(_early_alert(game).is_empty(), not (to_low <= 60.0) or not game.breach_system.is_sealed(), "after Retry the warning follows the restored runway (%.1f s)" % to_low)
	else:
		_assert_true(false, "a day checkpoint is available for Retry")
	_dispose(game)
