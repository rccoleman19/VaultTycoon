extends "res://tests/test_runner.gd"


func _run() -> void:
	_run_case("grow-tray output is stored only after a preferred-zone haul", _test_raw_food_haul)
	_run_case("cooked meals wait for an eligible hauler before becoming stored", _test_meal_haul)
	_run_case("disabled Haul preserves repeated raw-food and meal output", _test_pending_backlog)
	_run_case("food cargo uses fallback destinations and reroutes in flight", _test_fallbacks_and_reroute)
	_run_case("food cargo survives interruption, producer removal, and death", _test_food_haul_interruption)
	_run_case("an injured sole hauler finishes critical carried food", _test_injured_food_carrier)
	_run_case("food cargo saves round trip and malformed payloads reject atomically", _test_food_haul_saves)
	_run_case("stockpile guidance names every supported cargo type", _test_food_haul_hud)
	print("FOOD HAULING TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _food_game() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		for work_type: String in VaultResident.WORK_TYPES:
			resident.set_work_priority(work_type, VaultResident.PRIORITY_DISABLED)
	return game


func _finish_food_hauls(game: VaultGame) -> void:
	for _tick in 800:
		game.job_system.advance(VaultGame.SIMULATION_TICK)
		if game.job_system.get_pending_raw_food() == 0 and game.job_system.get_pending_meals() == 0:
			return
	_assert_true(false, "food hauling completes within eighty seconds")


func _wait_for_meal_output(game: VaultGame) -> void:
	for _tick in 60:
		game.job_system.advance(VaultGame.SIMULATION_TICK)
		if game.job_system.get_pending_meals() > 0:
			return
	_assert_true(false, "cooking produces a meal-haul job within six seconds")


func _test_raw_food_haul() -> void:
	var game := _food_game()
	var source := Vector2i(20, 12)
	var destination := Vector2i(27, 19)
	var worker: VaultResident = game.residents[0]
	worker.set_work_priority("haul", 1)
	worker.position = game.map_grid.cell_to_world(source)
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(18, 12))
	var grow_tray := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, source)
	game.map_grid.paint_stockpile(destination)
	game.power_grid.recalculate(game.buildings)
	var stored_before := game.food_system.raw_food

	_assert_true(grow_tray.powered, "raw-food fixture is powered")
	grow_tray.production_progress = FoodSystem.GROW_SECONDS - VaultGame.SIMULATION_TICK
	game.food_system.advance(VaultGame.SIMULATION_TICK, game.buildings)
	_assert_approximately(grow_tray.production_progress, 0.0, 0.0001, "grow cycle completes at its exact boundary")
	_assert_equal(game.food_system.raw_food, stored_before, "produced raw food is not stored at the tray")
	_assert_equal(game.job_system.get_pending_raw_food(), FoodSystem.GROW_YIELD, "grow output becomes pending cargo")

	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_equal(worker.current_job_type, JobSystem.JobType.HAUL_RAW_FOOD, "raw-food delivery is Haul work")
	_assert_equal(worker.carrying, FoodSystem.GROW_YIELD, "hauler physically picks up raw food")
	_assert_equal(game.food_system.raw_food, stored_before, "carried raw food remains outside stored inventory")
	_finish_food_hauls(game)
	_assert_equal(worker.get_cell(game.map_grid), destination, "raw food reaches the preferred zone")
	_assert_equal(game.food_system.raw_food, stored_before + FoodSystem.GROW_YIELD, "zone deposit credits raw food exactly once")
	_assert_equal(game.job_system.get_pending_raw_food(), 0, "completed raw-food cargo is no longer pending")
	_assert_equal(worker.carrying, 0, "hauler is empty-handed after the raw-food deposit")
	game.job_system.advance(1.0)
	_assert_equal(game.food_system.raw_food, stored_before + FoodSystem.GROW_YIELD, "completed raw-food jobs cannot duplicate inventory")
	_dispose(game)


func _test_meal_haul() -> void:
	var game := _food_game()
	var source := Vector2i(20, 12)
	var destination := Vector2i(27, 19)
	var cook: VaultResident = game.residents[0]
	var hauler: VaultResident = game.residents[1]
	cook.set_work_priority("cook", 1)
	cook.position = game.map_grid.cell_to_world(source)
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(18, 12))
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, source)
	game.map_grid.paint_stockpile(destination)
	game.power_grid.recalculate(game.buildings)
	game.food_system.raw_food = FoodSystem.COOK_INPUT
	var meals_before := game.food_system.meals

	_assert_true(kitchen.powered, "meal fixture is powered")
	_wait_for_meal_output(game)
	_assert_equal(game.food_system.raw_food, 0, "cooking consumes one unit of stored raw food")
	_assert_equal(game.food_system.meals, meals_before, "finished cooking does not store the meal at the kitchen")
	_assert_equal(game.job_system.get_pending_meals(), FoodSystem.COOK_OUTPUT, "cooked output becomes pending meal cargo")
	game.job_system.advance(1.0)
	_assert_equal(game.job_system.get_pending_meals(), FoodSystem.COOK_OUTPUT, "meal waits while every resident has Haul off")
	_assert_equal(game.food_system.meals, meals_before, "waiting meal cannot be eaten from shared inventory")

	hauler.set_work_priority("haul", 1)
	hauler.position = game.map_grid.cell_to_world(source)
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_equal(hauler.current_job_type, JobSystem.JobType.HAUL_MEAL, "meal delivery is Haul work rather than Cook work")
	_assert_equal(hauler.carrying, FoodSystem.COOK_OUTPUT, "hauler physically picks up the cooked meal")
	_finish_food_hauls(game)
	_assert_equal(hauler.get_cell(game.map_grid), destination, "meal reaches the preferred zone")
	_assert_equal(game.food_system.meals, meals_before + FoodSystem.COOK_OUTPUT, "meal becomes stored exactly once on deposit")
	_assert_equal(game.job_system.get_pending_meals(), 0, "completed meal cargo is no longer pending")
	game.job_system.advance(1.0)
	_assert_equal(game.food_system.meals, meals_before + FoodSystem.COOK_OUTPUT, "completed meal jobs cannot duplicate inventory")
	_dispose(game)


func _test_pending_backlog() -> void:
	var game := _food_game()
	var source := Vector2i(20, 12)
	var destination := Vector2i(26, 19)
	var raw_before := game.food_system.raw_food
	var meals_before := game.food_system.meals
	game.map_grid.paint_stockpile(destination)
	game.job_system.queue_raw_food(source, 2)
	game.job_system.queue_raw_food(source, 3)
	game.job_system.queue_meals(source, 2)

	_assert_equal(game.job_system.get_pending_raw_food(), 5, "repeated raw-food yields at one source accumulate")
	_assert_equal(game.job_system.get_pending_meals(), 2, "repeated meal output remains fully represented")
	for _tick in 10:
		game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_equal(game.job_system.get_pending_raw_food(), 5, "raw-food backlog remains pending with Haul off")
	_assert_equal(game.job_system.get_pending_meals(), 2, "meal backlog remains pending with Haul off")
	_assert_equal(game.food_system.raw_food, raw_before, "pending raw-food backlog is not prematurely stored")
	_assert_equal(game.food_system.meals, meals_before, "pending meal backlog is not prematurely stored")

	var worker: VaultResident = game.residents[0]
	worker.set_work_priority("haul", 1)
	worker.position = game.map_grid.cell_to_world(source)
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_equal(worker.carrying, 5, "hauler picks up the complete raw-food backlog")
	game.job_system.queue_raw_food(source, 3)
	_assert_equal(worker.carrying, 5, "new production does not teleport into the in-flight stack")
	_assert_equal(game.job_system.get_pending_raw_food(), 8, "new production remains represented beside in-flight cargo")
	_finish_food_hauls(game)
	_assert_equal(game.food_system.raw_food, raw_before + 8, "all accumulated and in-flight raw food is conserved")
	_assert_equal(game.food_system.meals, meals_before + 2, "all accumulated meals are conserved")
	_assert_equal(game.job_system.get_pending_raw_food(), 0, "raw-food backlog drains completely")
	_assert_equal(game.job_system.get_pending_meals(), 0, "meal backlog drains completely")
	_dispose(game)


func _test_fallbacks_and_reroute() -> void:
	for mode in 3:
		var game := _food_game()
		var source := Vector2i(20, 12)
		var worker: VaultResident = game.residents[0]
		worker.set_work_priority("haul", 1)
		worker.position = game.map_grid.cell_to_world(source)
		if mode == 1:
			var island := Vector2i(2, 2)
			game.map_grid.cells[island.y * MapGrid.WIDTH + island.x] = MapGrid.Tile.FLOOR
			game.map_grid.paint_stockpile(island)
		elif mode == 2:
			for building: VaultBuilding in game.buildings.duplicate():
				if building.kind == VaultBuilding.Kind.STOCKPILE:
					game.deconstruct_building(building.building_id)
		var expected := game.job_system._stockpile_cell()
		var raw_before := game.food_system.raw_food
		game.job_system.queue_raw_food(source, 1)
		_finish_food_hauls(game)
		_assert_equal(worker.get_cell(game.map_grid), expected, "fallback %d sends raw food to the existing destination" % mode)
		_assert_equal(game.food_system.raw_food, raw_before + 1, "fallback %d conserves raw food" % mode)
		if mode == 2:
			_assert_equal(expected, game.map_grid.get_chamber_center(), "missing Bay falls back to the chamber center")
		_dispose(game)

	var reroute_game := _food_game()
	var reroute_source := Vector2i(20, 12)
	var first_destination := Vector2i(27, 19)
	var replacement_destination := Vector2i(25, 19)
	var reroute_worker: VaultResident = reroute_game.residents[0]
	reroute_worker.set_work_priority("haul", 1)
	reroute_worker.position = reroute_game.map_grid.cell_to_world(reroute_source)
	reroute_game.map_grid.paint_stockpile(first_destination)
	var meals_before := reroute_game.food_system.meals
	reroute_game.job_system.queue_meals(reroute_source, 1)
	reroute_game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_equal(reroute_worker.carrying, 1, "meal is in flight before its zone changes")
	reroute_game.map_grid.clear_stockpile(first_destination)
	reroute_game.map_grid.paint_stockpile(replacement_destination)
	_finish_food_hauls(reroute_game)
	_assert_equal(reroute_worker.get_cell(reroute_game.map_grid), replacement_destination, "in-flight meal reroutes to the replacement zone")
	_assert_equal(reroute_game.food_system.meals, meals_before + 1, "rerouting conserves the meal")
	_dispose(reroute_game)


func _test_food_haul_interruption() -> void:
	var game := _food_game()
	var source := Vector2i(20, 12)
	var destination := Vector2i(27, 19)
	var worker: VaultResident = game.residents[0]
	worker.set_work_priority("haul", 1)
	worker.position = game.map_grid.cell_to_world(source)
	game.map_grid.paint_stockpile(destination)
	var producer := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, source)
	var raw_before := game.food_system.raw_food
	game.job_system.queue_raw_food(source, 2)
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_equal(worker.carrying, 2, "worker carries raw food before interruption")
	game.job_system.queue_raw_food(source, 1)
	_assert_true(game.set_work_priority(worker.resident_id, "haul", VaultResident.PRIORITY_DISABLED), "turning Haul off interrupts food delivery")
	_assert_equal(worker.carrying, 0, "interruption empties the worker's hands")
	_assert_equal(game.job_system.get_pending_raw_food(), 3, "interruption returns carried output to its source backlog")
	_assert_equal(game.food_system.raw_food, raw_before, "interruption cannot credit raw food")
	_assert_true(game.deconstruct_building(producer.building_id), "completed producer can be removed after creating output")
	_assert_equal(game.job_system.get_pending_raw_food(), 3, "producer removal preserves already-produced cargo")
	_assert_true(game.set_work_priority(worker.resident_id, "haul", 1), "Haul can be re-enabled for a safe retry")
	_finish_food_hauls(game)
	_assert_equal(game.food_system.raw_food, raw_before + 3, "retried raw-food output is deposited once")

	var meals_before := game.food_system.meals
	worker.position = game.map_grid.cell_to_world(source)
	game.job_system.queue_meals(source, 2)
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_equal(worker.carrying, 2, "worker carries meals before death")
	worker.kill()
	_assert_equal(game.job_system.get_pending_meals(), 2, "death returns carried meals to the pending job")
	_assert_equal(game.food_system.meals, meals_before, "death cannot credit carried meals")
	var replacement: VaultResident = game.residents[1]
	replacement.set_work_priority("haul", 1)
	replacement.position = game.map_grid.cell_to_world(source)
	_finish_food_hauls(game)
	_assert_equal(game.food_system.meals, meals_before + 2, "another hauler deposits the recovered meals exactly once")
	_dispose(game)


func _test_injured_food_carrier() -> void:
	var game := _food_game()
	var source := Vector2i(20, 12)
	var destination := Vector2i(27, 19)
	var worker: VaultResident = game.residents[0]
	worker.set_work_priority("haul", 1)
	worker.position = game.map_grid.cell_to_world(source)
	worker.needs.health = 80.0
	var medical_bed := _add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(19, 12))
	game.map_grid.paint_stockpile(destination)
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_equal(worker.medical_bed_id, medical_bed.building_id, "injured hauler initially reserves available medical care")

	worker.position = game.map_grid.cell_to_world(source)
	game.food_system.meals = 0
	game.job_system.queue_meals(source, 1)
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_equal(worker.current_job_type, JobSystem.JobType.HAUL_MEAL, "critical meal output releases the sole hauler from medical care")
	_assert_equal(worker.carrying, 1, "injured hauler picks up the last pending meal")
	_assert_equal(worker.medical_bed_id, -1, "medical reservation clears while the ration pipeline is critical")

	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_equal(worker.current_job_type, JobSystem.JobType.HAUL_MEAL, "carried meal remains critical after its source backlog reaches zero")
	_assert_equal(worker.carrying, 1, "injured carrier does not drop and reclaim the meal in a loop")
	_assert_equal(worker.medical_bed_id, -1, "injured carrier does not re-enter medical before deposit")
	_finish_food_hauls(game)
	_assert_equal(game.food_system.meals, 1, "injured sole hauler deposits the critical meal exactly once")
	_assert_equal(game.job_system.get_pending_meals(), 0, "critical meal job completes without livelock")
	_dispose(game)


func _test_food_haul_saves() -> void:
	var game := _food_game()
	var raw_source := Vector2i(20, 12)
	var meal_source := Vector2i(21, 12)
	var destination := Vector2i(27, 19)
	var worker: VaultResident = game.residents[0]
	worker.set_work_priority("haul", 1)
	worker.position = game.map_grid.cell_to_world(raw_source)
	game.map_grid.paint_stockpile(destination)
	game.job_system.queue_raw_food(raw_source, 2)
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_equal(worker.carrying, 2, "save fixture captures raw food in flight")
	game.job_system.queue_raw_food(raw_source, 3)
	game.job_system.queue_meals(meal_source, 1)
	var raw_before := game.food_system.raw_food
	var meals_before := game.food_system.meals
	var snapshot := game.create_snapshot()
	_assert_equal(snapshot.jobs.raw_food, [[raw_source.x, raw_source.y, 5]], "save combines queued and in-flight raw food canonically")
	_assert_equal(snapshot.jobs.meals, [[meal_source.x, meal_source.y, 1]], "meal save payload is canonical")

	_assert_true(game.apply_snapshot(snapshot), "pending and in-flight food cargo loads")
	_assert_equal(game.job_system.get_pending_raw_food(), 5, "loaded raw-food cargo restarts at its source")
	_assert_equal(game.job_system.get_pending_meals(), 1, "loaded meal cargo remains pending")
	_finish_food_hauls(game)
	_assert_equal(game.food_system.raw_food, raw_before + 5, "loaded raw-food cargo deposits exactly once")
	_assert_equal(game.food_system.meals, meals_before + 1, "loaded meal cargo deposits exactly once")

	var malformed_payloads := [
		["raw_food", null],
		["raw_food", [[raw_source.x, raw_source.y]]],
		["raw_food", [[raw_source.x, raw_source.y, 0]]],
		["raw_food", [[raw_source.x + 0.5, raw_source.y, 1]]],
		["raw_food", [[-1, raw_source.y, 1]]],
		["raw_food", [[0, 0, 1]]],
		["raw_food", [[raw_source.x, raw_source.y, 1], [raw_source.x, raw_source.y, 2]]],
		["meals", [[meal_source.x, meal_source.y, "1"]]],
	]
	for malformed: Array in malformed_payloads:
		var invalid := snapshot.duplicate(true)
		invalid.jobs[malformed[0]] = malformed[1]
		var before := game.create_snapshot()
		_assert_false(game.apply_snapshot(invalid), "malformed %s cargo is rejected" % malformed[0])
		_assert_variants_equal(before, game.create_snapshot(), "malformed food-cargo load is atomic")

	var legacy := snapshot.duplicate(true)
	legacy.jobs.erase("raw_food")
	legacy.jobs.erase("meals")
	_assert_true(game.apply_snapshot(legacy), "legacy snapshot without food-cargo arrays loads")
	_assert_equal(game.job_system.get_pending_raw_food(), 0, "legacy snapshot starts without pending raw food")
	_assert_equal(game.job_system.get_pending_meals(), 0, "legacy snapshot starts without pending meals")
	game.job_system.queue_raw_food(raw_source, 1)
	game.job_system.queue_meals(meal_source, 1)
	game.new_game(false)
	_assert_equal(game.job_system.get_pending_raw_food(), 0, "New Wing clears pending raw food")
	_assert_equal(game.job_system.get_pending_meals(), 0, "New Wing clears pending meals")
	_dispose(game)


func _test_food_haul_hud() -> void:
	var game := _food_game()
	game.job_system.queue_raw_food(Vector2i(20, 12), 2)
	game.job_system.queue_meals(Vector2i(21, 12), 1)
	game.set_tool("zone")
	game.player_orders.refresh()
	var tooltip: String = str(game.player_orders.command_buttons.zone.tooltip_text).to_lower()
	var tool_help: String = str(game.player_orders.tool_status.text).to_lower()
	for cargo_name in ["salvage", "raw food", "meal"]:
		_assert_true(cargo_name in tooltip, "zone tooltip names %s cargo" % cargo_name)
		_assert_true(cargo_name in tool_help, "active zone help names %s cargo" % cargo_name)
	_assert_true("MEALS 12 (+1)" in game.player_orders.resource_label.text, "resource HUD separates pending meals from stored meals")
	_assert_true("RAW 4 (+2)" in game.player_orders.resource_label.text, "resource HUD separates pending raw food from stored raw food")
	_assert_true("awaiting Haul" in game.player_orders.resource_label.tooltip_text, "resource HUD explains pending food counts")
	_dispose(game)
