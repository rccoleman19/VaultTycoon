extends "res://tests/test_air_early_warning.gd"

# QA 05 seed 8 at 144 s: "OXYGEN LOW IN" was below the fold because Next named the
# Air Recycler and DARKNESS/BED/REC/MOOD/CACHE filled the list. ALERTS now lead with
# lethality (air, then starvation, then critical HP, then the rest), and air alerts stay
# listed even when Next names the fix. The Spend button states the cost of the build it
# arms, not the salvage held. Assertions read the alert line and the Spend button.

const SEEDS := [4242, 8, 1234]


func _run() -> void:
	_run_case("idle 05, three seeds: the oxygen alert leads the visible alert line at ~144 s", _test_air_visible)
	_run_case("ALERTS sort by lethality: air, starvation, critical HP, then the rest", _test_lethality_order)
	_run_case("Spend shows the cost of the build it names", _test_spend_cost)
	print("")
	if _failure_count == 0:
		print("ALERT PRIORITY TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("ALERT PRIORITY TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
			_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _idle_05(seed: int) -> VaultGame:
	var game := _spawn_game()
	game.new_game(false, seed, 5)
	game.begin_shift()
	return game


func _to_seconds(game: VaultGame, seconds: float) -> void:
	while game.day_cycle.elapsed_seconds < seconds and not game.ended:
		game.step_simulation(SAMPLE_S)
	game.player_orders.refresh()


func _test_air_visible() -> void:
	for seed: int in SEEDS:
		var game := _idle_05(seed)
		_to_seconds(game, 145.0)
		var line: String = game.player_orders.alert_label.text.replace("\u00a0", " ")
		_assert_true(line.begins_with("OXYGEN LOW IN "), "seed %d at %.1f s: the alert line leads with the oxygen alert [%s]" % [seed, game.day_cycle.elapsed_seconds, line])
		_dispose(game)


func _test_lethality_order() -> void:
	var game := _idle_05(8)
	# Ari is nearer death than the pantry runs out, so a deadline-only order would put
	# CRITICAL ahead of LOW MEALS; the starvation tier must still lead it.
	game.residents[0].needs.health = 1.0
	game.food_system.meals = 400
	var mixed: Array[String] = ["DARKNESS · 2 CREW UNLIT", "BED SHORTAGE", "CRITICAL: Ari", "LOW MEALS", "OXYGEN LOW IN 00:50"]
	var ordered: Array[String] = game.player_orders._order_alerts_by_urgency(mixed)
	_assert_equal(ordered.slice(0, 3), ["OXYGEN LOW IN 00:50", "LOW MEALS", "CRITICAL: Ari"] as Array[String], "air, then starvation, then critical HP: %s" % str(ordered))
	_assert_equal(ordered.slice(3), ["DARKNESS · 2 CREW UNLIT", "BED SHORTAGE"] as Array[String], "the rest keep their order: %s" % str(ordered))
	_dispose(game)


func _test_spend_cost() -> void:
	var game := _idle_05(8)
	_to_seconds(game, 145.0)
	var salvage := game.food_system.salvage
	_assert_equal(_spend_text(game), "Spend 14: build Air Recycler", "Spend states the Air Recycler's cost, not salvage held (%d)" % salvage)
	_dispose(game)
	var short := _game(40, true)
	while short.player_orders._planned_power_spare() >= int(VaultBuilding.POWER_DEMAND[VaultBuilding.Kind.AIR_RECYCLER]):
		_add_complete(short, VaultBuilding.Kind.GROW_TRAY)
	short.oxygen_system.refresh_rates(short.residents, short.buildings, false)
	short.oxygen_system.oxygen = OxygenSystem.LOW_OXYGEN_THRESHOLD + (-short.oxygen_system.net_rate) * 30.0
	short.player_orders.refresh()
	_assert_equal(_spend_text(short), "Spend 18: build Charge Node", "power short: Spend states the Charge Node's cost")
	_dispose(short)
