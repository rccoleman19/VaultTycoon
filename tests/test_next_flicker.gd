extends "res://tests/test_runner.gd"

# Presentation regressions: T1-T5 use helpers already present on 171901b8.
# Time is advanced on the game's simulation clock; refresh is the observation
# path, and repeated Next getters must not start or age an idle interval.
const AIR_CELL := Vector2i(25, 12)
const SPEND_REC := "Next: YOU spend 8: build Rec Console · THEY craft"
const FUND_KINDS := [VaultBuilding.Kind.AIR_RECYCLER, VaultBuilding.Kind.BED,
	VaultBuilding.Kind.KITCHEN, VaultBuilding.Kind.GROW_TRAY,
	VaultBuilding.Kind.RECREATION_CONSOLE, VaultBuilding.Kind.GENERATOR]


func _run() -> void:
	_run_case("T1 continuously idle window has exact sim-time boundaries and resets", _test_idle_window)
	_run_case("T2 presentation hold survives jitter and yields to urgency or a changed step", _test_hold)
	_run_case("T3 affordable named fixtures never receive funding or reclamation advice", _test_affordability)
	_run_case("T4 engaged late shifts spend on live survival needs", _test_engaged)
	_run_case("T5 short between-job idles do not flicker across 25 sim seconds", _test_flicker_count)
	_run_case("D1 starving labels require the named resident's real runway", _test_starving_runway)
	_run_case("D2 starving names stay stable through sub-ten-second rank changes", _test_starving_sticky_name)
	_run_case("D3 starving names switch at ten seconds and clear after feeding", _test_starving_switch)
	_run_case("D4 healthy 03/05 openings never name a forecast starvation", _test_starving_opening_jitter)
	_run_case("D5 a hatch warning keeps the unnamed food forecast without prefixing the hatch step", _test_unnamed_over_breach)
	_run_case("D6 the food forecast onset matches the unheld runway trigger", _test_forecast_onset)
	_run_case("D7 the food forecast holds without an on-off flip and releases on schedule", _test_forecast_hold)
	_run_case("D8 a named death overrides the forecast hold", _test_forecast_named_override)
	_run_case("D9 the unnamed prefix goes only on food-chain steps", _test_prefix_food_chain_only)
	_run_case("D10 place 1 bunk, place 2 bunks and place bunks are one stable step", _test_bunk_text_stable)
	_run_case("D11 the food-worker Rec blocker waits out the Next hold of a bunk step", _test_rec_blocker_hold)
	print("NEXT FLICKER TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _wing(level := 5, extra_power := true, complete_bunks := true, complete_air := true) -> VaultGame:
	var game := _spawn_game()
	game.new_game(false, 4242, level)
	game.begin_shift()
	game.user_paused = true
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
		resident.drafted = false
		resident.sleeping = false
		resident.bed_id = -1
		resident.medical_bed_id = -1
		resident.state = "Assembling fixture"
	game.food_system.meals = 100
	game.food_system.raw_food = 0
	for x in range(17, 29):
		var cell := Vector2i(x, 10)
		_assert_true(game.map_grid.queue_dig(cell) and game.map_grid.apply_dig_work(cell, 8.0), "fixture carves the real twelve-rock gate")
	game.job_system.jobs = game.job_system.jobs.filter(func(job: Dictionary) -> bool:
		return int(job.type) not in [JobSystem.JobType.DIG, JobSystem.JobType.HAUL_RUBBLE])
	if complete_bunks:
		_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(20, 12))
		_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(21, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(22, 12))
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12))
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(24, 12))
	if complete_air:
		_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, AIR_CELL)
	if extra_power:
		_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(26, 12))
	game.breach_system.phase = BreachSystem.Phase.SEALED
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.patch_work_left = 0.0
	game.player_orders.show_breach_warning(false)
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	_assert_true(game.map_grid.dig_marks.is_empty() and game.job_system.get_uncredited_rubble() == 0, "fixture has no passive dig funding")
	return game


func _nudge_wing() -> VaultGame:
	var game := _wing()
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY:
			building.upgrade_tier = VaultBuilding.UPGRADE_TIER_MAX
	game.food_system.salvage = 8
	return game


func _advance_clock(game: VaultGame, seconds: float) -> void:
	game.day_cycle.elapsed_seconds += seconds
	game.player_orders.refresh()


func _next(game: VaultGame) -> Dictionary:
	return game.player_orders._primary_next_step()


func _text(game: VaultGame) -> String:
	return str(_next(game).get("text", ""))


func _present(game: VaultGame, step: Dictionary) -> Dictionary:
	return game.player_orders._salvage_next_step(step.duplicate(true))


func _idle_for(game: VaultGame, seconds: float) -> void:
	game.player_orders.refresh()
	_advance_clock(game, seconds)


func _assert_no_salvage_action(game: VaultGame, message: String) -> void:
	var step := _next(game)
	_assert_true(str(step.get("action", "")) not in ["reclaim", "spend"], message)
	_assert_true("begin reclamation" not in str(step.get("text", "")) and "YOU spend" not in str(step.get("text", "")), message + " has no lead/nudge text")


func _test_idle_window() -> void:
	var game := _nudge_wing()
	game.residents[0].state = "Idle"
	game.player_orders.refresh()
	# Getter calls at unchanged sim time must not accumulate observation time.
	for _i in range(12):
		_next(game)
	_assert_false(game.player_orders._has_idle_crew(), "T1 repeated getters are idempotent at the beginning of an idle interval")
	_advance_clock(game, 1.0)
	_assert_no_salvage_action(game, "T1 one second between jobs never triggers a salvage action")
	_advance_clock(game, 1.9)
	_assert_false(game.player_orders._has_idle_crew(), "T1 2.9 seconds does not meet the sustained window")
	_assert_no_salvage_action(game, "T1 2.9 second idle keeps the underlying Next")
	_advance_clock(game, 0.1)
	_assert_true(game.player_orders._has_idle_crew(), "T1 exactly 3.0 sim seconds qualifies as sustained idle")
	_assert_equal(_text(game), SPEND_REC, "T1 sustained idle permits the affordable spend nudge")
	game.residents[0].state = "Preparing meals"
	game.player_orders.refresh()
	_assert_false(game.player_orders._has_idle_crew(), "T1 becoming busy immediately clears the tracked interval")
	game.residents[0].state = "Idle"
	game.player_orders.refresh()
	_advance_clock(game, 2.9)
	_assert_false(game.player_orders._has_idle_crew(), "T1 a second idle interval restarts at zero")
	_advance_clock(game, 0.1)
	_assert_true(game.player_orders._has_idle_crew(), "T1 the restarted interval reaches its own 3.0 second boundary")
	game.residents[0].drafted = true
	game.player_orders.refresh()
	_assert_false(game.player_orders._has_idle_crew(), "T1 drafting resets sustained idle")
	game.residents[0].drafted = false
	game.player_orders.refresh()
	_advance_clock(game, 2.9)
	_assert_false(game.player_orders._has_idle_crew(), "T1 undrafting does not restore the old interval")
	_advance_clock(game, 0.1)
	game.residents[0].alive = false
	game.player_orders.refresh()
	_assert_false(game.player_orders._has_idle_crew(), "T1 a dead resident never counts as sustained idle")
	game.residents[0].alive = true
	game.player_orders.refresh()
	_advance_clock(game, 2.9)
	_assert_false(game.player_orders._has_idle_crew(), "T1 restoring a resident cannot revive its pre-death idle interval")
	_dispose(game)
	game = _nudge_wing()
	# Snapshot validation requires a real seal after the warning boundary,
	# including the emitted-transition flags, not the earlier unit shortcut.
	game.breach_system.reset()
	game.day_cycle.elapsed_seconds = game.breach_system.warning_at
	game.breach_system.advance(0.0, game.day_cycle.elapsed_seconds)
	var delivered := game.breach_system.add_delivery(BreachSystem.PATCH_COST)
	var sealed := game.breach_system.apply_patch_work(BreachSystem.PATCH_WORK_SECONDS)
	game.player_orders.show_breach_warning(false)
	_assert_true(delivered == BreachSystem.PATCH_COST and sealed, "T1 snapshot fixture seals through the real hatch API")
	# Instant fixture patching skips the scheduler tick that retires the
	# warning's supply job; rebuild the real post-seal job state before save.
	game.job_system.rebuild_from_state()
	game.residents[0].state = "Idle"
	_idle_for(game, 3.0)
	game.day_cycle.current_day = floori(game.day_cycle.elapsed_seconds / DayCycle.SECONDS_PER_DAY) + 1
	_assert_equal(_text(game), SPEND_REC, "T1 load-reset fixture starts with a held sustained-idle nudge")
	var snapshot := game.create_snapshot()
	_assert_true(game.apply_snapshot(snapshot), "T1 the real snapshot loader accepts the same-clock fixture")
	game.player_orders.refresh()
	_assert_false(game.player_orders._has_idle_crew(), "T1 loading at the same sim time resets the old residents' idle intervals")
	_assert_no_salvage_action(game, "T1 loading clears the old held presentation")
	_advance_clock(game, 2.9)
	_assert_false(game.player_orders._has_idle_crew(), "T1 loaded residents need a fresh complete idle window")
	_advance_clock(game, 0.1)
	_assert_true(game.player_orders._has_idle_crew(), "T1 loaded idle residents qualify after three new sim seconds")
	game.new_game(false, 4242, 5)
	_assert_false(game.player_orders._has_idle_crew(), "T1 new game clears tracking for the previous crew")
	_dispose(game)


func _test_hold() -> void:
	var game := _nudge_wing()
	game.residents[0].state = "Idle"
	_idle_for(game, 3.0)
	var held := _text(game)
	_assert_equal(held, SPEND_REC, "T2 hold begins with an affordable idle spend decision")
	var changes := 0
	var last := held
	for frame in range(10):
		game.residents[0].state = "Preparing meals" if frame % 2 == 0 else "Idle"
		_advance_clock(game, 0.1)
		var current := _text(game)
		if current != last:
			changes += 1
		last = current
	_assert_true(changes <= 1, "T2 ten 0.1-second idle/busy toggles change Next at most once (observed %d)" % changes)
	_assert_equal(last, held, "T2 the positive presentation decision survives the first second of jitter")
	game.residents[0].state = "Preparing meals"
	_advance_clock(game, 0.9)
	_assert_equal(_text(game), held, "T2 a held presentation persists at 1.9 seconds despite stable busy input")
	_advance_clock(game, 0.1)
	_assert_true("YOU spend" not in _text(game), "T2 stable busy input takes effect after the 2.0 second hold expires")
	# Establish a fresh positive hold, then create an actual CRITICAL resident.
	game.residents[0].state = "Idle"
	game.player_orders.refresh()
	_advance_clock(game, 3.0)
	_assert_equal(_text(game), SPEND_REC, "T2 a fresh sustained interval can select spending again")
	var ari: VaultResident = game.residents[0]
	ari.needs.rest = 0.0
	ari.needs.health = 20.0
	ari.drafted = true
	game.player_orders.refresh()
	_assert_equal(_text(game), "Next: Ari exhausted · YOU undraft Ari [R] · THEY rest", "T2 live CRITICAL urgency overrides the hold without advancing sim time")
	# Exercise too-late and same-text urgency metadata through the existing
	# presentation boundary, so controls cannot fail on a missing new method.
	var late := {"text": "Next: Ari starving · nothing lands in time · keep crew fed where possible", "tool": "select", "urgent": true, "too_late": true, "resident_id": ari.resident_id, "cause": "food"}
	_assert_equal(str(_present(game, late).get("text", "")), str(late.text), "T2 a too-late warning overrides immediately")
	var changed := {"text": "Next: YOU enable an Air Recycler · THEY recycle air", "tool": "select", "kind": "food"}
	_assert_equal(str(_present(game, changed).get("text", "")), str(changed.text), "T2 a changed underlying action switches immediately inside the old hold")
	var named := {"text": "Next: Bo starving · YOU undraft Bo [R] · THEY eat/work", "tool": "select", "urgent": true, "resident_id": game.residents[1].resident_id, "cause": "food"}
	_assert_equal(str(_present(game, named).get("text", "")), str(named.text), "T2 a different resident/need urgency is never held behind the old warning")
	_dispose(game)
	game = _wing(5, true, true, false)
	game.food_system.salvage = 0
	_assert_true(game.place_blueprint(VaultBuilding.Kind.AIR_RECYCLER, AIR_CELL), "T2 lead-invalidation fixture has an unfunded Air blueprint")
	var lead := _text(game)
	_assert_true("begin reclamation" in lead, "T2 the held reclamation lead is initially valid")
	game.reclaim_active = true
	_assert_false(game.can_start_reclamation(), "T2 starting reclamation invalidates another start immediately")
	_assert_true("begin reclamation" not in _text(game), "T2 can_start=false invalidates a held lead without waiting two seconds")
	_dispose(game)
	game = _nudge_wing()
	game.residents[0].state = "Idle"
	_idle_for(game, 3.0)
	var same_text := {"text": "Next: Ari starving · YOU place a Rec Console · THEY recover mood", "tool": "rec", "kind": "food", "urgent": false, "resident_id": game.residents[0].resident_id, "cause": "food"}
	var calm := _present(game, same_text)
	_assert_true(str(calm.get("action", "")) != "spend", "T2 same-text urgency fixture begins with a suppressed presentation decision")
	same_text["urgent"] = true
	var urgent := _present(game, same_text)
	_assert_equal(str(urgent.get("text", "")), "Next: Ari starving · YOU spend 8: build Rec Console · THEY craft", "T2 becoming urgent overrides a suppression hold even when underlying text/kind stay identical")
	_assert_true(bool(urgent.get("urgent", false)), "T2 same-text urgent override retains urgency metadata")
	_dispose(game)


func _fund_step(kind: int) -> Dictionary:
	return {"text": "Next: Ari starving · YOU mark 5 rock [E] · THEY fund the %s · bunks in progress" % VaultBuilding.KIND_NAMES[kind],
		"tool": "dig", "help": "Keep crew supplied.", "action": "reclaim", "urgent": true, "resident_id": 1, "cause": "food", "death_seconds": 85.0,
		"in_progress": ["bunks"]}


func _assert_no_funding_words(text: String, name: String, message: String) -> void:
	_assert_true("fund the %s" % name not in text and "begin reclamation" not in text.to_lower(), message + ": " + text)


func _test_affordability() -> void:
	for kind: int in FUND_KINDS:
		var game := _nudge_wing()
		var name: String = VaultBuilding.KIND_NAMES[kind]
		var cost: int = VaultBuilding.COSTS[kind]
		game.food_system.salvage = cost - 1
		var source := _fund_step(kind)
		var poor := _present(game, source)
		_assert_true("THEY fund the %s" % name in str(poor.get("text", "")), "T3 cost-1 keeps the selected %s funding target" % name)
		for stock: int in [cost, cost + 1]:
			game.food_system.salvage = stock
			var rich := _present(game, source)
			var rich_text := str(rich.get("text", ""))
			_assert_no_funding_words(rich_text, name, "T3 stock %d covers %s" % [stock, name])
			_assert_equal(rich_text, "Next: Ari starving · YOU mark 5 rock [E] · THEY build the %s · bunks in progress" % name, "T3 affordable rewrite keeps danger prefix and in-progress suffix")
			_assert_equal(str(rich.get("tool", "")), "dig", "T3 affordable rewrite preserves the source tool")
			_assert_true(str(rich.get("action", "")) != "reclaim", "T3 affordable rewrite removes the reclaim action")
			_assert_equal(rich.get("resident_id", -1), source.resident_id, "T3 affordable rewrite keeps danger metadata")
			_assert_no_funding_words(str(rich.get("help", "")), name, "T3 affordable help never asks for funding")
			# Refresh only the auxiliary surfaces for the selected funding step;
			# a full HUD refresh would choose the fixture's unrelated default.
			game.player_orders._refresh_also()
			game.player_orders._refresh_reclaim_button()
			_assert_no_funding_words(game.player_orders.also_label.text, name, "T3 Also text has no affordable funding lead")
			_assert_no_funding_words(game.player_orders.reclaim_button.text, name, "T3 wing-orders reclamation row has no affordable lead")
			_assert_no_funding_words(game.player_orders.reclaim_button.tooltip_text, name, "T3 reclamation-row help has no affordable lead")
			var placement := {"text": "Next: Ari starving · YOU place %s · THEY craft" % name, "tool": VaultGame.BUILD_KIND_BY_TOOL.find_key(kind), "urgent": true, "resident_id": 1, "cause": "food"}
			_assert_equal(str(_present(game, placement).get("text", "")), str(placement.text), "T3 an already affordable place/craft action remains unchanged")
		# Public Next and HUD help also stay free of invalid named funding text.
		game.player_orders.refresh()
		_assert_no_funding_words(_text(game), name, "T3 public Next has no affordable funding lead")
		_assert_no_funding_words(game.player_orders.tool_status.text, name, "T3 HUD help has no affordable lead")
		# A nominally affordable stockpile still belongs partly to the hatch.
		game.breach_system.phase = BreachSystem.Phase.WARNING
		game.breach_system.patch_delivered = 0
		game.breach_system.patch_work_left = BreachSystem.PATCH_WORK_SECONDS
		game.food_system.salvage = cost
		_assert_true(game.job_system.get_breach_salvage_reserve() > 0, "T3 reserve fixture holds salvage for the hatch")
		var reserved := _present(game, source)
		_assert_true("THEY fund the %s" % name in str(reserved.get("text", "")), "T3 %s affordability subtracts the hatch reserve" % name)
		game.food_system.salvage = cost + game.job_system.get_breach_salvage_reserve()
		_assert_no_funding_words(str(_present(game, source).get("text", "")), name, "T3 adding the reserve funds the named fixture exactly")
		_dispose(game)


func _engaged_wing(level: int) -> VaultGame:
	var game := _wing(level, false)
	# The ordinary Charge Node, emergency supply, and 2/3 Lumens match
	# the probe grids. Air and cooking win priority, shedding the enabled tray.
	_add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(26, 12))
	if level == 3:
		_add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(27, 12))
	var food := [77.0, 84.0, 91.0, 38.0] if level == 5 else [95.0, 42.0, 49.0, 56.0, 73.0]
	var rest := [84.0, 28.0, 56.0, 68.0] if level == 5 else [62.0, 40.0, 68.0, 79.0, 32.0]
	var mood := [36.0, 13.0, 11.0, 12.0] if level == 5 else [37.0, 19.0, 17.0, 16.0, 22.0]
	var states := ["Carrying meal", "Preparing meals", "Idle", "Idle"] if level == 5 else ["Sleeping", "Idle", "Preparing meals", "Idle", "Carrying raw food"]
	for i in range(game.residents.size()):
		var resident: VaultResident = game.residents[i]
		resident.needs.food = food[i]
		resident.needs.rest = rest[i]
		resident.needs.mood = mood[i]
		resident.state = states[i]
		resident.sleeping = states[i] == "Sleeping"
		if states[i] == "Carrying meal":
			resident.current_job_type = JobSystem.JobType.HAUL_MEAL
		elif states[i] == "Preparing meals":
			resident.current_job_type = JobSystem.JobType.COOK
		elif states[i] == "Carrying raw food":
			resident.current_job_type = JobSystem.JobType.HAUL_RAW_FOOD
	game.food_system.salvage = 11 if level == 5 else 29
	game.food_system.raw_food = 1
	game.food_system.meals = 8 if level == 5 else 7
	# Keep the probe's pantry runway, power deficit, and recovery work, but move
	# its stored meals to real pending Haul output so projected stored rations
	# do not hide hunger. The raw pile stays below the second-kitchen threshold.
	game.job_system.queue_meals(Vector2i(24, 12), game.food_system.meals)
	_assert_equal(game.job_system.get_pending_meals(), game.food_system.meals, "T4 the original meal reserve now waits in the real Haul pipeline")
	game.food_system.meals = 0
	_set_food_death(game.residents[0 if level == 5 else 3], 45.0)
	_assert_approximately(_food_death(game, game.residents[0 if level == 5 else 3]), 45.0, 0.00001, "T4 the original named resident has a real 45-second starvation runway")
	game.day_cycle.elapsed_seconds = 149.1 if level == 5 else 137.1
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	var tray := game.get_building_at(Vector2i(23, 12))
	_assert_true(tray.complete and not tray.powered and not tray.manually_disabled, "T4 probe has a complete tray shed by a short grid")
	_assert_equal(game.job_system.get_breach_salvage_reserve(), 0, "T4 sealed probe has no hatch reserve")
	return game


func _test_survival_sink_priority() -> void:
	var game := _nudge_wing()
	if not game.player_orders.has_method("salvage_survival_sink"):
		_assert_true(false, "T4 survival sink helper exists for affordable priority selection")
		_dispose(game)
		return
	game.food_system.salvage = 40
	game.food_system.meals = 0
	game.residents[0].needs.food = 10.0
	var kitchen := game.get_building_at(Vector2i(24, 12))
	game.buildings.erase(kitchen)
	kitchen.free()
	game.power_grid.recalculate(game.buildings)
	_assert_equal(int(game.player_orders.call("salvage_survival_sink", 40)), VaultBuilding.Kind.KITCHEN, "T4 food danger without a Nutrient Station chooses cooking first")
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(24, 12))
	game.food_system.raw_food = 6
	game.power_grid.recalculate(game.buildings)
	_assert_equal(int(game.player_orders.call("salvage_survival_sink", 40)), VaultBuilding.Kind.KITCHEN, "T4 food danger with a raw pile chooses a second Nutrient Station")
	game.food_system.raw_food = 0
	_assert_equal(int(game.player_orders.call("salvage_survival_sink", 40)), VaultBuilding.Kind.GROW_TRAY, "T4 food danger with air and spare power chooses a second Grow Tray")
	var generator := game.get_building_at(Vector2i(26, 12))
	game.buildings.erase(generator)
	generator.free()
	game.power_grid.recalculate(game.buildings)
	_assert_equal(int(game.player_orders.call("salvage_survival_sink", 40)), VaultBuilding.Kind.GENERATOR, "T4 planned Grow Tray demand gets a Charge Node first when spare power is short")
	game.residents[0].needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD
	_assert_equal(int(game.player_orders.call("salvage_survival_sink", 11)), VaultBuilding.Kind.RECREATION_CONSOLE, "T4 an unaffordable power/grow rescue is skipped for an affordable stress-break Rec Console")
	game.food_system.meals = 100
	game.residents[0].needs.food = 100.0
	_assert_equal(int(game.player_orders.call("salvage_survival_sink", 8)), VaultBuilding.Kind.RECREATION_CONSOLE, "T4 the exact stress-break mood threshold independently offers Rec recovery")
	_assert_equal(int(game.player_orders.call("salvage_survival_sink", 7)), -1, "T4 every unaffordable sink is skipped instead of offering an impossible purchase")
	_dispose(game)


func _test_engaged() -> void:
	_test_survival_sink_priority()
	for level: int in [5, 3]:
		var game := _engaged_wing(level)
		game.player_orders.refresh()
		_advance_clock(game, 1.0)
		_assert_true("YOU spend" not in _text(game), "T4 level %02d with only one idle second receives no spend nudge" % level)
		_advance_clock(game, 2.0)
		var step := _next(game)
		var expected := "Next: Ari starving · YOU spend 8: build Rec Console · THEY craft" if level == 5 else "Next: Dax starving · YOU spend 18: build Charge Node · THEY craft"
		_assert_equal(str(step.get("text", "")), expected, "T4 engaged %02d chooses its affordable survival sink and preserves the resident prefix" % level)
		_assert_equal(str(step.get("action", "")), "spend", "T4 engaged survival advice exposes Spend")
		_assert_true(bool(step.get("urgent", false)) and str(step.get("cause", "")) == "food", "T4 engaged spend keeps food danger metadata")
		var immediate := {"text": "Next: Ari starving · YOU disable a Lumen · THEY power the Grow Tray", "tool": "select", "kind": "food", "urgent": true, "resident_id": game.residents[0].resident_id, "cause": "food"}
		_assert_equal(str(_present(game, immediate).get("text", "")), str(immediate.text), "T4 free Lumen power recovery keeps precedence over stored-salvage spending")
		var late := {"text": "Next: Ari starving · nothing lands in time · keep crew fed where possible", "tool": "select", "kind": "food", "urgent": true, "too_late": true, "resident_id": game.residents[0].resident_id, "cause": "food"}
		_assert_equal(str(_present(game, late).get("text", "")), str(late.text), "T4 nothing-lands-in-time warning remains untouched")
		if level == 3:
			# With only 17, the top power rescue is still unaffordable and the
			# underlying step needs it: reclaim names Charge rather than Rec.
			game.food_system.salvage = 17
			_add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(28, 12))
			_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(17, 12))
			game.power_grid.recalculate(game.buildings)
			var power := {"text": "Next: Dax starving · YOU place a Charge Node · THEY power the Grow Tray", "tool": "generator", "kind": "food", "urgent": true, "resident_id": game.residents[3].resident_id, "cause": "food"}
			_assert_equal(str(_present(game, power).get("text", "")), "Next: Dax starving · YOU begin reclamation · +18 · THEY fund the Charge Node", "T4 an unaffordable top-value power rescue names the Charge Node in reclamation")
		_dispose(game)


func _test_flicker_count() -> void:
	var game := _wing(3, false, false, false)
	game.food_system.salvage = 48
	_assert_equal(game.residents.size(), 5, "T5 scenario has a five-resident crew")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(20, 12)), "T5 first Bunk blueprint is queued")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(21, 12)), "T5 second Bunk blueprint is queued")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.AIR_RECYCLER, AIR_CELL), "T5 Air Recycler blueprint is queued")
	game.player_orders.refresh()
	var last := _text(game)
	var changes := 0
	# Unit-level sim frames keep construction, inventories and underlying work
	# constant while reproducing the observed 1-4-frame between-job idles.
	for frame in range(250):
		for i in range(game.residents.size()):
			# Alternate an entirely busy crew with one resident briefly idle.
			# Block lengths 1..4 frames reproduce the measured busy=2/5..5/5.
			var block := frame / 10
			var within_block := frame % 10
			var idle_count := 1 + block % 3
			var idle_frame := within_block < 1 + block % 4
			game.residents[i].state = "Idle" if idle_frame and i < idle_count else "Assembling fixture"
		_advance_clock(game, 0.1)
		var current := _text(game)
		if current != last:
			changes += 1
		last = current
	_assert_true(changes <= 3, "T5 Next changes <=3 times across 25 sim seconds of job-boundary jitter (observed %d)" % changes)
	_assert_true("begin reclamation" not in last, "T5 funded Bunks/Air do not request reclamation")
	print("Next flicker count: %d changes / 250 frames / 25.0 sim seconds" % changes)
	_dispose(game)


# Spec D uses the same carved/powered fixture as T1-T5, with the opening's
# missing food producers and its real stored meals. No forecast is mocked.
func _starving_opening(level := 5) -> VaultGame:
	var game := _wing(level)
	for building: VaultBuilding in game.buildings.duplicate():
		if building.kind in [VaultBuilding.Kind.KITCHEN, VaultBuilding.Kind.GROW_TRAY]:
			game.buildings.erase(building)
			building.free()
	var food := [65.0, 72.0, 79.0, 86.0, 72.0]
	for i in range(game.residents.size()):
		game.residents[i].needs.food = food[i]
	game.food_system.meals = 12
	game.food_system.raw_food = 0
	game.food_system.salvage = 30
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	return game


func _food_death(game: VaultGame, resident: VaultResident) -> float:
	return float(game.player_orders._food_depletion_times()[resident.resident_id]) + resident.needs.health / (160.0 / DayCycle.SECONDS_PER_DAY)


# Call with no stored meals, or a drafted resident who cannot eat them. Set
# actual needs rather than injecting projected times into the urgency selector.
func _set_food_death(resident: VaultResident, seconds: float) -> void:
	var rate := 60.0 * resident.needs.food_drain_scale / DayCycle.SECONDS_PER_DAY
	resident.needs.food = (seconds - resident.needs.health / (160.0 / DayCycle.SECONDS_PER_DAY)) * rate
	_assert_true(resident.needs.food >= 0.0 and resident.needs.food <= 100.0, "D fixture expresses %.1f seconds through valid food needs" % seconds)


func _assert_no_starving(game: VaultGame, message: String) -> void:
	game.player_orders.refresh()
	var urgent: Dictionary = game.player_orders._resident_urgency_step()
	var next := _next(game)
	_assert_false("starving" in str(urgent.get("text", "")).to_lower(), message + " has no starving urgency")
	_assert_false("starving" in str(next.get("text", "")).to_lower(), message + " has no starving Next")
	_assert_equal(_sticky_id(game), -1, message + " names nobody")


# The food steps stay on the forecast; only the NAME waits for a real runway.
func _assert_unnamed_food(game: VaultGame, message: String) -> void:
	_assert_no_starving(game, message)
	var urgent: Dictionary = game.player_orders._resident_urgency_step()
	var text := str(urgent.get("text", ""))
	_assert_true(text.begins_with("Next: food runway short · YOU "), message + " shows the unnamed food step: " + text)
	_assert_equal(str(urgent.get("cause", "")), "food", message + " keeps the food cause")
	_assert_true(bool(urgent.get("urgent", false)), message + " keeps the food urgency")
	_assert_true(bool(urgent.get("food_unnamed", false)), message + " flags the step unnamed")
	_assert_true(int(urgent.get("resident_id", -1)) >= 0, message + " keeps a resident id for urgency handling")
	var next_text := str(_next(game).get("text", ""))
	_assert_true(next_text.begins_with("Next: food runway short · YOU "), message + " reaches the public Next unnamed: " + next_text)


func _assert_no_food_cause(game: VaultGame, message: String) -> void:
	game.player_orders.refresh()
	_assert_false("starving" in str(game.player_orders._resident_urgency_step().get("text", "")), message + " shows no starving label in the urgent step")
	_assert_false("starving" in _text(game), message + " shows no starving label in Next")
	_assert_true(str(game.player_orders._resident_urgency_step().get("cause", "")) != "food", message + " has no forecast food cause")
	_assert_true(str(_next(game).get("cause", "")) != "food", message + " leaves Next without food danger metadata")


func _assert_starving_name(game: VaultGame, resident: VaultResident, message: String) -> Dictionary:
	var urgent: Dictionary = game.player_orders._resident_urgency_step()
	_assert_true("Next: %s starving ·" % resident.resident_name in str(urgent.get("text", "")), message + " names " + resident.resident_name)
	_assert_equal(str(urgent.get("cause", "")), "food", message + " keeps the food cause")
	_assert_true(bool(urgent.get("urgent", false)), message + " is urgent")
	_assert_equal(int(urgent.get("resident_id", -1)), resident.resident_id, message + " exposes the named resident id")
	_assert_equal(_sticky_id(game), resident.resident_id, message + " remembers the selected resident")
	_assert_true(_food_death(game, resident) < 60.0, message + " names a resident below the real 60-second threshold")
	_assert_approximately(float(urgent.get("death_seconds", INF)), _food_death(game, resident), 0.00001, message + " reports the selected resident's own runway")
	_assert_equal(int(_next(game).get("resident_id", -1)), resident.resident_id, message + " reaches the public Next selector")
	return urgent


# Read by name so the control run on a tree without this API fails assertions instead of script errors.
func _sticky_id(game: VaultGame) -> Variant:
	return game.player_orders.get("_starving_resident_id")


func _orders_const(game: VaultGame, const_name: String) -> Variant:
	return game.player_orders.get_script().get_script_constant_map().get(const_name)


func _test_starving_runway() -> void:
	var game := _starving_opening()
	_assert_equal(game.residents.size(), 4, "D1 05 opening has the real four-resident crew")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.KITCHEN), 0, "D1 opening has no Nutrient Station")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.GROW_TRAY), 0, "D1 opening has no Grow Tray")
	_assert_equal(_orders_const(game, "STARVING_RUNWAY_S"), 60.0, "D1 starving uses the named 60-second runway constant")
	_assert_equal(_orders_const(game, "STARVING_SWITCH_S"), 10.0, "D1 sticky selection uses the named ten-second switch constant")
	var checkpoints := [[2.4, 30], [4.7, 17], [9.4, 8]]
	# Full pantry: no forecast at all, so Next shows no food cause and no name.
	for checkpoint: Array in checkpoints:
		game.day_cycle.elapsed_seconds = float(checkpoint[0])
		game.food_system.salvage = int(checkpoint[1])
		_assert_equal(game.food_system.meals, 12, "D1 lead jitter keeps all twelve stored meals")
		_assert_no_food_cause(game, "D1 %.1fs salvage %d full pantry" % [checkpoint[0], checkpoint[1]])
	# Three stored meals: the forecast fires while every resident is still fed.
	# The food steps stay (unnamed) at every lead value; nobody is named.
	game.food_system.meals = 3
	for checkpoint: Array in checkpoints:
		game.day_cycle.elapsed_seconds = float(checkpoint[0])
		game.food_system.salvage = int(checkpoint[1])
		for resident: VaultResident in game.residents:
			_assert_true(resident.needs.food >= 65.0 and resident.needs.food <= 86.0 and _food_death(game, resident) >= 60.0, "D1 %.1fs keeps %s fed and above the runway threshold" % [checkpoint[0], resident.resident_name])
		_assert_unnamed_food(game, "D1 %.1fs salvage %d lead jitter" % [checkpoint[0], checkpoint[1]])
	game.food_system.meals = 3
	var ari: VaultResident = game.residents[0]
	ari.drafted = true
	for seconds: float in [61.0, 60.0, 59.0]:
		_set_food_death(ari, seconds)
		_assert_approximately(_food_death(game, ari), seconds, 0.00001, "D1 boundary fixture has exactly %.1f seconds of real runway" % seconds)
		var plan: Dictionary = game.player_orders._food_fix_plan()
		var lead: float = float(plan.seconds) + game.player_orders._food_chain_work_lead(float(plan.seconds))
		_assert_true(game.player_orders._food_runway_seconds() < lead + game.player_orders.FOOD_RUNWAY_MARGIN_SECONDS, "D1 %.1f-second boundary retains forecast food danger" % seconds)
		if seconds >= 60.0:
			_assert_unnamed_food(game, "D1 %.1f-second boundary" % seconds)
		else:
			_assert_starving_name(game, ari, "D1 59-second boundary")
	game.food_system.meals = 100
	var calm_plan: Dictionary = game.player_orders._food_fix_plan()
	var calm_lead: float = float(calm_plan.seconds) + game.player_orders._food_chain_work_lead(float(calm_plan.seconds))
	_assert_true(_food_death(game, ari) < 60.0 and ari.needs.food > 20.0, "D1 stocked-pantry conjunction fixture retains a short personal runway without real-hunger relabeling")
	_assert_false(game.player_orders._food_runway_seconds() < calm_lead + game.player_orders.FOOD_RUNWAY_MARGIN_SECONDS, "D1 stocked pantry removes forecast food danger")
	_assert_no_food_cause(game, "D1 personal runway below sixty without forecast danger")
	# A food forecast without anyone below sixty must still yield to a real
	# non-food emergency through the existing threatened-resident branch.
	ari.drafted = false
	ari.needs.food = 65.0
	game.food_system.meals = 3
	var bo: VaultResident = game.residents[1]
	bo.drafted = true
	bo.needs.food = 100.0
	bo.needs.health = 20.0
	bo.needs.rest = 0.0
	var danger_plan: Dictionary = game.player_orders._food_fix_plan()
	var danger_lead: float = float(danger_plan.seconds) + game.player_orders._food_chain_work_lead(float(danger_plan.seconds))
	_assert_true(game.player_orders._food_runway_seconds() < danger_lead + game.player_orders.FOOD_RUNWAY_MARGIN_SECONDS, "D1 exhausted-resident fallthrough keeps forecast food danger true")
	for resident: VaultResident in game.residents:
		_assert_true(_food_death(game, resident) >= 60.0, "D1 exhausted-resident fallthrough keeps %s above the food threshold" % resident.resident_name)
	_assert_no_starving(game, "D1 food forecast falls through to genuine exhaustion")
	var exhausted: Dictionary = game.player_orders._resident_urgency_step()
	_assert_equal(str(exhausted.get("cause", "")), "rest", "D1 forecast food danger preserves the rest cause")
	_assert_equal(int(exhausted.get("resident_id", -1)), bo.resident_id, "D1 fallthrough retains exhausted Bo's id")
	_assert_true(bool(exhausted.get("urgent", false)), "D1 fallthrough retains the existing urgent flag")
	_assert_equal(str(exhausted.get("text", "")), "Next: Bo exhausted · YOU undraft Bo [R] · THEY rest", "D1 fallthrough preserves the existing exhaustion action and label")
	_dispose(game)


func _test_starving_sticky_name() -> void:
	var game := _starving_opening()
	game.food_system.meals = 3
	_assert_unnamed_food(game, "D2 every resident starts above the threshold")
	_assert_equal(_sticky_id(game), -1, "D2 healthy crew names nobody")
	game.food_system.meals = 0
	var ari: VaultResident = game.residents[0]
	var bo: VaultResident = game.residents[1]
	_set_food_death(ari, 50.0)
	_set_food_death(bo, 54.0)
	_assert_starving_name(game, ari, "D2 initial shortest runway")
	for gap: float in [0.5, 4.0, 9.9]:
		var before := game.day_cycle.elapsed_seconds
		game.step_simulation(1.0)
		_assert_approximately(game.day_cycle.elapsed_seconds, before + 1.0, 0.00001, "D2 advances one real simulation second")
		_set_food_death(bo, _food_death(game, ari) - gap)
		_assert_true(_food_death(game, bo) < _food_death(game, ari), "D2 Bo becomes the shorter runway by %.1f seconds" % gap)
		var first := _assert_starving_name(game, ari, "D2 %.1f-second rank jitter" % gap)
		for _repeat in range(6):
			_assert_equal(game.player_orders._resident_urgency_step(), first, "D2 repeated unchanged-state urgency calls are deterministic at gap %.1f" % gap)
			_assert_equal(int(_next(game).get("resident_id", -1)), ari.resident_id, "D2 repeated public getters keep Ari at gap %.1f" % gap)
	_dispose(game)


func _test_starving_switch() -> void:
	for gap: float in [10.0, 10.1]:
		var game := _starving_opening()
		game.food_system.meals = 0
		var ari: VaultResident = game.residents[0]
		var bo: VaultResident = game.residents[1]
		_set_food_death(ari, 50.0)
		_set_food_death(bo, 54.0)
		_assert_starving_name(game, ari, "D3 initial sticky name")
		_set_food_death(bo, 50.0 - gap)
		_assert_starving_name(game, bo, "D3 %.1f-second shorter runway switches immediately" % gap)
		_set_food_death(ari, _food_death(game, bo) - 9.9)
		_assert_starving_name(game, bo, "D3 old name cannot return with only a 9.9-second lead")
		_set_food_death(ari, _food_death(game, bo) - 10.1)
		_assert_starving_name(game, ari, "D3 old name returns after becoming over ten seconds shorter")
		ari.needs.eat()
		_assert_true(_food_death(game, ari) >= 60.0, "D3 eating takes the sticky resident beyond the threshold")
		_assert_starving_name(game, bo, "D3 feeding the sticky resident moves the name to the remaining hungry crew")
		bo.needs.eat()
		_assert_no_starving(game, "D3 everybody is above the threshold after eating")
		_assert_equal(_sticky_id(game), -1, "D3 no residents under the threshold clears the sticky id")
		_set_food_death(ari, 50.0)
		_set_food_death(bo, 54.0)
		_assert_starving_name(game, ari, "D3 a new hungry span selects the shortest runway again")
		ari.alive = false
		_assert_starving_name(game, bo, "D3 a dead sticky resident yields to living crew")
		_dispose(game)
	_test_starving_game_reset()


func _test_starving_game_reset() -> void:
	var game := _starving_opening()
	# Save a healthy state using the real seal transition required by snapshot
	# validation, then establish a sticky name without changing simulation time.
	game.breach_system.reset()
	game.day_cycle.elapsed_seconds = game.breach_system.warning_at
	game.breach_system.advance(0.0, game.day_cycle.elapsed_seconds)
	var delivered := game.breach_system.add_delivery(BreachSystem.PATCH_COST)
	var sealed := game.breach_system.apply_patch_work(BreachSystem.PATCH_WORK_SECONDS)
	_assert_true(delivered == BreachSystem.PATCH_COST and sealed, "D3 reset fixture seals through the real hatch API")
	game.player_orders.show_breach_warning(false)
	game.job_system.rebuild_from_state()
	game.day_cycle.current_day = floori(game.day_cycle.elapsed_seconds / DayCycle.SECONDS_PER_DAY) + 1
	var snapshot := game.create_snapshot()
	game.food_system.meals = 0
	_set_food_death(game.residents[0], 50.0)
	_assert_starving_name(game, game.residents[0], "D3 load fixture has a live sticky name")
	_assert_true(game.apply_snapshot(snapshot), "D3 real loader accepts the healthy same-clock snapshot")
	_assert_equal(_sticky_id(game), -1, "D3 loading clears the previous crew's sticky id before another getter")
	_assert_no_starving(game, "D3 restored healthy snapshot")
	game.food_system.meals = 0
	_set_food_death(game.residents[0], 50.0)
	_assert_starving_name(game, game.residents[0], "D3 new-game fixture has a live sticky name")
	game.new_game(false, 4242, 5)
	_assert_equal(_sticky_id(game), -1, "D3 new game clears the previous crew's sticky id")
	_dispose(game)


func _test_starving_opening_jitter() -> void:
	for level: int in [3, 5]:
		var game := _starving_opening(level)
		_assert_equal(game.residents.size(), 5 if level == 3 else 4, "D4 %02d opening uses its real crew count" % level)
		game.food_system.meals = 3
		for salvage: int in [30, 17, 8, 20, 30, 8, 17, 20]:
			game.food_system.salvage = salvage
			_advance_clock(game, 0.7)
			_assert_equal(game.food_system.meals, 3, "D4 %02d lead jitter leaves pantry stock constant" % level)
			_assert_unnamed_food(game, "D4 %02d opening salvage %d" % [level, salvage])
			_assert_equal(_sticky_id(game), -1, "D4 %02d opening never retains a forecast resident name" % level)
		_dispose(game)


func _test_unnamed_over_breach() -> void:
	for level: int in [3, 5]:
		var game := _starving_opening(level)
		game.food_system.meals = 3
		game.breach_system.reset()
		game.day_cycle.elapsed_seconds = game.breach_system.warning_at
		game.breach_system.advance(0.0, game.day_cycle.elapsed_seconds)
		for resident: VaultResident in game.residents:
			resident.drafted = true
		game.player_orders.refresh()
		var blocker: Dictionary = game.player_orders._breach_blocker_step()
		_assert_false(blocker.is_empty(), "D5 %02d drafted crew leave a hatch blocker step" % level)
		var step := _next(game)
		var text := str(step.get("text", ""))
		_assert_false("food runway short" in text, "D5 %02d hatch blocker step is not prefixed as a food step (%s)" % [level, text])
		_assert_true("undraft crew" in text or "acknowledge warning" in text, "D5 %02d hatch blocker step still leads (%s)" % [level, text])
		_assert_false("starving" in text, "D5 %02d blocker step names nobody" % level)
		_assert_equal(str(step.get("cause", "")), "food", "D5 %02d blocker step keeps the food cause" % level)
		_assert_true(bool(step.get("food_unnamed", false)), "D5 %02d blocker step is flagged unnamed" % level)
		_assert_equal(_sticky_id(game), -1, "D5 %02d blocker step retains no name" % level)
		_dispose(game)


func _raw_forecast(game: VaultGame) -> bool:
	var plan: Dictionary = game.player_orders._food_fix_plan()
	var lead: float = float(plan.seconds) + game.player_orders._food_chain_work_lead(float(plan.seconds))
	return game.player_orders._food_runway_seconds() < lead + game.player_orders.FOOD_RUNWAY_MARGIN_SECONDS


func _food_cause(game: VaultGame) -> String:
	return str(game.player_orders._resident_urgency_step().get("cause", ""))


func _test_forecast_onset() -> void:
	var onsets := 0
	for level: int in [3, 5]:
		for meals: int in [3, 4, 5, 6, 8, 12]:
			for salvage: int in [30, 17, 8]:
				var game := _starving_opening(level)
				game.food_system.meals = meals
				game.food_system.salvage = salvage
				var raw := _raw_forecast(game)
				onsets += 1 if raw else 0
				_assert_equal(_food_cause(game) == "food", raw, "D6 %02d meals %d salvage %d first observation matches the unheld trigger" % [level, meals, salvage])
				_dispose(game)
	_assert_true(onsets > 6, "D6 the grid exercises both sides of the trigger")


func _test_forecast_hold() -> void:
	var game := _starving_opening(5)
	game.food_system.meals = 5
	game.food_system.salvage = 8
	_assert_true(_raw_forecast(game), "D7 salvage 8 starts the forecast")
	_assert_equal(_food_cause(game), "food", "D7 onset shows the forecast")
	# Lead jitter that drops below the trigger must not flip the step off.
	var flips := 0
	var was_on := true
	for salvage: int in [30, 17, 30, 8, 17, 30, 20, 8, 30]:
		game.food_system.salvage = salvage
		_advance_clock(game, 0.5)
		var on := _food_cause(game) == "food"
		flips += 1 if was_on and not on else 0
		was_on = on
	_assert_equal(flips, 0, "D7 no on-off flip through 4.5 seconds of lead jitter")
	# Salvage 30 gives runway 50 against trigger 37.5: below trigger + 15, so it
	# still holds long after the minimum hold.
	game.food_system.salvage = 30
	_advance_clock(game, 20.0)
	_assert_false(_raw_forecast(game), "D7 runway has cleared the trigger itself")
	_assert_equal(_food_cause(game), "food", "D7 holds while the runway is inside trigger plus fifteen")
	# Clearing trigger + 15 releases it.
	game.food_system.meals = 6
	_assert_equal(_food_cause(game), "", "D7 releases once the runway clears the trigger by fifteen seconds")
	# A new onset after release starts a fresh hold with its own minimum.
	game.food_system.meals = 5
	game.food_system.salvage = 8
	_advance_clock(game, 0.1)
	_assert_equal(_food_cause(game), "food", "D7 a second onset fires at the unheld trigger")
	game.food_system.meals = 12
	_advance_clock(game, 2.0)
	_assert_equal(_food_cause(game), "food", "D7 minimum hold keeps a fully cleared runway on for five seconds")
	_advance_clock(game, 3.5)
	_assert_equal(_food_cause(game), "", "D7 releases after the minimum hold once the runway clears by fifteen")
	_dispose(game)


func _test_forecast_named_override() -> void:
	var game := _starving_opening(5)
	game.food_system.meals = 5
	game.food_system.salvage = 8
	_assert_equal(_food_cause(game), "food", "D8 hold starts on the forecast")
	# Everyone gets a stocked pantry, but one resident sits inside their own 60 s runway.
	game.food_system.meals = 100
	game.food_system.salvage = 30
	var ari: VaultResident = game.residents[0]
	ari.drafted = true
	_set_food_death(ari, 40.0)
	_assert_true(_food_death(game, ari) < 60.0, "D8 a drafted resident cannot eat and sits under sixty seconds")
	_advance_clock(game, 0.2)
	_assert_false(_raw_forecast(game), "D8 the unheld forecast is off with a stocked pantry")
	_assert_false(_food_cause(game) == "food", "D8 a named death does not extend the hold past the unheld trigger")
	# With the forecast truly on, the named death names that resident.
	game.food_system.meals = 3
	_assert_true(_raw_forecast(game), "D8 forecast is back on")
	_assert_starving_name(game, ari, "D8 under-sixty death overrides the unnamed hold")
	_dispose(game)


func _test_prefix_food_chain_only() -> void:
	var game := _starving_opening(5)
	var orders = game.player_orders
	_assert_true(orders.has_method("_is_food_chain_step"), "D9 the food-chain step predicate exists")
	if orders.has_method("_is_food_chain_step"):
		for text: String in ["Next: YOU place a Nutrient Station · THEY cook", "Next: YOU place Grow Tray · THEY haul output", "Next: YOU begin reclamation · +18 · THEY fund the Nutrient Station", "Next: YOU undraft Ari [R] · THEY eat/work", "Next: YOU leave Cook on · THEY make meals"]:
			_assert_true(orders._is_food_chain_step({"text": text}), "D9 prefixes food-chain step: " + text)
		for text: String in ["Next: YOU place a Rec Console · THEY recover mood", "Next: YOU leave Haul + Craft on · THEY finish the Rec Console", "Next: YOU acknowledge warning · then undraft crew [R]", "Next: YOU place Air Recycler · THEY craft it", "Next: YOU place bunks · THEY craft"]:
			_assert_false(orders._is_food_chain_step({"text": text}), "D9 never prefixes: " + text)
		_assert_false(orders._is_food_chain_step({"text": "Next: YOU place a Rec Console · THEY recover mood", "kind": "food", "tool": "rec"}), "D9 a food-kinded Rec blocker step is not a food-chain step")
	_dispose(game)


const BUNK_ONE := {"text": "Next: YOU place 1 bunk · THEY craft from Craft", "help": "Place BUNK blueprints on carved floor. Undrafted Craft priority finishes them.", "tool": "bed"}
const BUNK_TWO := {"text": "Next: YOU place 2 bunks · THEY craft from Craft", "help": "Place BUNK blueprints on carved floor. Undrafted Craft priority finishes them.", "tool": "bed"}
const BUNK_CRISIS := {"text": "Next: YOU place bunks · THEY craft", "help": "Place bunks so tired undrafted crew have a bed.", "tool": "bed"}
const REC_BLOCKER := {"text": "Next: YOU place a Rec Console · THEY recover mood", "tool": "rec", "kind": "food", "urgent": true, "cause": "food", "resident_id": 1, "food_unnamed": true}
const GENERATOR_STEP := {"text": "Next: YOU mark rock [E] · THEY dig on Dig defaults", "tool": "dig"}


# Bare clock advance: refresh() would feed the live step through the presentation latch.
func _tick(game: VaultGame, seconds: float) -> void:
	game.day_cycle.elapsed_seconds += seconds


func _test_bunk_text_stable() -> void:
	var game := _nudge_wing()
	game.player_orders.clear_survival_tips()
	var first := str(_present(game, BUNK_TWO).get("text", ""))
	_assert_equal(first, BUNK_TWO.text, "D10 the first bunk wording is shown as built")
	for variant: Dictionary in [BUNK_ONE, BUNK_CRISIS, BUNK_TWO, BUNK_CRISIS, BUNK_ONE]:
		_tick(game, 3.0)
		var shown := _present(game, variant)
		_assert_equal(str(shown.get("text", "")), BUNK_TWO.text, "D10 a count or tier change alone keeps the text (%s)" % variant.text)
		_assert_equal(str(shown.get("help", "")), str(BUNK_TWO.help), "D10 the help stays with the held text")
		_assert_equal(str(shown.get("tool", "")), "bed", "D10 the tool is unchanged")
	# A different step kind ends the latch, and a later bunk step starts a fresh one.
	_tick(game, 3.0)
	_assert_equal(str(_present(game, GENERATOR_STEP).get("text", "")), GENERATOR_STEP.text, "D10 a different step kind is shown as built")
	_tick(game, 3.0)
	_assert_equal(str(_present(game, BUNK_ONE).get("text", "")), BUNK_ONE.text, "D10 after leaving the bunk step a new bunk step starts fresh")
	# The latch holds whichever wording came first, including the singular one.
	game.player_orders.clear_survival_tips()
	_present(game, BUNK_ONE)
	for variant: Dictionary in [BUNK_TWO, BUNK_CRISIS, BUNK_ONE]:
		_tick(game, 3.0)
		_assert_equal(str(_present(game, variant).get("text", "")), BUNK_ONE.text, "D10 a first singular wording is held too (%s)" % variant.text)
	# An urgent bunk step is a different step even when its wording matches.
	var urgent_bunk := BUNK_CRISIS.duplicate(true)
	urgent_bunk["urgent"] = true
	game.player_orders.clear_survival_tips()
	_present(game, BUNK_TWO)
	_tick(game, 3.0)
	_assert_equal(str(_present(game, urgent_bunk).get("text", "")), BUNK_CRISIS.text, "D10 an urgent bunk step is never rewritten to the held text")
	game.player_orders.clear_survival_tips()
	_present(game, BUNK_TWO)
	# An urgent, named bunk step is a different step and is never rewritten.
	var named := {"text": "Next: Ari exhausted · YOU place bunks · THEY craft", "tool": "bed", "urgent": true, "resident_id": 1}
	_tick(game, 3.0)
	_assert_equal(str(_present(game, named).get("text", "")), named.text, "D10 an urgent named bunk step keeps its own text")
	_dispose(game)


func _test_rec_blocker_hold() -> void:
	var game := _nudge_wing()
	game.player_orders.clear_survival_tips()
	_tick(game, 1.0)
	_present(game, BUNK_TWO)
	_tick(game, 0.5)
	var held := _present(game, REC_BLOCKER)
	_assert_equal(str(held.get("text", "")), BUNK_TWO.text, "D11 the Rec blocker does not interject 0.5 s into a bunk step")
	_assert_false(bool(held.get("urgent", false)), "D11 the held bunk step is not urgent")
	_tick(game, 1.4)
	_assert_equal(str(_present(game, REC_BLOCKER).get("text", "")), BUNK_TWO.text, "D11 the hold still covers 1.9 s")
	_tick(game, 0.1)
	var shown := _present(game, REC_BLOCKER)
	_assert_equal(str(shown.get("text", "")), REC_BLOCKER.text, "D11 the Rec blocker shows once the 2 s hold has expired")
	_assert_true(bool(shown.get("urgent", false)) and str(shown.get("cause", "")) == "food", "D11 the released blocker keeps its urgent food flags")
	# A blocker over a non-bunk step is not delayed.
	game.player_orders.clear_survival_tips()
	_present(game, GENERATOR_STEP)
	_tick(game, 0.5)
	_assert_equal(str(_present(game, REC_BLOCKER).get("text", "")), REC_BLOCKER.text, "D11 the hold applies only over a bunk step")
	# A blocker without the unnamed food flag is another step and is not held.
	game.player_orders.clear_survival_tips()
	_present(game, BUNK_TWO)
	_tick(game, 0.5)
	var plain := REC_BLOCKER.duplicate(true)
	plain.erase("food_unnamed")
	_assert_equal(str(_present(game, plain).get("text", "")), REC_BLOCKER.text, "D11 only the unnamed food blocker waits")
	_dispose(game)
