extends "res://tests/test_runner.gd"

# Resident roster rows fit the right panel (QA 2026-10-18c #8).

const ROOM := 24.0


func _run() -> void:
	_run_case("a fresh wing's roster rows fit with room to spare", _test_fresh_rows)
	_run_case("the longest realistic vitals and statuses fit", _test_worst_rows)
	_run_case("stacked command flags wrap instead of clipping", _test_stacked_flags_wrap)
	_run_case("rows still say who, how they are and what they do", _test_row_content)

	print("")
	if _failure_count == 0:
		print("ROSTER FIT TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("ROSTER FIT TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
			_failed_case_count,
			_case_count,
			_failure_count,
			_assertion_count,
		])
		quit(1)


# Tests run without frames, so containers are not laid out. Derive the row
# width from the right panel's default width minus every ancestor's padding,
# and assume the roster's scroll bar is showing.
func _row_width(orders: PlayerOrders) -> float:
	var width := VaultGame.RIGHT_PANEL_WIDTH
	var node: Node = orders.roster_box.get_parent()
	while node is Control:
		if node is PanelContainer:
			width -= (node as PanelContainer).get_theme_stylebox("panel").get_minimum_size().x
			break
		if node is MarginContainer:
			width -= (node as Control).get_theme_constant("margin_left") + (node as Control).get_theme_constant("margin_right")
		if node is ScrollContainer:
			width -= (node as ScrollContainer).get_v_scroll_bar().get_combined_minimum_size().x
		node = node.get_parent()
	return width


func _rows(orders: PlayerOrders) -> Array[Button]:
	var rows: Array[Button] = []
	for child: Node in orders.roster_box.get_children():
		if child is Button and not child.is_queued_for_deletion():
			rows.append(child as Button)
	return rows


func _assert_rows_fit(orders: PlayerOrders, context: String) -> void:
	var rows := _rows(orders)
	_assert_true(not rows.is_empty(), "%s: roster has rows" % context)
	for row: Button in rows:
		var font := row.get_theme_font("font")
		var size := row.get_theme_font_size("font_size")
		var padding := row.get_theme_stylebox("normal").get_minimum_size().x
		for line: String in row.text.split("\n"):
			var room := _row_width(orders) - padding - font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			_assert_true(room >= ROOM, "%s: '%s' fits with %.0f px to spare" % [context, line, room])


func _game() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	game.player_orders._last_roster_signature = ""
	game.player_orders._refresh_roster()
	return game


func _refresh(game: VaultGame) -> void:
	game.player_orders._last_roster_signature = ""
	game.player_orders._refresh_roster()


func _test_fresh_rows() -> void:
	var game := _game()
	_assert_equal(_rows(game.player_orders).size(), game.residents.size(), "one row per resident")
	_assert_rows_fit(game.player_orders, "fresh wing")
	_dispose(game)


func _test_worst_rows() -> void:
	var game := _game()
	# Every resident takes the longest name the game hands out.
	var longest := ""
	for resident: VaultResident in game.residents:
		if resident.resident_name.length() > longest.length():
			longest = resident.resident_name
	var states := [
		["Walking to nutrient station", false, false],
		["Walking to nutrient station", false, true],
		["Rushing to pressure hatch", false, true],
		["Drafted · Move blocked", true, false],
		["Drafted · Moving", true, false],
	]
	for entry: Array in states:
		for resident: VaultResident in game.residents:
			resident.resident_name = longest
			resident.needs.health = 100.0
			resident.needs.mood = 100.0
			resident.needs.food = 100.0
			resident.needs.rest = 100.0
			resident.state = entry[0]
			resident.drafted = entry[1]
			resident.is_forced_job = entry[2]
		_refresh(game)
		_assert_rows_fit(game.player_orders, "%s%s%s" % ["DRAFTED " if entry[1] else "", "FORCED " if entry[2] else "", entry[0]])
	game.residents[0].alive = false
	_refresh(game)
	_assert_rows_fit(game.player_orders, "deceased")
	_dispose(game)


func _test_stacked_flags_wrap() -> void:
	var game := _game()
	_refresh(game)
	for row: Button in _rows(game.player_orders):
		_assert_false(row.clip_text, "rows never clip")
		_assert_equal(row.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "rows wrap a rare long status")
		_assert_equal(row.get_theme_font_size("font_size"), PlayerOrders.ROSTER_FONT_SIZE, "rows use the roster font size")
	_dispose(game)


func _test_row_content() -> void:
	var game := _game()
	var resident: VaultResident = game.residents[1]
	resident.needs.health = 63.4
	resident.needs.mood = 32.9
	resident.needs.food = 20.2
	resident.state = "Collecting meal"
	_refresh(game)
	var row: Button = _rows(game.player_orders)[1]
	_assert_equal(row.text, "%s · HP 63 · MOOD 32 · LOW 20\nCollecting meal" % resident.resident_name, "vitals line, then status line")
	_assert_equal(row.tooltip_text, row.text, "the tooltip repeats the row")
	resident.alive = false
	_refresh(game)
	row = _rows(game.player_orders)[1]
	_assert_equal(row.text, "%s · DECEASED" % resident.resident_name, "the dead keep one short line")
	_assert_true(row.disabled, "and are not clickable")
	_dispose(game)
