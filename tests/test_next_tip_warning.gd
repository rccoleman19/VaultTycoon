extends "res://tests/test_runner.gd"
# During an active hatch response (WARNING or OPEN), Next names what blocks the
# automatic patch before any other tip. A covered response keeps the ordinary
# tip, and sealing (or DORMANT) never takes the blocker branch.

const TICK := VaultGame.SIMULATION_TICK
const DIG := ["Next: YOU mark rock [E] · THEY dig on Dig defaults", "DIG [E] designates rock. Undrafted crew auto-claim Dig (default rank 3). Draft is optional.", "dig"]
const UNDRAFT := ["Next: YOU undraft crew [R] · THEY respond to hatch", "Drafted crew never answer the hatch. Select a drafted resident and press R to undraft.", "select"]
const ENABLE_BOTH := ["Next: YOU enable Haul + Craft [P] · THEY patch hatch", "Open PRIORITIES [P] and set Haul + Craft above OFF for an undrafted resident so crew auto-respond to the hatch.", "select"]
const ENABLE_HAUL := ["Next: YOU enable Haul [P] · THEY patch hatch", "Open PRIORITIES [P] and set Haul above OFF for an undrafted resident so crew auto-respond to the hatch.", "select"]
const ENABLE_CRAFT := ["Next: YOU enable Craft [P] · THEY patch hatch", "Open PRIORITIES [P] and set Craft above OFF for an undrafted resident so crew auto-respond to the hatch.", "select"]
const PATCH_SHORT_1 := ["Next: YOU mark 1 rock [E] · THEY fund the hatch patch", "The hatch patch is 2 salvage short. Each dug rock tile yields 3 salvage once hauled.", "dig"]
const PATCH_SHORT_COVERED := ["Next: YOU leave Dig + Haul on · THEY fund the hatch patch", "The hatch patch is 2 salvage short. Each dug rock tile yields 3 salvage once hauled.", "select"]
const ENABLE_DIG := ["Next: YOU enable Dig [P] · THEY fund the hatch patch", "The hatch patch is 2 salvage short. Open PRIORITIES [P] and set Dig above OFF for an undrafted resident so crew dig salvage.", "select"]
const PLACE_BUNKS := ["Next: YOU place bunks · THEY craft", "Place bunks so tired undrafted crew have a bed.", "bed"]
const PATCH_SHORT_TRANSIT := ["Next: YOU mark 1 rock [E] · THEY fund the hatch patch", "The hatch patch is 1 salvage short. Each dug rock tile yields 3 salvage once hauled.", "dig"]


func _run() -> void:
	_run_case("covered WARNING and OPEN keep the ordinary tip", _test_covered)
	_run_case("Haul and Craft OFF name both during WARNING and OPEN", _test_both_off)
	_run_case("Haul OFF or Craft OFF names that category", _test_single_off)
	_run_case("supplied patch needs Craft only", _test_supplied)
	_run_case("all drafted asks to undraft; dead crew never count", _test_drafted_and_dead)
	_run_case("salvage short counts stock, delivered and in-transit", _test_salvage_short)
	_run_case("Dig OFF while short asks for Dig unless rubble covers it", _test_dig_off_short)
	_run_case("blocker outranks critical food advice", _test_outranks_needs)
	_run_case("covered WARNING keeps the tired-crew bunk tip", _test_covered_bunk_crisis)
	_run_case("forced responder is not counted as coverage", _test_forced_not_counted)
	_run_case("DORMANT and SEALED never take the blocker branch", _test_dormant_and_sealed)
	_run_case("HUD walk shows the blocker from WARNING through OPEN, then clears", _test_hud_walk)
	print("NEXT TIP WARNING TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(0 if _failure_count == 0 else 1)


func _healthy() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
		resident.drafted = false
		resident.sleeping = false
		resident.bed_id = -1
		resident.medical_bed_id = -1
	return game


func _warn(game: VaultGame) -> void:
	# Real path: one simulation tick across 60 s raises the warning modal.
	game.day_cycle.elapsed_seconds = BreachSystem.WARNING_AT_SECONDS - TICK
	game.step_simulation(TICK)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.WARNING, "real hatch WARNING")
	game.acknowledge_breach_warning(false)


func _open(game: VaultGame) -> void:
	game.day_cycle.elapsed_seconds = BreachSystem.WARNING_AT_SECONDS + BreachSystem.GRACE_SECONDS + 1.0
	game.breach_system.advance(0.0, game.day_cycle.elapsed_seconds)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.OPEN, "real hatch OPEN")


func _set_all(game: VaultGame, work: String, priority: int) -> void:
	for resident: VaultResident in game.residents:
		resident.set_work_priority(work, priority)


func _tuple(game: VaultGame) -> Array:
	var step: Dictionary = game.player_orders._primary_next_step()
	return [step.text, step.help, step.tool]


func _assert_tuple(game: VaultGame, expected: Array, message: String) -> void:
	_assert_equal(_tuple(game), expected, message)


func _test_covered() -> void:
	var game := _healthy()
	_assert_tuple(game, DIG, "DORMANT ordinary tip")
	_warn(game)
	_assert_tuple(game, DIG, "covered WARNING keeps the ordinary tip")
	_open(game)
	_assert_tuple(game, DIG, "covered OPEN keeps the ordinary tip")
	_dispose(game)


func _test_both_off() -> void:
	var game := _healthy()
	_set_all(game, "haul", VaultResident.PRIORITY_DISABLED)
	_set_all(game, "craft", VaultResident.PRIORITY_DISABLED)
	_warn(game)
	_assert_tuple(game, ENABLE_BOTH, "WARNING with Haul + Craft OFF")
	_open(game)
	_assert_tuple(game, ENABLE_BOTH, "OPEN with Haul + Craft OFF")
	game.residents[2].set_work_priority("haul", 4)
	game.residents[3].set_work_priority("craft", 4)
	_assert_tuple(game, DIG, "one Haul and one Craft above OFF clears the blocker")
	_dispose(game)


func _test_single_off() -> void:
	var game := _healthy()
	_set_all(game, "haul", VaultResident.PRIORITY_DISABLED)
	_warn(game)
	_assert_tuple(game, ENABLE_HAUL, "WARNING with Haul OFF")
	_dispose(game)
	game = _healthy()
	_set_all(game, "craft", VaultResident.PRIORITY_DISABLED)
	_warn(game)
	_assert_tuple(game, ENABLE_CRAFT, "WARNING with Craft OFF")
	_open(game)
	_assert_tuple(game, ENABLE_CRAFT, "OPEN with Craft OFF")
	_dispose(game)


func _test_supplied() -> void:
	var game := _healthy()
	_warn(game)
	_assert_equal(game.breach_system.add_delivery(BreachSystem.PATCH_COST), BreachSystem.PATCH_COST, "patch fully supplied")
	_set_all(game, "haul", VaultResident.PRIORITY_DISABLED)
	_assert_tuple(game, DIG, "supplied patch: Haul OFF no longer blocks")
	_set_all(game, "craft", VaultResident.PRIORITY_DISABLED)
	_assert_tuple(game, ENABLE_CRAFT, "supplied patch: Craft OFF blocks alone")
	_dispose(game)


func _test_drafted_and_dead() -> void:
	var game := _healthy()
	_warn(game)
	for resident: VaultResident in game.residents:
		resident.drafted = true
	_assert_tuple(game, UNDRAFT, "all living crew drafted")
	game.residents[0].drafted = false
	_assert_tuple(game, DIG, "one undrafted resident with defaults clears the blocker")
	game.residents[0].set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
	_assert_tuple(game, ENABLE_HAUL, "drafted crew with Haul on do not count")
	for index in range(1, game.residents.size()):
		game.residents[index].drafted = false
		game.residents[index].alive = false
	_assert_tuple(game, ENABLE_HAUL, "dead crew with Haul on do not count")
	game.residents[0].alive = false
	_assert_tuple(game, UNDRAFT, "no living undrafted crew left")
	_dispose(game)


func _test_salvage_short() -> void:
	var game := _healthy()
	_warn(game)
	game.food_system.salvage = 2
	_assert_equal(game.job_system.get_uncredited_rubble(), 0, "fixture has no uncredited rubble")
	_assert_equal(game.map_grid.dig_marks.size(), 0, "fixture has no queued digs")
	_assert_tuple(game, PATCH_SHORT_1, "2 stock salvage: mark 1 rock")
	_assert_true(game.map_grid.queue_dig(Vector2i(17, 10)), "one connected rock marked")
	_assert_tuple(game, PATCH_SHORT_COVERED, "queued dig covers the shortfall")
	game.map_grid.dig_marks.clear()
	game.food_system.salvage = 1
	_assert_equal(game.breach_system.add_delivery(1), 1, "one salvage already delivered")
	var supply: Dictionary = {}
	for job: Dictionary in game.job_system.jobs:
		if int(job.type) == JobSystem.JobType.SUPPLY_BREACH and not bool(job.get("done", false)):
			supply = job
	_assert_false(supply.is_empty(), "real hatch supply job exists")
	supply["in_transit"] = 1
	_assert_tuple(game, PATCH_SHORT_TRANSIT, "stock 1 + delivered 1 + transit 1 is 1 short")
	supply["in_transit"] = 2
	_assert_tuple(game, DIG, "stock 1 + delivered 1 + transit 2 covers the patch")
	_dispose(game)


func _test_dig_off_short() -> void:
	var game := _healthy()
	_warn(game)
	game.food_system.salvage = 2
	_set_all(game, "dig", VaultResident.PRIORITY_DISABLED)
	_assert_tuple(game, ENABLE_DIG, "Dig OFF with no rubble asks for Dig")
	game.job_system.queue_rubble(Vector2i(18, 11), 1)
	_assert_tuple(game, ENABLE_DIG, "1 rubble does not cover a 2 shortfall")
	game.job_system.queue_rubble(Vector2i(19, 11), 1)
	_assert_tuple(game, PATCH_SHORT_COVERED, "2 rubble covers the shortfall without Dig")
	_dispose(game)


func _test_covered_bunk_crisis() -> void:
	var game := _healthy()
	game.residents[0].needs.rest = 28.0
	_assert_tuple(game, PLACE_BUNKS, "DORMANT tired-crew bunk tip")
	_warn(game)
	_assert_tuple(game, PLACE_BUNKS, "covered WARNING keeps the tired-crew bunk tip")
	_dispose(game)


func _test_outranks_needs() -> void:
	var game := _healthy()
	game.residents[0].needs.food = 10.0
	game.food_system.meals = 0
	_assert_equal(_tuple(game)[0], "Next: YOU place a Nutrient Station · THEY cook", "DORMANT critical food tip")
	_set_all(game, "haul", VaultResident.PRIORITY_DISABLED)
	_warn(game)
	_assert_tuple(game, ENABLE_HAUL, "Haul blocker outranks the critical food tip")
	_set_all(game, "haul", VaultResident.DEFAULT_WORK_PRIORITY)
	_assert_equal(_tuple(game)[0], "Next: YOU place a Nutrient Station · THEY cook", "covered WARNING keeps the critical food tip")
	_dispose(game)


func _test_forced_not_counted() -> void:
	var game := _healthy()
	_warn(game)
	var ari: VaultResident = game.residents[0]
	for resident: VaultResident in game.residents:
		game.job_system.release_resident(resident)
		for work: String in VaultResident.WORK_TYPES:
			resident.set_work_priority(work, VaultResident.PRIORITY_DISABLED)
	game.select_resident(ari.resident_id)
	_assert_true(game.issue_context_order(BreachSystem.HATCH_CELL), "real forced hatch supply accepted")
	_assert_true(ari.is_forced_job and ari.current_job_type == JobSystem.JobType.SUPPLY_BREACH, "Ari forced onto hatch supply")
	_assert_tuple(game, ENABLE_BOTH, "a one-shot force does not replace Haul + Craft")
	_dispose(game)


func _test_dormant_and_sealed() -> void:
	var game := _healthy()
	_set_all(game, "haul", VaultResident.PRIORITY_DISABLED)
	_set_all(game, "craft", VaultResident.PRIORITY_DISABLED)
	_assert_tuple(game, DIG, "DORMANT with Haul + Craft OFF keeps the ordinary tip")
	_dispose(game)
	game = _healthy()
	_warn(game)
	game.breach_system.add_delivery(BreachSystem.PATCH_COST)
	_assert_true(game.breach_system.apply_patch_work(BreachSystem.PATCH_WORK_SECONDS), "patch work seals the hatch")
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.SEALED, "hatch SEALED")
	_set_all(game, "haul", VaultResident.PRIORITY_DISABLED)
	_set_all(game, "craft", VaultResident.PRIORITY_DISABLED)
	for resident: VaultResident in game.residents:
		resident.drafted = true
	game.food_system.salvage = 0
	_assert_tuple(game, DIG, "SEALED returns to ordinary advice despite OFF, drafted and no salvage")
	_dispose(game)


func _test_hud_walk() -> void:
	var game := _healthy()
	_set_all(game, "haul", VaultResident.PRIORITY_DISABLED)
	_set_all(game, "craft", VaultResident.PRIORITY_DISABLED)
	_warn(game)
	game.acknowledge_breach_warning(true)
	var tool_before: String = game.active_tool
	var blocked_ticks := 0
	var other: Array[String] = []
	var saw_open := false
	while game.day_cycle.elapsed_seconds < 95.0:
		game.player_orders.refresh()
		if game.player_orders.objective_label.text == ENABLE_BOTH[0]:
			blocked_ticks += 1
		elif other.size() < 3:
			other.append("%.1fs %s" % [game.day_cycle.elapsed_seconds, game.player_orders.objective_label.text])
		saw_open = saw_open or game.breach_system.phase == BreachSystem.Phase.OPEN
		game.step_simulation(TICK)
	_assert_equal(other, [] as Array[String], "objective names Haul + Craft every tick from 60 s to 95 s")
	_assert_true(blocked_ticks >= 340, "blocker shown on every walked tick")
	_assert_true(saw_open, "walk crosses into OPEN")
	_assert_equal(game.active_tool, tool_before, "refresh never changes the active tool")
	_set_all(game, "haul", VaultResident.DEFAULT_WORK_PRIORITY)
	_set_all(game, "craft", VaultResident.DEFAULT_WORK_PRIORITY)
	game.player_orders.refresh()
	_assert_true(game.player_orders.objective_label.text != ENABLE_BOTH[0], "enabling Haul + Craft clears the blocker from the HUD")
	_dispose(game)
