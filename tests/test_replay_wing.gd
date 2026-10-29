extends "res://tests/test_runner.gd"

# Wing-seed slice 4: REPLAY WING on the outcome panel restarts the same seeded wing.
# Seed 0 never shows it.

func _run() -> void:
	_run_case("legacy outcomes keep their actions and loss shows the recap", _test_legacy)
	_run_case("seeded win and loss panels offer REPLAY WING", _test_seeded)
	_run_case("REPLAY WING starts a fresh run of the same seed", _test_replay)
	_run_case("the replay briefing hides LOAD of the ended run's checkpoint", _test_replay_hides_load)
	_run_case("the ended status line names every outcome button", _test_ended_status)
	_run_case("real seeded win shows each LOAD error until expiry and keeps outcome actions", _test_real_win_footer)
	_run_case("real seeded loss shows each LOAD error until expiry and keeps outcome actions", _test_real_loss_footer)
	_run_case("successful LOAD of a real seeded win keeps outcome actions throughout", _test_real_win_load_footer)
	_run_case("successful LOAD of a real seeded loss keeps outcome actions throughout", _test_real_loss_load_footer)
	_run_case("real seeded win keeps outcome guidance and LOAD errors across tool hotkeys", _test_real_win_tool_hotkeys)
	_run_case("real seeded loss keeps outcome guidance and LOAD errors across tool hotkeys", _test_real_loss_tool_hotkeys)
	_run_case("tool key events work live and preserve legacy ended wording", _test_legacy_tool_hotkeys)
	_run_case("a seeded panel followed by a legacy one hides the button again", _test_seeded_then_legacy)
	_run_case("NEW WING still opens a fresh seeded briefing", _test_new_wing_action)
	_run_case("legacy outcomes keep live messages and LOAD feedback", _test_legacy_load_feedback)
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
	_assert_equal(_visible_buttons(orders), ["LOAD LAST CHECKPOINT", "NEW WING"] as Array[String], "legacy loss keeps both legacy actions")
	_assert_true(orders.outcome_retry_button.visible, "loss also offers Retry from day checkpoint")
	_assert_false(orders.outcome_resume_button.visible, "loss cannot Resume")
	_assert_true(orders.outcome_text.text.begins_with("No residents remain alive.\n\n"), "loss recap keeps the final-loss explanation")
	_assert_true("died of" in orders.outcome_text.text and "DAY " in orders.outcome_text.text, "loss recap identifies cause and sim time")
	_assert_true("No tip could have saved them." in orders.outcome_text.text, "a loss without live tip history says no tip was available")
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
		_assert_equal(game.player_orders.outcome_retry_button.visible, not won, "Retry is offered on loss while win actions stay unchanged")
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
	game.player_orders.briefing_begin_button.pressed.emit()
	_assert_false(game.tutorial_open, "replay BEGIN closes the briefing")
	_assert_false(game.user_paused, "replay BEGIN starts the shift")
	game.step_simulation(1.0)
	_assert_almost(game.day_cycle.elapsed_seconds, 1.0, "replay clock advances after BEGIN")
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
			var tools := ["select", "dig", "air"] if seed_value != 0 else ["select"]
			for tool in tools:
				var game := _spawn_game()
				game.new_game(false, seed_value)
				game.set_tool(tool)
				if won:
					game._finish_win()
				else:
					game._finish_loss()
				var expected := "SHIFT ENDED // LOAD LAST CHECKPOINT, NEW WING or REPLAY WING" if seed_value != 0 else "SHIFT ENDED // LOAD LAST CHECKPOINT or NEW WING"
				var message_times := [0.0, 4.0] if seed_value != 0 else [0.0]
				for message_left in message_times:
					game.status_message_left = message_left
					game.player_orders.refresh()
					var label := "seed %d %s tool %s stale message %.1fs" % [seed_value, "win" if won else "loss", tool, message_left]
					_assert_footer(game, expected, label)
				_dispose(game)


func _test_real_win_footer() -> void:
	_test_real_footer(true)


func _test_real_loss_footer() -> void:
	_test_real_footer(false)


func _test_real_win_load_footer() -> void:
	_test_real_footer(true, true)


func _test_real_loss_load_footer() -> void:
	_test_real_footer(false, true)


func _test_real_win_tool_hotkeys() -> void:
	_test_real_footer(true, false, true)


func _test_real_loss_tool_hotkeys() -> void:
	_test_real_footer(false, false, true)


func _test_real_footer(won: bool, load_ended := false, tool_hotkeys := false) -> void:
	var kind := "win" if won else "loss"
	var directory := "user://headless_replay_footer"
	_assert_equal(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)), OK, "isolated footer records directory")
	var game := MAIN_SCENE.instantiate() as VaultGame
	game.records_path = directory.path_join(kind + "-records.json")
	game.best_path = directory.path_join(kind + "-best.json")
	game.save_path = directory.path_join(kind + "-save.json")
	game.checkpoint_path = directory.path_join(kind + "-checkpoint.json")
	for path in [game.records_path, game.best_path, game.save_path, game.checkpoint_path]:
		_remove_test_save(path)
	root.add_child(game)
	# Seed 45 leaves all twelve route cells as rock and warns naturally at 60 s.
	game.new_game(false, 45)
	if not won:
		# The real loss stays idle: veto the Cook's auto food step (as if each Cook blueprint was cancelled).
		for kind_id in VaultGame.COOK_AUTO_CHAIN:
			game.cook_auto_vetoed[kind_id] = true
	game.begin_shift()
	var live_checkpoint := game.create_snapshot()
	if won:
		game.set_tool("dig")
		for x in [16, 15, 14, 13]:
			for y in [14, 15, 16]:
				_assert_true(game.issue_order(Vector2i(x, y)), "real route dig accepted")
		game.step_simulation(40.0)
		for plan in [
			[VaultBuilding.Kind.BED, Vector2i(27, 12)],
			[VaultBuilding.Kind.BED, Vector2i(26, 12)],
			[VaultBuilding.Kind.GENERATOR, Vector2i(21, 12)],
			[VaultBuilding.Kind.KITCHEN, Vector2i(22, 12)],
			[VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12)],
			[VaultBuilding.Kind.AIR_RECYCLER, Vector2i(24, 12)],
		]:
			_assert_true(game.place_blueprint(int(plan[0]), plan[1]), "real route blueprint accepted")
	var tick_limit := int(DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE / VaultGame.SIMULATION_TICK) + 1
	for _tick in tick_limit:
		if game.ended:
			break
		if game.player_orders.breach_warning_panel.visible:
			game.player_orders.breach_resume_button.pressed.emit()
		if game.outcome == "death":
			game.player_orders.outcome_resume_button.pressed.emit()
		game.step_simulation(VaultGame.SIMULATION_TICK)
	_assert_true(game.records_enabled(), "real " + kind + " records enabled")
	_assert_true(game.ended, "real " + kind + " ended")
	_assert_equal(game.outcome, kind, "real outcome reached through play")
	_assert_equal(game.get_alive_count(), 4 if won else 0, "real " + kind + " survivor count")
	_assert_true(game.status_message_left > 0.0, "last live message still pending at " + kind)
	var orders := game.player_orders
	orders.refresh()
	var expected := "SHIFT ENDED // LOAD LAST CHECKPOINT, NEW WING or REPLAY WING"
	_assert_equal(orders.tool_status.text, expected, "real " + kind + " footer names replay immediately")
	_assert_equal(orders.tool_status.tooltip_text, expected, "real " + kind + " footer tooltip")
	_assert_true(orders.tool_status.is_visible_in_tree(), "real " + kind + " footer visible")
	_assert_true(orders.outcome_panel.is_visible_in_tree(), "real " + kind + " panel visible")
	_assert_true(orders.outcome_replay_button.is_visible_in_tree(), "real " + kind + " replay action visible")
	_assert_equal(_visible_buttons(orders), ["LOAD LAST CHECKPOINT", "NEW WING", "REPLAY WING"] as Array[String], "real " + kind + " action order agrees with footer")
	if tool_hotkeys:
		_assert_ended_tool_hotkeys(game, kind)
	elif load_ended:
		_assert_successful_ended_load(game, kind)
	else:
		_assert_failed_loads(game, kind)
	if won:
		orders.keep_running_button.pressed.emit()
		_assert_true(game.keep_running and not game.ended, "real win KEEP RUNNING stays live")
		_assert_false(orders.outcome_panel.visible, "KEEP RUNNING closes the outcome")
		orders.refresh()
		_assert_footer(game, "SELECT // Keep running: the seal win is recorded. The vault carries on.", "KEEP RUNNING feedback")
	else:
		# Exercise the actual successful LOAD action after all failed attempts.
		_assert_true(game.save_load.save_snapshot(live_checkpoint, game.save_path).ok, "write valid live checkpoint")
		_press_outcome_action(game, "LOAD LAST CHECKPOINT")
		_assert_false(game.ended, "successful LOAD restores a live shift")
		_assert_equal(game.outcome, "", "successful LOAD clears the loss")
		_assert_true(game.user_paused, "successful LOAD stays paused")
		_assert_false(orders.outcome_panel.visible, "successful LOAD closes the outcome")
		orders.refresh()
		_assert_footer(game, "SELECT // Wing loaded.", "successful LOAD feedback")
	for path in [game.records_path, game.best_path, game.save_path, game.checkpoint_path]:
		_remove_test_save(path)
	_dispose(game)


func _tool_key(game: VaultGame, key: Key) -> void:
	# Use physical key events in the production handler (including InputMap actions).
	# Release too, so these model separate presses rather than held-key repeats.
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.pressed = pressed
		game._unhandled_input(event)


func _assert_ended_tool_hotkeys(game: VaultGame, kind: String) -> void:
	var expected := "SHIFT ENDED // LOAD LAST CHECKPOINT, NEW WING or REPLAY WING"
	for key: Key in [KEY_E, KEY_X, KEY_ESCAPE]:
		var label := "real %s hotkey %s" % [kind, OS.get_keycode_string(key)]
		_tool_key(game, key)
		var elapsed := 0.0
		for delta in [0.0, 3.9, 0.2]:
			elapsed += delta
			game._process(delta)
			_assert_footer(game, expected, "%s at %.1fs" % [label, elapsed])
		# A fresh failure must survive the same key without losing its serial or timer.
		_remove_test_save(game.save_path)
		_press_outcome_action(game, "LOAD LAST CHECKPOINT")
		_tool_key(game, key)
		elapsed = 0.0
		for delta in [0.0, 3.9, 0.2]:
			elapsed += delta
			game._process(delta)
			_assert_footer(game, "%s // No local save exists yet." % game.active_tool.to_upper(), "%s failed LOAD at %.1fs" % [label, elapsed])
			_assert_almost(game.status_message_left, 5.0 - elapsed, label + " preserves the LOAD countdown")
		game._process(1.0)
		_assert_footer(game, expected, label + " after LOAD expiry")
	# UI buttons and programmatic callers share the same set_tool guard.
	game.set_tool("air")
	game._process(0.0)
	_assert_footer(game, expected, "real " + kind + " direct tool selection")


func _test_legacy_tool_hotkeys() -> void:
	for won in [true, false]:
		var game := _spawn_game()
		game.new_game(false, 0)
		for binding in [[KEY_E, "dig"], [KEY_X, "cancel"], [KEY_ESCAPE, "select"]]:
			_tool_key(game, binding[0])
			_assert_equal(game.active_tool, binding[1], "physical key dispatch selects " + binding[1] + " while live")
		if won:
			game._finish_win()
		else:
			game._finish_loss()
		game._process(4.1)
		for key: Key in [KEY_E, KEY_X, KEY_ESCAPE]:
			_tool_key(game, key)
			var elapsed := 0.0
			for delta in [0.0, 3.9, 0.2]:
				elapsed += delta
				game._process(delta)
				_assert_footer(game, "SHIFT ENDED // LOAD LAST CHECKPOINT or NEW WING", "legacy %s hotkey %s at %.1fs" % ["win" if won else "loss", OS.get_keycode_string(key), elapsed])
		_dispose(game)


func _assert_successful_ended_load(game: VaultGame, kind: String) -> void:
	# Wins auto-save the ended wing; losses need that natural outcome saved explicitly.
	if kind == "loss":
		_assert_true(game.save_game(false), "save the natural ended loss")
	_press_outcome_action(game, "LOAD LAST CHECKPOINT")
	_assert_true(game.ended and game.outcome == kind, "successful LOAD restores the ended " + kind)
	_assert_equal(game.status_message, "Wing loaded.", "ended " + kind + " LOAD succeeds")
	_assert_almost(game.status_message_left, 5.0, "ended " + kind + " LOAD starts its timer")
	var elapsed := 0.0
	for delta in [0.0, 4.9, 0.2]:
		elapsed += delta
		# A zero-delta UI frame also checks the immediate, unexpired success message.
		game._process(delta)
		var label := "ended %s LOAD at %.1fs" % [kind, elapsed]
		_assert_footer(game, "SHIFT ENDED // LOAD LAST CHECKPOINT, NEW WING or REPLAY WING", label)
		_assert_false("Wing loaded." in game.player_orders.tool_status.text, label + " hides success in footer")
		_assert_false("Wing loaded." in game.player_orders.tool_status.tooltip_text, label + " hides success in tooltip")


func _assert_footer(game: VaultGame, expected: String, label: String) -> void:
	_assert_equal(game.player_orders.tool_status.text, expected, label + " footer text")
	_assert_equal(game.player_orders.tool_status.tooltip_text, expected, label + " footer tooltip")
	_assert_true(game.player_orders.tool_status.is_visible_in_tree(), label + " footer visible")


func _press_outcome_action(game: VaultGame, text: String) -> void:
	for child: Node in game.player_orders.outcome_replay_button.get_parent().get_children():
		if child is Button and (child as Button).text == text:
			var button := child as Button
			_assert_true(button.is_visible_in_tree() and not button.disabled, text + " is available")
			button.pressed.emit()
			return
	_assert_true(false, "outcome action exists: " + text)


func _assert_failed_loads(game: VaultGame, kind: String) -> void:
	var before := game.create_snapshot()
	var records_md5 := FileAccess.get_md5(game.records_path)
	var best_md5 := FileAccess.get_md5(game.best_path)
	var failures := [
		["missing", "", "No local save exists yet."],
		["damaged", "[]", "The local save is damaged."],
		["unsupported-version", '{"version":2,"game":{}}', "The local save uses an unsupported version."],
		["invalid-shape", '{"version":1,"game":{}}', "The save did not contain a valid vault wing."],
	]
	for failure: Array in failures:
		var label := "real %s %s LOAD" % [kind, failure[0]]
		_remove_test_save(game.save_path)
		if failure[0] != "missing":
			var file := FileAccess.open(game.save_path, FileAccess.WRITE)
			file.store_string(failure[1])
			file.close()
		_press_outcome_action(game, "LOAD LAST CHECKPOINT")
		game.player_orders.refresh()
		_assert_footer(game, "%s // %s" % [game.active_tool.to_upper(), failure[2]], label)
		_assert_almost(game.status_message_left, 5.0, label + " starts a five-second timer")
		_assert_true(game.ended and game.outcome == kind, label + " keeps the outcome")
		_assert_true(game.player_orders.outcome_panel.is_visible_in_tree(), label + " keeps actions visible")
		# Use the real UI frame timer: the simulation is paused on an outcome.
		game._process(4.9)
		_assert_footer(game, "%s // %s" % [game.active_tool.to_upper(), failure[2]], label + " before expiry")
		game._process(0.2)
		_assert_footer(game, "SHIFT ENDED // LOAD LAST CHECKPOINT, NEW WING or REPLAY WING", label + " after expiry")
		_assert_variants_equal(before, game.create_snapshot(), label + " leaves the vault snapshot unchanged")
		_assert_equal(FileAccess.get_md5(game.records_path), records_md5, label + " leaves records unchanged")
		_assert_equal(FileAccess.get_md5(game.best_path), best_md5, label + " leaves best unchanged")
		if failure[0] != "missing":
			_assert_equal(FileAccess.get_file_as_string(game.save_path), failure[1], label + " leaves save bytes unchanged")
		else:
			_assert_false(FileAccess.file_exists(game.save_path), label + " does not create a save")


func _test_new_wing_action() -> void:
	for won in [true, false]:
		var game := _spawn_game()
		game.new_game(false, 45)
		if won:
			game._finish_win()
		else:
			game._finish_loss()
		_press_outcome_action(game, "NEW WING")
		_assert_true(game.wing_seed != 0, "NEW WING rolls a seeded wing")
		_assert_false(game.ended, "NEW WING clears the outcome")
		_assert_equal(game.outcome, "", "NEW WING clears the result")
		_assert_equal(game.get_alive_count(), 4, "NEW WING resets the crew")
		_assert_almost(game.day_cycle.elapsed_seconds, 0.0, "NEW WING resets the clock")
		_assert_true(game.player_orders.is_briefing_open(), "NEW WING opens the briefing")
		_assert_true(game.player_orders.briefing_load_button.visible, "NEW WING retains briefing LOAD")
		_dispose(game)


func _test_legacy_load_feedback() -> void:
	for won in [true, false]:
		var game := _spawn_game()
		game.save_path = "user://legacy_outcome_feedback.json"
		game.new_game(false, 0)
		game.set_tool("select")
		if won:
			game._finish_win()
		else:
			game._finish_loss()
		game.player_orders.refresh()
		_assert_footer(game, "SELECT // " + game._tool_help("select"), "legacy keeps the last live message")
		_remove_test_save(game.save_path)
		_press_outcome_action(game, "LOAD LAST CHECKPOINT")
		game.player_orders.refresh()
		_assert_footer(game, "SELECT // No local save exists yet.", "legacy LOAD feedback")
		game._process(5.1)
		_assert_footer(game, "SHIFT ENDED // LOAD LAST CHECKPOINT or NEW WING", "legacy expired feedback")
		_dispose(game)
