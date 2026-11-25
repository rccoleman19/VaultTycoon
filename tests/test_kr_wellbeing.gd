extends "res://tests/test_runner.gd"

# After the win residents seek the Rec Console at 45 (before MOOD STRESSED at < 40), and while the
# comfort card is available Next points at it, even over a latched Rec or Med step.
# Post-win MOOD STRESSED is a warning; other danger alerts and pre-win colors stay red.


func _run() -> void:
	_run_case("the Rec Console seek threshold is 45 only while the won vault keeps running", _test_threshold)
	_run_case("a resident at mood 42 takes a free console after the win, not before", _test_seek_job)
	_run_case("Next points at the comfort card over Rec/Med steps; life support still leads", _test_comfort_next)
	_run_case("post-win stress alone is amber on the alert line and DETAILS", _test_stress_warning_colors)
	_run_case("danger keeps the top red while DETAILS colors each folded alert", _test_mixed_alert_colors)
	_run_case("pre-win stress and post-win break risk remain red", _test_stress_danger_colors)
	_run_case("the comfort Next fits two lines with 12 px to spare", _test_fit)
	print("")
	if _failure_count == 0:
		print("KR WELLBEING TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("KR WELLBEING TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _won() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	game.day_cycle.deserialize({"elapsed_seconds": 70.0, "current_day": 2, "completed": false})
	game.breach_system.advance(0.0, 70.0)
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.apply_patch_work(100.0)
	game.job_system.rebuild_from_state()
	game.day_cycle.deserialize({"elapsed_seconds": 279.5, "current_day": 7, "completed": false})
	game.oxygen_system.oxygen = 100.0
	game.step_simulation(1.0)
	return game


func _calm(game: VaultGame) -> void:
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
	game.food_system.meals = 20


func _test_threshold() -> void:
	var game := _spawn_game()
	game.begin_shift()
	for resident: VaultResident in game.residents:
		_assert_approximately(resident.needs.recreation_seek, 35.0, 0.001, "pre-win %s seeks at 35" % resident.resident_name)
	game.residents[0].needs.mood = 42.0
	_assert_false(game.residents[0].needs.wants_recreation(), "mood 42 does not want Rec before the win")
	_dispose(game)
	game = _won()
	game.start_keep_running()
	game.step_simulation(0.5)
	for resident: VaultResident in game.residents:
		_assert_approximately(resident.needs.recreation_seek, 45.0, 0.001, "kept-running %s seeks at 45" % resident.resident_name)
	game.residents[0].needs.mood = 42.0
	_assert_true(game.residents[0].needs.wants_recreation(), "mood 42 wants Rec after the win")
	game.residents[0].needs.mood = 46.0
	_assert_false(game.residents[0].needs.wants_recreation(), "mood 46 does not")
	game.new_game(false)
	for resident: VaultResident in game.residents:
		_assert_approximately(resident.needs.recreation_seek, 35.0, 0.001, "NEW WING resets %s to 35" % resident.resident_name)
	_dispose(game)


func _test_seek_job() -> void:
	for kept in [false, true]:
		var game := _won()
		if kept:
			game.start_keep_running()
			game.step_simulation(0.5)
		_calm(game)
		var cell: Vector2i = game._annex_free_cells(1)[0]
		var console := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, cell)
		console.powered = true
		var ari: VaultResident = game.residents[0]
		ari.needs.mood = 42.0
		game.job_system.release_resident(ari)
		game.job_system._handle_survival(ari, 0.1)
		var claimed := console.reserved_by == ari.resident_id and ari.recreating
		_assert_equal(claimed, kept, "mood 42 claims the console: %s (kept running: %s)" % [claimed, kept])
		_dispose(game)


func _test_comfort_next() -> void:
	var game := _won()
	game.start_keep_running()
	# This vault has no powered Air Recycler, so salvage-aware Next would lead with reclamation.
	# The fixture is about the keep-running pointer: start it as already taken (no salvage paid).
	game.reclaim_active = true
	_calm(game)
	# Nothing banked yet: with salvage in hand, Next offers the spend nudge (build Rec Console) instead.
	game.food_system.salvage = 0
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, PlayerOrders.COMFORT_TEXT.next, "calm vault: Next points at the card")
	game.residents[0].needs.health = 50.0
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, PlayerOrders.COMFORT_TEXT.next, "an injury's Med Bed step gives way to the card")
	game.residents[0].needs.health = 100.0
	game.residents[0].needs.mood = 5.0
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, PlayerOrders.COMFORT_TEXT.next, "a Rec Console step gives way to the card")
	game.residents[0].needs.mood = 100.0
	# A food-chain emergency is life support: it still leads over the card.
	for building: VaultBuilding in game.buildings.duplicate():
		if building.kind == VaultBuilding.Kind.KITCHEN:
			game.buildings.erase(building)
			building.queue_free()
	game.food_system.meals = 0
	game.residents[0].needs.food = 10.0
	game.player_orders.refresh()
	var food: String = game.player_orders.objective_label.text
	_assert_equal(food, "Next: Ari starving · YOU place a Nutrient Station · THEY cook", "a food-chain step still leads")
	game.apply_comfort()
	_assert_false(game.comfort_pending(), "card used")
	_dispose(game)


func _text_width(control: Control, text: String) -> float:
	return control.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, control.get_theme_font_size("font_size")).x


func _test_fit() -> void:
	var game := _won()
	game.start_keep_running()
	var orders := game.player_orders
	var width := VaultGame.RIGHT_PANEL_WIDTH
	var node: Node = orders.comfort_box.get_parent()
	while node is Control:
		if node is PanelContainer:
			width -= (node as PanelContainer).get_theme_stylebox("panel").get_minimum_size().x
			break
		if node is MarginContainer:
			width -= (node as Control).get_theme_constant("margin_left") + (node as Control).get_theme_constant("margin_right")
		node = node.get_parent()
	var room := 2.0 * width - _text_width(orders.objective_label, PlayerOrders.COMFORT_TEXT.next)
	_assert_true(room >= 12.0, "comfort Next fits two lines with %.0f px to spare" % room)
	_dispose(game)


# Exercise real alert generation; only fold all clauses for the isolated DETAILS color checks.
# Normal fold/layout behavior is covered unchanged by test_alert_line_cap.gd.
func _stress_game(kept: bool) -> VaultGame:
	var game := _won() if kept else _spawn_game()
	game.set_process(false)
	if kept:
		game.start_keep_running()
	else:
		game.begin_shift()
	_calm(game)
	var cell: Vector2i = game._annex_free_cells(1)[0]
	var console := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, cell)
	console.powered = true
	game.residents[0].needs.mood = 38.0
	if not game.player_orders._details_expanded:
		game.player_orders._toggle_details_rail()
	return game


func _assert_font(control: Control, expected: String, context: String) -> void:
	_assert_equal(control.get_theme_color("font_color").to_html(false), expected, context + ": actual font color")
	_assert_equal(control.modulate * control.self_modulate, Color.WHITE, context + ": no tint changes the font")


func _assert_details_font(orders: PlayerOrders, clause: String, expected: String) -> void:
	var surface: Control = orders.alert_more_label
	# Also reads the old multiline Label so the baseline control fails on color assertions.
	var rows: Array[Node] = [surface]
	rows.append_array(surface.get_children())
	var found := false
	for row: Node in rows:
		if row is Label and clause in (row as Label).text.split("\n"):
			found = true
			_assert_true((row as Label).is_visible_in_tree(), clause + ": DETAILS row is visible")
			_assert_font(row as Label, expected, "DETAILS " + clause)
	_assert_true(found, clause + ": DETAILS has a rendered Label")


func _fold_all(orders: PlayerOrders) -> void:
	orders.alert_hidden_count = orders.alert_list.size()
	orders._refresh_alert_details()


func _test_stress_warning_colors() -> void:
	var game := _stress_game(true)
	var orders := game.player_orders
	var stress := "MOOD STRESSED · " + game.residents[0].resident_name
	orders._refresh_alerts({})
	_assert_equal(orders.alert_list, [stress], "real stressed-only alert set")
	_assert_font(orders.alert_label, "efc56b", "post-win stressed-only top")
	_fold_all(orders)
	_assert_details_font(orders, stress, "efc56b")
	# A danger already stated by Next is excluded from shown/folded clauses.
	game.food_system.meals = 0
	orders._refresh_alerts({"text": "Next: cook meals"})
	_assert_true("NO MEALS" in orders.all_alerts, "fixture includes a filtered danger")
	_assert_equal(orders.alert_list, [stress], "only stress remains after Next filtering")
	_assert_font(orders.alert_label, "efc56b", "shown/folded warnings only")
	_dispose(game)


func _test_mixed_alert_colors() -> void:
	var game := _stress_game(true)
	var orders := game.player_orders
	var stress := "MOOD STRESSED · " + game.residents[0].resident_name
	game.food_system.meals = 0
	orders._refresh_alerts({})
	_assert_equal(orders.alert_list, ["NO MEALS", stress], "real mixed warning and danger")
	_assert_font(orders.alert_label, "ef6860", "mixed top")
	_fold_all(orders)
	_assert_details_font(orders, stress, "efc56b")
	_assert_details_font(orders, "NO MEALS", "ef6860")
	# Four real clauses leave both stress and a danger folded into DETAILS.
	game.residents[1].needs.health = 50.0
	for resident: VaultResident in game.residents:
		resident.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
	orders._refresh_alerts({})
	_assert_equal(orders.alert_list.size(), 4, "four real clauses exercise normal folding")
	_assert_true(orders.alert_hidden_count >= 2, "normal cap folds danger and stress")
	_assert_font(orders.alert_label, "ef6860", "mixed top with folded danger")
	_assert_details_font(orders, stress, "efc56b")
	_assert_details_font(orders, "INJURED 1 · NO MED BED", "ef6860")
	_dispose(game)


func _test_stress_danger_colors() -> void:
	var game := _stress_game(false)
	var orders := game.player_orders
	var stress := "MOOD STRESSED · " + game.residents[0].resident_name
	orders._refresh_alerts({})
	_assert_equal(orders.alert_list, [stress], "pre-win stressed-only alerts")
	_assert_font(orders.alert_label, "ef6860", "pre-win stressed top")
	_fold_all(orders)
	_assert_details_font(orders, stress, "ef6860")
	_dispose(game)
	game = _stress_game(true)
	orders = game.player_orders
	game.residents[0].needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD
	orders._refresh_alerts({})
	var risk := "MOOD BREAK RISK · " + game.residents[0].resident_name
	_assert_true(risk in orders.alert_list, "break risk is still a danger")
	_assert_font(orders.alert_label, "ef6860", "post-win break-risk top")
	_fold_all(orders)
	_assert_details_font(orders, risk, "ef6860")
	_dispose(game)
