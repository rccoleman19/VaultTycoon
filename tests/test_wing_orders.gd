extends "res://tests/test_runner.gd"

# Wing orders (QA 2026-10-18c #3, slice 2): post-seal goals that unlock Charge Node and Air Recycler Mk II.


func _run() -> void:
	_run_case("the orders panel appears only after the seal and leaves Next alone", _test_panel_gating)
	_run_case("fitting a Grow Tray Mk II claims its order at once, even paused, and it stays claimed", _test_fit_order)
	_run_case("16 stored meals claim the stock order; raw food and pre-seal stocks do not", _test_stock_order)
	_run_case("Charge Node Mk II is locked until its order, then gives 10 power at once", _test_charge_mk2)
	_run_case("Air Recycler Mk II is locked until its order, then keeps the air for 2 power", _test_air_mk2)
	_run_case("claims save and load; old saves claim nothing; bad claims are rejected", _test_save)
	_run_case("a new wing clears the claims and an ended wing claims nothing", _test_reset_and_end)
	_run_case("a done order row selects a fixture to fit; the offer stays Grow-only", _test_ui_rows)
	_run_case("a managed wing earns both fits from its own salvage and still wins", _test_playthrough)

	print("")
	if _failure_count == 0:
		print("WING ORDERS TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("WING ORDERS TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
			_failed_case_count,
			_case_count,
			_failure_count,
			_assertion_count,
		])
		quit(1)


# Seals the hatch the way a crew does (patched during WARNING), so the wing can also be saved.
func _seal(game: VaultGame) -> void:
	game.day_cycle.deserialize({"elapsed_seconds": 70.0, "current_day": 2, "completed": false})
	game.breach_system.advance(0.0, 70.0)
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.apply_patch_work(100.0)
	game.job_system.rebuild_from_state()


func _base_game(salvage := 60) -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(22, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(24, 12))
	_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(26, 12))
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.food_system.salvage = salvage
	return game


func _first(game: VaultGame, kind: int) -> VaultBuilding:
	for building: VaultBuilding in game.buildings:
		if building.kind == kind and not building.is_emergency_core:
			return building
	return null


func _core(game: VaultGame) -> VaultBuilding:
	for building: VaultBuilding in game.buildings:
		if building.is_emergency_core:
			return building
	return null


func _step(game: VaultGame) -> void:
	game.user_paused = false
	game.step_simulation(VaultGame.SIMULATION_TICK)


func _test_panel_gating() -> void:
	var game := _base_game()
	var orders := game.player_orders
	orders.refresh()
	_assert_false(orders.wing_orders_box.visible, "hidden before the seal")
	var next_before := str(orders._primary_next_step()["text"])
	_seal(game)
	orders.refresh()
	_assert_true(orders.wing_orders_box.visible, "shown after the seal")
	_assert_equal(orders.wing_orders_header.text, "WING ORDERS · 0/2", "header counts claims")
	_assert_true(orders.wing_orders_box.get_parent() != orders.details_box, "outside DETAILS")
	_assert_equal((orders.wing_order_rows[VaultGame.ORDER_FIT_GROW_MK2] as Button).text, "[  ] Fit Grow Mk II → Charge Mk II", "fit order text")
	_assert_rows_fit(orders, "open rows")
	_assert_true((orders.wing_order_rows[VaultGame.ORDER_STOCK_MEALS] as Button).text.begins_with("[  ] Stock 16 meals ("), "stock order shows progress")
	_assert_false(str(orders._primary_next_step()["text"]).contains("ORDER"), "Next does not carry orders")
	_assert_false(orders.objective_label.text.contains("Stock 16"), "the objective label does not carry orders")
	_assert_true(next_before != "", "Next still computes")
	_dispose(game)


func _test_fit_order() -> void:
	var game := _base_game()
	_seal(game)
	var tray := _first(game, VaultBuilding.Kind.GROW_TRAY)
	game.user_paused = true
	_assert_true(game.upgrade_building(tray.building_id), "Grow Mk II bought while paused")
	_assert_true(VaultGame.ORDER_FIT_GROW_MK2 in game.wing_orders_claimed, "claimed immediately on purchase")
	_assert_true(game.deconstruct_building(tray.building_id), "the tray is removed before resuming")
	_step(game)
	_assert_true(VaultGame.ORDER_FIT_GROW_MK2 in game.wing_orders_claimed, "removal does not revoke the claim")
	_assert_equal(game.wing_orders_claimed.count(VaultGame.ORDER_FIT_GROW_MK2), 1, "claimed once")
	_assert_true(game.is_upgrade_unlocked(VaultBuilding.Kind.GENERATOR), "Charge Node Mk II unlocked")
	_assert_false(game.is_upgrade_unlocked(VaultBuilding.Kind.AIR_RECYCLER), "Air Recycler Mk II still locked")
	# A slice-1 save that already holds a Mk II tray qualifies on its next sealed tick.
	var old := _base_game()
	_seal(old)
	_first(old, VaultBuilding.Kind.GROW_TRAY).upgrade_tier = 2
	_assert_false(VaultGame.ORDER_FIT_GROW_MK2 in old.wing_orders_claimed, "not claimed before a tick")
	_step(old)
	_assert_true(VaultGame.ORDER_FIT_GROW_MK2 in old.wing_orders_claimed, "claimed by the tick checker")
	_dispose(old)
	_dispose(game)


func _test_stock_order() -> void:
	var game := _base_game()
	game.food_system.meals = 30
	_step(game)
	_assert_false(VaultGame.ORDER_STOCK_MEALS in game.wing_orders_claimed, "no claim before the seal")
	_seal(game)
	game.food_system.meals = 15
	game.food_system.raw_food = 40
	_step(game)
	_assert_false(VaultGame.ORDER_STOCK_MEALS in game.wing_orders_claimed, "15 meals plus raw food is not 16 meals")
	game.food_system.meals = 16
	_step(game)
	_assert_true(VaultGame.ORDER_STOCK_MEALS in game.wing_orders_claimed, "16 stored meals claim")
	game.food_system.meals = 2
	_step(game)
	_assert_true(VaultGame.ORDER_STOCK_MEALS in game.wing_orders_claimed, "eating the meals does not revoke")
	_assert_true(game.is_upgrade_unlocked(VaultBuilding.Kind.AIR_RECYCLER), "Air Recycler Mk II unlocked")
	_dispose(game)


func _test_charge_mk2() -> void:
	var game := _base_game()
	_seal(game)
	var node := _first(game, VaultBuilding.Kind.GENERATOR)
	_assert_false(game.upgrade_building(node.building_id), "locked before the order")
	_assert_equal(game.food_system.salvage, 60, "nothing spent")
	game.wing_orders_claimed.append(VaultGame.ORDER_FIT_GROW_MK2)
	_assert_false(game.upgrade_building(_core(game).building_id), "the emergency core can never be fitted")
	var supply_before := game.power_grid.supply
	game.user_paused = true
	_assert_true(game.upgrade_building(node.building_id), "Charge Node Mk II bought")
	_assert_equal(game.food_system.salvage, 42, "exactly 18 spent")
	_assert_equal(node.get_power_output(), 10, "10 power")
	_assert_equal(_core(game).get_power_output(), 2, "the core stays at 2")
	_assert_equal(game.power_grid.supply, supply_before + 3, "the grid gains 3 at once, while paused")
	_assert_equal(node.get_display_name(), "Charge Node Mk II", "name shows Mk II")
	_assert_equal(node.get_deconstruct_refund(), 18, "refund is half of 18 + 18")
	_assert_false(game.upgrade_building(node.building_id), "no second fit")
	_assert_equal(game.food_system.salvage, 42, "no repeat charge")
	game.food_system.salvage = 17
	var other := _add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(28, 12))
	_assert_false(game.upgrade_building(other.building_id), "17 salvage is not enough")
	_assert_equal(game.food_system.salvage, 17, "no partial debit")
	_dispose(game)


func _test_air_mk2() -> void:
	var game := _base_game()
	_seal(game)
	var air := _first(game, VaultBuilding.Kind.AIR_RECYCLER)
	_assert_false(game.upgrade_building(air.building_id), "locked before the order")
	game.wing_orders_claimed.append(VaultGame.ORDER_STOCK_MEALS)
	var demand_before := game.power_grid.demand
	var output_before := game.oxygen_system.recycler_output_rate
	game.user_paused = true
	_assert_true(game.upgrade_building(air.building_id), "Air Recycler Mk II bought")
	_assert_equal(air.get_base_power_demand(), 2, "draws 2 power")
	_assert_equal(game.power_grid.demand, demand_before - 1, "grid demand falls by 1 at once")
	_assert_true(air.powered, "still powered")
	_assert_approximately(game.oxygen_system.recycler_output_rate, output_before, 0.0001, "same air output")
	_assert_equal(air.get_deconstruct_refund(), 16, "refund is half of 14 + 18")
	_assert_equal(air.get_display_name(), "Air Recycler Mk II", "name shows Mk II")
	_dispose(game)


func _test_save() -> void:
	var game := _base_game()
	_seal(game)
	game.wing_orders_claimed.append(VaultGame.ORDER_FIT_GROW_MK2)
	var node := _first(game, VaultBuilding.Kind.GENERATOR)
	_assert_true(game.upgrade_building(node.building_id), "Charge Mk II bought")
	var node_id := node.building_id
	var snap: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	_assert_equal(snap.get("wing_orders"), {"claimed": [VaultGame.ORDER_FIT_GROW_MK2]}, "claims are saved")
	game.wing_orders_claimed.append(VaultGame.ORDER_STOCK_MEALS)
	_assert_true(game.apply_snapshot(snap), "the save loads")
	_assert_equal(game.wing_orders_claimed, [VaultGame.ORDER_FIT_GROW_MK2] as Array[String], "claims restored, live extras dropped")
	_assert_equal(game.get_building_by_id(node_id).get_power_output(), 10, "Charge Mk II restored")
	var supply := game.power_grid.supply
	for bad: Variant in [[], {"claimed": "x"}, {"claimed": ["nope"]}, {"claimed": [VaultGame.ORDER_FIT_GROW_MK2, VaultGame.ORDER_FIT_GROW_MK2]}, {"claimed": [1]}, {}]:
		var tampered := snap.duplicate(true)
		tampered["wing_orders"] = bad
		_assert_false(game.apply_snapshot(tampered), "wing_orders %s rejected" % str(bad))
	var no_claim := snap.duplicate(true)
	no_claim["wing_orders"] = {"claimed": []}
	_assert_false(game.apply_snapshot(no_claim), "a Charge Mk II without its claim is rejected")
	var air_snap := snap.duplicate(true)
	for entry: Dictionary in air_snap["buildings"]:
		if int(entry["kind"]) == VaultBuilding.Kind.AIR_RECYCLER:
			entry["upgrade_tier"] = 2
	_assert_false(game.apply_snapshot(air_snap), "an Air Mk II without the stock claim is rejected")
	air_snap["wing_orders"] = {"claimed": [VaultGame.ORDER_FIT_GROW_MK2, VaultGame.ORDER_STOCK_MEALS]}
	_assert_equal(game.wing_orders_claimed, [VaultGame.ORDER_FIT_GROW_MK2] as Array[String], "rejections leave live claims alone")
	_assert_equal(game.power_grid.supply, supply, "and the live grid")
	_assert_true(game.apply_snapshot(air_snap), "with both claims the Air Mk II save loads")
	game.wing_orders_claimed.append(VaultGame.ORDER_STOCK_MEALS)
	var old := snap.duplicate(true)
	old.erase("wing_orders")
	for entry: Dictionary in old["buildings"]:
		entry["upgrade_tier"] = 1
	_assert_true(game.apply_snapshot(old), "a save without wing_orders loads")
	_assert_true(game.wing_orders_claimed.is_empty(), "and claims nothing")
	var old_with_mk2 := snap.duplicate(true)
	old_with_mk2.erase("wing_orders")
	_assert_false(game.apply_snapshot(old_with_mk2), "an old save cannot carry a Charge Mk II")
	_dispose(game)


func _test_reset_and_end() -> void:
	var game := _base_game()
	_seal(game)
	game.wing_orders_claimed.append(VaultGame.ORDER_FIT_GROW_MK2)
	game.new_game(false)
	_assert_true(game.wing_orders_claimed.is_empty(), "a new wing clears claims")
	game.player_orders.refresh()
	_assert_false(game.player_orders.wing_orders_box.visible, "and hides the panel")
	var ended := _base_game()
	_seal(ended)
	ended.food_system.meals = 30
	ended.ended = true
	ended._check_wing_orders()
	_assert_false(VaultGame.ORDER_STOCK_MEALS in ended.wing_orders_claimed, "an ended wing claims nothing")
	ended.player_orders.refresh()
	_assert_false(ended.player_orders.wing_orders_box.visible, "and shows no orders")
	_dispose(ended)
	_dispose(game)


# Text width plus the button's padding and 24 px of room must fit the laid-out row.
func _assert_rows_fit(orders: PlayerOrders, context: String) -> void:
	for order_id: String in VaultGame.WING_ORDER_IDS:
		var row: Button = orders.wing_order_rows[order_id]
		var font := row.get_theme_font("font")
		var text_width := font.get_string_size(row.text, HORIZONTAL_ALIGNMENT_LEFT, -1, row.get_theme_font_size("font_size")).x
		var padding := row.get_theme_stylebox("normal").get_minimum_size().x
		var room := _row_width(orders) - padding - text_width
		_assert_true(room >= 24.0, "%s: '%s' fits with %.0f px to spare" % [context, row.text, room])


# Tests run without frames, so containers are not laid out yet. Derive the row
# width from the right panel's default width minus every ancestor's padding.
func _row_width(orders: PlayerOrders) -> float:
	var width := VaultGame.RIGHT_PANEL_WIDTH
	var node: Node = orders.wing_orders_box.get_parent()
	while node is Control:
		if node is PanelContainer:
			width -= (node as PanelContainer).get_theme_stylebox("panel").get_minimum_size().x
			break
		if node is MarginContainer:
			width -= (node as Control).get_theme_constant("margin_left") + (node as Control).get_theme_constant("margin_right")
		node = node.get_parent()
	return width


func _test_ui_rows() -> void:
	var game := _base_game(10)
	var orders := game.player_orders
	_seal(game)
	orders.refresh()
	var fit_row: Button = orders.wing_order_rows[VaultGame.ORDER_FIT_GROW_MK2]
	_assert_true(fit_row.disabled, "an open order row is not clickable")
	var node := _first(game, VaultBuilding.Kind.GENERATOR)
	game.select_building(node.building_id)
	orders.refresh()
	_assert_false(orders.fixture_upgrade_row.visible, "no FIT row on a locked Charge Node")
	game.select_building(-1)
	game.food_system.salvage = 30
	var tray := _first(game, VaultBuilding.Kind.GROW_TRAY)
	_assert_true(game.upgrade_building(tray.building_id), "Grow Mk II bought")
	orders.refresh()
	_assert_equal(fit_row.text, "[DONE] Fit Grow Mk II → Charge Mk II", "done text")
	_assert_rows_fit(orders, "a done row")
	_assert_equal(orders.wing_orders_header.text, "WING ORDERS · 1/2", "header 1/2")
	_assert_false(orders.upgrade_offer_button.visible, "the offer stays Grow-only and hides once trays are fitted")
	_assert_false(fit_row.disabled, "the done row is clickable")
	fit_row.pressed.emit()
	_assert_equal(game.selected_building_id, node.building_id, "it selects the Charge Node, not the core")
	orders.refresh()
	_assert_true(orders.fixture_upgrade_row.visible, "the Charge Node shows its FIT row")
	_assert_true(orders.fixture_upgrade_button.disabled, "12 salvage cannot afford it")
	_assert_equal(orders.fixture_upgrade_button.tooltip_text, "Needs 18 salvage (have 12).", "it says what is missing")
	game.food_system.salvage = 20
	orders.refresh()
	_assert_equal(orders.fixture_upgrade_button.tooltip_text, "10 power instead of 7.", "benefit tooltip")
	orders.fixture_upgrade_button.pressed.emit()
	_assert_equal(node.get_power_output(), 10, "the inspector button fits it")
	orders.refresh()
	_assert_true(fit_row.disabled, "no target left: the row is not clickable")
	game.wing_orders_claimed.append(VaultGame.ORDER_STOCK_MEALS)
	orders.refresh()
	_assert_equal((orders.wing_order_rows[VaultGame.ORDER_STOCK_MEALS] as Button).text, "[DONE] Stock 16 meals → Air Mk II", "done stock text")
	_assert_rows_fit(orders, "both done")
	_dispose(game)


func _test_playthrough() -> void:
	var game := _spawn_game()
	for cell: Vector2i in [Vector2i(18, 12), Vector2i(19, 12), Vector2i(20, 12), Vector2i(21, 12)]:
		_add_completed_building(game, VaultBuilding.Kind.BED, cell)
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(22, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(25, 12))
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(26, 12))
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(27, 12))
	_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(24, 12))
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.begin_shift()
	var orders := game.player_orders
	var grow_at := -1.0
	var charge_at := -1.0
	while not game.ended and game.day_cycle.elapsed_seconds < DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE + 1.0:
		if game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged:
			game.acknowledge_breach_warning(true)
		if game.breach_system.is_sealed():
			orders.refresh()
			if grow_at < 0.0 and orders.upgrade_offer_button.visible:
				orders.upgrade_offer_button.pressed.emit()
				orders.refresh()
				if not orders.fixture_upgrade_button.disabled:
					orders.fixture_upgrade_button.pressed.emit()
					grow_at = game.day_cycle.elapsed_seconds
			elif grow_at >= 0.0 and charge_at < 0.0:
				var row: Button = orders.wing_order_rows[VaultGame.ORDER_FIT_GROW_MK2]
				if not row.disabled:
					row.pressed.emit()
					orders.refresh()
					if orders.fixture_upgrade_row.visible and not orders.fixture_upgrade_button.disabled:
						orders.fixture_upgrade_button.pressed.emit()
						charge_at = game.day_cycle.elapsed_seconds
			game.select_building(-1)
		game.user_paused = false
		game.step_simulation(0.5)
	print("  playthrough: Grow Mk II at %.1f s, Charge Mk II at %.1f s, claims %s, salvage left %d" % [grow_at, charge_at, game.wing_orders_claimed, game.food_system.salvage])
	_assert_true(game.ended and game.outcome == "win", "the wing wins")
	_assert_true(grow_at > 0.0 and grow_at < 280.0, "Grow Mk II bought from earned salvage (%.1f s)" % grow_at)
	_assert_true(charge_at > grow_at and charge_at < 280.0, "Charge Mk II bought after its order (%.1f s)" % charge_at)
	_assert_true(VaultGame.ORDER_FIT_GROW_MK2 in game.wing_orders_claimed, "the fit order is claimed")
	_dispose(game)
