extends "res://tests/test_runner.gd"

# Wing seed (QA 2026-10-18c #2, slice 1).


func _run() -> void:
	_run_case("the boot and test wing is the legacy seed with today's 60 s warning", _test_legacy_default)
	_run_case("a save without wing_seed loads as the legacy wing", _test_legacy_save)
	_run_case("seeded windows are 45-80 s and every slot is reachable", _test_window_table)
	_run_case("the same seed plays the same run", _test_same_seed_same_run)
	_run_case("different seeds play different runs", _test_different_seeds_differ)
	_run_case("a seeded save round-trips its seed and window", _test_seeded_round_trip)
	_run_case("save validation follows the saved seed", _test_validation_uses_seed)
	_run_case("NEW WING rolls a fresh non-legacy seed and labels the wing", _test_new_wing_button)
	_run_case("golden seed to window pairs are frozen", _test_golden_pairs)
	_run_case("every window warns and opens on time from a natural clock", _test_natural_boundaries)
	_run_case("seed picking is pure, bounded and changes the window", _test_pick_wing_seed)
	_run_case("seedless saves keep the historical breach synthesis", _test_legacy_synthesis)
	_run_case("a seeded save without breach state or clock is rejected", _test_seeded_needs_breach)
	_run_case("a managed 45 s seeded wing still wins", _test_managed_early_wing_wins)
	_run_case("a patch finished on the seeded open tick prevents the opening", _test_seeded_open_boundary_patch)

	print("")
	if _failure_count == 0:
		print("WING SEED TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("WING SEED TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
			_failed_case_count,
			_case_count,
			_failure_count,
			_assertion_count,
		])
		quit(1)


func _first_seed_with_window(window: float) -> int:
	for s in range(1, VaultGame.MAX_WING_SEED + 1):
		if BreachSystem.warning_at_for_seed(s) == window:
			return s
	return -1


# A fixed scripted opening, then the sim runs to `until` with warnings acknowledged.
func _scripted_run(wing_seed: int, until: float) -> VaultGame:
	var game := _spawn_game()
	game.new_game(false, wing_seed)
	game.begin_shift()
	game.set_tool("dig")
	for x in [16, 15, 14]:
		for y in [13, 14, 15, 16]:
			game.issue_order(Vector2i(x, y))
	game.set_tool("select")
	game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(27, 12))
	game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(21, 12))
	while game.day_cycle.elapsed_seconds < until and not game.ended:
		if game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged:
			game.acknowledge_breach_warning(true)
		game.user_paused = false
		game.step_simulation(0.5)
	return game


func _test_legacy_default() -> void:
	var game := _spawn_game()
	_assert_equal(game.wing_seed, VaultGame.LEGACY_WING_SEED, "boot wing is legacy")
	_assert_equal(game.breach_system.warning_at, 60.0, "legacy warning at 60 s")
	_assert_equal(game.breach_system.get_open_at(), 80.0, "legacy open at 80 s")
	_assert_equal(int(game.create_snapshot()["wing_seed"]), 0, "snapshot carries wing_seed 0")
	_assert_equal(game.player_orders.wing_brand_label.text, "VAULT WING // SUBLEVEL 07", "legacy top bar unchanged")
	_assert_equal(game.player_orders.wing_briefing_title.text, "VAULT WING 07 // SEAL STABILIZATION", "legacy briefing unchanged")
	game.new_game(false)
	_assert_equal(game.wing_seed, 0, "new_game() without a seed stays legacy")
	_dispose(game)


func _test_legacy_save() -> void:
	var game := _scripted_run(0, 65.0)
	var snapshot := game.create_snapshot()
	snapshot.erase("wing_seed")
	game.new_game(false, 0x3F2A)
	_assert_true(game.apply_snapshot(JSON.parse_string(JSON.stringify(snapshot))), "legacy save (no wing_seed) loads")
	_assert_equal(game.wing_seed, 0, "legacy save is the legacy seed")
	_assert_equal(game.breach_system.warning_at, 60.0, "legacy save warns at 60 s")
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.WARNING, "legacy WARNING at 65 s restored")
	_assert_equal(game.player_orders.wing_brand_label.text, "VAULT WING // SUBLEVEL 07", "legacy save relabels the wing")
	_dispose(game)


func _test_window_table() -> void:
	var seen := {}
	for s in range(1, VaultGame.MAX_WING_SEED + 1):
		var w := BreachSystem.warning_at_for_seed(s)
		if not seen.has(w):
			_assert_true(w >= 45.0 and w <= 80.0 and fmod(w, 5.0) == 0.0, "window %s in 45-80 by 5" % w)
		seen[w] = int(seen.get(w, 0)) + 1
	_assert_equal(seen.size(), 8, "all 8 windows reachable")
	for w: float in seen:
		_assert_true(int(seen[w]) > 6000, "window %s is common (%d seeds)" % [w, seen[w]])
	_assert_equal(BreachSystem.warning_at_for_seed(0), 60.0, "seed 0 is legacy 60 s")
	_assert_equal(BreachSystem.warning_at_for_seed(0x3F2A), BreachSystem.warning_at_for_seed(0x3F2A), "pure function")


func _test_same_seed_same_run() -> void:
	var a := _scripted_run(0x3F2A, 100.0)
	var b := _scripted_run(0x3F2A, 100.0)
	_assert_equal(a.breach_system.warning_at, b.breach_system.warning_at, "same seed, same window")
	_assert_equal(JSON.stringify(a.create_snapshot()), JSON.stringify(b.create_snapshot()), "same seed, byte-identical snapshot at 100 s")
	_dispose(a)
	_dispose(b)


func _test_different_seeds_differ() -> void:
	var early := _first_seed_with_window(45.0)
	var late := _first_seed_with_window(80.0)
	_assert_true(early > 0 and late > 0, "seeds for 45 s and 80 s exist")
	var a := _scripted_run(early, 50.0)
	var b := _scripted_run(late, 50.0)
	_assert_equal(a.breach_system.phase, BreachSystem.Phase.WARNING, "45 s wing is in WARNING at 50 s")
	_assert_equal(b.breach_system.phase, BreachSystem.Phase.DORMANT, "80 s wing is still dormant at 50 s")
	var sa := a.create_snapshot()
	var sb := b.create_snapshot()
	sa.erase("wing_seed")
	sb.erase("wing_seed")
	_assert_true(JSON.stringify(sa) != JSON.stringify(sb), "different seeds, different snapshots beyond the seed field")
	_dispose(a)
	_dispose(b)
	# Repair blocked: at 70 s the 45 s wing is OPEN and venting while the 80 s wing is still dormant.
	a = _blocked_run(early, 70.0)
	b = _blocked_run(late, 70.0)
	_assert_equal(a.breach_system.phase, BreachSystem.Phase.OPEN, "45 s wing OPEN at 70 s")
	_assert_equal(b.breach_system.phase, BreachSystem.Phase.DORMANT, "80 s wing DORMANT at 70 s")
	_assert_true(a.oxygen_system.oxygen < b.oxygen_system.oxygen - 5.0, "45 s wing has lost air (%.1f vs %.1f)" % [a.oxygen_system.oxygen, b.oxygen_system.oxygen])
	_dispose(a)
	_dispose(b)
	var legacy := _scripted_run(0, 50.0)
	_assert_equal(legacy.breach_system.phase, BreachSystem.Phase.DORMANT, "legacy dormant at 50 s")
	_dispose(legacy)


func _test_seeded_round_trip() -> void:
	var s := _first_seed_with_window(45.0)
	var game := _scripted_run(s, 52.0)
	var snap := JSON.stringify(game.create_snapshot())
	game.new_game(false)
	_assert_true(game.apply_snapshot(JSON.parse_string(snap)), "seeded save loads")
	_assert_equal(game.wing_seed, s, "seed restored")
	_assert_equal(game.breach_system.warning_at, 45.0, "window restored from the seed")
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.WARNING, "seeded WARNING at 52 s restored")
	_assert_equal(game.player_orders.wing_brand_label.text, "VAULT WING // 07-%04X" % s, "top bar names the seeded wing")
	_assert_equal(game.player_orders.wing_briefing_title.text, "VAULT WING 07-%04X // SEAL STABILIZATION\nHATCH TEST AT 00:45\n3 ROCK POCKETS · 2 SALVAGE VEINS" % s, "briefing names the seeded wing, its test time and contents")
	_assert_equal(JSON.stringify(game.create_snapshot()), snap, "round trip is byte-identical")
	_dispose(game)


func _test_validation_uses_seed() -> void:
	var s := _first_seed_with_window(45.0)
	var game := _scripted_run(s, 52.0)
	var snap: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	var as_legacy := snap.duplicate(true)
	as_legacy.erase("wing_seed")
	_assert_true(not game.apply_snapshot(as_legacy), "WARNING at 52 s is invalid for the legacy 60 s wing")
	_assert_equal(game.wing_seed, s, "a rejected save leaves the wing seed alone")
	_assert_equal(game.breach_system.warning_at, 45.0, "a rejected save leaves the window alone")
	for bad: Variant in [-1, 0x10000, 1.5, "3F2A", true]:
		var tampered := snap.duplicate(true)
		tampered["wing_seed"] = bad
		_assert_true(not game.apply_snapshot(tampered), "wing_seed %s rejected" % str(bad))
	_assert_true(game.apply_snapshot(snap), "the genuine seeded save still loads")
	_dispose(game)


func _test_new_wing_button() -> void:
	var game := _spawn_game()
	var seen := {}
	for i in 5:
		var before := game.wing_seed
		var rolled := game.roll_wing_seed()
		_assert_true(rolled >= 1 and rolled <= VaultGame.MAX_WING_SEED and rolled != before, "roll %d is a new non-legacy seed" % rolled)
		game.new_game(true, rolled)
		seen[rolled] = true
		_assert_equal(game.wing_seed, rolled, "new wing takes the rolled seed")
		_assert_equal(game.breach_system.warning_at, BreachSystem.warning_at_for_seed(rolled), "window follows the seed")
		var warn := roundi(BreachSystem.warning_at_for_seed(rolled))
		_assert_equal(game.player_orders.wing_briefing_title.text, "VAULT WING 07-%04X // SEAL STABILIZATION\nHATCH TEST AT %02d:%02d\n%s" % [rolled, warn / 60, warn % 60, PlayerOrders.wing_layout_summary(rolled)], "briefing shows the wing id, test time and contents")
	_assert_true(seen.size() >= 2, "rolls vary")
	_dispose(game)


func _blocked_run(wing_seed: int, until: float) -> VaultGame:
	var game := _spawn_game()
	game.new_game(false, wing_seed)
	game.begin_shift()
	for resident: VaultResident in game.residents:
		resident.set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
		resident.set_work_priority("craft", VaultResident.PRIORITY_DISABLED)
	while game.day_cycle.elapsed_seconds < until and not game.ended:
		if game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged:
			game.acknowledge_breach_warning(true)
		game.user_paused = false
		game.step_simulation(VaultGame.SIMULATION_TICK)
	return game


func _test_golden_pairs() -> void:
	# Frozen: the mapping is save behavior. Changing it needs a migration, not a test edit.
	var golden := {1: 80.0, 2: 70.0, 3: 55.0, 4: 60.0, 6: 65.0, 8: 45.0, 15: 75.0, 17: 50.0, 0x3F2A: 80.0, 0x7FFF: 65.0, 0xFFFF: 50.0, 999: 75.0}
	for s: int in golden:
		_assert_equal(BreachSystem.warning_at_for_seed(s), golden[s], "seed %d window" % s)
	_assert_equal(PlayerOrders.wing_id(0x3F2A), "07-3F2A", "wing id format")
	_assert_equal(PlayerOrders.wing_id(1), "07-0001", "wing id pads to 4 hex")
	_assert_equal(PlayerOrders.wing_id(0), "07", "legacy wing id")


func _test_natural_boundaries() -> void:
	for s: int in [8, 17, 3, 4, 6, 2, 15, 1]:
		var window := BreachSystem.warning_at_for_seed(s)
		var game := _blocked_run(s, window - 0.5)
		var warned_at := -1.0
		var opened_at := -1.0
		while game.day_cycle.elapsed_seconds < window + 21.0 and not game.ended:
			if game.breach_system.phase == BreachSystem.Phase.WARNING and warned_at < 0.0:
				warned_at = game.day_cycle.elapsed_seconds
				game.acknowledge_breach_warning(true)
			if game.breach_system.phase == BreachSystem.Phase.OPEN and opened_at < 0.0:
				opened_at = game.day_cycle.elapsed_seconds
			game.user_paused = false
			game.step_simulation(VaultGame.SIMULATION_TICK)
		_assert_true(warned_at >= window - 0.0001 and warned_at <= window + 0.1001, "seed %d warns within a tick of %s (%.4f)" % [s, window, warned_at])
		_assert_true(opened_at >= window + 20.0 - 0.0001 and opened_at <= window + 20.1001, "seed %d opens within a tick of %s (%.4f)" % [s, window + 20.0, opened_at])
		_dispose(game)


func _test_pick_wing_seed() -> void:
	for entropy in [0, 1, 7, 123456789, 0x7FFFFFFF, -5]:
		for current in [0, 1, 8, 0xFFFF]:
			var a := VaultGame.pick_wing_seed(entropy, current)
			_assert_equal(a, VaultGame.pick_wing_seed(entropy, current), "pure for %d/%d" % [entropy, current])
			_assert_true(a >= 1 and a <= VaultGame.MAX_WING_SEED, "in range")
			_assert_true(BreachSystem.warning_at_for_seed(a) != BreachSystem.warning_at_for_seed(current), "window differs from the current wing (%d -> %d)" % [current, a])


func _test_legacy_synthesis() -> void:
	var game := _spawn_game()
	game.new_game(false, 8)
	var cases := {59.9: BreachSystem.Phase.DORMANT, 60.0: BreachSystem.Phase.WARNING, 79.9: BreachSystem.Phase.WARNING, 80.0: BreachSystem.Phase.SEALED}
	for t: float in cases:
		var snap := game.create_snapshot()
		snap.erase("wing_seed")
		snap.erase("breach")
		snap["day"]["elapsed_seconds"] = t
		snap["day"]["current_day"] = 2 if t >= 40.0 else 1
		var ok := game.apply_snapshot(JSON.parse_string(JSON.stringify(snap)))
		_assert_true(ok, "seedless save at %s loads" % t)
		_assert_equal(game.wing_seed, 0, "seedless save becomes legacy even over a seeded wing")
		_assert_equal(game.breach_system.phase, cases[t], "historical synthesis at %s" % t)
		game.new_game(false, 8)
	_dispose(game)


func _test_seeded_needs_breach() -> void:
	var game := _scripted_run(8, 30.0)
	var snap: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	var no_breach := snap.duplicate(true)
	no_breach.erase("breach")
	_assert_true(not game.apply_snapshot(no_breach), "seeded save without breach rejected")
	var empty_breach := snap.duplicate(true)
	empty_breach["breach"] = {}
	_assert_true(not game.apply_snapshot(empty_breach), "seeded save with empty breach rejected")
	var no_clock := snap.duplicate(true)
	no_clock["day"].erase("elapsed_seconds")
	_assert_true(not game.apply_snapshot(no_clock), "seeded save without a clock rejected")
	var float_seed := snap.duplicate(true)
	float_seed["wing_seed"] = 8.0
	_assert_true(game.apply_snapshot(float_seed), "a JSON float seed 8.0 is accepted")
	_assert_equal(game.wing_seed, 8, "and converted to int")
	_dispose(game)


func _test_managed_early_wing_wins() -> void:
	var game := _spawn_game()
	game.new_game(false, 8)
	_assert_equal(game.breach_system.warning_at, 45.0, "seed 8 warns at 45 s")
	var bed_cells: Array[Vector2i] = [Vector2i(18, 12), Vector2i(19, 12), Vector2i(20, 12), Vector2i(21, 12)]
	for cell: Vector2i in bed_cells:
		_add_completed_building(game, VaultBuilding.Kind.BED, cell)
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(22, 12))
	_add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(23, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(25, 12))
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(26, 12))
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(27, 12))
	_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(24, 12))
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.begin_shift()
	game.step_simulation(DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE + VaultGame.SIMULATION_TICK)
	_assert_true(game.ended and game.outcome == "win", "managed 45 s wing wins")
	_assert_true(game.breach_system.is_sealed(), "and seals the hatch")
	_dispose(game)


# Mirrors test_runner's exact 80 s boundary patch at seeded open times. The
# final tick's patch work must land before the hatch is judged at the seeded boundary.
func _test_seeded_open_boundary_patch() -> void:
	for s: int in [8, 6, 1]:
		var game := _spawn_game()
		game.new_game(false, s)
		game.begin_shift()
		for index in game.residents.size():
			var resident: VaultResident = game.residents[index]
			resident.needs.food = 100.0
			resident.needs.rest = 100.0
			resident.needs.light_mood = 100.0
			resident.work_allowed.dig = false
			resident.work_allowed.haul = false
			resident.work_allowed.craft = index == 0
			resident.work_allowed.cook = false
		game.residents[0].position = game.map_grid.cell_to_world(BreachSystem.HATCH_CELL)
		var opening_signals := {"count": 0}
		game.breach_system.breach_opened.connect(func() -> void:
			opening_signals["count"] = int(opening_signals["count"]) + 1
		)
		var open_at := game.breach_system.get_open_at()
		var just_before_open := open_at - VaultGame.SIMULATION_TICK
		var day := int(just_before_open / DayCycle.SECONDS_PER_DAY) + 1
		game.day_cycle.deserialize({"elapsed_seconds": just_before_open, "current_day": day, "completed": false})
		game.breach_system.advance(0.0, just_before_open)
		_assert_equal(game.breach_system.phase, BreachSystem.Phase.WARNING, "seed %d is in WARNING one tick before %s" % [s, open_at])
		game.breach_system.patch_delivered = BreachSystem.PATCH_COST
		game.breach_system.patch_work_left = VaultGame.SIMULATION_TICK
		game.job_system.rebuild_from_state()

		game._simulation_step(VaultGame.SIMULATION_TICK)

		_assert_approximately(game.day_cycle.elapsed_seconds, open_at, 0.0001, "seed %d boundary step reaches %s" % [s, open_at])
		_assert_true(game.breach_system.is_sealed(), "seed %d final tick of patch work seals at the seeded boundary" % s)
		_assert_equal(opening_signals["count"], 0, "seed %d emits no open event" % s)
		_assert_approximately(game.oxygen_system.breach_loss_rate, 0.0, 0.0001, "seed %d never starts the leak" % s)
		_dispose(game)
