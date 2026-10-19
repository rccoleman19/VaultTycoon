extends "res://tests/test_runner.gd"

# Post-seal pacing (QA-d #2/#3/#4): life support is supplied first after the seal; a player-started
# reclamation income funds a choice every ~30 s.


func _run() -> void:
	_run_case("after the seal, life-support blueprints are supplied before others", _test_life_support_rule)
	_run_case("a second Grow Tray cannot take the Air Recycler's salvage", _test_life_support_sim)
	_run_case("reclamation is a post-seal choice the player starts once", _test_reclaim_gate)
	_run_case("reclamation pays +18 every 30 s, 6 times, then stops", _test_reclaim_schedule)
	_run_case("the reclamation save key is additive, versioned and validated", _test_reclaim_save)
	_run_case("with reclamation started, cooking and meal haul lead until Stock 16 is met", _test_meal_priority)
	_run_case("the Mk II offer covers every unlocked fit and an unpowered tray", _test_offer_order)
	_run_case("idle post-seal salvage is pointed at the next useful build", _test_salvage_nudge)
	_run_case("every new post-seal button text fits the right panel", _test_texts_fit)
	_finish()


func _finish() -> void:
	print("")
	if _failure_count == 0:
		print("POST-SEAL TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("POST-SEAL TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


# A save-valid seal (same as test_wing_orders): day 2, hatch patched.
func _seal(game: VaultGame) -> void:
	game.day_cycle.deserialize({"elapsed_seconds": 70.0, "current_day": 2, "completed": false})
	game.breach_system.advance(0.0, 70.0)
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.apply_patch_work(100.0)
	game.job_system.rebuild_from_state()


func _blueprint(game: VaultGame, kind: int, cell: Vector2i) -> VaultBuilding:
	_assert_true(game.place_blueprint(kind, cell), "%s blueprint placed at %s" % [VaultBuilding.KIND_NAMES[kind], cell])
	for building: VaultBuilding in game.buildings:
		if building.cell == cell and building.kind == kind:
			return building
	return null


func _test_life_support_rule() -> void:
	var game := _spawn_game()
	game.begin_shift()
	var air := _blueprint(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(24, 12))
	var tray := _blueprint(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12))
	var charge := _blueprint(game, VaultBuilding.Kind.GENERATOR, Vector2i(21, 12))
	_assert_false(game.job_system._life_support_waiting(tray), "pre-seal: the tray never waits")
	_seal(game)
	_assert_true(game.job_system._life_support_waiting(tray), "sealed: the tray waits for life support")
	_assert_false(game.job_system._life_support_waiting(air), "the Air Recycler never waits")
	_assert_false(game.job_system._life_support_waiting(charge), "a Charge Node never waits")
	air.delivered = air.get_cost()
	_assert_true(game.job_system._life_support_waiting(tray), "an unsupplied Charge Node still holds the tray")
	charge.delivered = charge.get_cost()
	_assert_false(game.job_system._life_support_waiting(tray), "all life support supplied: the tray may take salvage")
	_dispose(game)


func _test_life_support_sim() -> void:
	var game := _spawn_game()
	game.begin_shift()
	_seal(game)
	var tray := _blueprint(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12))
	var air := _blueprint(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(24, 12))
	game.food_system.salvage = 14
	game.step_simulation(40.0)
	_assert_equal(air.delivered, 14, "the Air Recycler gets all 14 salvage")
	_assert_equal(tray.delivered, 0, "the earlier-placed tray gets none")
	_dispose(game)


func _test_reclaim_gate() -> void:
	var game := _spawn_game()
	game.begin_shift()
	var salvage := game.food_system.salvage
	_assert_false(game.can_start_reclamation(), "locked before the seal")
	_assert_false(game.start_reclamation(), "start refused before the seal")
	_assert_equal(game.food_system.salvage, salvage, "no salvage before the seal")
	game.step_simulation(5.0)
	_assert_false(game.reclaim_active, "never starts by itself")
	_assert_false(game.create_snapshot().has(VaultGame.RECLAIM_KEY), "no save key until started")
	_seal(game)
	_assert_true(game.can_start_reclamation(), "offered after the seal")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.reclaim_button.text, "Begin reclamation · +18 salvage", "button names the payout")
	_assert_false(game.player_orders.reclaim_button.disabled, "button live")
	game.food_system.salvage = 0
	game.player_orders.reclaim_button.pressed.emit()
	_assert_true(game.reclaim_active, "the button starts it")
	_assert_equal(game.food_system.salvage, 18, "+18 at once")
	_assert_false(game.start_reclamation(), "only once")
	_assert_equal(game.food_system.salvage, 18, "no second start payout")
	game.player_orders.refresh()
	_assert_true(game.player_orders.reclaim_button.disabled, "button becomes a readout")
	_assert_equal(game.player_orders.reclaim_button.text, "Reclamation · +18 in 30 s · 6 left", "readout counts down")
	game.ended = true
	_assert_false(game.can_start_reclamation(), "an ended wing cannot start it")
	_dispose(game)


func _test_reclaim_schedule() -> void:
	var game := _spawn_game()
	game.begin_shift()
	_seal(game)
	game.food_system.salvage = 0
	game.start_reclamation()
	game.food_system.salvage = 0
	game._advance_reclamation(29.9)
	_assert_equal(game.food_system.salvage, 0, "nothing before 30 s")
	game._advance_reclamation(0.1)
	_assert_equal(game.food_system.salvage, 18, "+18 at 30 s")
	game._advance_reclamation(95.0)
	_assert_equal(game.food_system.salvage, 72, "+18 at 60, 90 and 120 s")
	game._advance_reclamation(1000.0)
	_assert_equal(game.food_system.salvage, 108, "stops after 6 deliveries (108)")
	_assert_equal(game.reclaim_paid, 6, "6 paid")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.reclaim_button.text, "Reclamation complete", "complete readout")
	_dispose(game)
	game = _spawn_game()
	game.begin_shift()
	_seal(game)
	game.start_reclamation()
	var before := game.food_system.salvage
	game.ended = true
	game._advance_reclamation(60.0)
	_assert_equal(game.food_system.salvage, before, "an ended wing earns nothing")
	game.ended = false
	game.new_game(false)
	_assert_false(game.reclaim_active, "a new wing resets it")
	_assert_equal(game.reclaim_paid, 0, "paid reset")
	_dispose(game)


func _test_reclaim_save() -> void:
	var game := _spawn_game()
	game.begin_shift()
	_seal(game)
	game.start_reclamation()
	game._advance_reclamation(45.0)
	var snapshot := game.create_snapshot()
	_assert_true(snapshot.has(VaultGame.RECLAIM_KEY), "the key is written once started")
	_assert_equal(snapshot.get(VaultGame.RECLAIM_KEY), {"version": 1, "elapsed": 45.0, "paid": 1}, "additive versioned key")
	_assert_equal(snapshot.keys().back(), VaultGame.RECLAIM_KEY, "appended after every existing key")
	var json := snapshot.duplicate(true)
	var other := game
	other.new_game(false)
	_assert_false(other.reclaim_active, "a new wing starts inactive")
	_assert_true(other.apply_snapshot(json), "round-trip loads")
	_assert_true(other.reclaim_active, "active restored")
	_assert_equal(other.reclaim_paid, 1, "paid restored")
	_assert_true(absf(other.reclaim_elapsed - 45.0) < 0.001, "elapsed restored")
	json.erase(VaultGame.RECLAIM_KEY)
	_assert_true(other.apply_snapshot(json), "a save without the key loads")
	_assert_false(other.reclaim_active, "and is inactive")
	for bad: Variant in [5, {"version": 2, "elapsed": 1.0, "paid": 0}, {"version": 1, "elapsed": -1.0, "paid": 0}, {"version": 1, "elapsed": 1.0, "paid": 7}, {"version": 1, "elapsed": "x", "paid": 0}, {"version": 1, "elapsed": 1.0, "paid": 1.5}]:
		var broken := json.duplicate(true)
		broken[VaultGame.RECLAIM_KEY] = bad
		_assert_false(other.apply_snapshot(broken), "rejects %s" % [bad])
	var unsealed: Dictionary = snapshot.duplicate(true)
	unsealed.breach.phase = BreachSystem.Phase.OPEN
	_assert_false(other.apply_snapshot(unsealed), "a save whose hatch is not sealed is already rejected (so the key never meets an unsealed wing)")
	_dispose(game)


func _test_meal_priority() -> void:
	var game := _spawn_game()
	game.begin_shift()
	var jobs := game.job_system
	var cook := JobSystem.JobType.COOK
	var haul := JobSystem.JobType.HAUL_MEAL
	var build := JobSystem.JobType.SUPPLY_BUILD
	game.food_system.meals = 10
	_assert_equal(jobs._job_priority(cook), 20, "pre-seal cook: 20")
	_assert_equal(jobs._job_priority(haul), 45, "pre-seal 10 meals: batching rule (45)")
	_seal(game)
	_assert_equal(jobs._job_priority(cook), 20, "sealed without reclamation: unchanged")
	_assert_equal(jobs._job_priority(haul), 45, "sealed without reclamation: unchanged")
	game.start_reclamation()
	_assert_equal(jobs._job_priority(cook), 8, "reclamation, 10 < 16 meals: cook 8")
	_assert_equal(jobs._job_priority(haul), 9, "and meal haul 9")
	_assert_true(jobs._job_priority(cook) < jobs._job_priority(build), "ahead of blueprint supply")
	game.food_system.meals = 15
	_assert_equal(jobs._job_priority(cook), 8, "15 meals: still 8")
	game.food_system.meals = 16
	_assert_equal(jobs._job_priority(cook), 20, "16 meals: cook back to 20")
	_assert_equal(jobs._job_priority(haul), 45, "16 meals: haul back to 45")
	game.food_system.meals = 10
	var air := _blueprint(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(24, 12))
	_assert_equal(jobs._job_priority(cook), 20, "an unfinished Air Recycler keeps building first")
	air.delivered = air.get_cost()
	_assert_equal(jobs._job_priority(cook), 20, "supplied but not built still counts")
	air.complete = true
	_assert_equal(jobs._job_priority(cook), 8, "once built, cooking leads again")
	var charge := _blueprint(game, VaultBuilding.Kind.GENERATOR, Vector2i(21, 12))
	_assert_equal(jobs._job_priority(cook), 20, "an unfinished Charge Node also keeps building first")
	charge.complete = true
	game.wing_orders_claimed.append(VaultGame.ORDER_STOCK_MEALS)
	_assert_equal(jobs._job_priority(cook), 20, "order claimed: back to 20")
	game.food_system.meals = 4
	_assert_equal(jobs._job_priority(haul), 18, "the low-meal haul rule still applies")
	_dispose(game)


func _offer(game: VaultGame) -> String:
	game.player_orders.refresh()
	return game.player_orders.upgrade_offer_button.text if game.player_orders.upgrade_offer_button.visible else "<hidden>"


func _offer_game() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(22, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(24, 12))
	_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(26, 12))
	game.power_grid.recalculate(game.buildings)
	game.food_system.salvage = 0
	return game


func _of_kind(game: VaultGame, kind: int, index := 0) -> VaultBuilding:
	var found := []
	for building: VaultBuilding in game.buildings:
		if building.kind == kind and not building.is_emergency_core:
			found.append(building)
	return found[index]


func _test_offer_order() -> void:
	var game := _offer_game()
	_assert_equal(_offer(game), "<hidden>", "hidden before the seal")
	_seal(game)
	_assert_equal(_offer(game), "Grow Tray Mk II · 18 salvage", "Grow first, shown even when unaffordable")
	_of_kind(game, VaultBuilding.Kind.GROW_TRAY).upgrade_tier = 2
	game._check_wing_orders()
	_assert_equal(_offer(game), "Charge Mk II · 18 · +3 power", "then the unlocked Charge fit")
	game.player_orders._on_upgrade_offer_pressed()
	_assert_equal(game.selected_building_id, _of_kind(game, VaultBuilding.Kind.GENERATOR).building_id, "the offer selects the Charge Node")
	var tray2 := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 13))
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_false(tray2.powered, "the second tray is unpowered at 9/9")
	_assert_equal(_offer(game), "Tray unpowered · Charge Mk II 18", "an unpowered tray puts Charge first and says why")
	_of_kind(game, VaultBuilding.Kind.GENERATOR).upgrade_tier = 2
	game.power_grid.recalculate(game.buildings)
	_assert_true(tray2.powered, "Charge Mk II powers it")
	_assert_equal(_offer(game), "Grow Tray Mk II · 18 salvage", "then the second tray's Grow fit")
	tray2.upgrade_tier = 2
	game.food_system.salvage = 0
	_assert_equal(_offer(game), "<hidden>", "Air locked, nothing to fit, no idle salvage")
	game.wing_orders_claimed.append(VaultGame.ORDER_STOCK_MEALS)
	_assert_equal(_offer(game), "Air Mk II · 18 salvage · -1 power", "Stock 16 unlocks the Air fit offer")
	_of_kind(game, VaultBuilding.Kind.AIR_RECYCLER).upgrade_tier = 2
	_assert_equal(_offer(game), "<hidden>", "all fitted")
	game.ended = true
	_assert_equal(_offer(game), "<hidden>", "hidden once ended")
	_dispose(game)


func _test_salvage_nudge() -> void:
	var game := _offer_game()
	_seal(game)
	_of_kind(game, VaultBuilding.Kind.GROW_TRAY).upgrade_tier = 2
	_of_kind(game, VaultBuilding.Kind.GENERATOR).upgrade_tier = 2
	game._check_wing_orders()
	game.power_grid.recalculate(game.buildings)
	game.food_system.raw_food = 0
	game.food_system.salvage = 7
	_assert_equal(_offer(game), "<hidden>", "7 salvage: nothing useful is affordable")
	game.food_system.salvage = 28
	_assert_equal(_offer(game), "Spend 28: build Rec Console", "no Rec Console yet: the nudge names one")
	game.player_orders._on_upgrade_offer_pressed()
	_assert_equal(game.active_tool, "rec", "and picks its tool")
	game.food_system.raw_food = 6
	_assert_equal(_offer(game), "Spend 28: build Nutrient Station", "a raw pile of 6 asks for a second Nutrient Station first")
	game.player_orders._on_upgrade_offer_pressed()
	_assert_equal(game.active_tool, "kitchen", "and picks its tool")
	game.food_system.raw_food = 0
	_add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(20, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_equal(_offer(game), "Spend 28: build Grow Tray", "then a second Grow Tray")
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 13))
	_add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(21, 13))
	_add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(21, 14))
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.player_orders._planned_power_spare(), 0, "12 supply, 12 planned demand")
	_assert_equal(_offer(game), "Spend 28: build Charge Node", "no room for a tray's 3 power: a Charge Node first")
	game.player_orders._on_upgrade_offer_pressed()
	_assert_equal(game.active_tool, "generator", "and picks its tool")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(25, 13)), "a planned Charge Node")
	_assert_equal(_offer(game), "Spend 28: build Grow Tray", "a planned Charge Node counts: the tray again")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 13)), "a planned second tray")
	_assert_equal(_offer(game), "<hidden>", "two trays, a Rec Console, no pile: nothing to nudge")
	_dispose(game)
	game = _offer_game()
	_seal(game)
	game.food_system.salvage = 17
	game.food_system.raw_food = 0
	_assert_equal(_offer(game), "Grow Tray Mk II · 18 salvage", "a Mk II fit on offer comes before any build nudge")
	game.player_orders._on_upgrade_offer_pressed()
	_assert_equal(game.selected_building_id, _of_kind(game, VaultBuilding.Kind.GROW_TRAY).building_id, "and selects the tray")
	_dispose(game)
	game = _offer_game()
	game.food_system.salvage = 40
	_assert_equal(game.player_orders.salvage_nudge_kind(), -1, "no nudge before the seal")
	_dispose(game)

# Tests run without frames: derive the width like test_wing_orders (panel width minus padding).
func _room(orders: PlayerOrders, button: Button, text: String) -> float:
	var width := VaultGame.RIGHT_PANEL_WIDTH
	var node: Node = orders.wing_orders_box.get_parent()
	while node is Control:
		if node is PanelContainer:
			width -= (node as PanelContainer).get_theme_stylebox("panel").get_minimum_size().x
			break
		if node is MarginContainer:
			width -= (node as Control).get_theme_constant("margin_left") + (node as Control).get_theme_constant("margin_right")
		node = node.get_parent()
	var font := button.get_theme_font("font")
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
	return width - button.get_theme_stylebox("normal").get_minimum_size().x - text_width


func _test_texts_fit() -> void:
	var game := _spawn_game()
	var orders := game.player_orders
	for text: String in ["Tray unpowered · Charge Mk II 18", "Charge Mk II · 18 · +3 power", "Air Mk II · 18 salvage · -1 power", "Grow Tray Mk II · 18 salvage", "Spend 999: build Nutrient Station", "Spend 999: build Rec Console", "Spend 999: build Charge Node"]:
		var room := _room(orders, orders.upgrade_offer_button, text)
		_assert_true(room >= 12.0, "offer '%s' fits with %.0f px to spare" % [text, room])
	for text: String in ["Begin reclamation · +18 salvage", "Reclamation · +18 in 30 s · 6 left", "Reclamation complete"]:
		var room := _room(orders, orders.reclaim_button, text)
		_assert_true(room >= 12.0, "reclaim '%s' fits with %.0f px to spare" % [text, room])
	_dispose(game)
