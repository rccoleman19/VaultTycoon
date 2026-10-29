extends "res://tests/test_food_card_next_step.gd"

# QA 05 seed 8: Dax starved on day 6 while the sidebar said "Spend 35: build Rec Console".
# While anyone starves or the food runway is short, Spend names only the food card's step
# (the same build as the card and Next) or hides; the RESIDENT LOST recap names the build
# the sidebar was offering at the loss. Assertions read visible sidebar text and press it.

const FOOD_NUDGE_NAMES := ["Nutrient Station", "Grow Tray", "Charge Node"]


func _run() -> void:
	_run_case("(a) a starving resident's Spend nudge names the card's food build", _test_nudge_names_food)
	_run_case("(a) a short food runway with nobody starving still names food", _test_runway_short)
	_run_case("(a) after a starvation loss, Spend never names a non-food build", _test_after_loss)
	_run_case("(a) no affordable food step hides the nudge", _test_hides_without_food)
	_run_case("(a) Spend, card and Next agree across states; pressing arms that build", _test_sweep)
	_run_case("(b) the recap's would-have-saved build is the one the sidebar offered at the loss", _test_recap_matches_sidebar)
	_run_case("(c) a suffocation recap keeps its Charge Node while the card offers food", _test_suffocation_recap_keeps_tip)
	print("")
	if _failure_count == 0:
		print("SPEND NUDGE FOOD FIRST TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("SPEND NUDGE FOOD FIRST TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
			_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _spend(game: VaultGame) -> String:
	var button: Button = game.player_orders.upgrade_offer_button
	return button.text if button != null and button.is_visible_in_tree() and button.text.begins_with("Spend ") else ""


func _spend_build(game: VaultGame) -> String:
	var text := _spend(game)
	return text.get_slice(": build ", 1) if ": build " in text else ""


func _card_build(game: VaultGame) -> String:
	if not _card_shown(game) or _button(game).disabled:
		return ""
	var text := _button(game).text
	for name: String in FOOD_NUDGE_NAMES:
		if text.begins_with(name):
			return name
	return {"Charge": "Charge Node", "Station": "Nutrient Station", "Tray": "Grow Tray"}.get(_first_build(text), "")


func _next_full_build(game: VaultGame) -> String:
	for name: String in FOOD_NUDGE_NAMES:
		if ("place a %s" % name) in _next(game):
			return name
	return ""


func _kill_by_starvation(game: VaultGame, index: int) -> String:
	var resident: VaultResident = game.residents[index]
	resident.needs.food = 0.0
	resident.needs.rest = 100.0
	resident.needs.mood = 100.0
	resident.needs.health = 0.2
	resident.advance_needs(VaultGame.SIMULATION_TICK / DayCycle.SECONDS_PER_DAY, true, false)
	game.player_orders.refresh()
	return resident.resident_name


func _test_nudge_names_food() -> void:
	var game := _game(35, true)
	var name := _starve(game, 1)
	_assert_true(("%s starving" % name) in _next(game), "fixture: Next names %s starving: %s" % [name, _next(game)])
	_assert_equal(_spend(game), "Spend 35: build Nutrient Station", "Spend names the Station while %s starves" % name)
	_assert_equal(_spend_build(game), _card_build(game), "Spend and the card name one build")
	_assert_equal(_spend_build(game), _next_full_build(game), "Spend and Next name one build")
	_dispose(game)


func _test_runway_short() -> void:
	var game := _game(35, true)
	game.food_system.meals = 0
	game.food_system.raw_food = 0
	game.player_orders.refresh()
	_assert_true("food runway short" in _next(game) or "starving" in _next(game), "fixture: Next is on food: %s" % _next(game))
	_assert_true(_spend_build(game) in FOOD_NUDGE_NAMES, "a short runway Spend names a food build: '%s'" % _spend(game))
	_assert_equal(_spend_build(game), _card_build(game), "and the card's build")
	_dispose(game)


func _test_after_loss() -> void:
	var game := _game(35, true)
	_starve(game, 2)
	var dead := _kill_by_starvation(game, 1)
	_assert_equal(game.outcome, "death", "fixture: %s starves" % dead)
	var spend := _spend_build(game)
	_assert_true(spend.is_empty() or spend in FOOD_NUDGE_NAMES, "after the loss Spend names food or hides: '%s'" % _spend(game))
	_assert_false("Rec Console" in _spend(game), "never Rec Console while the crew starves")
	if not spend.is_empty():
		_assert_equal(spend, _card_build(game), "after the loss Spend matches the card")
	_dispose(game)


func _test_hides_without_food() -> void:
	# 9 salvage buys a Rec Console (8) but no food step (Station 10).
	var game := _game(9, true)
	_starve(game, 2)
	_kill_by_starvation(game, 1)
	_assert_equal(_spend(game), "", "no affordable food step: Spend hides, got '%s'" % _spend(game))
	_dispose(game)
	game = _game(9, true)
	_starve(game, 1)
	_assert_equal(_spend(game), "", "starving at 9 salvage: Spend hides, got '%s'" % _spend(game))
	_dispose(game)


func _test_sweep() -> void:
	var shown := 0
	for salvage: int in [5, 8, 9, 10, 12, 18, 26, 35, 44, 60]:
		for state: String in ["starving", "short", "lost"]:
			var game := _game(salvage, true)
			if state == "starving":
				_starve(game, 1)
			elif state == "short":
				game.food_system.meals = 0
				game.food_system.raw_food = 0
				game.player_orders.refresh()
			else:
				_starve(game, 2)
				_kill_by_starvation(game, 1)
			var tag := "%d salvage %s: Spend '%s' card '%s' Next '%s'" % [salvage, state, _spend(game), _button(game).text if _card_shown(game) else "none", _next(game)]
			var spend := _spend_build(game)
			var card := _card_build(game)
			if card.is_empty():
				_assert_equal(spend, "", "no food step on the card, so no Spend: %s" % tag)
			if not spend.is_empty():
				shown += 1
				_assert_true(spend in FOOD_NUDGE_NAMES, "Spend names food: %s" % tag)
				_assert_equal(spend, card, "Spend matches the card: %s" % tag)
				var next_build := _next_full_build(game)
				if not next_build.is_empty():
					_assert_equal(spend, next_build, "Spend matches Next: %s" % tag)
				game.player_orders.upgrade_offer_button.pressed.emit()
				_assert_equal(game.active_tool, game.player_orders.NUDGE_TOOLS[VaultBuilding.KIND_NAMES.find_key(spend)], "pressing Spend arms that build: %s" % tag)
			_dispose(game)
	_assert_true(shown >= 6, "Spend was visible in %d food states" % shown)


func _test_recap_matches_sidebar() -> void:
	var game := _game(26, true)
	var name := _starve(game, 1)
	_assert_true("YOU place a Nutrient Station" in _next(game), "fixture: first warning says Station: %s" % _next(game))
	# The player taps before the sim runs; otherwise the Cook (auto food step) queues first.
	_press(game)
	game.user_paused = false
	game.step_simulation(1.0)
	game.player_orders.refresh()
	var offered := _card_build(game)
	_assert_equal(offered, "Grow Tray", "fixture: with the Station queued the sidebar offers the Grow Tray: %s" % _button(game).text)
	_kill_by_starvation(game, 1)
	_assert_equal(game.outcome, "death", "fixture: %s starves" % name)
	var body := game.player_orders.outcome_text.text
	_assert_true(("This would have saved %s" % name) in body, "recap has a would-have-saved line: %s" % body)
	var line := body.get_slice("This would have saved", 1)
	_assert_true(("place a %s" % offered) in line, "recap names the sidebar's %s: %s" % [offered, line])
	_assert_false("place a Nutrient Station" in line, "not the stale Station from the first warning: %s" % line)
	_dispose(game)


const AIR_TIP := "YOU place a Charge Node · THEY power the Air Recycler"


# Codex note on #136: the sidebar swap is for starvation only; a suffocation tip keeps its build.
func _suffocate_with_tip(game: VaultGame, index: int) -> VaultResident:
	var resident: VaultResident = game.residents[index]
	var orders := game.player_orders
	orders._survival_tips[resident.resident_id] = {"air": AIR_TIP}
	orders._survival_tip_details[resident.resident_id] = {"air": {"elapsed_seconds": -1.0, "cause": "air", "tick": -1}}
	resident.needs.food = 60.0
	resident.needs.rest = 100.0
	resident.needs.mood = 100.0
	resident.needs.health = 0.0
	game.oxygen_system.oxygen = OxygenSystem.CRITICAL_OXYGEN_THRESHOLD - 5.0
	return resident


func _test_suffocation_recap_keeps_tip() -> void:
	var game := _game(35, true)
	_starve(game, 1)
	_assert_true(_card_shown(game) and "Station" in _button(game).text, "fixture: the card offers the Nutrient Station: %s" % _button(game).text)
	var resident := _suffocate_with_tip(game, 2)
	var recap := game.player_orders.death_recap_for(resident)
	_assert_equal(str(recap.cause), "suffocation", "fixture: suffocation loss")
	_assert_equal(str(recap.tip), AIR_TIP, "suffocation recap keeps the Charge Node advice")
	# The real death path stores it (recap save/load itself is covered by test_death_recap).
	resident.kill()
	_assert_equal(str(game.death_recap.get("tip", "")), AIR_TIP, "the live death recap keeps the Charge Node advice")
	_dispose(game)
	# No food offer: unchanged too.
	game = _game(35, true)
	game.food_system.meals = 40
	game.player_orders.refresh()
	resident = _suffocate_with_tip(game, 2)
	_assert_equal(str(game.player_orders.death_recap_for(resident).tip), AIR_TIP, "no food offer: the suffocation tip is unchanged")
	_dispose(game)
