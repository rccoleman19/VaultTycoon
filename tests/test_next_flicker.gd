extends "res://tests/test_runner.gd"

# Presentation regression controls: all called helpers already exist on 171901b8.
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
