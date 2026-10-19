extends "res://tests/test_runner.gd"

# North star slice 1: KEEP RUNNING on the win panel continues the same vault past Day 7.

const KR_SAVE := "user://test_keep_running.json"


func _run() -> void:
	_run_case("the win panel offers KEEP RUNNING beside LOAD and NEW WING; a loss never does", _test_offer)
	_run_case("keep running goes live past Day 7 without winning again", _test_runs_on)
	_run_case("Next and alerts drop the Day 7 texts while it keeps running", _test_next_alerts)
	_run_case("a Med Bed / Rec Console suggestion latches instead of flipping", _test_latch)
	_run_case("the keep-running key is additive, versioned and validated", _test_save)
	_run_case("losing the vault later keeps the seal win on record", _test_later_loss)
	_run_case("keep-running texts fit with 12 px to spare", _test_fit)
	print("")
	if _failure_count == 0:
		print("KEEP RUNNING TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("KEEP RUNNING TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
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


func _buttons(game: VaultGame) -> Array[String]:
	var names: Array[String] = []
	for button: Node in game.player_orders.outcome_panel.find_children("*", "Button", true, false):
		if (button as Button).visible:
			names.append((button as Button).text)
	return names


func _test_offer() -> void:
	var game := _won()
	_assert_true(game.ended and game.outcome == "win", "the fixture wins at Day 7")
	_assert_true(game.player_orders.outcome_panel.visible, "win panel shown")
	var names := _buttons(game)
	for text: String in ["LOAD LAST CHECKPOINT", "NEW WING", "KEEP RUNNING"]:
		_assert_true(text in names, "%s on the win panel" % text)
	_assert_true(game.can_keep_running(), "a won wing can keep running")
	_dispose(game)
	game = _spawn_game()
	game.begin_shift()
	for resident: VaultResident in game.residents:
		resident.needs.food = 0.0
		resident.needs.health = 0.0
		resident.alive = false
	game._finish_loss()
	_assert_equal(game.outcome, "loss", "loss fixture")
	_assert_false("KEEP RUNNING" in _buttons(game), "a loss never offers KEEP RUNNING")
	_assert_false(game.start_keep_running(), "and refuses it")
	_dispose(game)


func _test_runs_on() -> void:
	var game := _won()
	_assert_true(game.start_keep_running(), "KEEP RUNNING starts")
	_assert_false(game.ended, "the wing is live again")
	_assert_true(game.keep_running, "keep_running set")
	_assert_false(game.player_orders.outcome_panel.visible, "win panel hidden")
	_assert_false(game.can_keep_running(), "it cannot be started twice")
	_assert_false(game.start_keep_running(), "a second start refuses")
	game.step_simulation(30.0)
	_assert_false(game.ended, "no second win while running")
	_assert_approximately(game.keep_running_seconds, 30.0, 0.2, "the keep-running clock advances")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.clock_label.text, "DAY 8 · LIVE", "clock shows day 8")
	_remove_test_save(SaveLoad.DEFAULT_PATH)
	game.step_simulation(15.0)
	game.player_orders.refresh()
	_assert_equal(game.player_orders.clock_label.text, "DAY 9 · LIVE", "clock rolls to day 9 after 40 s")
	_assert_true(FileAccess.file_exists(SaveLoad.DEFAULT_PATH), "each keep-running day writes a checkpoint")
	_assert_equal(game.day_cycle.elapsed_seconds, DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE, "the Day 7 clock stays complete")
	_dispose(game)
	_remove_test_save(SaveLoad.DEFAULT_PATH)


func _test_next_alerts() -> void:
	var game := _won()
	game.start_keep_running()
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
	game.food_system.meals = 20
	game.player_orders.refresh()
	var next: String = game.player_orders.objective_label.text
	_assert_false(next.contains("Day 7"), "no 'hold Day 7' text: %s" % next)
	_assert_false(next.contains("VICTORY"), "no VICTORY PENDING in Next")
	_assert_false(next.contains("check blockers"), "no 'check blockers' text")
	_assert_equal(next, PlayerOrders.KEEP_RUNNING_TEXT.next, "a calm vault shows the keep-running Next")
	_assert_false(game.player_orders.alert_label.text.contains("VICTORY PENDING"), "no VICTORY PENDING alert")
	game.status_message_left = 0.0
	game.player_orders.refresh()
	var help: String = game.player_orders.tool_status.text
	_assert_false(help.contains("Day 7"), "the help line drops the Day 7 text: %s" % help)
	_assert_equal(help, "SELECT // Select a living resident, then [R] to draft/undraft. Right-click: drafted = move; undrafted = force context job.", "the calm help line is the plain select help that fits the bar")
	game.oxygen_system.oxygen = 10.0
	game.player_orders.refresh()
	_assert_false(game.player_orders.objective_label.text.begins_with("VICTORY PENDING"), "low O2 does not bring back VICTORY PENDING")
	_assert_true(game.player_orders.alert_label.text.contains("OXYGEN"), "oxygen alerts still work")
	_dispose(game)


func _test_latch() -> void:
	var game := _won()
	game.start_keep_running()
	game.food_system.meals = 20
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
	var ari: VaultResident = game.residents[0]
	ari.needs.health = 50.0
	game.player_orders.refresh()
	var first: String = game.player_orders.objective_label.text
	_assert_true(first.contains("Med Bed"), "injury suggests a Med Bed: %s" % first)
	ari.needs.health = 100.0
	ari.needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD - 1.0
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, first, "a mood dip does not flip it to the Rec Console")
	ari.needs.mood = 100.0
	game.step_simulation(5.0)
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, first, "the suggestion holds while the need is briefly gone")
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
	game.food_system.meals = 20
	game.keep_running_seconds += PlayerOrders.KEEP_RUNNING_UNLATCH_S + 1.0
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, PlayerOrders.KEEP_RUNNING_TEXT.next, "after the unlatch window the calm Next returns")
	ari.needs.health = 50.0
	game.player_orders.refresh()
	_assert_true(game.player_orders.objective_label.text.contains("Med Bed"), "a fresh injury latches again")
	_add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(18, 12))
	ari.needs.health = 100.0
	game.player_orders.refresh()
	_assert_false(game.player_orders.objective_label.text.contains("Med Bed"), "a built Med Bed releases the latch at once")
	_dispose(game)


func _test_save() -> void:
	var game := _won()
	var won_snapshot := game.create_snapshot()
	_assert_false(won_snapshot.has(VaultGame.KEEP_RUNNING_KEY), "a won save carries no keep-running key")
	game.start_keep_running()
	game.step_simulation(12.0)
	var snapshot := game.create_snapshot()
	_assert_true(snapshot.has(VaultGame.KEEP_RUNNING_KEY), "keep-running save carries the key")
	_assert_equal(int(snapshot[VaultGame.KEEP_RUNNING_KEY].version), 1, "version 1")
	_assert_approximately(float(snapshot[VaultGame.KEEP_RUNNING_KEY].seconds), 12.0, 0.2, "seconds saved")
	_assert_false(bool(snapshot.ended), "saved live")
	_assert_equal(str(snapshot.outcome), "", "saved without a win panel")
	_remove_test_save(KR_SAVE)
	_assert_true(game.save_game(false, KR_SAVE), "saved")
	game.new_game(false)
	_assert_false(game.keep_running, "new game clears keep running")
	_assert_true(game.load_game(KR_SAVE), "loaded")
	_assert_true(game.keep_running, "keep running restored")
	_assert_approximately(game.keep_running_seconds, 12.0, 0.2, "seconds restored")
	_assert_false(game.ended, "live after load")
	_assert_false(game.player_orders.outcome_panel.visible, "no panel after load")
	_remove_test_save(KR_SAVE)
	var bad: Dictionary = snapshot.duplicate(true)
	bad[VaultGame.KEEP_RUNNING_KEY].version = 2
	_assert_false(game._is_snapshot_shape_valid(bad), "unknown version rejected")
	bad = snapshot.duplicate(true)
	bad[VaultGame.KEEP_RUNNING_KEY].seconds = -1.0
	_assert_false(game._is_snapshot_shape_valid(bad), "negative seconds rejected")
	bad = snapshot.duplicate(true)
	bad[VaultGame.KEEP_RUNNING_KEY] = 3
	_assert_false(game._is_snapshot_shape_valid(bad), "non-dictionary rejected")
	bad = snapshot.duplicate(true)
	bad.day.elapsed_seconds = 200.0
	bad.day.completed = false
	_assert_false(game._is_snapshot_shape_valid(bad), "a wing before Day 7 cannot keep running")
	bad = snapshot.duplicate(true)
	bad.ended = true
	bad.outcome = "win"
	_assert_false(game._is_snapshot_shape_valid(bad), "never a win panel and keep running at once")
	_assert_true(game._is_snapshot_shape_valid(snapshot), "the real snapshot is valid")
	_dispose(game)


func _test_later_loss() -> void:
	var game := _won()
	game.start_keep_running()
	for resident: VaultResident in game.residents:
		resident.needs.food = 0.0
		resident.alive = false
	game.step_simulation(0.2)
	_assert_true(game.ended, "the vault can still be lost")
	_assert_equal(game.outcome, "loss", "outcome loss")
	_assert_true(game.keep_running, "the keep-running record stays")
	_assert_true(game.player_orders.outcome_text.text.contains(PlayerOrders.KEEP_RUNNING_TEXT.loss), "the loss panel says the seal win stands")
	_assert_false("KEEP RUNNING" in _buttons(game), "no KEEP RUNNING on that loss")
	_assert_true(game.create_snapshot().has(VaultGame.KEEP_RUNNING_KEY), "the save still records the win")
	_dispose(game)


func _text_width(control: Control, text: String) -> float:
	return control.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, control.get_theme_font_size("font_size")).x


func _test_fit() -> void:
	var game := _won()
	var orders := game.player_orders
	var clock_room := orders.clock_label.custom_minimum_size.x - _text_width(orders.clock_label, "DAY 99 · LIVE")
	_assert_true(clock_room >= 12.0, "clock fits with %.0f px to spare" % clock_room)
	var next_width := VaultGame.RIGHT_PANEL_WIDTH
	var node: Node = orders.objective_label.get_parent()
	while node is Control:
		if node is PanelContainer:
			next_width -= (node as PanelContainer).get_theme_stylebox("panel").get_minimum_size().x
			break
		if node is MarginContainer:
			next_width -= (node as Control).get_theme_constant("margin_left") + (node as Control).get_theme_constant("margin_right")
		node = node.get_parent()
	var next_room := 2.0 * next_width - _text_width(orders.objective_label, PlayerOrders.KEEP_RUNNING_TEXT.next)
	_assert_true(next_room >= 12.0, "Next fits two lines (like every Next) with %.0f px to spare" % next_room)
	var button := orders.keep_running_button
	_assert_true(button.get_parent() != null and button.get_parent().get_child_count() == 1, "KEEP RUNNING sits on its own row")
	var row_width := _text_width(button, button.text) + button.get_theme_stylebox("normal").get_minimum_size().x
	var panel_room := orders.outcome_panel.size.x - 2.0 * 24.0 - row_width
	_assert_true(panel_room >= 12.0, "the KEEP RUNNING row fits the win panel with %.0f px to spare" % panel_room)
	var loss_room := 2.0 * (orders.outcome_panel.size.x - 48.0) - _text_width(orders.outcome_text, PlayerOrders.KEEP_RUNNING_TEXT.loss)
	_assert_true(loss_room >= 12.0, "the loss note fits two lines with %.0f px to spare" % loss_room)
	_dispose(game)
