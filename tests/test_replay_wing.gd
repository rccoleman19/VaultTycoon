extends "res://tests/test_runner.gd"

# Wing-seed slice 4: REPLAY WING on the outcome panel restarts the same seeded wing.
# Seed 0 never shows it.

const LEGACY_LOSS := "No residents remain alive. Reopen the last daily checkpoint or initialize a new wing and stabilize supplies, powered air recycling, and the pressure hatch sooner."


func _run() -> void:
	_run_case("legacy outcome panels keep two buttons and their text", _test_legacy)
	_run_case("seeded win and loss panels offer REPLAY WING", _test_seeded)
	_run_case("REPLAY WING starts a fresh run of the same seed", _test_replay)
	_run_case("the replay briefing hides LOAD of the ended run's checkpoint", _test_replay_hides_load)
	_run_case("the ended status line names every outcome button", _test_ended_status)
	_run_case("a seeded panel followed by a legacy one hides the button again", _test_seeded_then_legacy)
	_finish()


func _finish() -> void:
	print("")
	if _failure_count == 0:
		print("REPLAY WING TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("REPLAY WING TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _visible_buttons(orders: PlayerOrders) -> Array[String]:
	var names: Array[String] = []
	for child: Node in orders.outcome_replay_button.get_parent().get_children():
		if child is Button and (child as Button).visible:
			names.append((child as Button).text)
	return names


func _test_legacy() -> void:
	var game := _spawn_game()
	game._finish_loss()
	var orders := game.player_orders
	_assert_true(orders.outcome_panel.visible, "loss panel shows")
	_assert_equal(_visible_buttons(orders), ["LOAD LAST CHECKPOINT", "NEW WING"] as Array[String], "legacy loss keeps two buttons")
	_assert_equal(orders.outcome_text.text, LEGACY_LOSS, "legacy loss text unchanged")
	_dispose(game)
	game = _spawn_game()
	game.new_game(false, 0)
	game._finish_win()
	orders = game.player_orders
	_assert_equal(_visible_buttons(orders), ["LOAD LAST CHECKPOINT", "NEW WING"] as Array[String], "legacy win keeps two buttons")
	_assert_equal(orders.outcome_title.text, "SEAL STABILIZED", "legacy win title unchanged")
	_dispose(game)


func _test_seeded() -> void:
	for won in [true, false]:
		var game := _spawn_game()
		game.new_game(false, 4242)
		if won:
			game._finish_win()
		else:
			game._finish_loss()
		_assert_equal(_visible_buttons(game.player_orders), ["LOAD LAST CHECKPOINT", "NEW WING", "REPLAY WING"] as Array[String], "seeded %s offers REPLAY WING last" % ("win" if won else "loss"))
		_dispose(game)


func _test_replay() -> void:
	var game := _spawn_game()
	game.new_game(false, 4242)
	game.begin_shift()
	game.step_simulation(30.0)
	game.residents[0].kill()
	game.map_grid.dig_marks[Vector2i(16, 15)] = true
	game._finish_loss()
	game.player_orders.outcome_replay_button.pressed.emit()
	_assert_equal(game.wing_seed, 4242, "the same seed")
	_assert_false(game.ended, "a fresh run")
	_assert_equal(game.outcome, "", "no outcome carried over")
	_assert_equal(game.day_cycle.current_day, 1, "back to day 1")
	_assert_almost(game.day_cycle.elapsed_seconds, 0.0, "clock reset")
	_assert_equal(game.get_alive_count(), 4, "whole crew back")
	_assert_equal(game.map_grid.layout_seed, 4242, "same seeded layout")
	_assert_false(game.map_grid.dig_marks.has(Vector2i(16, 15)), "old designations cleared")
	var crew := VaultResident.crew_traits_for_seed(4242)
	for resident: VaultResident in game.residents:
		_assert_equal(resident.trait_id, crew[resident.resident_id - 1], "%s keeps the wing's trait" % resident.resident_name)
	_assert_equal(game.breach_system.warning_at, BreachSystem.warning_at_for_seed(4242), "same hatch window")
	_assert_false(game.player_orders.outcome_panel.visible, "outcome closes")
	_assert_true(game.player_orders.is_briefing_open(), "the NEW WING briefing opens")
	_dispose(game)


func _assert_almost(actual: float, expected: float, label: String) -> void:
	_assert_true(absf(actual - expected) < 0.0001, "%s — expected %.4f, got %.4f" % [label, expected, actual])


func _test_seeded_then_legacy() -> void:
	var game := _spawn_game()
	game.new_game(false, 4242)
	game._finish_loss()
	_assert_true(game.player_orders.outcome_replay_button.visible, "seeded loss shows it")
	game.new_game(false, 0)
	_assert_false(game.player_orders.outcome_panel.visible, "new game hides the panel")
	game._finish_loss()
	_assert_false(game.player_orders.outcome_replay_button.visible, "the legacy loss hides it again")
	game.player_orders.replay_wing()
	_assert_true(game.ended, "replay does nothing on the legacy wing")
	_dispose(game)


func _test_replay_hides_load() -> void:
	var game := _spawn_game()
	game.new_game(true, 4242)
	var orders := game.player_orders
	_assert_true(orders.briefing_load_button.visible, "a seeded NEW WING briefing keeps LOAD")
	game.begin_shift()
	game.step_simulation(30.0)
	_assert_true(game.save_game(false), "a checkpoint of this run exists")
	game._finish_loss()
	orders.outcome_replay_button.pressed.emit()
	_assert_true(orders.is_briefing_open(), "the replay briefing opens")
	_assert_false(orders.briefing_load_button.visible, "the replay briefing hides LOAD")
	_assert_false(orders.briefing_load_button in orders._briefing_focus_controls(true), "LOAD is not a focus stop")
	_assert_true(orders.briefing_begin_button.visible, "BEGIN SHIFT stays")
	orders.show_briefing(true, false)
	_assert_true(orders.briefing_load_button.visible, "the HELP briefing still offers LOAD")
	game.new_game(true, 0)
	_assert_true(orders.briefing_load_button.visible, "a legacy NEW WING briefing keeps LOAD")
	game.new_game(true, 4242)
	_assert_true(orders.briefing_load_button.visible, "a plain seeded NEW WING after a replay keeps LOAD")
	_dispose(game)


func _test_ended_status() -> void:
	for seed_value in [0, 4242]:
		for won in [true, false]:
			var game := _spawn_game()
			game.new_game(false, seed_value)
			if won:
				game._finish_win()
			else:
				game._finish_loss()
			game.set_tool("select")
			game.status_message_left = 0.0
			game.player_orders.refresh()
			var expected := "SHIFT ENDED // LOAD LAST CHECKPOINT, NEW WING or REPLAY WING" if seed_value != 0 else "SHIFT ENDED // LOAD LAST CHECKPOINT or NEW WING"
			_assert_equal(game.player_orders.tool_status.text, expected, "seed %d %s status line" % [seed_value, "win" if won else "loss"])
			_dispose(game)
