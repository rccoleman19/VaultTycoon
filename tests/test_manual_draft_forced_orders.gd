extends "res://tests/test_runner.gd"


func _run() -> void:
	_run_case("drafting safely releases work, cargo, and self-care", _test_draft_release_and_toggle)
	_run_case("drafted residents obey replaceable moves without autonomy", _test_manual_move_and_drafted_autonomy)
	_run_case("forced jobs target exactly, bypass OFF, and never steal", _test_forced_job_arbitration)
	_run_case("context orders cover hauling, building, cooking, and the hatch", _test_context_job_types)
	_run_case("survival and hatch urgency can interrupt ordinary forced work", _test_forced_job_interruptions)
	_run_case("manual commands preserve controls and expose clear HUD states", _test_command_state_and_hud)
	_run_case("schema-one manual orders round trip and reject malformed payloads", _test_manual_order_save_compatibility)
	print("MANUAL DRAFT / FORCED ORDER TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _test_draft_release_and_toggle() -> void:
	var game := _manual_game()
	var resident: VaultResident = game.residents[0]
	game.select_resident(resident.resident_id)
	resident.set_work_priority("haul", VaultResident.PRIORITY_HIGHEST)
	var blueprint_cell := Vector2i(27, 19)
	_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, blueprint_cell), "cargo-release fixture places a reachable blueprint")
	var supply_job := _find_job_of_type(game, JobSystem.JobType.SUPPLY_BUILD)
	var salvage_before_pickup := game.food_system.salvage
	for _tick in 100:
		game.job_system.advance(VaultGame.SIMULATION_TICK)
		if resident.carrying > 0:
			break
	_assert_true(resident.carrying > 0, "resident picks up blueprint salvage before being drafted")
	_assert_equal(supply_job.get("reserved_by"), resident.resident_id, "active supply work is reserved by the selected resident")
	_assert_true(game.toggle_resident_draft(resident.resident_id), "draft toggle reports the drafted state")
	_assert_true(resident.drafted, "selected living resident becomes drafted")
	_assert_equal(resident.current_job_id, -1, "drafting releases the active job")
	_assert_equal(resident.carrying, 0, "drafting clears carried cargo")
	_assert_equal(resident.carrying_kind, "", "drafting clears the carried-cargo kind")
	_assert_equal(supply_job.get("reserved_by"), -1, "drafting releases the job reservation")
	_assert_equal(supply_job.get("in_transit"), 0, "drafting clears the in-transit supply amount")
	_assert_equal(game.food_system.salvage, salvage_before_pickup, "drafting refunds in-flight salvage exactly once")

	_assert_false(game.toggle_resident_draft(resident.resident_id), "second toggle reports the undrafted state")
	_assert_false(resident.drafted, "resident returns to autonomous scheduling")
	var console := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(20, 12))
	console.reserved_by = resident.resident_id
	resident.begin_recreation(console.building_id)
	_assert_true(game.toggle_resident_draft(resident.resident_id), "resident can be drafted out of recreation")
	_assert_false(resident.recreating, "drafting cancels recreation")
	_assert_equal(resident.recreation_id, -1, "drafting clears the recreation target")
	_assert_equal(console.reserved_by, -1, "drafting releases the recreation-console reservation")

	_assert_false(game.toggle_resident_draft(resident.resident_id), "resident can be undrafted after recreation cleanup")
	var medical_bed := _add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(21, 12))
	medical_bed.reserved_by = resident.resident_id
	resident.medical_bed_id = medical_bed.building_id
	resident.state = "Seeking Medical Bed"
	_assert_true(game.toggle_resident_draft(resident.resident_id), "resident can be drafted out of medical care")
	_assert_equal(resident.medical_bed_id, -1, "drafting clears the medical target")
	_assert_equal(medical_bed.reserved_by, -1, "drafting releases the medical-bed reservation")

	_assert_false(game.toggle_resident_draft(resident.resident_id), "resident can be undrafted after medical cleanup")
	var bunk := _add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(22, 12))
	resident.sleeping = true
	resident.bed_id = bunk.building_id
	resident.state = "Sleeping"
	_assert_true(game.toggle_resident_draft(resident.resident_id), "resident can be drafted out of sleep")
	_assert_false(resident.sleeping, "drafting cancels sleep")
	_assert_equal(resident.bed_id, -1, "drafting clears the assigned bunk")
	_assert_false(game.toggle_resident_draft(999), "unknown resident cannot be drafted")
	_assert_true(game.issue_context_order(Vector2i(25, 18)), "death fixture gives the drafted resident a pending move")
	resident.kill()
	_assert_false(resident.alive, "death fixture kills the drafted resident")
	_assert_false(resident.drafted, "death clears persistent draft")
	_assert_false(resident.has_manual_move_order(), "death clears pending manual movement")
	_assert_false(resident.is_forced_job, "death clears any manual-job marker")
	_dispose(game)

	for cargo_type: int in [JobSystem.JobType.HAUL_RAW_FOOD, JobSystem.JobType.HAUL_MEAL]:
		var cargo_game := _manual_game()
		var carrier: VaultResident = cargo_game.residents[0]
		cargo_game.select_resident(carrier.resident_id)
		carrier.set_work_priority("haul", VaultResident.PRIORITY_HIGHEST)
		var source := carrier.get_cell(cargo_game.map_grid)
		var stored_before := cargo_game.food_system.raw_food if cargo_type == JobSystem.JobType.HAUL_RAW_FOOD else cargo_game.food_system.meals
		if cargo_type == JobSystem.JobType.HAUL_RAW_FOOD:
			cargo_game.job_system.queue_raw_food(source, 2)
		else:
			cargo_game.job_system.queue_meals(source, 2)
		cargo_game.job_system.advance(VaultGame.SIMULATION_TICK)
		var cargo_job := _find_job_of_type(cargo_game, cargo_type)
		_assert_equal(carrier.carrying, 2, "food hauler picks up %s before draft" % JobSystem.JOB_NAMES[cargo_type])
		_assert_equal(cargo_job.get("in_transit"), 2, "picked-up food is tracked in transit")
		_assert_true(cargo_game.toggle_resident_draft(carrier.resident_id), "draft interrupts %s safely" % JobSystem.JOB_NAMES[cargo_type])
		_assert_equal(carrier.carrying, 0, "draft empties the food carrier's hands")
		_assert_equal(cargo_job.get("amount"), 2, "draft returns carried food to its source backlog")
		_assert_equal(cargo_job.get("in_transit"), 0, "draft clears food in-transit state")
		_assert_equal(cargo_job.get("reserved_by"), -1, "draft releases the food-haul reservation")
		var stored_after := cargo_game.food_system.raw_food if cargo_type == JobSystem.JobType.HAUL_RAW_FOOD else cargo_game.food_system.meals
		_assert_equal(stored_after, stored_before, "draft cannot silently credit carried food")
		_dispose(cargo_game)


func _test_manual_move_and_drafted_autonomy() -> void:
	var game := _manual_game()
	var resident: VaultResident = game.residents[0]
	game.select_resident(resident.resident_id)
	for work_type: String in VaultResident.WORK_TYPES:
		resident.set_work_priority(work_type, VaultResident.PRIORITY_HIGHEST)
	resident.needs.food = 34.0
	resident.needs.rest = 27.0
	resident.needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD
	var meals_before := game.food_system.meals
	var food_before := resident.needs.food
	var rest_before := resident.needs.rest
	var mood_before := resident.needs.mood
	var rubble_cell := resident.get_cell(game.map_grid)
	game.job_system.queue_rubble(rubble_cell, 3)
	var rubble_job := _find_job_of_type(game, JobSystem.JobType.HAUL_RUBBLE)

	_assert_true(game.toggle_resident_draft(resident.resident_id), "resident enters persistent drafted mode")
	var first_destination := Vector2i(24, 18)
	var final_destination := Vector2i(26, 18)
	_assert_true(game.issue_context_order(first_destination), "drafted resident accepts a reachable floor move")
	_assert_true(resident.has_manual_move_order(), "accepted move exposes pending manual movement")
	_assert_equal(resident.manual_destination, first_destination, "first move records its exact floor cell")
	_assert_true(game.issue_context_order(final_destination), "a second reachable move replaces the first")
	_assert_equal(resident.manual_destination, final_destination, "replacement move keeps only the newest destination")
	_assert_false(game.issue_context_order(Vector2i.ZERO), "rock cannot replace a valid manual move")
	_assert_equal(resident.manual_destination, final_destination, "invalid replacement preserves the existing move")
	_assert_false(game.issue_context_order(Vector2i(-1, 12)), "out-of-bounds floor commands are rejected")
	_assert_equal(resident.manual_destination, final_destination, "out-of-bounds rejection preserves the existing move")
	var isolated_floor := Vector2i(2, 2)
	game.map_grid.cells[isolated_floor.y * MapGrid.WIDTH + isolated_floor.x] = MapGrid.Tile.FLOOR
	_assert_true(game.map_grid.is_walkable(isolated_floor), "unreachable fixture is carved floor")
	_assert_true(game.map_grid.find_path(resident.get_cell(game.map_grid), isolated_floor).is_empty(), "unreachable fixture is disconnected from the chamber")
	_assert_false(game.issue_context_order(isolated_floor), "disconnected carved floor cannot replace a reachable move")
	_assert_equal(resident.manual_destination, final_destination, "unreachable rejection preserves the existing move")
	game.select_resident(game.residents[1].resident_id)
	_assert_true(resident.drafted, "changing selection does not clear draft")
	_assert_equal(resident.manual_destination, final_destination, "changing selection does not clear the pending move")
	game.select_resident(resident.resident_id)

	for _tick in 120:
		game.step_simulation(VaultGame.SIMULATION_TICK)
		if not resident.has_manual_move_order():
			break
	_assert_equal(resident.get_cell(game.map_grid), final_destination, "manual movement ends on the exact ordered cell")
	_assert_false(resident.has_manual_move_order(), "arrival consumes the one manual move")
	_assert_true(resident.drafted, "arrival does not silently undraft the resident")
	_assert_equal(resident.current_job_id, -1, "drafted resident does not claim queued ordinary work")
	_assert_equal(rubble_job.get("reserved_by"), -1, "queued work remains unreserved by the drafted resident")
	_assert_equal(game.food_system.meals, meals_before, "drafted hunger does not trigger autonomous eating")
	_assert_false(resident.sleeping, "drafted low rest does not trigger autonomous sleep")
	_assert_equal(resident.stress_break_left, 0.0, "drafted low mood does not trigger an autonomous stress break")
	_assert_true(resident.needs.food < food_before, "food need still advances while drafted")
	_assert_true(resident.needs.rest < rest_before, "rest need still advances while drafted")
	_assert_true(resident.needs.mood < mood_before, "mood still advances while drafted")

	game.oxygen_system.oxygen = OxygenSystem.CRITICAL_OXYGEN_THRESHOLD
	var oxygen_before := game.oxygen_system.oxygen
	var health_before := resident.needs.health
	game.step_simulation(0.5)
	_assert_true(game.oxygen_system.oxygen < oxygen_before, "drafted resident still contributes to vault oxygen consumption")
	_assert_true(resident.needs.health < health_before, "critical oxygen still damages a drafted resident")
	_assert_true(resident.drafted, "environmental damage does not silently undraft its target")

	game.breach_system.advance(0.0, BreachSystem.WARNING_AT_SECONDS)
	game.job_system.advance(0.0)
	_assert_true(resident.drafted, "pressure warning does not undraft the resident")
	_assert_equal(resident.current_job_id, -1, "drafted resident does not autonomously answer the hatch warning")
	_dispose(game)


func _test_forced_job_arbitration() -> void:
	var game := _manual_game()
	var resident: VaultResident = game.residents[0]
	var other: VaultResident = game.residents[1]
	game.select_resident(resident.resident_id)
	var first_target := Vector2i(16, 12)
	var reserved_target := Vector2i(16, 14)
	var replacement_target := Vector2i(16, 16)
	_queue_dig_for_manual_test(game, first_target)
	_queue_dig_for_manual_test(game, reserved_target)

	_assert_equal(resident.get_work_priority("dig"), VaultResident.PRIORITY_DISABLED, "forced-work fixture starts with Dig OFF")
	_assert_true(game.issue_context_order(first_target), "undrafted selected resident accepts the exact queued excavation")
	_assert_true(resident.is_forced_job, "accepted context job is marked forced")
	_assert_equal(resident.current_job_type, JobSystem.JobType.DIG, "forced excavation has the correct job type")
	var first_job := game.job_system._find_job(resident.current_job_id)
	_assert_equal(first_job.get("target"), first_target, "forced excavation uses the clicked target rather than scheduler preference")
	_assert_equal(first_job.get("reserved_by"), resident.resident_id, "forced worker owns the exact reservation")
	_assert_equal(resident.get_work_priority("dig"), VaultResident.PRIORITY_DISABLED, "forcing bypasses OFF without changing the saved schedule")

	other.set_work_priority("dig", VaultResident.PRIORITY_HIGHEST)
	game.job_system.advance(0.0)
	var other_job := game.job_system._find_job(other.current_job_id)
	_assert_equal(other_job.get("target"), reserved_target, "second resident reserves the other exact excavation")
	var original_job_id := resident.current_job_id
	_assert_false(game.issue_context_order(reserved_target), "context order cannot steal another resident's reservation")
	_assert_equal(resident.current_job_id, original_job_id, "failed reservation steal leaves current forced work intact")
	_assert_true(resident.is_forced_job, "failed reservation steal keeps the forced marker")
	_assert_equal(first_job.get("reserved_by"), resident.resident_id, "failed reservation steal preserves the original reservation")
	_assert_false(game.issue_context_order(Vector2i(25, 18)), "floor with no contextual job is invalid for an undrafted resident")
	_assert_equal(resident.current_job_id, original_job_id, "invalid empty-floor command leaves existing work intact")

	_queue_dig_for_manual_test(game, replacement_target)
	_assert_true(game.issue_context_order(replacement_target), "valid context job replaces prior ordinary forced work")
	_assert_true(resident.is_forced_job, "replacement remains explicitly forced")
	var replacement_job := game.job_system._find_job(resident.current_job_id)
	_assert_equal(replacement_job.get("target"), replacement_target, "replacement binds the newly clicked job")
	_assert_equal(first_job.get("reserved_by"), -1, "replacing forced work releases the old reservation")
	var replacement_job_id := resident.current_job_id
	var isolated_floor := Vector2i(2, 2)
	game.map_grid.cells[isolated_floor.y * MapGrid.WIDTH + isolated_floor.x] = MapGrid.Tile.FLOOR
	game.job_system.queue_rubble(isolated_floor, 3)
	_assert_false(game.issue_context_order(isolated_floor), "unreachable queued work cannot be forced")
	_assert_equal(resident.current_job_id, replacement_job_id, "unreachable force preserves the resident's current job")
	_assert_equal(replacement_job.get("reserved_by"), resident.resident_id, "unreachable force preserves the current reservation")

	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(23, 12))
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(25, 12))
	game.power_grid.recalculate(game.buildings)
	game.job_system.advance(0.0)
	_assert_false(_find_job_of_type(game, JobSystem.JobType.COOK).is_empty(), "ready kitchen creates a forceable contextual job")
	_assert_true(game.toggle_building_enabled(kitchen.building_id), "test disables the kitchen after its job is queued")
	_assert_false(game.issue_context_order(kitchen.cell), "job whose live power prerequisite failed cannot be forced")
	_assert_equal(resident.current_job_id, replacement_job_id, "failed live prerequisite leaves forced work intact")
	_assert_equal(replacement_job.get("reserved_by"), resident.resident_id, "failed live prerequisite leaves its reservation intact")

	resident.kill()
	_assert_false(resident.is_forced_job, "death clears forced-job state")
	_assert_true(resident.forced_order.is_empty(), "death clears the persisted forced descriptor")
	_assert_equal(replacement_job.get("reserved_by"), -1, "death releases the forced reservation")
	_dispose(game)


func _test_context_job_types() -> void:
	var rubble_game := _manual_game()
	var resident: VaultResident = rubble_game.residents[0]
	rubble_game.select_resident(resident.resident_id)
	var rubble_cell := Vector2i(20, 12)
	rubble_game.job_system.queue_rubble(rubble_cell, 3)
	_assert_forced_job(rubble_game, resident, rubble_cell, JobSystem.JobType.HAUL_RUBBLE, "rubble context forces Haul")
	_dispose(rubble_game)

	for cargo in [[JobSystem.JobType.HAUL_RAW_FOOD, Vector2i(21, 12)], [JobSystem.JobType.HAUL_MEAL, Vector2i(22, 12)]]:
		var cargo_game := _manual_game()
		resident = cargo_game.residents[0]
		cargo_game.select_resident(resident.resident_id)
		if int(cargo[0]) == JobSystem.JobType.HAUL_RAW_FOOD:
			cargo_game.job_system.queue_raw_food(cargo[1], 2)
		else:
			cargo_game.job_system.queue_meals(cargo[1], 2)
		_assert_forced_job(cargo_game, resident, cargo[1], int(cargo[0]), "produced food context forces its exact Haul job")
		_dispose(cargo_game)

	var supply_game := _manual_game()
	resident = supply_game.residents[0]
	supply_game.select_resident(resident.resident_id)
	var blueprint_cell := Vector2i(26, 19)
	_assert_true(supply_game.place_blueprint(VaultBuilding.Kind.BED, blueprint_cell), "supply context creates a blueprint")
	_assert_forced_job(supply_game, resident, blueprint_cell, JobSystem.JobType.SUPPLY_BUILD, "unsupplied blueprint context forces Supply")
	_dispose(supply_game)

	var build_game := _manual_game()
	resident = build_game.residents[0]
	build_game.select_resident(resident.resident_id)
	_assert_true(build_game.place_blueprint(VaultBuilding.Kind.BED, blueprint_cell), "build context creates a blueprint")
	var blueprint := build_game.get_building_at(blueprint_cell)
	build_game.job_system.cancel_building(blueprint.building_id)
	_assert_equal(blueprint.add_delivery(blueprint.get_cost()), blueprint.get_cost(), "build context supplies the blueprint directly")
	build_game.job_system.queue_building(blueprint)
	_assert_forced_job(build_game, resident, blueprint_cell, JobSystem.JobType.BUILD, "supplied blueprint context forces Build")
	_dispose(build_game)

	var cook_game := _manual_game()
	resident = cook_game.residents[0]
	cook_game.select_resident(resident.resident_id)
	_add_completed_building(cook_game, VaultBuilding.Kind.GENERATOR, Vector2i(23, 12))
	var kitchen := _add_completed_building(cook_game, VaultBuilding.Kind.KITCHEN, Vector2i(25, 12))
	cook_game.power_grid.recalculate(cook_game.buildings)
	cook_game.job_system.advance(0.0)
	_assert_true(kitchen.powered and cook_game.food_system.can_cook(), "cook context has a powered ready nutrient station")
	_assert_forced_job(cook_game, resident, kitchen.cell, JobSystem.JobType.COOK, "ready station context forces Cook")
	_dispose(cook_game)

	var hatch_game := _manual_game()
	resident = hatch_game.residents[0]
	hatch_game.breach_system.advance(0.0, BreachSystem.WARNING_AT_SECONDS)
	hatch_game.acknowledge_breach_warning(false)
	hatch_game.select_resident(resident.resident_id)
	_assert_forced_job(hatch_game, resident, BreachSystem.HATCH_CELL, JobSystem.JobType.SUPPLY_BREACH, "warning hatch context forces emergency Haul through OFF")
	_dispose(hatch_game)

	var patch_game := _manual_game()
	resident = patch_game.residents[0]
	patch_game.breach_system.advance(0.0, BreachSystem.WARNING_AT_SECONDS)
	patch_game.acknowledge_breach_warning(false)
	_assert_equal(patch_game.breach_system.add_delivery(BreachSystem.PATCH_COST), BreachSystem.PATCH_COST, "patch fixture supplies the warned hatch directly")
	patch_game.job_system.advance(0.0)
	patch_game.select_resident(resident.resident_id)
	_assert_forced_job(patch_game, resident, BreachSystem.HATCH_CELL, JobSystem.JobType.PATCH_BREACH, "supplied hatch context forces emergency Craft through OFF")
	_dispose(patch_game)


func _test_forced_job_interruptions() -> void:
	var hunger_game := _manual_game()
	var resident: VaultResident = hunger_game.residents[0]
	hunger_game.select_resident(resident.resident_id)
	var dig_target := Vector2i(16, 12)
	_queue_dig_for_manual_test(hunger_game, dig_target)
	_assert_true(hunger_game.issue_context_order(dig_target), "survival fixture begins forced excavation")
	resident.needs.food = 35.0
	var meals_before := hunger_game.food_system.meals
	hunger_game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_equal(hunger_game.food_system.meals, meals_before - 1, "urgent hunger may consume a ration during forced work")
	_assert_true(resident.needs.food > 35.0, "survival interruption restores hunger")
	_assert_equal(resident.current_job_id, -1, "survival activity interrupts ordinary forced work")
	_assert_false(resident.is_forced_job, "survival interruption clears the forced marker")
	_assert_true(resident.forced_order.is_empty(), "survival interruption clears persisted forced-order intent")
	_dispose(hunger_game)

	var breach_game := _manual_game()
	resident = breach_game.residents[0]
	breach_game.select_resident(resident.resident_id)
	resident.set_work_priority("haul", VaultResident.PRIORITY_LOWEST)
	_queue_dig_for_manual_test(breach_game, dig_target)
	_assert_true(breach_game.issue_context_order(dig_target), "hatch fixture begins ordinary forced excavation")
	breach_game.breach_system.advance(0.0, BreachSystem.WARNING_AT_SECONDS)
	_assert_equal(resident.current_job_id, -1, "hatch warning immediately releases ordinary forced work")
	_assert_false(resident.is_forced_job, "hatch warning clears the ordinary forced marker")
	breach_game.job_system.advance(0.0)
	_assert_equal(resident.current_job_type, JobSystem.JobType.SUPPLY_BREACH, "urgent hatch work may replace the interrupted forced task")
	_assert_false(resident.is_forced_job, "automatic emergency response is not mislabeled as player-forced")
	_dispose(breach_game)


func _test_command_state_and_hud() -> void:
	var game := _manual_game()
	var resident: VaultResident = game.residents[0]
	game.select_resident(resident.resident_id)
	game.user_paused = true
	game.simulation_speed = 3
	game.set_tool("dig")
	var selected_before := game.selected_resident_id
	_send_manual_key(game, KEY_R)
	_assert_true(resident.drafted, "R drafts the selected resident while another map tool is active")
	_assert_true(game.user_paused, "draft command preserves pause state")
	_assert_equal(game.simulation_speed, 3, "draft command preserves simulation speed")
	_assert_equal(game.active_tool, "dig", "draft command preserves the active map tool")
	_assert_equal(game.selected_resident_id, selected_before, "draft command preserves resident selection")

	game.set_tool("select")
	var destination := Vector2i(25, 18)
	_assert_true(game.issue_context_order(destination), "manual move is accepted while paused")
	var move_feedback := game.status_message.to_lower()
	_assert_true(resident.resident_name.to_lower() in move_feedback and "mov" in move_feedback, "accepted move provides contextual resident feedback")
	_assert_true(game.user_paused, "manual move preserves pause state")
	_assert_equal(game.simulation_speed, 3, "manual move preserves simulation speed")
	_assert_equal(game.active_tool, "select", "manual move preserves the Select tool")
	_assert_equal(game.selected_resident_id, selected_before, "manual move preserves resident selection")

	game.player_orders.refresh()
	_assert_true(game.player_orders.resident_command_header.visible, "resident selection exposes the command section")
	_assert_true(game.player_orders.resident_command_row.visible, "resident selection exposes the command row")
	_assert_equal(game.player_orders.resident_draft_button.text, "UNDRAFT [R]", "drafted resident exposes an explicit undraft action")
	var tooltip := game.player_orders.resident_draft_button.tooltip_text.to_lower()
	_assert_true("right-click" in tooltip and "move" in tooltip, "drafted control explains the direct-move gesture")
	_assert_true("DRAFTED" in game.player_orders.inspector_state.text, "inspector identifies persistent drafted mode")
	_assert_true("MANUAL MOVE" in game.player_orders.inspector_state.text, "inspector identifies a pending manual move")
	_assert_true(_roster_contains(game, "DRAFTED"), "roster identifies drafted control")
	_assert_true(_roster_contains(game, "MANUAL MOVE"), "roster identifies pending direct movement")
	_assert_true("APPLY AFTER UNDRAFT" in game.player_orders.work_header.text, "drafted inspector explains when work priorities resume")
	_assert_true(_action_has_physical_key("draft_selected", KEY_R), "R is configured as the draft-selected shortcut")
	game.status_message_left = 0.0
	game.player_orders.refresh()
	var select_help := game.player_orders.tool_status.text.to_lower()
	_assert_true("draft" in select_help and "right-click" in select_help and "force" in select_help, "Select help explains both contextual command modes")

	game.player_orders.resident_draft_button.pressed.emit()
	_assert_false(resident.drafted, "inspector action undrafts its selected resident")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.resident_draft_button.text, "DRAFT [R]", "undrafted resident exposes an explicit draft action")
	tooltip = game.player_orders.resident_draft_button.tooltip_text.to_lower()
	_assert_true("right-click" in tooltip and "force" in tooltip, "undrafted control explains the force-context gesture")
	var rubble_cell := resident.get_cell(game.map_grid)
	game.job_system.queue_rubble(rubble_cell, 3)
	_assert_true(game.issue_context_order(rubble_cell), "HUD fixture accepts an undrafted forced job")
	_assert_true("forc" in game.status_message.to_lower(), "accepted forced job provides contextual feedback")
	game.player_orders.refresh()
	_assert_true("FORCED" in game.player_orders.inspector_state.text, "inspector distinguishes player-forced work")
	_assert_true(_roster_contains(game, "FORCED"), "roster distinguishes player-forced work")
	_assert_true(game.user_paused, "forced job preserves pause state")
	_assert_equal(game.simulation_speed, 3, "forced job preserves simulation speed")
	_assert_equal(game.active_tool, "select", "forced job preserves active tool")
	_assert_equal(game.selected_resident_id, selected_before, "forced job preserves selection")
	var checklist_guidance := game.player_orders.checklist.text.to_lower()
	_assert_true("manual orders" in checklist_guidance and "draft" in checklist_guidance and "force" in checklist_guidance, "Help checklist covers manual control")
	_assert_true(_node_text_contains(game.player_orders.root, "right-click"), "control reference exposes the contextual right-click gesture")
	game.player_orders.help_button.pressed.emit()
	_assert_true(game.player_orders.is_help_open(), "Help can display the manual-order guidance")
	_assert_true("draft" in game.player_orders.checklist.text.to_lower(), "visible Help retains draft guidance")
	_dispose(game)


func _test_manual_order_save_compatibility() -> void:
	_assert_equal(SaveLoad.SAVE_VERSION, 1, "manual orders remain an extension of save schema one")
	var source := _manual_game()
	var mover: VaultResident = source.residents[0]
	var worker: VaultResident = source.residents[1]
	var destination := Vector2i(26, 18)
	var dig_target := Vector2i(16, 12)
	source.select_resident(mover.resident_id)
	_assert_true(source.toggle_resident_draft(mover.resident_id), "save fixture drafts its mover")
	_assert_true(source.issue_context_order(destination), "save fixture records a pending move")
	_queue_dig_for_manual_test(source, dig_target)
	source.select_resident(worker.resident_id)
	_assert_true(source.issue_context_order(dig_target), "save fixture records a forced job")
	var snapshot := source.create_snapshot()
	_assert_equal(snapshot.residents[0].drafted, true, "snapshot writes drafted state")
	_assert_equal(snapshot.residents[0].manual_destination, [destination.x, destination.y], "snapshot writes an exact manual destination")
	_assert_true(snapshot.residents[0].forced_order.is_empty(), "manual mover has no forced-job payload")
	_assert_equal(snapshot.residents[1].drafted, false, "forced worker remains undrafted in the snapshot")
	_assert_equal(snapshot.residents[1].manual_destination, [], "forced worker has no move payload")
	_assert_variants_equal(
		{
			"type": JobSystem.JobType.DIG,
			"target": [dig_target.x, dig_target.y],
			"building_id": -1,
		},
		snapshot.residents[1].forced_order,
		"snapshot writes the exact forced job descriptor",
	)

	var loaded := _spawn_game()
	_assert_true(loaded.apply_snapshot(snapshot), "manual movement and forced work load from schema one")
	var loaded_mover: VaultResident = loaded.residents[0]
	var loaded_worker: VaultResident = loaded.residents[1]
	_assert_true(loaded_mover.drafted and loaded_mover.has_manual_move_order(), "load restores the drafted resident's pending move")
	_assert_equal(loaded_mover.manual_destination, destination, "load restores the exact move destination")
	_assert_true(loaded_worker.is_forced_job, "load restores the forced-job marker")
	var restored_job := loaded.job_system._find_job(loaded_worker.current_job_id)
	_assert_equal(restored_job.get("type"), JobSystem.JobType.DIG, "load restores the forced job type")
	_assert_equal(restored_job.get("target"), dig_target, "load restores the forced job target")
	_assert_equal(restored_job.get("reserved_by"), loaded_worker.resident_id, "load restores the forced reservation")
	_dispose(loaded)

	var legacy := snapshot.duplicate(true)
	for entry: Dictionary in legacy.residents:
		entry.erase("drafted")
		entry.erase("manual_destination")
		entry.erase("forced_order")
	var legacy_loaded := _spawn_game()
	_assert_true(legacy_loaded.apply_snapshot(legacy), "legacy schema-one residents without manual fields still load")
	for resident: VaultResident in legacy_loaded.residents:
		_assert_false(resident.drafted, "%s defaults to undrafted" % resident.resident_name)
		_assert_false(resident.has_manual_move_order(), "%s defaults to no manual move" % resident.resident_name)
		_assert_false(resident.is_forced_job, "%s defaults to no forced work" % resident.resident_name)
		_assert_true(resident.forced_order.is_empty(), "%s defaults to an empty forced descriptor" % resident.resident_name)
	_dispose(legacy_loaded)

	var malformed_payloads := [
		[0, "drafted", "true"],
		[0, "manual_destination", null],
		[0, "manual_destination", [destination.x]],
		[0, "manual_destination", [float(destination.x) + 0.5, destination.y]],
		[0, "manual_destination", [0, 0]],
		[1, "forced_order", []],
		[1, "forced_order", {"type": 999, "target": [dig_target.x, dig_target.y], "building_id": -1}],
		[1, "forced_order", {"type": JobSystem.JobType.DIG, "target": ["16", dig_target.y], "building_id": -1}],
		[1, "forced_order", {"type": JobSystem.JobType.DIG, "target": [0, 0], "building_id": -1}],
	]
	for malformed: Array in malformed_payloads:
		var target := _spawn_game()
		var stable_snapshot := target.create_snapshot()
		var invalid := snapshot.duplicate(true)
		invalid.residents[int(malformed[0])][malformed[1]] = malformed[2]
		_assert_false(target.apply_snapshot(invalid), "malformed manual payload is rejected: %s" % str(malformed))
		_assert_variants_equal(stable_snapshot, target.create_snapshot(), "rejected manual payload leaves the active wing unchanged")
		_dispose(target)

	var supply_source := _manual_game()
	var hatch_worker: VaultResident = supply_source.residents[0]
	supply_source.breach_system.advance(0.0, BreachSystem.WARNING_AT_SECONDS)
	supply_source.acknowledge_breach_warning(false)
	supply_source.select_resident(hatch_worker.resident_id)
	_assert_forced_job(supply_source, hatch_worker, BreachSystem.HATCH_CELL, JobSystem.JobType.SUPPLY_BREACH, "save fixture forces hatch supply")
	var forced_supply_snapshot := supply_source.create_snapshot()
	for invalid_supply: Variant in [null, {}, "invalid", 4]:
		var supply_target := _spawn_game()
		var supply_stable := supply_target.create_snapshot()
		var invalid := forced_supply_snapshot.duplicate(true)
		invalid.jobs.breach_supply = invalid_supply
		_assert_false(supply_target.apply_snapshot(invalid), "non-array forced hatch-supply payload is rejected")
		_assert_variants_equal(supply_stable, supply_target.create_snapshot(), "rejected hatch-supply payload is atomic")
		_dispose(supply_target)
	_dispose(supply_source)

	var patch_source := _manual_game()
	hatch_worker = patch_source.residents[0]
	patch_source.breach_system.advance(0.0, BreachSystem.WARNING_AT_SECONDS)
	patch_source.acknowledge_breach_warning(false)
	_assert_equal(patch_source.breach_system.add_delivery(BreachSystem.PATCH_COST), BreachSystem.PATCH_COST, "save fixture supplies the hatch")
	patch_source.job_system.advance(0.0)
	patch_source.select_resident(hatch_worker.resident_id)
	_assert_forced_job(patch_source, hatch_worker, BreachSystem.HATCH_CELL, JobSystem.JobType.PATCH_BREACH, "save fixture forces hatch patch work")
	var forced_patch_snapshot := patch_source.create_snapshot()
	for invalid_patch: Variant in [null, {}, "invalid", 1]:
		var patch_target := _spawn_game()
		var patch_stable := patch_target.create_snapshot()
		var invalid := forced_patch_snapshot.duplicate(true)
		invalid.jobs.breach_patch = invalid_patch
		_assert_false(patch_target.apply_snapshot(invalid), "non-array forced hatch-patch payload is rejected")
		_assert_variants_equal(patch_stable, patch_target.create_snapshot(), "rejected hatch-patch payload is atomic")
		_dispose(patch_target)
	_dispose(patch_source)

	source.new_game(false)
	for resident: VaultResident in source.residents:
		_assert_false(resident.drafted, "New Wing resets %s to autonomous control" % resident.resident_name)
		_assert_false(resident.has_manual_move_order(), "New Wing clears %s's move order" % resident.resident_name)
		_assert_false(resident.is_forced_job, "New Wing clears %s's forced order" % resident.resident_name)
	_dispose(source)


func _manual_game() -> VaultGame:
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
	return game


func _queue_dig_for_manual_test(game: VaultGame, target: Vector2i) -> void:
	_assert_true(game.map_grid.queue_dig(target), "test queues reachable excavation at %s" % target)
	game.job_system.queue_dig(target)


func _find_job_of_type(game: VaultGame, type: int) -> Dictionary:
	for job: Dictionary in game.job_system.jobs:
		if int(job.get("type", -1)) == type and not bool(job.get("done", false)):
			return job
	return {}


func _send_manual_key(game: VaultGame, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	game._unhandled_input(event)


func _roster_contains(game: VaultGame, token: String) -> bool:
	for child: Node in game.player_orders.roster_box.get_children():
		if child is Button and token in (child as Button).text:
			return true
	return false


func _node_text_contains(node: Node, token: String) -> bool:
	var normalized_token := token.to_lower()
	if node is Label and normalized_token in (node as Label).text.to_lower():
		return true
	if node is Button and normalized_token in (node as Button).text.to_lower():
		return true
	if node is RichTextLabel and normalized_token in (node as RichTextLabel).text.to_lower():
		return true
	for child: Node in node.get_children():
		if _node_text_contains(child, normalized_token):
			return true
	return false


func _assert_forced_job(game: VaultGame, resident: VaultResident, cell: Vector2i, expected_type: int, message: String) -> bool:
	var accepted := game.issue_context_order(cell)
	_assert_true(accepted, message)
	if not accepted:
		return false
	_assert_true(resident.is_forced_job, "%s marks the assignment forced" % message)
	_assert_equal(resident.current_job_type, expected_type, "%s chooses the contextual job type" % message)
	var job := game.job_system._find_job(resident.current_job_id)
	_assert_false(job.is_empty(), "%s creates or finds an active job" % message)
	if job.is_empty():
		return false
	_assert_equal(job.get("target"), cell, "%s binds the exact clicked cell" % message)
	_assert_equal(job.get("reserved_by"), resident.resident_id, "%s reserves only for the selected resident" % message)
	var work_type := game.job_system.get_work_type_for_job(expected_type)
	_assert_equal(resident.get_work_priority(work_type), VaultResident.PRIORITY_DISABLED, "%s bypasses OFF without mutating it" % message)
	return true
