extends "res://tests/test_runner.gd"

var _separator_wraps := 0
var _same_line_separators := 0


func _run() -> void:
	await _frame_case("zero, one, two, three and many real alerts count clauses beyond the visible cap", _test_counts)
	_run_case("the bar uses the existing urgency order, including changing deadlines", _test_order)
	await _frame_case("busy real scene stays within two rendered lines at 1280x720", _test_layout)
	await _frame_case("countdown ticks preserve text width and wrapping", _test_countdown)
	await _frame_case("CRITICAL: Bo and internal dots never split across rendered lines", _test_clause_boundaries)
	await _frame_case("an overwide second clause folds into +N and DETAILS", _test_fold)
	await _frame_case("a second clause that needs a third line folds too", _test_line_budget)
	await _frame_case("the theme font stays fixed through refresh and resize", _test_fixed_font)
	await _frame_case("rendered separators stay between whole clauses across alert sets and widths", _test_separator_matrix)
	print("ALERT LINE CAP TESTS: %s — %d cases, %d assertions, %d failures" % [
		"FAIL" if _failure_count else "PASS", _case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _frame_case(case_name: String, test: Callable) -> void:
	_case_count += 1
	_current_case = case_name
	var before := _failure_count
	print("[TEST] %s" % case_name)
	await test.call()
	if before == _failure_count:
		print("[PASS] %s" % case_name)
	else:
		_failed_case_count += 1


func _layout() -> void:
	for frame in 4:
		await process_frame


func _game() -> VaultGame:
	root.size = Vector2i(1280, 720)
	var game := _spawn_game()
	game.begin_shift()
	game.user_paused = true
	# Keep layout running while each test controls the exact displayed alert state.
	game.set_process(false)
	game.food_system.meals = 24
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.health = 100.0
		resident.needs.mood = 100.0
	return game


func _busy() -> VaultGame:
	var game := _game()
	game.food_system.meals = 0
	game.residents[0].needs.rest = 0.0
	game.residents[0].needs.health = 10.0
	game.residents[1].needs.health = 70.0
	game.residents[2].needs.mood = 10.0
	game.residents[3].drafted = true
	for resident: VaultResident in game.residents:
		resident.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
	game.oxygen_system.oxygen = 10.0
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.breach_system.advance(0.0, game.breach_system.warning_at + 10.0)
	game.player_orders._refresh_alerts({})
	return game


func _assert_bar(orders: PlayerOrders, context: String) -> void:
	var alerts := orders.alert_list
	var hidden := orders.alert_hidden_count
	var shown := alerts.size() - hidden
	_assert_true(shown == mini(2, alerts.size()) or (shown == 1 and alerts.size() >= 2),
		"%s: the first clause always shows, with at most two alerts" % context)
	var expected := "  ·  ".join(alerts.slice(0, shown))
	if hidden > 0:
		expected += "  ·  +%d more" % hidden
	if alerts.is_empty():
		expected = "STATUS NOMINAL" if orders.all_alerts.is_empty() else "SEE NEXT"
	_assert_equal(orders.alert_label.text.replace("\u00a0", " ").replace("\n", "  ·  "), expected, "%s: exact leading clauses and +%d more" % [context, hidden])
	_assert_equal(orders.alert_more_label.text, "\n".join(alerts.slice(shown)), "%s: DETAILS contains exactly the dropped clauses" % context)


func _test_counts() -> void:
	var game := _game()
	var orders := game.player_orders
	orders._refresh_alerts({})
	_assert_equal(orders.all_alerts.size(), 0, "healthy fixture is nominal")
	_assert_bar(orders, "nominal")
	for count in [1, 2, 3, 5]:
		match count:
			1:
				for resident: VaultResident in game.residents:
					resident.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
			2:
				game.residents[1].needs.health = 70.0
			3:
				game.residents[0].needs.rest = 25.0
			5:
				game.residents[2].needs.mood = 30.0
		orders._refresh_alerts({})
		_assert_equal(orders.alert_list.size(), count, "fixture generates %d actual clauses" % count)
		await _layout()
		_assert_true(orders.alert_hidden_count >= maxi(0, count - 2), "the bar shows no more than two clauses")
		_assert_bar(orders, "%d clauses" % count)
	_set_clauses(orders, ["OXYGEN LOW", "LOW MEALS", "NO COOK ENABLED"])
	await _layout()
	_assert_equal(orders.alert_hidden_count, 1, "two fitting clauses stay visible alongside +1 more")
	_assert_layout(orders, "short clauses retain two-alert cap")
	_dispose(game)


func _test_order() -> void:
	var game := _busy()
	var orders := game.player_orders
	_assert_true(orders.alert_list.size() >= 5, "busy state generates at least five clauses")
	_assert_equal(orders.all_alerts, orders._order_alerts_by_urgency(orders.all_alerts), "generated order agrees with existing #120 triage")
	_assert_equal(orders.alert_list[0], "OXYGEN CRITICAL", "zero-second oxygen threat leads")
	_assert_bar(orders, "critical oxygen")
	game.food_system.meals = 24
	game.oxygen_system.oxygen = 30.0
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	orders._refresh_alerts({})
	_assert_true(orders.alert_list[0].begins_with("SEAL WARNING"), "hatch deadline now leads the longer death runways")
	_assert_equal(orders.all_alerts, orders._order_alerts_by_urgency(orders.all_alerts), "changed deadlines still use existing triage")
	_assert_bar(orders, "hatch first")
	# Exercise the normal refresh path and its existing Next suppression too.
	orders.refresh()
	var expected: Array[String] = []
	for alert: String in orders._order_alerts_by_urgency(orders.all_alerts):
		if not orders._alert_stated_by_next(alert, orders._displayed_next_step):
			expected.append(alert)
	_assert_equal(orders.alert_list, expected, "normal scene refresh filters Next after triage")
	_assert_bar(orders, "normal refresh")
	_dispose(game)


func _assert_layout(orders: PlayerOrders, context: String) -> void:
	var label := orders.alert_label
	_assert_equal(root.get_visible_rect().size, Vector2(1280, 720), "layout uses the actual 1280x720 viewport")
	_assert_true(label.is_visible_in_tree() and label.size.x > 200.0, "real pinned label is visible and laid out")
	_assert_true(label.get_line_count() <= 2, "%s: real font renders %d lines: %s" % [context, label.get_line_count(), label.text])
	_assert_equal(label.get_visible_line_count(), label.get_line_count(), "all lines remain visible without clipping")
	_assert_equal(label.max_lines_visible, -1, "line limit is achieved without hiding overflow")
	_assert_false(label.has_theme_font_size_override("font_size"), "%s: no font size override" % context)
	_assert_equal(label.get_theme_font_size("font_size"), label.get_theme_default_font_size(), "%s: theme default font size" % context)
	_assert_whole_lines(orders, context)
	_assert_bar(orders, context)


func _test_layout() -> void:
	var game := _busy()
	var orders := game.player_orders
	await _layout()
	_assert_layout(orders, "many threats")
	# Long clauses must fit too: remove timed threats so drafted/medical advice
	# leads, while all the unrelated bed, mood and cook alerts remain active.
	game.oxygen_system.oxygen = 100.0
	game.breach_system.phase = BreachSystem.Phase.SEALED
	game.food_system.meals = 24
	game.residents[0].needs.rest = 25.0
	game.residents[0].needs.health = 100.0
	for resident: VaultResident in game.residents:
		resident.set_work_priority("cook", VaultResident.DEFAULT_WORK_PRIORITY)
	orders._refresh_alerts({})
	_assert_true(orders.alert_list.size() >= 5, "long-clause state still generates at least five clauses")
	await _layout()
	_assert_layout(orders, "long drafted and bed clauses")
	_dispose(game)


func _width(label: Label) -> float:
	return label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, label.get_theme_font_size("font_size")).x


func _test_countdown() -> void:
	var game := _game()
	var orders := game.player_orders
	game.residents[1].needs.health = 70.0
	game.residents[2].needs.mood = 30.0
	for pair: Array in [[10, 9], [100, 99], [60, 59]]:
		var before_text := ""
		var before_width := 0.0
		var before_lines := 0
		for seconds: int in pair:
			# The real breach clock supplies the countdown; a longer warning window
			# covers the 100 -> 99 boundary without changing simulation code.
			game.breach_system.warning_at = 200.0
			game.breach_system.phase = BreachSystem.Phase.WARNING
			game.breach_system.advance(0.0, game.breach_system.get_open_at() - seconds)
			orders._refresh_alerts({})
			await _layout()
			_assert_true(orders.alert_label.text.replace("\u00a0", " ").begins_with("SEAL WARNING · "), "the ticking field is visible")
			var expected_time := "%02d:%02d" % [seconds / 60, seconds % 60]
			_assert_true(expected_time in orders.alert_label.text, "countdown keeps padded MM:SS: %s" % expected_time)
			_assert_layout(orders, "%ds remaining" % seconds)
			if not before_text.is_empty():
				_assert_true(orders.alert_label.text != before_text, "the countdown actually ticks")
				_assert_equal(orders.alert_label.text.length(), before_text.length(), "tick preserves character count")
				_assert_approximately(_width(orders.alert_label), before_width, 0.001, "tick preserves real font width")
				_assert_equal(orders.alert_label.get_line_count(), before_lines, "tick preserves wrap")
			before_text = orders.alert_label.text
			before_width = _width(orders.alert_label)
			before_lines = orders.alert_label.get_line_count()
	_dispose(game)


# Shape the real label's text with its actual font, width and wrap policy. The
# paragraph exposes the rendered line ranges that Label itself does not expose.
func _assert_whole_lines(orders: PlayerOrders, context: String) -> void:
	var label := orders.alert_label
	var paragraph := TextParagraph.new()
	paragraph.width = label.size.x
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | label.autowrap_trim_flags
	if label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART:
		paragraph.break_flags |= TextServer.BREAK_ADAPTIVE
	paragraph.add_string(label.text, label.get_theme_font("font"), label.get_theme_font_size("font_size"))
	_assert_equal(paragraph.get_line_count(), label.get_line_count(), "%s: line ranges match the real label" % context)
	var clauses := orders.alert_list.slice(0, orders.alert_list.size() - orders.alert_hidden_count)
	if orders.alert_hidden_count > 0:
		clauses.append("+%d more" % orders.alert_hidden_count)
	if clauses.is_empty():
		clauses.append("STATUS NOMINAL" if orders.all_alerts.is_empty() else "SEE NEXT")
	var plain := label.text.replace("\u00a0", " ")
	var cursor := 0
	for clause: String in clauses:
		var start := plain.find(clause, cursor)
		_assert_true(start >= 0, "%s: whole clause is present: %s" % [context, clause])
		if start < 0:
			continue
		var end := start + clause.length()
		for line in paragraph.get_line_count():
			var span := paragraph.get_line_range(line)
			_assert_false(span.x > start and span.x < end, "%s: line %d starts inside %s" % [context, line, clause])
			_assert_false(span.y > start and span.y < end, "%s: line %d ends inside %s" % [context, line, clause])
		cursor = end
	for line in paragraph.get_line_count():
		var span := paragraph.get_line_range(line)
		var rendered := plain.substr(span.x, span.y - span.x).strip_edges()
		_assert_false(rendered.begins_with("·"), "%s: rendered line %d starts without a separator: %s" % [context, line, rendered])
		_assert_false(rendered.ends_with("·"), "%s: rendered line %d ends without a separator: %s" % [context, line, rendered])
		var on_line: Array[String] = []
		cursor = 0
		for clause: String in clauses:
			var start := plain.find(clause, cursor)
			if start >= span.x and start + clause.length() <= span.y:
				on_line.append(clause)
			cursor = start + clause.length()
		_assert_equal(rendered, "  ·  ".join(on_line), "%s: rendered line %d retains separators exactly between its clauses" % [context, line])
		_same_line_separators += maxi(0, on_line.size() - 1)
	_separator_wraps += maxi(0, paragraph.get_line_count() - 1)


func _set_clauses(orders: PlayerOrders, clauses: Array[String]) -> void:
	# Presentation-only fixture; call the same existing fit hook on the real rail.
	# Also works on the baseline implementation, without calling new methods.
	orders.alert_list.assign(clauses)
	orders.all_alerts.assign(clauses)
	orders.alert_hidden_count = maxi(0, clauses.size() - 2)
	orders.alert_label.text = "  ·  ".join(clauses.slice(0, 2))
	if orders.alert_hidden_count > 0:
		orders.alert_label.text += "  ·  +%d more" % orders.alert_hidden_count
	orders._fit_alert_line()
	orders._refresh_alert_details()


func _test_clause_boundaries() -> void:
	var game := _game()
	var orders := game.player_orders
	await _layout()
	var label := orders.alert_label
	var font := label.get_theme_font("font")
	var size := label.get_theme_default_font_size()
	# Leave room for CRITICAL: but not Bo: this reproduces the reviewed split.
	var first := "OXYGEN"
	while font.get_string_size(first + "W  ·  CRITICAL: Bo", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= label.size.x:
		first += "W"
	_assert_true(font.get_string_size(first + "  ·  CRITICAL:", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= label.size.x,
		"fixture leaves room for CRITICAL: but not its name")
	_set_clauses(orders, [first, "CRITICAL: Bo"])
	await _layout()
	_assert_layout(orders, "reviewed CRITICAL: Bo boundary")
	_assert_equal(orders.alert_hidden_count, 0, "two short whole clauses remain visible")
	# A first clause wider than the rail still shows as one indivisible unit.
	_set_clauses(orders, ["DRAFTED CREW 123 · AUTO WORK PAUSED UNTIL UNDRAFTED"])
	await _layout()
	_assert_layout(orders, "overwide first with internal dot")
	_assert_equal(orders.alert_hidden_count, 0, "the first clause is never folded")
	_dispose(game)


func _test_fold() -> void:
	var game := _busy()
	var orders := game.player_orders
	game.residents[0].resident_name = "Ari With A Very Long Resident Name"
	game.residents[0].needs.food = 0.0
	game.residents[0].drafted = true
	game.food_system.meals = 24
	orders._refresh_alerts({})
	await _layout()
	_assert_equal(orders.alert_list[0], "OXYGEN CRITICAL", "the most urgent real alert stays first")
	_assert_true(orders.alert_list[1].begins_with("CRITICAL: Ari"), "the second real alert uses the long resident name")
	var font := orders.alert_label.get_theme_font("font")
	_assert_true(font.get_string_size(orders.alert_list[1], HORIZONTAL_ALIGNMENT_LEFT, -1,
		orders.alert_label.get_theme_default_font_size()).x > orders.alert_label.size.x, "second clause is wider than the real rail")
	_assert_equal(orders.alert_hidden_count, orders.alert_list.size() - 1, "folding increments +N by one")
	_assert_equal(orders.alert_label.text.replace("\u00a0", " ").replace("\n", "  ·  "), "OXYGEN CRITICAL  ·  +%d more" % (orders.alert_list.size() - 1),
		"line shows first clause plus the incremented whole +N more")
	orders._toggle_details_rail()
	await _layout()
	_assert_true(orders.alert_more_label.is_visible_in_tree(), "DETAILS visibly expands the hidden list")
	_assert_true(orders.alert_more_label.text.begins_with(orders.alert_list[1] + "\n"), "DETAILS starts with the folded second clause")
	_assert_layout(orders, "folded real second clause")
	# Resize refits the existing clauses without a simulation refresh.
	var panel := orders.alert_label.get_parent().get_parent().get_parent().get_parent() as Control
	panel.offset_left = -600.0
	await _layout()
	_assert_equal(orders.alert_hidden_count, orders.alert_list.size() - 2, "a wider rail restores the second clause")
	_assert_bar(orders, "wider rail restores DETAILS offset")
	panel.offset_left = -VaultGame.RIGHT_PANEL_WIDTH
	await _layout()
	_assert_equal(orders.alert_hidden_count, orders.alert_list.size() - 1, "restoring the real rail width folds it again")
	_assert_layout(orders, "refold after resize")
	_dispose(game)


func _test_line_budget() -> void:
	var game := _game()
	var orders := game.player_orders
	await _layout()
	var label := orders.alert_label
	var font := label.get_theme_font("font")
	var size := label.get_theme_default_font_size()
	var clause := "ALERT"
	while font.get_string_size(clause + "W", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= label.size.x:
		clause += "W"
	_set_clauses(orders, [clause, clause, "NO COOK ENABLED"])
	await _layout()
	_assert_true(font.get_string_size(clause, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= label.size.x,
		"each candidate clause fits individually")
	_assert_equal(orders.alert_hidden_count, 2, "second clause folds when +N would need a third line")
	_assert_equal(orders.alert_label.text.replace("\u00a0", " ").replace("\n", "  ·  "), clause + "  ·  +2 more", "two-line budget preserves the first and suffix")
	_assert_layout(orders, "third-line budget")
	_dispose(game)


func _test_fixed_font() -> void:
	var game := _game()
	var orders := game.player_orders
	var label := orders.alert_label
	var expected_size := label.get_theme_default_font_size()
	var panel := label.get_parent().get_parent().get_parent().get_parent() as Control
	for width in [VaultGame.RIGHT_PANEL_WIDTH, 600, VaultGame.RIGHT_PANEL_WIDTH]:
		panel.offset_left = -width
		orders._refresh_alerts({})
		await _layout()
		_assert_false(label.has_theme_font_size_override("font_size"), "nominal refresh/resize never overrides font size")
		_set_clauses(orders, ["DRAFTED CREW 123 · AUTO WORK PAUSED", "HATCH RESPONSE EXCLUDES DRAFTED CREW", "NO COOK ENABLED"])
		await _layout()
		_assert_false(label.has_theme_font_size_override("font_size"), "crowded refresh/resize never overrides font size")
		_assert_equal(label.get_theme_font_size("font_size"), expected_size, "crowded text keeps the inherited font size")
	_dispose(game)


func _test_separator_matrix() -> void:
	var game := _game()
	var orders := game.player_orders
	var label := orders.alert_label
	var panel := label.get_parent().get_parent().get_parent().get_parent() as Control
	var alert_sets: Array[Array] = [
		[], ["OXYGEN LOW"], ["OXYGEN LOW", "LOW MEALS"],
		["OXYGEN CRITICAL", "CRITICAL: Bo"],
		["SEAL WARNING · 00:09", "LOW MEALS", "NO COOK ENABLED"],
		["CRITICAL: Ari With A Very Long Resident Name", "LOW MEALS", "NO COOK ENABLED"],
		["DRAFTED CREW 1 · AUTO WORK PAUSED", "HATCH RESPONSE EXCLUDES DRAFTED CREW"],
		["LOW MEALS", "NO COOK ENABLED", "LOW MOOD: Bo", "BEDS NEEDED 2", "OXYGEN LOW"],
		["LOW MEALS", "LOW MOOD: Bo", "BEDS NEEDED 2", "NO COOK ENABLED", "OXYGEN LOW",
			"CRITICAL: Ari", "REST LOW", "MEDICAL", "POWER LOW", "HATCH OPEN", "DRAFTED CREW 1", "COOKING PAUSED"],
	]
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var before_wraps := _separator_wraps
	var before_same_line := _same_line_separators
	var combinations := 0
	for width in [310, 330, 360, 400, 450, 500, 600, 800]:
		panel.offset_left = -width
		await _layout()
		# Bracket the separator's own width, so it can fit before a wrap,
		# fail to fit, or have the next clause land exactly on the boundary.
		var first := "ALERT"
		while font.get_string_size(first + "W  ·  ", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= label.size.x:
			first += "W"
		var sets := alert_sets.duplicate()
		sets.append([first, "CRITICAL: Bo"])
		sets.append([first + "WW", "CRITICAL: Bo", "NO COOK ENABLED"])
		sets.append(["LOW MEALS", first, "NO COOK ENABLED"])
		for index in sets.size():
			var clauses: Array[String] = []
			clauses.assign(sets[index])
			_set_clauses(orders, clauses)
			if clauses.is_empty():
				orders._refresh_alerts({})
			await _layout()
			var context := "panel %d / set %d / rail %.1f" % [width, index, label.size.x]
			_assert_whole_lines(orders, context)
			_assert_bar(orders, context)
			_assert_true(label.get_line_count() <= 2, "%s: retains the two-line budget" % context)
			_assert_equal(label.get_visible_line_count(), label.get_line_count(), "%s: rendered lines are visible" % context)
			_assert_equal(label.autowrap_mode, TextServer.AUTOWRAP_WORD, "%s: whole-word wrapping stays enabled" % context)
			combinations += 1
	_assert_equal(combinations, 96, "matrix covers twelve alert sets at eight real rail widths")
	_assert_true(_separator_wraps - before_wraps >= 20, "matrix exercises many actual rendered wraps")
	_assert_true(_same_line_separators - before_same_line >= 20, "matrix exercises many same-line clause separators")
	print("SEPARATOR MATRIX: %d layouts, %d rendered wraps, %d same-line separators" % [
		combinations, _separator_wraps - before_wraps, _same_line_separators - before_same_line])
	_dispose(game)
