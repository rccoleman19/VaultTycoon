extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SAVE_TEST_PATH := "user://headless_round_trip.json"

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
	_run_case("powered kitchens cook at the starting meal stock", _test_cooking_at_starting_stock)
	_run_case("day seven completes only at the exact boundary", _test_exact_day_boundary)
	_run_case("save and load preserve a deterministic simulation", _test_save_load_round_trip)
	_run_case("an unmanaged wing starves before day seven", _test_unmanaged_loss)
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
	_assert_true(game.get_node_or_null("JobSystem") != null, "JobSystem exists")
	_assert_true(game.get_node_or_null("PlayerOrders/Interface") != null, "player-order UI was built")
	_assert_equal(game.residents.size(), 4, "exactly four starting residents")
	_assert_equal(game.get_alive_count(), 4, "all starting residents are alive")
	_assert_equal(game.buildings.size(), 3, "three emergency fixtures are present")
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


func _test_unmanaged_loss() -> void:
	var game := _spawn_game()
	game.begin_shift()
	game.step_simulation(DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE)

	_assert_true(game.ended, "untouched starting wing reaches an outcome")
	_assert_equal(game.outcome, "loss", "starting rations alone end in starvation")
	_assert_equal(game.get_alive_count(), 0, "all unmanaged residents eventually die")
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
	for x in [16, 15, 14]:
		for y in [14, 15, 16]:
			dig_cells.append(Vector2i(x, y))
	for cell: Vector2i in dig_cells:
		_assert_true(game.issue_order(cell), "planned expansion accepts dig designation at %s" % cell)
	var plans := [
		[VaultBuilding.Kind.BED, Vector2i(18, 12)],
		[VaultBuilding.Kind.BED, Vector2i(19, 12)],
		[VaultBuilding.Kind.GENERATOR, Vector2i(20, 12)],
		[VaultBuilding.Kind.GROW_TRAY, Vector2i(21, 12)],
		[VaultBuilding.Kind.KITCHEN, Vector2i(22, 12)],
	]
	for plan in plans:
		_assert_true(game.place_blueprint(int(plan[0]), plan[1]), "survival fixture blueprint is accepted")

	game.step_simulation(120.0)
	for cell: Vector2i in dig_cells:
		_assert_equal(game.map_grid.get_tile(cell), MapGrid.Tile.FLOOR, "planned expansion tile was excavated")
	for plan in plans:
		var building: VaultBuilding = game.get_building_at(plan[1])
		_assert_true(building != null and building.complete, "survival fixture was supplied and assembled")
	_assert_true(game.food_system.salvage >= 0, "ordered construction never overdraws salvage")

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
	game.power_grid.recalculate(game.buildings)
	game.begin_shift()

	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.BED), 4, "managed wing has one bunk per resident")
	_assert_true(grow_tray.powered and kitchen.powered, "food production fixtures start powered")
	game.step_simulation(DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE + VaultGame.SIMULATION_TICK)

	_assert_true(game.ended, "managed simulation reaches an outcome")
	_assert_equal(game.outcome, "win", "managed wing reaches the win state")
	_assert_true(game.day_cycle.completed, "seven-day clock is complete")
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


func _remove_test_save() -> void:
	var absolute_path := ProjectSettings.globalize_path(SAVE_TEST_PATH)
	if FileAccess.file_exists(SAVE_TEST_PATH):
		DirAccess.remove_absolute(absolute_path)


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
