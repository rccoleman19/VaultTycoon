extends "res://tests/test_air_early_warning.gd"

# Light-touch QA 05 seed 8 (2026-10-30): following the early food tips spent the hatch
# salvage before the warning, the breach opened, and the recap said no tip could have
# saved Dax. Tips now keep the hatch patch before the seal, the patch step leads the
# alert line during an open breach, the recap omits the no-tip claim, and Next holds the
# Air Recycler on idle 05 s8. Assertions read Next, the alert line, Spend and the recap.


func _run() -> void:
	_run_case("before the seal Next never names a build that spends the hatch patch", _test_reserve_next)
	_run_case("patch paid, nothing queued: a held build names its own shortfall, never 'save 0'", _test_zero_commitment)
	_run_case("an open breach's patch step leads the alert line and Next", _test_patch_leads)
	_run_case("the recap never claims no tip could have saved them", _test_recap)
	_run_case("idle 05 s8 from 230 s: Next holds the Air Recycler", _test_flicker)
	print("")
	if _failure_count == 0:
		print("HATCH RESERVE TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("HATCH RESERVE TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
			_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _idle_05() -> VaultGame:
	var game := _spawn_game()
	game.new_game(false, 8, 5)
	game.begin_shift()
	return game


func _tick(game: VaultGame) -> void:
	var po := game.player_orders
	if game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged:
		po.breach_resume_button.pressed.emit()
	game.step_simulation(0.1)
	po.refresh()


const BUILD_NAMES := {
	"Nutrient Station": VaultBuilding.Kind.KITCHEN, "Charge Node": VaultBuilding.Kind.GENERATOR,
	"Grow Tray": VaultBuilding.Kind.GROW_TRAY, "Rec Console": VaultBuilding.Kind.RECREATION_CONSOLE,
	"Air Recycler": VaultBuilding.Kind.AIR_RECYCLER,
}


func _test_reserve_next() -> void:
	var game := _idle_05()
	var po := game.player_orders
	var saw_save := false
	var bad := ""
	while not game.breach_system.is_sealed() and game.day_cycle.elapsed_seconds < 60.0 and not game.ended:
		# The light-touch run spent down to a few salvage over the patch before the warning.
		if game.day_cycle.elapsed_seconds > 15.0:
			game.food_system.salvage = mini(game.food_system.salvage, 12)
		_tick(game)
		if game.breach_system.is_sealed():
			break
		var text: String = po.objective_label.text
		saw_save = saw_save or "YOU save 4 for the hatch patch" in text
		var spendable: int = game.food_system.salvage - maxi(0, BreachSystem.PATCH_COST - game.breach_system.patch_delivered - game.job_system.get_breach_supply_in_transit()) - game.queued_build_commitment()
		for name: String in BUILD_NAMES:
			var cost := int(VaultBuilding.COSTS[BUILD_NAMES[name]])
			if ("YOU place a " + name in text or "YOU place " + name in text or ("YOU spend" in text and name in text)) and cost > spendable and bad.is_empty():
				bad = "%.1f s: %s (spendable %d)" % [game.day_cycle.elapsed_seconds, text, spendable]
		if po.upgrade_offer_button.visible and not game.breach_system.is_sealed() and bad.is_empty():
			for name: String in BUILD_NAMES:
				if name in po.upgrade_offer_button.text and int(VaultBuilding.COSTS[BUILD_NAMES[name]]) > spendable:
					bad = "Spend: " + po.upgrade_offer_button.text
	_assert_true(bad.is_empty(), "no pre-seal Next/Spend build eats the hatch patch: " + bad)
	_assert_true(saw_save, "Next says 'save 4 for the hatch patch' when a build would not fit")
	_dispose(game)


# Codex 6530847810 on #140: with the patch funded (owed 0) and no queued builds, Next said
# "YOU save 0 for the queued builds · THEY finish them" until the seal.
func _test_zero_commitment() -> void:
	var game := _idle_05()
	var po := game.player_orders
	var held := ""
	var bad := ""
	while not game.breach_system.is_sealed() and game.day_cycle.elapsed_seconds < 55.0 and not game.ended:
		if game.day_cycle.elapsed_seconds > 15.0:
			game.breach_system.patch_delivered = BreachSystem.PATCH_COST
			game.food_system.salvage = mini(game.food_system.salvage, 3)
		_tick(game)
		if game.day_cycle.elapsed_seconds <= 15.5 or game.breach_system.is_sealed():
			continue
		var text: String = po.objective_label.text
		var help := str(po._displayed_next_step.get("help", ""))
		if bad.is_empty() and ("YOU save 0 " in text or " 0 salvage for" in help or " 0 for queued" in help or "keep 0" in help):
			bad = "%.1f s: %s | %s" % [game.day_cycle.elapsed_seconds, text, help]
		if held.is_empty() and game.queued_build_commitment() == 0 and game.food_plan_patch_owed() == 0 and "more salvage for the " in text:
			for name: String in BUILD_NAMES:
				var need := int(VaultBuilding.COSTS[BUILD_NAMES[name]]) - maxi(0, game.food_plan_spendable())
				if ("YOU need %d more salvage for the %s · THEY dig salvage" % [need, name]) in text:
					held = text
	_assert_true(bad.is_empty(), "no Next or help claims a reserve of 0: " + bad)
	_assert_true(not held.is_empty(), "a held build names its real shortfall ('YOU need N more salvage for the <build>')")
	_dispose(game)


func _test_patch_leads() -> void:
	var game := _idle_05()
	var po := game.player_orders
	while game.breach_system.phase == BreachSystem.Phase.DORMANT and not game.ended:
		_tick(game)
	game.food_system.salvage = 0
	while game.breach_system.phase != BreachSystem.Phase.OPEN and not game.ended:
		game.food_system.salvage = 0
		_tick(game)
	game.residents[0].needs.food = 5.0
	for i in 20:
		_tick(game)
	var alerts: String = po.alert_label.text.replace(char(0xA0), " ").replace(char(0x2009), " ").strip_edges()
	_assert_true(alerts.begins_with("BREACH OPEN"), "BREACH OPEN leads the alert line, got: " + alerts)
	# A lead wider than the rail breaks at its own " · " onto a second line.
	var lead: String = po.alert_list[0]
	_assert_true(alerts.replace("\n", " · ").begins_with(lead), "the label renders the leading alert, got: " + alerts)
	_assert_true(lead.count(" · ") >= 2, "the leading alert names the patch step, got: " + lead)
	_assert_true("CRITICAL" in alerts or po.all_alerts.size() > 1, "another alert is live to outrank")
	_assert_true("hatch" in po.objective_label.text, "Next names the patch step, got: " + po.objective_label.text)
	_dispose(game)


func _test_recap() -> void:
	var game := _idle_05()
	_to_seconds_plain(game, 2.0)
	var dax: VaultResident = game.residents[0]
	game.job_system.release_resident(dax)
	dax.drafted = true
	dax.needs.food = 0.0
	dax.needs.health = 0.1
	game._simulation_step(VaultGame.SIMULATION_TICK)
	game.player_orders.refresh()
	var body: String = game.player_orders.outcome_text.text
	_assert_true("died of" in body, "the recap shows, got: " + body)
	_assert_false("No tip could have saved them" in body, "the recap omits the no-tip claim")
	_dispose(game)


func _to_seconds_plain(game: VaultGame, seconds: float) -> void:
	while game.day_cycle.elapsed_seconds < seconds and not game.ended:
		_tick(game)


func _test_flicker() -> void:
	var game := _idle_05()
	var po := game.player_orders
	var changes := 0
	var rec_swaps := 0
	var last := ""
	while game.day_cycle.elapsed_seconds < 275.0 and not game.ended:
		_tick(game)
		if game.day_cycle.elapsed_seconds < 230.0:
			continue
		var text: String = po.objective_label.text
		if text != last:
			changes += 1
			if "suffocating" in text and "Rec Console" in text:
				rec_swaps += 1
			last = text
	_assert_equal(rec_swaps, 0, "a suffocating Next never swaps the Air Recycler for Rec Console")
	_assert_true(changes <= 4, "Next changes at most 4 times from 230 s, got %d" % changes)
	_dispose(game)
