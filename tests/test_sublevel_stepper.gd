extends "res://tests/test_runner.gd"

# Records + ladder C6: NEW WING starts on the deepest unlocked sublevel; the opening briefing steps
# between unlocked sublevels and shows the wing's record.

var _path := ""


func _run() -> void:
	_path = "user://test_sublevel_stepper_%d.json" % OS.get_process_id()
	_run_case("without an unlock (or records) the briefing is unchanged", _test_hidden)
	_run_case("NEW WING starts on the deepest unlocked sublevel and the stepper moves within range", _test_stepper)
	_run_case("the briefing names the wing's record on this sublevel", _test_record_line)
	_run_case("stepping keeps a replay's LOAD hidden and does nothing once the shift began", _test_replay_and_started)
	print("")
	if _failure_count == 0:
		print("SUBLEVEL STEPPER TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("SUBLEVEL STEPPER TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _clean() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path + suffix))


func _guard(game: VaultGame) -> bool:
	var ok := game.has_method("new_wing") and game.player_orders.has_method("step_sublevel")
	_assert_true(ok, "NEW WING and the stepper exist")
	return ok


func _game(won_levels: Array) -> VaultGame:
	_clean()
	var store := WingRecords.new()
	store.path = _path
	for level: int in won_levels:
		store.record(0x0777, true, 2, 7, level)
	var game := _spawn_game()
	game.records_path = _path
	return game


func _test_hidden() -> void:
	var game := _spawn_game()
	if not _guard(game):
		_dispose(game)
		return
	game.new_wing()
	_assert_equal(game.sublevel, 7, "records off: NEW WING is 07")
	_assert_false(game.player_orders.briefing_sublevel_row.visible, "records off: no stepper")
	_assert_false(game.player_orders.briefing_record_label.visible, "records off: no record line")
	_dispose(game)
	game = _game([])
	game.new_wing()
	_assert_equal(game.sublevel, 7, "nothing unlocked: 07")
	_assert_false(game.player_orders.briefing_sublevel_row.visible, "nothing unlocked: no stepper")
	game.new_game(true, 0)
	_assert_false(game.player_orders.briefing_sublevel_row.visible, "seed 0: no stepper")
	_dispose(game)
	_clean()


func _test_stepper() -> void:
	var game := _game([7, 6])
	if not _guard(game):
		_dispose(game)
		return
	game.new_wing()
	var seed_value := game.wing_seed
	var orders := game.player_orders
	_assert_equal(game.sublevel, 5, "07 and 06 won: NEW WING starts on 05")
	_assert_true(orders.briefing_sublevel_row.visible, "the stepper shows")
	_assert_equal(orders.briefing_sublevel_label.text, "SUBLEVEL 05 · THIN VEINS", "names the sublevel and modifier")
	_assert_true(orders.briefing_deeper_button.disabled, "05 is the deepest unlocked")
	orders.briefing_shallower_button.pressed.emit()
	_assert_equal([game.wing_seed, game.sublevel], [seed_value, 6], "▶ goes to 06 on the same seed")
	_assert_equal(game.breach_system.warning_at, BreachSystem.warning_at_for_seed(seed_value) - 15.0, "06 rules apply")
	orders.briefing_shallower_button.pressed.emit()
	_assert_equal(game.sublevel, 7, "▶ again goes to 07")
	_assert_equal(orders.briefing_sublevel_label.text, "SUBLEVEL 07 · BASE", "07 is the base")
	_assert_true(orders.briefing_shallower_button.disabled, "07 is the top")
	orders.step_sublevel(1)
	_assert_equal(game.sublevel, 7, "no step past 07")
	orders.briefing_deeper_button.pressed.emit()
	orders.briefing_deeper_button.pressed.emit()
	orders.step_sublevel(-1)
	_assert_equal(game.sublevel, 5, "no step past the deepest unlocked")
	_assert_true(orders.briefing_overlay.visible and orders.briefing_begin_button.visible, "still the opening briefing")
	game.new_game(true, seed_value)
	_assert_equal(game.sublevel, 7, "new_game itself still defaults to 07")
	_dispose(game)
	_clean()


func _test_record_line() -> void:
	var game := _game([7])
	if not _guard(game):
		_dispose(game)
		return
	game.new_game(true, 0x0777)
	_assert_equal(game.player_orders.briefing_record_label.text, "RECORD 07-0777 · BEST ★★☆ · FURTHEST DAY 7", "the 07 record")
	_assert_true(game.player_orders.briefing_record_label.visible, "record line shows")
	game.player_orders.step_sublevel(-1)
	_assert_equal(game.sublevel, 6, "stepped to 06")
	_assert_false(game.player_orders.briefing_record_label.visible, "no 06 record yet")
	game.wing_records().record(0x0777, true, 3, 9, 7, true)
	game.new_game(true, 0x0777)
	_assert_equal(game.player_orders.briefing_record_label.text, "RECORD 07-0777 · BEST ★★★ · FURTHEST DAY 9 · ANNEX", "best grade, furthest day and the annex badge")
	_dispose(game)
	_clean()


func _test_replay_and_started() -> void:
	var game := _game([7])
	if not _guard(game):
		_dispose(game)
		return
	game.new_game(false, 0x0777, 6)
	game.begin_shift()
	game._finish_loss()
	game.player_orders.replay_wing()
	_assert_equal(game.sublevel, 6, "replay keeps 06")
	_assert_false(game.player_orders.briefing_load_button.visible, "replay hides LOAD")
	game.player_orders.step_sublevel(1)
	_assert_equal(game.sublevel, 7, "stepped to 07")
	_assert_false(game.player_orders.briefing_load_button.visible, "LOAD stays hidden after a step")
	game.begin_shift()
	game.player_orders.step_sublevel(-1)
	_assert_equal(game.sublevel, 7, "no step once the shift began")
	_assert_false(game.player_orders.briefing_sublevel_row.visible, "stepper hidden in play")
	_dispose(game)
	_clean()
