extends "res://tests/test_runner.gd"

# QA playtest 2026-10-30 (05 seed 8): the Food plan card offers the next affordable food build,
# is only tappable when the tap would do something, never names a different build than Next,
# and a starving resident leads the alert line. Assertions read the visible card, Next and
# alert line, and press the card like a player.

const BUILD_WORDS := ["Charge", "Station", "Tray"]


func _run() -> void:
	_run_case("(a) short of the full plan, the card offers the next affordable food build", _test_next_step)
	_run_case("(b) the card is enabled exactly when a tap queues something affordable", _test_enabled_matches_click)
	_run_case("(c) the card and Next lead with the same food build", _test_agrees_with_next)
	_run_case("(d) a starving resident leads the alert line", _test_starving_first)
	print("")
	if _failure_count == 0:
		print("FOOD CARD NEXT STEP TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("FOOD CARD NEXT STEP TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
			_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _game(salvage: int, sealed: bool) -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	game.user_paused = true
	game.food_system.salvage = salvage
	if sealed:
		game.breach_system.phase = BreachSystem.Phase.SEALED
		game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.power_grid.recalculate(game.buildings)
	game.player_orders.refresh()
	return game


func _button(game: VaultGame) -> Button:
	return game.player_orders.find_child("FoodPlanButton", true, false)


func _card_shown(game: VaultGame) -> bool:
	var card: Control = game.player_orders.find_child("FoodPlanCard", true, false)
	return card != null and card.is_visible_in_tree()


func _next(game: VaultGame) -> String:
	return game.player_orders.objective_label.text


func _alert_line(game: VaultGame) -> String:
	return game.player_orders.alert_label.text.replace("\u00a0", " ")


# Press the card like a player; returns what got queued and the salvage cost of it.
func _press(game: VaultGame) -> Dictionary:
	var before := game.buildings.size()
	var button := _button(game)
	if button != null and not button.disabled:
		button.pressed.emit()
	var kinds: Array[int] = []
	var cost := 0
	for index in range(before, game.buildings.size()):
		kinds.append(game.buildings[index].kind)
		cost += int(VaultBuilding.COSTS[game.buildings[index].kind])
	return {"kinds": kinds, "cost": cost}


func _first_build(text: String) -> String:
	var best := ""
	var best_at := 1 << 30
	for word: String in BUILD_WORDS:
		var at := text.find(word)
		if at >= 0 and at < best_at:
			best = word
			best_at = at
	return best


func _next_build(text: String) -> String:
	for pair in [["place a Nutrient Station", "Station"], ["place a Grow Tray", "Tray"], ["place a Charge Node", "Charge"]]:
		if pair[0] in text:
			return pair[1]
	return ""


func _cost_in(text: String) -> int:
	return int(text.get_slice(" · ", 1)) if " · " in text else -1


func _starve(game: VaultGame, resident_index: int) -> String:
	game.food_system.meals = 0
	var resident: VaultResident = game.residents[resident_index]
	resident.needs.food = 0.0
	resident.needs.health = 20.0
	game.player_orders.refresh()
	return resident.resident_name


func _test_next_step() -> void:
	# Day 4 of the playtest: hatch patched, 26 salvage, the full plan costs 40.
	var game := _game(26, true)
	var button := _button(game)
	_assert_true(_card_shown(game), "card is up with no food chain")
	_assert_equal(button.text, "Nutrient Station · 10", "26 salvage offers the Nutrient Station alone")
	_assert_true(not button.disabled, "the single step is tappable")
	_assert_equal(_press(game).kinds, [VaultBuilding.Kind.KITCHEN], "one tap queues just the Nutrient Station")
	_assert_true(_card_shown(game), "card stays for the Grow Tray")
	_assert_equal(_button(game).text, "Grow Tray · 12", "next it offers the Grow Tray")
	_dispose(game)
	# Day 1 of the playtest: 30 salvage with 4 owed to the hatch (26 spendable).
	game = _game(30, false)
	_assert_equal(_button(game).text, "Nutrient Station · 10", "30 salvage with the hatch reserve still offers the Station")
	_assert_true(not _button(game).disabled, "and it is tappable, not held")
	_dispose(game)
	# 13 spendable: not even the Station after the reserve? 14 - 4 = 10 is exactly enough.
	game = _game(14, false)
	_assert_equal(_button(game).text, "Nutrient Station · 10", "reserve 4 + Station 10 = 14 is enough")
	_dispose(game)
	game = _game(13, false)
	_assert_true(_button(game).disabled and _button(game).text == "Keep 4 salvage for the hatch", "13 salvage: held for the hatch: %s" % _button(game).text)
	_dispose(game)


func _test_enabled_matches_click() -> void:
	for salvage: int in [0, 9, 10, 21, 26, 30, 35, 39, 40, 48]:
		for sealed: bool in [true, false]:
			var game := _game(salvage, sealed)
			var button := _button(game)
			var spendable := salvage - (0 if sealed else BreachSystem.PATCH_COST)
			var shown_cost := _cost_in(button.text)
			var enabled := not button.disabled
			var queued := _press(game)
			var tag := "%d salvage%s, '%s'" % [salvage, " sealed" if sealed else "", button.text]
			_assert_equal(enabled, not queued.kinds.is_empty(), "enabled exactly when a tap queues: %s" % tag)
			if enabled:
				_assert_true(shown_cost >= 0 and shown_cost <= spendable, "an enabled card never shows more than spendable %d: %s" % [spendable, tag])
				_assert_equal(queued.cost, shown_cost, "the tap spends what the card says: %s" % tag)
			_dispose(game)
	var game := _game(5, true)
	_assert_true(_button(game).disabled, "5 salvage, patched hatch: nothing affordable, card disabled")
	_assert_equal(_button(game).text, "Need 10 salvage: Nutrient Station", "and it says what it is waiting for")
	_dispose(game)


func _test_agrees_with_next() -> void:
	var seen := 0
	for salvage: int in [14, 26, 30, 44, 60]:
		for sealed: bool in [true, false]:
			for starving: bool in [false, true]:
				var game := _game(salvage, sealed)
				game.food_system.meals = 1
				game.player_orders.refresh()
				if starving:
					_starve(game, 1)
				var next := _next(game)
				var want := _next_build(next)
				if want.is_empty() or not _card_shown(game) or _button(game).disabled:
					_dispose(game)
					continue
				seen += 1
				_assert_equal(_first_build(_button(game).text), want, "%d salvage: Next '%s' vs card '%s'" % [salvage, next, _button(game).text])
				var queued := _press(game)
				_assert_true(not queued.kinds.is_empty() and VaultBuilding.KIND_NAMES[queued.kinds[0]].contains(want), "the tap queues Next's build first: %s" % str(queued.kinds))
				_dispose(game)
	_assert_true(seen >= 6, "covered %d card+Next food states" % seen)


func _test_starving_first() -> void:
	var game := _game(26, true)
	var name := _starve(game, 1)
	_assert_true(("%s starving" % name) in _next(game), "fixture: Next names %s starving: %s" % [name, _next(game)])
	_assert_true(_alert_line(game).begins_with("STARVING: %s" % name), "alert line leads with STARVING: %s: %s" % [name, _alert_line(game)])
	_assert_true(not ("CRITICAL: %s" % name) in _alert_line(game), "no duplicate CRITICAL clause for %s" % name)
	# A dark, bunkless, unhappy vault still leads with the starving resident.
	game.residents[0].needs.rest = 5.0
	game.residents[2].needs.mood = 5.0
	game.player_orders.refresh()
	_assert_true(_alert_line(game).begins_with("STARVING: %s" % name), "still first with other alerts up: %s" % _alert_line(game))
	_dispose(game)
