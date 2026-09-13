extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SAVE_TEST_PATH := "user://headless_work_priorities.json"

var _assertion_count := 0
var _failure_count := 0
var _case_count := 0
var _failed_case_count := 0
var _current_case := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_run_case("work priority values, defaults, and cycling match the contract", _test_priority_model)
	_run_case("resident priorities outrank ordinary job kinds", _test_ordinary_priority_order)
	_run_case("ordinary ties retain kind, distance, and job-id ordering", _test_ordinary_tie_breaks)
	_run_case("worker priority outranks distance and supports specialization", _test_worker_priority_and_specialization)
	_run_case("turning work off releases jobs and refunds carried salvage", _test_off_release_and_refund)
	_run_case("urgent hatch work overrides ranks but still respects off", _test_breach_priority_override)
	_run_case("the work board edits all residents safely while paused", _test_work_priorities_board)
	_run_case("numeric, legacy, and missing work settings load compatibly", _test_save_round_trip_and_legacy_migration)
	_run_case("malformed work priority snapshots are rejected atomically", _test_malformed_save_rejection)

	print("")
	if _failure_count == 0:
		print("WORK PRIORITIES TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("WORK PRIORITIES TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
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


func _test_priority_model() -> void:
	_assert_equal(VaultResident.WORK_TYPES, ["dig", "haul", "craft", "cook"], "the board has exactly four canonical work types")
	_assert_equal(VaultResident.PRIORITY_DISABLED, 0, "zero disables a work type")
	_assert_equal(VaultResident.PRIORITY_HIGHEST, 1, "one is the highest priority")
	_assert_equal(VaultResident.PRIORITY_LOWEST, 4, "four is the lowest enabled priority")
	_assert_equal(VaultResident.DEFAULT_WORK_PRIORITY, 3, "legacy and missing settings default to priority three")

	var game := _spawn_game()
	for resident: VaultResident in game.residents:
		for work_type: String in VaultResident.WORK_TYPES:
			_assert_equal(resident.get_work_priority(work_type), 3, "%s starts with %s at priority three" % [resident.resident_name, work_type])
			_assert_true(bool(resident.work_allowed[work_type]), "%s starts eligible for %s" % [resident.resident_name, work_type])

	var resident: VaultResident = game.residents[0]
	_assert_equal(game.cycle_work_priority(resident.resident_id, "dig"), 4, "three cycles to four")
	_assert_equal(game.cycle_work_priority(resident.resident_id, "dig"), 0, "four cycles to off")
	_assert_equal(resident.get_work_priority_label("dig"), "OFF", "disabled work uses an explicit off label")
	_assert_false(bool(resident.work_allowed.dig), "cycling off updates the compatibility permission")
	_assert_equal(game.cycle_work_priority(resident.resident_id, "dig"), 1, "off cycles to highest")
	_assert_equal(game.cycle_work_priority(resident.resident_id, "dig"), 2, "one cycles to two")
	_assert_equal(game.cycle_work_priority(resident.resident_id, "dig"), 3, "two cycles back to the default")
	_assert_false(game.set_work_priority(resident.resident_id, "dig", -1), "priority below off is rejected")
	_assert_false(game.set_work_priority(resident.resident_id, "dig", 5), "priority below the supported rank is rejected")
	_assert_false(game.set_work_priority(resident.resident_id, "repair", 1), "unknown work types are rejected")
	_assert_false(game.set_work_priority(999, "dig", 1), "unknown residents are rejected")
	_assert_equal(game.cycle_work_priority(999, "dig"), -1, "invalid cycle requests return the failure sentinel")
	_assert_equal(resident.get_work_priority("dig"), 3, "invalid requests do not mutate the resident")
	_dispose(game)


func _test_ordinary_priority_order() -> void:
	var scenarios := [
		[1, 4, JobSystem.JobType.DIG, "high-priority Dig beats intrinsically earlier Haul"],
		[4, 1, JobSystem.JobType.HAUL_RUBBLE, "high-priority Haul beats Dig"],
		[3, 3, JobSystem.JobType.HAUL_RUBBLE, "equal ranks retain the intrinsic Haul-before-Dig order"],
	]
	for scenario: Array in scenarios:
		var game := _spawn_game()
		_prepare_residents_for_work(game)
		var resident: VaultResident = game.residents[0]
		resident.set_work_priority("dig", int(scenario[0]))
		resident.set_work_priority("haul", int(scenario[1]))
		_queue_dig(game, MapGrid.CHAMBER.position + Vector2i.LEFT)
		game.job_system.queue_rubble(resident.get_cell(game.map_grid), 3)
		game.job_system.advance(0.0)
		_assert_equal(resident.current_job_type, int(scenario[2]), str(scenario[3]))
		_dispose(game)


func _test_ordinary_tie_breaks() -> void:
	var distance_game := _spawn_game()
	_prepare_residents_for_work(distance_game)
	var resident: VaultResident = distance_game.residents[0]
	resident.set_work_priority("dig", 2)
	var far_target := Vector2i(MapGrid.CHAMBER.position.x - 1, MapGrid.CHAMBER.end.y - 2)
	var near_target := Vector2i(MapGrid.CHAMBER.position.x - 1, resident.get_cell(distance_game.map_grid).y)
	_queue_dig(distance_game, far_target)
	_queue_dig(distance_game, near_target)
	distance_game.job_system.advance(0.0)
	var claimed := distance_game.job_system._find_job(resident.current_job_id)
	_assert_false(claimed.is_empty(), "a reachable equal-priority Dig job is claimed")
	_assert_equal(claimed.get("target"), near_target, "distance breaks a same-kind priority tie")
	_dispose(distance_game)

	var id_game := _spawn_game()
	_prepare_residents_for_work(id_game)
	resident = id_game.residents[0]
	resident.set_work_priority("dig", 2)
	var first_target := Vector2i(MapGrid.CHAMBER.position.x - 1, resident.get_cell(id_game.map_grid).y - 1)
	var second_target := Vector2i(MapGrid.CHAMBER.position.x - 1, resident.get_cell(id_game.map_grid).y + 1)
	_queue_dig(id_game, first_target)
	_queue_dig(id_game, second_target)
	id_game.job_system.advance(0.0)
	claimed = id_game.job_system._find_job(resident.current_job_id)
	_assert_false(claimed.is_empty(), "an equal-distance Dig job is claimed")
	_assert_equal(claimed.get("target"), first_target, "lower job id breaks an equal-distance tie")
	_dispose(id_game)


func _test_worker_priority_and_specialization() -> void:
	var scarce_game := _spawn_game()
	_prepare_residents_for_work(scarce_game)
	var ari: VaultResident = scarce_game.residents[0]
	var bo: VaultResident = scarce_game.residents[1]
	ari.set_work_priority("haul", 4)
	bo.set_work_priority("haul", 1)
	scarce_game.job_system.queue_rubble(ari.get_cell(scarce_game.map_grid), 3)
	scarce_game.job_system.advance(0.0)
	_assert_equal(bo.current_job_type, JobSystem.JobType.HAUL_RUBBLE, "the higher-priority worker wins scarce work despite being farther away")
	_assert_equal(ari.current_job_id, -1, "the nearer lower-priority worker does not reserve the scarce job")
	_dispose(scarce_game)

	var worker_tie_game := _spawn_game()
	_prepare_residents_for_work(worker_tie_game)
	ari = worker_tie_game.residents[0]
	bo = worker_tie_game.residents[1]
	ari.set_work_priority("haul", 2)
	bo.set_work_priority("haul", 2)
	worker_tie_game.job_system.queue_rubble(bo.get_cell(worker_tie_game.map_grid), 3)
	worker_tie_game.job_system.advance(0.0)
	_assert_equal(ari.current_job_type, JobSystem.JobType.HAUL_RUBBLE, "lower resident ID resolves an equal worker-priority claim")
	_assert_equal(bo.current_job_id, -1, "the nearer equal-priority resident does not bypass the resident-ID tie-break")
	_dispose(worker_tie_game)

	var specialist_game := _spawn_game()
	_prepare_residents_for_work(specialist_game)
	ari = specialist_game.residents[0]
	bo = specialist_game.residents[1]
	ari.set_work_priority("dig", 1)
	ari.set_work_priority("haul", 4)
	bo.set_work_priority("dig", 4)
	bo.set_work_priority("haul", 1)
	_queue_dig(specialist_game, MapGrid.CHAMBER.position + Vector2i.LEFT)
	specialist_game.job_system.queue_rubble(ari.get_cell(specialist_game.map_grid), 3)
	specialist_game.job_system.advance(0.0)
	_assert_equal(ari.current_job_type, JobSystem.JobType.DIG, "the Dig specialist claims excavation")
	_assert_equal(bo.current_job_type, JobSystem.JobType.HAUL_RUBBLE, "the Haul specialist claims salvage")
	_dispose(specialist_game)


func _test_off_release_and_refund() -> void:
	var game := _spawn_game()
	_prepare_residents_for_work(game)
	var resident: VaultResident = game.residents[0]
	resident.set_work_priority("haul", 1)
	var blueprint_cell := Vector2i(MapGrid.CHAMBER.end.x - 2, MapGrid.CHAMBER.end.y - 2)
	_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, blueprint_cell), "refund scenario places a reachable blueprint")
	var initial_salvage := game.food_system.salvage
	var supply_job := _find_job_of_type(game, JobSystem.JobType.SUPPLY_BUILD)
	_assert_false(supply_job.is_empty(), "blueprint creates a supply job")
	for _step in 80:
		game.job_system.advance(VaultGame.SIMULATION_TICK)
		if int(supply_job.get("in_transit", 0)) > 0:
			break
	var carried := int(supply_job.get("in_transit", 0))
	_assert_true(carried > 0, "hauler picks up blueprint salvage before the priority changes")
	_assert_equal(game.food_system.salvage, initial_salvage - carried, "pickup removes exactly the carried amount")
	_assert_equal(supply_job.get("reserved_by"), resident.resident_id, "in-flight supply remains reserved by its hauler")
	var active_job_id := resident.current_job_id
	_assert_true(game.set_work_priority(resident.resident_id, "haul", 4), "an active enabled priority can be lowered")
	_assert_equal(resident.current_job_id, active_job_id, "enabled-to-enabled changes do not interrupt current work")
	_assert_equal(supply_job.get("reserved_by"), resident.resident_id, "enabled-to-enabled changes retain the reservation")

	_assert_true(game.set_work_priority(resident.resident_id, "haul", VaultResident.PRIORITY_DISABLED), "Haul can be turned off while work is active")
	_assert_equal(resident.current_job_id, -1, "turning the active category off releases the resident")
	_assert_equal(resident.carrying, 0, "released resident no longer carries salvage")
	_assert_equal(supply_job.get("in_transit"), 0, "released supply job clears its in-transit amount")
	_assert_equal(supply_job.get("reserved_by"), -1, "released supply job becomes claimable")
	_assert_equal(game.food_system.salvage, initial_salvage, "all in-flight salvage is refunded exactly once")
	game.job_system.advance(0.0)
	_assert_equal(resident.current_job_id, -1, "off work is not reclaimed on the next scheduler pass")
	_assert_equal(game.food_system.salvage, initial_salvage, "subsequent passes do not duplicate the refund")

	_assert_true(game.set_work_priority(resident.resident_id, "haul", 3), "Haul can be re-enabled at the default rank")
	game.job_system.advance(0.0)
	_assert_equal(resident.current_job_type, JobSystem.JobType.SUPPLY_BUILD, "re-enabled Haul can claim the waiting supply job")
	_dispose(game)


func _test_breach_priority_override() -> void:
	var game := _spawn_game()
	_prepare_residents_for_work(game)
	var resident: VaultResident = game.residents[0]
	resident.set_work_priority("dig", 1)
	_queue_dig(game, MapGrid.CHAMBER.position + Vector2i.LEFT)
	game.job_system.advance(0.0)
	_assert_equal(resident.current_job_type, JobSystem.JobType.DIG, "resident starts ordinary high-priority excavation")

	game.breach_system.advance(0.0, BreachSystem.WARNING_AT_SECONDS)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.WARNING, "test enters the hatch warning")
	_assert_equal(resident.current_job_id, -1, "warning releases ordinary work before emergency assignment")
	_assert_equal(game.job_system.get_breach_response_status(), "BLOCKED · ENABLE HAUL", "off Haul remains an emergency blocker")

	_assert_true(game.set_work_priority(resident.resident_id, "haul", 4), "lowest numbered Haul rank can still be enabled")
	game.job_system.advance(0.0)
	_assert_equal(resident.current_job_type, JobSystem.JobType.SUPPLY_BREACH, "urgent Haul overrides priority-one Dig")
	_assert_true(game.set_work_priority(resident.resident_id, "haul", 0), "turning emergency Haul off releases it")
	_assert_equal(resident.current_job_id, -1, "disabled emergency assignment is released")

	_assert_equal(game.breach_system.add_delivery(BreachSystem.PATCH_COST), BreachSystem.PATCH_COST, "test supplies the emergency patch directly")
	_assert_equal(game.job_system.get_breach_response_status(), "BLOCKED · ENABLE CRAFT", "off Craft remains a post-delivery blocker")
	_assert_true(game.set_work_priority(resident.resident_id, "craft", 4), "lowest Craft rank can still be enabled")
	game.job_system.advance(0.0)
	_assert_equal(resident.current_job_type, JobSystem.JobType.PATCH_BREACH, "urgent Craft overrides priority-one Dig")
	_dispose(game)


func _test_work_priorities_board() -> void:
	var game := _spawn_game()
	var orders: PlayerOrders = game.player_orders
	orders.refresh()
	_assert_true(orders.work_priorities_panel != null, "HUD builds a dedicated work-priorities panel")
	_assert_true(orders.work_priorities_button != null and "PRIORITIES" in orders.work_priorities_button.text, "roster exposes the board entry point")
	_assert_false(orders.is_work_priorities_open(), "work board starts closed")
	_assert_equal(orders.work_priority_buttons.size(), game.residents.size() * VaultResident.WORK_TYPES.size(), "board contains a four-by-four matrix")
	for resident: VaultResident in game.residents:
		for work_type: String in VaultResident.WORK_TYPES:
			var initial_button := orders.get_work_priority_button(resident.resident_id, work_type)
			_assert_true(initial_button != null, "%s/%s has a matrix cell" % [resident.resident_name, work_type])
			if initial_button != null:
				_assert_equal(initial_button.text, "3", "%s/%s displays its default rank" % [resident.resident_name, work_type])

	game.begin_shift()
	game.user_paused = true
	game.set_tool("dig")
	var original_selected := game.selected_resident_id
	_send_key(game, KEY_P)
	_assert_true(orders.is_work_priorities_open(), "P opens the work board")
	_assert_true(game.user_paused, "opening the board does not resume a paused shift")
	_assert_equal(game.active_tool, "dig", "opening the board preserves the active map tool")
	_assert_equal(game.selected_resident_id, original_selected, "opening the board preserves selection")
	_assert_true(_work_board_focus_is_trapped(orders), "all Tab and directional focus links remain inside the modal")

	var ari: VaultResident = game.residents[0]
	var ari_dig := orders.get_work_priority_button(ari.resident_id, "dig")
	var priority_before_modal_space := ari.get_work_priority("dig")
	_send_gui_key(game, KEY_SPACE)
	_assert_false(game.user_paused, "Space keeps its global pause behavior while the board owns button focus")
	_assert_true(orders.is_work_priorities_open(), "Space does not dismiss the open priorities board")
	_assert_equal(ari.get_work_priority("dig"), priority_before_modal_space, "Space does not activate the focused priority cell")
	_send_gui_key(game, KEY_SPACE)
	_assert_true(game.user_paused, "a second Space pauses again while the board remains open")
	var camera_before_modal_input := game.world_camera.position
	game._dragging_camera = true
	Input.action_press("camera_right")
	game._update_camera(0.5)
	Input.action_release("camera_right")
	_assert_equal(game.world_camera.position, camera_before_modal_input, "WASD cannot pan the camera behind the modal")
	_assert_false(game._dragging_camera, "opening the modal cancels an in-progress camera drag")
	_assert_true(ari_dig != null and "1 → 2 → 3 → 4 → OFF" in ari_dig.tooltip_text, "matrix cell documents the complete cycle")
	ari_dig.pressed.emit()
	orders.refresh()
	_assert_equal(ari.get_work_priority("dig"), 4, "matrix click edits the intended resident and category")
	_assert_equal(ari_dig.text, "4", "matrix cell refreshes immediately while paused")
	_assert_equal(ari.get_work_priority("haul"), 3, "matrix click leaves the resident's other categories unchanged")
	_assert_equal(game.residents[1].get_work_priority("dig"), 3, "matrix click leaves other residents unchanged")
	ari_dig.pressed.emit()
	orders.refresh()
	_assert_equal(ari.get_work_priority("dig"), 0, "matrix cycles four to off")
	_assert_equal(ari_dig.text, "OFF", "matrix labels disabled work explicitly")

	var deceased: VaultResident = game.residents[3]
	deceased.kill()
	orders.refresh()
	var focus_after_rebuild := game.get_viewport().gui_get_focus_owner()
	_assert_true(focus_after_rebuild != null and orders.work_priorities_overlay.is_ancestor_of(focus_after_rebuild), "rebuilding rows after a death keeps keyboard focus inside the open modal")
	for work_type: String in VaultResident.WORK_TYPES:
		var deceased_button := orders.get_work_priority_button(deceased.resident_id, work_type)
		_assert_true(deceased_button != null and deceased_button.disabled, "deceased row disables %s editing" % work_type)

	_send_key(game, KEY_ESCAPE)
	_assert_false(orders.is_work_priorities_open(), "Escape closes the work board")
	_assert_equal(game.active_tool, "dig", "board Escape does not also cancel the active map tool")
	var priority_before_space := ari.get_work_priority("dig")
	var paused_before_space := game.user_paused
	_send_gui_key(game, KEY_SPACE)
	_assert_equal(game.user_paused, not paused_before_space, "Space still toggles pause after the board closes")
	_assert_false(orders.is_work_priorities_open(), "Space does not reactivate the priorities opener after a P/Escape close")
	_assert_equal(ari.get_work_priority("dig"), priority_before_space, "Space after close does not cycle the formerly focused priority cell")
	ari.kill()
	orders.refresh()
	_send_key(game, KEY_P)
	_assert_true(orders.is_work_priorities_open(), "P can reopen the board")
	_assert_equal(game.get_viewport().gui_get_focus_owner(), orders.get_work_priority_button(game.residents[1].resident_id, "dig"), "opening skips a deceased first resident and focuses the next live cell")
	game.breach_system.advance(0.0, BreachSystem.WARNING_AT_SECONDS)
	orders.refresh()
	_assert_false(orders.is_work_priorities_open(), "priority incident closes the ordinary-work board")
	_assert_true(orders.breach_warning_panel.visible, "breach warning remains the foreground modal")
	_assert_true(orders.work_priorities_button.disabled, "board entry point is disabled behind an unacknowledged warning")
	_assert_equal(game.get_viewport().gui_get_focus_owner(), orders.breach_resume_button, "breach warning initially focuses its Resume action")
	orders.show_work_priorities(false)
	_assert_equal(game.get_viewport().gui_get_focus_owner(), orders.breach_resume_button, "closing an already closed work board preserves warning-modal focus")
	_send_key(game, KEY_P)
	_assert_false(orders.is_work_priorities_open(), "P cannot open the board behind the warning")
	_assert_true(game.user_paused, "board and warning interactions never resume the shift")
	_dispose(game)


func _test_save_round_trip_and_legacy_migration() -> void:
	_remove_test_save()
	var original := _spawn_game()
	var expected := [
		[1, 2, 3, 4],
		[4, 3, 2, 1],
		[0, 1, 4, 2],
		[2, 0, 1, 3],
	]
	for resident_index in original.residents.size():
		var resident: VaultResident = original.residents[resident_index]
		for work_index in VaultResident.WORK_TYPES.size():
			original.set_work_priority(resident.resident_id, VaultResident.WORK_TYPES[work_index], int(expected[resident_index][work_index]))
	_assert_true(original.save_game(false, SAVE_TEST_PATH), "numeric matrix writes to the isolated save")
	var loaded := _spawn_game()
	_assert_true(loaded.load_game(SAVE_TEST_PATH), "numeric matrix loads into a fresh game")
	_assert_matrix(loaded, expected, "round-trip")
	var saved_resident: Dictionary = loaded.create_snapshot().residents[2]
	_assert_equal(saved_resident.work_priorities.dig, 0, "canonical save stores off as numeric zero")
	_assert_false(bool(saved_resident.work_allowed.dig), "compatibility permission agrees with numeric off")
	_assert_equal(saved_resident.work_priorities.craft, 4, "canonical save retains the lowest enabled rank")
	_dispose(loaded)
	_dispose(original)
	_remove_test_save()

	var source := _spawn_game()
	var legacy_snapshot: Dictionary = source.create_snapshot().duplicate(true)
	for entry: Dictionary in legacy_snapshot.residents:
		entry.erase("work_priorities")
		entry.work_allowed = {"dig": true, "haul": true, "craft": true, "cook": true}
	legacy_snapshot.residents[0].work_allowed = {"dig": true, "haul": false, "craft": true, "cook": false}
	var legacy_loaded := _spawn_game()
	_assert_true(legacy_loaded.apply_snapshot(legacy_snapshot), "legacy boolean permissions remain loadable")
	_assert_equal(legacy_loaded.residents[0].get_work_priority("dig"), 3, "legacy true migrates to priority three")
	_assert_equal(legacy_loaded.residents[0].get_work_priority("haul"), 0, "legacy false migrates to off")
	_assert_equal(legacy_loaded.residents[0].get_work_priority("craft"), 3, "each legacy true migrates independently")
	_assert_equal(legacy_loaded.residents[0].get_work_priority("cook"), 0, "each legacy false migrates independently")
	_assert_equal(legacy_loaded.residents[1].get_work_priority("haul"), 3, "legacy enabled defaults are uniform across residents")
	_dispose(legacy_loaded)

	var missing_snapshot: Dictionary = source.create_snapshot().duplicate(true)
	for entry: Dictionary in missing_snapshot.residents:
		entry.erase("work_priorities")
		entry.erase("work_allowed")
	var missing_loaded := _spawn_game()
	_assert_true(missing_loaded.apply_snapshot(missing_snapshot), "schema-one residents with no work fields remain loadable")
	for resident: VaultResident in missing_loaded.residents:
		for work_type: String in VaultResident.WORK_TYPES:
			_assert_equal(resident.get_work_priority(work_type), 3, "missing %s/%s defaults to priority three" % [resident.resident_name, work_type])
	_dispose(missing_loaded)
	_dispose(source)


func _test_malformed_save_rejection() -> void:
	var source := _spawn_game()
	var valid_snapshot: Dictionary = source.create_snapshot()
	var target := _spawn_game()
	target.set_work_priority(target.residents[0].resident_id, "dig", 1)
	var stable_snapshot: Dictionary = target.create_snapshot()
	var malformed_priorities: Array = [
		[1, 2, 3, 4],
		{"dig": 1, "haul": 2, "craft": 3},
		{"dig": 1, "haul": 2, "craft": 3, "cook": 4, "repair": 1},
		{"dig": -1, "haul": 2, "craft": 3, "cook": 4},
		{"dig": 5, "haul": 2, "craft": 3, "cook": 4},
		{"dig": 1.5, "haul": 2, "craft": 3, "cook": 4},
		{"dig": "1", "haul": 2, "craft": 3, "cook": 4},
	]
	for malformed_priorities_payload: Variant in malformed_priorities:
		var malformed: Dictionary = valid_snapshot.duplicate(true)
		malformed.residents[0].work_priorities = malformed_priorities_payload
		_assert_false(target.apply_snapshot(malformed), "malformed canonical priority payload is rejected: %s" % str(malformed_priorities_payload))
		_assert_variants_equal(stable_snapshot, target.create_snapshot(), "rejected canonical payload leaves the active wing unchanged")

	var mismatched: Dictionary = valid_snapshot.duplicate(true)
	mismatched.residents[0].work_priorities.dig = 0
	mismatched.residents[0].work_allowed.dig = true
	_assert_false(target.apply_snapshot(mismatched), "canonical off cannot disagree with its compatibility permission")
	_assert_variants_equal(stable_snapshot, target.create_snapshot(), "permission mismatch is rejected atomically")

	var malformed_legacy: Dictionary = valid_snapshot.duplicate(true)
	malformed_legacy.residents[0].erase("work_priorities")
	malformed_legacy.residents[0].work_allowed = {"dig": "true", "haul": true, "craft": true, "cook": true}
	_assert_false(target.apply_snapshot(malformed_legacy), "legacy permissions reject non-boolean values")
	_assert_variants_equal(stable_snapshot, target.create_snapshot(), "malformed legacy data leaves the active wing unchanged")
	_dispose(target)
	_dispose(source)


func _prepare_residents_for_work(game: VaultGame) -> void:
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


func _queue_dig(game: VaultGame, target: Vector2i) -> void:
	_assert_true(game.map_grid.queue_dig(target), "test queues reachable excavation at %s" % target)
	game.job_system.queue_dig(target)


func _find_job_of_type(game: VaultGame, type: int) -> Dictionary:
	for job: Dictionary in game.job_system.jobs:
		if int(job.type) == type and not bool(job.get("done", false)):
			return job
	return {}


func _assert_matrix(game: VaultGame, expected: Array, context: String) -> void:
	for resident_index in game.residents.size():
		var resident: VaultResident = game.residents[resident_index]
		for work_index in VaultResident.WORK_TYPES.size():
			var work_type: String = VaultResident.WORK_TYPES[work_index]
			_assert_equal(
				resident.get_work_priority(work_type),
				int(expected[resident_index][work_index]),
				"%s keeps %s/%s" % [context, resident.resident_name, work_type],
			)


func _work_board_focus_is_trapped(orders: PlayerOrders) -> bool:
	var controls: Array[Control] = []
	for resident: VaultResident in orders.game.residents:
		if not resident.alive:
			continue
		for work_type: String in VaultResident.WORK_TYPES:
			var button := orders.get_work_priority_button(resident.resident_id, work_type)
			if button != null:
				controls.append(button)
	if orders.work_priorities_close_button != null:
		controls.append(orders.work_priorities_close_button)
	if controls.is_empty():
		return false
	for control: Control in controls:
		for neighbor_path: NodePath in [control.focus_previous, control.focus_next, control.focus_neighbor_left, control.focus_neighbor_top, control.focus_neighbor_right, control.focus_neighbor_bottom]:
			var neighbor := control.get_node_or_null(neighbor_path)
			if neighbor == null or not orders.work_priorities_overlay.is_ancestor_of(neighbor):
				return false
	return true


func _send_key(game: VaultGame, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	game._unhandled_input(event)


func _send_gui_key(game: VaultGame, keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		game.get_viewport().push_input(event)


func _spawn_game() -> VaultGame:
	var game := MAIN_SCENE.instantiate() as VaultGame
	if game != null:
		root.add_child(game)
	return game


func _dispose(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()


func _remove_test_save() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_TEST_PATH + suffix))


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


func _assert_variants_equal(expected: Variant, actual: Variant, message: String) -> void:
	_assertion_count += 1
	var difference := _first_variant_difference(expected, actual, "$")
	if not difference.is_empty():
		_fail(message, difference)


func _first_variant_difference(expected: Variant, actual: Variant, path: String) -> String:
	var expected_type := typeof(expected)
	var actual_type := typeof(actual)
	var expected_is_number := expected_type == TYPE_INT or expected_type == TYPE_FLOAT
	var actual_is_number := actual_type == TYPE_INT or actual_type == TYPE_FLOAT
	if expected_is_number and actual_is_number:
		if absf(float(expected) - float(actual)) <= 0.0001:
			return ""
		return "%s expected %s, got %s" % [path, str(expected), str(actual)]
	if expected_type != actual_type:
		return "%s expected type %d, got type %d" % [path, expected_type, actual_type]
	if expected_type == TYPE_DICTIONARY:
		var expected_dictionary: Dictionary = expected
		var actual_dictionary: Dictionary = actual
		if expected_dictionary.size() != actual_dictionary.size():
			return "%s expected %d keys, got %d" % [path, expected_dictionary.size(), actual_dictionary.size()]
		for key: Variant in expected_dictionary:
			if not actual_dictionary.has(key):
				return "%s is missing key %s" % [path, str(key)]
			var child_difference := _first_variant_difference(
				expected_dictionary[key],
				actual_dictionary[key],
				"%s.%s" % [path, str(key)],
			)
			if not child_difference.is_empty():
				return child_difference
		return ""
	if expected_type == TYPE_ARRAY:
		var expected_array: Array = expected
		var actual_array: Array = actual
		if expected_array.size() != actual_array.size():
			return "%s expected %d entries, got %d" % [path, expected_array.size(), actual_array.size()]
		for index in expected_array.size():
			var child_difference := _first_variant_difference(
				expected_array[index],
				actual_array[index],
				"%s[%d]" % [path, index],
			)
			if not child_difference.is_empty():
				return child_difference
		return ""
	if expected != actual:
		return "%s expected %s, got %s" % [path, str(expected), str(actual)]
	return ""


func _fail(message: String, detail: String) -> void:
	_failure_count += 1
	printerr("[FAIL] %s :: %s — %s" % [_current_case, message, detail])
