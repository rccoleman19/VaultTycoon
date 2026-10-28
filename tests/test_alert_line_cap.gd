extends "res://tests/test_runner.gd"


func _run() -> void:
	_run_case("zero, one, two, three and many real alerts count only clauses beyond two", _test_counts)
	_run_case("the bar uses the existing urgency order, including changing deadlines", _test_order)
	await _frame_case("busy real scene stays within two rendered lines at 1280x720", _test_layout)
	await _frame_case("countdown ticks preserve text width and wrapping", _test_countdown)
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
	var hidden := maxi(0, alerts.size() - 2)
	var expected := "  ·  ".join(alerts.slice(0, 2))
	if hidden > 0:
		expected += "  ·  +%d more" % hidden
	if alerts.is_empty():
		expected = "STATUS NOMINAL" if orders.all_alerts.is_empty() else "SEE NEXT"
	_assert_equal(orders.alert_label.text, expected, "%s: exact first two clauses and +%d more" % [context, hidden])
	_assert_equal(orders.alert_hidden_count, hidden, "%s: hidden count excludes the two shown" % context)
	_assert_equal(orders.alert_more_label.text, "\n".join(alerts.slice(2)), "%s: DETAILS contains exactly the dropped clauses" % context)


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
		_assert_bar(orders, "%d clauses" % count)
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
			_assert_true(orders.alert_label.text.begins_with("SEAL WARNING · "), "the ticking field is visible")
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
