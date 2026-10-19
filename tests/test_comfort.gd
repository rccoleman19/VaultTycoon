extends "res://tests/test_runner.gd"

# North star slice 4: after KEEP RUNNING one tap queues a Rec Console, a Med Bed and their power and light.


func _run() -> void:
	_run_case("the comfort card shows only while a kept-running vault lacks Rec or Med", _test_offer)
	_run_case("one tap queues Rec, Med Bed, a Charge Node for power and a Lumen by a dark bunk", _test_apply)
	_run_case("the Annex waits for salvage while a blueprint is unbuilt", _test_annex_waits)
	_run_case("a kept-running vault flags only treatable injuries", _test_injured_alert)
	_run_case("comfort texts fit with 12 px to spare", _test_fit)
	print("")
	if _failure_count == 0:
		print("COMFORT TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("COMFORT TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
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


func _running() -> VaultGame:
	var game := _won()
	game.start_keep_running()
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
	return game


func _count(game: VaultGame, kind: int, complete_only := false) -> int:
	var n := 0
	for b in game.buildings:
		if b.kind == kind and (b.complete or not complete_only):
			n += 1
	return n


func _test_offer() -> void:
	var game := _won()
	game.player_orders.refresh()
	_assert_false(game.comfort_pending(), "not on the win panel")
	_assert_false(game.player_orders.comfort_box.visible, "no card on the win panel")
	game.start_keep_running()
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
	game.food_system.meals = 20
	game.player_orders.refresh()
	_assert_true(game.comfort_pending(), "offered once the vault keeps running")
	_assert_true(game.player_orders.comfort_box.visible, "the card shows")
	_assert_equal(game.player_orders.comfort_header.text, "AFTER THE WIN · comfort", "header")
	_assert_equal(game.player_orders.comfort_button.text, "Rec, Med Bed, power, light · %d" % game.comfort_cost(), "button names the cost")
	_assert_equal(game.player_orders.objective_label.text, PlayerOrders.COMFORT_TEXT.next, "Next points at the card")
	var rec := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, game._annex_free_cells(1)[0])
	_assert_true(game.comfort_pending(), "still offered without a Med Bed")
	_add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, game._annex_free_cells(1)[0])
	game.player_orders.refresh()
	_assert_false(game.comfort_pending(), "a vault with both is already comfortable (derived from the world)")
	_assert_false(game.player_orders.comfort_box.visible, "card hidden")
	_assert_false(game.apply_comfort(), "nothing to apply")
	_assert_true(rec != null, "fixture added")
	_dispose(game)
	game = _spawn_game()
	game.begin_shift()
	game.player_orders.refresh()
	_assert_false(game.comfort_pending(), "never pre-win")
	_assert_false(game.player_orders.comfort_box.visible, "no card pre-win")
	_dispose(game)


func _test_apply() -> void:
	var game := _running()
	var salvage_before := game.food_system.salvage
	var spare := game._planned_power_spare()
	var plan := game.comfort_plan()
	var kinds: Array = []
	for piece: Array in plan:
		kinds.append(int(piece[0]))
	_assert_true(kinds.has(VaultBuilding.Kind.RECREATION_CONSOLE) and kinds.has(VaultBuilding.Kind.MEDICAL_BED), "plan holds Rec and Med: %s" % [kinds])
	var need := 1 + (1 if game._comfort_dark_bunk() != null else 0)
	_assert_equal(kinds.has(VaultBuilding.Kind.GENERATOR), spare < need, "a Charge Node only when planned power (%d spare) cannot carry Rec (+ Lumen): %d" % [spare, need])
	_assert_equal(kinds.has(VaultBuilding.Kind.LAMP), game._comfort_dark_bunk() != null, "a Lumen only when a bunk is dark")
	var cost := game.comfort_cost()
	_assert_true(game.apply_comfort(), "applies")
	_assert_equal(game.status_message, VaultGame.COMFORT_STATUS, "status names what was queued")
	_assert_equal(_count(game, VaultBuilding.Kind.RECREATION_CONSOLE), 1, "Rec blueprint queued")
	_assert_equal(_count(game, VaultBuilding.Kind.MEDICAL_BED), 1, "Med Bed blueprint queued")
	_assert_equal(game.food_system.salvage, salvage_before, "blueprints are paid on delivery, not up front")
	_assert_false(game.comfort_pending(), "the card retires")
	_assert_false(game.apply_comfort(), "a second tap does nothing")
	_assert_true(cost >= 16, "cost covers at least Rec + Med (%d)" % cost)
	for piece: Array in plan:
		_assert_true(piece[1] != BreachSystem.HATCH_CELL, "never on the hatch")
	# Power: forced shortfall must add a Charge Node.
	_dispose(game)
	game = _running()
	for i in 4:
		_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, game._annex_free_cells(1)[0])
	_assert_true(game._planned_power_spare() < 2, "power is short")
	var short_kinds: Array = []
	for piece: Array in game.comfort_plan():
		short_kinds.append(int(piece[0]))
	_assert_equal(short_kinds[0], VaultBuilding.Kind.GENERATOR, "the Charge Node comes first when power is short")
	_dispose(game)


func _test_annex_waits() -> void:
	var game := _running()
	game.food_system.meals = 0
	game.food_system.salvage = 50
	game.apply_comfort()
	for i in 60:
		game._advance_annex(0.1)
	_assert_equal(game.annex_salvage, 0, "no salvage to the Annex while comfort is unbuilt")
	for b in game.buildings:
		b.complete = true
	for i in 60:
		game._advance_annex(0.1)
	_assert_true(game.annex_salvage > 0, "the Annex takes salvage once construction is done")
	_dispose(game)


func _test_injured_alert() -> void:
	var game := _running()
	_add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, game._annex_free_cells(1)[0])
	_add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, game._annex_free_cells(1)[0])
	game.player_orders.refresh()
	_assert_false(game.player_orders.alert_label.text.contains("INJURED"), "a Med Bed alone no longer raises INJURED: %s" % game.player_orders.alert_label.text)
	game.residents[0].needs.health = 97.0
	game.player_orders.refresh()
	_assert_false(game.player_orders.alert_label.text.contains("INJURED"), "97 HP is below Med Bed care; no alert")
	game.residents[0].needs.health = 90.0
	game.player_orders.refresh()
	_assert_true(game.player_orders.alert_label.text.contains("INJURED 1"), "90 HP is treatable: INJURED 1")
	_dispose(game)
	# Pre-win stays as it was: any Med Bed shows the line.
	game = _spawn_game()
	game.begin_shift()
	_add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(game.map_grid.get_floor_cells()[0]))
	game.player_orders.refresh()
	_assert_true(game.player_orders.alert_label.text.contains("INJURED 0"), "pre-win alert unchanged")
	_dispose(game)


func _text_width(control: Control, text: String) -> float:
	return control.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, control.get_theme_font_size("font_size")).x


func _test_fit() -> void:
	var game := _running()
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
	var header_room := width - _text_width(orders.comfort_header, PlayerOrders.COMFORT_TEXT.header)
	_assert_true(header_room >= 12.0, "header fits with %.0f px to spare" % header_room)
	var button_pad: float = orders.comfort_button.get_theme_stylebox("normal").get_minimum_size().x
	var button_room := width - button_pad - _text_width(orders.comfort_button, PlayerOrders.COMFORT_TEXT.button % 99)
	_assert_true(button_room >= 12.0, "button fits with %.0f px to spare" % button_room)
	var next_room := 2.0 * width - _text_width(orders.objective_label, PlayerOrders.COMFORT_TEXT.next)
	_assert_true(next_room >= 12.0, "Next fits two lines with %.0f px to spare" % next_room)
	var select_line := "SELECT // Select a living resident, then [R] to draft/undraft. Right-click: drafted = move; undrafted = force context job."
	var status_room := _text_width(orders.tool_status, select_line) - _text_width(orders.tool_status, "SELECT // " + VaultGame.COMFORT_STATUS)
	_assert_true(status_room >= 12.0, "status is %.0f px shorter than the select help the bar fits" % status_room)
	_dispose(game)
