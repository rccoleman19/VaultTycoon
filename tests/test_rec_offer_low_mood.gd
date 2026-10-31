extends "res://tests/test_rec_flash_cause.gd"
# Crew mood under ~40 with no Rec Console: Next and Spend offer the Rec Console and a
# real Spend press places it (place_spend_build, #142). Air, food and bunk holds still win.


func _run() -> void:
	_run_case("mood 30: Next and Spend offer the Rec Console", _test_low_mood_offers)
	_run_case("mood 30: pressing Spend places a Rec Console blueprint", _test_press_places_rec)
	_run_case("mood 60: no Rec offer", _test_mood_ok)
	_run_case("mood 30 with tired crew and no bunks: the bunk hold wins", _test_bunks_win)
	_run_case("mood 30 with falling air and no Air Recycler: air wins", _test_air_wins)
	_run_case("mood 30 with a starving resident and no meals: food wins", _test_food_wins)
	_run_case("mood 30 while the Rec nudge waits on two unpaid blueprints: Spend keeps the Mk II", _test_waiting_nudge_keeps_mk2)
	print("REC OFFER LOW MOOD: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _low(bunks := true, air := true, mood := 30.0) -> VaultGame:
	var game := _plateau(bunks, air)
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY:
			building.upgrade_tier = VaultBuilding.UPGRADE_TIER_BASE
	game.food_system.salvage = 40
	for resident: VaultResident in game.residents:
		resident.needs.mood = mood
	return game


func _recs(game: VaultGame) -> int:
	var count := 0
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.RECREATION_CONSOLE:
			count += 1
	return count


func _test_low_mood_offers() -> void:
	var game := _low()
	var text := _next(game)
	var spend := _spend_text(game)
	_assert_true("Rec Console" in text, "Next names the Rec Console (%s)" % text)
	_assert_true(spend.begins_with("Spend ") and "Rec Console" in spend, "Spend offers the Rec Console (%s)" % spend)
	_dispose(game)


func _test_press_places_rec() -> void:
	var game := _low()
	_next(game)
	game.player_orders.refresh()
	_assert_equal(_recs(game), 0, "no Rec Console before the press")
	game.player_orders.upgrade_offer_button.pressed.emit()
	_assert_equal(_recs(game), 1, "Spend placed one Rec Console blueprint")
	var text := _next(game)
	_assert_false("YOU place a Rec Console" in text, "Next moves past placing the Rec (%s)" % text)
	_dispose(game)


func _test_mood_ok() -> void:
	var game := _low(true, true, 60.0)
	var text := _next(game)
	var spend := _spend_text(game)
	_assert_false("Rec Console" in text, "Next names no Rec (%s)" % text)
	_assert_true("Mk II" in spend, "Spend keeps its Mk II offer (%s)" % spend)
	_dispose(game)


func _test_bunks_win() -> void:
	var game := _low(false)
	var text := _next(game)
	var spend := _spend_text(game)
	_assert_true("bunk" in text, "Next keeps the bunks (%s)" % text)
	_assert_false("Rec Console" in spend, "Spend does not offer Rec over the bunks (%s)" % spend)
	_dispose(game)


func _test_air_wins() -> void:
	var game := _low(true, false)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.oxygen_system.oxygen = OxygenSystem.LOW_OXYGEN_THRESHOLD + 5.0
	var text := _next(game)
	var spend := _spend_text(game)
	_assert_true("Air" in text, "Next names Air (%s)" % text)
	_assert_false("Rec Console" in spend, "Spend does not offer Rec over Air (%s)" % spend)
	_dispose(game)


func _test_food_wins() -> void:
	var game := _low()
	game.food_system.meals = 0
	game.residents[0].needs.food = 10.0
	var text := _next(game)
	var spend := _spend_text(game)
	_assert_false("Rec Console" in text, "Next does not lead with Rec (%s)" % text)
	_assert_false("Rec Console" in spend, "Spend does not offer Rec over food (%s)" % spend)
	_dispose(game)


func _test_waiting_nudge_keeps_mk2() -> void:
	var game := _low()
	for i in 2:
		var cells: Array[Vector2i] = game.player_orders.spend_build_cells(VaultBuilding.Kind.LAMP)
		_assert_true(not cells.is_empty() and game.place_blueprint(VaultBuilding.Kind.LAMP, cells[0]), "an unpaid Lumen is queued")
	_next(game)
	var spend := _spend_text(game)
	_assert_true("Mk II" in spend, "Spend still offers the Mk II fit (%s)" % spend)
	_dispose(game)
