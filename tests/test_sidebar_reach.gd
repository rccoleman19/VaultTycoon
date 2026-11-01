extends "res://tests/test_runner.gd"

# Codex VT-20 on #111: after the seal, opening DETAILS must not starve the roster/inspector scroll
# at the 1280x720 desktop layout. Every case awaits real process frames so the containers lay out
# before anything is measured.

const MIN_SCROLL_HEIGHT := 150.0
const LAYOUT_FRAMES := 6
const FOCUS_MARGIN := 24.0
const TEXT_ROOM := 12.0


func _run() -> void:
	await _run_frame_case("post-seal DETAILS keeps a usable roster and inspector scroll at 1280x720", _test_post_seal_details_space)
	await _run_frame_case("the Grow Mk II offer and a done order reveal FIT with DETAILS open, and FIT fits", _test_offer_fit_reachable)
	await _run_frame_case("opening DETAILS shows its readouts at the top, by hand or on an urgency", _test_details_scroll_to_top)
	await _run_frame_case("pre-seal DETAILS still shows every readout and FOCUS HATCH at once", _test_pre_seal_details)
	await _run_frame_case("the right panel holds its width and the Mk II offer fits it", _test_panel_width)

	print("")
	if _failure_count == 0:
		print("SIDEBAR REACH TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("SIDEBAR REACH TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
			_failed_case_count,
			_case_count,
			_failure_count,
			_assertion_count,
		])
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


func _new_game() -> VaultGame:
	root.size = Vector2i(1280, 720)
	var game := _spawn_game()
	game.begin_shift()
	game.user_paused = true
	return game


# A completed tray, Charge and Air, sealed the way a crew does (patched during WARNING).
func _sealed_game() -> VaultGame:
	var game := _new_game()
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(22, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(24, 12))
	_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(26, 12))
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.food_system.salvage = 60
	game.day_cycle.deserialize({"elapsed_seconds": 70.0, "current_day": 2, "completed": false})
	game.breach_system.advance(0.0, 70.0)
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.apply_patch_work(100.0)
	game.job_system.rebuild_from_state()
	game.user_paused = true
	game.player_orders.refresh()
	return game


func _first(game: VaultGame, kind: int) -> VaultBuilding:
	for building: VaultBuilding in game.buildings:
		if building.kind == kind and not building.is_emergency_core:
			return building
	return null


func _set_details(game: VaultGame, expanded: bool) -> void:
	if game.player_orders.details_box.visible != expanded:
		game.player_orders.details_toggle.pressed.emit()
	game.player_orders.refresh()
	await _layout()


func _right_panel(orders: PlayerOrders) -> Control:
	var node: Node = orders.right_scroll
	while node != null and not node is PanelContainer:
		node = node.get_parent()
	return node as Control


func _viewport_rect() -> Rect2:
	return root.get_viewport().get_visible_rect()


func _assert_scroll_usable(orders: PlayerOrders, label: String) -> void:
	var scroll_rect := orders.right_scroll.get_global_rect()
	var viewport := _viewport_rect()
	_assert_true(orders.right_scroll.size.y >= MIN_SCROLL_HEIGHT, "%s: roster/inspector scroll is at least %d px tall (got %.1f)" % [label, MIN_SCROLL_HEIGHT, orders.right_scroll.size.y])
	_assert_true(scroll_rect.position.y >= viewport.position.y and scroll_rect.end.y <= viewport.end.y, "%s: the scroll stays on screen vertically (y %.1f..%.1f)" % [label, scroll_rect.position.y, scroll_rect.end.y])
	_assert_true(_right_panel(orders).get_global_rect().end.y <= viewport.end.y, "%s: the right panel does not grow past the bottom edge" % label)


# On screen means inside the scroll's visible rect for scrolled content, else inside the viewport.
func _assert_on_screen(orders: PlayerOrders, control: Control, label: String) -> void:
	var clip := orders.right_scroll.get_global_rect() if orders.right_scroll.is_ancestor_of(control) else _viewport_rect()
	var rect := control.get_global_rect()
	_assert_true(control.is_visible_in_tree(), "%s is shown" % label)
	_assert_true(rect.size.y > 0.0 and rect.position.y >= clip.position.y and rect.end.y <= clip.end.y and rect.position.x >= clip.position.x, "%s lies inside its visible area (%s in %s)" % [label, rect, clip])


func _test_post_seal_details_space() -> void:
	var game := _sealed_game()
	var orders := game.player_orders
	await _layout()
	_assert_equal(_viewport_rect().size, Vector2(1280, 720), "the supported desktop viewport")
	_assert_true(game.breach_system.is_sealed(), "the wing is sealed")
	_assert_true(orders.upgrade_offer_button.visible, "the Grow Mk II offer shows")
	_assert_true(orders.wing_orders_box.visible, "wing orders show")
	_assert_false(orders.details_box.visible, "DETAILS starts collapsed")
	var collapsed_height := orders.right_scroll.size.y
	_assert_scroll_usable(orders, "post-seal collapsed")
	await _set_details(game, true)
	_assert_true(orders.details_box.visible, "DETAILS is open")
	_assert_scroll_usable(orders, "post-seal DETAILS open")
	_assert_true(orders.right_scroll.size.y >= collapsed_height, "opening DETAILS does not shrink the roster/inspector scroll (%.1f vs %.1f)" % [orders.right_scroll.size.y, collapsed_height])
	var scroll_top := orders.right_scroll.get_global_rect().position.y
	var pinned_controls := {
		"Next": orders.objective_label,
		"the Mk II offer": orders.upgrade_offer_button,
		"wing orders": orders.wing_orders_box,
		"the DETAILS toggle": orders.details_toggle,
	}
	for label: String in pinned_controls:
		var pinned: Control = pinned_controls[label]
		_assert_false(orders.right_scroll.is_ancestor_of(pinned), "%s stays pinned outside the scroll" % label)
		_assert_true(pinned.get_global_rect().end.y <= scroll_top and pinned.get_global_rect().position.y >= _viewport_rect().position.y, "%s stays on screen above the scroll" % label)
	_assert_on_screen(orders, orders.crew_mood_label, "the crew mood readout")
	var details_gap := orders.details_box.get_global_rect().position.y - orders.details_toggle.get_global_rect().end.y
	_assert_true(details_gap >= 0.0 and details_gap <= 4.5, "open DETAILS starts right under its toggle, as before (gap %.1f)" % details_gap)
	var first_row := orders.roster_box.get_child(0) as Control
	orders.right_scroll.ensure_control_visible(first_row)
	await _layout()
	_assert_on_screen(orders, first_row, "the first roster row, scrolled to")
	orders.right_scroll.ensure_control_visible(orders.inspector_title)
	await _layout()
	_assert_on_screen(orders, orders.inspector_title, "the inspector title, scrolled to")
	await _set_details(game, false)
	_assert_false(orders.details_box.visible, "DETAILS collapses")
	_assert_equal(orders.right_scroll.size.y, collapsed_height, "collapsing restores the same scroll")
	_dispose(game)


func _test_offer_fit_reachable() -> void:
	var game := _sealed_game()
	var orders := game.player_orders
	var tray := _first(game, VaultBuilding.Kind.GROW_TRAY)
	var charge := _first(game, VaultBuilding.Kind.GENERATOR)
	await _set_details(game, true)
	orders.upgrade_offer_button.pressed.emit()
	orders.refresh()
	await _layout()
	_assert_equal(game.selected_building_id, tray.building_id, "the offer selects the tray")
	_assert_true(orders.details_box.visible, "DETAILS stays open while inspecting")
	_assert_scroll_usable(orders, "tray selected with DETAILS open")
	_assert_equal(orders.fixture_upgrade_button.text, "FIT MK II · 18 SALVAGE", "the tray's FIT control")
	_assert_false(orders.fixture_upgrade_button.disabled, "FIT is affordable")
	_assert_on_screen(orders, orders.fixture_upgrade_button, "the tray's FIT control")
	orders.fixture_upgrade_button.pressed.emit()
	_assert_equal(tray.upgrade_tier, 2, "pressing FIT fits Grow Tray Mk II")
	_assert_equal(game.food_system.salvage, 42, "FIT spends 18 salvage")
	_assert_true(VaultGame.ORDER_FIT_GROW_MK2 in game.wing_orders_claimed, "the fit order is claimed")
	orders.refresh()
	await _layout()
	_assert_equal(orders.upgrade_offer_button.text if orders.upgrade_offer_button.visible else "<hidden>", "Charge Mk II · 18 · +3 power", "once no tier-1 tray is left the offer moves on to the unlocked Charge fit (QA-d #2)")
	_assert_false(orders.fixture_upgrade_row.is_visible_in_tree(), "the fitted tray offers no further FIT")
	_assert_scroll_usable(orders, "after fitting with DETAILS open")
	# The done order row selects the Charge Node its reward unlocked; its FIT is reachable too.
	(orders.wing_order_rows[VaultGame.ORDER_FIT_GROW_MK2] as Button).pressed.emit()
	orders.refresh()
	await _layout()
	_assert_equal(game.selected_building_id, charge.building_id, "the done order selects the Charge Node")
	_assert_scroll_usable(orders, "Charge selected with DETAILS open")
	_assert_on_screen(orders, orders.fixture_upgrade_button, "the Charge Node's FIT control")
	orders.fixture_upgrade_button.pressed.emit()
	_assert_equal(charge.upgrade_tier, 2, "pressing FIT fits Charge Node Mk II")
	_assert_equal(game.food_system.salvage, 24, "the second FIT spends 18 more")
	_dispose(game)


func _test_details_scroll_to_top() -> void:
	var game := _sealed_game()
	var orders := game.player_orders
	await _layout()
	orders.upgrade_offer_button.pressed.emit()
	orders.refresh()
	await _layout()
	orders.right_scroll.scroll_vertical = 100000
	await _layout()
	_assert_true(orders.right_scroll.scroll_vertical > 0, "the inspector is scrolled down")
	await _set_details(game, true)
	_assert_equal(orders.right_scroll.scroll_vertical, 0, "opening DETAILS by hand scrolls to its readouts")
	_assert_on_screen(orders, orders.crew_mood_label, "the crew mood readout after a manual open")
	await _set_details(game, false)
	orders.right_scroll.scroll_vertical = 100000
	await _layout()
	_assert_true(orders.right_scroll.scroll_vertical > 0, "scrolled down again with DETAILS collapsed")
	# A brownout onset (10 demand on 9 supply) opens DETAILS on its own.
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	_add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(18, 12))
	_add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(16, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_true(game.power_grid.brownout_active, "the extra fixtures brown out the grid (%d/%d)" % [game.power_grid.demand, game.power_grid.supply])
	orders.refresh()
	await _layout()
	_assert_true(orders.details_box.visible, "the brownout opens DETAILS")
	_assert_equal(orders.right_scroll.scroll_vertical, 0, "an urgency open scrolls to the readouts")
	_assert_on_screen(orders, orders.power_detail_label, "the power readout after the brownout opens DETAILS")
	_assert_scroll_usable(orders, "brownout DETAILS open")
	_dispose(game)


func _test_pre_seal_details() -> void:
	var game := _new_game()
	var orders := game.player_orders
	orders.refresh()
	await _set_details(game, false)
	var collapsed_height := orders.right_scroll.size.y
	_assert_scroll_usable(orders, "pre-seal collapsed")
	await _set_details(game, true)
	_assert_scroll_usable(orders, "pre-seal DETAILS open")
	_assert_true(orders.right_scroll.size.y >= collapsed_height, "pre-seal DETAILS does not shrink the scroll (%.1f vs %.1f)" % [orders.right_scroll.size.y, collapsed_height])
	_assert_on_screen(orders, orders.crew_mood_label, "the crew mood readout")
	_assert_on_screen(orders, orders.oxygen_label, "the atmosphere readout")
	_assert_on_screen(orders, orders.breach_label, "the hatch readout")
	# The hatch warning (acknowledged) opens DETAILS with every readout and FOCUS HATCH on one screen.
	await _set_details(game, false)
	orders.right_scroll.scroll_vertical = 100000
	await _layout()
	game.day_cycle.deserialize({"elapsed_seconds": 62.0, "current_day": 1, "completed": false})
	game.breach_system.advance(0.0, 62.0)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.WARNING, "the hatch warning begins")
	game.acknowledge_breach_warning(false)
	game.user_paused = true
	orders.refresh()
	await _layout()
	_assert_true(orders.details_box.visible, "the hatch warning opens DETAILS")
	_assert_equal(orders.right_scroll.scroll_vertical, 0, "the warning open scrolls to the readouts")
	_assert_scroll_usable(orders, "hatch warning DETAILS open")
	var food_card: Control = orders.find_child("FoodPlanCard", true, false)
	_assert_true(food_card == null or not food_card.is_visible_in_tree(), "the Food plan card is hidden during the hatch warning")
	var readouts := {
		"crew mood": orders.crew_mood_label,
		"power grid": orders.power_detail_label,
		"atmosphere": orders.oxygen_label,
		"hatch": orders.breach_label,
		"FOCUS HATCH": orders.breach_focus_button,
	}
	for label: String in readouts:
		_assert_on_screen(orders, readouts[label], "the %s readout during the hatch warning" % label)
	var focus_room := orders.right_scroll.get_global_rect().end.y - orders.breach_focus_button.get_global_rect().end.y
	_assert_true(focus_room >= FOCUS_MARGIN, "FOCUS HATCH keeps at least %d px above the scroll's bottom edge (got %.1f)" % [FOCUS_MARGIN, focus_room])
	_assert_panel_width(orders, "hatch warning DETAILS open")
	_assert_equal(orders.details_box.get_child(orders.breach_label.get_index() - 1).get_index(), 0, "during the warning the hatch block leads DETAILS")
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.apply_patch_work(100.0)
	orders.refresh()
	await _layout()
	_assert_true(game.breach_system.is_sealed(), "the hatch seals")
	_assert_equal(orders.breach_label.get_index() - 1, orders.oxygen_bar.get_index() + 1, "once sealed the hatch block returns below VAULT ATMOSPHERE")
	_assert_equal(orders.breach_focus_button.get_index(), orders.breach_bar.get_index() + 1, "in its own order")
	_assert_equal(orders.upgrade_offer_button.text if orders.upgrade_offer_button.visible else "<hidden>", "Spend 48: build Rec Console", "sealed with no tray to fit: the idle-salvage nudge (QA-d #4)")
	_dispose(game)


# Follow-up to VT-20: nothing in the rail may widen the right panel past RIGHT_PANEL_WIDTH.
func _assert_panel_width(orders: PlayerOrders, label: String) -> void:
	var panel := _right_panel(orders)
	_assert_true(panel.size.x <= VaultGame.RIGHT_PANEL_WIDTH + 0.5, "%s: the right panel stays %d px wide (got %.1f)" % [label, VaultGame.RIGHT_PANEL_WIDTH, panel.size.x])
	_assert_true(panel.get_global_rect().end.x <= _viewport_rect().end.x + 0.5, "%s: the right panel ends at the screen edge" % label)


func _test_panel_width() -> void:
	var game := _sealed_game()
	var orders := game.player_orders
	await _set_details(game, false)
	_assert_panel_width(orders, "post-seal collapsed")
	await _set_details(game, true)
	_assert_panel_width(orders, "post-seal DETAILS open")
	var offer := orders.upgrade_offer_button
	_assert_true(offer.visible and offer.clip_text, "the Mk II offer clips rather than widening the rail")
	_assert_false(offer.text.begins_with("Optional"), "the offer label is short; the tooltip keeps the full hint")
	var font := offer.get_theme_font("font")
	var font_size := offer.get_theme_font_size("font_size")
	var style := offer.get_theme_stylebox("normal")
	var text_width := font.get_string_size(offer.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var room := offer.size.x - style.get_minimum_size().x - text_width
	_assert_true(room >= TEXT_ROOM, "'%s' fits its button with %.0f px to spare" % [offer.text, room])
	var row := orders.lighting_label.get_parent() as Control
	var content_width := orders.right_scroll.size.x - orders.right_scroll.get_v_scroll_bar().size.x
	_assert_true(row.get_combined_minimum_size().x <= content_width, "the lighting row's minimum (%.0f px) fits beside the scroll bar (%.0f px)" % [row.get_combined_minimum_size().x, content_width])
	_assert_true(orders.lighting_overlay_button.get_global_rect().end.x <= orders.right_scroll.get_global_rect().end.x, "[L] MAP OFF stays inside the rail")
	_dispose(game)
