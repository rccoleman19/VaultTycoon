extends "res://tests/test_runner.gd"

const RELEASE := "Next: YOU disable a Lumen · THEY power the Grow Tray"
const ADD_POWER := "Next: YOU place a Charge Node · THEY power the Grow Tray"
const ENABLE := "Next: YOU enable a Grow Tray · THEY grow"
const REC := "Next: YOU place a Rec Console · THEY recover mood"
const FINISH_POWER := "Next: YOU leave Haul + Craft on · THEY finish the Charge Node"
const TRAY_CELL := Vector2i(23, 12)
const KITCHEN_CELL := Vector2i(24, 12)
const EXTRA_LUMEN_CELL := Vector2i(26, 12)


func _run() -> void:
	_run_case("S1 real shed tray outranks mood breaks and releases a Lumen", _test_shed_release)
	_run_case("S2 the last powered Lumen is preserved and suppressed builds stay suppressed", _test_last_lumen)
	_run_case("S3 a manually disabled tray uses the real enable action", _test_disabled)
	_run_case("S4 named starvation replaces the active food-worker blocker", _test_named_starvation)
	_run_case("S4 unnamed forecast keeps the food runway prefix on the tray fix", _test_unnamed_forecast)
	_run_case("S4 drafted food urgency still asks for undrafting", _test_drafted_urgency)
	_run_case("S4 too-late food advice is preserved", _test_too_late)
	_run_case("S5 releasing power restores the tray and preserves the mood latch", _test_fix_and_latch)
	_run_case("S5 a powered tray keeps the Rec tip even with a disabled spare", _test_powered_tray)
	_run_case("S6 an unfinished Charge Node is finished instead of placing another", _test_finish_charge)
	_run_case("S7 an unpowered kitchen leaves the previous mood tip unchanged", _test_unpowered_kitchen)
	_run_case("S7 an incomplete tray leaves the previous mood tip unchanged", _test_incomplete_tray)
	_run_case("S7 the real hatch blocker keeps priority", _test_hatch_priority)
	_run_case("S7 suffocating urgency keeps priority", _test_air_priority)
	_run_case("S7 ended games do not receive the shed recovery rule", _test_ended_guard)
	print("SHED TRAY TIP TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


# The core plus one completed Charge Node supply 9. Air (3), the kitchen (2)
# and two Lumens (2) consume 7, leaving 2: the real allocator sheds the 3-power
# tray. A single Lumen release then makes exactly enough room for the tray.
# With one Lumen, a second kitchen keeps demand high while testing that the
# final powered light cannot be offered as the release action.
func _wing(two_lumens := true, extra_power := false) -> VaultGame:
	var game := _spawn_game()
	game.new_game(false, 4242, 3)
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
	game.residents[0].needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD
	game.food_system.meals = 100
	game.food_system.raw_food = 0
	game.food_system.salvage = 100
	for x in range(17, 29):
		var cell := Vector2i(x, 10)
		_assert_true(game.map_grid.queue_dig(cell) and game.map_grid.apply_dig_work(cell, 8.0), "fixture carves the real twelve-rock gate")
	game.job_system.jobs = game.job_system.jobs.filter(func(job: Dictionary) -> bool:
		return int(job.type) not in [JobSystem.JobType.DIG, JobSystem.JobType.HAUL_RUBBLE])
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(20, 12))
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(21, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(22, 12))
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, TRAY_CELL)
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, KITCHEN_CELL)
	_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(25, 12))
	_add_completed_building(game, VaultBuilding.Kind.LAMP if two_lumens else VaultBuilding.Kind.KITCHEN, EXTRA_LUMEN_CELL)
	if extra_power:
		_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(27, 12))
	game.breach_system.phase = BreachSystem.Phase.SEALED
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.patch_work_left = 0.0
	game.player_orders.show_breach_warning(false)
	_refresh_power(game)
	game.player_orders.clear_survival_tips()
	return game


func _refresh_power(game: VaultGame) -> void:
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, game.breach_system.is_open())


func _next(game: VaultGame) -> Dictionary:
	return game.player_orders._primary_next_step()


func _text(game: VaultGame) -> String:
	return str(_next(game).get("text", ""))


func _assert_shown(game: VaultGame, expected: String, message: String) -> void:
	_assert_equal(_text(game), expected, message + " selects the exact Next text")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, expected, message + " reaches the displayed Next label")


func _assert_shed(game: VaultGame, message: String) -> void:
	var tray := game.get_building_at(TRAY_CELL)
	_assert_true(tray != null and tray.complete and not tray.manually_disabled, message + " has a complete enabled tray")
	_assert_false(tray.powered, message + " tray is unpowered")
	_assert_true(game.power_grid.is_building_shed(tray.building_id), message + " is shed by the real power allocator")
	_assert_true(game.power_grid.brownout_active, message + " has an actual brownout")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.GROW_TRAY), 0, message + " has no powered tray")
	_assert_true(game.get_building_at(KITCHEN_CELL).powered, message + " kitchen remains powered")


func _assert_recovery_metadata(step: Dictionary, message: String) -> void:
	_assert_equal(str(step.get("kind", "")), "food", message + " remains a food step")
	_assert_true(bool(step.get("restores_existing_tray", false)), message + " identifies an existing tray recovery")


func _test_shed_release() -> void:
	var game := _wing()
	_assert_shed(game, "S1")
	_assert_equal(game.power_grid.supply, 9, "S1 uses the observed nine-power grid")
	_assert_equal(game.power_grid.served, 7, "S1 leaves two power, below the tray's three-power draw")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.LAMP), 2, "S1 can spare one of two powered Lumens")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.RECREATION_CONSOLE), 0, "S1 has no completed Rec Console")
	_assert_true(game.player_orders._resident_urgency_step().is_empty(), "S1 stocked pantry and healthy needs have no starvation or other urgency")
	_assert_shown(game, RELEASE, "S1")
	_assert_false("Rec Console" in _text(game), "S1 the mood-break tip yields to the shed tray")
	_assert_recovery_metadata(_next(game), "S1")
	_dispose(game)


func _test_last_lumen() -> void:
	var game := _wing(false)
	_assert_shed(game, "S2")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.LAMP), 1, "S2 only the last Lumen is powered")
	_assert_shown(game, ADD_POWER, "S2")
	_assert_recovery_metadata(_next(game), "S2")
	var suppressed := {VaultBuilding.Kind.GENERATOR: true}
	_assert_true(game.player_orders._shed_tray_step(suppressed).is_empty(), "S2 queued-suppressed Charge placement does not become a shed tip")
	_assert_equal(str(game.player_orders._primary_next_step_chain(suppressed).get("text", "")), REC, "S2 suppression lets the existing mood decision run")
	_dispose(game)


func _test_disabled() -> void:
	var game := _wing(true, true)
	var tray := game.get_building_at(TRAY_CELL)
	_assert_true(tray.powered, "S3 tray is genuinely powered before the manual toggle")
	_assert_true(game.toggle_building_enabled(tray.building_id), "S3 actual DISABLE action succeeds")
	_assert_true(tray.manually_disabled and not tray.powered, "S3 the real toggle disables the completed tray")
	_assert_false(game.power_grid.is_building_shed(tray.building_id), "S3 a manually disabled tray is not classified as shed")
	_assert_false(game.power_grid.brownout_active, "S3 manual disabling needs no brownout")
	_assert_shown(game, ENABLE, "S3")
	_assert_recovery_metadata(_next(game), "S3")
	_assert_true(game.toggle_building_enabled(tray.building_id), "S3 actual ENABLE action succeeds")
	_assert_true(tray.powered and not tray.manually_disabled, "S3 ENABLE immediately restores tray power")
	_assert_shown(game, REC, "S3 after enabling")
	_dispose(game)


# One real raw ration keeps the worker-break blocker active while the only
# complete tray is shed. It is not counted as an already-stored meal for the
# named resident's starvation deadline, but is counted in pantry runway.
func _food_warning(game: VaultGame, named: bool) -> void:
	game.food_system.meals = 0
	game.food_system.raw_food = 1
	if named:
		game.residents[0].needs.food = 0.0
	game.player_orders.clear_survival_tips()


func _test_named_starvation() -> void:
	var game := _wing()
	_food_warning(game, true)
	_assert_shed(game, "S4 named")
	_assert_equal(str(game.player_orders._food_work_blocker_step().get("text", "")), REC, "S4 named has the active food-worker Rec blocker")
	var resident: VaultResident = game.residents[0]
	var food_death := float(game.player_orders._food_depletion_times()[resident.resident_id]) + resident.needs.health / (160.0 / DayCycle.SECONDS_PER_DAY)
	_assert_true(food_death < 60.0, "S4 named resident is inside their own real starvation window")
	_assert_false(bool(game.player_orders._food_fix_plan().step.get("too_late", false)), "S4 named still has an available food plan")
	_assert_shown(game, "Next: %s starving · YOU disable a Lumen · THEY power the Grow Tray" % resident.resident_name, "S4 named")
	var next := _next(game)
	_assert_equal(str(next.get("cause", "")), "food", "S4 named preserves food urgency cause")
	_assert_equal(int(next.get("resident_id", -1)), resident.resident_id, "S4 named preserves the threatened resident")
	_assert_true(bool(next.get("urgent", false)), "S4 named preserves the urgency flag")
	_assert_false(bool(next.get("food_unnamed", false)), "S4 named never becomes an unnamed forecast")
	_assert_recovery_metadata(next, "S4 named")
	_dispose(game)


func _test_unnamed_forecast() -> void:
	var game := _wing()
	_food_warning(game, false)
	_assert_shed(game, "S4 forecast")
	_assert_equal(str(game.player_orders._food_work_blocker_step().get("text", "")), REC, "S4 forecast has the active food-worker Rec blocker")
	for resident: VaultResident in game.residents:
		var food_death := float(game.player_orders._food_depletion_times()[resident.resident_id]) + resident.needs.health / (160.0 / DayCycle.SECONDS_PER_DAY)
		_assert_true(food_death >= 60.0, "S4 forecast %s stays outside the named starvation window" % resident.resident_name)
	_assert_shown(game, "Next: food runway short · YOU disable a Lumen · THEY power the Grow Tray", "S4 forecast")
	var next := _next(game)
	_assert_equal(str(next.get("cause", "")), "food", "S4 forecast preserves the food cause")
	_assert_true(bool(next.get("food_unnamed", false)) and bool(next.get("urgent", false)), "S4 forecast preserves unnamed urgency metadata")
	_assert_false("starving" in str(next.get("text", "")), "S4 forecast names no resident")
	_assert_recovery_metadata(next, "S4 forecast")
	_dispose(game)


func _test_drafted_urgency() -> void:
	var game := _wing()
	_food_warning(game, true)
	var resident: VaultResident = game.residents[0]
	resident.drafted = true
	_assert_false(game.player_orders._food_work_blocker_step().is_empty(), "S4 drafted still has other eligible but breaking food workers")
	_assert_shown(game, "Next: %s starving · YOU undraft %s [R] · THEY eat/work" % [resident.resident_name, resident.resident_name], "S4 drafted")
	_assert_false(bool(_next(game).get("restores_existing_tray", false)), "S4 drafted retains the undraft action without tray recovery metadata")
	_dispose(game)


func _test_too_late() -> void:
	var game := _wing()
	game.food_system.meals = 0
	game.residents[0].needs.food = 0.0
	game.residents[0].needs.health = 1.0
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GROW_TRAY, Vector2i(27, 12)), "S4 too-late unfinished source is a real tray blueprint")
	game.player_orders.clear_survival_tips()
	_assert_false(game.player_orders._food_work_blocker_step().is_empty(), "S4 too-late also has the food-worker blocker")
	_assert_true(bool(game.player_orders._food_fix_plan().step.get("too_late", false)), "S4 too-late has no food rescue inside pantry runway")
	_assert_shown(game, "Next: %s starving · nothing lands in time · keep crew fed where possible" % game.residents[0].resident_name, "S4 too-late")
	_assert_true(bool(_next(game).get("too_late", false)), "S4 too-late retains the existing flag")
	_assert_false("disable a Lumen" in _text(game), "S4 too-late is never replaced by the shed action")
	_dispose(game)


func _test_fix_and_latch() -> void:
	var game := _wing()
	_assert_shed(game, "S5 before release")
	_assert_shown(game, RELEASE, "S5 before release")
	# A normal stress break lifts mood from 9 to 25. The shed early return must
	# still have entered the existing mood latch before we restore tray power.
	game.residents[0].needs.mood = 25.0
	var lumen := game.get_building_at(EXTRA_LUMEN_CELL)
	_assert_true(game.toggle_building_enabled(lumen.building_id), "S5 applies the recommended real Lumen DISABLE action")
	_assert_true(game.get_building_at(TRAY_CELL).powered, "S5 released power immediately restores the only tray")
	_assert_false(game.power_grid.brownout_active, "S5 the real allocation clears its brownout")
	_assert_true(game.player_orders._shed_tray_step().is_empty(), "S5 the shed rule stops once the tray is powered")
	_assert_shown(game, REC, "S5 after power release with mood now 25")
	_assert_false("Grow Tray" in _text(game), "S5 a repaired tray does not remain in Next")
	_dispose(game)


func _test_powered_tray() -> void:
	var game := _wing(true, true)
	_assert_true(game.get_building_at(TRAY_CELL).powered, "S5 unchanged fixture has a powered tray from the start")
	_assert_shown(game, REC, "S5 powered from the start")
	var spare := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(28, 12))
	_refresh_power(game)
	_assert_true(game.toggle_building_enabled(spare.building_id), "S5 spare tray is manually disabled through the real action")
	_assert_true(spare.manually_disabled and not spare.powered, "S5 spare is a disabled complete tray")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.GROW_TRAY), 1, "S5 main tray stays powered alongside the disabled spare")
	_assert_true(game.player_orders._shed_tray_step().is_empty(), "S5 any powered tray prevents the new rule from firing")
	_assert_shown(game, REC, "S5 powered tray with disabled spare")
	_dispose(game)


func _test_finish_charge() -> void:
	var game := _wing(false)
	_assert_shed(game, "S6")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(27, 12)), "S6 Charge Node is a real unfinished blueprint")
	_assert_false(game.get_building_at(Vector2i(27, 12)).complete, "S6 the queued Charge Node is unfinished")
	_assert_shown(game, FINISH_POWER, "S6")
	_assert_false("place a Charge Node" in _text(game), "S6 never requests another Charge Node")
	_assert_recovery_metadata(_next(game), "S6")
	_assert_equal(str(game.player_orders._shed_tray_step({VaultBuilding.Kind.GENERATOR: true}).get("text", "")), FINISH_POWER, "S6 queued placement suppression leaves the existing finish action usable")
	_dispose(game)


func _test_unpowered_kitchen() -> void:
	var game := _wing()
	var generator := game.get_building_at(Vector2i(22, 12))
	game.buildings.erase(generator)
	generator.free()
	_refresh_power(game)
	game.player_orders.clear_survival_tips()
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.KITCHEN), 1, "S7 kitchen guard has a complete kitchen")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.KITCHEN), 0, "S7 actual low supply sheds the kitchen as well")
	_assert_true(game.power_grid.is_building_shed(game.get_building_at(TRAY_CELL).building_id), "S7 tray remains really shed while kitchen is offline")
	_assert_true(game.player_orders._shed_tray_step().is_empty(), "S7 an unpowered kitchen blocks the shed-only rule")
	_assert_shown(game, REC, "S7 unpowered kitchen preserves the previous mood tip")
	_dispose(game)


func _test_incomplete_tray() -> void:
	var game := _wing()
	var tray := game.get_building_at(TRAY_CELL)
	game.buildings.erase(tray)
	tray.free()
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GROW_TRAY, TRAY_CELL), "S7 incomplete tray is a real blueprint")
	_refresh_power(game)
	game.player_orders.clear_survival_tips()
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.GROW_TRAY), 0, "S7 incomplete blueprint is not a completed tray")
	_assert_true(game.get_building_at(KITCHEN_CELL).powered, "S7 no-complete-tray guard still has a powered kitchen")
	_assert_true(game.player_orders._shed_tray_step().is_empty(), "S7 no completed tray blocks the shed rule")
	_assert_shown(game, REC, "S7 incomplete tray preserves the previous mood tip")
	_dispose(game)


func _test_hatch_priority() -> void:
	var game := _wing()
	_assert_shed(game, "S7 hatch")
	game.breach_system.reset()
	game.day_cycle.elapsed_seconds = game.breach_system.warning_at
	game.breach_system.advance(0.0, game.day_cycle.elapsed_seconds)
	for resident: VaultResident in game.residents:
		resident.drafted = true
	game.player_orders.clear_survival_tips()
	_assert_true(game.breach_system.is_response_active(), "S7 hatch warning is a real active response")
	_assert_false(game.player_orders._breach_blocker_step().is_empty(), "S7 drafted crew create a real hatch blocker")
	_assert_shown(game, "Next: YOU acknowledge warning · then undraft crew [R]", "S7 hatch blocker")
	_assert_false("Grow Tray" in _text(game), "S7 hatch blocker still outranks the shed recovery")
	_dispose(game)


func _test_air_priority() -> void:
	var game := _wing()
	_assert_shed(game, "S7 air")
	game.oxygen_system.oxygen = 0.0
	game.residents[0].needs.health = 20.0
	_refresh_power(game)
	game.player_orders.clear_survival_tips()
	_assert_true(game.oxygen_system.is_critical(), "S7 air fixture has real critical oxygen")
	var urgent: Dictionary = game.player_orders._resident_urgency_step()
	_assert_equal(str(urgent.get("cause", "")), "air", "S7 real suffocation produces an air urgency")
	_assert_true(game.player_orders._urgency_interrupts_care(urgent), "S7 air urgency interrupts care before shed recovery")
	_assert_shown(game, "Next: %s suffocating · YOU place Air Recycler · THEY recycle more air" % game.residents[0].resident_name, "S7 air emergency")
	_assert_false("Grow Tray" in _text(game), "S7 suffocation still outranks the shed recovery")
	_dispose(game)


func _test_ended_guard() -> void:
	var game := _wing()
	_assert_shed(game, "S7 ended")
	_assert_false(game.player_orders._shed_tray_step().is_empty(), "S7 live fixture initially has a shed recovery step")
	game.ended = true
	_assert_true(game.player_orders._shed_tray_step().is_empty(), "S7 ended game suppresses the shed recovery rule")
	_dispose(game)
