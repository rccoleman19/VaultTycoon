extends "res://tests/test_runner.gd"

# QA-d #8 Lever 1: a one-tap Food plan card queues the food chain an idle vault never builds.
# Assertions read the visible card (FoodPlanCard / its button) and press it like a player.


func _run() -> void:
	_run_case("opening wing: the card offers Charge + Station + Tray and one tap queues them in order", _test_power_short)
	_run_case("with spare power the plan skips the Charge Node", _test_power_ok)
	_run_case("the card is held while the live hatch needs its patch salvage", _test_gate)
	_run_case("the card hides while the pre-seal hatch warning is up", _test_warning_hide)
	_run_case("a queued partial offer's unpaid cost is reserved before the next offer", _test_queued_reserve)
	print("")
	if _failure_count == 0:
		print("FOOD PLAN CARD TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("FOOD PLAN CARD TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
			_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _game(salvage: int, spare_power: bool) -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	game.user_paused = true
	game.food_system.salvage = salvage
	if spare_power:
		_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(24, 12))
	game.power_grid.recalculate(game.buildings)
	game.player_orders.refresh()
	return game


func _card(game: VaultGame) -> Control:
	return game.player_orders.find_child("FoodPlanCard", true, false)


func _button(game: VaultGame) -> Button:
	return game.player_orders.find_child("FoodPlanButton", true, false)


func _press(game: VaultGame) -> Array[int]:
	var before := game.buildings.size()
	var button := _button(game)
	if button != null and not button.disabled:
		button.pressed.emit()
	var kinds: Array[int] = []
	for index in range(before, game.buildings.size()):
		kinds.append(game.buildings[index].kind)
	return kinds


func _test_power_short() -> void:
	var game := _game(48, false)
	var card := _card(game)
	_assert_true(card != null and card.is_visible_in_tree(), "Food plan card is visible on the opening wing")
	var button := _button(game)
	_assert_true(button != null and not button.disabled, "card is tappable with 48 salvage")
	if button == null:
		_dispose(game)
		return
	_assert_equal(button.text, "Charge + Station + Tray · 40", "card names the plan and its cost")
	var queued := _press(game)
	_assert_equal(queued, [VaultBuilding.Kind.GENERATOR, VaultBuilding.Kind.KITCHEN, VaultBuilding.Kind.GROW_TRAY], "one tap queues Charge Node, Station, Grow Tray")
	_assert_true(not card.is_visible_in_tree(), "card hides once the plan is queued")
	_dispose(game)


func _test_power_ok() -> void:
	var game := _game(48, true)
	var button := _button(game)
	_assert_true(button != null and button.text == "Station + Tray · 22", "no Charge Node with spare power: %s" % (button.text if button else "none"))
	_assert_equal(_press(game), [VaultBuilding.Kind.KITCHEN, VaultBuilding.Kind.GROW_TRAY], "queues Station then Tray only")
	_dispose(game)
	# Planned spare exactly equal to Station 2 + Tray 3 is enough: still no Charge Node.
	game = _game(48, true)
	var x := 16
	while game._planned_power_spare() > 5 and x < 34:
		_add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(x, 13))
		x += 2
	game.power_grid.recalculate(game.buildings)
	game.player_orders.refresh()
	_assert_equal(game._planned_power_spare(), 5, "fixture plans exactly 5 spare power")
	_assert_equal(_button(game).text, "Station + Tray · 22", "exactly enough power skips the Charge Node")
	_dispose(game)


func _test_gate() -> void:
	# Plan 40 + patch 4: 44 covers the whole plan; 43 falls back to the Station alone
	# (QA playtest 2026-10-30); 13 cannot cover patch 4 + Station 10, so it is held.
	var game := _game(13, false)
	var button := _button(game)
	_assert_true(button != null and button.disabled, "13 salvage: card held")
	_assert_true(button != null and button.text == "Keep 4 salvage for the hatch", "held card says why: %s" % (button.text if button else "none"))
	_assert_equal(_press(game).size(), 0, "a held card queues nothing")
	_assert_true(not game.apply_food_plan(), "apply is refused while held")
	_dispose(game)
	game = _game(43, false)
	_assert_equal(_button(game).text, "Nutrient Station · 10", "43 salvage: short of plan 40 + patch 4, offers the Station")
	_dispose(game)
	game = _game(44, false)
	_assert_true(not _button(game).disabled, "44 salvage covers plan 40 + patch 4")
	_dispose(game)
	game = _game(20, false)
	game.breach_system.phase = BreachSystem.Phase.SEALED
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.player_orders.refresh()
	_assert_true(not _button(game).disabled, "a patched hatch lifts the gate")
	_dispose(game)


func _test_warning_hide() -> void:
	var game := _game(48, false)
	game.breach_system.phase = BreachSystem.Phase.WARNING
	game.player_orders.refresh()
	_assert_true(not _card(game).is_visible_in_tree(), "card hidden during the hatch warning")
	game.breach_system.phase = BreachSystem.Phase.OPEN
	game.player_orders.refresh()
	_assert_true(_card(game).is_visible_in_tree(), "card back once the hatch is open")
	_dispose(game)


# Codex note on #135: placing a blueprint debits nothing until pickup, so after tapping the partial
# "Nutrient Station · 10" offer the card used to offer "Grow Tray · 12" against the same stock and
# the two taps spent the hatch patch reserve (05 s8 + Bunk: hatch opened at 103.8 s unpatched).
func _test_queued_reserve() -> void:
	var game := _spawn_game()
	game.new_game(false, 8, 5)
	game.begin_shift()
	game.user_paused = true
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(27, 12))
	game.food_system.salvage = 22
	game.power_grid.recalculate(game.buildings)
	game.player_orders.refresh()
	_assert_equal(_button(game).text, "Nutrient Station · 10", "fixture: 22 stock - patch 4 offers the Station alone")
	_assert_equal(_press(game), [VaultBuilding.Kind.KITCHEN] as Array[int], "the tap queues the Station")
	game.player_orders.refresh()
	_assert_true(_button(game).disabled or not _card(game).is_visible_in_tree(), "the card holds while the Station's 10 is unpaid: %s" % _button(game).text)
	_assert_false("Grow Tray" in _button(game).text, "no Grow Tray offer against the same stock: %s" % _button(game).text)
	_assert_equal(_press(game).size(), 0, "a second tap queues nothing")
	# Driver run: keep tapping whenever the card is live; the hatch must still get its patch.
	game.user_paused = false
	var extra := 0
	for _tick in range(int(110.0 / VaultGame.SIMULATION_TICK)):
		if game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged:
			game.acknowledge_breach_warning(true)
		if _card(game).is_visible_in_tree():
			extra += _press(game).size()
		game.step_simulation(VaultGame.SIMULATION_TICK)
		game.player_orders.refresh()
		if game.breach_system.is_sealed():
			break
	_assert_true(game.breach_system.is_sealed(), "the hatch seals (patch %d/%d, %d more taps)" % [game.breach_system.patch_delivered, BreachSystem.PATCH_COST, extra])
	_dispose(game)
