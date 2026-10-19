extends "res://tests/test_runner.gd"

# QA-e #2: after the seal, HELP lists wing orders, Stock 16 progress, reclamation and the Mk II offer.


func _run() -> void:
	_run_case("HELP adds the post-seal lines only after the seal", _test_gating)
	_run_case("the post-seal lines track orders, Stock 16, reclamation and the offer", _test_tracking)
	_run_case("every post-seal line fits the HELP checklist with 12 px to spare", _test_fit)
	print("")
	if _failure_count == 0:
		print("POST-SEAL HELP TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("POST-SEAL HELP TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


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


func _help(game: VaultGame) -> String:
	game.player_orders.open_help()
	game.player_orders.refresh()
	return game.player_orders.checklist.text


func _plain(line: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\[/?color[^\\]]*\\]")
	return regex.sub(line, "", true)


func _post_lines(game: VaultGame) -> Array[String]:
	var lines: Array[String] = []
	for line: String in game.player_orders.postseal_checklist_lines():
		lines.append(_plain(line))
	return lines


func _test_gating() -> void:
	var game := _base_game()
	_assert_false("AFTER THE SEAL" in _help(game), "no post-seal block before the seal")
	_assert_equal(game.player_orders.postseal_checklist_lines().size(), 0, "the helper is empty before the seal")
	game.player_orders.show_briefing(false)
	_seal(game)
	var text := _help(game)
	_assert_true("AFTER THE SEAL" in text, "the block appears after the seal")
	_assert_true(text.find("AFTER THE SEAL") > text.find("Finish Day 7"), "below the required list")
	_assert_true(text.find("AFTER THE SEAL") < text.find("Power a Rec Console"), "above the optional list")
	game.player_orders.show_briefing(false)
	game.ended = true
	_assert_equal(game.player_orders.postseal_checklist_lines().size(), 0, "an ended wing lists nothing")
	_dispose(game)


func _test_tracking() -> void:
	var game := _base_game()
	_seal(game)
	var lines := _post_lines(game)
	_assert_equal(lines.size(), 5, "header, two orders, reclamation, offer")
	_assert_equal(lines[1], "[    ]  Wing order: Fit Grow Mk II → unlocks Charge Mk II", "fit order open")
	_assert_equal(lines[2], "[    ]  Wing order: Stock 16 meals (%d/16) → unlocks Air Mk II" % mini(game.food_system.meals, 16), "stock order shows progress")
	_assert_equal(lines[3], "[    ]  Begin reclamation · +%d salvage" % VaultGame.RECLAIM_START_SALVAGE, "reclamation ready")
	var target: VaultBuilding = game.player_orders._upgrade_offer_target()
	_assert_true(target != null, "a Grow Tray Mk II is on offer")
	_assert_equal(lines[4], "[OFFER]  Mk II: %s" % game.player_orders.upgrade_offer_text(target), "offer matches the right panel")
	game.food_system.meals = 11
	_assert_equal(_post_lines(game)[2], "[    ]  Wing order: Stock 16 meals (11/16) → unlocks Air Mk II", "progress follows meals")
	_assert_true(game.upgrade_building(target.building_id), "fit the Grow Tray")
	lines = _post_lines(game)
	_assert_equal(lines[1], "[DONE]  Wing order: Fit Grow Mk II → unlocks Charge Mk II", "fit order done")
	_assert_true(lines[4].begins_with("[OFFER]  Mk II: Charge Mk II"), "offer moves on to Charge (%s)" % lines[4])
	_assert_true(game.start_reclamation(), "start reclamation")
	lines = _post_lines(game)
	_assert_true(lines[3].begins_with("[ACTIVE]  Reclamation · +"), "reclamation active (%s)" % lines[3])
	game.reclaim_paid = VaultGame.RECLAIM_DELIVERIES
	_assert_equal(_post_lines(game)[3], "[DONE]  Reclamation complete", "reclamation complete")
	game.food_system.meals = 16
	game.wing_orders_claimed.append(VaultGame.ORDER_STOCK_MEALS)
	_assert_equal(_post_lines(game)[2], "[DONE]  Wing order: Stock 16 meals → unlocks Air Mk II", "stock order done")
	_dispose(game)


func _test_fit() -> void:
	var game := _base_game(999)
	_seal(game)
	var orders := game.player_orders
	var checklist: RichTextLabel = orders.checklist
	var scroll := checklist.get_parent() as ScrollContainer
	# Panel width minus its frame, the 18 px margins and the scroll bar the long list always shows.
	var width: float = orders.briefing_panel.custom_minimum_size.x - orders.briefing_panel.get_theme_stylebox("panel").get_minimum_size().x - 36.0 - scroll.get_v_scroll_bar().get_combined_minimum_size().x
	_assert_true(width > 400.0 and width < 560.0, "the checklist width is plausible (%.0f)" % width)
	var font := checklist.get_theme_font("normal_font")
	var size := checklist.get_theme_font_size("normal_font_size")
	var texts: Array[String] = _post_lines(game)
	texts.append("[    ]  Wing order: Stock 16 meals (16/16) → unlocks Air Mk II")
	texts.append("[ACTIVE]  Reclamation · +%d in %d s · %d left" % [VaultGame.RECLAIM_DELIVERY, roundi(VaultGame.RECLAIM_INTERVAL), VaultGame.RECLAIM_DELIVERIES])
	texts.append("[OFFER]  Mk II: Tray unpowered · Charge Mk II 18")
	texts.append("[OFFER]  Mk II: Air Mk II · 18 salvage · -1 power")
	texts.append("[OFFER]  Mk II: Charge Mk II · 18 · +3 power")
	texts.append("[OFFER]  Mk II: nothing to fit right now")
	for text: String in texts:
		var room := width - font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		_assert_true(room >= 12.0, "'%s' fits with %.0f px to spare" % [text, room])
	_dispose(game)
