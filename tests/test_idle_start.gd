extends "res://tests/test_runner.gd"

# QA-d #8 idle start: a two-step card offered only for a wing nobody has touched by 30 s.

const PREFS := "user://test_idle_start_prefs.cfg"


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	_run_case("the idle start is offered only for an untouched wing from 30 s", _test_gate)
	_run_case("a baseline-style opening (digs at 0 s, bunks at 32 s) never sees it", _test_baseline_opening)
	_run_case("step 1 queues the standard opening, step 2 the Air Recycler", _test_steps)
	_run_case("a blocked cell refuses step 1 and places nothing", _test_blocked)
	_run_case("dismissal is per profile and final", _test_dismiss)
	_run_case("the idle start save key is additive, versioned and validated", _test_save)
	_run_case("the right-panel card walks step 1, step 2 and dismissal", _test_card)
	_run_case("the card never changes the Next hint", _test_next_unchanged)
	_run_case("every card text fits the right panel with 12 px to spare", _test_texts_fit)
	_finish()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))


func _finish() -> void:
	print("")
	if _failure_count == 0:
		print("IDLE START TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("IDLE START TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _game() -> VaultGame:
	var game := _spawn_game()
	game.idle_start_prefs_path = PREFS
	game.begin_shift()
	return game


func _advance_to(game: VaultGame, seconds: float) -> void:
	while game.day_cycle.elapsed_seconds < seconds - 0.0001 and not game.ended:
		game.step_simulation(VaultGame.SIMULATION_TICK)


func _test_gate() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var game := _game()
	_assert_false(game.can_offer_idle_start(), "not at 0 s")
	_advance_to(game, 29.5)
	_assert_false(game.can_offer_idle_start(), "not at 29.5 s")
	_advance_to(game, 30.0)
	_assert_true(game.can_offer_idle_start(), "offered at 30 s on an untouched wing")
	_assert_true(game.map_grid.queue_dig(Vector2i(16, 13)), "a dig mark")
	_assert_false(game.can_offer_idle_start(), "an open dig mark withdraws it")
	game.map_grid.cancel_dig(Vector2i(16, 13))
	_assert_true(game.can_offer_idle_start(), "a cancelled mark leaves the wing untouched")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(27, 12)), "a bunk blueprint")
	_assert_false(game.can_offer_idle_start(), "a blueprint withdraws it")
	game.set_tool("cancel")
	_assert_true(game.issue_order(Vector2i(27, 12)), "the bunk is cancelled")
	_assert_false(game.can_offer_idle_start(), "a cancelled blueprint still counts as built")
	_dispose(game)
	game = _game()
	_advance_to(game, 30.0)
	game.map_grid.queue_dig(Vector2i(16, 13))
	game.map_grid.apply_dig_work(Vector2i(16, 13), 99.0)
	_assert_true(game.map_grid.dig_marks.is_empty(), "the dig finished")
	_assert_false(game.can_offer_idle_start(), "carved rock withdraws it")
	_dispose(game)
	game = _game()
	_advance_to(game, 30.0)
	game.breach_system.phase = BreachSystem.Phase.OPEN
	_assert_false(game.can_offer_idle_start(), "not once the hatch is open")
	game.breach_system.phase = BreachSystem.Phase.WARNING
	_assert_false(game.can_offer_idle_start(), "not during the warning (its modal and readouts own the panel)")
	game.breach_system.phase = BreachSystem.Phase.DORMANT
	game.ended = true
	_assert_false(game.can_offer_idle_start(), "not once ended")
	_dispose(game)


func _test_baseline_opening() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var game := _game()
	for x: int in [16, 15, 14]:
		if game.map_grid.queue_dig(Vector2i(x, 13)):
			game.job_system.queue_dig(Vector2i(x, 13))
	var seen := false
	var bunks := false
	while game.day_cycle.elapsed_seconds < 60.0 and not game.ended:
		if game.day_cycle.elapsed_seconds >= 32.0 and not bunks:
			bunks = true
			game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(27, 12))
			game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(26, 12))
		seen = seen or game.can_offer_idle_start() or game.idle_start_air_pending()
		game.step_simulation(VaultGame.SIMULATION_TICK)
	_assert_false(seen, "never offered across 0-60 s")
	_assert_false(game.create_snapshot().has(VaultGame.IDLE_START_KEY), "no save key")
	_dispose(game)


func _test_steps() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var game := _game()
	_assert_false(game.apply_idle_start(), "step 1 refused before 30 s")
	_assert_false(game.place_idle_start_air(), "step 2 refused before step 1")
	_advance_to(game, 30.0)
	var before := game.buildings.size()
	_assert_true(game.apply_idle_start(), "step 1 applies")
	_assert_equal(game.buildings.size(), before + VaultGame.IDLE_START_PIECES.size(), "five blueprints")
	for piece: Array in VaultGame.IDLE_START_PIECES:
		var building := game.get_building_at(piece[1])
		_assert_true(building != null and building.kind == int(piece[0]) and not building.complete, "%s blueprint at %s" % [VaultBuilding.KIND_NAMES[piece[0]], piece[1]])
	_assert_equal(game.map_grid.dig_marks.size(), 25, "all 25 standard digs are marked (x 16->12 keeps each column connected)")
	_assert_true(game.map_grid.dig_marks.has(Vector2i(16, 13)), "starting at the chamber edge")
	_assert_equal(game.idle_start_stage, 1, "stage 1")
	_assert_false(game.can_offer_idle_start(), "step 1 is not offered twice")
	_assert_false(game.apply_idle_start(), "and cannot be applied twice")
	_assert_true(game.idle_start_air_pending(), "the Air Recycler is the explicit second step")
	_assert_true(game.place_idle_start_air(), "step 2 applies")
	var air := game.get_building_at(VaultGame.IDLE_START_AIR_CELL)
	_assert_true(air != null and air.kind == VaultBuilding.Kind.AIR_RECYCLER, "Air Recycler blueprint at %s" % VaultGame.IDLE_START_AIR_CELL)
	_assert_equal(game.idle_start_stage, 2, "stage 2: done")
	_assert_false(game.idle_start_air_pending(), "nothing pending")
	_assert_false(game.place_idle_start_air(), "step 2 cannot repeat")
	_dispose(game)
	game = _game()
	_advance_to(game, 30.0)
	game.apply_idle_start()
	game.place_blueprint(VaultBuilding.Kind.LAMP, VaultGame.IDLE_START_AIR_CELL)
	_assert_false(game.place_idle_start_air(), "a taken Air cell refuses step 2")
	_assert_equal(game.idle_start_stage, 1, "and keeps it pending")
	_dispose(game)


func _test_blocked() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var game := _game()
	_advance_to(game, 30.0)
	_add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(23, 12))
	game._idle_start_next_id = game.next_building_id
	_assert_true(game.can_offer_idle_start(), "offered (test fixture counted as start)")
	var before := game.buildings.size()
	_assert_false(game.apply_idle_start(), "the Grow Tray cell is taken: refused")
	_assert_equal(game.buildings.size(), before, "nothing placed")
	_assert_true(game.map_grid.dig_marks.is_empty(), "no digs marked")
	_assert_equal(game.idle_start_stage, 0, "still stage 0")
	_dispose(game)


func _test_dismiss() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var game := _game()
	_advance_to(game, 30.0)
	_assert_false(game.idle_start_dismissed(), "not dismissed yet")
	game.dismiss_idle_start()
	_assert_false(game.can_offer_idle_start(), "dismissed: withdrawn")
	_assert_true(FileAccess.file_exists(PREFS), "saved to the profile")
	game.new_game(false)
	game.idle_start_prefs_path = PREFS
	game.begin_shift()
	_advance_to(game, 30.0)
	_assert_false(game.can_offer_idle_start(), "a new wing does not offer it again")
	_dispose(game)
	game = _game()
	game._idle_start_dismissed_cache.clear()
	_advance_to(game, 30.0)
	_assert_false(game.can_offer_idle_start(), "a fresh game instance reads the profile too")
	_dispose(game)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	game = _game()
	_advance_to(game, 30.0)
	game.apply_idle_start()
	var pending: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	game.dismiss_idle_start()
	_assert_false(game.idle_start_air_pending(), "dismissing step 2 hides the Air step")
	_assert_false(game.create_snapshot().has(VaultGame.IDLE_START_KEY), "and leaves no save key")
	_assert_true(game.apply_snapshot(pending), "a save made with the Air step pending loads")
	_assert_equal(game.idle_start_stage, 1, "its stage is restored")
	_assert_false(game.idle_start_air_pending(), "but a dismissed profile never sees the Air step")
	_dispose(game)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))


func _test_save() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var game := _game()
	_advance_to(game, 30.0)
	_assert_false(game.create_snapshot().has(VaultGame.IDLE_START_KEY), "stage 0: no key")
	var keys_before := game.create_snapshot().keys()
	game.apply_idle_start()
	var snapshot := game.create_snapshot()
	_assert_true(snapshot.has(VaultGame.IDLE_START_KEY), "stage 1: key written")
	if not snapshot.has(VaultGame.IDLE_START_KEY):
		_dispose(game)
		return
	_assert_equal(snapshot[VaultGame.IDLE_START_KEY], {"version": 1, "stage": 1}, "versioned payload")
	_assert_equal(snapshot.keys().slice(0, keys_before.size()), keys_before, "additive: appended after the existing keys")
	var copy: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	game.new_game(false)
	_assert_true(game.apply_snapshot(copy), "loads")
	_assert_equal(game.idle_start_stage, 1, "stage 1 restored")
	_assert_true(game.idle_start_air_pending(), "the Air step survives a reload")
	var bad: Dictionary = copy.duplicate(true)
	bad[VaultGame.IDLE_START_KEY]["version"] = 2
	_assert_false(game.apply_snapshot(bad), "unknown version rejected")
	bad[VaultGame.IDLE_START_KEY] = {"version": 1, "stage": 2}
	_assert_false(game.apply_snapshot(bad), "stage outside 1 rejected")
	bad[VaultGame.IDLE_START_KEY] = "x"
	_assert_false(game.apply_snapshot(bad), "non-dictionary rejected")
	game.place_idle_start_air()
	_assert_false(game.create_snapshot().has(VaultGame.IDLE_START_KEY), "stage 2: no key")
	_dispose(game)
	game = _game()
	var plain: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	_assert_true(game.apply_snapshot(plain), "an untouched save loads")
	_advance_to(game, 31.0)
	_assert_false(game.can_offer_idle_start(), "a loaded save never re-offers step 1")
	_dispose(game)


func _card(game: VaultGame) -> String:
	var orders := game.player_orders
	orders.refresh()
	if orders.idle_start_box == null or not orders.idle_start_box.visible:
		return "<hidden>"
	return "%s | %s" % [orders.idle_start_header.text, orders.idle_start_button.text]


func _test_card() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var game := _game()
	_assert_true(game.player_orders.get("idle_start_box") != null, "the card exists")
	if game.player_orders.get("idle_start_box") == null:
		_dispose(game)
		return
	_assert_equal(_card(game), "<hidden>", "hidden at 0 s")
	_advance_to(game, 30.0)
	_assert_equal(_card(game), "IDLE START · 1/2 · beds, food, power | Recommended start", "step 1 at 30 s")
	_assert_true(game.player_orders.idle_start_box.get_parent() == game.player_orders.alert_label.get_parent(), "in the right-panel summary")
	_assert_equal(game.player_orders.idle_start_box.get_index(), game.player_orders.alert_label.get_index() + 1, "directly under the alerts")
	game.player_orders.idle_start_button.pressed.emit()
	_assert_equal(game.idle_start_stage, 1, "the button applies step 1")
	_assert_equal(_card(game), "IDLE START · 2/2 · air | Place Air Recycler · 14 salvage", "then names the Air Recycler")
	var orders = game.player_orders
	_assert_equal(orders.idle_start_box.get_parent(), orders.alert_label.get_parent(), "the card shares the alert's summary block")
	_assert_equal(orders.idle_start_box.get_index(), orders.alert_label.get_index() + 1, "directly under the alert, ahead of the upgrade offer")
	game.breach_system.phase = BreachSystem.Phase.WARNING
	_assert_equal(_card(game), "<hidden>", "the hatch warning hides the card")
	game.breach_system.phase = BreachSystem.Phase.OPEN
	_assert_equal(_card(game), "IDLE START · 2/2 · air | Place Air Recycler · 14 salvage", "and it returns after")
	game.breach_system.phase = BreachSystem.Phase.DORMANT
	game.player_orders.idle_start_button.pressed.emit()
	_assert_equal(game.idle_start_stage, 2, "the button applies step 2")
	_assert_equal(_card(game), "<hidden>", "done: hidden")
	_dispose(game)
	game = _game()
	_advance_to(game, 30.0)
	_assert_equal(_card(game), "IDLE START · 1/2 · beds, food, power | Recommended start", "offered")
	_assert_equal(game.player_orders.idle_start_dismiss_button.text, "Dismiss · don't offer again", "dismiss is labelled")
	game.player_orders.idle_start_dismiss_button.pressed.emit()
	_assert_equal(_card(game), "<hidden>", "dismissed: hidden")
	_assert_equal(game.buildings.size(), 3, "dismiss places nothing")
	_assert_true(game.map_grid.dig_marks.is_empty(), "and marks nothing")
	_advance_to(game, 45.0)
	_assert_equal(_card(game), "<hidden>", "and stays hidden")
	_dispose(game)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))


func _test_next_unchanged() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var game := _game()
	_advance_to(game, 30.0)
	game.player_orders.refresh()
	var with_card := game.player_orders.objective_label.text
	var alert := game.player_orders.alert_label.text
	_assert_true(game.player_orders.idle_start_box.visible, "card visible")
	game.dismiss_idle_start()
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, with_card, "Next text identical with and without the card")
	_assert_equal(game.player_orders.alert_label.text, alert, "alert text identical")
	_dispose(game)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))


func _panel_width(orders: PlayerOrders) -> float:
	var width := VaultGame.RIGHT_PANEL_WIDTH
	var node: Node = orders.idle_start_box.get_parent()
	while node is Control:
		if node is PanelContainer:
			width -= (node as PanelContainer).get_theme_stylebox("panel").get_minimum_size().x
			break
		if node is MarginContainer:
			width -= (node as Control).get_theme_constant("margin_left") + (node as Control).get_theme_constant("margin_right")
		node = node.get_parent()
	return width


func _text_width(control: Control, text: String) -> float:
	return control.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, control.get_theme_font_size("font_size")).x


func _test_texts_fit() -> void:
	var game := _spawn_game()
	var orders := game.player_orders
	var width := _panel_width(orders)
	var button_chrome := orders.idle_start_button.get_theme_stylebox("normal").get_minimum_size().x
	for text: String in ["Recommended start", "Place Air Recycler · 14 salvage", "Place Air Recycler · 999 salvage"]:
		var room := width - button_chrome - _text_width(orders.idle_start_button, text)
		_assert_true(room >= 12.0, "button '%s' fits with %.0f px to spare" % [text, room])
	var dismiss_room := width - orders.idle_start_dismiss_button.get_theme_stylebox("normal").get_minimum_size().x - _text_width(orders.idle_start_dismiss_button, "Dismiss · don't offer again")
	_assert_true(dismiss_room >= 12.0, "dismiss fits with %.0f px to spare" % dismiss_room)
	for text: String in ["IDLE START · 1/2 · beds, food, power", "IDLE START · 2/2 · air"]:
		var room := width - _text_width(orders.idle_start_header, text)
		_assert_true(room >= 12.0, "header '%s' fits with %.0f px to spare" % [text, room])
	_dispose(game)
