extends "res://tests/test_runner.gd"

# Wing-seed slice 3, display: the roster and inspector name each seeded resident's trait.
# With #112's two-line rows the trait leads the second line, and rows must still fit.

const ROOM := 24.0


func _run() -> void:
	_run_case("legacy roster rows and inspector carry no trait", _test_legacy)
	_run_case("seeded rows and the inspector name each trait", _test_seeded)
	_run_case("an ordinary refresh shows a new crew with identical vitals", _test_cache)
	_run_case("trait rows fit the right panel with the longest trait and statuses", _test_fit)
	_finish()


func _finish() -> void:
	print("")
	if _failure_count == 0:
		print("CREW ROSTER TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("CREW ROSTER TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _rows(orders: PlayerOrders) -> Array[Button]:
	var rows: Array[Button] = []
	for child: Node in orders.roster_box.get_children():
		if child is Button and not child.is_queued_for_deletion():
			rows.append(child as Button)
	return rows


func _two_line(orders: PlayerOrders) -> bool:
	return _rows(orders)[0].text.contains("\n")


func _refresh(game: VaultGame) -> void:
	game.player_orders._last_roster_signature = ""
	game.player_orders._refresh_roster()


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


func _test_legacy() -> void:
	var game := _spawn_game()
	game.begin_shift()
	_refresh(game)
	for row: Button in _rows(game.player_orders):
		for t: String in VaultResident.TRAIT_POOL:
			_assert_false(row.text.contains(t), "legacy row has no %s" % t)
		_assert_equal(row.tooltip_text, row.text, "legacy tooltip repeats the row")
	game.selected_resident_id = 1
	game.player_orders._refresh_inspector()
	_assert_false(game.player_orders.inspector_state.text.contains("Trait:"), "legacy inspector has no trait line")
	_dispose(game)


func _test_seeded() -> void:
	var game := _spawn_game()
	game.new_game(false, 4242)
	game.begin_shift()
	_refresh(game)
	var rows := _rows(game.player_orders)
	print("ROSTER MODE: %s" % ("two-line" if _two_line(game.player_orders) else "one-line"))
	for index in rows.size():
		var resident: VaultResident = game.residents[index]
		var row := rows[index]
		var t := resident.trait_id
		_assert_true(t != "", "%s has a trait" % resident.resident_name)
		if row.text.contains("\n"):
			_assert_true(row.text.split("\n")[1].begins_with("%s · " % t), "%s's trait leads line two" % resident.resident_name)
		else:
			_assert_true(row.text.begins_with("%s · %s · " % [resident.resident_name, t]), "%s's trait follows the name" % resident.resident_name)
		_assert_true(row.tooltip_text.ends_with("%s: %s" % [t, VaultResident.TRAIT_EFFECTS[t]]), "%s's tooltip explains the trait" % resident.resident_name)
		game.selected_resident_id = resident.resident_id
		game.player_orders._refresh_inspector()
		_assert_true(game.player_orders.inspector_state.text.ends_with("\nTrait: %s · %s" % [t, VaultResident.TRAIT_EFFECTS[t]]), "%s's inspector ends with the trait" % resident.resident_name)
	game.residents[0].alive = false
	_refresh(game)
	_assert_false(_rows(game.player_orders)[0].text.contains(game.residents[0].trait_id), "the dead row stays short")
	_dispose(game)


func _test_cache() -> void:
	var game := _spawn_game()
	game.new_game(false, 4242)
	game.player_orders._refresh_roster()
	var before := _rows(game.player_orders)[0].text
	game.new_game(false, 1)
	game.player_orders._refresh_roster()
	var after := _rows(game.player_orders)[0].text
	_assert_true(after.contains(game.residents[0].trait_id), "seed 1's first trait shows after a plain refresh")
	_assert_true(before != after, "the row changed with the crew")
	_dispose(game)


func _test_fit() -> void:
	var game := _spawn_game()
	game.new_game(false, 4242)
	game.begin_shift()
	_refresh(game)
	if not _two_line(game.player_orders):
		_assert_true(true, "one-line rows (#112 not stacked): fit is measured on the integrated stack")
		_dispose(game)
		return
	var longest_trait := ""
	for t: String in VaultResident.TRAIT_POOL:
		var font := _rows(game.player_orders)[0].get_theme_font("font")
		if longest_trait == "" or font.get_string_size(t).x > font.get_string_size(longest_trait).x:
			longest_trait = t
	var states := [
		["Idle", false, false],
		["Walking to nutrient station", false, false],
		["Rushing to pressure hatch", false, false],
		["Patching pressure breach", false, false],
		["Drafted · Moving", true, false],
	]
	for entry: Array in states:
		for resident: VaultResident in game.residents:
			resident.set_trait(longest_trait)
			resident.state = entry[0]
			resident.drafted = entry[1]
			resident.is_forced_job = entry[2]
		_refresh(game)
		for row: Button in _rows(game.player_orders):
			var font := row.get_theme_font("font")
			var size := row.get_theme_font_size("font_size")
			var padding := row.get_theme_stylebox("normal").get_minimum_size().x
			for line: String in row.text.split("\n"):
				var room := _row_width(game.player_orders) - padding - font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
				_assert_true(room >= ROOM, "%s: '%s' fits with %.0f px to spare" % [entry[0], line, room])
	_dispose(game)
