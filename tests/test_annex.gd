extends "res://tests/test_runner.gd"

# North star slice 2: the Annex takes meals above a reserve plus salvage while the vault keeps running.

const ANNEX_SAVE := "user://test_annex.json"


func _run() -> void:
	_run_case("the Annex card shows only while the vault keeps running", _test_card)
	_run_case("each tick takes one meal above the reserve and one salvage", _test_intake)
	_run_case("hungry crew and the reserve keep their meals; salvage at zero waits", _test_guards)
	_run_case("the upkeep trickle keeps salvage coming", _test_trickle)
	_run_case("the reserve stepper clamps to 4-20 in steps of 2", _test_stepper)
	_run_case("full quotas complete the Annex and stop the intake", _test_complete)
	_run_case("the annex key is additive, versioned and validated", _test_save)
	_run_case("Annex texts fit with 12 px to spare", _test_fit)
	print("")
	if _failure_count == 0:
		print("ANNEX TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("ANNEX TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
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
	_fed(game)
	return game


func _fed(game: VaultGame) -> void:
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0


# Advances the annex alone (no crew eating or cooking) for exact counts.
func _annex(game: VaultGame, seconds: float) -> void:
	var left := seconds
	while left > 0.0001:
		game._advance_annex(minf(0.1, left))
		left -= 0.1


func _test_card() -> void:
	var game := _won()
	game.player_orders.refresh()
	_assert_false(game.player_orders.annex_box.visible, "no Annex on the win panel")
	_assert_false(game.annex_active(), "inactive before keep running")
	game.start_keep_running()
	game.player_orders.refresh()
	_assert_true(game.player_orders.annex_box.visible, "the card shows once the vault keeps running")
	_assert_equal(game.player_orders.annex_header.text, "ANNEX · meals 0/30 · salvage 0/150", "header names both quotas")
	_assert_equal(game.player_orders.annex_reserve_label.text, "Keep 8 meals", "default reserve 8")
	_assert_approximately(game.player_orders.annex_bar.value, 0.0, 0.0001, "empty bar")
	_fed(game)
	game.food_system.meals = 20
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, PlayerOrders.COMFORT_TEXT.next, "comfort comes first")
	_add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, game._annex_free_cells(1)[0])
	_add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, game._annex_free_cells(1)[0])
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, "Next: YOU set the meal reserve · THEY build the Annex", "then Next points at the Annex")
	_dispose(game)
	game = _spawn_game()
	game.begin_shift()
	game.player_orders.refresh()
	_assert_false(game.player_orders.annex_box.visible, "a fresh wing never shows it")
	_dispose(game)


func _test_intake() -> void:
	var game := _running()
	game.food_system.meals = 12
	game.food_system.salvage = 40
	_annex(game, 5.0)
	_assert_equal(game.annex_meals, 1, "one meal per tick")
	_assert_equal(game.annex_salvage, 1, "one salvage per tick")
	_assert_equal(game.food_system.meals, 11, "taken from stored meals")
	_assert_equal(game.food_system.salvage, 39, "taken from salvage")
	_annex(game, 15.0)
	_assert_equal(game.annex_meals, 4, "meals stop at the reserve (12 - 8 = 4)")
	_assert_equal(game.food_system.meals, 8, "the reserve stays")
	_assert_equal(game.annex_salvage, 4, "salvage keeps going")
	_assert_approximately(game.annex_progress(), 8.0 / 180.0, 0.0001, "progress counts both quotas")
	game.player_orders.refresh()
	_assert_approximately(game.player_orders.annex_bar.value, 8.0 / 180.0, 0.0001, "the bar follows")
	_dispose(game)


func _test_guards() -> void:
	var game := _running()
	game.food_system.meals = 20
	game.food_system.salvage = 0
	game.residents[1].needs.food = VaultGame.ANNEX_HUNGRY_FOOD - 1.0
	_annex(game, 5.0)
	_assert_equal(game.annex_meals, 0, "a hungry crew member keeps every meal")
	_assert_equal(game.annex_salvage, 0, "no salvage, none taken")
	game.residents[1].alive = false
	_annex(game, 5.0)
	_assert_equal(game.annex_meals, 1, "the dead do not count as hungry")
	game.food_system.meals = 8
	_annex(game, 5.0)
	_assert_equal(game.annex_meals, 1, "at the reserve nothing goes in")
	_dispose(game)


func _test_trickle() -> void:
	var game := _running()
	game.food_system.salvage = 0
	game.food_system.meals = 0
	_annex(game, 19.9)
	_assert_equal(game.food_system.salvage + game.annex_salvage, 0, "no trickle before 20 s")
	_annex(game, 0.2)
	_assert_equal(game.food_system.salvage + game.annex_salvage, 1, "+1 salvage at 20 s")
	_annex(game, 40.0)
	_assert_equal(game.food_system.salvage + game.annex_salvage, 3, "+1 every 20 s")
	_dispose(game)
	game = _won()
	var before := game.food_system.salvage
	game._advance_annex(30.0)
	_assert_equal(game.food_system.salvage, before, "no trickle unless keep running")
	_dispose(game)


func _test_stepper() -> void:
	var game := _running()
	var orders := game.player_orders
	orders.annex_minus_button.pressed.emit()
	_assert_equal(game.annex_reserve, 6, "minus takes 2")
	orders.annex_minus_button.pressed.emit()
	orders.annex_minus_button.pressed.emit()
	_assert_equal(game.annex_reserve, 4, "floor 4")
	orders.refresh()
	_assert_true(orders.annex_minus_button.disabled, "minus disabled at the floor")
	for i in 12:
		orders.annex_plus_button.pressed.emit()
	_assert_equal(game.annex_reserve, 20, "ceiling 20")
	orders.refresh()
	_assert_true(orders.annex_plus_button.disabled, "plus disabled at the ceiling")
	_assert_equal(orders.annex_reserve_label.text, "Keep 20 meals", "label follows")
	game.set_annex_reserve(9)
	_assert_equal(game.annex_reserve, 8, "odd values round down to the step")
	_dispose(game)


func _test_complete() -> void:
	var game := _running()
	game.annex_meals = VaultGame.ANNEX_MEALS - 1
	game.annex_salvage = VaultGame.ANNEX_SALVAGE - 1
	game.food_system.meals = 20
	game.food_system.salvage = 20
	_annex(game, 5.0)
	_assert_true(game.annex_done, "full quotas complete the Annex")
	_assert_false(game.annex_active(), "no longer active")
	_assert_equal(game.food_system.meals, 19, "the last meal went in")
	_assert_equal(game.food_system.salvage, 19, "the last salvage went in")
	_annex(game, 60.0)
	_assert_equal(game.food_system.meals, 19, "no more meals taken")
	_assert_equal(game.food_system.salvage, 19, "no more salvage taken, no trickle")
	game.player_orders.refresh()
	_assert_false(game.player_orders.annex_minus_button.get_parent().visible, "the stepper goes away")
	_assert_approximately(game.player_orders.annex_bar.value, 1.0, 0.0001, "the bar is full")
	_dispose(game)


func _test_save() -> void:
	var game := _running()
	game.annex_meals = 7
	game.annex_salvage = 33
	game.set_annex_reserve(12)
	var snapshot := game.create_snapshot()
	_assert_true(snapshot.has(VaultGame.ANNEX_KEY), "keep-running save carries the annex key")
	_assert_variants_equal({"version": 1, "meals": 7, "salvage": 33, "reserve": 12, "done": false}, snapshot[VaultGame.ANNEX_KEY], "key contents")
	_remove_test_save(ANNEX_SAVE)
	_assert_true(game.save_game(false, ANNEX_SAVE), "saved")
	game.new_game(false)
	_assert_equal(game.annex_meals, 0, "new game resets the annex")
	_assert_equal(game.annex_reserve, 8, "and the reserve")
	_assert_true(game.load_game(ANNEX_SAVE), "loaded")
	_assert_equal([game.annex_meals, game.annex_salvage, game.annex_reserve, game.annex_done], [7, 33, 12, false], "restored")
	_remove_test_save(ANNEX_SAVE)
	for change: Array in [["version", 2], ["meals", 31], ["salvage", 151], ["meals", -1], ["reserve", 2], ["reserve", 22], ["reserve", 9], ["done", 1], ["done", true]]:
		var bad: Dictionary = snapshot.duplicate(true)
		bad[VaultGame.ANNEX_KEY][change[0]] = change[1]
		_assert_false(game._is_snapshot_shape_valid(bad), "%s = %s rejected" % [change[0], change[1]])
	var full: Dictionary = snapshot.duplicate(true)
	full[VaultGame.ANNEX_KEY] = {"version": 1, "meals": 30, "salvage": 150, "reserve": 8, "done": true}
	_assert_true(game._is_snapshot_shape_valid(full), "a finished annex is valid")
	var orphan: Dictionary = snapshot.duplicate(true)
	orphan.erase(VaultGame.KEEP_RUNNING_KEY)
	_assert_false(game._is_snapshot_shape_valid(orphan), "an annex without keep running is rejected")
	var filled: Dictionary = snapshot.duplicate(true)
	filled[VaultGame.ANNEX_KEY] = {"version": 1, "meals": 30, "salvage": 150, "reserve": 8, "done": false}
	_assert_true(game.apply_snapshot(filled), "a filled-but-open annex loads")
	_assert_true(game.annex_done, "and reconciles to done from its quotas")
	_assert_false(_won_snapshot_has_annex(), "a plain won save has no annex key")
	_dispose(game)


func _won_snapshot_has_annex() -> bool:
	var game := _won()
	var has := game.create_snapshot().has(VaultGame.ANNEX_KEY)
	_dispose(game)
	return has


func _text_width(control: Control, text: String) -> float:
	return control.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, control.get_theme_font_size("font_size")).x


func _panel_width(orders: PlayerOrders) -> float:
	var width := VaultGame.RIGHT_PANEL_WIDTH
	var node: Node = orders.annex_box.get_parent()
	while node is Control:
		if node is PanelContainer:
			width -= (node as PanelContainer).get_theme_stylebox("panel").get_minimum_size().x
			break
		if node is MarginContainer:
			width -= (node as Control).get_theme_constant("margin_left") + (node as Control).get_theme_constant("margin_right")
		node = node.get_parent()
	return width


func _test_fit() -> void:
	var game := _running()
	var orders := game.player_orders
	var width := _panel_width(orders)
	var header_room := width - _text_width(orders.annex_header, "ANNEX · meals 30/30 · salvage 150/150")
	_assert_true(header_room >= 12.0, "header fits with %.0f px to spare" % header_room)
	var row_room := width - 2.0 * 26.0 - 8.0 - _text_width(orders.annex_reserve_label, "Keep 20 meals")
	_assert_true(row_room >= 12.0, "reserve row fits with %.0f px to spare" % row_room)
	var next_room := 2.0 * width - _text_width(orders.objective_label, "Next: YOU set the meal reserve · THEY build the Annex")
	_assert_true(next_room >= 12.0, "Next fits two lines with %.0f px to spare" % next_room)
	_dispose(game)
