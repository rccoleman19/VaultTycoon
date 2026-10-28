extends "res://tests/test_runner.gd"

# Meta perks P2: the briefing's perk row: hidden until a perk is unlocked, ◀/▶ pick NONE or an
# unlocked perk and rebuild the wing with it once, the arrows join the keyboard ring after the
# sublevel stepper, and the win screen's record line says which perk the run used.

var _path := ""


func _run() -> void:
	_path = "user://test_perk_row_%d.json" % OS.get_process_id()
	_run_case("the perk row stays hidden until a perk is unlocked", _test_hidden)
	_run_case("▶ equips PROVISIONING and rebuilds the wing with it; ◀ returns to NONE", _test_pick)
	_run_case("the perk arrows join the keyboard ring after the stepper, focus stays on them", _test_focus)
	_run_case("the record line says \"with PROVISIONING\" only on a perk run", _test_record_line)
	_run_case("HELP and REPLAY: HELP hides the row, REPLAY keeps the perk and LOAD hidden", _test_help_replay)
	print("")
	if _failure_count == 0:
		print("PERK ROW TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("PERK ROW TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _clean() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path + suffix))


func _game(won_levels: Array) -> VaultGame:
	_clean()
	var store := WingRecords.new()
	store.path = _path
	for level: int in won_levels:
		store.record(0x0777, true, 2, 7, level)
	var game := _spawn_game()
	game.records_path = _path
	return game


func _guard(game: VaultGame) -> bool:
	var ok := "briefing_perk_row" in game.player_orders and game.player_orders.has_method("step_perk")
	_assert_true(ok, "the briefing has a perk row")
	return ok


func _key(game: VaultGame, keycode: Key, shift := false) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.shift_pressed = shift
		event.pressed = pressed
		game.get_viewport().push_input(event)


func _focus(game: VaultGame) -> Control:
	return game.get_viewport().gui_get_focus_owner()


func _stores(game: VaultGame) -> Array:
	return [game.food_system.meals, game.food_system.salvage]


func _test_hidden() -> void:
	var game := _game([])
	if not _guard(game):
		_dispose(game)
		return
	game.new_game(true, 0x0777)
	_assert_false(game.player_orders.briefing_perk_row.visible, "no win yet: no perk row")
	_assert_equal(game.player_orders.perk_choices(), [""], "only NONE")
	game.records_path = ""
	var store := WingRecords.new()
	store.path = _path
	store.record(0x0777, true, 2, 7, 7)
	game.new_game(true, 0x0777)
	_assert_false(game.player_orders.briefing_perk_row.visible, "records off: no perk row even with a 07 win")
	game.records_path = _path
	game.new_game(true, 0)
	_assert_false(game.player_orders.briefing_perk_row.visible, "seed 0: no perk row")
	_dispose(game)
	_clean()


func _test_pick() -> void:
	var game := _game([7])
	if not _guard(game):
		_dispose(game)
		return
	game.new_game(true, 0x0777)
	var orders := game.player_orders
	_assert_true(orders.briefing_perk_row.is_visible_in_tree(), "07 won: the perk row shows")
	_assert_equal(orders.briefing_perk_label.text, "PERK · NONE", "NONE by default")
	_assert_true(orders.briefing_perk_prev_button.disabled and not orders.briefing_perk_next_button.disabled, "◀ disabled at NONE, ▶ enabled")
	orders.briefing_perk_next_button.pressed.emit()
	_assert_equal([game.equipped_perk, game.wing_perk], ["provisioning", "provisioning"], "▶ equips PROVISIONING for this wing")
	_assert_equal(_stores(game), [FoodSystem.STARTING_MEALS + VaultGame.PROVISIONING_MEALS, FoodSystem.STARTING_SALVAGE - VaultGame.PROVISIONING_SALVAGE_COST], "the wing is rebuilt with the perk's start, once")
	_assert_equal(orders.briefing_perk_label.text, "PERK · PROVISIONING: %s" % VaultGame.PERKS["provisioning"].detail, "the row names the perk and its trade")
	_assert_true(orders.briefing_perk_next_button.disabled and not orders.briefing_perk_prev_button.disabled, "▶ disabled at the last perk")
	_assert_true(orders.briefing_overlay.visible and orders.briefing_begin_button.visible, "still the opening briefing")
	orders.briefing_perk_prev_button.pressed.emit()
	_assert_equal([game.equipped_perk, game.wing_perk, _stores(game)], ["", "", [FoodSystem.STARTING_MEALS, FoodSystem.STARTING_SALVAGE]], "◀ returns to NONE with the usual stores")
	_dispose(game)
	_clean()


func _test_focus() -> void:
	var game := _game([7])
	if not _guard(game):
		_dispose(game)
		return
	game.new_game(true, 0x0777)
	var orders := game.player_orders
	_assert_equal(orders._briefing_focus_controls(true), [orders.briefing_begin_button, orders.briefing_deeper_button, orders.briefing_perk_next_button, orders.briefing_load_button], "ring: BEGIN, sublevel ◀, perk ▶, LOAD")
	_assert_equal(_focus(game), orders.briefing_begin_button, "BEGIN SHIFT keeps first focus")
	_key(game, KEY_TAB)
	_key(game, KEY_TAB)
	_assert_equal(_focus(game), orders.briefing_perk_next_button, "Tab twice reaches perk ▶")
	_key(game, KEY_ENTER)
	_assert_equal(game.wing_perk, "provisioning", "Enter on perk ▶ equips PROVISIONING")
	_assert_equal(_focus(game), orders.briefing_perk_prev_button, "▶ is now disabled, so focus moves to perk ◀")
	_assert_equal(orders._briefing_focus_controls(true), [orders.briefing_begin_button, orders.briefing_deeper_button, orders.briefing_perk_prev_button, orders.briefing_load_button], "the ring is rebuilt")
	_key(game, KEY_TAB)
	_assert_equal(_focus(game), orders.briefing_load_button, "Tab from perk ◀ reaches LOAD")
	_key(game, KEY_TAB, true)
	_key(game, KEY_ENTER)
	_assert_equal([game.wing_perk, _focus(game)], ["", orders.briefing_perk_next_button], "Enter on perk ◀: NONE, focus to perk ▶")
	orders.briefing_begin_button.grab_focus()
	orders.briefing_perk_next_button.pressed.emit()
	_assert_equal(game.wing_perk, "provisioning", "a mouse press works too")
	_assert_equal(_focus(game), orders.briefing_begin_button, "and leaves BEGIN SHIFT focused when the arrows had no focus")
	_dispose(game)
	_clean()


func _test_record_line() -> void:
	var game := _game([7])
	if not _guard(game):
		_dispose(game)
		return
	game.new_game(false, 0x0777)
	game.begin_shift()
	game._finish_loss()
	_assert_false(game.player_orders.record_line(false).contains("with "), "a NONE run's line names no perk: %s" % game.player_orders.record_line(false))
	game.equipped_perk = "provisioning"
	game.new_game(false, 0x0777)
	game.begin_shift()
	game._finish_loss()
	_assert_true(game.player_orders.record_line(false).ends_with(" · with PROVISIONING"), "a perk run's line ends with the perk: %s" % game.player_orders.record_line(false))
	_assert_true(game.player_orders.outcome_record.text.contains("with PROVISIONING"), "and the outcome shows it")
	_assert_false(game.best_enabled(), "Best is disabled for this legacy record-only fixture")
	_assert_true(game.player_orders.outcome_record.is_visible_in_tree(), "without Best the original record and perk suffix remain visible")
	var record := game.wing_records().get_record(0x0777)
	_assert_equal(record.keys().size(), 4, "records keep their four fields")
	_dispose(game)
	_clean()


func _test_help_replay() -> void:
	var game := _game([7])
	if not _guard(game):
		_dispose(game)
		return
	game.equipped_perk = "provisioning"
	game.new_game(false, 0x0777)
	game.begin_shift()
	game._finish_loss()
	game.player_orders.replay_wing()
	var orders := game.player_orders
	_assert_equal(game.wing_perk, "provisioning", "REPLAY keeps the perk")
	_assert_false(orders.briefing_load_button.visible, "replay hides LOAD")
	orders.briefing_perk_prev_button.pressed.emit()
	_assert_equal(game.wing_perk, "", "◀ on a replay briefing: NONE")
	_assert_false(orders.briefing_load_button.visible, "LOAD stays hidden after the perk step")
	orders.briefing_begin_button.pressed.emit()
	orders.open_help()
	_assert_false(orders.briefing_perk_row.visible, "HELP hides the perk row")
	_assert_false(orders.briefing_perk_prev_button in orders._briefing_focus_controls(false), "and its arrows leave the ring")
	_dispose(game)
	_clean()
