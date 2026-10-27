extends "res://tests/test_runner.gd"

# North star slice 3: the finished Annex brings a fifth resident, three fixtures and a stable end state.


func _run() -> void:
	_run_case("finishing the Annex moves in a fifth resident with a bunk, Grow Tray, Nutrient Station and Charge Node", _test_payoff)
	_run_case("the arrival is celebrated, then the vault reads stable", _test_celebration)
	_run_case("the payoff reconciles from the save and never doubles", _test_reconcile)
	_run_case("payoff texts fit with 12 px to spare", _test_fit)
	print("")
	if _failure_count == 0:
		print("ANNEX PAYOFF TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("ANNEX PAYOFF TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _running() -> VaultGame:
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
	game.start_keep_running()
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
	return game


func _finish(game: VaultGame) -> void:
	game.annex_meals = VaultGame.ANNEX_MEALS - 1
	game.annex_salvage = VaultGame.ANNEX_SALVAGE - 1
	game.food_system.meals = 20
	game.food_system.salvage = 20
	for i in 60:
		game._advance_annex(0.1)


func _count(game: VaultGame, kind: int) -> int:
	var n := 0
	for b in game.buildings:
		if b.kind == kind and b.complete:
			n += 1
	return n


func _test_payoff() -> void:
	var game := _running()
	var beds := _count(game, VaultBuilding.Kind.BED)
	var trays := _count(game, VaultBuilding.Kind.GROW_TRAY)
	var nodes := _count(game, VaultBuilding.Kind.GENERATOR)
	var kitchens := _count(game, VaultBuilding.Kind.KITCHEN)
	_assert_equal(game.residents.size(), 4, "four crew before")
	_finish(game)
	_assert_true(game.annex_done, "annex done")
	_assert_equal(game.residents.size(), 5, "a fifth resident")
	var eko := game.annex_resident()
	_assert_true(eko != null and eko.resident_name == "Eko" and eko.resident_id == 5, "resident 5 is Eko")
	_assert_true(eko.alive, "alive")
	_assert_equal(_count(game, VaultBuilding.Kind.BED), beds + 1, "+1 completed bunk")
	_assert_equal(_count(game, VaultBuilding.Kind.GROW_TRAY), trays + 1, "+1 completed Grow Tray")
	_assert_equal(_count(game, VaultBuilding.Kind.GENERATOR), nodes + 1, "+1 completed Charge Node")
	_assert_equal(_count(game, VaultBuilding.Kind.KITCHEN), kitchens + 1, "+1 completed Nutrient Station")
	for b in game.buildings:
		_assert_true(b.cell != BreachSystem.HATCH_CELL, "nothing on the hatch")
	var cells := {}
	for b in game.buildings:
		_assert_false(cells.has(b.cell), "no two fixtures share a cell")
		cells[b.cell] = true
	_assert_true(game.map_grid.is_walkable(eko.get_cell(game.map_grid)), "Eko stands on floor")
	_dispose(game)


func _test_celebration() -> void:
	var game := _running()
	game.food_system.meals = 30
	# Comfort already queued (slice 4), so Next can read the stable end state.
	_add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, game._annex_free_cells(1)[0])
	_add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, game._annex_free_cells(1)[0])
	_finish(game)
	game.player_orders.refresh()
	_assert_true(game.status_message.begins_with("ANNEX OPEN: Eko moves in"), "status toast: %s" % game.status_message)
	_assert_true("  ·  ".join(game.player_orders.all_alerts).contains("NEW CREW · EKO MOVES IN"), "alert names the arrival")
	_assert_equal(game.player_orders.alert_label.get_theme_color("font_color"), Color("75d4b4"), "a lone welcome reads green")
	_assert_true(game.player_orders.annex_box.visible, "the card stays as a stable marker")
	_assert_equal(game.player_orders.annex_header.text, "ANNEX OPEN · 5 crew · vault stable", "stable header")
	_assert_false(game.player_orders.annex_minus_button.get_parent().visible, "no stepper once open")
	_assert_equal(game.player_orders.objective_label.text, "Next: YOU enjoy a stable vault · THEY run all of it", "stable Next")
	game.step_simulation(31.0)
	game.player_orders.refresh()
	_assert_false("  ·  ".join(game.player_orders.all_alerts).contains("NEW CREW"), "the welcome fades after 30 s")
	_dispose(game)


func _test_reconcile() -> void:
	var game := _running()
	var beds_before := _count(game, VaultBuilding.Kind.BED)
	_finish(game)
	var snapshot := game.create_snapshot()
	_assert_equal((snapshot.residents as Array).size(), 5, "the save carries five residents")
	_assert_true(game.apply_snapshot(snapshot), "reload")
	_assert_equal(game.residents.size(), 5, "still five, no duplicate")
	_assert_equal(_count(game, VaultBuilding.Kind.BED), beds_before + 1, "no duplicate bunk")
	var lost: Dictionary = snapshot.duplicate(true)
	var crew: Array = lost.residents
	crew.resize(4)
	_assert_true(game.apply_snapshot(lost), "a done annex without resident 5 loads")
	_assert_equal(game.residents.size(), 5, "and reconciles the arrival")
	game._grant_annex_payoff()
	_assert_equal(game.residents.size(), 5, "granting twice adds nobody")
	_dispose(game)


func _text_width(control: Control, text: String) -> float:
	return control.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, control.get_theme_font_size("font_size")).x


func _test_fit() -> void:
	var game := _running()
	var orders := game.player_orders
	var width := VaultGame.RIGHT_PANEL_WIDTH
	var node: Node = orders.annex_box.get_parent()
	while node is Control:
		if node is PanelContainer:
			width -= (node as PanelContainer).get_theme_stylebox("panel").get_minimum_size().x
			break
		if node is MarginContainer:
			width -= (node as Control).get_theme_constant("margin_left") + (node as Control).get_theme_constant("margin_right")
		node = node.get_parent()
	var header_room := width - _text_width(orders.annex_header, "ANNEX OPEN · 5 crew · vault stable")
	_assert_true(header_room >= 12.0, "open header fits with %.0f px to spare" % header_room)
	var next_room := 2.0 * width - _text_width(orders.objective_label, "Next: YOU enjoy a stable vault · THEY run all of it")
	_assert_true(next_room >= 12.0, "stable Next fits two lines with %.0f px to spare" % next_room)
	# The plain select help is the longest line the command bar already shows; stay 12 px under it.
	var select_line := "SELECT // Select a living resident, then [R] to draft/undraft. Right-click: drafted = move; undrafted = force context job."
	var status_room := _text_width(orders.tool_status, select_line) - _text_width(orders.tool_status, "SELECT // " + VaultGame.ANNEX_OPEN_STATUS % "Eko")
	_assert_true(status_room >= 12.0, "arrival status is %.0f px shorter than the select help the bar fits" % status_room)
	var alert_room := width - _text_width(orders.alert_label, "NEW CREW · EKO MOVES IN")
	_assert_true(alert_room >= 12.0, "welcome alert fits one line with %.0f px to spare" % alert_room)
	_dispose(game)
