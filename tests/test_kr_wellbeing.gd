extends "res://tests/test_runner.gd"

# After the win residents seek the Rec Console at 45 (before MOOD STRESSED at < 40), and while the
# comfort card is available Next points at it, even over a latched Rec or Med step.


func _run() -> void:
	_run_case("the Rec Console seek threshold is 45 only while the won vault keeps running", _test_threshold)
	_run_case("a resident at mood 42 takes a free console after the win, not before", _test_seek_job)
	_run_case("Next points at the comfort card over Rec/Med steps; life support still leads", _test_comfort_next)
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
	_calm(game)
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
