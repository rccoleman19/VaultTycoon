extends "res://tests/test_runner.gd"

# Top-bar fit: at the 1280x720 design size, which canvas_items/keep also gives 1280x800 and
# 1024x576 windows, every top-bar control stays fully on screen with room to spare, and the
# stats text stays readable in the busiest case.

const SPARE := 12.0
const LAYOUT_FRAMES := 4
# The busiest resource line once the meals-days readout (#89-era HUD leaf) is merged.
const MEALS_DAYS_LINE := "MEALS 188 (+0) · 47.0 DAYS  RAW 188 (+0)  SALVAGE 188"


func _run() -> void:
	for window in [Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1024, 576)]:
		await _run_frame_case("top bar fits a %dx%d window, fresh wing" % [window.x, window.y], _test_fresh.bind(window))
		await _run_frame_case("top bar fits a %dx%d window with every stat at its longest" % [window.x, window.y], _test_busiest.bind(window))
	await _run_frame_case("the 54-character meals-days stats line reads in full beside a BROWNOUT", _test_busiest.bind(Vector2i(1280, 720), MEALS_DAYS_LINE))
	await _run_frame_case("an overlong stats line clips instead of pushing 3x off screen", _test_overlong)
	print("")
	if _failure_count == 0:
		print("TOPBAR FIT TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("TOPBAR FIT TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _run_frame_case(case_name: String, test_callable: Callable) -> void:
	_case_count += 1
	_current_case = case_name
	var failures_before := _failure_count
	print("[TEST] %s" % case_name)
	await test_callable.call()
	if _failure_count == failures_before:
		print("[PASS] %s" % case_name)
	else:
		_failed_case_count += 1


func _layout() -> void:
	for _frame in LAYOUT_FRAMES:
		await process_frame


func _game(window: Vector2i) -> VaultGame:
	root.size = window
	var game := _spawn_game()
	game.begin_shift()
	game.user_paused = true
	return game


func _text_width(label: Label) -> float:
	var font := label.get_theme_font("font")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x


func _assert_fits(game: VaultGame, context: String) -> void:
	var orders := game.player_orders
	var row := orders.clock_label.get_parent() as HBoxContainer
	var view := root.get_visible_rect()
	_assert_equal(view.size.x, 1280.0, "%s: the UI lays out at the 1280 design width" % context)
	var room := row.size.x - row.get_combined_minimum_size().x
	_assert_true(room >= SPARE, "%s: the top row's minimum leaves %.0f px spare (>= %d)" % [context, room, SPARE])
	for child: Node in row.get_children():
		var control := child as Control
		if control == null or not control.visible:
			continue
		var rect := control.get_global_rect()
		_assert_true(rect.position.x >= view.position.x and rect.end.x <= view.end.x - SPARE + 2.0, "%s: '%s' is on screen (x %.0f..%.0f of %.0f)" % [context, str(control.get("text")), rect.position.x, rect.end.x, view.end.x])
	var last := row.get_child(row.get_child_count() - 1) as Button
	_assert_equal(last.text, "3x", "%s: 3x is the last control" % context)
	_assert_true(last.get_global_rect().end.x <= view.end.x - SPARE + 2.0, "%s: 3x ends %.0f px inside the screen edge" % [context, view.end.x - last.get_global_rect().end.x])
	for label: Label in [orders.clock_label, orders.resource_label, orders.power_label]:
		var spare := label.size.x - _text_width(label)
		_assert_true(spare >= 0.0, "%s: '%s' reads in full (%.0f px spare)" % [context, label.text, spare])


func _test_fresh(window: Vector2i) -> void:
	var game := _game(window)
	game.player_orders.refresh()
	await _layout()
	_assert_fits(game, "fresh")
	_dispose(game)


func _test_busiest(window: Vector2i, resource_text := "") -> void:
	var game := _game(window)
	for index in 6:
		var lamp := _add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(18 + index, 12))
		lamp.powered = true
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(18, 13))
	game.food_system.meals = 188
	game.food_system.raw_food = 188
	game.food_system.salvage = 188
	game.day_cycle.deserialize({"elapsed_seconds": 59.0 * 60.0 + 59.0, "current_day": 7, "completed": false})
	game.power_grid.recalculate(game.buildings)
	game.player_orders.refresh()
	if not resource_text.is_empty():
		# Hold the per-frame HUD refresh so the injected line is what gets laid out.
		game.set_process(false)
		game.player_orders.resource_label.text = resource_text
	await _layout()
	_assert_true(game.power_grid.brownout_active, "busiest: the grid is browned out (longest power text)")
	_assert_true(game.player_orders.power_label.text.contains("shed") and game.player_orders.power_label.text.contains("BROWNOUT"), "busiest: power text names shed load and BROWNOUT")
	_assert_true(game.player_orders.resource_label.text.contains("188"), "busiest: three-digit stocks")
	_assert_fits(game, "busiest")
	_dispose(game)


func _test_overlong() -> void:
	var game := _game(Vector2i(1280, 720))
	var orders := game.player_orders
	orders.refresh()
	game.set_process(false)
	orders.power_label.text = "PWR 88/88 used · 88 shed · BROWNOUT"
	orders.resource_label.text = MEALS_DAYS_LINE + "  " + MEALS_DAYS_LINE
	await _layout()
	var row := orders.clock_label.get_parent() as HBoxContainer
	var view := root.get_visible_rect()
	_assert_true(orders.resource_label.clip_text, "the stats clip")
	_assert_true(_text_width(orders.resource_label) > orders.resource_label.size.x, "the overlong line really is wider than its slot")
	_assert_true(row.size.x - row.get_combined_minimum_size().x >= SPARE, "the row minimum still leaves %d px" % SPARE)
	var last := row.get_child(row.get_child_count() - 1) as Button
	_assert_true(last.text == "3x" and last.get_global_rect().end.x <= view.end.x - SPARE + 2.0, "3x stays on screen")
	_assert_true(orders.power_label.size.x >= _text_width(orders.power_label), "the BROWNOUT power status still reads in full")
	_dispose(game)
