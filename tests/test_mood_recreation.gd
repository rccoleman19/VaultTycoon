extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var _assertion_count := 0
var _failure_count := 0
var _case_count := 0
var _failed_case_count := 0
var _current_case := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_run_case("mood rates, thresholds, and compatibility alias are deterministic", _test_mood_model)
	_run_case("rec console fixture and optional power priority match the contract", _test_console_power_contract)
	_run_case("recreation thresholds and single-console capacity are exact", _test_recreation_thresholds_and_capacity)
	_run_case("recreation requires a powered reachable console and cleans up", _test_recreation_availability_and_cleanup)
	_run_case("recreation selection and death cleanup are deterministic", _test_recreation_selection_and_death_cleanup)
	_run_case("survival needs interrupt recreation and critical mood has a fallback", _test_survival_interruptions_and_fallback)
	_run_case("breach response preempts recreation and stress breaks", _test_breach_preemption)
	_run_case("active and legacy mood recreation snapshots load safely", _test_save_compatibility)
	_run_case("HUD exposes mood tiers and console lifecycle states", _test_hud_contract)

	print("")
	if _failure_count == 0:
		print("MOOD AND RECREATION TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("MOOD AND RECREATION TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
			_failed_case_count,
			_case_count,
			_failure_count,
			_assertion_count,
		])
		quit(1)


func _run_case(case_name: String, test_callable: Callable) -> void:
	_case_count += 1
	_current_case = case_name
	var failures_before := _failure_count
	print("[TEST] %s" % case_name)
	test_callable.call()
	if _failure_count == failures_before:
		print("[PASS] %s" % case_name)
	else:
		_failed_case_count += 1


func _test_mood_model() -> void:
	var one_second := 1.0 / DayCycle.SECONDS_PER_DAY
	_assert_approximately(ResidentNeeds.BASE_MOOD_LOSS_PER_DAY, 18.0, 0.0001, "daily baseline mood loss is eighteen")
	_assert_approximately(ResidentNeeds.DARKNESS_MOOD_LOSS_PER_DAY, 30.0, 0.0001, "darkness adds thirty daily mood loss")
	_assert_approximately(ResidentNeeds.LOW_NEED_MOOD_LOSS_PER_DAY, 12.0, 0.0001, "each low need adds twelve daily mood loss")
	_assert_approximately(ResidentNeeds.LOW_OXYGEN_MOOD_LOSS_PER_DAY, 24.0, 0.0001, "low oxygen adds twenty-four daily mood loss")
	_assert_approximately(ResidentNeeds.RECREATION_RECOVERY_PER_SECOND, 18.0, 0.0001, "recreation restores eighteen mood per second")
	_assert_approximately(ResidentNeeds.RECREATION_SEEK_THRESHOLD, 35.0, 0.0001, "recreation seek threshold is thirty-five")
	_assert_approximately(ResidentNeeds.RECREATION_TARGET, 85.0, 0.0001, "recreation target is eighty-five")

	var needs := ResidentNeeds.new()
	needs.food = 100.0
	needs.rest = 100.0
	needs.mood = 50.0
	needs.advance(one_second, true, false, false)
	_assert_approximately(needs.mood, 49.55, 0.0001, "a lit awake resident loses only baseline mood")

	needs.food = 100.0
	needs.rest = 100.0
	needs.mood = 50.0
	needs.advance(one_second, false, false, false)
	_assert_approximately(needs.mood, 48.8, 0.0001, "darkness stacks with baseline mood loss")

	needs.food = 34.0
	needs.rest = 100.0
	needs.mood = 50.0
	needs.advance(one_second, true, false, false)
	_assert_approximately(needs.mood, 49.25, 0.0001, "hunger adds one low-need mood penalty")

	needs.food = 100.0
	needs.rest = 29.0
	needs.mood = 50.0
	needs.advance(one_second, true, false, false)
	_assert_approximately(needs.mood, 49.25, 0.0001, "fatigue adds one low-need mood penalty")

	needs.food = 34.0
	needs.rest = 29.0
	needs.mood = 50.0
	needs.advance(one_second, false, false, false)
	_assert_approximately(needs.mood, 48.2, 0.0001, "darkness, hunger, fatigue, and baseline strain stack")

	needs.food = 100.0
	needs.rest = 100.0
	needs.mood = 50.0
	needs.advance(one_second, true, false, false, false, true)
	_assert_approximately(needs.mood, 48.95, 0.0001, "low oxygen stacks with awake baseline mood loss")
	_assert_equal(needs.get_mood_factors(true, false, true), "Lit · low O2 · -42 mood/day", "mood factors expose the exact low-oxygen weight")
	needs.food = 34.0
	needs.rest = 29.0
	needs.mood = 50.0
	needs.advance(one_second, false, false, false, false, true)
	_assert_approximately(needs.mood, 47.6, 0.0001, "all five awake mood pressures stack to ninety-six points per day")

	needs.mood = 50.0
	needs.advance(one_second, false, true, true, false, true)
	_assert_approximately(needs.mood, 50.0, 0.0001, "sleep keeps mood stable even in darkness and low oxygen")
	needs.advance(one_second, false, false, false, true, true)
	_assert_approximately(needs.mood, 50.0, 0.0001, "active recreation pauses passive mood loss even in low oxygen")
	needs.recreate(1.0)
	_assert_approximately(needs.mood, 68.0, 0.0001, "one recreation second restores exactly eighteen mood")
	needs.recreate(10.0)
	_assert_approximately(needs.mood, 100.0, 0.0001, "recreation clamps mood at one hundred")
	needs.finish_recreation()
	_assert_approximately(needs.mood, 85.0, 0.0001, "finishing recreation normalizes mood to its exact target")

	needs.mood = 35.0001
	_assert_false(needs.wants_recreation(), "mood just above thirty-five does not seek recreation")
	needs.mood = 35.0
	_assert_true(needs.wants_recreation(), "mood exactly thirty-five seeks recreation")
	needs.mood = 84.9999
	_assert_false(needs.is_recreation_satisfied(), "mood just below eighty-five continues recreation")
	needs.mood = 85.0
	_assert_true(needs.is_recreation_satisfied(), "mood exactly eighty-five completes recreation")

	needs.mood = 70.0
	_assert_equal(needs.get_mood_state(), "STEADY", "mood seventy is steady")
	needs.mood = 69.9999
	_assert_equal(needs.get_mood_state(), "STRAINED", "mood just below seventy is strained")
	needs.mood = 40.0
	_assert_equal(needs.get_mood_state(), "STRAINED", "mood forty remains strained")
	needs.mood = 39.9999
	_assert_equal(needs.get_mood_state(), "STRESSED", "mood just below forty is stressed")
	needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD + 0.0001
	_assert_equal(needs.get_mood_state(), "STRESSED", "mood just above nine remains stressed")
	needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD
	_assert_equal(needs.get_mood_state(), "BREAK RISK", "mood nine enters break risk")

	needs.light_mood = 41.25
	_assert_approximately(needs.mood, 41.25, 0.0001, "legacy light_mood writes through to canonical mood")
	needs.mood = 62.5
	_assert_approximately(needs.light_mood, 62.5, 0.0001, "legacy light_mood reads canonical mood")
	var serialized := needs.serialize()
	_assert_true(serialized.has("mood"), "active needs payload stores canonical mood")
	_assert_false(serialized.has("light_mood"), "active needs payload does not emit the legacy mood key")
	var legacy_needs := ResidentNeeds.new()
	legacy_needs.deserialize({"food": 80.0, "rest": 70.0, "light_mood": 46.5, "health": 90.0})
	_assert_approximately(legacy_needs.mood, 46.5, 0.0001, "legacy light_mood payload restores canonical mood")

	var resident := VaultResident.new()
	resident.needs.food = 100.0
	resident.needs.rest = 100.0
	resident.needs.mood = 30.0
	_assert_approximately(resident.get_work_multiplier(), 1.0, 0.0001, "mood thirty has no work penalty")
	resident.needs.mood = 29.9
	_assert_approximately(resident.get_work_multiplier(), 0.7, 0.0001, "mood below thirty applies the mood work penalty")
	resident.needs.food = 29.0
	resident.needs.rest = 24.0
	_assert_approximately(resident.get_work_multiplier(), 0.35, 0.0001, "combined need penalties respect the minimum work speed")
	resident.free()

	var game := _spawn_game()
	_prepare_residents(game)
	var game_resident: VaultResident = game.residents[0]
	game.oxygen_system.oxygen = OxygenSystem.LOW_OXYGEN_THRESHOLD + 0.0001
	game._simulation_step(VaultGame.SIMULATION_TICK)
	_assert_approximately(game_resident.needs.mood, 99.955, 0.0002, "oxygen just above thirty-five applies baseline mood loss only")
	game_resident.needs.mood = 100.0
	game.oxygen_system.oxygen = OxygenSystem.LOW_OXYGEN_THRESHOLD
	game._simulation_step(VaultGame.SIMULATION_TICK)
	_assert_approximately(game_resident.needs.mood, 99.895, 0.0002, "oxygen exactly thirty-five applies the low-oxygen modifier")
	_dispose(game)


func _test_console_power_contract() -> void:
	var game := _spawn_game()
	_assert_equal(int(VaultBuilding.Kind.RECREATION_CONSOLE), 7, "rec console is appended as saved building kind seven")
	_assert_equal(int(VaultBuilding.PowerPriority.OPTIONAL), 4, "optional power is appended below existing priority tiers")

	var console := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, game.residents[0].get_cell(game.map_grid))
	game.power_grid.recalculate(game.buildings)
	_assert_equal(console.get_display_name(), "Rec Console", "fixture uses the compact display name")
	_assert_equal(console.get_cost(), 8, "rec console costs eight salvage")
	_assert_approximately(console.get_build_time(), 5.0, 0.0001, "rec console takes five work seconds to assemble")
	_assert_equal(console.get_base_power_demand(), 1, "rec console demands one power")
	_assert_equal(console.get_power_priority(), VaultBuilding.PowerPriority.OPTIONAL, "rec console is the least-protected load")
	_assert_equal(console.get_deconstruct_refund(), 4, "rec console deconstruction refunds half its cost")
	_assert_equal(game.power_grid.supply, 2, "starting emergency core still supplies two power")
	_assert_equal(game.power_grid.demand, 2, "starting lumen and console demand two power")
	_assert_equal(game.power_grid.served, 2, "starting grid can serve one console beside the lumen")
	_assert_true(console.powered, "console is usable when its one-power demand is served")

	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(18, 12))
	var recycler := _add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(19, 12))
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	var grow_tray := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(21, 12))
	var lamp: VaultBuilding = game.get_building_at(Vector2i(22, 14))
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.power_grid.supply, 9, "one added charge node raises supply to nine")
	_assert_equal(game.power_grid.demand, 10, "full life support plus recreation demands ten")
	_assert_equal(game.power_grid.served, 9, "allocator serves all protected demand")
	_assert_equal(game.power_grid.shed_demand, 1, "brownout sheds exactly the one-power console")
	_assert_equal(game.power_grid.shed_count, 1, "brownout sheds exactly one fixture")
	_assert_false(console.powered, "optional recreation sheds first")
	_assert_true(game.power_grid.is_building_shed(console.building_id), "shed accounting identifies the rec console")
	_assert_true(recycler.powered and lamp.powered and kitchen.powered and grow_tray.powered, "recreation never displaces life support or food loads")
	var shed_order := game.power_grid.get_shed_order(game.buildings)
	_assert_equal(shed_order[0].building_id, console.building_id, "documented shed order starts with recreation")
	_assert_equal(shed_order[1].building_id, grow_tray.building_id, "grow trays shed after recreation")
	_assert_true(game.power_grid.get_shed_order_text().begins_with("Rec Consoles -> Grow Trays"), "power help documents the new first-shed tier")
	_dispose(game)


func _test_recreation_thresholds_and_capacity() -> void:
	var game := _spawn_game()
	_prepare_residents(game)
	var resident: VaultResident = game.residents[0]
	var second: VaultResident = game.residents[1]
	var console := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, resident.get_cell(game.map_grid))
	game.power_grid.recalculate(game.buildings)

	resident.needs.mood = 35.0001
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_false(resident.recreating, "resident does not claim recreation above the exact seek threshold")
	resident.needs.mood = 35.0
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_true(resident.recreating, "resident claims recreation at the exact seek threshold")
	_assert_equal(resident.recreation_id, console.building_id, "resident stores the claimed console ID")
	_assert_equal(console.reserved_by, resident.resident_id, "console stores its single occupant")
	_assert_equal(resident.current_job_id, -1, "self-directed recreation is not a queued work job")
	_assert_true(game.job_system.is_actively_recreating(resident), "resident already on the console is an active user")

	game._simulation_step(VaultGame.SIMULATION_TICK)
	_assert_approximately(resident.needs.mood, 36.8, 0.0001, "one console tick restores exactly 1.8 mood")
	_assert_equal(resident.state, "Recreating", "resident state exposes active recreation")
	resident.needs.mood = 83.2
	game._simulation_step(VaultGame.SIMULATION_TICK)
	_assert_approximately(resident.needs.mood, 85.0, 0.0001, "recreation finishes at the exact target")
	_assert_false(resident.recreating, "resident leaves after reaching the recreation target")
	_assert_equal(resident.recreation_id, -1, "completed recreation clears the resident fixture reference")
	_assert_equal(console.reserved_by, -1, "completed recreation frees console capacity")
	_assert_equal(resident.recreation_sessions, 1, "completed recreation increments the session count once")

	resident.needs.mood = 35.0
	second.needs.mood = 35.0
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_true(resident.recreating, "first eligible resident claims the only console")
	_assert_false(second.recreating, "a second resident cannot share an occupied console")
	_assert_equal(console.reserved_by, resident.resident_id, "single capacity remains assigned to one resident")
	resident.needs.mood = 85.0
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_false(resident.recreating, "satisfied first resident releases the console")
	_assert_true(second.recreating, "waiting resident claims capacity in the same deterministic pass")
	_assert_equal(console.reserved_by, second.resident_id, "console reservation transfers to the next resident")
	_dispose(game)


func _test_recreation_availability_and_cleanup() -> void:
	var game := _spawn_game()
	_prepare_residents(game)
	var resident: VaultResident = game.residents[0]
	var distant_cell := Vector2i(28, 20)
	var console := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, distant_cell)
	game.power_grid.recalculate(game.buildings)
	resident.needs.mood = 35.0
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_true(resident.recreating, "resident claims a reachable powered console")
	var mood_before_walk := resident.needs.mood
	game._simulation_step(VaultGame.SIMULATION_TICK)
	_assert_true(resident.needs.mood < mood_before_walk, "walking toward recreation keeps ordinary awake mood decay")
	_assert_equal(resident.state, "Seeking recreation", "travel is visible before console use")

	resident.position = game.map_grid.cell_to_world(distant_cell)
	resident.clear_path()
	var mood_at_arrival := resident.needs.mood
	game._simulation_step(VaultGame.SIMULATION_TICK)
	_assert_approximately(resident.needs.mood, mood_at_arrival + 1.8, 0.0001, "mood recovers only after the resident reaches the console")

	var competing_lumen := _add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(18, 12))
	var mood_before_brownout := resident.needs.mood
	game._simulation_step(VaultGame.SIMULATION_TICK)
	_assert_false(console.powered, "optional console sheds when protected lumen demand consumes its power")
	_assert_true(game.power_grid.is_building_shed(console.building_id), "brownout accounting identifies the occupied console")
	_assert_false(resident.recreating, "brownout shedding cancels active recreation immediately")
	_assert_equal(console.reserved_by, -1, "brownout shedding frees console capacity")
	_assert_true(resident.needs.mood < mood_before_brownout, "a shed console grants no recovery")
	_assert_true(game.deconstruct_building(competing_lumen.building_id), "removing competing demand restores console power")
	_assert_true(console.powered, "console powers up after the competing load is removed")
	resident.needs.mood = ResidentNeeds.RECREATION_SEEK_THRESHOLD
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_true(resident.recreating, "resident reclaims recreation after brownout recovery")
	_assert_true(game.toggle_building_enabled(console.building_id), "powered console can be manually disabled")
	_assert_true(console.manually_disabled and not console.powered, "disabled console leaves power allocation")
	_assert_false(resident.recreating, "power loss cancels active recreation immediately")
	_assert_equal(console.reserved_by, -1, "power loss frees console capacity")

	_assert_true(game.toggle_building_enabled(console.building_id), "console can be re-enabled")
	resident.needs.mood = 35.0
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_true(resident.recreating, "low-mood resident can reclaim restored recreation")
	var salvage_before := game.food_system.salvage
	_assert_true(game.deconstruct_building(console.building_id), "occupied console can be deconstructed")
	_assert_false(resident.recreating, "deconstruction clears active recreation")
	_assert_equal(resident.recreation_id, -1, "deconstruction clears the resident console ID")
	_assert_equal(game.food_system.salvage, salvage_before + 4, "deconstruction refunds four salvage")

	var isolated_cell := Vector2i(5, 5)
	game.map_grid.cells[isolated_cell.y * MapGrid.WIDTH + isolated_cell.x] = MapGrid.Tile.FLOOR
	var isolated_console := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, isolated_cell)
	game.power_grid.recalculate(game.buildings)
	resident.needs.mood = 35.0
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_true(isolated_console.powered, "global grid can power a console on disconnected saved floor")
	_assert_false(resident.recreating, "resident does not reserve an unreachable console")
	_assert_equal(isolated_console.reserved_by, -1, "unreachable console remains unreserved")
	_dispose(game)


func _test_recreation_selection_and_death_cleanup() -> void:
	var game := _spawn_game()
	_prepare_residents(game)
	var resident: VaultResident = game.residents[0]
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(18, 13))
	var far_console := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(28, 20))
	var near_console := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(20, 14))
	game.power_grid.recalculate(game.buildings)
	resident.needs.mood = ResidentNeeds.RECREATION_SEEK_THRESHOLD
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_equal(resident.recreation_id, near_console.building_id, "nearest reachable console wins before building ID")
	_assert_equal(near_console.reserved_by, resident.resident_id, "nearest console owns the reservation")
	_assert_equal(far_console.reserved_by, -1, "farther console remains free")

	game.job_system.release_resident(resident)
	near_console.manually_disabled = true
	far_console.manually_disabled = true
	var lower_id_console := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(19, 15))
	var higher_id_console := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(21, 15))
	game.power_grid.recalculate(game.buildings)
	resident.needs.mood = ResidentNeeds.RECREATION_SEEK_THRESHOLD
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_equal(resident.recreation_id, lower_id_console.building_id, "building ID breaks equal path-length ties")
	_assert_equal(lower_id_console.reserved_by, resident.resident_id, "tie winner owns the only resident claim")
	_assert_equal(higher_id_console.reserved_by, -1, "higher-ID equal-distance console remains free")

	resident.kill()
	_assert_false(resident.recreating, "resident death clears active recreation")
	_assert_equal(resident.recreation_id, -1, "resident death clears the console reference")
	_assert_equal(lower_id_console.reserved_by, -1, "resident death immediately frees console capacity")
	_dispose(game)


func _test_survival_interruptions_and_fallback() -> void:
	var game := _spawn_game()
	_prepare_residents(game)
	var resident: VaultResident = game.residents[0]
	var console := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, resident.get_cell(game.map_grid))
	var bed := _add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(19, 12))
	game.power_grid.recalculate(game.buildings)

	resident.needs.mood = ResidentNeeds.RECREATION_SEEK_THRESHOLD
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_true(resident.recreating, "low mood begins recreation before hunger interrupts")
	var meals_before := game.food_system.meals
	resident.needs.food = 35.0
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_false(resident.recreating, "an available meal interrupts recreation")
	_assert_equal(console.reserved_by, -1, "hunger releases console capacity")
	_assert_equal(game.food_system.meals, meals_before - 1, "hunger consumes exactly one shared meal")
	_assert_approximately(resident.needs.food, 95.0, 0.0001, "the interrupted resident eats normally")

	resident.needs.food = 100.0
	resident.needs.rest = 100.0
	resident.needs.mood = ResidentNeeds.RECREATION_SEEK_THRESHOLD
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_true(resident.recreating, "resident can reclaim recreation after eating")
	resident.needs.rest = 28.0
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_false(resident.recreating, "sleep need interrupts recreation")
	_assert_equal(console.reserved_by, -1, "sleep releases console capacity")
	_assert_true(resident.sleeping, "tired resident enters the sleep behavior")
	_assert_equal(resident.bed_id, bed.building_id, "tired resident reserves the available bunk")

	resident.sleeping = false
	resident.bed_id = -1
	resident.needs.rest = 100.0
	resident.needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD
	console.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	game.job_system.reconcile_recreation_state()
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_false(resident.recreating, "critical mood cannot claim a disabled console")
	_assert_approximately(resident.stress_break_left, 7.0, 0.0001, "critical mood begins the seven-second fallback break")
	game.job_system.advance(7.0)
	_assert_approximately(resident.stress_break_left, 0.0, 0.0001, "fallback break ends after seven seconds")
	_assert_approximately(resident.needs.mood, 17.0, 0.0001, "fallback break grants only eight mood")

	var severe_needs := ResidentNeeds.new()
	severe_needs.food = 100.0
	severe_needs.rest = 100.0
	severe_needs.mood = ResidentNeeds.SEVERE_MOOD_THRESHOLD
	severe_needs.health = 100.0
	severe_needs.advance(1.0 / DayCycle.SECONDS_PER_DAY, true, false, false)
	_assert_approximately(severe_needs.health, 99.875, 0.0001, "severe mood retains its bounded daily health consequence")
	_dispose(game)


func _test_breach_preemption() -> void:
	var game := _spawn_game()
	_prepare_residents(game)
	var resident: VaultResident = game.residents[0]
	for worker: VaultResident in game.residents:
		worker.work_allowed.dig = false
		worker.work_allowed.haul = false
		worker.work_allowed.craft = false
		worker.work_allowed.cook = false
	resident.work_allowed.haul = true
	resident.work_allowed.craft = true
	var console := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, resident.get_cell(game.map_grid))
	game.power_grid.recalculate(game.buildings)
	resident.needs.mood = 35.0
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_true(resident.recreating, "resident is recreating before the incident")
	_assert_equal(console.reserved_by, resident.resident_id, "incident test begins with occupied recreation")
	var stressed_resident: VaultResident = game.residents[1]
	stressed_resident.stress_break_left = 3.0
	stressed_resident.state = "Stress break"

	game.breach_system.advance(0.0, BreachSystem.WARNING_AT_SECONDS)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.WARNING, "deterministic hatch warning begins")
	_assert_false(resident.recreating, "warning immediately preempts recreation")
	_assert_equal(console.reserved_by, -1, "warning immediately frees recreation capacity")
	_assert_approximately(stressed_resident.stress_break_left, 0.0, 0.0001, "warning clears an in-progress nonessential stress break")

	resident.needs.mood = 5.0
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_equal(resident.current_job_type, JobSystem.JobType.SUPPLY_BREACH, "urgent salvage response outranks critical low mood")
	_assert_false(resident.recreating, "active breach suppresses new recreation claims")
	_assert_approximately(resident.stress_break_left, 0.0, 0.0001, "active breach suppresses new stress breaks")
	_dispose(game)


func _test_save_compatibility() -> void:
	var original := _spawn_game()
	_prepare_residents(original)
	var resident: VaultResident = original.residents[0]
	var console := _add_completed_building(original, VaultBuilding.Kind.RECREATION_CONSOLE, resident.get_cell(original.map_grid))
	original.power_grid.recalculate(original.buildings)
	resident.needs.mood = 34.0
	original.job_system.advance(VaultGame.SIMULATION_TICK)
	var active_snapshot := original.create_snapshot()
	var saved_resident: Dictionary = active_snapshot.residents[0]
	_assert_approximately(float(saved_resident.needs.mood), 34.0, 0.0001, "active snapshot stores canonical mood")
	_assert_false(saved_resident.needs.has("light_mood"), "active snapshot omits the legacy mood key")
	_assert_true(bool(saved_resident.recreating), "active snapshot stores recreation state")
	_assert_equal(int(saved_resident.recreation_id), console.building_id, "active snapshot stores the console ID")

	var loaded := _spawn_game()
	_assert_true(loaded.apply_snapshot(active_snapshot), "active mood and recreation snapshot loads")
	var loaded_resident: VaultResident = loaded.get_resident_by_id(resident.resident_id)
	var loaded_console: VaultBuilding = loaded.get_building_by_id(console.building_id)
	_assert_approximately(loaded_resident.needs.mood, 34.0, 0.0001, "canonical mood survives load")
	_assert_true(loaded_resident.recreating, "active recreation survives load")
	_assert_equal(loaded_resident.recreation_id, loaded_console.building_id, "loaded resident retains the console reference")
	_assert_equal(loaded_console.reserved_by, loaded_resident.resident_id, "load rebuilds derived single-console occupancy")
	original._simulation_step(0.5)
	loaded._simulation_step(0.5)
	_assert_approximately(loaded_resident.needs.mood, resident.needs.mood, 0.0001, "loaded recreation advances deterministically")

	var legacy_snapshot: Dictionary = active_snapshot.duplicate(true)
	for entry: Dictionary in legacy_snapshot.residents:
		entry.needs.light_mood = entry.needs.mood
		entry.needs.erase("mood")
		entry.erase("recreating")
		entry.erase("recreation_id")
		entry.erase("recreation_sessions")
	_assert_true(loaded.apply_snapshot(legacy_snapshot), "schema-one resident payload without recreation fields loads")
	loaded_resident = loaded.get_resident_by_id(resident.resident_id)
	_assert_approximately(loaded_resident.needs.mood, 34.0, 0.0001, "legacy light_mood restores canonical mood")
	_assert_false(loaded_resident.recreating, "legacy resident defaults to no active recreation")
	_assert_equal(loaded_resident.recreation_id, -1, "legacy resident defaults to no console reference")
	_assert_equal(loaded_resident.recreation_sessions, 0, "legacy resident defaults to zero completed sessions")

	var stable_mood := loaded_resident.needs.mood
	var malformed_mood: Dictionary = legacy_snapshot.duplicate(true)
	malformed_mood.residents[0].needs.light_mood = "strained"
	_assert_false(loaded.apply_snapshot(malformed_mood), "nonnumeric legacy mood is rejected")
	_assert_approximately(loaded.get_resident_by_id(resident.resident_id).needs.mood, stable_mood, 0.0001, "rejected mood payload leaves active state unchanged")
	var malformed_recreation: Dictionary = active_snapshot.duplicate(true)
	malformed_recreation.residents[0].recreating = "sometimes"
	_assert_false(loaded.apply_snapshot(malformed_recreation), "nonboolean recreation state is rejected")
	_assert_approximately(loaded.get_resident_by_id(resident.resident_id).needs.mood, stable_mood, 0.0001, "rejected recreation payload is atomic")
	var malformed_recreation_id: Dictionary = active_snapshot.duplicate(true)
	malformed_recreation_id.residents[0].recreation_id = "console"
	_assert_false(loaded.apply_snapshot(malformed_recreation_id), "nonnumeric recreation fixture ID is rejected")
	var malformed_sessions: Dictionary = active_snapshot.duplicate(true)
	malformed_sessions.residents[0].recreation_sessions = -1
	_assert_false(loaded.apply_snapshot(malformed_sessions), "negative completed recreation count is rejected")
	var dead_recreation: Dictionary = active_snapshot.duplicate(true)
	dead_recreation.residents[0].alive = false
	_assert_false(loaded.apply_snapshot(dead_recreation), "a deceased resident cannot load as actively recreating")
	var sleeping_recreation: Dictionary = active_snapshot.duplicate(true)
	sleeping_recreation.residents[0].sleeping = true
	_assert_false(loaded.apply_snapshot(sleeping_recreation), "a sleeping resident cannot load as actively recreating")

	var stale_snapshot: Dictionary = active_snapshot.duplicate(true)
	stale_snapshot.residents[0].recreation_id = 999
	_assert_true(loaded.apply_snapshot(stale_snapshot), "well-typed stale console reference loads safely")
	loaded_resident = loaded.get_resident_by_id(resident.resident_id)
	_assert_false(loaded_resident.recreating, "stale console reference is canceled during reconciliation")
	_assert_equal(loaded_resident.recreation_id, -1, "stale recreation ID is cleared")

	var duplicate_snapshot: Dictionary = active_snapshot.duplicate(true)
	duplicate_snapshot.residents[1].recreating = true
	duplicate_snapshot.residents[1].recreation_id = console.building_id
	duplicate_snapshot.residents[1].sleeping = false
	_assert_true(loaded.apply_snapshot(duplicate_snapshot), "duplicate well-typed occupancy is reconciled safely")
	var first_loaded := loaded.get_resident_by_id(1) as VaultResident
	var second_loaded := loaded.get_resident_by_id(2) as VaultResident
	loaded_console = loaded.get_building_by_id(console.building_id)
	_assert_true(first_loaded.recreating, "lowest resident ID retains duplicate console claim")
	_assert_false(second_loaded.recreating, "later duplicate console claim is canceled")
	_assert_equal(loaded_console.reserved_by, first_loaded.resident_id, "duplicate occupancy resolves to exactly one resident")

	var satisfied_snapshot: Dictionary = active_snapshot.duplicate(true)
	satisfied_snapshot.residents[0].needs.mood = ResidentNeeds.RECREATION_TARGET
	satisfied_snapshot.residents[0].recreation_sessions = 3
	_assert_true(loaded.apply_snapshot(satisfied_snapshot), "satisfied well-typed recreation claim loads safely")
	first_loaded = loaded.get_resident_by_id(1) as VaultResident
	loaded_console = loaded.get_building_by_id(console.building_id)
	_assert_false(first_loaded.recreating, "satisfied loaded resident releases recreation during reconciliation")
	_assert_equal(first_loaded.recreation_id, -1, "satisfied loaded recreation reference is cleared")
	_assert_equal(first_loaded.recreation_sessions, 3, "load normalization does not invent a completed recreation session")
	_assert_equal(loaded_console.reserved_by, -1, "satisfied loaded claim leaves console capacity free")

	_dispose(loaded)
	_dispose(original)


func _test_hud_contract() -> void:
	var game := _spawn_game()
	var orders := game.player_orders
	orders.refresh()
	_assert_equal(orders.command_grid.columns, 8, "expanded command grid retains two-row layout")
	_assert_equal(orders.command_grid.get_child_count(), 15, "toolbar contains twelve tools plus save, load, and Help")
	_assert_equal(orders.briefing_panel.size, Vector2(640, 600), "briefing leaves room for every stabilization objective")
	_assert_equal(orders.briefing_overlay.mouse_filter, Control.MOUSE_FILTER_STOP, "briefing backdrop blocks accidental map input")
	_assert_true(orders.checklist.fit_content and orders.checklist.custom_minimum_size.y >= 238.0, "briefing checklist expands to keep all objectives legible")
	_assert_false(orders.right_scroll.is_ancestor_of(orders.objective_label), "critical wing telemetry stays outside the scrolling inspector")
	_assert_equal(orders.command_buttons.rec.text, "REC $8", "toolbar exposes the compact recreation build command")
	_assert_true("1 power" in orders.command_buttons.rec.tooltip_text, "recreation tooltip states its power demand")
	_assert_true("LOW ARI 72% · STEADY" in orders.crew_mood_label.text, "crew HUD identifies the lowest initial mood and tier")
	_assert_true("AVERAGE 72%" in orders.crew_mood_label.text, "crew HUD exposes the initial living average")
	_assert_equal(orders.crew_mood_bar.value, 72.0, "crew mood bar tracks the lowest living resident")
	_assert_equal(orders.crew_mood_bar.modulate, Color("75d4b4"), "steady crew mood uses the healthy effect color")
	var roster_moods := [71.9, 62.8, 53.7, 44.6]
	for index in game.residents.size():
		var roster_resident: VaultResident = game.residents[index]
		roster_resident.needs.mood = roster_moods[index]
	orders.refresh()
	for index in game.residents.size():
		var roster_resident: VaultResident = game.residents[index]
		var mood_button := _find_roster_button(orders, roster_resident.resident_name)
		_assert_true(mood_button != null and "MOOD %d" % floori(roster_moods[index]) in mood_button.text, "%s roster row shows that resident's mood" % roster_resident.resident_name)
	for roster_resident: VaultResident in game.residents:
		roster_resident.needs.mood = 72.0
	var deceased_resident: VaultResident = game.residents[3]
	deceased_resident.needs.mood = 0.0
	deceased_resident.kill()
	orders.refresh()
	_assert_true("LOW ARI 72% · STEADY" in orders.crew_mood_label.text and "AVERAGE 72%" in orders.crew_mood_label.text, "crew summary excludes deceased residents from low and average mood")

	game.begin_shift()
	orders.refresh()
	orders.command_buttons.rec.pressed.emit()
	_assert_equal(game.active_tool, "rec", "recreation toolbar button activates the build tool")
	var blueprint_cell := Vector2i(28, 20)
	_assert_true(game.issue_order(blueprint_cell), "recreation tool places a console blueprint on carved floor")
	var blueprint: VaultBuilding = game.get_building_at(blueprint_cell)
	_assert_true(blueprint != null and blueprint.kind == VaultBuilding.Kind.RECREATION_CONSOLE and not blueprint.complete, "recreation order creates the correct incomplete fixture")
	_assert_true("[OPTIONAL][/color]  Power a Rec Console" in orders.checklist.text, "an unfinished console remains clearly optional")
	game.set_tool("cancel")
	_assert_true(game.issue_order(blueprint_cell), "cancel removes the test recreation blueprint")
	game.set_tool("select")

	var resident: VaultResident = game.residents[0]
	resident.needs.mood = 39.0
	game.select_resident(resident.resident_id)
	orders.refresh()
	_assert_true("39% · STRESSED" in orders.crew_mood_label.text, "crew HUD exposes the stressed tier")
	_assert_equal(orders.crew_mood_bar.modulate, Color("efc56b"), "stressed crew mood uses the warning color")
	_assert_true("MOOD STRESSED · Ari" in orders.alert_label.text, "compound alerts name the stressed resident")
	_assert_equal(orders.need_labels.mood.text, "MOOD", "resident inspector relabels the legacy light need")
	_assert_equal(orders.need_bars.mood.value, 39.0, "resident mood bar shows the canonical meter")
	_assert_true("Mood: STRESSED" in orders.inspector_state.text, "resident inspector includes the mood tier")
	_assert_equal(orders.inspector_state.text.count("\n"), 3, "resident inspector uses stable explicit task, work, mood, and factor lines")
	game.oxygen_system.oxygen = OxygenSystem.LOW_OXYGEN_THRESHOLD
	orders.refresh()
	_assert_true("low O2" in orders.inspector_state.text and "-42 mood/day" in orders.inspector_state.text, "resident inspector exposes the low-oxygen mood weight")
	game.oxygen_system.oxygen = OxygenSystem.STARTING_OXYGEN
	var roster_button := _find_roster_button(orders, resident.resident_name)
	_assert_true(roster_button != null and "MOOD 39" in roster_button.text and "LOW 39" in roster_button.text, "roster exposes mood and includes it in urgency")
	_assert_true(roster_button != null and roster_button.tooltip_text == roster_button.text, "clipped roster text remains available as a tooltip")

	resident.needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD
	orders.refresh()
	_assert_true("BREAK RISK" in orders.crew_mood_label.text, "crew HUD exposes the exact break-risk boundary")
	_assert_equal(orders.crew_mood_bar.modulate, Color("ef5a54"), "break-risk crew mood uses the danger color")
	_assert_true("MOOD BREAK RISK · Ari" in orders.alert_label.text, "break-risk alert names the affected resident")
	_assert_true("NO REC CONSOLE" in orders.alert_label.text, "seek-level mood without a console raises an actionable shortage alert")

	var console := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, blueprint_cell)
	game.power_grid.recalculate(game.buildings)
	game.select_building(console.building_id)
	orders.refresh()
	_assert_true("[DONE][/color]  Power a Rec Console" in orders.checklist.text, "a powered completed console satisfies its optional checklist item")
	_assert_true("Priority: OPTIONAL (fixed)" in orders.inspector_state.text, "console inspector exposes its shed priority")
	_assert_true("Mood recovery: +18/s · one resident" in orders.inspector_state.text, "console inspector exposes recovery and capacity")
	_assert_true("Recreation: AVAILABLE · seek at 35%" in orders.inspector_state.text, "idle powered console reports availability")

	game.job_system.advance(VaultGame.SIMULATION_TICK)
	orders.refresh()
	_assert_true("Recreation: RESERVED · Ari" in orders.inspector_state.text, "claimed console distinguishes a reservation from active use")
	resident.position = game.map_grid.cell_to_world(console.cell)
	resident.clear_path()
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	orders.refresh()
	_assert_true("Recreation: IN USE · Ari" in orders.inspector_state.text, "occupied console names its active resident")
	_assert_true("1 RECREATING" in orders.crew_mood_label.text, "crew HUD counts active recreation")

	var second_resident: VaultResident = game.residents[1]
	second_resident.position = game.map_grid.cell_to_world(console.cell)
	second_resident.clear_path()
	game.set_tool("select")
	game.select_building(console.building_id)
	_assert_true(game.issue_order(console.cell), "selecting a stacked console first reaches its first resident")
	_assert_equal(game.selected_resident_id, resident.resident_id, "first occupied-cell click selects the active recreation user")
	_assert_true(game.issue_order(console.cell), "a second occupied-cell click cycles to the next resident")
	_assert_equal(game.selected_resident_id, second_resident.resident_id, "stacked residents remain individually inspectable")
	_assert_true(game.issue_order(console.cell), "a third occupied-cell click reaches the underlying fixture")
	_assert_equal(game.selected_building_id, console.building_id, "occupied recreation fixture remains selectable from the map")

	game.user_paused = true
	orders.refresh()
	_assert_true("Recreation: PAUSED · Ari" in orders.inspector_state.text, "paused console assignment does not claim active recovery")
	_assert_true("0 RECREATING" in orders.crew_mood_label.text, "paused crew summary does not count frozen recovery")
	game.select_resident(resident.resident_id)
	orders.refresh()
	_assert_true("Rec Console · paused" in orders.inspector_state.text, "resident inspector exposes a paused console session")
	game.user_paused = false
	game.select_building(console.building_id)
	orders.refresh()
	_assert_true("Recreation: IN USE · Ari" in orders.inspector_state.text, "resuming restores active console wording")
	_assert_true(game.toggle_building_enabled(console.building_id), "console can be disabled from its fixture lifecycle")
	orders.refresh()
	_assert_true("DISABLED" in orders.inspector_state.text and "Recreation: OFFLINE" in orders.inspector_state.text, "disabled console reports both power and recreation state")
	_assert_true("REC CONSOLE OFFLINE" in orders.alert_label.text, "low mood with an existing disabled console reports an outage rather than a shortage")
	_assert_false(resident.recreating, "disabling the console immediately clears its HUD-driving resident state")
	_dispose(game)


func _find_roster_button(orders: PlayerOrders, resident_name: String) -> Button:
	for child: Node in orders.roster_box.get_children():
		if child is Button and not child.is_queued_for_deletion() and child.text.begins_with(resident_name):
			return child as Button
	return null


func _prepare_residents(game: VaultGame) -> void:
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
		resident.sleeping = false
		resident.bed_id = -1
		resident.stress_break_left = 0.0
		game.job_system.release_resident(resident)


func _spawn_game() -> VaultGame:
	var game := MAIN_SCENE.instantiate() as VaultGame
	if game != null:
		root.add_child(game)
	return game


func _add_completed_building(game: VaultGame, kind: int, cell: Vector2i) -> VaultBuilding:
	var building := VaultBuilding.new()
	game.building_root.add_child(building)
	building.configure(game.next_building_id, kind as VaultBuilding.Kind, cell, true)
	game.next_building_id += 1
	game.buildings.append(building)
	return building


func _dispose(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()


func _assert_true(condition: bool, message: String) -> void:
	_assertion_count += 1
	if not condition:
		_fail(message, "expected true")


func _assert_false(condition: bool, message: String) -> void:
	_assertion_count += 1
	if condition:
		_fail(message, "expected false")


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	_assertion_count += 1
	if actual != expected:
		_fail(message, "expected %s, got %s" % [str(expected), str(actual)])


func _assert_approximately(actual: float, expected: float, tolerance: float, message: String) -> void:
	_assertion_count += 1
	if absf(actual - expected) > tolerance:
		_fail(message, "expected %.6f +/- %.6f, got %.6f" % [expected, tolerance, actual])


func _fail(message: String, detail: String) -> void:
	_failure_count += 1
	printerr("[FAIL] %s :: %s — %s" % [_current_case, message, detail])
