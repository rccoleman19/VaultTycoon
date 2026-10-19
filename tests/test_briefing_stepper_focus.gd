extends "res://tests/test_runner.gd"

# Codex P3 on #110: the opening briefing's keyboard ring reaches the visible, enabled sublevel arrows,
# keeps BEGIN SHIFT first, leaves a disabled endpoint arrow out, and is rebuilt after every step.

var _path := ""


func _run() -> void:
	_path = "user://test_briefing_stepper_focus_%d.json" % OS.get_process_id()
	_run_case("NEW WING at 06: Tab and arrows reach ▶ and Enter on it returns to 07", _test_new_wing_06)
	_run_case("REPLAY WING at 06: the LOAD-less ring still reaches ▶", _test_replay_06)
	_run_case("at 07 the disabled ▶ is out of the ring and ◀ is in", _test_endpoint_07)
	_run_case("the ring is rebuilt after each step and focus stays on the stepper", _test_rewire_after_step)
	_run_case("BEGIN SHIFT keeps first focus and HELP keeps its CLOSE/LOAD ring", _test_primary_and_help)
	print("")
	if _failure_count == 0:
		print("BRIEFING STEPPER FOCUS TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("BRIEFING STEPPER FOCUS TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
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


# Names the focus owner after each of `count` presses, e.g. ["▶", "LOAD", "BEGIN SHIFT"].
func _walk(game: VaultGame, keycode: Key, count: int, shift := false) -> Array:
	var seen := []
	for index in count:
		_key(game, keycode, shift)
		var owner := _focus(game)
		seen.append((owner as Button).text if owner is Button else str(owner))
	return seen


# Every Tab/arrow link of every ring member stays on a visible, enabled briefing button.
func _ring_links_ok(orders: PlayerOrders) -> bool:
	var ring := orders._briefing_focus_controls(orders._briefing_is_opening)
	for control: Control in ring:
		for neighbor_path: NodePath in [control.focus_previous, control.focus_next, control.focus_neighbor_left, control.focus_neighbor_top, control.focus_neighbor_right, control.focus_neighbor_bottom]:
			var neighbor := control.get_node_or_null(neighbor_path) as Button
			if neighbor == null or not neighbor.is_visible_in_tree() or neighbor.disabled or not neighbor in ring:
				return false
	return true


func _test_new_wing_06() -> void:
	var game := _game([7])
	game.new_wing()
	var orders := game.player_orders
	_assert_equal(game.sublevel, 6, "07 won: NEW WING starts on 06")
	_assert_true(orders.briefing_shallower_button.is_visible_in_tree() and not orders.briefing_shallower_button.disabled, "▶ is visible and enabled")
	_assert_true(orders.briefing_deeper_button.disabled, "◀ is disabled at the deepest unlocked")
	_assert_equal(_focus(game), orders.briefing_begin_button, "BEGIN SHIFT has first focus")
	_assert_equal(_walk(game, KEY_TAB, 3), ["▶", "LOAD", "BEGIN SHIFT"], "Tab: BEGIN → ▶ → LOAD → BEGIN")
	_assert_equal(_walk(game, KEY_TAB, 3, true), ["LOAD", "▶", "BEGIN SHIFT"], "Shift-Tab walks it backwards")
	_assert_equal(_walk(game, KEY_RIGHT, 1), ["▶"], "→ from BEGIN reaches ▶")
	_assert_equal(_walk(game, KEY_LEFT, 1), ["BEGIN SHIFT"], "← returns to BEGIN")
	_assert_equal(_walk(game, KEY_DOWN, 1), ["▶"], "↓ from BEGIN reaches ▶")
	_assert_true(_ring_links_ok(orders), "every ring link stays on an enabled briefing button")
	_assert_equal(_focus(game), orders.briefing_shallower_button, "▶ focused")
	_key(game, KEY_ENTER)
	_assert_equal(game.sublevel, 7, "Enter on ▶ goes 06 → 07")
	_assert_true(orders.briefing_overlay.visible and orders.briefing_begin_button.visible, "still the opening briefing")
	_dispose(game)
	_clean()


func _test_replay_06() -> void:
	var game := _game([7])
	game.new_game(false, 0x0777, 6)
	game.begin_shift()
	game._finish_loss()
	game.player_orders.replay_wing()
	var orders := game.player_orders
	_assert_equal(game.sublevel, 6, "replay keeps 06")
	_assert_false(orders.briefing_load_button.visible, "replay hides LOAD")
	_assert_equal(_focus(game), orders.briefing_begin_button, "BEGIN SHIFT has first focus")
	_assert_equal(_walk(game, KEY_TAB, 2), ["▶", "BEGIN SHIFT"], "Tab: BEGIN ↔ ▶ without LOAD")
	_assert_equal(_walk(game, KEY_TAB, 1, true), ["▶"], "Shift-Tab reaches ▶ too")
	_assert_true(_ring_links_ok(orders), "every ring link stays on an enabled briefing button")
	_key(game, KEY_ENTER)
	_assert_equal(game.sublevel, 7, "Enter on ▶ goes 06 → 07")
	_assert_false(orders.briefing_load_button.visible, "LOAD stays hidden after the step")
	_assert_equal(_focus(game), orders.briefing_deeper_button, "07 disables ▶, so focus moves to ◀")
	_dispose(game)
	_clean()


func _test_endpoint_07() -> void:
	var game := _game([7])
	game.new_game(true, 0x0777)
	var orders := game.player_orders
	_assert_equal(game.sublevel, 7, "07 opening")
	_assert_true(orders.briefing_sublevel_row.visible, "stepper shows (06 unlocked)")
	_assert_true(orders.briefing_shallower_button.disabled, "▶ is disabled at 07")
	var ring := orders._briefing_focus_controls(true)
	_assert_false(orders.briefing_shallower_button in ring, "disabled ▶ is not in the ring")
	_assert_equal(ring, [orders.briefing_begin_button, orders.briefing_deeper_button, orders.briefing_load_button], "ring is BEGIN, ◀, LOAD")
	_assert_true(_ring_links_ok(orders), "no ring link points at the disabled ▶")
	_assert_equal(_walk(game, KEY_TAB, 3), ["◀", "LOAD", "BEGIN SHIFT"], "Tab never lands on the disabled ▶")
	_assert_equal(_walk(game, KEY_RIGHT, 2), ["◀", "LOAD"], "arrows skip it too")
	_dispose(game)
	_clean()


func _test_rewire_after_step() -> void:
	var game := _game([7, 6])
	game.new_wing()
	var orders := game.player_orders
	_assert_equal(game.sublevel, 5, "07 and 06 won: starts on 05")
	_assert_equal(_walk(game, KEY_TAB, 1), ["▶"], "Tab reaches ▶ (◀ disabled at 05)")
	_key(game, KEY_ENTER)
	_assert_equal(game.sublevel, 6, "Enter on ▶: 05 → 06")
	_assert_equal(_focus(game), orders.briefing_shallower_button, "focus stays on ▶")
	_assert_equal(orders._briefing_focus_controls(true), [orders.briefing_begin_button, orders.briefing_deeper_button, orders.briefing_shallower_button, orders.briefing_load_button], "06 ring: BEGIN, ◀, ▶, LOAD")
	_assert_true(_ring_links_ok(orders), "06 ring links are rebuilt")
	_assert_equal(_walk(game, KEY_TAB, 4), ["LOAD", "BEGIN SHIFT", "◀", "▶"], "Tab walks the four-button ring")
	_key(game, KEY_ENTER)
	_assert_equal(game.sublevel, 7, "Enter on ▶: 06 → 07")
	_assert_equal(_focus(game), orders.briefing_deeper_button, "▶ disabled at 07, focus moves to ◀")
	_assert_false(orders.briefing_shallower_button in orders._briefing_focus_controls(true), "07 ring drops ▶")
	_assert_true(_ring_links_ok(orders), "07 ring links are rebuilt")
	_assert_equal(_walk(game, KEY_TAB, 1, true), ["BEGIN SHIFT"], "Shift-Tab from ◀ goes to BEGIN, not the disabled ▶")
	_assert_equal(_walk(game, KEY_TAB, 1), ["◀"], "Tab back to ◀")
	_key(game, KEY_ENTER)
	_assert_equal(game.sublevel, 6, "Enter on ◀: 07 → 06")
	_assert_equal(_focus(game), orders.briefing_deeper_button, "◀ still enabled at 06, focus stays")
	_key(game, KEY_ENTER)
	_assert_equal(game.sublevel, 5, "Enter on ◀: 06 → 05")
	_assert_equal(_focus(game), orders.briefing_shallower_button, "◀ disabled at 05, focus moves to ▶")
	_assert_false(orders.briefing_deeper_button in orders._briefing_focus_controls(true), "05 ring drops ◀")
	_assert_true(_ring_links_ok(orders), "05 ring links are rebuilt")
	_dispose(game)
	_clean()


func _test_primary_and_help() -> void:
	var game := _game([7, 6])
	game.new_wing()
	var orders := game.player_orders
	orders.briefing_shallower_button.pressed.emit()
	_assert_equal(game.sublevel, 6, "a mouse-style press steps to 06")
	_assert_equal(_focus(game), orders.briefing_begin_button, "a press without stepper focus leaves BEGIN SHIFT focused")
	_assert_equal(orders._briefing_focus_controls(true)[0], orders.briefing_begin_button, "BEGIN SHIFT leads the ring")
	_key(game, KEY_ENTER)
	_assert_false(orders.briefing_overlay.visible, "Enter on first focus still begins the shift")
	_assert_equal(game.sublevel, 6, "the shift began on 06")
	orders.open_help()
	_assert_false(orders.briefing_sublevel_row.visible, "HELP hides the stepper")
	_assert_equal(orders._briefing_focus_controls(false), [orders.briefing_close_button, orders.briefing_load_button], "HELP ring is still CLOSE, LOAD")
	_assert_equal(_focus(game), orders.briefing_close_button, "HELP focuses CLOSE")
	_assert_equal(_walk(game, KEY_TAB, 2), ["LOAD", "CLOSE [ESC]"], "HELP Tab ring unchanged")
	_dispose(game)
	_clean()
