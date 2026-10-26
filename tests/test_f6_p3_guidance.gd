extends "res://tests/test_runner.gd"

# Funding advice needs automatic Haul even when a forced hatch trip covers the
# current response. Path help names a live reservation's responder, otherwise
# retaining the category-level explanation.
const ENABLE_HAUL := "Next: YOU enable Haul [P] · THEY patch hatch"
const ENABLE_HAUL_HELP := "Open PRIORITIES [P] and set Haul above OFF for an undrafted resident so crew auto-respond to the hatch."
const FUND_WITH_RUBBLE := "Next: YOU leave Dig + Haul on · THEY fund the hatch patch"
const FUND_HELP := "The hatch patch is 2 salvage short. Each dug rock tile yields 3 salvage once hauled."
const WATCH_HATCH := "Next: YOU watch hatch · THEY auto-patch"
const WATCH_HELP := "When the hatch warns, undrafted Haul + Craft claim supply/patch without draft."
const TUNNEL_TO_HATCH := "Next: YOU mark a tunnel to the hatch [E] · THEY dig it out"
const TUNNEL_HELP := "Mark rock with DIG [E] to connect them to the hatch; crew with Dig above OFF dig it out."
const ARI_NO_PATH_HELP := "Ari can't walk to the hatch. " + TUNNEL_HELP
const HAUL_EN_ROUTE := "HAUL RESPONSE EN ROUTE"
const PATCH_RESPONDING := "PATCH CREW RESPONDING"
const NO_PATH := "BLOCKED · NO PATH TO HATCH"
const SHORTFALL := "BLOCKED · NEEDS 2 SALVAGE"


func _run() -> void:
	_run_case("a forced hatch trip cannot automatically haul rubble to fund a shortfall", _test_forced_supply_funding)
	_run_case("stranded forced supply names its responder despite a reachable bystander", _test_forced_supply_no_path)
	_run_case("stranded forced patch names its responder despite a reachable bystander", _test_forced_patch_no_path)
	_run_case("stranded automatic reservations also name their responder", _test_reserved_no_path)
	_run_case("no reservation retains generic Haul and Craft path help", _test_generic_no_path)
	print("F6 P3 GUIDANCE TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _test_forced_supply_funding() -> void:
	var game := _warned_game()
	var ari: VaultResident = game.residents[0]
	_set_all(game, "craft", VaultResident.DEFAULT_WORK_PRIORITY)
	_set_all(game, "dig", VaultResident.DEFAULT_WORK_PRIORITY)
	game.food_system.salvage = 2
	game.job_system.queue_rubble(Vector2i(18, 11), 3)
	_force_hatch(game, ari, JobSystem.JobType.SUPPLY_BREACH, "short supply")
	_assert_equal(game.food_system.salvage, 2, "fixture has two stock salvage")
	_assert_equal(game.job_system.get_uncredited_rubble(), 3, "fixture has three floor rubble")
	_assert_equal(game.job_system.get_uncredited_rubble(true), 0, "a forced supply trip does not make rubble automatically haulable")
	_assert_hud(game, ENABLE_HAUL, ENABLE_HAUL_HELP, SHORTFALL, "Haul OFF with forced supply and a real shortfall")
	# Enabling automatic Haul makes this reachable rubble useful funding.
	game.residents[1].set_work_priority("haul", VaultResident.DEFAULT_WORK_PRIORITY)
	_assert_equal(game.job_system.get_uncredited_rubble(true), 3, "an automatic hauler can claim the floor rubble")
	_assert_hud(game, FUND_WITH_RUBBLE, FUND_HELP, SHORTFALL, "automatic Haul now covers the rubble")
	game.residents[1].set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
	# With enough stock, the same live forced reservation covers the supply
	# stage even though nobody may automatically haul rubble.
	game.food_system.salvage = BreachSystem.PATCH_COST
	_assert_hud(game, WATCH_HATCH, WATCH_HELP, HAUL_EN_ROUTE, "enough stock with forced supply and Haul OFF")
	for _tick: int in 200:
		game.step_simulation(VaultGame.SIMULATION_TICK)
		if ari.carrying > 0:
			break
	_assert_equal(ari.carrying, BreachSystem.PATCH_COST, "the forced trip picks up the full patch")
	_assert_equal(game.food_system.salvage, 0, "the patch salvage has left stock")
	_assert_equal(game.job_system.get_breach_supply_in_transit(), BreachSystem.PATCH_COST, "the full patch is now in transit")
	_assert_true(ari.is_forced_job, "the in-transit supply remains a real forced order")
	_assert_hud(game, WATCH_HATCH, WATCH_HELP, HAUL_EN_ROUTE, "full patch in transit with Haul OFF")
	_dispose(game)


func _test_forced_supply_no_path() -> void:
	_test_forced_no_path(JobSystem.JobType.SUPPLY_BREACH)


func _test_forced_patch_no_path() -> void:
	_test_forced_no_path(JobSystem.JobType.PATCH_BREACH)


func _test_forced_no_path(type: int) -> void:
	var game := _warned_game()
	var ari: VaultResident = game.residents[0]
	var bo: VaultResident = game.residents[1]
	var patching := type == JobSystem.JobType.PATCH_BREACH
	var label := "forced %s" % ("patch" if patching else "supply")
	if patching:
		_assert_equal(game.breach_system.add_delivery(BreachSystem.PATCH_COST), BreachSystem.PATCH_COST, "%s: fixture supplies the hatch" % label)
	else:
		bo.set_work_priority("craft", VaultResident.DEFAULT_WORK_PRIORITY)
	_force_hatch(game, ari, type, label)
	_assert_hud(game, WATCH_HATCH, WATCH_HELP, PATCH_RESPONDING if patching else HAUL_EN_ROUTE, "%s before disconnection" % label)
	_teleport_isolated(game, ari)
	bo.set_work_priority("craft" if patching else "haul", VaultResident.DEFAULT_WORK_PRIORITY)
	_assert_false(game.map_grid.find_path(bo.get_cell(game.map_grid), BreachSystem.HATCH_CELL).is_empty(), "%s: eligible bystander can reach the hatch" % label)
	_assert_true(ari.is_forced_job, "%s: disconnected order remains forced" % label)
	_assert_equal(game.job_system.get_hatch_response().responder, ari, "%s: the shared response still names Ari" % label)
	_assert_hud(game, TUNNEL_TO_HATCH, ARI_NO_PATH_HELP, NO_PATH, "%s after disconnection" % label)
	_dispose(game)


func _test_reserved_no_path() -> void:
	for type: int in [JobSystem.JobType.SUPPLY_BREACH, JobSystem.JobType.PATCH_BREACH]:
		var game := _warned_game()
		var ari: VaultResident = game.residents[0]
		var patching := type == JobSystem.JobType.PATCH_BREACH
		var label := "automatic %s" % ("patch" if patching else "supply")
		if patching:
			_assert_equal(game.breach_system.add_delivery(BreachSystem.PATCH_COST), BreachSystem.PATCH_COST, "%s: fixture supplies the hatch" % label)
		else:
			game.residents[1].set_work_priority("craft", VaultResident.DEFAULT_WORK_PRIORITY)
		ari.set_work_priority("craft" if patching else "haul", VaultResident.DEFAULT_WORK_PRIORITY)
		game.job_system.advance(0.0)
		_assert_equal(ari.current_job_type, type, "%s: Ari claims the hatch stage automatically" % label)
		_assert_false(ari.is_forced_job, "%s: the reservation is automatic" % label)
		_assert_equal(int(game.job_system._find_job(ari.current_job_id).get("reserved_by", -1)), ari.resident_id, "%s: Ari owns the reservation" % label)
		_teleport_isolated(game, ari)
		_assert_equal(game.job_system.get_hatch_response().responder, ari, "%s: the response names the reserved resident" % label)
		_assert_hud(game, TUNNEL_TO_HATCH, ARI_NO_PATH_HELP, NO_PATH, label)
		_dispose(game)


func _test_generic_no_path() -> void:
	for type: int in [JobSystem.JobType.SUPPLY_BREACH, JobSystem.JobType.PATCH_BREACH]:
		var game := _warned_game()
		var ari: VaultResident = game.residents[0]
		var patching := type == JobSystem.JobType.PATCH_BREACH
		var category := "Craft" if patching else "Haul"
		var label := "%s without a reservation" % category
		if patching:
			_assert_equal(game.breach_system.add_delivery(BreachSystem.PATCH_COST), BreachSystem.PATCH_COST, "%s: fixture supplies the hatch" % label)
		else:
			game.residents[1].set_work_priority("craft", VaultResident.DEFAULT_WORK_PRIORITY)
		ari.set_work_priority("craft" if patching else "haul", VaultResident.DEFAULT_WORK_PRIORITY)
		_teleport_isolated(game, ari)
		_assert_equal(ari.current_job_id, -1, "%s: Ari has not claimed a job" % label)
		_assert_equal(game.job_system.get_hatch_response().responder, null, "%s: no specific responder is set" % label)
		var help := "No undrafted %s crew can walk to the hatch. " % category + TUNNEL_HELP
		_assert_hud(game, TUNNEL_TO_HATCH, help, NO_PATH, label)
		_dispose(game)


func _warned_game() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	# Keep the forced/reserved hatch response as the only deadline under test:
	# 24 meals cover 240 seconds for this four-person crew even with work OFF.
	game.food_system.meals = 24
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
		resident.sleeping = false
		resident.bed_id = -1
		resident.stress_break_left = 0.0
		game.job_system.release_resident(resident)
		for work_type: String in VaultResident.WORK_TYPES:
			resident.set_work_priority(work_type, VaultResident.PRIORITY_DISABLED)
	game.day_cycle.elapsed_seconds = BreachSystem.WARNING_AT_SECONDS
	game.breach_system.advance(0.0, game.day_cycle.elapsed_seconds)
	game.acknowledge_breach_warning(false)
	return game


func _set_all(game: VaultGame, work_type: String, priority: int) -> void:
	for resident: VaultResident in game.residents:
		resident.set_work_priority(work_type, priority)


func _force_hatch(game: VaultGame, resident: VaultResident, expected_type: int, label: String) -> void:
	game.select_resident(resident.resident_id)
	_assert_true(game.issue_context_order(BreachSystem.HATCH_CELL), "%s: hatch context order is accepted" % label)
	_assert_true(resident.is_forced_job, "%s: hatch order is forced" % label)
	_assert_equal(resident.current_job_type, expected_type, "%s: forced job has the expected type" % label)
	var job := game.job_system._find_job(resident.current_job_id)
	_assert_equal(int(job.get("reserved_by", -1)), resident.resident_id, "%s: responder owns the reservation" % label)
	_assert_false(bool(job.get("done", true)), "%s: reservation is live" % label)
	_assert_equal(job.get("target"), BreachSystem.HATCH_CELL, "%s: reserved target is the hatch" % label)


func _teleport_isolated(game: VaultGame, resident: VaultResident) -> void:
	var isolated := Vector2i(2, 2)
	game.map_grid.cells[isolated.y * MapGrid.WIDTH + isolated.x] = MapGrid.Tile.FLOOR
	resident.clear_path()
	resident.position = game.map_grid.cell_to_world(isolated)
	_assert_equal(resident.get_cell(game.map_grid), isolated, "Ari now stands on the isolated floor")
	_assert_true(game.map_grid.find_path(isolated, BreachSystem.HATCH_CELL).is_empty(), "Ari has no path to the hatch")


func _assert_hud(game: VaultGame, expected_next: String, expected_help: String, expected_status: String, label: String) -> void:
	game.focus_breach()
	game.player_orders.refresh()
	var step: Dictionary = game.player_orders._primary_next_step()
	_assert_equal(str(step.get("text", "")), expected_next, "%s: Next names the expected action" % label)
	_assert_equal(str(step.get("help", "")), expected_help, "%s: step.help explains the expected action and responder" % label)
	_assert_equal(game.player_orders.objective_label.text, expected_next, "%s: rendered Next matches the action" % label)
	_assert_equal(game.job_system.get_breach_response_status(), expected_status, "%s: shared hatch status names the current response" % label)
	_assert_equal(game.player_orders.inspector_title.text, "MAINTENANCE HATCH", "%s: DETAILS target is the hatch" % label)
	_assert_equal(game.player_orders.inspector_state.text.get_slice("\n", 2), expected_status, "%s: DETAILS inspector shows the exact response status" % label)
	_assert_equal(game.player_orders.breach_label.text.get_slice("\n", 2), expected_status, "%s: DETAILS hatch readout shows the exact response status" % label)
