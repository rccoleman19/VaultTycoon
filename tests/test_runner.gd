extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SAVE_TEST_PATH := "user://headless_round_trip.json"
const BREACH_SAVE_TEST_PATH := "user://headless_breach_round_trip.json"
const OXYGEN_SAVE_TEST_PATH := "user://headless_oxygen_round_trip.json"
const POWER_SAVE_TEST_PATH := "user://headless_power_round_trip.json"
const ATOMIC_SAVE_TEST_PATH := "user://headless_atomic_save.json"

var _assertion_count := 0
var _failure_count := 0
var _case_count := 0
var _failed_case_count := 0
var _current_case := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_run_case("main scene boots with a sealed four-resident wing", _test_scene_boot_and_initial_state)
	_run_case("tool hotkeys and help match the documented controls", _test_tool_hotkeys_and_help)
	_run_case("manual work priorities arbitrate jobs across the crew", _test_work_priority_claiming)
	_run_case("work priorities persist and legacy permissions migrate", _test_work_priority_save_compatibility)
	_run_case("the work-priorities board edits crew without changing tools", _test_work_priorities_board)
	_run_case("dig orders complete through the job system", _test_dig_completion)
	_run_case("blueprints are supplied and constructed", _test_blueprint_build)
	_run_case("cancel previews and powered checklist match their actions", _test_order_preview_and_checklist)
	_run_case("power is allocated by supply and priority", _test_power_allocation)
	_run_case("fixed fixture priorities deterministically control brownout shedding", _test_fixed_power_priorities)
	_run_case("fixture recovery controls work immediately while paused", _test_fixture_recovery_controls_while_paused)
	_run_case("balanced power grids serve every enabled consumer", _test_balanced_power_grid_accounting)
	_run_case("power recovery can disable, deconstruct, or add capacity", _test_power_recovery_controls)
	_run_case("shed grow trays pause and resume production progress", _test_shed_production_progress)
	_run_case("living residents consume shared oxygen within hard bounds", _test_oxygen_consumption_and_clamping)
	_run_case("air recyclers require power and retain life-support priority", _test_air_recycler_power_and_rates)
	_run_case("critical oxygen damages only for exact exposure time", _test_oxygen_threshold_damage)
	_run_case("overbuilding can shed recycling and cascade into oxygen danger", _test_brownout_during_critical_air_recovery)
	_run_case("powered kitchens cook without a silent meal cap", _test_cooking_at_starting_stock)
	_run_case("breach warning triggers exactly once and pauses the shift", _test_breach_warning_interrupt)
	_run_case("breach blockers and urgent jobs drive the patch sequence", _test_breach_response_jobs)
	_run_case("a prepared response seals during grace without damage", _test_prepared_breach_survival)
	_run_case("a patch completed at 80 seconds prevents the hatch opening", _test_exact_open_boundary_patch)
	_run_case("an open breach drains shared oxygen only until sealed", _test_breach_oxygen_drain_and_seal)
	_run_case("active and legacy breach snapshots load safely", _test_breach_save_load_compatibility)
	_run_case("active, malformed, and legacy oxygen snapshots load safely", _test_oxygen_save_load_compatibility)
	_run_case("power controls round trip and legacy defaults load safely", _test_power_controls_save_load_compatibility)
	_run_case("day seven completes only at the exact boundary", _test_exact_day_boundary)
	_run_case("day-seven victory requires a sealed breathable wing", _test_day_seven_requires_sealed_breathable_wing)
	_run_case("save and load preserve a deterministic simulation", _test_save_load_round_trip)
	_run_case("interrupted save writes preserve the prior slot", _test_atomic_save_recovery)
	_run_case("an unmanaged wing fails before day seven", _test_unmanaged_loss)
	_run_case("the twelve-dig required path reaches day seven with recovery margin", _test_required_first_session_path)
	_run_case("the optional recreation path reaches a comfortable day-seven win", _test_player_order_survival_plan)
	_run_case("a managed wing survives to the day-seven win", _test_managed_day_seven_win)

	print("")
	if _failure_count == 0:
		print("HEADLESS TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("HEADLESS TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
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


func _test_scene_boot_and_initial_state() -> void:
	var game := _spawn_game()
	_assert_true(game != null, "main scene instantiated")
	if game == null:
		return

	_assert_true(game.is_inside_tree(), "main scene entered the SceneTree")
	_assert_true(game.get_node_or_null("MapGrid") != null, "MapGrid exists")
	_assert_true(game.get_node_or_null("BreachSystem") != null, "fixed pressure-hatch system exists")
	_assert_true(game.get_node_or_null("OxygenSystem") != null, "global vault oxygen system exists")
	_assert_true(game.get_node_or_null("JobSystem") != null, "JobSystem exists")
	_assert_true(game.get_node_or_null("PlayerOrders/Interface") != null, "player-order UI was built")
	_assert_equal(game.residents.size(), 4, "exactly four starting residents")
	_assert_equal(game.get_alive_count(), 4, "all starting residents are alive")
	for resident: VaultResident in game.residents:
		for work_type: String in VaultResident.WORK_TYPES:
			_assert_equal(resident.get_work_priority(work_type), VaultResident.DEFAULT_WORK_PRIORITY, "%s starts with %s at sensible normal priority" % [resident.resident_name, work_type])
	_assert_equal(game.buildings.size(), 3, "three emergency fixtures are present")
	_assert_equal(game.food_system.meals, FoodSystem.STARTING_MEALS, "new wing receives the tuned meal reserve")
	_assert_equal(game.food_system.raw_food, FoodSystem.STARTING_RAW_FOOD, "new wing receives the tuned raw-food reserve")
	_assert_equal(game.food_system.salvage, FoodSystem.STARTING_SALVAGE, "new wing receives the tuned salvage reserve")
	_assert_equal(FoodSystem.STARTING_MEALS, 12, "first-session kit starts with twelve meals")
	_assert_equal(FoodSystem.STARTING_RAW_FOOD, 4, "first-session kit starts with four raw food")
	_assert_equal(FoodSystem.STARTING_SALVAGE, 48, "first-session kit starts with forty-eight salvage")
	_assert_approximately(game.oxygen_system.oxygen, OxygenSystem.STARTING_OXYGEN, 0.0001, "new wing starts with full oxygen")
	_assert_true(game.tutorial_open, "opening briefing is visible")
	_assert_true(game.player_orders.briefing_overlay.visible, "opening checklist overlay is visible")
	_assert_true(game.is_simulation_paused(), "new wing starts paused")

	var expected_floor_count := MapGrid.CHAMBER.size.x * MapGrid.CHAMBER.size.y
	_assert_equal(game.map_grid.get_floor_cells().size(), expected_floor_count, "only the chamber is carved")
	_assert_equal(game.map_grid.get_tile(MapGrid.CHAMBER.position), MapGrid.Tile.FLOOR, "chamber corner is floor")
	_assert_equal(game.map_grid.get_tile(MapGrid.CHAMBER.end - Vector2i.ONE), MapGrid.Tile.FLOOR, "opposite chamber corner is floor")
	_assert_equal(
		game.map_grid.get_tile(MapGrid.CHAMBER.position + Vector2i.LEFT),
		MapGrid.Tile.ROCK,
		"rock seals the chamber's west wall",
	)
	_assert_equal(game.map_grid.get_tile(Vector2i.ZERO), MapGrid.Tile.ROCK, "map boundary remains rock")
	_assert_equal(game.map_grid.dig_marks.size(), 0, "new wing has no dig designations")
	_assert_equal(BreachSystem.HATCH_CELL, Vector2i(28, 15), "pressure hatch occupies its fixed chamber cell")
	_assert_true(game.map_grid.is_walkable(BreachSystem.HATCH_CELL), "pressure hatch is reachable across carved floor")
	_assert_true(game.get_building_at(BreachSystem.HATCH_CELL) == null, "pressure hatch is not a removable fixture")
	game.begin_shift()
	_assert_false(game.place_blueprint(VaultBuilding.Kind.BED, BreachSystem.HATCH_CELL), "pressure hatch rejects fixture blueprints")
	_dispose(game)


func _test_tool_hotkeys_and_help() -> void:
	var game := _spawn_game()
	_assert_true(_action_has_physical_key("tool_dig", KEY_E), "E is configured as the Dig hotkey")
	_assert_true(_action_has_physical_key("work_priorities", KEY_P), "P is configured as the work-priorities hotkey")
	for action in ["camera_left", "camera_right", "camera_up", "camera_down"]:
		_assert_false(_action_has_physical_key(action, KEY_E), "Dig hotkey does not overlap %s" % action)

	var pan_event := InputEventKey.new()
	pan_event.physical_keycode = KEY_D
	pan_event.pressed = true
	var dig_event := InputEventKey.new()
	dig_event.physical_keycode = KEY_E
	dig_event.pressed = true
	game._unhandled_input(dig_event)
	_assert_equal(game.active_tool, "select", "opening briefing blocks map-tool hotkeys behind its overlay")
	game.begin_shift()
	game._unhandled_input(pan_event)
	_assert_equal(game.active_tool, "select", "camera-right D does not select Dig")
	game._unhandled_input(dig_event)
	_assert_equal(game.active_tool, "dig", "configured E hotkey selects Dig")
	_assert_equal(
		game._tool_help("kitchen"),
		"NUTRIENT STATION: powered Cook work turns %d raw into %d meal (10 salvage, 2 power)." % [FoodSystem.COOK_INPUT, FoodSystem.COOK_OUTPUT],
		"nutrient help is derived from the simulated recipe",
	)
	game.set_tool("dig")
	game.status_message = "Transient order feedback"
	game.status_message_left = 0.0
	game.player_orders.refresh()
	_assert_true("hauled rubble yields 3 salvage" in game.player_orders.tool_status.text, "active-tool help returns after transient feedback expires")
	var elapsed_before_help := game.day_cycle.elapsed_seconds
	game.player_orders.help_button.pressed.emit()
	_assert_true(game.player_orders.is_help_open(), "Help reopens the live checklist after the shift begins")
	_assert_true(game.is_simulation_paused(), "reopened Help pauses simulation behind the overlay")
	_assert_false(game.user_paused, "Help does not overwrite the player's running pause state")
	_assert_equal(game.active_tool, "dig", "opening Help preserves the active map tool")
	_assert_equal(game.get_viewport().gui_get_focus_owner(), game.player_orders.briefing_close_button, "reopened Help focuses its close action")
	for control: Control in [game.player_orders.briefing_close_button, game.player_orders.briefing_load_button]:
		for neighbor_path: NodePath in [control.focus_previous, control.focus_next, control.focus_neighbor_left, control.focus_neighbor_top, control.focus_neighbor_right, control.focus_neighbor_bottom]:
			var neighbor := control.get_node_or_null(neighbor_path)
			_assert_true(neighbor != null and game.player_orders.briefing_overlay.is_ancestor_of(neighbor), "Help keeps keyboard focus inside its overlay")
	var camera_before_help_input := game.world_camera.position
	game._dragging_camera = true
	Input.action_press("camera_right")
	game._update_camera(0.5)
	Input.action_release("camera_right")
	_assert_equal(game.world_camera.position, camera_before_help_input, "WASD cannot pan the camera behind Help")
	_assert_false(game._dragging_camera, "opening Help cancels an in-progress camera drag")
	game._process(1.0)
	_assert_approximately(game.day_cycle.elapsed_seconds, elapsed_before_help, 0.0001, "simulation time remains frozen while Help is open")
	game.player_orders.briefing_close_button.pressed.emit()
	_assert_false(game.player_orders.is_help_open(), "Close Help dismisses the checklist")
	_assert_false(game.is_simulation_paused(), "closing Help resumes a previously running shift")
	game.user_paused = true
	game.player_orders.help_button.pressed.emit()
	var escape_event := InputEventKey.new()
	escape_event.physical_keycode = KEY_ESCAPE
	escape_event.pressed = true
	game._unhandled_input(escape_event)
	_assert_false(game.player_orders.is_help_open(), "Escape closes reopened Help")
	_assert_true(game.user_paused and game.is_simulation_paused(), "closing Help preserves a previously paused shift")
	_dispose(game)


func _test_work_priority_claiming() -> void:
	var game := _spawn_game()
	game.begin_shift()
	var target := MapGrid.CHAMBER.position + Vector2i.LEFT
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		for work_type: String in VaultResident.WORK_TYPES:
			resident.set_work_priority(work_type, VaultResident.PRIORITY_DISABLED)
	var low_priority: VaultResident = game.residents[0]
	var high_priority: VaultResident = game.residents[1]
	low_priority.position = game.map_grid.cell_to_world(MapGrid.CHAMBER.position)
	high_priority.position = game.map_grid.cell_to_world(MapGrid.CHAMBER.end - Vector2i.ONE)
	low_priority.set_work_priority("dig", VaultResident.PRIORITY_LOWEST)
	high_priority.set_work_priority("dig", VaultResident.PRIORITY_HIGHEST)
	_assert_true(game.map_grid.queue_dig(target), "scarce reachable excavation is designated")
	game.job_system.queue_dig(target)
	game.job_system.advance(0.0)
	_assert_equal(high_priority.current_job_type, JobSystem.JobType.DIG, "higher-priority digger claims before an earlier and closer low-priority digger")
	_assert_equal(low_priority.current_job_id, -1, "low-priority digger does not take the scarce job")
	var claimed_dig := game.job_system._find_job(high_priority.current_job_id)
	_assert_equal(int(claimed_dig.get("reserved_by", -1)), high_priority.resident_id, "scarce dig reservation names the high-priority worker")
	_dispose(game)

	game = _spawn_game()
	game.begin_shift()
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.set_work_priority("dig", VaultResident.PRIORITY_DISABLED)
	_assert_true(game.map_grid.queue_dig(target), "disabled-priority excavation is still a valid player order")
	game.job_system.queue_dig(target)
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	for resident: VaultResident in game.residents:
		_assert_true(resident.current_job_type != JobSystem.JobType.DIG, "%s never claims Disabled Dig work" % resident.resident_name)
	_assert_equal(game.job_system.get_queued_count(), 1, "Disabled work remains queued for later reprioritization")
	_assert_equal(int(game.job_system.jobs[0].reserved_by), -1, "Disabled work remains unreserved")
	_dispose(game)

	game = _spawn_game()
	game.begin_shift()
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		for work_type: String in VaultResident.WORK_TYPES:
			resident.set_work_priority(work_type, VaultResident.PRIORITY_DISABLED)
	var worker: VaultResident = game.residents[0]
	worker.set_work_priority("dig", VaultResident.PRIORITY_HIGHEST)
	worker.set_work_priority("haul", VaultResident.PRIORITY_LOWEST)
	_assert_true(game.map_grid.queue_dig(target), "preference fixture includes a reachable dig")
	game.job_system.queue_dig(target)
	game.job_system.queue_rubble(worker.get_cell(game.map_grid), 3)
	game.job_system.advance(0.0)
	_assert_equal(worker.current_job_type, JobSystem.JobType.DIG, "one colonist chooses priority-1 Dig over priority-4 Haul")
	game.breach_system.advance(0.0, BreachSystem.WARNING_AT_SECONDS)
	game.food_system.salvage = BreachSystem.PATCH_COST
	game.job_system.advance(0.0)
	_assert_equal(worker.current_job_type, JobSystem.JobType.SUPPLY_BREACH, "urgent hatch Haul overrides numbered ordinary-work priorities")
	_dispose(game)


func _test_work_priority_save_compatibility() -> void:
	var original := _spawn_game()
	var resident: VaultResident = original.residents[0]
	_assert_true(original.set_work_priority(resident.resident_id, "dig", 1), "Dig accepts priority 1")
	_assert_true(original.set_work_priority(resident.resident_id, "haul", 2), "Haul accepts priority 2")
	_assert_true(original.set_work_priority(resident.resident_id, "craft", 4), "Craft accepts priority 4")
	_assert_true(original.set_work_priority(resident.resident_id, "cook", VaultResident.PRIORITY_DISABLED), "Cook accepts Disabled")
	var active_snapshot := original.create_snapshot()
	_assert_variants_equal(
		{"dig": 1, "haul": 2, "craft": 4, "cook": 0},
		active_snapshot.residents[0].work_priorities,
		"active resident snapshot stores every numeric work priority",
	)
	_assert_false(bool(active_snapshot.residents[0].work_allowed.cook), "schema-one permission mirror stores Disabled Cook")

	var loaded := _spawn_game()
	_assert_true(loaded.apply_snapshot(active_snapshot), "numeric work-priority snapshot loads")
	var loaded_resident: VaultResident = loaded.get_resident_by_id(resident.resident_id)
	_assert_equal(loaded_resident.get_work_priority("dig"), 1, "Dig priority survives load")
	_assert_equal(loaded_resident.get_work_priority("haul"), 2, "Haul priority survives load")
	_assert_equal(loaded_resident.get_work_priority("craft"), 4, "Craft priority survives load")
	_assert_equal(loaded_resident.get_work_priority("cook"), 0, "Disabled Cook survives load")

	var legacy_snapshot: Dictionary = active_snapshot.duplicate(true)
	for entry: Dictionary in legacy_snapshot.residents:
		entry.erase("work_priorities")
	legacy_snapshot.residents[0].work_allowed = {"dig": true, "haul": false, "craft": true, "cook": false}
	_assert_true(loaded.apply_snapshot(legacy_snapshot), "legacy boolean permissions load without a priority map")
	loaded_resident = loaded.get_resident_by_id(resident.resident_id)
	_assert_equal(loaded_resident.get_work_priority("dig"), VaultResident.DEFAULT_WORK_PRIORITY, "legacy enabled work migrates to normal priority")
	_assert_equal(loaded_resident.get_work_priority("haul"), VaultResident.PRIORITY_DISABLED, "legacy disabled work migrates to Disabled")
	_assert_equal(loaded_resident.get_work_priority("craft"), VaultResident.DEFAULT_WORK_PRIORITY, "each legacy enabled category receives the normal default")
	_assert_equal(loaded_resident.get_work_priority("cook"), VaultResident.PRIORITY_DISABLED, "each legacy disabled category stays blocked")

	var stable_snapshot := loaded.create_snapshot()
	var out_of_range: Dictionary = active_snapshot.duplicate(true)
	out_of_range.residents[0].work_priorities.dig = 5
	_assert_false(loaded.apply_snapshot(out_of_range), "priority above 4 is rejected")
	_assert_variants_equal(stable_snapshot, loaded.create_snapshot(), "rejected priority range leaves the active wing unchanged")
	var nonnumeric: Dictionary = active_snapshot.duplicate(true)
	nonnumeric.residents[0].work_priorities.haul = "urgent"
	_assert_false(loaded.apply_snapshot(nonnumeric), "nonnumeric priority is rejected")
	_assert_variants_equal(stable_snapshot, loaded.create_snapshot(), "rejected priority type is atomic")
	var malformed_permission: Dictionary = active_snapshot.duplicate(true)
	malformed_permission.residents[0].work_allowed.cook = 0
	_assert_false(loaded.apply_snapshot(malformed_permission), "nonboolean legacy permission mirror is rejected")
	_assert_variants_equal(stable_snapshot, loaded.create_snapshot(), "rejected permission type is atomic")
	_dispose(loaded)
	_dispose(original)


func _test_work_priorities_board() -> void:
	var game := _spawn_game()
	game.begin_shift()
	game.set_speed(2)
	game.set_tool("dig")
	var orders := game.player_orders
	orders.refresh()
	_assert_equal(orders.command_grid.get_child_count(), 16, "Help does not displace or masquerade as a map tool")
	_assert_false(orders.command_grid.is_ancestor_of(orders.work_priorities_button), "priorities opener lives with the roster rather than the map tools")
	_assert_equal(orders.work_priority_buttons.size(), game.residents.size() * VaultResident.WORK_TYPES.size(), "board exposes one cell for every resident and work category")
	_assert_equal(orders.work_priorities_grid.columns, 5, "board contains Resident plus the four in-game work kinds")
	_assert_equal(orders.work_priorities_grid.get_child_count(), 25, "board has five headers and four complete resident rows")
	_assert_equal(orders.get_work_priority_button(1, "dig").text, "3", "fresh priority cell shows the normal default")
	_assert_equal(orders.work_priorities_overlay.mouse_filter, Control.MOUSE_FILTER_STOP, "full-screen priorities backdrop blocks map orders")

	var paused_before := game.user_paused
	var speed_before := game.simulation_speed
	orders.work_priorities_button.pressed.emit()
	_assert_true(orders.is_work_priorities_open(), "roster button opens the crew matrix")
	_assert_equal(game.active_tool, "dig", "opening the board preserves the active Dig tool")
	_assert_equal(game.user_paused, paused_before, "opening the board does not change pause state")
	_assert_equal(game.simulation_speed, speed_before, "opening the board does not change speed")
	var dig_priority_button := orders.get_work_priority_button(1, "dig")
	dig_priority_button.pressed.emit()
	orders.refresh()
	_assert_equal(game.residents[0].get_work_priority("dig"), 4, "board click advances normal priority 3 to 4")
	_assert_equal(dig_priority_button.text, "4", "matrix label stays synchronized with the model")
	game.select_resident(1)
	orders.refresh()
	_assert_equal(orders.work_buttons.dig.text, "DIG: 4", "selected-resident shortcut mirrors the board")
	dig_priority_button.pressed.emit()
	orders.refresh()
	_assert_equal(game.residents[0].get_work_priority("dig"), VaultResident.PRIORITY_DISABLED, "next board click advances priority 4 to Disabled")
	_assert_equal(dig_priority_button.text, "OFF", "Disabled state is carried by text, not color alone")

	var escape_event := InputEventKey.new()
	escape_event.physical_keycode = KEY_ESCAPE
	escape_event.pressed = true
	game._unhandled_input(escape_event)
	_assert_false(orders.is_work_priorities_open(), "Escape closes the priorities board")
	_assert_equal(game.active_tool, "dig", "Escape closes only the board and preserves Dig")
	var p_event := InputEventKey.new()
	p_event.physical_keycode = KEY_P
	p_event.pressed = true
	game._unhandled_input(p_event)
	_assert_true(orders.is_work_priorities_open(), "P opens the priorities board")
	game._unhandled_input(p_event)
	_assert_false(orders.is_work_priorities_open(), "P closes the priorities board")
	_assert_equal(game.active_tool, "dig", "P toggle never changes the selected map tool")

	orders.show_work_priorities(true)
	orders.show_breach_warning(true)
	_assert_false(orders.is_work_priorities_open(), "breach incident supersedes and closes the priorities board")
	orders.show_breach_warning(false)
	game.residents[3].kill()
	orders.refresh()
	_assert_true(orders.get_work_priority_button(4, "cook").disabled, "deceased resident priority cells are disabled")
	_dispose(game)


func _test_dig_completion() -> void:
	var game := _spawn_game()
	var target := MapGrid.CHAMBER.position + Vector2i.LEFT
	var outward_target := target + Vector2i.LEFT
	var isolated_target := Vector2i(5, 5)
	var initial_floor_count := game.map_grid.get_floor_cells().size()
	game.begin_shift()
	game.set_tool("dig")

	_assert_true(game.map_grid.is_diggable(isolated_target), "isolated test target is ordinary diggable rock")
	_assert_false(game.map_grid.is_preview_valid("dig", isolated_target), "isolated rock has an invalid Dig preview")
	_assert_false(game.issue_order(isolated_target), "isolated rock rejects a dig order")
	_assert_false(game.map_grid.dig_marks.has(isolated_target), "rejected excavation leaves no designation")
	_assert_equal(game.job_system.get_queued_count(), 0, "rejected excavation leaves no queued job")
	_assert_true("Connect excavation" in game.status_message, "rejected excavation explains how to connect it")
	_assert_true(game.map_grid.is_preview_valid("dig", target), "rock beside carved floor has a valid Dig preview")
	_assert_true(game.issue_order(target), "adjacent rock accepts a dig order")
	_assert_false(game.issue_order(target), "duplicate dig order is rejected")
	_assert_true(game.map_grid.dig_marks.has(target), "dig designation is stored")
	_assert_true(game.map_grid.is_preview_valid("dig", outward_target), "rock joined to an anchored designation previews valid")
	_assert_true(game.issue_order(outward_target), "an outward designation connected through the first is accepted")
	_assert_equal(game.job_system.get_queued_count(), 2, "two connected excavation jobs are queued")

	game.step_simulation(24.0)

	_assert_equal(game.map_grid.get_tile(target), MapGrid.Tile.FLOOR, "excavation converts rock to floor")
	_assert_equal(game.map_grid.get_tile(outward_target), MapGrid.Tile.FLOOR, "connected outward excavation becomes reachable and completes")
	_assert_false(game.map_grid.dig_marks.has(target), "completed dig designation is cleared")
	_assert_false(game.map_grid.dig_marks.has(outward_target), "connected designation clears after completion")
	_assert_equal(game.map_grid.get_floor_cells().size(), initial_floor_count + 2, "excavation adds both floor tiles")
	_dispose(game)


func _test_blueprint_build() -> void:
	var game := _spawn_game()
	var target := Vector2i(18, 12)
	game.begin_shift()
	game.set_tool("bed")

	_assert_true(game.issue_order(target), "bed blueprint can be placed on chamber floor")
	_assert_false(game.issue_order(target), "occupied floor rejects another blueprint")
	var building: VaultBuilding = game.get_building_at(target)
	_assert_true(building != null, "blueprint exists at its target")
	if building == null:
		_dispose(game)
		return
	_assert_false(building.complete, "new blueprint starts incomplete")
	_assert_equal(building.delivered, 0, "new blueprint starts unsupplied")

	game.step_simulation(39.0)

	_assert_true(building.complete, "residents supply and assemble the blueprint")
	_assert_equal(building.delivered, building.get_cost(), "completed fixture received its full salvage cost")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.BED), 1, "completed bunk is counted")
	_assert_equal(game.food_system.salvage, FoodSystem.STARTING_SALVAGE - building.get_cost(), "construction consumes the expected tuned salvage")
	_dispose(game)


func _test_order_preview_and_checklist() -> void:
	var game := _spawn_game()
	game.begin_shift()
	game.player_orders._refresh_checklist()
	var checklist_text := game.player_orders.checklist.text
	for expected_label in [
		"Excavate at least 12 connected tiles; haul rubble for salvage",
		"Assemble at least 2 bunks",
		"Build a Charge Node (+7 power)",
		"Power Grow Tray + Nutrient Station; keep Cook enabled",
		"Power an Air Recycler (3 power)",
		"Reserve 4 salvage; keep Haul + Craft enabled",
		"Patch and seal the maintenance hatch",
		"Finish Day 7 with a sealed hatch and O2 >= 15%",
		"Power a Rec Console; free 1 power if shed",
		"PRIORITIES [P]: 1 highest · 4 lowest · OFF disabled",
	]:
		_assert_true(expected_label in checklist_text, "checklist covers %s" % expected_label)
	_assert_true("[OPTIONAL][/color]  Power a Rec Console" in checklist_text, "checklist marks recreation as optional")
	_assert_true("[OPTIONAL][/color]  PRIORITIES [P]" in checklist_text, "checklist marks work specialization as optional")
	var blueprint_cell := Vector2i(18, 12)
	_assert_false(game.map_grid.is_preview_valid("bed", BreachSystem.HATCH_CELL), "reserved pressure hatch has an invalid build preview")
	_assert_false(game.place_blueprint(VaultBuilding.Kind.BED, BreachSystem.HATCH_CELL), "reserved pressure hatch rejects blueprints")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, blueprint_cell), "cancel-preview fixture is placed")
	_assert_true(game.map_grid.is_preview_valid("cancel", blueprint_cell), "unfinished blueprint has a valid Cancel preview")
	game.set_tool("cancel")
	_assert_true(game.issue_order(blueprint_cell), "unfinished blueprint is canceled")
	_assert_true(game.get_building_at(blueprint_cell) == null, "canceled blueprint is removed")

	var grow_tray := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, blueprint_cell)
	game.power_grid.recalculate(game.buildings)
	game.player_orders._refresh_checklist()
	_assert_false(grow_tray.powered, "grow tray is initially unpowered during overload")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.GROW_TRAY), 0, "unpowered tray does not satisfy the powered count")
	_assert_true("[    ][/color]  Power Grow Tray + Nutrient Station" in game.player_orders.checklist.text, "checklist leaves an unpowered food chain incomplete")

	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(19, 12))
	game.power_grid.recalculate(game.buildings)
	game.player_orders._refresh_checklist()
	_assert_true(grow_tray.powered, "charge capacity powers the grow tray")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.GROW_TRAY), 1, "powered tray satisfies the powered count")
	_assert_true("[    ][/color]  Power Grow Tray + Nutrient Station" in game.player_orders.checklist.text, "powered grow tray alone does not complete the food chain")
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	game.power_grid.recalculate(game.buildings)
	game.player_orders._refresh_checklist()
	_assert_true(kitchen.powered, "charge capacity also powers the nutrient station")
	_assert_true("[DONE][/color]  Power Grow Tray + Nutrient Station" in game.player_orders.checklist.text, "powered food fixtures with an eligible Cook complete the food chain")
	for resident: VaultResident in game.residents:
		resident.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
	game.player_orders._refresh_checklist()
	_assert_true("[    ][/color]  Power Grow Tray + Nutrient Station" in game.player_orders.checklist.text, "food chain becomes incomplete when every Cook is disabled")
	game.residents[0].set_work_priority("cook", VaultResident.DEFAULT_WORK_PRIORITY)
	game.food_system.salvage = BreachSystem.PATCH_COST - 1
	game.player_orders._refresh_checklist()
	_assert_true("[    ][/color]  Reserve 4 salvage; keep Haul + Craft enabled" in game.player_orders.checklist.text, "hatch readiness reports an insufficient reserve before the warning")
	_dispose(game)


func _test_power_allocation() -> void:
	var game := _spawn_game()
	var lamp: VaultBuilding = game.get_building_at(Vector2i(22, 14))
	_assert_true(lamp != null, "starting lumen exists")
	_assert_equal(game.power_grid.supply, 2, "emergency core supplies two power")
	_assert_equal(game.power_grid.demand, 1, "starting lumen demands one power")
	_assert_true(lamp != null and lamp.powered, "starting lumen receives emergency power")

	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(18, 12))
	var grow_tray := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(19, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.power_grid.supply, 2, "consumers do not add power supply")
	_assert_equal(game.power_grid.demand, 6, "all consumer demand is reported")
	_assert_equal(game.power_grid.served, 1, "limited core power serves only the priority lumen")
	_assert_true(lamp.powered, "lumen retains first power priority")
	_assert_false(kitchen.powered, "kitchen remains offline when two power are unavailable")
	_assert_false(grow_tray.powered, "grow tray remains offline during overload")

	var generator := _add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(20, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_equal(generator.get_power_output(), 7, "built charge node contributes seven power")
	_assert_equal(game.power_grid.supply, 9, "charge node and core supplies combine")
	_assert_equal(game.power_grid.served, 6, "all demand is served after adding charge capacity")
	_assert_true(lamp.powered and kitchen.powered and grow_tray.powered, "all consumers are powered")
	_dispose(game)


func _test_fixed_power_priorities() -> void:
	var game := _spawn_game()
	var lamp: VaultBuilding = game.get_building_at(Vector2i(22, 14))
	var generator := _add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(18, 12))
	var recycler := _add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(19, 12))
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	var first_grow := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(21, 12))
	var second_grow := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(22, 12))
	var transitions := {"started": 0, "cleared": 0}
	game.power_grid.brownout_started.connect(func(_count: int, _amount: int) -> void:
		transitions.started = int(transitions.started) + 1
	)
	game.power_grid.brownout_cleared.connect(func() -> void:
		transitions.cleared = int(transitions.cleared) + 1
	)

	game.power_grid.recalculate(game.buildings)
	_assert_equal(recycler.get_power_priority(), VaultBuilding.PowerPriority.CRITICAL, "air recycler has immutable critical priority")
	_assert_equal(lamp.get_power_priority(), VaultBuilding.PowerPriority.HIGH, "lumen has fixed high priority")
	_assert_equal(kitchen.get_power_priority(), VaultBuilding.PowerPriority.NORMAL, "nutrient station has fixed normal priority")
	_assert_equal(first_grow.get_power_priority(), VaultBuilding.PowerPriority.LOW, "grow trays have fixed low priority")
	var default_shed_order: Array[VaultBuilding] = game.power_grid.get_shed_order(game.buildings)
	var default_shed_names: Array[String] = []
	for building: VaultBuilding in default_shed_order:
		default_shed_names.append("%s#%d" % [building.get_display_name(), building.building_id])
	_assert_variants_equal([
		"Grow Tray#%d" % second_grow.building_id,
		"Grow Tray#%d" % first_grow.building_id,
		"Nutrient Station#%d" % kitchen.building_id,
		"Lumen#%d" % lamp.building_id,
		"Air Recycler#%d" % recycler.building_id,
	], default_shed_names, "documented shed order runs from lowest priority to protected life support")
	_assert_true("Grow Trays -> Nutrient Stations -> Lumens -> Air Recyclers" in game.power_grid.get_shed_order_text(), "shed order text documents priority groups")
	_assert_true(game.power_grid.brownout_active, "unserved completed demand enters brownout")
	_assert_equal(game.power_grid.supply, 9, "priority test has nine available power")
	_assert_equal(game.power_grid.demand, 12, "priority test has twelve total demand")
	_assert_equal(game.power_grid.served, 9, "priority allocator remains work-conserving")
	_assert_equal(game.power_grid.shed_demand, 3, "brownout accounts for all shed power")
	_assert_equal(game.power_grid.shed_count, 1, "brownout accounts for one shed fixture")
	_assert_true(first_grow.powered, "lower building ID wins an equal-priority tie")
	_assert_false(second_grow.powered, "newer equal-priority fixture sheds deterministically")
	_assert_equal(transitions.started, 1, "entering brownout emits one transition")
	game.power_grid.recalculate(game.buildings)
	_assert_equal(transitions.started, 1, "idempotent recalculation does not repeat the transition")

	_assert_true(recycler.powered, "protected life support remains powered during the default overload")
	_assert_false(game.power_grid.is_building_shed(recycler.building_id), "protected recycler is absent from the shed set")
	_assert_true(game.power_grid.is_building_shed(second_grow.building_id), "grid exposes the exact shed fixture")
	_assert_equal(game.power_grid.get_shed_summary(), "Grow Tray", "brownout summary names the shed load")

	var reordered: Array[VaultBuilding] = []
	for index in range(game.buildings.size() - 1, -1, -1):
		reordered.append(game.buildings[index])
	game.power_grid.recalculate(reordered)
	_assert_true(recycler.powered, "allocation is independent of input array order")
	_assert_true(first_grow.powered and not second_grow.powered, "reordered input preserves deterministic same-kind winner")
	_assert_equal(generator.get_power_priority(), VaultBuilding.PowerPriority.NORMAL, "non-consumers use a harmless fixed fallback priority")

	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(23, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_false(game.power_grid.brownout_active, "added capacity clears the brownout")
	_assert_equal(game.power_grid.shed_demand, 0, "restored grid clears shed-power accounting")
	_assert_equal(game.power_grid.shed_count, 0, "restored grid clears shed-fixture accounting")
	_assert_true(recycler.powered and first_grow.powered and second_grow.powered, "restored capacity powers every consumer")
	_assert_equal(transitions.cleared, 1, "leaving brownout emits one recovery transition")
	game.power_grid.recalculate(game.buildings)
	_assert_equal(transitions.cleared, 1, "stable recalculation does not repeat the recovery transition")
	_dispose(game)


func _test_fixture_recovery_controls_while_paused() -> void:
	var game := _spawn_game()
	game.begin_shift()
	game.toggle_pause()
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(18, 12))
	_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(19, 12))
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	var first_grow := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(21, 12))
	var second_grow := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(22, 12))
	second_grow.production_progress = 4.25
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.select_building(second_grow.building_id)
	game.player_orders.refresh()

	_assert_true(game.user_paused, "fixture-control test starts user-paused")
	_assert_false(second_grow.powered, "selected low-priority grow tray starts shed")
	_assert_true(game.player_orders.fixture_controls.visible, "completed consumer exposes recovery controls")
	_assert_equal(game.player_orders.fixture_header.text, "FIXTURE CONTROLS", "fixture controls do not imply mutable shedding priorities")
	_assert_true(game.player_orders.fixture_power_button.visible and not game.player_orders.fixture_power_button.disabled, "consumer can be disabled")
	_assert_false(game.player_orders.fixture_deconstruct_button.disabled, "optional consumer can be removed")
	_assert_true("SHED · BROWNOUT" in game.player_orders.inspector_state.text, "inspector distinguishes a shed fixture")
	_assert_true("Priority: LOW (fixed)" in game.player_orders.inspector_state.text, "inspector explains the immutable shed tier")
	_assert_true("SHED 3 POWER" in game.player_orders.power_detail_label.text, "power readout exposes shed demand")
	_assert_true("POWER BROWNOUT" in game.player_orders.alert_label.text, "compound alerts name the brownout")

	var elapsed_before := game.day_cycle.elapsed_seconds
	var oxygen_before := game.oxygen_system.oxygen
	var progress_before := second_grow.production_progress
	game.player_orders.fixture_power_button.pressed.emit()
	game.player_orders.refresh()

	_assert_true(second_grow.manually_disabled, "Disable press removes the selected consumer's demand")
	_assert_false(game.power_grid.brownout_active, "disabling enough optional load clears the grid immediately")
	_assert_true(first_grow.powered, "fixed same-kind winner remains powered")
	_assert_equal(game.selected_building_id, second_grow.building_id, "recovery action preserves fixture selection")
	_assert_equal(game.player_orders.fixture_power_button.text, "ENABLE", "fixture control refreshes to the inverse action")
	_assert_true("DISABLED" in game.player_orders.inspector_state.text, "inspector distinguishes manual disable from shedding")
	_assert_approximately(game.day_cycle.elapsed_seconds, elapsed_before, 0.0001, "disable does not advance the paused clock")
	_assert_approximately(game.oxygen_system.oxygen, oxygen_before, 0.0001, "disable does not advance paused oxygen")
	_assert_approximately(second_grow.production_progress, progress_before, 0.0001, "disable does not advance production")

	game.player_orders.fixture_power_button.pressed.emit()
	game.player_orders.refresh()
	_assert_false(second_grow.manually_disabled, "Enable press restores the selected consumer's demand")
	_assert_true(game.power_grid.brownout_active and not second_grow.powered, "re-enabled low-priority load returns to the deterministic shed state")

	var core: VaultBuilding = game.get_building_at(Vector2i(24, 15))
	game.select_building(core.building_id)
	game.player_orders.refresh()
	_assert_true(game.player_orders.fixture_controls.visible, "generator selection exposes fixture controls")
	_assert_false(game.player_orders.fixture_power_button.visible, "generator selection hides consumer disable control")
	_assert_true(game.player_orders.fixture_deconstruct_button.disabled, "emergency core cannot be removed")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12)), "test can place an unfinished consumer blueprint")
	var blueprint := game.get_building_at(Vector2i(23, 12))
	game.select_building(blueprint.building_id)
	game.player_orders.refresh()
	_assert_false(game.player_orders.fixture_controls.visible, "unfinished blueprint hides fixture controls")
	_dispose(game)


func _test_balanced_power_grid_accounting() -> void:
	var game := _spawn_game()
	var lamp: VaultBuilding = game.get_building_at(Vector2i(22, 14))
	var generator := _add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(18, 12))
	var recycler := _add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(19, 12))
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	var grow_tray := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(21, 12))
	game.power_grid.recalculate(game.buildings)
	game.player_orders.refresh()

	_assert_equal(generator.get_power_output(), 7, "non-core charge node adds seven supply")
	_assert_equal(game.power_grid.supply, 9, "balanced grid includes emergency core and charge node supply")
	_assert_equal(game.power_grid.demand, 9, "balanced grid reports enabled consumer demand")
	_assert_equal(game.power_grid.served, 9, "balanced grid serves all enabled demand")
	_assert_equal(game.power_grid.shed_demand, 0, "balanced grid sheds no load")
	_assert_equal(game.power_grid.disabled_demand, 0, "balanced grid has no disabled demand")
	_assert_false(game.power_grid.brownout_active, "balanced grid does not enter brownout")
	_assert_true(lamp.powered and recycler.powered and kitchen.powered and grow_tray.powered, "all balanced consumers are powered")
	_assert_true("PWR 9/9 used" in game.power_grid.get_status_text(), "top HUD status reports used supply explicitly")
	_assert_true("SUPPLY 9" in game.player_orders.power_detail_label.text, "right HUD reports supply")
	_assert_true("DEMAND 9" in game.player_orders.power_detail_label.text, "right HUD reports demand")
	_assert_true("ALL CONSUMERS SERVED" in game.player_orders.power_detail_label.text, "right HUD reports stable service state")
	_dispose(game)


func _test_power_recovery_controls() -> void:
	var game := _spawn_game()
	var generator := _add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(18, 12))
	var recycler := _add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(19, 12))
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	var first_grow := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(21, 12))
	var second_grow := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(22, 12))
	var second_grow_id := second_grow.building_id
	game.power_grid.recalculate(game.buildings)
	_assert_true(game.power_grid.brownout_active, "extra grow tray starts a recoverable brownout")
	_assert_false(second_grow.powered, "newest low-priority grow tray is initially shed")

	_assert_true(game.toggle_building_enabled(second_grow_id), "selected consumer can be manually disabled")
	_assert_true(second_grow.manually_disabled, "manual disable state is stored on the fixture")
	_assert_false(game.power_grid.brownout_active, "manual disable removes enough demand to clear brownout")
	_assert_equal(game.power_grid.disabled_demand, 3, "disabled demand is accounted separately")
	_assert_true("disabled" in game.power_grid.get_status_text(), "HUD status exposes disabled demand")

	_assert_true(game.toggle_building_enabled(second_grow_id), "disabled consumer can be re-enabled")
	_assert_true(game.power_grid.brownout_active, "re-enabled load returns the brownout")
	var salvage_before_deconstruct := game.food_system.salvage
	_assert_true(game.deconstruct_building(second_grow_id), "deconstructing optional load is a recovery action")
	_assert_true(game.get_building_by_id(second_grow_id) == null, "deconstructed load leaves the building list")
	_assert_equal(game.food_system.salvage, salvage_before_deconstruct + 6, "deconstruction recovers half the grow tray cost")
	_assert_false(game.power_grid.brownout_active, "removing optional load clears the brownout")

	_assert_true(game.deconstruct_building(generator.building_id), "non-core charge node can be deconstructed and recovered")
	_assert_true(game.power_grid.brownout_active, "removing charge capacity creates a severe brownout")
	_assert_false(recycler.powered, "severe brownout can take the recycler offline")
	_assert_true(game.get_building_by_id(kitchen.building_id) != null and game.get_building_by_id(first_grow.building_id) != null, "only the requested fixture is deconstructed")

	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(23, 12))
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	_assert_false(game.power_grid.brownout_active, "adding charge capacity restores the grid")
	_assert_true(recycler.powered, "restored capacity brings the recycler back online")
	_assert_approximately(game.oxygen_system.recycler_output_rate, 0.8, 0.0001, "oxygen recovery resumes after power recovery")
	_dispose(game)


func _test_shed_production_progress() -> void:
	var game := _spawn_game()
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(18, 12))
	_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(19, 12))
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	var first_grow := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(21, 12))
	var second_grow := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(22, 12))
	second_grow.production_progress = 4.0
	game.power_grid.recalculate(game.buildings)
	var raw_before := game.food_system.raw_food

	_assert_false(second_grow.powered, "newer low-priority tray starts shed")
	game.food_system.advance(3.0, game.buildings)
	_assert_approximately(second_grow.production_progress, 4.0, 0.0001, "shed tray preserves rather than advances its progress")
	_assert_equal(game.food_system.raw_food, raw_before, "shed tray produces no food")

	_assert_true(game.toggle_building_enabled(first_grow.building_id), "disabling another tray frees enough power for the shed tray")
	_assert_true(second_grow.powered, "restored tray is powered immediately")
	_assert_true(first_grow.manually_disabled and not first_grow.powered, "disabled optional load remains outside allocation")
	game.food_system.advance(4.9, game.buildings)
	_assert_approximately(second_grow.production_progress, 8.9, 0.0001, "restored tray resumes from its preserved progress")
	_assert_equal(game.food_system.raw_food, raw_before, "tray does not yield before its exact production boundary")
	game.food_system.advance(0.1, game.buildings)
	_assert_approximately(second_grow.production_progress, 0.0, 0.0001, "completed production cycle resets progress once")
	_assert_equal(game.food_system.raw_food, raw_before + FoodSystem.GROW_YIELD, "restored tray yields exactly one raw food")
	_dispose(game)


func _test_oxygen_consumption_and_clamping() -> void:
	var game := _spawn_game()
	var oxygen := game.oxygen_system
	_assert_approximately(OxygenSystem.MAX_OXYGEN, 100.0, 0.0001, "oxygen maximum is one hundred percent")
	_assert_equal(oxygen.living_resident_count, 4, "oxygen rates count all four living residents")
	_assert_approximately(oxygen.consumption_rate, 0.32, 0.0001, "four residents consume 0.08 oxygen each per second")
	_assert_approximately(oxygen.recycler_output_rate, 0.0, 0.0001, "a wing without a recycler has no oxygen recovery")
	_assert_approximately(oxygen.breach_loss_rate, 0.0, 0.0001, "a closed hatch contributes no oxygen loss")
	_assert_approximately(oxygen.net_rate, -0.32, 0.0001, "closed starting wing reports its global oxygen rate")

	game._process(5.0)
	_assert_approximately(oxygen.oxygen, OxygenSystem.STARTING_OXYGEN, 0.0001, "tutorial pause freezes oxygen with the rest of the simulation")
	game.begin_shift()
	game.step_simulation(10.0)
	_assert_approximately(oxygen.oxygen, 96.8, 0.0002, "ten simulated seconds consume deterministic shared oxygen")

	game.residents[3].alive = false
	oxygen.refresh_rates(game.residents, game.buildings, false)
	_assert_equal(oxygen.living_resident_count, 3, "dead residents stop consuming oxygen")
	_assert_approximately(oxygen.consumption_rate, 0.24, 0.0001, "only living residents contribute to consumption")
	game.residents[3].alive = true

	oxygen.oxygen = 0.1
	oxygen.advance(1.0, game.residents, game.buildings, false)
	_assert_approximately(oxygen.oxygen, 0.0, 0.0001, "oxygen clamps at zero instead of becoming negative")
	var recycler := _add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(18, 12))
	recycler.powered = true
	oxygen.oxygen = 99.9
	oxygen.advance(1.0, game.residents, game.buildings, false)
	_assert_approximately(oxygen.oxygen, OxygenSystem.MAX_OXYGEN, 0.0001, "net recovery clamps oxygen at its maximum")
	_dispose(game)


func _test_air_recycler_power_and_rates() -> void:
	var game := _spawn_game()
	var lamp: VaultBuilding = game.get_building_at(Vector2i(22, 14))
	var recycler := _add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(18, 12))
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)

	_assert_equal(recycler.get_power_demand(), 3, "completed air recycler demands three power")
	_assert_false(recycler.powered, "two emergency power cannot run the three-power recycler")
	_assert_true(lamp != null and lamp.powered, "an unaffordable recycler does not strand usable lamp power")
	_assert_equal(game.oxygen_system.powered_recycler_count, 0, "unpowered recycler is excluded from oxygen production")
	_assert_approximately(game.oxygen_system.recycler_output_rate, 0.0, 0.0001, "unpowered recycler produces no oxygen")

	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(19, 12))
	var first_grow := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(20, 12))
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(21, 12))
	var second_grow := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(22, 12))
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)

	_assert_equal(game.power_grid.supply, 9, "charge node and emergency core provide nine power")
	_assert_equal(game.power_grid.demand, 12, "overloaded fixture set reports all demand")
	_assert_equal(game.power_grid.served, 9, "priority allocation uses all available power")
	_assert_true(recycler.powered, "life-support recycler retains first power priority during overload")
	_assert_true(lamp != null and lamp.powered and kitchen.powered and first_grow.powered, "higher-priority consumers fit within remaining power")
	_assert_false(second_grow.powered, "lower-priority grow tray remains offline during overload")
	_assert_equal(game.oxygen_system.powered_recycler_count, 1, "one powered completed recycler is counted")
	_assert_approximately(game.oxygen_system.recycler_output_rate, 0.8, 0.0001, "powered recycler restores 0.8 oxygen per second")
	_assert_approximately(game.oxygen_system.net_rate, 0.48, 0.0001, "recycler output offsets global resident consumption")
	_dispose(game)


func _test_oxygen_threshold_damage() -> void:
	var game := _spawn_game()
	var oxygen := game.oxygen_system
	for resident: VaultResident in game.residents:
		resident.needs.health = 100.0

	oxygen.oxygen = OxygenSystem.LOW_OXYGEN_THRESHOLD
	_assert_true(oxygen.is_low(), "oxygen is low exactly at the 35 percent threshold")
	_assert_false(oxygen.is_critical(), "the low threshold is not yet critical")
	oxygen.oxygen = OxygenSystem.CRITICAL_OXYGEN_THRESHOLD + 0.32
	oxygen.advance(2.0, game.residents, game.buildings, false)

	_assert_approximately(oxygen.oxygen, OxygenSystem.CRITICAL_OXYGEN_THRESHOLD - 0.32, 0.0001, "two-second step crosses the critical threshold at its midpoint")
	_assert_true(oxygen.is_critical(), "oxygen is critical at or below fifteen percent")
	for resident: VaultResident in game.residents:
		_assert_approximately(
			resident.needs.health,
			96.0,
			0.0001,
			"%s takes four damage for exactly one critical second" % resident.resident_name,
		)
	_dispose(game)


func _test_brownout_during_critical_air_recovery() -> void:
	var game := _spawn_game()
	var oxygen := game.oxygen_system
	for resident: VaultResident in game.residents:
		resident.needs.health = 100.0

	var recycler := _add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(18, 12))
	game.power_grid.recalculate(game.buildings)
	oxygen.oxygen = 14.0
	oxygen.advance(2.0, game.residents, game.buildings, false)

	_assert_true(game.power_grid.brownout_active, "overbuilding the two-power emergency grid creates a brownout")
	_assert_equal(game.power_grid.supply, 2, "the emergency core exposes its two available power")
	_assert_equal(game.power_grid.demand, 4, "the recycler and starting lumen expose four enabled demand")
	_assert_false(recycler.powered, "highest-priority recycler still sheds when its three-power load cannot fit")
	_assert_true(game.power_grid.is_building_shed(recycler.building_id), "brownout accounting identifies the unpowered recycler")
	_assert_approximately(oxygen.recycler_output_rate, 0.0, 0.0001, "shed recycler contributes no oxygen recovery")
	_assert_approximately(oxygen.net_rate, -0.32, 0.0001, "overbuild cascade leaves only resident oxygen consumption")
	_assert_approximately(oxygen.oxygen, 13.36, 0.0001, "overbuild cascade drives critical oxygen lower")
	for resident: VaultResident in game.residents:
		_assert_approximately(
			resident.needs.health,
			92.0,
			0.001,
			"%s takes damage throughout the unpowered critical-air interval" % resident.resident_name,
		)

	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(19, 12))
	game.power_grid.recalculate(game.buildings)
	oxygen.advance(4.0, game.residents, game.buildings, false)

	_assert_false(game.power_grid.brownout_active, "added charge capacity clears the overbuild brownout")
	_assert_true(recycler.powered, "added capacity restores protected life support")
	_assert_approximately(oxygen.recycler_output_rate, 0.8, 0.0001, "restored recycler resumes oxygen output")
	_assert_approximately(oxygen.net_rate, 0.48, 0.0001, "restored recycler creates positive net oxygen recovery")
	_assert_approximately(oxygen.oxygen, 15.28, 0.0001, "power recovery returns the wing above critical oxygen")
	for resident: VaultResident in game.residents:
		_assert_approximately(
			resident.needs.health,
			78.3333,
			0.001,
			"%s stops taking damage once restored recycling crosses the threshold" % resident.resident_name,
		)
	_dispose(game)


func _test_cooking_at_starting_stock() -> void:
	var game := _spawn_game()
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(18, 12))
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, game.residents[0].get_cell(game.map_grid))
	game.food_system.meals = 8
	game.food_system.raw_food = FoodSystem.COOK_INPUT
	game.power_grid.recalculate(game.buildings)
	game.begin_shift()

	_assert_true(kitchen.powered, "nutrient station is powered")
	game.step_simulation(4.2)
	_assert_equal(game.food_system.raw_food, 0, "cooking consumes raw food while meals start at eight")
	_assert_equal(game.food_system.meals, 8 + FoodSystem.COOK_OUTPUT, "cooking adds a meal above the old silent cap")
	_dispose(game)


func _test_breach_warning_interrupt() -> void:
	var game := _spawn_game()
	var warning_signals := {"count": 0}
	var initial_health: Array[float] = []
	for resident: VaultResident in game.residents:
		initial_health.append(resident.needs.health)
	game.breach_system.warning_started.connect(func() -> void:
		warning_signals["count"] = int(warning_signals["count"]) + 1
	)
	game.begin_shift()
	game.set_speed(3)
	game.set_tool("dig")
	game.food_system.salvage = 0
	for resident: VaultResident in game.residents:
		resident.work_allowed.haul = false
		resident.work_allowed.craft = false

	game.step_simulation(BreachSystem.WARNING_AT_SECONDS - VaultGame.SIMULATION_TICK)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.DORMANT, "breach remains dormant one tick before 60 seconds")
	_assert_equal(warning_signals["count"], 0, "warning has not fired before the exact threshold")
	_assert_false(game.user_paused, "shift is still running before the warning")
	for index in game.residents.size():
		_assert_approximately(game.residents[index].needs.health, initial_health[index], 0.0001, "dormant hatch causes no early damage to resident %d" % index)

	game.step_simulation(VaultGame.SIMULATION_TICK)
	game.player_orders.refresh()
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.WARNING, "breach warning begins at exactly 60 seconds")
	_assert_equal(warning_signals["count"], 1, "warning fires once at the threshold")
	_assert_true(game.user_paused, "first warning automatically pauses the shift")
	_assert_equal(game.simulation_speed, 1, "first warning resets simulation speed to 1x")
	_assert_true(game.selected_breach, "first warning selects the pressure hatch")
	_assert_equal(game.active_tool, "select", "first warning returns to Select mode")
	_assert_equal(game.world_camera.position, game.map_grid.cell_to_world(BreachSystem.HATCH_CELL), "first warning focuses the hatch")
	_assert_equal(game.job_system.get_breach_response_status(), "BLOCKED · ENABLE HAUL", "weak wing reports its first response blocker")
	_assert_true(game.player_orders.breach_warning_panel.visible, "first warning opens the priority incident card")
	_assert_true(game.player_orders.breach_resume_button.has_focus(), "priority incident focuses its Resume action")
	_assert_true("SEAL WARNING" in game.player_orders.alert_label.text, "warning overrides nominal wing status")
	_assert_approximately(game.breach_system.get_pressure_percent(), 0.0, 0.0001, "pressure starts at zero percent at the warning boundary")
	for index in game.residents.size():
		_assert_approximately(game.residents[index].needs.health, initial_health[index], 0.0001, "warning boundary causes no early damage to resident %d" % index)

	var elapsed_while_paused := game.day_cycle.elapsed_seconds
	var pressure_while_paused := game.breach_system.get_pressure_percent()
	var health_while_paused: Array[float] = []
	for resident: VaultResident in game.residents:
		health_while_paused.append(resident.needs.health)
	game._process(5.0)
	_assert_approximately(game.day_cycle.elapsed_seconds, elapsed_while_paused, 0.0001, "paused processing does not advance the simulation clock")
	_assert_approximately(game.breach_system.get_pressure_percent(), pressure_while_paused, 0.0001, "paused processing does not advance breach pressure")
	for index in game.residents.size():
		_assert_approximately(game.residents[index].needs.health, health_while_paused[index], 0.0001, "paused processing does not apply breach damage to resident %d" % index)

	game.breach_system.advance(0.0, BreachSystem.WARNING_AT_SECONDS)
	_assert_equal(warning_signals["count"], 1, "warning does not retrigger after the shift resumes")
	game.acknowledge_breach_warning(true)
	_assert_false(game.user_paused, "resuming clears the one-time warning pause")
	_assert_false(game.player_orders.breach_warning_panel.visible, "resuming dismisses the priority incident card")
	game.breach_system.advance(
		BreachSystem.GRACE_SECONDS - VaultGame.SIMULATION_TICK,
		BreachSystem.WARNING_AT_SECONDS + BreachSystem.GRACE_SECONDS - VaultGame.SIMULATION_TICK,
	)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.WARNING, "hatch remains in warning through 79.9 seconds")
	for index in game.residents.size():
		_assert_approximately(game.residents[index].needs.health, initial_health[index], 0.0001, "warning grace causes no damage to resident %d" % index)
	game.breach_system.advance(
		VaultGame.SIMULATION_TICK,
		BreachSystem.WARNING_AT_SECONDS + BreachSystem.GRACE_SECONDS,
	)
	game.player_orders.refresh()
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.OPEN, "unanswered hatch opens at exactly 80 seconds")
	_assert_false(game.user_paused, "opening does not grant a second automatic pause")
	_assert_equal(warning_signals["count"], 1, "opening does not replay the warning interrupt")
	_assert_true("BREACH OPEN" in game.player_orders.alert_label.text, "open breach remains visible in compound alerts")
	_dispose(game)


func _test_breach_response_jobs() -> void:
	var game := _spawn_game()
	game.begin_shift()
	var ordinary_dig := MapGrid.CHAMBER.position + Vector2i.LEFT
	_assert_true(game.map_grid.queue_dig(ordinary_dig), "competing ordinary dig can be queued")
	game.job_system.queue_dig(ordinary_dig)
	var competing_blueprint_cell := Vector2i(18, 12)
	_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, competing_blueprint_cell), "competing blueprint can be queued")
	var competing_blueprint := game.get_building_at(competing_blueprint_cell)
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.light_mood = 100.0
		resident.work_allowed.haul = false
		resident.work_allowed.craft = false

	game.breach_system.advance(0.0, BreachSystem.WARNING_AT_SECONDS)
	_assert_equal(game.job_system.get_breach_response_status(), "BLOCKED · ENABLE HAUL", "Haul permission is the first reported blocker")

	game.residents[0].work_allowed.haul = true
	game.food_system.salvage = 0
	_assert_equal(game.job_system.get_breach_response_status(), "BLOCKED · NEEDS 4 SALVAGE", "missing patch salvage is reported after Haul is enabled")

	game.food_system.salvage = BreachSystem.PATCH_COST
	game.residents[1].work_allowed.haul = true
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_equal(game.residents[0].current_job_type, JobSystem.JobType.SUPPLY_BREACH, "urgent breach supply outranks an ordinary Dig job")
	_assert_equal(game.food_system.salvage, BreachSystem.PATCH_COST, "emergency salvage remains reserved while its hauler approaches")
	_assert_equal(competing_blueprint.delivered, 0, "a second hauler cannot divert the four reserved salvage")
	_assert_true(game.residents[1].current_job_type != JobSystem.JobType.SUPPLY_BUILD, "ordinary blueprint supply waits behind the breach reserve")
	for _index in 80:
		if game.job_system.get_breach_supply_in_transit() > 0:
			break
		game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_equal(game.job_system.get_breach_supply_in_transit(), BreachSystem.PATCH_COST, "hatch salvage is tracked while its hauler is en route")
	game.residents[2].work_allowed.craft = true
	game.player_orders._refresh_checklist()
	_assert_true("[DONE][/color]  Reserve 4 salvage; keep Haul + Craft enabled" in game.player_orders.checklist.text, "committed in-transit patch salvage keeps hatch readiness complete")
	game.residents[2].work_allowed.craft = false
	for _index in 80:
		if game.breach_system.is_supplied():
			break
		game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_equal(game.breach_system.patch_delivered, BreachSystem.PATCH_COST, "Haul response delivers exactly four salvage")
	_assert_equal(game.food_system.salvage, 0, "breach supply consumes the four salvage")
	_assert_approximately(game.breach_system.patch_work_left, BreachSystem.PATCH_WORK_SECONDS, 0.0001, "Craft work waits for all four salvage")
	_assert_equal(game.job_system.get_breach_response_status(), "BLOCKED · ENABLE CRAFT", "Craft permission is reported after supplies arrive")

	game.residents[0].work_allowed.craft = true
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_equal(game.residents[0].current_job_type, JobSystem.JobType.PATCH_BREACH, "urgent Craft job follows the Haul response")
	game.player_orders._refresh_checklist()
	_assert_true("[DONE][/color]  Reserve 4 salvage; keep Haul + Craft enabled" in game.player_orders.checklist.text, "delivered patch salvage keeps hatch readiness complete during Craft work")
	for _index in 78:
		game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_false(game.breach_system.is_sealed(), "pressure hatch remains unsealed one work tick before the eight-second patch completes")
	_assert_approximately(game.breach_system.patch_work_left, VaultGame.SIMULATION_TICK, 0.0002, "exactly one patch tick remains after 7.9 seconds of Craft work")
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_true(game.breach_system.is_sealed(), "eight seconds of urgent Craft work seals the breach")
	_assert_approximately(game.breach_system.patch_work_left, 0.0, 0.0001, "completed patch has no work remaining")
	_dispose(game)


func _test_prepared_breach_survival() -> void:
	var game := _spawn_game()
	game.begin_shift()
	game.food_system.salvage = BreachSystem.PATCH_COST
	var initial_health: Array[float] = []
	for index in game.residents.size():
		var resident: VaultResident = game.residents[index]
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.light_mood = 100.0
		resident.needs.health = 100.0
		resident.work_allowed.dig = false
		resident.work_allowed.haul = index == 0
		resident.work_allowed.craft = index == 1
		resident.work_allowed.cook = false
		initial_health.append(resident.needs.health)
	game.residents[0].position = game.map_grid.cell_to_world(Vector2i(19, 17))
	game.residents[1].position = game.map_grid.cell_to_world(BreachSystem.HATCH_CELL)

	game.step_simulation(BreachSystem.WARNING_AT_SECONDS)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.WARNING, "prepared wing receives the deterministic 60-second warning")
	_assert_true(game.user_paused, "prepared response waits for the one-time player resume")
	_assert_equal(game.food_system.salvage, BreachSystem.PATCH_COST, "paused warning has not started the emergency haul")
	var competing_blueprint_cell := Vector2i(18, 12)
	_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, competing_blueprint_cell), "prepared fixture adds competing Craft work during the pause")
	var competing_blueprint := game.get_building_at(competing_blueprint_cell)
	game.job_system.cancel_building(competing_blueprint.building_id)
	competing_blueprint.delivered = competing_blueprint.get_cost()
	game.job_system.queue_building(competing_blueprint)
	game.acknowledge_breach_warning(true)
	game._simulation_step(VaultGame.SIMULATION_TICK)
	_assert_equal(game.residents[1].current_job_type, JobSystem.JobType.BUILD, "Craft worker may continue ordinary work while patch supplies travel")

	var saw_patch_preemption := false
	for _index in floori(BreachSystem.GRACE_SECONDS / VaultGame.SIMULATION_TICK):
		if game.breach_system.is_sealed():
			break
		game._simulation_step(VaultGame.SIMULATION_TICK)
		if game.residents[1].current_job_type == JobSystem.JobType.PATCH_BREACH:
			saw_patch_preemption = true

	_assert_true(game.breach_system.is_sealed(), "automatic Haul then Craft response seals during the grace period")
	_assert_true(saw_patch_preemption, "ready patch work preempts the resident's ordinary Craft job")
	_assert_true(
		game.day_cycle.elapsed_seconds < BreachSystem.WARNING_AT_SECONDS + BreachSystem.GRACE_SECONDS,
		"prepared response finishes before the 80-second opening boundary",
	)
	_assert_equal(game.breach_system.patch_delivered, BreachSystem.PATCH_COST, "prepared response delivers exactly four salvage")
	_assert_equal(game.food_system.salvage, 0, "prepared response consumes only the four patch salvage")
	_assert_approximately(game.breach_system.patch_work_left, 0.0, 0.0001, "prepared response completes all eight seconds of patch work")
	var emergency_job_left := false
	for job: Dictionary in game.job_system.jobs:
		if int(job.type) in [JobSystem.JobType.SUPPLY_BREACH, JobSystem.JobType.PATCH_BREACH] and not bool(job.get("done", false)):
			emergency_job_left = true
	_assert_false(emergency_job_left, "sealed response leaves no emergency job behind")
	for index in game.residents.size():
		_assert_approximately(game.residents[index].needs.health, initial_health[index], 0.0001, "prepared grace response prevents damage to resident %d" % index)
	_dispose(game)


func _test_exact_open_boundary_patch() -> void:
	var game := _spawn_game()
	game.begin_shift()
	for index in game.residents.size():
		var resident: VaultResident = game.residents[index]
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.light_mood = 100.0
		resident.work_allowed.dig = false
		resident.work_allowed.haul = false
		resident.work_allowed.craft = index == 0
		resident.work_allowed.cook = false
	game.residents[0].position = game.map_grid.cell_to_world(BreachSystem.HATCH_CELL)
	var opening_signals := {"count": 0}
	game.breach_system.breach_opened.connect(func() -> void:
		opening_signals["count"] = int(opening_signals["count"]) + 1
	)
	var just_before_open := BreachSystem.WARNING_AT_SECONDS + BreachSystem.GRACE_SECONDS - VaultGame.SIMULATION_TICK
	game.day_cycle.deserialize({"elapsed_seconds": just_before_open, "current_day": 2, "completed": false})
	game.breach_system.advance(0.0, just_before_open)
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.patch_work_left = VaultGame.SIMULATION_TICK
	game.job_system.rebuild_from_state()

	game._simulation_step(VaultGame.SIMULATION_TICK)

	_assert_approximately(game.day_cycle.elapsed_seconds, BreachSystem.WARNING_AT_SECONDS + BreachSystem.GRACE_SECONDS, 0.0001, "boundary step reaches exactly 80 seconds")
	_assert_true(game.breach_system.is_sealed(), "the final 0.1 seconds of patch work completes at the boundary")
	_assert_equal(opening_signals["count"], 0, "a patch completed at 80 seconds does not emit a spurious open event")
	_assert_approximately(game.oxygen_system.breach_loss_rate, 0.0, 0.0001, "boundary containment never activates the oxygen leak")
	_dispose(game)


func _test_breach_oxygen_drain_and_seal() -> void:
	var game := _spawn_game()
	game.begin_shift()
	game.food_system.salvage = 0
	for resident: VaultResident in game.residents:
		resident.needs.health = 100.0
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.light_mood = 100.0
		resident.work_allowed.haul = false
		resident.work_allowed.craft = false
	game.oxygen_system.oxygen = 50.0
	game.breach_system.advance(
		0.0,
		BreachSystem.WARNING_AT_SECONDS + BreachSystem.GRACE_SECONDS - VaultGame.SIMULATION_TICK,
	)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.WARNING, "blocked breach remains in warning one tick before 80 seconds")
	_assert_equal(game.breach_system.patch_delivered, 0, "blocked breach has no emergency salvage delivered")
	for resident: VaultResident in game.residents:
		_assert_approximately(resident.needs.health, 100.0, 0.0001, "warning remains harmless through 79.9 seconds for %s" % resident.resident_name)

	game.breach_system.advance(
		VaultGame.SIMULATION_TICK,
		BreachSystem.WARNING_AT_SECONDS + BreachSystem.GRACE_SECONDS,
	)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.OPEN, "breach opens at the end of its 20-second grace period")
	for resident: VaultResident in game.residents:
		_assert_approximately(resident.needs.health, 100.0, 0.0001, "opening the hatch does not directly damage %s" % resident.resident_name)
	_assert_approximately(game.oxygen_system.oxygen, 50.0, 0.0001, "opening the hatch does not bypass the oxygen simulation")

	game._simulation_step(1.0)
	_assert_approximately(game.oxygen_system.breach_loss_rate, 2.5, 0.0001, "open hatch contributes its global breach-loss rate")
	_assert_approximately(game.oxygen_system.oxygen, 47.18, 0.0001, "open hatch and four residents drain shared oxygen for one second")
	for resident: VaultResident in game.residents:
		_assert_approximately(resident.needs.health, 100.0, 0.0001, "breach causes no direct health damage above critical oxygen for %s" % resident.resident_name)

	_assert_equal(game.breach_system.add_delivery(BreachSystem.PATCH_COST), BreachSystem.PATCH_COST, "open breach accepts the four-salvage patch")
	_assert_true(game.breach_system.apply_patch_work(BreachSystem.PATCH_WORK_SECONDS), "supplied eight-second patch seals the open breach")
	game._simulation_step(5.0)
	_assert_approximately(game.oxygen_system.breach_loss_rate, 0.0, 0.0001, "sealed hatch removes the breach-loss rate immediately")
	_assert_approximately(game.oxygen_system.oxygen, 45.58, 0.0001, "after sealing only resident consumption continues")
	for index in game.residents.size():
		_assert_approximately(game.residents[index].needs.health, 100.0, 0.0001, "healthy oxygen leaves resident %d unharmed after sealing" % index)
	_dispose(game)


func _test_breach_save_load_compatibility() -> void:
	_remove_test_save(BREACH_SAVE_TEST_PATH)
	var original := _spawn_game()
	for resident: VaultResident in original.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.light_mood = 100.0
	original.food_system.salvage = BreachSystem.PATCH_COST
	original.day_cycle.advance(BreachSystem.WARNING_AT_SECONDS + 5.0)
	original.breach_system.advance(0.0, original.day_cycle.elapsed_seconds)
	for _index in 20:
		original.job_system.advance(VaultGame.SIMULATION_TICK)
		var saved_supply: Array = original.job_system.serialize().breach_supply
		if saved_supply.size() >= 2 and int(saved_supply[1]) == BreachSystem.PATCH_COST:
			break
	var snapshot_before := original.create_snapshot()
	_assert_equal(original.breach_system.phase, BreachSystem.Phase.WARNING, "round-trip snapshot captures an active warning")
	_assert_approximately(original.breach_system.get_pressure_percent(), 25.0, 0.0001, "round-trip snapshot captures active grace progress")
	_assert_equal(snapshot_before.jobs.breach_supply[1], BreachSystem.PATCH_COST, "round-trip snapshot captures four patch salvage in transit")
	_assert_true(int(snapshot_before.jobs.breach_supply[2]) > 0, "round-trip snapshot records the emergency hauler")

	_assert_true(original.save_game(false, BREACH_SAVE_TEST_PATH), "active breach snapshot writes to the isolated save")
	var loaded := _spawn_game()
	_assert_true(loaded.load_game(BREACH_SAVE_TEST_PATH), "fresh game loads the active breach snapshot")
	_assert_variants_equal(snapshot_before, loaded.create_snapshot(), "active breach snapshot round trip")
	_assert_true(loaded.user_paused, "loading an active breach returns paused")
	_assert_equal(
		loaded.residents[int(snapshot_before.jobs.breach_supply[2]) - 1].carrying,
		BreachSystem.PATCH_COST,
		"loaded emergency hauler still carries the in-flight salvage",
	)
	original.step_simulation(14.0)
	loaded.step_simulation(14.0)
	_assert_true(original.breach_system.is_sealed(), "original mid-haul response completes after the snapshot")
	_assert_true(loaded.breach_system.is_sealed(), "loaded mid-haul response completes without losing salvage")
	_assert_variants_equal(original.create_snapshot(), loaded.create_snapshot(), "loaded emergency response remains deterministic")

	var stable_snapshot := loaded.create_snapshot()
	var impossible_clock: Dictionary = snapshot_before.duplicate(true)
	impossible_clock.day.elapsed_seconds = 0.0
	_assert_false(loaded.apply_snapshot(impossible_clock), "warning state before its clock threshold is rejected")
	_assert_variants_equal(stable_snapshot, loaded.create_snapshot(), "rejected breach clock mismatch is atomic")
	var malformed_breach_job: Dictionary = snapshot_before.duplicate(true)
	malformed_breach_job.jobs.breach_supply = [BreachSystem.PATCH_COST, "four", 1]
	_assert_false(loaded.apply_snapshot(malformed_breach_job), "non-numeric in-flight breach salvage is rejected")
	_assert_variants_equal(stable_snapshot, loaded.create_snapshot(), "rejected breach job payload is atomic")
	var unknown_carrier: Dictionary = snapshot_before.duplicate(true)
	unknown_carrier.jobs.breach_supply[2] = 999
	_assert_false(loaded.apply_snapshot(unknown_carrier), "unknown emergency-haul carrier is rejected")
	_assert_variants_equal(stable_snapshot, loaded.create_snapshot(), "rejected carrier identity leaves the wing unchanged")
	var malformed_snapshot: Dictionary = stable_snapshot.duplicate(true)
	malformed_snapshot.breach.patch_delivered = BreachSystem.PATCH_COST + 1
	_assert_false(loaded.apply_snapshot(malformed_snapshot), "malformed optional breach state is rejected")
	_assert_variants_equal(stable_snapshot, loaded.create_snapshot(), "rejected breach state does not mutate the active wing")
	var partial_snapshot: Dictionary = stable_snapshot.duplicate(true)
	partial_snapshot.breach = {"patch_delivered": BreachSystem.PATCH_COST}
	_assert_false(loaded.apply_snapshot(partial_snapshot), "partial breach state cannot synthesize free patch materials")
	_assert_variants_equal(stable_snapshot, loaded.create_snapshot(), "rejected partial breach state is atomic")
	loaded._simulation_accumulator = 0.09
	_assert_true(loaded.apply_snapshot(stable_snapshot), "valid state can replace a running in-memory wing")
	_assert_approximately(loaded._simulation_accumulator, 0.0, 0.0001, "successful restore clears pre-load simulation backlog")

	var legacy_snapshot: Dictionary = snapshot_before.duplicate(true)
	legacy_snapshot.erase("breach")
	var legacy_jobs: Dictionary = legacy_snapshot.get("jobs", {})
	legacy_jobs.erase("breach_supply")
	legacy_snapshot.jobs = legacy_jobs
	legacy_snapshot.food.salvage = int(legacy_snapshot.food.salvage) + BreachSystem.PATCH_COST
	var legacy_write: Dictionary = original.save_load.save_snapshot(legacy_snapshot, BREACH_SAVE_TEST_PATH)
	_assert_true(bool(legacy_write.ok), "compatible version-one snapshot without breach data writes successfully")
	var legacy_loaded := _spawn_game()
	var restored_warning_signals := {"count": 0}
	legacy_loaded.breach_system.warning_started.connect(func() -> void:
		restored_warning_signals["count"] = int(restored_warning_signals["count"]) + 1
	)
	_assert_true(legacy_loaded.load_game(BREACH_SAVE_TEST_PATH), "version-one snapshot without breach data loads safely")
	_assert_equal(legacy_loaded.breach_system.phase, BreachSystem.Phase.WARNING, "legacy load derives the safe breach phase from elapsed time")
	_assert_approximately(legacy_loaded.breach_system.get_pressure_percent(), 25.0, 0.0001, "legacy load derives the grace progress from elapsed time")
	_assert_equal(legacy_loaded.breach_system.patch_delivered, 0, "legacy load defaults patch supplies safely")
	_assert_approximately(legacy_loaded.breach_system.patch_work_left, BreachSystem.PATCH_WORK_SECONDS, 0.0001, "legacy load defaults patch work safely")
	_assert_equal(restored_warning_signals["count"], 0, "legacy restore does not replay the warning interrupt")

	var collision_snapshot: Dictionary = legacy_snapshot.duplicate(true)
	collision_snapshot.buildings.append({
		"id": 900,
		"kind": int(VaultBuilding.Kind.BED),
		"cell": [BreachSystem.HATCH_CELL.x, BreachSystem.HATCH_CELL.y],
		"complete": true,
		"delivered": 8,
		"construction_left": 0.0,
		"powered": false,
		"is_emergency_core": false,
		"production_progress": 0.0,
	})
	collision_snapshot.next_building_id = 901
	var collision_loaded := _spawn_game()
	_assert_true(collision_loaded.apply_snapshot(collision_snapshot), "legacy hatch fixture loads without destructive migration")
	collision_loaded.begin_shift()
	_assert_true(collision_loaded.issue_order(BreachSystem.HATCH_CELL), "legacy hatch fixture remains selectable")
	_assert_equal(collision_loaded.selected_building_id, 900, "hatch selection preserves access to the legacy fixture")
	collision_loaded.focus_breach()
	_assert_true(collision_loaded.selected_breach, "dedicated focus still opens the overlaid breach inspector")
	_assert_true(collision_loaded.get_building_by_id(900) != null, "legacy hatch fixture remains intact after breach focus")

	_dispose(collision_loaded)
	_dispose(legacy_loaded)
	_dispose(loaded)
	_dispose(original)
	_remove_test_save(BREACH_SAVE_TEST_PATH)


func _test_oxygen_save_load_compatibility() -> void:
	_remove_test_save(OXYGEN_SAVE_TEST_PATH)
	var original := _spawn_game()
	original.oxygen_system.oxygen = 27.25
	var active_snapshot := original.create_snapshot()
	_assert_variants_equal(active_snapshot.oxygen, {"oxygen": 27.25}, "active snapshot stores the global oxygen field")
	_assert_true(original.save_game(false, OXYGEN_SAVE_TEST_PATH), "active oxygen snapshot writes to the isolated save")

	var loaded := _spawn_game()
	_assert_true(loaded.load_game(OXYGEN_SAVE_TEST_PATH), "fresh game loads the active oxygen snapshot")
	_assert_approximately(loaded.oxygen_system.oxygen, 27.25, 0.0001, "active oxygen value survives the round trip")
	_assert_true(loaded.oxygen_system.is_low(), "restored oxygen also restores its low-air state")
	_assert_true(loaded.user_paused, "loading oxygen state returns the simulation paused")

	var stable_snapshot := loaded.create_snapshot()
	var empty_snapshot: Dictionary = stable_snapshot.duplicate(true)
	empty_snapshot.oxygen = {}
	_assert_false(loaded.apply_snapshot(empty_snapshot), "an explicitly empty oxygen payload is rejected")
	_assert_variants_equal(stable_snapshot, loaded.create_snapshot(), "rejected empty oxygen payload is atomic")
	var nonnumeric_snapshot: Dictionary = stable_snapshot.duplicate(true)
	nonnumeric_snapshot.oxygen = {"oxygen": "thin"}
	_assert_false(loaded.apply_snapshot(nonnumeric_snapshot), "nonnumeric oxygen payload is rejected")
	_assert_variants_equal(stable_snapshot, loaded.create_snapshot(), "rejected oxygen type leaves the wing unchanged")
	var out_of_range_snapshot: Dictionary = stable_snapshot.duplicate(true)
	out_of_range_snapshot.oxygen = {"oxygen": OxygenSystem.MAX_OXYGEN + 0.1}
	_assert_false(loaded.apply_snapshot(out_of_range_snapshot), "out-of-range oxygen payload is rejected")
	_assert_variants_equal(stable_snapshot, loaded.create_snapshot(), "rejected oxygen range is atomic")
	var extra_field_snapshot: Dictionary = stable_snapshot.duplicate(true)
	extra_field_snapshot.oxygen = {"oxygen": 27.25, "rooms": []}
	_assert_false(loaded.apply_snapshot(extra_field_snapshot), "multi-room gas payload is outside the scalar oxygen schema")
	_assert_variants_equal(stable_snapshot, loaded.create_snapshot(), "rejected expanded gas payload is atomic")

	var forged_win: Dictionary = stable_snapshot.duplicate(true)
	forged_win.day = {
		"elapsed_seconds": DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE,
		"current_day": DayCycle.DAYS_TO_SURVIVE,
		"completed": true,
	}
	forged_win.breach = {
		"phase": int(BreachSystem.Phase.SEALED),
		"patch_delivered": BreachSystem.PATCH_COST,
		"patch_work_left": 0.0,
		"warning_acknowledged": true,
		"warning_emitted": true,
		"open_emitted": false,
		"sealed_emitted": true,
	}
	forged_win.oxygen = {"oxygen": 0.0}
	forged_win.ended = true
	forged_win.outcome = "win"
	_assert_false(loaded.apply_snapshot(forged_win), "saved victory cannot bypass the breathable-oxygen gate")
	_assert_variants_equal(stable_snapshot, loaded.create_snapshot(), "rejected unbreathable saved victory is atomic")
	forged_win.oxygen = {"oxygen": OxygenSystem.STARTING_OXYGEN}
	forged_win.breach = {
		"phase": int(BreachSystem.Phase.OPEN),
		"patch_delivered": 0,
		"patch_work_left": BreachSystem.PATCH_WORK_SECONDS,
		"warning_acknowledged": true,
		"warning_emitted": true,
		"open_emitted": true,
		"sealed_emitted": false,
	}
	_assert_false(loaded.apply_snapshot(forged_win), "saved victory cannot bypass the sealed-hatch gate")
	_assert_variants_equal(stable_snapshot, loaded.create_snapshot(), "rejected open-hatch saved victory is atomic")
	forged_win.breach.phase = int(BreachSystem.Phase.SEALED)
	forged_win.breach.patch_delivered = BreachSystem.PATCH_COST
	forged_win.breach.patch_work_left = 0.0
	forged_win.breach.open_emitted = false
	forged_win.breach.sealed_emitted = true
	forged_win.day.elapsed_seconds = DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE - VaultGame.SIMULATION_TICK
	forged_win.day.current_day = DayCycle.DAYS_TO_SURVIVE
	forged_win.day.completed = false
	_assert_false(loaded.apply_snapshot(forged_win), "saved victory cannot bypass the seven-day gate")
	_assert_variants_equal(stable_snapshot, loaded.create_snapshot(), "rejected early saved victory is atomic")

	var legacy_snapshot: Dictionary = active_snapshot.duplicate(true)
	legacy_snapshot.erase("oxygen")
	_assert_true(loaded.apply_snapshot(legacy_snapshot), "legacy snapshot without oxygen data loads safely")
	_assert_approximately(loaded.oxygen_system.oxygen, OxygenSystem.STARTING_OXYGEN, 0.0001, "legacy snapshot defaults to full oxygen")
	_assert_true(loaded.oxygen_system.is_breathable(), "legacy oxygen default is immediately breathable")

	_dispose(loaded)
	_dispose(original)
	_remove_test_save(OXYGEN_SAVE_TEST_PATH)


func _test_power_controls_save_load_compatibility() -> void:
	_remove_test_save(POWER_SAVE_TEST_PATH)
	var original := _spawn_game()
	_add_completed_building(original, VaultBuilding.Kind.GENERATOR, Vector2i(18, 12))
	var recycler := _add_completed_building(original, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(19, 12))
	var kitchen := _add_completed_building(original, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	var first_grow := _add_completed_building(original, VaultBuilding.Kind.GROW_TRAY, Vector2i(21, 12))
	var second_grow := _add_completed_building(original, VaultBuilding.Kind.GROW_TRAY, Vector2i(22, 12))
	_assert_true(original.toggle_building_enabled(kitchen.building_id), "round-trip kitchen accepts manual disable")
	var snapshot_before := original.create_snapshot()
	_assert_true(recycler.powered, "fixed-priority recycler is protected before saving")
	_assert_true(first_grow.powered and not second_grow.powered, "same-kind allocation is deterministic before saving")
	_assert_true(kitchen.manually_disabled, "disabled kitchen stores separate demand before saving")
	_assert_true(original.save_game(false, POWER_SAVE_TEST_PATH), "power-control snapshot writes to the isolated save")

	var loaded := _spawn_game()
	_assert_true(loaded.load_game(POWER_SAVE_TEST_PATH), "fresh game loads power controls")
	_assert_variants_equal(snapshot_before, loaded.create_snapshot(), "manual disable and derived allocation round trip")
	_assert_true(loaded.user_paused, "power-control load returns paused")
	var loaded_recycler := loaded.get_building_by_id(recycler.building_id)
	var loaded_kitchen := loaded.get_building_by_id(kitchen.building_id)
	var loaded_first_grow := loaded.get_building_by_id(first_grow.building_id)
	var loaded_second_grow := loaded.get_building_by_id(second_grow.building_id)
	_assert_equal(loaded_recycler.get_power_priority(), VaultBuilding.PowerPriority.CRITICAL, "loaded recycler retains immutable life-support priority")
	_assert_true(loaded_kitchen.manually_disabled, "manual disable survives by building ID")
	_assert_equal(loaded.power_grid.disabled_demand, 2, "loaded manual disable restores disabled-demand accounting")
	_assert_true(loaded_first_grow.powered and not loaded_second_grow.powered, "loaded grid recomputes the same fixed-priority winner")
	_assert_true(loaded_recycler.powered, "loaded grid keeps the recycler protected")

	var stale_powered: Dictionary = snapshot_before.duplicate(true)
	for entry: Dictionary in stale_powered.buildings:
		if int(entry.id) == recycler.building_id:
			entry.powered = false
		elif int(entry.id) == first_grow.building_id:
			entry.powered = false
	_assert_true(loaded.apply_snapshot(stale_powered), "snapshot powered flags remain derived rather than authoritative")
	_assert_true(loaded.get_building_by_id(recycler.building_id).powered, "load corrects a stale unpowered recycler flag")
	_assert_true(loaded.get_building_by_id(first_grow.building_id).powered, "load corrects a stale shed flag on a priority winner")

	var legacy_snapshot: Dictionary = snapshot_before.duplicate(true)
	for entry: Dictionary in legacy_snapshot.buildings:
		entry.erase("manually_disabled")
	_assert_true(loaded.apply_snapshot(legacy_snapshot), "schema-one snapshot without manual-disable state loads safely")
	loaded_recycler = loaded.get_building_by_id(recycler.building_id)
	loaded_kitchen = loaded.get_building_by_id(kitchen.building_id)
	loaded_first_grow = loaded.get_building_by_id(first_grow.building_id)
	loaded_second_grow = loaded.get_building_by_id(second_grow.building_id)
	_assert_equal(loaded_recycler.get_power_priority(), VaultBuilding.PowerPriority.CRITICAL, "legacy recycler retains its fixed life-support priority")
	_assert_false(loaded_kitchen.manually_disabled, "legacy consumer defaults to enabled")
	_assert_true(loaded_recycler.powered and loaded_first_grow.powered, "legacy defaults reproduce Slice 3 winners")
	_assert_false(loaded_second_grow.powered, "legacy defaults reproduce deterministic same-kind shedding")

	var stable_snapshot := loaded.create_snapshot()
	var malformed_disabled: Dictionary = stable_snapshot.duplicate(true)
	malformed_disabled.buildings[1].manually_disabled = "sometimes"
	_assert_false(loaded.apply_snapshot(malformed_disabled), "nonnumeric manual-disable state is rejected")
	_assert_variants_equal(stable_snapshot, loaded.create_snapshot(), "rejected manual-disable type is atomic")

	_dispose(loaded)
	_dispose(original)
	_remove_test_save(POWER_SAVE_TEST_PATH)


func _test_exact_day_boundary() -> void:
	var day_cycle := DayCycle.new()
	root.add_child(day_cycle)
	day_cycle.reset()
	var completed_signals := {"count": 0}
	day_cycle.seven_days_completed.connect(func() -> void:
		completed_signals["count"] = int(completed_signals["count"]) + 1
	)
	var completion_boundary := DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE

	day_cycle.advance(completion_boundary - 0.1)
	_assert_false(day_cycle.completed, "day seven is not complete one tick before the boundary")
	_assert_equal(day_cycle.current_day, 7, "the final in-progress day is labeled day seven")
	_assert_equal(completed_signals["count"], 0, "completion signal has not fired early")

	day_cycle.advance(0.1)
	_assert_true(day_cycle.completed, "day seven completes exactly at the boundary")
	_assert_approximately(day_cycle.elapsed_seconds, completion_boundary, 0.0001, "elapsed time clamps to the boundary")
	_assert_equal(completed_signals["count"], 1, "completion signal fires once")
	_assert_equal(day_cycle.get_clock_text(), "DAY 7 COMPLETE", "clock reports the completed objective")

	day_cycle.advance(10.0)
	_assert_approximately(day_cycle.elapsed_seconds, completion_boundary, 0.0001, "completed clock does not advance")
	_assert_equal(completed_signals["count"], 1, "completion signal remains single-shot")
	_dispose(day_cycle)


func _test_day_seven_requires_sealed_breathable_wing() -> void:
	var game := _spawn_game()
	game.begin_shift()
	for resident: VaultResident in game.residents:
		resident.work_allowed.haul = false
		resident.work_allowed.craft = false
	var completion_boundary := DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE
	game.day_cycle.advance(completion_boundary - VaultGame.SIMULATION_TICK)
	game.breach_system.advance(0.0, completion_boundary - VaultGame.SIMULATION_TICK)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.OPEN, "unanswered pressure hatch is open before day seven completes")

	game._simulation_step(VaultGame.SIMULATION_TICK)
	_assert_true(game.day_cycle.completed, "seven-day clock can complete while the hatch remains open")
	_assert_false(game.ended, "completed clock does not win while the hatch remains unsealed")
	_assert_equal(game.outcome, "", "unsealed completed wing has no premature outcome")
	_assert_true(game.get_alive_count() > 0, "victory gate is the hatch rather than colony loss")
	game.player_orders.refresh()
	_assert_true("VICTORY PENDING // SEAL HATCH" in game.player_orders.objective_label.text, "completed clock names the unsealed hatch victory blocker")
	_assert_true("VICTORY PENDING · SEAL HATCH" in game.player_orders.alert_label.text, "alerts keep the pending hatch action visible")

	_assert_equal(game.breach_system.add_delivery(BreachSystem.PATCH_COST), BreachSystem.PATCH_COST, "late response accepts its four salvage")
	_assert_true(game.breach_system.apply_patch_work(BreachSystem.PATCH_WORK_SECONDS), "late eight-second patch seals the hatch")
	game.oxygen_system.oxygen = 0.0
	_assert_false(game.ended, "sealing waits for the next simulation evaluation before declaring victory")
	game._simulation_step(VaultGame.SIMULATION_TICK)
	_assert_false(game.ended, "sealed day-seven wing cannot win with unbreathable oxygen")
	_assert_equal(game.outcome, "", "unbreathable completed wing has no premature outcome")
	_assert_true(game.get_alive_count() > 0, "oxygen victory gate is evaluated before suffocation becomes colony loss")
	game.player_orders.refresh()
	_assert_true("VICTORY PENDING // RESTORE O2 TO 15%" in game.player_orders.objective_label.text, "completed clock names the oxygen victory blocker")
	_assert_true("VICTORY PENDING · O2 >= 15%" in game.player_orders.alert_label.text, "alerts state the exact breathable threshold")

	game.oxygen_system.oxygen = OxygenSystem.STARTING_OXYGEN
	game._simulation_step(VaultGame.SIMULATION_TICK)
	_assert_true(game.ended, "sealed day-seven wing reaches an outcome")
	_assert_equal(game.outcome, "win", "sealed hatch and breathable oxygen unlock day-seven victory")
	_dispose(game)


func _test_save_load_round_trip() -> void:
	_remove_test_save()
	var original := _spawn_game()
	var dig_target := MapGrid.CHAMBER.position + Vector2i.LEFT
	_assert_true(original.map_grid.queue_dig(dig_target), "round-trip fixture includes a dig designation")
	_assert_false(original.map_grid.apply_dig_work(dig_target, 2.5), "partial dig remains incomplete")
	original.job_system.queue_dig(dig_target)
	_assert_true(original.place_blueprint(VaultBuilding.Kind.BED, Vector2i(18, 12)), "round-trip fixture includes a blueprint")
	original.food_system.meals = 7
	original.food_system.raw_food = 3
	original.food_system.salvage = 41
	original.day_cycle.advance(17.25)
	original.residents[0].needs.food = 54.5
	original.residents[0].needs.rest = 63.25
	original.residents[0].work_allowed["cook"] = false
	original.world_camera.position = Vector2(432.5, 321.25)
	original.world_camera.zoom = Vector2.ONE * 1.25
	var snapshot_before := original.create_snapshot()

	_assert_true(original.save_game(false, SAVE_TEST_PATH), "snapshot writes to the isolated test save")
	var loaded := _spawn_game()
	_assert_true(loaded.load_game(SAVE_TEST_PATH), "fresh game loads the saved wing")
	_assert_variants_equal(snapshot_before, loaded.create_snapshot(), "loaded snapshot")
	var stable_snapshot := loaded.create_snapshot()
	_assert_false(loaded.apply_snapshot({}), "malformed snapshot is rejected")
	_assert_variants_equal(stable_snapshot, loaded.create_snapshot(), "rejected snapshot does not mutate the active wing")

	original.step_simulation(5.0)
	loaded.step_simulation(5.0)
	_assert_variants_equal(original.create_snapshot(), loaded.create_snapshot(), "original and loaded games remain deterministic")

	_dispose(loaded)
	_dispose(original)
	_remove_test_save()


func _test_atomic_save_recovery() -> void:
	_remove_test_save(ATOMIC_SAVE_TEST_PATH)
	var save_load := SaveLoad.new()
	root.add_child(save_load)
	var stable_snapshot := {"marker": "stable"}
	var replacement_snapshot := {"marker": "replacement"}
	_assert_true(bool(save_load.save_snapshot(stable_snapshot, ATOMIC_SAVE_TEST_PATH).ok), "initial save writes successfully")

	var temporary_absolute := ProjectSettings.globalize_path(ATOMIC_SAVE_TEST_PATH + ".tmp")
	_assert_equal(DirAccess.make_dir_absolute(temporary_absolute), OK, "test blocks the temporary file with a directory")
	var interrupted := save_load.save_snapshot(replacement_snapshot, ATOMIC_SAVE_TEST_PATH)
	_assert_false(bool(interrupted.ok), "failed temporary write is reported")
	var preserved := save_load.load_snapshot(ATOMIC_SAVE_TEST_PATH)
	_assert_true(bool(preserved.ok), "prior slot still loads after a failed replacement")
	_assert_equal(preserved.snapshot.marker, "stable", "failed replacement preserves the prior snapshot")
	DirAccess.remove_absolute(temporary_absolute)

	var target_absolute := ProjectSettings.globalize_path(ATOMIC_SAVE_TEST_PATH)
	var backup_absolute := ProjectSettings.globalize_path(ATOMIC_SAVE_TEST_PATH + ".bak")
	_assert_equal(DirAccess.rename_absolute(target_absolute, backup_absolute), OK, "test simulates an interrupted promotion")
	var recovered := save_load.load_snapshot(ATOMIC_SAVE_TEST_PATH)
	_assert_true(bool(recovered.ok), "orphaned intact backup is recoverable")
	_assert_equal(recovered.snapshot.marker, "stable", "backup recovery returns the prior snapshot")
	_assert_true(bool(save_load.save_snapshot(replacement_snapshot, ATOMIC_SAVE_TEST_PATH).ok), "next save completes from the recovered state")
	_assert_false(FileAccess.file_exists(ATOMIC_SAVE_TEST_PATH + ".bak"), "successful promotion removes the backup")
	var replaced := save_load.load_snapshot(ATOMIC_SAVE_TEST_PATH)
	_assert_equal(replaced.snapshot.marker, "replacement", "successful replacement becomes the active slot")

	_dispose(save_load)
	_remove_test_save(ATOMIC_SAVE_TEST_PATH)


func _test_unmanaged_loss() -> void:
	var game := _spawn_game()
	game.begin_shift()
	game.step_simulation(DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE)

	_assert_true(game.ended, "untouched starting wing reaches an outcome")
	_assert_equal(game.outcome, "loss", "starting supplies and finite oxygen cannot sustain an unmanaged wing")
	_assert_equal(game.get_alive_count(), 0, "all unmanaged residents eventually die")
	_assert_true(game.breach_system.is_sealed(), "unmanaged workers still contain the scripted breach before colony loss")
	_assert_false(game.day_cycle.completed, "colony fails before completing seven days")
	_assert_true(
		game.day_cycle.elapsed_seconds < DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE,
		"loss occurs before the survival boundary",
	)
	_dispose(game)


func _test_required_first_session_path() -> void:
	var game := _spawn_game()
	game.begin_shift()
	game.set_tool("dig")
	var dig_cells: Array[Vector2i] = []
	for x in [16, 15, 14, 13]:
		for y in [14, 15, 16]:
			dig_cells.append(Vector2i(x, y))
	for cell: Vector2i in dig_cells:
		_assert_true(game.issue_order(cell), "required expansion accepts dig designation at %s" % cell)
	game.step_simulation(40.0)
	var plans := [
		[VaultBuilding.Kind.BED, Vector2i(27, 12)],
		[VaultBuilding.Kind.BED, Vector2i(26, 12)],
		[VaultBuilding.Kind.GENERATOR, Vector2i(21, 12)],
		[VaultBuilding.Kind.KITCHEN, Vector2i(22, 12)],
		[VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12)],
		[VaultBuilding.Kind.AIR_RECYCLER, Vector2i(24, 12)],
	]
	for plan in plans:
		_assert_true(game.place_blueprint(int(plan[0]), plan[1]), "required fixture blueprint is accepted")
	game.step_simulation(BreachSystem.WARNING_AT_SECONDS - game.day_cycle.elapsed_seconds + VaultGame.SIMULATION_TICK)
	_assert_true(game.user_paused and game.player_orders.breach_warning_panel.visible, "required path reaches the hatch warning")
	game.player_orders.breach_resume_button.pressed.emit()
	_assert_true(game.breach_system.warning_acknowledged, "required path acknowledges the hatch warning")

	var remaining := DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE - game.day_cycle.elapsed_seconds
	game.step_simulation(remaining + 1.0)

	for cell: Vector2i in dig_cells:
		_assert_equal(game.map_grid.get_tile(cell), MapGrid.Tile.FLOOR, "required expansion tile was excavated")
	for plan in plans:
		var building: VaultBuilding = game.get_building_at(plan[1])
		_assert_true(building != null and building.complete, "required fixture at %s was supplied and assembled" % plan[1])
	_assert_equal(game.outcome, "win", "the twelve-dig required path reaches day-seven victory")
	_assert_equal(game.get_alive_count(), 4, "the required path preserves all four residents")
	_assert_true(game.breach_system.is_sealed(), "the required path finishes with a sealed hatch")
	_assert_true(game.oxygen_system.oxygen >= OxygenSystem.LOW_OXYGEN_THRESHOLD, "the required path finishes above the low-air band")
	_assert_true(game.food_system.meals > 0 or game.food_system.raw_food > 0, "the required path retains food")
	_assert_true(game.food_system.salvage >= 10, "the required path retains ten salvage for one recoverable mistake")
	_dispose(game)


func _test_player_order_survival_plan() -> void:
	var game := _spawn_game()
	_assert_equal(game.food_system.meals, 12, "first-session route starts with the tuned meal headroom")
	_assert_equal(game.food_system.raw_food, 4, "first-session route starts with the tuned raw-food headroom")
	_assert_equal(game.food_system.salvage, 48, "first-session route starts with the tuned salvage headroom")
	game.begin_shift()
	game.set_tool("dig")
	var dig_cells: Array[Vector2i] = []
	for x in [16, 15, 14, 13, 12]:
		for y in [14, 15, 16]:
			dig_cells.append(Vector2i(x, y))
	for cell: Vector2i in dig_cells:
		_assert_true(game.issue_order(cell), "planned expansion accepts dig designation at %s" % cell)
	var plans := [
		[VaultBuilding.Kind.BED, Vector2i(27, 12)],
		[VaultBuilding.Kind.BED, Vector2i(26, 12)],
		[VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(20, 12)],
		[VaultBuilding.Kind.GENERATOR, Vector2i(21, 12)],
		[VaultBuilding.Kind.KITCHEN, Vector2i(22, 12)],
		[VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12)],
		[VaultBuilding.Kind.AIR_RECYCLER, Vector2i(24, 12)],
	]
	for plan in plans:
		_assert_true(game.place_blueprint(int(plan[0]), plan[1]), "survival fixture blueprint is accepted")
	var starting_lumen: VaultBuilding = game.get_building_at(Vector2i(22, 14))

	game.step_simulation(BreachSystem.WARNING_AT_SECONDS)
	_assert_true(game.user_paused and game.player_orders.breach_warning_panel.visible, "first-session path reaches the unacknowledged hatch warning")
	game.player_orders.breach_resume_button.pressed.emit()
	_assert_true(game.breach_system.warning_acknowledged, "first-session path uses Resume Response to acknowledge the warning")
	_assert_false(game.user_paused or game.player_orders.breach_warning_panel.visible, "Resume Response returns the first-session path to play")
	game.step_simulation(200.0 - BreachSystem.WARNING_AT_SECONDS)
	_assert_true(game.food_system.salvage >= 0, "ordered construction never overdraws salvage")
	_assert_true(game.breach_system.is_sealed(), "player-order plan automatically contains the first breach")
	var rec_console: VaultBuilding = game.get_building_at(Vector2i(20, 12))
	_assert_true(game.power_grid.is_building_shed(rec_console.building_id), "full survival load sheds optional recreation first")
	_assert_true(game.toggle_building_enabled(starting_lumen.building_id), "player frees one power by disabling the starting lumen")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.RECREATION_CONSOLE), 1, "freed capacity restores the rec console")

	var remaining := DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE - game.day_cycle.elapsed_seconds
	game.step_simulation(remaining + VaultGame.SIMULATION_TICK)
	var initial_floor_count := MapGrid.CHAMBER.size.x * MapGrid.CHAMBER.size.y
	_assert_true(game.map_grid.get_floor_cells().size() >= initial_floor_count + 12, "optional route completes at least the twelve-tile expansion target")
	for plan in plans:
		var building: VaultBuilding = game.get_building_at(plan[1])
		_assert_true(building != null and building.complete, "survival fixture at %s was supplied and assembled" % plan[1])
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.AIR_RECYCLER), 1, "player-order plan powers its air recycler")
	_assert_true(game.oxygen_system.net_rate > 0.0, "ordered life support recovers oxygen after resident consumption")
	_assert_true(game.ended, "first-session order path reaches a terminal outcome")
	_assert_true(game.day_cycle.completed, "first-session order path completes all seven days")
	_assert_equal(game.outcome, "win", "a player-order-only plan reaches day-seven victory")
	_assert_equal(game.get_alive_count(), 4, "the forgiving first-session path preserves all four residents")
	_assert_true(game.breach_system.is_sealed(), "the first-session win retains a sealed maintenance hatch")
	_assert_true(game.oxygen_system.oxygen >= OxygenSystem.CRITICAL_OXYGEN_THRESHOLD, "the first-session win finishes at or above 15 percent oxygen")
	_assert_true(game.oxygen_system.oxygen >= OxygenSystem.LOW_OXYGEN_THRESHOLD, "the managed path finishes with oxygen headroom above the low-air band")
	_assert_true(game.food_system.meals > 0 or game.food_system.raw_food > 0, "the managed path finishes with food headroom")
	_assert_true(game.food_system.salvage >= 7, "the fifteen-tile expansion leaves at least seven salvage after the optional console and hatch patch")
	_dispose(game)


func _test_managed_day_seven_win(with_medical := false) -> void:
	var game := _spawn_game()
	var bed_cells: Array[Vector2i] = [
		Vector2i(18, 12),
		Vector2i(19, 12),
		Vector2i(20, 12),
		Vector2i(21, 12),
	]
	for cell: Vector2i in bed_cells:
		_add_completed_building(game, VaultBuilding.Kind.BED, cell)
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(22, 12))
	var console := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(23, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(25, 12))
	var grow_tray := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(26, 12))
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(27, 12))
	var recycler := _add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(24, 12))
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.begin_shift()

	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.BED), 4, "managed wing has one bunk per resident")
	_assert_true(console.powered and grow_tray.powered and kitchen.powered and recycler.powered, "mood, food, and oxygen fixtures start powered")
	_assert_true(game.oxygen_system.net_rate > 0.0, "managed recycler exceeds resident oxygen demand")
	if with_medical:
		game.step_simulation(90.0)
		_assert_true(game.place_blueprint(VaultBuilding.Kind.MEDICAL_BED, Vector2i(18, 13)), "medical blueprint uses the normal construction pipeline")
		game.residents[0].apply_damage(35.0)
		game.step_simulation(55.0)
		_assert_true(game.get_building_at(Vector2i(18, 13)).complete, "medical bed is supplied and built")
		_assert_true(game.residents[0].needs.health > 65.0, "medical care restores injury after the hatch event")
	game.step_simulation(DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE + VaultGame.SIMULATION_TICK)

	_assert_true(game.ended, "managed simulation reaches an outcome")
	_assert_equal(game.outcome, "win", "managed wing reaches the win state")
	_assert_true(game.day_cycle.completed, "seven-day clock is complete")
	_assert_true(game.breach_system.is_sealed(), "managed wing contains the first breach before victory")
	_assert_true(game.oxygen_system.is_breathable(), "managed wing remains breathable at victory")
	_assert_true(game.get_alive_count() >= 1, "at least one resident survives")
	var recreation_sessions := 0
	for resident: VaultResident in game.residents:
		recreation_sessions += resident.recreation_sessions
	_assert_true(recreation_sessions > 0, "managed residents use recreation before day seven")
	_assert_true(game.food_system.meals > 0 or game.food_system.raw_food > 0, "food loop remains productive")
	_dispose(game)


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


func _remove_test_save(path := SAVE_TEST_PATH) -> void:
	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _action_has_physical_key(action: StringName, physical_keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == physical_keycode:
			return true
	return false


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
