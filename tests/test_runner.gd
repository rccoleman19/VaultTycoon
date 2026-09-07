extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SAVE_TEST_PATH := "user://headless_round_trip.json"
const BREACH_SAVE_TEST_PATH := "user://headless_breach_round_trip.json"
const OXYGEN_SAVE_TEST_PATH := "user://headless_oxygen_round_trip.json"
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
	_run_case("dig orders complete through the job system", _test_dig_completion)
	_run_case("blueprints are supplied and constructed", _test_blueprint_build)
	_run_case("cancel previews and powered checklist match their actions", _test_order_preview_and_checklist)
	_run_case("power is allocated by supply and priority", _test_power_allocation)
	_run_case("living residents consume shared oxygen within hard bounds", _test_oxygen_consumption_and_clamping)
	_run_case("air recyclers require power and retain life-support priority", _test_air_recycler_power_and_rates)
	_run_case("critical oxygen damages only for exact exposure time", _test_oxygen_threshold_damage)
	_run_case("powered kitchens cook at the starting meal stock", _test_cooking_at_starting_stock)
	_run_case("breach warning triggers exactly once and pauses the shift", _test_breach_warning_interrupt)
	_run_case("breach blockers and urgent jobs drive the patch sequence", _test_breach_response_jobs)
	_run_case("a prepared response seals during grace without damage", _test_prepared_breach_survival)
	_run_case("a patch completed at 80 seconds prevents the hatch opening", _test_exact_open_boundary_patch)
	_run_case("an open breach drains shared oxygen only until sealed", _test_breach_oxygen_drain_and_seal)
	_run_case("active and legacy breach snapshots load safely", _test_breach_save_load_compatibility)
	_run_case("active, malformed, and legacy oxygen snapshots load safely", _test_oxygen_save_load_compatibility)
	_run_case("day seven completes only at the exact boundary", _test_exact_day_boundary)
	_run_case("day-seven victory requires a sealed breathable wing", _test_day_seven_requires_sealed_breathable_wing)
	_run_case("save and load preserve a deterministic simulation", _test_save_load_round_trip)
	_run_case("interrupted save writes preserve the prior slot", _test_atomic_save_recovery)
	_run_case("an unmanaged wing fails before day seven", _test_unmanaged_loss)
	_run_case("player-issued dig and build orders sustain the wing", _test_player_order_survival_plan)
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
	_assert_equal(game.buildings.size(), 3, "three emergency fixtures are present")
	_assert_approximately(game.oxygen_system.oxygen, OxygenSystem.STARTING_OXYGEN, 0.0001, "new wing starts with full oxygen")
	_assert_true(game.tutorial_open, "opening briefing is visible")
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
	for action in ["camera_left", "camera_right", "camera_up", "camera_down"]:
		_assert_false(_action_has_physical_key(action, KEY_E), "Dig hotkey does not overlap %s" % action)

	var pan_event := InputEventKey.new()
	pan_event.physical_keycode = KEY_D
	pan_event.pressed = true
	game._unhandled_input(pan_event)
	_assert_equal(game.active_tool, "select", "camera-right D does not select Dig")

	var dig_event := InputEventKey.new()
	dig_event.physical_keycode = KEY_E
	dig_event.pressed = true
	game._unhandled_input(dig_event)
	_assert_equal(game.active_tool, "dig", "configured E hotkey selects Dig")
	_assert_equal(
		game._tool_help("kitchen"),
		"NUTRIENT STATION: cooks %d raw food into %d meal (10 salvage, 2 power)." % [FoodSystem.COOK_INPUT, FoodSystem.COOK_OUTPUT],
		"nutrient help is derived from the simulated recipe",
	)
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
	_assert_equal(game.food_system.salvage, 30 - building.get_cost(), "construction consumes the expected salvage")
	_dispose(game)


func _test_order_preview_and_checklist() -> void:
	var game := _spawn_game()
	game.begin_shift()
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
	_assert_true("[    ][/color]  Power a grow tray" in game.player_orders.checklist.text, "checklist leaves an unpowered tray incomplete")

	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(19, 12))
	game.power_grid.recalculate(game.buildings)
	game.player_orders._refresh_checklist()
	_assert_true(grow_tray.powered, "charge capacity powers the grow tray")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.GROW_TRAY), 1, "powered tray satisfies the powered count")
	_assert_true("[DONE][/color]  Power a grow tray" in game.player_orders.checklist.text, "checklist completes only after the tray is powered")
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

	_assert_equal(game.breach_system.add_delivery(BreachSystem.PATCH_COST), BreachSystem.PATCH_COST, "late response accepts its four salvage")
	_assert_true(game.breach_system.apply_patch_work(BreachSystem.PATCH_WORK_SECONDS), "late eight-second patch seals the hatch")
	game.oxygen_system.oxygen = 0.0
	_assert_false(game.ended, "sealing waits for the next simulation evaluation before declaring victory")
	game._simulation_step(VaultGame.SIMULATION_TICK)
	_assert_false(game.ended, "sealed day-seven wing cannot win with unbreathable oxygen")
	_assert_equal(game.outcome, "", "unbreathable completed wing has no premature outcome")
	_assert_true(game.get_alive_count() > 0, "oxygen victory gate is evaluated before suffocation becomes colony loss")

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


func _test_player_order_survival_plan() -> void:
	var game := _spawn_game()
	game.begin_shift()
	game.set_tool("dig")
	var dig_cells: Array[Vector2i] = []
	for x in [16, 15, 14, 13, 12]:
		for y in [14, 15, 16]:
			dig_cells.append(Vector2i(x, y))
	for cell: Vector2i in dig_cells:
		_assert_true(game.issue_order(cell), "planned expansion accepts dig designation at %s" % cell)
	var plans := [
		[VaultBuilding.Kind.BED, Vector2i(18, 12)],
		[VaultBuilding.Kind.BED, Vector2i(19, 12)],
		[VaultBuilding.Kind.GENERATOR, Vector2i(20, 12)],
		[VaultBuilding.Kind.AIR_RECYCLER, Vector2i(21, 12)],
		[VaultBuilding.Kind.GROW_TRAY, Vector2i(22, 12)],
		[VaultBuilding.Kind.KITCHEN, Vector2i(23, 12)],
	]
	for plan in plans:
		_assert_true(game.place_blueprint(int(plan[0]), plan[1]), "survival fixture blueprint is accepted")

	game.step_simulation(160.0)
	for cell: Vector2i in dig_cells:
		_assert_equal(game.map_grid.get_tile(cell), MapGrid.Tile.FLOOR, "planned expansion tile was excavated")
	for plan in plans:
		var building: VaultBuilding = game.get_building_at(plan[1])
		_assert_true(building != null and building.complete, "survival fixture at %s was supplied and assembled" % plan[1])
	_assert_true(game.food_system.salvage >= 0, "ordered construction never overdraws salvage")
	_assert_true(game.breach_system.is_sealed(), "player-order plan automatically contains the first breach")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.AIR_RECYCLER), 1, "player-order plan powers its air recycler")
	_assert_true(game.oxygen_system.net_rate > 0.0, "ordered life support recovers oxygen after resident consumption")

	var remaining := DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE - game.day_cycle.elapsed_seconds
	game.step_simulation(remaining + VaultGame.SIMULATION_TICK)
	_assert_equal(game.outcome, "win", "a player-order-only plan reaches day-seven victory")
	_assert_true(game.get_alive_count() >= 1, "the ordered plan leaves at least one survivor")
	_dispose(game)


func _test_managed_day_seven_win() -> void:
	var game := _spawn_game()
	var bed_cells: Array[Vector2i] = [
		Vector2i(18, 12),
		Vector2i(19, 12),
		Vector2i(20, 12),
		Vector2i(21, 12),
	]
	for cell: Vector2i in bed_cells:
		_add_completed_building(game, VaultBuilding.Kind.BED, cell)
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(25, 12))
	var grow_tray := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(26, 12))
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(27, 12))
	var recycler := _add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(24, 12))
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.begin_shift()

	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.BED), 4, "managed wing has one bunk per resident")
	_assert_true(grow_tray.powered and kitchen.powered and recycler.powered, "food and oxygen production fixtures start powered")
	_assert_true(game.oxygen_system.net_rate > 0.0, "managed recycler exceeds resident oxygen demand")
	game.step_simulation(DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE + VaultGame.SIMULATION_TICK)

	_assert_true(game.ended, "managed simulation reaches an outcome")
	_assert_equal(game.outcome, "win", "managed wing reaches the win state")
	_assert_true(game.day_cycle.completed, "seven-day clock is complete")
	_assert_true(game.breach_system.is_sealed(), "managed wing contains the first breach before victory")
	_assert_true(game.oxygen_system.is_breathable(), "managed wing remains breathable at victory")
	_assert_true(game.get_alive_count() >= 1, "at least one resident survives")
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
