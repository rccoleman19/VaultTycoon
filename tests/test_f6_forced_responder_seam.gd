extends "res://tests/test_runner.gd"

# A live forced hatch reservation bypasses OFF. Next must describe the same
# response (or blocker) as DETAILS and follow the reserved resident's path.
const WATCH_HATCH := "Next: YOU watch hatch · THEY auto-patch"
const TUNNEL_TO_HATCH := "Next: YOU mark a tunnel to the hatch [E] · THEY dig it out"
const ENABLE_HAUL := "Next: YOU enable Haul [P] · THEY patch hatch"
const ENABLE_CRAFT := "Next: YOU enable Craft [P] · THEY patch hatch"
const HAUL_EN_ROUTE := "HAUL RESPONSE EN ROUTE"
const PATCH_RESPONDING := "PATCH CREW RESPONDING"
const NO_PATH := "BLOCKED · NO PATH TO HATCH"
const HAUL_BLOCKED := "BLOCKED · ENABLE HAUL"
const CRAFT_BLOCKED := "BLOCKED · ENABLE CRAFT"


func _run() -> void:
	_run_case("forced supply with Haul OFF keeps Next and DETAILS on the hatch response", _test_forced_supply)
	_run_case("forced patch with Craft OFF keeps Next and DETAILS on the hatch response", _test_forced_patch)
	_run_case("a reachable bystander cannot hide a stranded forced hatch carrier", _test_disconnected_forced_responder)
	_run_case("cancelled or drafted forced responders restore the same hatch blocker", _test_cancel_or_draft)
	print("F6 SEAM TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _test_forced_supply() -> void:
	var game := _warned_game()
	var ari: VaultResident = game.residents[0]
	# Cover the later Craft stage so this case isolates the forced Haul exception.
	game.residents[1].set_work_priority("craft", VaultResident.DEFAULT_WORK_PRIORITY)
	_assert_hud(game, ENABLE_HAUL, HAUL_BLOCKED, "before force")
	_force_hatch(game, ari, JobSystem.JobType.SUPPLY_BREACH, "supply")
	_assert_equal(ari.get_work_priority("haul"), VaultResident.PRIORITY_DISABLED, "forcing supply leaves Haul OFF")
	_assert_hud(game, WATCH_HATCH, HAUL_EN_ROUTE, "live forced supply")
	_dispose(game)


func _test_forced_patch() -> void:
	var game := _warned_game()
	var ari: VaultResident = game.residents[0]
	_assert_equal(game.breach_system.add_delivery(BreachSystem.PATCH_COST), BreachSystem.PATCH_COST, "fixture supplies the hatch")
	game.job_system.advance(0.0)
	_assert_hud(game, ENABLE_CRAFT, CRAFT_BLOCKED, "before force")
	_force_hatch(game, ari, JobSystem.JobType.PATCH_BREACH, "patch")
	_assert_equal(ari.get_work_priority("craft"), VaultResident.PRIORITY_DISABLED, "forcing patch leaves Craft OFF")
	_assert_hud(game, WATCH_HATCH, PATCH_RESPONDING, "live forced patch")
	_dispose(game)


func _test_disconnected_forced_responder() -> void:
	var game := _warned_game()
	var ari: VaultResident = game.residents[0]
	var bo: VaultResident = game.residents[1]
	bo.set_work_priority("craft", VaultResident.DEFAULT_WORK_PRIORITY)
	_force_hatch(game, ari, JobSystem.JobType.SUPPLY_BREACH, "stranded supply")
	for _tick: int in 200:
		game.step_simulation(VaultGame.SIMULATION_TICK)
		if ari.carrying > 0:
			break
	_assert_equal(ari.carrying, BreachSystem.PATCH_COST, "forced carrier picks up the hatch salvage")
	_assert_true(game.breach_system.needs_supply(), "the carried salvage has not reached the hatch")
	_teleport_isolated(game, ari)
	_assert_true(ari.is_forced_job, "stranded carrier keeps the forced order")
	var job := game.job_system._find_job(ari.current_job_id)
	_assert_equal(int(job.get("reserved_by", -1)), ari.resident_id, "stranded carrier still owns the live reservation")
	_assert_false(bool(job.get("done", true)), "stranded reservation is unfinished")
	bo.set_work_priority("haul", VaultResident.DEFAULT_WORK_PRIORITY)
	_assert_false(game.map_grid.find_path(bo.get_cell(game.map_grid), BreachSystem.HATCH_CELL).is_empty(), "eligible bystander can reach the hatch")
	# Do not advance: the reservation is still live and belongs to the stranded
	# carrier, so the bystander's route cannot turn the response into watch hatch.
	_assert_hud(game, TUNNEL_TO_HATCH, NO_PATH, "stranded carrier with reachable bystander")
	_dispose(game)


func _test_cancel_or_draft() -> void:
	for type: int in [JobSystem.JobType.SUPPLY_BREACH, JobSystem.JobType.PATCH_BREACH]:
		for ending: String in ["cancel", "draft"]:
			var game := _warned_game()
			var ari: VaultResident = game.residents[0]
			var patching := type == JobSystem.JobType.PATCH_BREACH
			var label := "%s forced %s" % [ending, "patch" if patching else "supply"]
			if patching:
				_assert_equal(game.breach_system.add_delivery(BreachSystem.PATCH_COST), BreachSystem.PATCH_COST, "%s: fixture supplies the hatch" % label)
				game.job_system.advance(0.0)
			else:
				game.residents[1].set_work_priority("craft", VaultResident.DEFAULT_WORK_PRIORITY)
			_force_hatch(game, ari, type, label)
			_assert_equal(_status(game), PATCH_RESPONDING if patching else HAUL_EN_ROUTE, "%s: DETAILS starts with a live response" % label)
			if ending == "cancel":
				_assert_true(game.job_system.cancel_manual_command(ari), "%s: manual order cancels" % label)
			else:
				_assert_true(game.toggle_resident_draft(ari.resident_id), "%s: responder drafts" % label)
			_assert_false(ari.is_forced_job, "%s: forced order has ended" % label)
			_assert_equal(ari.get_work_priority("craft" if patching else "haul"), VaultResident.PRIORITY_DISABLED, "%s: work priority remains OFF" % label)
			_assert_hud(game, ENABLE_CRAFT if patching else ENABLE_HAUL, CRAFT_BLOCKED if patching else HAUL_BLOCKED, label)
			_dispose(game)


func _warned_game() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
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
	_assert_equal(resident.get_cell(game.map_grid), isolated, "forced carrier now stands on the isolated floor")
	_assert_true(game.map_grid.find_path(isolated, BreachSystem.HATCH_CELL).is_empty(), "forced carrier has no path to the hatch")


func _status(game: VaultGame) -> String:
	return game.job_system.get_breach_response_status()


func _assert_hud(game: VaultGame, expected_next: String, expected_status: String, label: String) -> void:
	game.focus_breach()
	game.player_orders.refresh()
	var step: Dictionary = game.player_orders._primary_next_step()
	_assert_equal(str(step.get("text", "")), expected_next, "%s: Next action and target agree with DETAILS" % label)
	_assert_equal(game.player_orders.objective_label.text, expected_next, "%s: rendered Next names the same hatch action" % label)
	_assert_equal(_status(game), expected_status, "%s: hatch response status names the expected action" % label)
	_assert_equal(game.player_orders.inspector_title.text, "MAINTENANCE HATCH", "%s: DETAILS target is the hatch" % label)
	_assert_equal(game.player_orders.inspector_state.text.get_slice("\n", 2), expected_status, "%s: hatch inspector shows the exact response status" % label)
	_assert_equal(game.player_orders.breach_label.text.get_slice("\n", 2), expected_status, "%s: DETAILS hatch readout shows the exact response status" % label)
