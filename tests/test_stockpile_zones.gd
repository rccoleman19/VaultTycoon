extends "res://tests/test_runner.gd"

func _run() -> void:
	_run_case("zone paint, cancel, build, and HUD coexist", _test_zone_orders)
	_run_case("salvage is credited only after hauling to a preferred zone", _test_zone_haul)
	_run_case("no-zone and unreachable-zone fallbacks preserve existing destinations", _test_zone_fallbacks)
	_run_case("nearest zone selection is deterministic", _test_zone_selection)
	_run_case("clearing an in-flight destination reroutes without losing salvage", _test_zone_reroute)
	_run_case("zone saves round trip, legacy saves load, malformed zones reject atomically", _test_zone_saves)
	print("STOCKPILE ZONE TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _zone_game() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	for resident: VaultResident in game.residents:
		for work: String in VaultResident.WORK_TYPES:
			resident.set_work_priority(work, VaultResident.PRIORITY_DISABLED)
	game.residents[0].set_work_priority("haul", 1)
	return game


func _finish_haul(game: VaultGame) -> void:
	for tick in 400:
		game.job_system.advance(0.1)
		if game.job_system.jobs.is_empty():
			return
	_assert_true(false, "haul completes within forty seconds")


func _test_zone_orders() -> void:
	var game := _zone_game()
	var cell := Vector2i(19, 12)
	game.set_tool("zone")
	_assert_true(game.issue_order(cell), "zone tool paints floor")
	_assert_false(game.issue_order(cell), "repainting is idempotent")
	_assert_true(game.issue_order(cell + Vector2i.RIGHT), "cell set can contain adjacent cells")
	_assert_false(game.issue_order(Vector2i(0, 0)), "rock is rejected")
	_assert_false(game.issue_order(Vector2i(-1, 12)), "out of bounds is rejected")
	_assert_false(game.issue_order(BreachSystem.HATCH_CELL), "hatch stays clear")
	_assert_false(game.issue_order(game.buildings[0].cell), "fixtures stay clear")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.command_buttons.zone.text, "ZONE 2", "HUD counts painted cells")
	game.set_tool("cancel")
	_assert_true(game.map_grid.is_preview_valid("cancel", cell), "cancel preview recognizes zones")
	_assert_true(game.issue_order(cell), "cancel clears one cell")
	_assert_false(game.map_grid.stockpile_cells.has(cell), "cancel removes marking")
	_assert_true(game.map_grid.stockpile_cells.has(cell + Vector2i.RIGHT), "cancel preserves other cells")
	game.set_tool("bed")
	_assert_true(game.issue_order(cell + Vector2i.RIGHT), "build works over a zone")
	_assert_true(game.map_grid.stockpile_cells.is_empty(), "building retires its zone cell")
	game.set_tool("zone")
	game.player_orders.show_briefing(true)
	_assert_false(game.issue_order(cell), "help blocks zone painting")
	game.player_orders.show_briefing(false)
	game.set_tool("dig")
	_assert_true(game.issue_order(Vector2i(16, 12)), "dig remains independent")
	game.set_tool("cancel")
	_assert_true(game.issue_order(Vector2i(16, 12)), "cancel still removes digging")
	_dispose(game)


func _test_zone_haul() -> void:
	var game := _zone_game()
	var source := Vector2i(19, 12)
	var destination := Vector2i(26, 19)
	game.map_grid.paint_stockpile(destination)
	game.residents[0].position = game.map_grid.cell_to_world(source)
	var initial := game.food_system.salvage
	game.job_system.queue_rubble(source, 3)
	game.job_system.advance(0.1)
	_assert_equal(game.residents[0].carrying, 3, "resident picks up rubble")
	_assert_equal(game.food_system.salvage, initial, "in-transit salvage is not credited")
	_finish_haul(game)
	_assert_equal(game.residents[0].get_cell(game.map_grid), destination, "hauler physically deposits in zone")
	_assert_equal(game.food_system.salvage, initial + 3, "deposit credits exactly once")
	_assert_equal(game.residents[0].carrying, 0, "hands are empty after deposit")
	game.job_system.advance(1.0)
	_assert_equal(game.food_system.salvage, initial + 3, "completed jobs cannot duplicate salvage")
	_dispose(game)


func _test_zone_fallbacks() -> void:
	for mode in 3:
		var game := _zone_game()
		if mode == 1:
			var island := Vector2i(2, 2)
			game.map_grid.cells[island.y * MapGrid.WIDTH + island.x] = MapGrid.Tile.FLOOR
			game.map_grid.paint_stockpile(island)
		if mode == 2:
			for building: VaultBuilding in game.buildings.duplicate():
				if building.kind == VaultBuilding.Kind.STOCKPILE:
					game.deconstruct_building(building.building_id)
		var expected := game.job_system._stockpile_cell()
		var initial := game.food_system.salvage
		game.job_system.queue_rubble(Vector2i(19, 12), 3)
		_finish_haul(game)
		_assert_equal(game.residents[0].get_cell(game.map_grid), expected, "fallback %d reaches original destination" % mode)
		_assert_equal(game.food_system.salvage, initial + 3, "fallback conserves salvage")
		if mode == 2:
			_assert_equal(expected, game.map_grid.get_chamber_center(), "missing bay uses chamber center")
		_dispose(game)


func _test_zone_selection() -> void:
	var game := _zone_game()
	var from_cell := Vector2i(21, 12)
	game.map_grid.paint_stockpile(Vector2i(22, 12))
	game.map_grid.paint_stockpile(Vector2i(20, 12))
	_assert_equal(game.map_grid.nearest_stockpile(from_cell), Vector2i(20, 12), "equal-distance ties prefer left independent of paint order")
	game.map_grid.paint_stockpile(from_cell)
	_assert_equal(game.map_grid.nearest_stockpile(from_cell), from_cell, "current cell is nearest")
	_dispose(game)


func _test_zone_reroute() -> void:
	var game := _zone_game()
	var destination := Vector2i(26, 19)
	game.map_grid.paint_stockpile(destination)
	game.residents[0].position = game.map_grid.cell_to_world(Vector2i(19, 12))
	var initial := game.food_system.salvage
	game.job_system.queue_rubble(Vector2i(19, 12), 3)
	game.job_system.advance(0.1)
	game.map_grid.clear_stockpile(destination)
	_finish_haul(game)
	_assert_equal(game.residents[0].get_cell(game.map_grid), game.job_system._stockpile_cell(), "clearing last zone reroutes to bay")
	_assert_equal(game.food_system.salvage, initial + 3, "rerouting conserves cargo")
	_dispose(game)


func _test_zone_saves() -> void:
	var game := _zone_game()
	game.map_grid.paint_stockpile(Vector2i(26, 19))
	game.job_system.queue_rubble(Vector2i(19, 12), 3)
	game.job_system.advance(0.1)
	var snapshot := game.create_snapshot()
	var initial := game.food_system.salvage
	_assert_true(game.apply_snapshot(snapshot), "in-flight save loads")
	_finish_haul(game)
	_assert_equal(game.residents[0].get_cell(game.map_grid), Vector2i(26, 19), "loaded haul prefers restored zone")
	_assert_equal(game.food_system.salvage, initial + 3, "loaded haul credits once")
	for malformed: Variant in [null, [[-1, 12]], [[19.5, 12]], [[19, 12], [19, 12]], [[0, 0]], [[28, 15]], [[19, "12"]], [[19]]]:
		var invalid := snapshot.duplicate(true)
		invalid.map.stockpile_cells = malformed
		var before := game.create_snapshot()
		_assert_false(game.apply_snapshot(invalid), "invalid zone data rejected")
		_assert_variants_equal(before, game.create_snapshot(), "invalid load is atomic")
	var legacy := snapshot.duplicate(true)
	legacy.map.erase("stockpile_cells")
	_assert_true(game.apply_snapshot(legacy), "legacy snapshot without zones loads")
	_assert_true(game.map_grid.stockpile_cells.is_empty(), "legacy snapshots start without zones")
	game.map_grid.paint_stockpile(Vector2i(26, 19))
	game.new_game(false)
	_assert_true(game.map_grid.stockpile_cells.is_empty(), "new game clears zones")
	_dispose(game)
