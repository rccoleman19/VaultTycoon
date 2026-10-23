extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TICK := VaultGame.SIMULATION_TICK
const EPSILON := 0.000001
const CHARGE_FOR_REC := "Next: YOU place a Charge Node · THEY power the Rec Console"
const CHARGE_FOR_REC_HELP := "The grid lacks available power for the Rec Console. Place a Charge Node to add 7 power."
const DAY_SEVEN := "Next: YOU designate needs · THEY hold Day 7"
const DAY_SEVEN_HELP := "Keep designating dig/build/stockpile. Defaults keep food, power, and air running."
const ENABLE_REC := "Next: YOU enable a Rec Console · THEY recover mood"
const ENABLE_REC_HELP := "Select a completed Rec Console and click ENABLE so crew can recover mood."
const FINISH_CHARGE := "Next: YOU leave Haul + Craft on · THEY finish the Charge Node"
const FINISH_CHARGE_HELP := "Keep Haul + Craft above OFF so crew supply and finish the Charge Node blueprint."

var _case_count := 0
var _assertion_count := 0
var _failure_count := 0
var _current_case := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_run_case("wired hold with dark hungry tired low-O2 control", _test_wired_hold)
	for lit in [false, true]:
		for hungry in [false, true]:
			for tired in [false, true]:
				_run_case("matrix lit=%s hungry=%s tired=%s" % [lit, hungry, tired], _test_matrix.bind(lit, hungry, tired))
	_run_case("loop regression: dark hungry recovery lasts at least ten seconds", _test_loop)
	_run_case("drafting mid-break clears without reward and resumes drain", _test_draft)
	_run_case("drafted stale break timer grants no hold", _test_stale_draft)
	_run_case("breach response clears without reward and resumes drain", _test_breach)
	_run_case("medical admission clears without reward", _test_medical)
	_run_case("sleep still holds mood", _test_sleep)
	_run_case("active Rec still restores eighteen per second to eighty-five", _test_recreation)
	_run_case("severe mood health loss remains during venting", _test_severe_health)
	_run_case("save-load with three seconds remaining holds and rewards once", _test_save_load)
	_run_case("inspector exact rounded break line and normal factors afterward", _test_inspector)
	_run_case("echo mood thirty-five uses exact Charge tuple", _test_echo_threshold)
	_run_case("echo above thirty-five returns exact Day-7 tuple", _test_echo_above)
	_run_case("echo mood nine preserves high branch", _test_echo_high)
	_run_case("echo ignores the only low-mood resident when dead", _test_echo_dead)
	_run_case("echo includes drafted low-mood resident", _test_echo_drafted)
	_run_case("echo all Recs disabled returns enable tuple", _test_echo_disabled)
	_run_case("short Charge fund fallback outranks echo", _test_echo_short)
	_run_case("echo funded undelivered Charge uses finish tuple", _test_echo_funded)
	_run_case("powered Rec returns Day-7 tuple", _test_echo_powered)
	_run_case("medical crisis outranks echo", _test_echo_injured)
	_run_case("bunk crisis outranks echo", _test_echo_bunks)
	_run_case("echo refresh preserves active build tool", _test_echo_refresh)
	print("STRESS BREAK VENTING TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(0 if _failure_count == 0 else 1)


func _run_case(label: String, test: Callable) -> void:
	_case_count += 1
	_current_case = label
	var before := _failure_count
	print("[TEST] %s" % label)
	test.call()
	print("[%s] %s" % ["PASS" if before == _failure_count else "FAIL", label])


func _spawn_game() -> VaultGame:
	var game := MAIN_SCENE.instantiate() as VaultGame
	root.add_child(game)
	game.begin_shift()
	game.user_paused = true
	return game


# Fixtures finish all needs/clock staging before any measured simulation ticks.
# No food production, available bunks or work can interrupt the measured breaks.
func _venting_game(lit := false, hungry := false, tired := false, low_oxygen := false) -> VaultGame:
	var game := _spawn_game()
	game.food_system.meals = 0
	for resident: VaultResident in game.residents:
		resident.needs.food = 30.0 if hungry else 100.0
		resident.needs.rest = 25.0 if tired else 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
		for key in ["dig", "haul", "craft", "cook"]:
			resident.work_allowed[key] = false
		game.job_system.release_resident(resident)
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.LAMP:
			building.manually_disabled = not lit
	game.power_grid.recalculate(game.buildings)
	game.refresh_lighting(true)
	game.oxygen_system.oxygen = 30.0 if low_oxygen else 100.0
	game.residents[0].needs.mood = 9.0
	_assert_equal(game.is_resident_lit(game.residents[0]), lit, "fixture lighting matches case")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.RECREATION_CONSOLE), 0, "fixture has no Rec")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.BED), 0, "fixture has no bunk")
	return game


# Start at exactly nine without a passive-needs tick: this is fixture setup,
# using the real trigger rather than injecting the timer or later mood values.
func _start_at_nine(game: VaultGame) -> VaultResident:
	var resident: VaultResident = game.residents[0]
	game.job_system.advance(0.0)
	_close(resident.needs.mood, 9.0, "fixture break starts at exactly nine")
	_close(resident.stress_break_left, 7.0, "real trigger starts seven-second break")
	return resident


func _finish_break(game: VaultGame, resident: VaultResident, held_mood: float) -> int:
	var ticks := 0
	while resident.stress_break_left > 0.0 and ticks < 72:
		var left_before := resident.stress_break_left
		game.step_simulation(TICK)
		ticks += 1
		_close(resident.stress_break_left, maxf(0.0, left_before - TICK), "timer advances by one fixed tick")
		if resident.stress_break_left > 0.0:
			_close(resident.needs.mood, held_mood, "every active break tick holds mood")
		else:
			_close(resident.needs.mood, held_mood + 16.0, "completion grants exactly sixteen once")
	_close(resident.stress_break_left, 0.0, "break completes inside its bounded duration")
	return ticks


func _test_wired_hold() -> void:
	var game := _venting_game(false, true, true, true)
	var resident: VaultResident = game.residents[0]
	var control: VaultResident = game.residents[1]
	_assert_false(control.drafted, "control is undrafted and awake")
	_assert_false(game.is_resident_lit(control), "control shares dark lighting")
	_close(resident.needs.mood, 9.0, "wired subject initially at trigger threshold")
	game.step_simulation(TICK)
	_close(resident.stress_break_left, 7.0, "first real game tick starts the break")
	var held_mood := resident.needs.mood
	_close(held_mood, 9.0 - 2.4 * TICK, "trigger tick uses unchanged dark hungry tired low-O2 drain")
	_close(control.needs.mood, 100.0 - 2.4 * TICK, "control exact trigger-tick drain")
	var ticks := 0
	while resident.stress_break_left > 0.0 and ticks < 72:
		var control_before := control.needs.mood
		game.step_simulation(TICK)
		ticks += 1
		_close(resident.needs.mood, held_mood + (16.0 if resident.stress_break_left <= 0.0 else 0.0), "subject holds every break tick and gains sixteen only on completion")
		_close(control.needs.mood, control_before - 2.4 * TICK, "same-tick awake control loses exact ninety-six mood/day")
		_assert_true(not control.sleeping and control.stress_break_left == 0.0, "control remains awake outside a break")
		_assert_true(game.oxygen_system.is_low(), "low O2 persists throughout hold")
	_close(resident.stress_break_left, 0.0, "wired break finishes")
	_assert_true(ticks >= 70 and ticks <= 71, "seven seconds complete within one floating-point boundary tick")
	_close(resident.needs.food, 30.0 - (ticks + 1) * TICK * 1.5, "food continues draining during break")
	_close(resident.needs.rest, 25.0 - (ticks + 1) * TICK * 0.85, "rest continues draining during break")
	_close(resident.needs.health, 100.0, "nonsevere mood and noncritical O2 preserve health")
	game.step_simulation(TICK)
	_close(resident.needs.mood, held_mood + 16.0 - 2.4 * TICK, "post-completion tick resumes drain without a second reward")
	game.free()


func _test_matrix(lit: bool, hungry: bool, tired: bool) -> void:
	var game := _venting_game(lit, hungry, tired)
	var resident := _start_at_nine(game)
	var ticks := _finish_break(game, resident, 9.0)
	_assert_true(ticks >= 70 and ticks <= 71, "matrix keeps seven-second duration")
	_close(resident.needs.mood, 25.0, "all eight environments finish at exactly twenty-five")
	var rate := (18.0 + (0.0 if lit else 30.0) + (12.0 if hungry else 0.0) + (12.0 if tired else 0.0)) / 40.0
	game.step_simulation(TICK)
	_close(resident.needs.mood, 25.0 - rate * TICK, "matrix resumes exact normal drain without duplicate reward")
	game.free()


func _test_loop() -> void:
	var game := _venting_game(false, true, false)
	var resident := _start_at_nine(game)
	_finish_break(game, resident, 9.0)
	var mood_after := resident.needs.mood
	var next_break_tick := -1
	for tick in range(1, 112):
		game.step_simulation(TICK)
		if resident.stress_break_left > 0.0:
			next_break_tick = tick
			break
		_assert_true(resident.stress_break_left == 0.0, "every intervening tick remains outside a break")
		_assert_false(resident.sleeping, "loop recovery is awake, not a sleep rescue")
		_close(resident.needs.mood, mood_after - 1.5 * tick * TICK, "intervening ticks drain exactly sixty mood/day")
	_assert_true(next_break_tick >= 100, "loop regression: next break cannot start sooner than ten seconds")
	_assert_equal(next_break_tick, 107, "sixteen mood at 1.5/s retriggers on the 10.7-second tick")
	_close(resident.stress_break_left, 7.0, "next trigger begins a fresh full-duration break")
	game.free()


func _test_draft() -> void:
	var game := _venting_game()
	var resident := _start_at_nine(game)
	game.step_simulation(1.0)
	var before := resident.needs.mood
	_assert_true(game.toggle_resident_draft(resident.resident_id), "real draft command succeeds mid-break")
	_close(resident.stress_break_left, 0.0, "drafting clears timer immediately")
	_close(resident.needs.mood, before, "drafting grants no completion reward")
	game.step_simulation(TICK)
	_close(resident.needs.mood, before - 1.2 * TICK, "drafted resident resumes dark awake drain")
	game.free()


func _test_stale_draft() -> void:
	var game := _venting_game()
	var resident: VaultResident = game.residents[0]
	resident.drafted = true
	resident.stress_break_left = 3.0
	game.step_simulation(TICK)
	_close(resident.needs.mood, 9.0 - 1.2 * TICK, "stale drafted timer cannot pause passive mood loss")
	game.free()


func _test_breach() -> void:
	var game := _venting_game()
	game.day_cycle.elapsed_seconds = BreachSystem.WARNING_AT_SECONDS - 1.0
	var resident := _start_at_nine(game)
	# Cross the actual warning boundary naturally, without changing the clock again.
	for _tick in range(11):
		if game.breach_system.is_response_active():
			break
		game.step_simulation(TICK)
	_assert_true(game.breach_system.is_response_active(), "real simulation triggers warning")
	_close(resident.stress_break_left, 0.0, "warning clears active break")
	_close(resident.needs.mood, 9.0, "breach interruption grants no reward")
	game.step_simulation(TICK)
	_close(resident.needs.mood, 9.0 - 1.2 * TICK, "breach response resumes passive drain")
	_close(resident.stress_break_left, 0.0, "response suppresses a new break")
	game.free()


func _test_medical() -> void:
	var game := _venting_game()
	var resident: VaultResident = game.residents[0]
	resident.needs.health = 80.0
	var bed := _add_completed(game, VaultBuilding.Kind.MEDICAL_BED, resident.get_cell(game.map_grid))
	bed.manually_disabled = true
	_start_at_nine(game)
	game.step_simulation(TICK)
	var before := resident.needs.mood
	_assert_true(game.toggle_building_enabled(bed.building_id), "enable medical bed during running break")
	game.step_simulation(TICK)
	_assert_equal(resident.medical_bed_id, bed.building_id, "real survival handler admits resident")
	_close(resident.stress_break_left, 0.0, "medical admission clears break")
	_close(resident.needs.mood, before, "medical admission grants no completion reward")
	_assert_true(resident.needs.health > 80.0, "admitted patient receives care")
	game.free()


func _test_sleep() -> void:
	var game := _venting_game(false, true, true, true)
	var resident: VaultResident = game.residents[0]
	resident.sleeping = true
	game.step_simulation(1.0)
	_close(resident.needs.mood, 9.0, "sleep holds mood under all passive pressures")
	_assert_true(resident.sleeping, "resident remains asleep")
	_close(resident.stress_break_left, 0.0, "sleep does not trigger a stress break")
	game.free()


func _test_recreation() -> void:
	var game := _venting_game()
	var resident: VaultResident = game.residents[0]
	resident.needs.mood = 31.25
	var rec := _add_completed(game, VaultBuilding.Kind.RECREATION_CONSOLE, resident.get_cell(game.map_grid))
	game.power_grid.recalculate(game.buildings)
	game.job_system.advance(0.0)
	_assert_true(rec.powered and game.job_system.is_actively_recreating(resident), "fixture begins active powered Rec")
	for tick in range(1, 31):
		game.step_simulation(TICK)
		_close(resident.needs.mood, minf(85.0, 31.25 + 18.0 * tick * TICK), "active Rec restores exactly eighteen per second")
	_close(resident.needs.mood, 85.0, "session ends at eighty-five")
	_assert_equal(resident.recreation_sessions, 1, "exactly one session completes")
	_assert_false(resident.recreating, "completed session releases resident")
	game.free()


func _test_severe_health() -> void:
	var game := _venting_game()
	var resident: VaultResident = game.residents[0]
	resident.needs.mood = 5.0
	game.job_system.advance(0.0)
	game.step_simulation(1.0)
	_close(resident.needs.mood, 5.0, "severe mood still holds during break")
	_close(resident.needs.health, 99.875, "severe mood still loses five health per day during hold")
	game.free()


func _test_save_load() -> void:
	var game := _venting_game()
	var resident := _start_at_nine(game)
	game.step_simulation(4.0)
	_close(resident.stress_break_left, 3.0, "save taken with exactly three seconds left")
	var snapshot := game.create_snapshot()
	_close(float(snapshot.residents[0].stress_break_left), 3.0, "snapshot retains remaining timer")
	var loaded := _spawn_game()
	_assert_true(loaded.apply_snapshot(snapshot), "three-second-break snapshot loads")
	var restored: VaultResident = loaded.get_resident_by_id(resident.resident_id)
	_close(restored.stress_break_left, 3.0, "load restores three-second timer")
	_close(restored.needs.mood, 9.0, "load restores held mood")
	_finish_break(loaded, restored, 9.0)
	game.step_simulation(3.1)
	_close(restored.needs.mood, resident.needs.mood, "loaded and original completion agree")
	loaded.step_simulation(TICK)
	_close(restored.needs.mood, 25.0 - 1.2 * TICK, "loaded reward occurs once then normal drain resumes")
	loaded.free()
	game.free()


func _test_inspector() -> void:
	var game := _venting_game()
	var resident: VaultResident = game.residents[0]
	resident.stress_break_left = 0.25
	resident.state = "Stress break"
	game.select_resident(resident.resident_id)
	game.player_orders.refresh()
	_assert_equal(game.player_orders.inspector_state.text.get_slice("\n", 3), "Stress break · mood holds · +16 in 1s", "inspector rounds fractional seconds upward and gives exact recovery")
	_finish_break(game, resident, 9.0)
	game.player_orders.refresh()
	_assert_equal(game.player_orders.inspector_state.text.get_slice("\n", 3), "Dark · -48 mood/day", "completed break shows exact normal factor line")
	game.free()


func _add_completed(game: VaultGame, kind: int, cell: Vector2i) -> VaultBuilding:
	var building := VaultBuilding.new()
	game.building_root.add_child(building)
	building.configure(game.next_building_id, kind as VaultBuilding.Kind, cell, true)
	game.next_building_id += 1
	game.buildings.append(building)
	return building


# Local mirror of survival-next's progression/air/_fallback_ready_game chain.
# Clear the staged dig rubble so no other salvage instruction can mask the echo.
func _fallback_ready_game() -> VaultGame:
	var game := _spawn_game()
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
	game.food_system.meals = game.get_alive_count()
	for x in range(17, 29):
		var cell := Vector2i(x, 10)
		_assert_true(game.map_grid.queue_dig(cell), "tail fixture queues connected rock")
		_assert_true(game.map_grid.apply_dig_work(cell, 8.0), "tail fixture carves progression floor")
	_assert_equal(game.map_grid.get_floor_cells().size(), 132, "tail fixture meets opening floor gate")
	_assert_equal(game.job_system.get_uncredited_rubble(), 36, "staged carving creates expected rubble")
	game.job_system.jobs = game.job_system.jobs.filter(func(job: Dictionary) -> bool: return int(job.type) not in [JobSystem.JobType.DIG, JobSystem.JobType.HAUL_RUBBLE])
	_assert_equal(game.job_system.get_uncredited_rubble(), 0, "tail fixture clears all staged rubble")
	_assert_true(game.map_grid.dig_marks.is_empty(), "tail fixture has no pending dig marks")
	_add_completed(game, VaultBuilding.Kind.BED, Vector2i(20, 12))
	_add_completed(game, VaultBuilding.Kind.BED, Vector2i(21, 12))
	_add_completed(game, VaultBuilding.Kind.GENERATOR, Vector2i(22, 12))
	_add_completed(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12))
	_add_completed(game, VaultBuilding.Kind.KITCHEN, Vector2i(24, 12))
	_add_completed(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(25, 12))
	game.breach_system.phase = BreachSystem.Phase.SEALED
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.patch_work_left = 0.0
	game.power_grid.recalculate(game.buildings)
	_assert_true(game.breach_system.is_sealed() and not game.day_cycle.completed, "tail fixture sealed before Day 7 completion")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.BED), 2, "tail fixture meets bunk progression")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.GENERATOR, true), 1, "tail fixture has first built Charge")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.GROW_TRAY), 1, "Grow is powered")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.KITCHEN), 1, "Nutrient is powered")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.AIR_RECYCLER), 1, "Air is powered")
	_assert_step(game, DAY_SEVEN, "select", DAY_SEVEN_HELP)
	return game


func _echo_game(mood: float) -> VaultGame:
	var game := _fallback_ready_game()
	var rec := _add_completed(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(26, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_equal([game.power_grid.supply, game.power_grid.demand, game.power_grid.served], [9, 10, 9], "tail Rec is genuinely shed by power capacity")
	_assert_true(game.power_grid.is_building_shed(rec.building_id) and not rec.powered, "tail Rec is completed but offline")
	for resident: VaultResident in game.residents:
		resident.needs.mood = mood
	return game


func _test_echo_threshold() -> void:
	var game := _echo_game(35.0)
	_assert_step(game, CHARGE_FOR_REC, "generator", CHARGE_FOR_REC_HELP)
	game.free()


func _test_echo_above() -> void:
	var game := _echo_game(35.0001)
	_assert_step(game, DAY_SEVEN, "select", DAY_SEVEN_HELP)
	game.free()


func _test_echo_high() -> void:
	var game := _echo_game(9.0)
	_assert_step(game, CHARGE_FOR_REC, "generator", CHARGE_FOR_REC_HELP)
	game.free()


func _test_echo_dead() -> void:
	var game := _echo_game(100.0)
	game.residents[0].needs.mood = 20.0
	game.residents[0].kill()
	_assert_step(game, DAY_SEVEN, "select", DAY_SEVEN_HELP)
	game.free()


func _test_echo_drafted() -> void:
	var game := _echo_game(100.0)
	game.residents[0].needs.mood = 20.0
	game.residents[0].drafted = true
	_assert_step(game, CHARGE_FOR_REC, "generator", CHARGE_FOR_REC_HELP)
	game.free()


func _test_echo_disabled() -> void:
	var game := _echo_game(20.0)
	game.get_building_at(Vector2i(26, 12)).manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, ENABLE_REC, "select", ENABLE_REC_HELP)
	game.free()


func _test_echo_short() -> void:
	var game := _echo_game(20.0)
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(27, 12)), "short Charge blueprint placed")
	game.food_system.salvage = 0
	_assert_step(game, "Next: YOU mark 6 rock [E] · THEY fund the Charge Node", "dig", "The Charge Node blueprint is 18 salvage short. Each dug rock tile yields 3 salvage once hauled.")
	game.free()


func _test_echo_funded() -> void:
	var game := _echo_game(20.0)
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(27, 12)), "funded Charge blueprint placed")
	var charge: VaultBuilding = game.get_building_at(Vector2i(27, 12))
	game.food_system.salvage = charge.get_cost()
	_assert_true(not charge.complete and charge.delivered == 0, "funded Charge remains completely undelivered")
	_assert_step(game, FINISH_CHARGE, "select", FINISH_CHARGE_HELP)
	game.free()


func _test_echo_powered() -> void:
	var game := _echo_game(20.0)
	_add_completed(game, VaultBuilding.Kind.GENERATOR, Vector2i(27, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_true(game.get_building_at(Vector2i(26, 12)).powered, "additional Charge powers Rec")
	_assert_step(game, DAY_SEVEN, "select", DAY_SEVEN_HELP)
	game.free()


func _test_echo_injured() -> void:
	var game := _echo_game(20.0)
	game.residents[0].needs.health = 95.0
	_assert_step(game, "Next: YOU place a Med Bed · THEY treat", "medical", "Place a Med Bed so the injured can be treated.")
	game.free()


func _test_echo_bunks() -> void:
	var game := _echo_game(20.0)
	for resident: VaultResident in game.residents:
		resident.needs.rest = 25.0
	_assert_step(game, "Next: YOU place bunks · THEY craft", "bed", "Place bunks so tired undrafted crew have a bed.")
	game.free()


func _test_echo_refresh() -> void:
	var game := _echo_game(20.0)
	game.set_tool("bed")
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "bed", "refresh preserves selected build tool")
	_assert_equal(game.player_orders.objective_label.text, CHARGE_FOR_REC, "refresh displays Charge-for-Rec echo")
	_assert_step(game, CHARGE_FOR_REC, "generator", CHARGE_FOR_REC_HELP)
	game.free()


func _assert_step(game: VaultGame, text: String, tool: String, help: String) -> void:
	var step: Dictionary = game.player_orders._primary_next_step()
	_assert_equal(step.get("text"), text, "exact Next text")
	_assert_equal(step.get("tool"), tool, "exact suggested tool")
	_assert_equal(step.get("help"), help, "exact Next help")


func _assert_true(condition: bool, message: String) -> void:
	_assert_equal(condition, true, message)


func _assert_false(condition: bool, message: String) -> void:
	_assert_equal(condition, false, message)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	_assertion_count += 1
	if actual != expected:
		_fail(message, "expected %s, got %s" % [str(expected), str(actual)])


func _close(actual: float, expected: float, message: String) -> void:
	_assertion_count += 1
	if not is_finite(actual) or absf(actual - expected) > EPSILON:
		_fail(message, "expected %.9f, got %.9f" % [expected, actual])


func _fail(message: String, detail: String) -> void:
	_failure_count += 1
	printerr("[FAIL] %s :: %s — %s" % [_current_case, message, detail])
