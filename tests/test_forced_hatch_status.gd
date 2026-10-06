extends "res://tests/test_runner.gd"

const HAUL_BLOCKED := "BLOCKED · ENABLE HAUL"
const CRAFT_BLOCKED := "BLOCKED · ENABLE CRAFT"
const HAUL_EN_ROUTE := "HAUL RESPONSE EN ROUTE"
const PATCH_RESPONDING := "PATCH CREW RESPONDING"


func _run() -> void:
	_run_case("forced hatch supply with Haul OFF reports en route, not blocked", _test_forced_supply_status)
	_run_case("forced supply stays en route through pickup and carry, then hands off", _test_forced_supply_carry)
	_run_case("forced supply still reports a real salvage shortfall", _test_forced_supply_shortfall)
	_run_case("forced hatch patch with Craft OFF reports the crew responding", _test_forced_patch_status)
	_run_case("forced supply during an open breach reports en route", _test_forced_supply_open_breach)
	_run_case("cancel, draft, and death restore the OFF blocker", _test_forced_end_restores_blocker)
	_run_case("only a live forced hatch reservation counts", _test_non_hatch_or_stale_forced_work)
	_run_case("an isolated eligible bystander does not hide a reachable forced hauler", _test_isolated_bystander)
	_run_case("a disconnected forced responder reports no path", _test_disconnected_forced_responder)
	_run_case("a loaded forced hatch order keeps its live status", _test_forced_supply_after_load)
	_run_case("automatic response statuses are unchanged", _test_automatic_statuses_unchanged)
	_run_case("a forced marker on someone else's, a done, or a missing job does not count", _test_stale_reservation_variants)
	_run_case("drafted or dead flags alone exclude the forced responder", _test_direct_flag_guards)
	_run_case("the patch stage ignores a still-reserved forced supply hauler", _test_stage_switch_with_live_supply_reservation)
	_run_case("a forced supply saved mid-carry stays en route every tick after load", _test_load_mid_carry_ticks)
	_run_case("a loaded forced patch keeps responding every tick until sealed", _test_load_forced_patch_ticks)
	print("FORCED HATCH STATUS TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _test_forced_supply_status() -> void:
	var game := _warned_game()
	var ari: VaultResident = game.residents[0]
	_assert_equal(_status(game), HAUL_BLOCKED, "all-OFF wing reports the Haul blocker before any force")
	_force_hatch(game, ari, JobSystem.JobType.SUPPLY_BREACH, "supply")
	_assert_equal(ari.get_work_priority("haul"), VaultResident.PRIORITY_DISABLED, "forced supply leaves Haul OFF")
	_assert_equal(_status(game), HAUL_EN_ROUTE, "live forced supply reports the haul en route")
	_assert_hud(game, HAUL_EN_ROUTE, "forced supply")
	_dispose(game)


func _test_forced_supply_carry() -> void:
	var game := _warned_game()
	var ari: VaultResident = game.residents[0]
	_force_hatch(game, ari, JobSystem.JobType.SUPPLY_BREACH, "carry")
	var saw_carry := false
	var wrong := 0
	for _tick: int in 200:
		game.step_simulation(VaultGame.SIMULATION_TICK)
		if not game.breach_system.needs_supply():
			break
		if ari.carrying > 0:
			saw_carry = true
		if _status(game) != HAUL_EN_ROUTE:
			wrong += 1
	_assert_true(saw_carry, "forced hauler picks up patch salvage")
	_assert_equal(wrong, 0, "every pickup and carry tick reports the haul en route")
	_assert_equal(game.breach_system.patch_delivered, BreachSystem.PATCH_COST, "forced hauler delivers the full patch with Haul OFF")
	_assert_false(ari.is_forced_job, "the one-shot supply order ends on delivery")
	_assert_equal(_status(game), CRAFT_BLOCKED, "after delivery the all-OFF wing reports the Craft blocker")
	_dispose(game)


func _test_forced_supply_shortfall() -> void:
	var game := _warned_game()
	var ari: VaultResident = game.residents[0]
	game.food_system.salvage = 2
	_force_hatch(game, ari, JobSystem.JobType.SUPPLY_BREACH, "shortfall")
	_assert_equal(_status(game), "BLOCKED · NEEDS 2 SALVAGE", "forced supply does not hide a salvage shortfall")
	for _tick: int in 10:
		game.step_simulation(VaultGame.SIMULATION_TICK)
		if ari.carrying > 0:
			break
	_assert_equal(ari.carrying, 2, "forced hauler carries the 2 salvage available")
	_assert_equal(_status(game), "BLOCKED · NEEDS 2 SALVAGE", "carrying a partial load still reports the shortfall")
	for _tick: int in 200:
		game.step_simulation(VaultGame.SIMULATION_TICK)
		if game.breach_system.patch_delivered > 0:
			break
	_assert_equal(game.breach_system.patch_delivered, 2, "partial load reaches the hatch")
	_assert_false(ari.is_forced_job, "partial delivery ends the one-shot order")
	_assert_equal(_status(game), HAUL_BLOCKED, "after the forced trip the all-OFF wing reports the Haul blocker")
	_dispose(game)


func _test_forced_patch_status() -> void:
	var game := _warned_game()
	var ari: VaultResident = game.residents[0]
	_assert_equal(game.breach_system.add_delivery(BreachSystem.PATCH_COST), BreachSystem.PATCH_COST, "patch fixture supplies the hatch")
	game.job_system.advance(0.0)
	_assert_equal(_status(game), CRAFT_BLOCKED, "supplied all-OFF wing reports the Craft blocker before any force")
	_force_hatch(game, ari, JobSystem.JobType.PATCH_BREACH, "patch")
	_assert_equal(ari.get_work_priority("craft"), VaultResident.PRIORITY_DISABLED, "forced patch leaves Craft OFF")
	_assert_equal(_status(game), PATCH_RESPONDING, "live forced patch reports the crew responding")
	_assert_hud(game, PATCH_RESPONDING, "forced patch")
	var saw_patching := false
	var wrong := 0
	for _tick: int in 200:
		game.step_simulation(VaultGame.SIMULATION_TICK)
		if game.breach_system.is_sealed():
			break
		if ari.state == "Patching pressure breach":
			saw_patching = true
		if _status(game) != PATCH_RESPONDING:
			wrong += 1
	_assert_true(saw_patching, "forced crafter reaches the hatch and patches")
	_assert_equal(wrong, 0, "every walk and patch tick reports the crew responding")
	_assert_true(game.breach_system.is_sealed(), "forced patch seals the hatch with Craft OFF")
	_assert_equal(_status(game), "PATCH COMPLETE · HATCH STABLE", "sealed hatch reports complete")
	_dispose(game)


func _test_forced_supply_open_breach() -> void:
	var game := _warned_game()
	var ari: VaultResident = game.residents[0]
	game.breach_system.advance(0.0, BreachSystem.WARNING_AT_SECONDS + BreachSystem.GRACE_SECONDS)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.OPEN, "fixture opens the breach")
	_assert_equal(_status(game), HAUL_BLOCKED, "open all-OFF wing reports the Haul blocker before any force")
	_force_hatch(game, ari, JobSystem.JobType.SUPPLY_BREACH, "open supply")
	_assert_equal(_status(game), HAUL_EN_ROUTE, "forced supply during an open breach reports en route")
	_assert_hud(game, HAUL_EN_ROUTE, "open-breach forced supply")
	_dispose(game)


func _test_forced_end_restores_blocker() -> void:
	var game := _warned_game()
	var ari: VaultResident = game.residents[0]
	_force_hatch(game, ari, JobSystem.JobType.SUPPLY_BREACH, "cancel")
	_assert_equal(_status(game), HAUL_EN_ROUTE, "cancel fixture starts en route")
	_assert_true(game.job_system.cancel_manual_command(ari), "the forced hatch order can be cancelled")
	_assert_equal(_status(game), HAUL_BLOCKED, "cancelling the forced order restores the Haul blocker")

	_force_hatch(game, ari, JobSystem.JobType.SUPPLY_BREACH, "draft")
	_assert_true(game.toggle_resident_draft(ari.resident_id), "the forced hauler can be drafted")
	_assert_equal(_status(game), HAUL_BLOCKED, "drafting the forced hauler restores the Haul blocker")

	# The toggle returns the resulting drafted state, so undrafting returns false.
	game.toggle_resident_draft(ari.resident_id)
	_assert_equal(game.breach_system.add_delivery(BreachSystem.PATCH_COST), BreachSystem.PATCH_COST, "death fixture supplies the hatch")
	game.job_system.advance(0.0)
	_force_hatch(game, ari, JobSystem.JobType.PATCH_BREACH, "death")
	_assert_equal(_status(game), PATCH_RESPONDING, "death fixture starts responding")
	ari.kill()
	_assert_equal(_status(game), CRAFT_BLOCKED, "the forced crafter's death restores the Craft blocker")
	_dispose(game)


func _test_non_hatch_or_stale_forced_work() -> void:
	var game := _warned_game()
	var ari: VaultResident = game.residents[0]
	var blueprint_cell := Vector2i(26, 19)
	_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, blueprint_cell), "fixture places a blueprint during the warning")
	game.select_resident(ari.resident_id)
	_assert_true(game.issue_context_order(blueprint_cell), "blueprint supply can be forced during the warning")
	_assert_equal(ari.current_job_type, JobSystem.JobType.SUPPLY_BUILD, "forced work is blueprint supply, not hatch supply")
	_assert_equal(_status(game), HAUL_BLOCKED, "forced non-hatch Haul work does not mask the hatch blocker")

	_force_hatch(game, ari, JobSystem.JobType.SUPPLY_BREACH, "stale")
	var job := game.job_system._find_job(ari.current_job_id)
	job.reserved_by = -1
	_assert_true(ari.is_forced_job, "stale fixture keeps the forced marker")
	_assert_equal(_status(game), HAUL_BLOCKED, "a forced marker without its live reservation does not count")
	_dispose(game)


func _test_isolated_bystander() -> void:
	var game := _warned_game()
	var ari: VaultResident = game.residents[0]
	var bo: VaultResident = game.residents[1]
	bo.set_work_priority("haul", 3)
	_teleport_isolated(game, bo)
	_assert_equal(_status(game), "BLOCKED · NO PATH TO HATCH", "only an isolated hauler is eligible before any force")
	_force_hatch(game, ari, JobSystem.JobType.SUPPLY_BREACH, "bystander")
	_assert_equal(_status(game), HAUL_EN_ROUTE, "reachable forced hauler reports en route despite the isolated bystander")
	_dispose(game)


func _test_disconnected_forced_responder() -> void:
	var game := _warned_game()
	var ari: VaultResident = game.residents[0]
	_force_hatch(game, ari, JobSystem.JobType.SUPPLY_BREACH, "disconnected")
	_teleport_isolated(game, ari)
	_assert_true(ari.is_forced_job, "teleported hauler keeps the forced order")
	_assert_equal(_status(game), "BLOCKED · NO PATH TO HATCH", "a stranded forced hauler reports no path")
	var bo: VaultResident = game.residents[1]
	bo.set_work_priority("haul", 3)
	_assert_equal(_status(game), "BLOCKED · NO PATH TO HATCH", "a reachable eligible bystander does not mask the stranded forced hauler")
	_dispose(game)


func _teleport_isolated(game: VaultGame, resident: VaultResident) -> void:
	var isolated := Vector2i(2, 2)
	game.map_grid.cells[isolated.y * MapGrid.WIDTH + isolated.x] = MapGrid.Tile.FLOOR
	resident.clear_path()
	resident.position = game.map_grid.cell_to_world(isolated)
	_assert_equal(resident.get_cell(game.map_grid), isolated, "%s now stands on the isolated floor" % resident.resident_name)
	_assert_true(game.map_grid.find_path(isolated, BreachSystem.HATCH_CELL).is_empty(), "isolated floor has no path to the hatch")


func _test_forced_supply_after_load() -> void:
	var source := _warned_game()
	var ari: VaultResident = source.residents[0]
	# Snapshot validation ties the WARNING phase to elapsed time in [60, 80).
	source.day_cycle.elapsed_seconds = BreachSystem.WARNING_AT_SECONDS + 1.0
	_force_hatch(source, ari, JobSystem.JobType.SUPPLY_BREACH, "save")
	_assert_equal(_status(source), HAUL_EN_ROUTE, "save source reports en route")
	var snapshot := source.create_snapshot()
	_dispose(source)
	var loaded := _spawn_game()
	_assert_true(loaded.apply_snapshot(snapshot), "forced hatch supply snapshot loads")
	var loaded_ari: VaultResident = loaded.residents[0]
	_assert_true(loaded_ari.is_forced_job, "load restores the forced hatch order")
	_assert_equal(loaded_ari.current_job_type, JobSystem.JobType.SUPPLY_BREACH, "load restores hatch supply")
	_assert_equal(_status(loaded), HAUL_EN_ROUTE, "loaded forced supply reports en route")
	_dispose(loaded)


func _test_automatic_statuses_unchanged() -> void:
	var game := _warned_game()
	var bo: VaultResident = game.residents[1]
	bo.set_work_priority("haul", 3)
	_assert_equal(_status(game), "AWAITING HAUL RESPONSE", "eligible unclaimed supply awaits a hauler")
	game.job_system.advance(0.0)
	_assert_equal(bo.current_job_type, JobSystem.JobType.SUPPLY_BREACH, "eligible hauler claims supply automatically")
	_assert_false(bo.is_forced_job, "automatic response is not forced")
	_assert_equal(_status(game), HAUL_EN_ROUTE, "automatic hauler reports en route")
	_assert_true(game.set_work_priority(bo.resident_id, "haul", VaultResident.PRIORITY_DISABLED), "Haul can be turned OFF again")
	_assert_equal(_status(game), HAUL_BLOCKED, "OFF automatic hauler reports the Haul blocker")
	_assert_equal(game.breach_system.add_delivery(BreachSystem.PATCH_COST), BreachSystem.PATCH_COST, "fixture supplies the hatch")
	_assert_equal(_status(game), CRAFT_BLOCKED, "no Craft reports the Craft blocker")
	bo.set_work_priority("craft", 3)
	_assert_equal(_status(game), "AWAITING PATCH CREW", "eligible unclaimed patch awaits a crafter")
	game.job_system.advance(0.0)
	_assert_equal(_status(game), PATCH_RESPONDING, "automatic crafter reports responding")
	_dispose(game)


func _test_stale_reservation_variants() -> void:
	for variant: String in ["other resident", "done", "missing"]:
		var game := _warned_game()
		var ari: VaultResident = game.residents[0]
		var bo: VaultResident = game.residents[1]
		_force_hatch(game, ari, JobSystem.JobType.SUPPLY_BREACH, variant)
		_assert_equal(_status(game), HAUL_EN_ROUTE, "%s: fixture starts en route" % variant)
		var job := game.job_system._find_job(ari.current_job_id)
		_assert_false(job.is_empty(), "%s: fixture finds the forced job" % variant)
		match variant:
			"other resident":
				job.reserved_by = bo.resident_id
			"done":
				job.done = true
			"missing":
				ari.current_job_id = 999999
		_assert_true(ari.is_forced_job, "%s: Ari keeps the forced marker" % variant)
		_assert_equal(_status(game), HAUL_BLOCKED, "%s: the stale forced marker does not count" % variant)
		_dispose(game)


func _test_direct_flag_guards() -> void:
	# Every in-game path that drafts or kills also clears the force; these pin the helper's own guards.
	var game := _warned_game()
	var ari: VaultResident = game.residents[0]
	_force_hatch(game, ari, JobSystem.JobType.SUPPLY_BREACH, "guard")
	ari.drafted = true
	_assert_true(ari.is_forced_job, "drafted flag fixture keeps the forced marker")
	_assert_equal(_status(game), HAUL_BLOCKED, "the drafted flag alone excludes the forced hauler")
	ari.drafted = false
	_assert_equal(_status(game), HAUL_EN_ROUTE, "clearing the flag restores en route")
	ari.alive = false
	_assert_true(ari.is_forced_job, "dead flag fixture keeps the forced marker")
	_assert_equal(_status(game), HAUL_BLOCKED, "the dead flag alone excludes the forced hauler")
	ari.alive = true
	_assert_equal(_status(game), HAUL_EN_ROUTE, "clearing the flag restores en route again")
	_dispose(game)


func _test_stage_switch_with_live_supply_reservation() -> void:
	var game := _warned_game()
	var ari: VaultResident = game.residents[0]
	var bo: VaultResident = game.residents[1]
	_force_hatch(game, ari, JobSystem.JobType.SUPPLY_BREACH, "switch")
	var job := game.job_system._find_job(ari.current_job_id)
	# No advance: the forced supply reservation is still live when the stage flips.
	_assert_equal(game.breach_system.add_delivery(BreachSystem.PATCH_COST), BreachSystem.PATCH_COST, "fixture supplies the hatch")
	_assert_equal(int(job.get("reserved_by", -1)), ari.resident_id, "the forced supply reservation is still live")
	_assert_true(ari.is_forced_job and ari.current_job_type == JobSystem.JobType.SUPPLY_BREACH, "Ari is still the forced hauler")
	_assert_equal(_status(game), CRAFT_BLOCKED, "the patch stage ignores the forced hauler and reports the Craft blocker")
	bo.set_work_priority("craft", 3)
	_assert_equal(_status(game), "AWAITING PATCH CREW", "an eligible crafter turns it into awaiting the patch crew")
	_dispose(game)


func _test_load_mid_carry_ticks() -> void:
	var source := _warned_game()
	var ari: VaultResident = source.residents[0]
	# Snapshot validation ties the WARNING phase to elapsed time in [60, 80).
	source.day_cycle.elapsed_seconds = BreachSystem.WARNING_AT_SECONDS + 1.0
	_force_hatch(source, ari, JobSystem.JobType.SUPPLY_BREACH, "carry save")
	for _tick: int in 100:
		source.step_simulation(VaultGame.SIMULATION_TICK)
		if ari.carrying > 0:
			break
	_assert_true(ari.carrying > 0, "save source: the forced hauler is carrying salvage")
	_assert_true(source.breach_system.needs_supply(), "save source: the hatch still needs supply")
	_assert_equal(_status(source), HAUL_EN_ROUTE, "save source reports en route mid-carry")
	var snapshot := source.create_snapshot()
	_dispose(source)
	var loaded := _spawn_game()
	_assert_true(loaded.apply_snapshot(snapshot), "mid-carry snapshot loads")
	var loaded_ari: VaultResident = loaded.residents[0]
	_assert_true(loaded_ari.is_forced_job, "load restores the forced order")
	_assert_equal(loaded_ari.current_job_type, JobSystem.JobType.SUPPLY_BREACH, "load restores hatch supply")
	_assert_equal(_status(loaded), HAUL_EN_ROUTE, "loaded mid-carry supply reports en route")
	var wrong := 0
	var checked := 0
	for _tick: int in 200:
		loaded.step_simulation(VaultGame.SIMULATION_TICK)
		if not loaded.breach_system.needs_supply():
			break
		checked += 1
		if _status(loaded) != HAUL_EN_ROUTE:
			wrong += 1
	_assert_true(checked > 0, "status was checked on ticks before delivery (got %d)" % checked)
	_assert_equal(wrong, 0, "every tick after load reports en route until delivery")
	_assert_equal(loaded.breach_system.patch_delivered, BreachSystem.PATCH_COST, "the loaded forced hauler delivers the full patch")
	_dispose(loaded)


func _test_load_forced_patch_ticks() -> void:
	var source := _warned_game()
	var ari: VaultResident = source.residents[0]
	source.day_cycle.elapsed_seconds = BreachSystem.WARNING_AT_SECONDS + 1.0
	# Natural forced delivery (not add_delivery) so the snapshot carries no stale supply job.
	_force_hatch(source, ari, JobSystem.JobType.SUPPLY_BREACH, "natural supply")
	for _tick: int in 200:
		source.step_simulation(VaultGame.SIMULATION_TICK)
		if not source.breach_system.needs_supply():
			break
	_assert_true(source.breach_system.is_supplied(), "save source: forced supply delivered the patch")
	_assert_true(source.breach_system.is_response_active(), "save source: hatch response still active")
	source.day_cycle.elapsed_seconds = minf(source.day_cycle.elapsed_seconds, BreachSystem.WARNING_AT_SECONDS + BreachSystem.GRACE_SECONDS - 1.0)
	_force_hatch(source, ari, JobSystem.JobType.PATCH_BREACH, "patch save")
	_assert_equal(_status(source), PATCH_RESPONDING, "save source reports the crew responding")
	var snapshot := source.create_snapshot()
	_dispose(source)
	var loaded := _spawn_game()
	_assert_true(loaded.apply_snapshot(snapshot), "forced patch snapshot loads")
	var loaded_ari: VaultResident = loaded.residents[0]
	_assert_true(loaded_ari.is_forced_job, "load restores the forced patch order")
	_assert_equal(loaded_ari.current_job_type, JobSystem.JobType.PATCH_BREACH, "load restores hatch patch")
	_assert_equal(_status(loaded), PATCH_RESPONDING, "loaded forced patch reports the crew responding")
	var wrong := 0
	var checked := 0
	for _tick: int in 300:
		loaded.step_simulation(VaultGame.SIMULATION_TICK)
		if loaded.breach_system.is_sealed():
			break
		checked += 1
		if _status(loaded) != PATCH_RESPONDING:
			wrong += 1
	_assert_true(checked > 0, "status was checked on ticks before sealing (got %d)" % checked)
	_assert_true(loaded.breach_system.is_sealed(), "the loaded forced patch seals the hatch with Craft OFF")
	_assert_equal(wrong, 0, "every tick after load reports the crew responding until sealed")
	_dispose(loaded)


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
	game.breach_system.advance(0.0, BreachSystem.WARNING_AT_SECONDS)
	game.acknowledge_breach_warning(false)
	return game


func _force_hatch(game: VaultGame, resident: VaultResident, expected_type: int, label: String) -> void:
	game.select_resident(resident.resident_id)
	_assert_true(game.issue_context_order(BreachSystem.HATCH_CELL), "%s: hatch context order is accepted" % label)
	_assert_true(resident.is_forced_job, "%s: hatch order is marked forced" % label)
	_assert_equal(resident.current_job_type, expected_type, "%s: hatch order has the expected job type" % label)


func _status(game: VaultGame) -> String:
	return game.job_system.get_breach_response_status()


func _assert_hud(game: VaultGame, expected: String, label: String) -> void:
	game.player_orders.refresh()
	var bar_text: String = game.player_orders.breach_label.text
	_assert_true(expected in bar_text, "%s: breach HUD shows %s" % [label, expected])
	_assert_false("BLOCKED" in bar_text, "%s: breach HUD shows no blocker" % label)
	game.focus_breach()
	game.player_orders.refresh()
	var inspector_text: String = game.player_orders.inspector_state.text
	_assert_true(expected in inspector_text, "%s: hatch inspector shows %s" % [label, expected])
	_assert_false("BLOCKED" in inspector_text, "%s: hatch inspector shows no blocker" % label)
