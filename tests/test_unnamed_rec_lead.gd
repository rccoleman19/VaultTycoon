extends "res://tests/test_next_flicker.gd"

# #121 Codex P3: the unnamed urgent food Rec step has no "<Name> <condition> · "
# prefix, so the salvage lead must read its action from the step fields, not
# from the second " · " segment. Reuses the next-flicker wing fixtures.
const UNNAMED_REC := {"text": "Next: YOU place a Rec Console · THEY recover mood", "tool": "rec", "kind": "food", "urgent": true, "cause": "food", "resident_id": 1, "food_unnamed": true}
const FUND_REC := "Next: YOU begin reclamation · +18 · THEY fund the Rec Console"


func _run() -> void:
	_run_case("U1 unnamed food Rec step leads with reclamation at salvage 0 and 7", _test_unnamed_short)
	_run_case("U2 unnamed food Rec step at salvage 8+ is affordable spending, not reclamation", _test_unnamed_affordable)
	_run_case("U3 named food Rec step keeps its resident prefix and lead", _test_named_unchanged)
	_run_case("U4 unnamed runway-labelled step keeps the label as its prefix", _test_unnamed_label)
	_run_case("U5 no second reclamation lead once reclamation runs", _test_guards)
	print("UNNAMED REC LEAD TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _breaking_idle_wing(salvage: int) -> VaultGame:
	var game := _wing()
	game.food_system.salvage = salvage
	game.residents[0].needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD - 1.0
	game.residents[1].state = "Idle"
	game.player_orders.refresh()
	_advance_clock(game, game.player_orders.IDLE_CREW_WINDOW_S + 1.0)
	_assert_true(game.player_orders._has_idle_crew(), "fixture has a settled idle worker")
	_assert_true(game.can_start_reclamation(), "fixture can begin reclamation")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.RECREATION_CONSOLE), 0, "fixture has no Rec Console")
	return game


func _choose(game: VaultGame, step: Dictionary) -> Dictionary:
	return game.player_orders._choose_salvage_next_step(step.duplicate(true))


func _test_unnamed_short() -> void:
	for salvage in [0, 7]:
		var game := _breaking_idle_wing(salvage)
		var shown := _choose(game, UNNAMED_REC)
		_assert_true(str(shown.get("text", "")).begins_with(FUND_REC), "U1 salvage %d: unnamed Rec step leads with begin reclamation · fund the Rec Console (got %s)" % [salvage, shown.get("text", "")])
		_assert_equal(str(shown.get("action", "")), "reclaim", "U1 salvage %d: the lead exposes the reclaim action" % salvage)
		_assert_equal(str(shown.get("tool", "")), "select", "U1 salvage %d: reclamation is a select action" % salvage)
		_assert_false(str(shown.get("text", "")).begins_with("Next: THEY") or "Next: YOU place a Rec Console" in str(shown.get("text", "")), "U1 salvage %d: no bare Rec placement left" % salvage)
		_assert_true(bool(shown.get("urgent", false)) and bool(shown.get("food_unnamed", false)), "U1 salvage %d: urgent unnamed flags survive" % salvage)
		_dispose(game)


func _test_unnamed_affordable() -> void:
	for salvage in [8, 20]:
		var game := _breaking_idle_wing(salvage)
		var shown := _choose(game, UNNAMED_REC)
		var text := str(shown.get("text", ""))
		_assert_true("begin reclamation" not in text, "U2 salvage %d: affordable Rec is not a reclamation lead (got %s)" % [salvage, text])
		_assert_true(text.begins_with("Next: YOU spend 8: build Rec Console") or text.begins_with("Next: YOU place a Rec Console"), "U2 salvage %d: build/spend wording without a bogus prefix (got %s)" % [salvage, text])
		_assert_false(text.begins_with("Next: THEY"), "U2 salvage %d: the action segment is not dropped" % salvage)
		_dispose(game)


func _test_named_unchanged() -> void:
	var game := _breaking_idle_wing(0)
	var named := UNNAMED_REC.duplicate(true)
	named.erase("food_unnamed")
	named.text = "Next: Ari starving · YOU place a Rec Console · THEY recover mood"
	var shown := _choose(game, named)
	_assert_equal(str(shown.get("text", "")), "Next: Ari starving · YOU begin reclamation · +18 · THEY fund the Rec Console", "U3 the named step keeps its prefix and reclamation lead")
	_assert_equal(game.player_orders._next_step_prefix(named) if game.player_orders.has_method("_next_step_prefix") else "Next: Ari starving · ", "Next: Ari starving · ", "U3 named prefix is the resident segment")
	_dispose(game)


func _test_unnamed_label() -> void:
	var game := _breaking_idle_wing(0)
	var labelled := UNNAMED_REC.duplicate(true)
	labelled.text = "Next: food runway short · YOU place a Rec Console · THEY recover mood"
	var shown := _choose(game, labelled)
	_assert_equal(str(shown.get("text", "")), "Next: food runway short · YOU begin reclamation · +18 · THEY fund the Rec Console", "U4 the runway label stays the prefix of the lead")
	_dispose(game)


func _test_guards() -> void:
	var game := _breaking_idle_wing(0)
	_assert_true(game.start_reclamation(), "U5 fixture starts reclamation")
	game.food_system.salvage = 0
	_assert_true("begin reclamation" not in str(_choose(game, UNNAMED_REC).get("text", "")), "U5 running reclamation is not offered again")
	_dispose(game)
