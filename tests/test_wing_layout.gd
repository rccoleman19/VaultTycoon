extends "res://tests/test_runner.gd"

# Wing-seed slice 2: each seeded wing opens its own rock pockets; seed 0 stays the legacy map.

const LEGACY_FLOOR := 120


func _run() -> void:
	_run_case("seed 0 and seedless wings keep the legacy map byte for byte", _test_legacy_map)
	_run_case("the same seed always draws the same map", _test_deterministic)
	_run_case("every seed 1..65535 keeps the 12-dig path and connected, bounded pockets", _test_all_seeds)
	_run_case("different seeds give different layouts", _test_distinct)
	_run_case("a seeded save reloads to the same map and layout", _test_save_round_trip)
	_run_case("pre-layout seeded saves and bad layout keys", _test_compat_and_validation)
	_run_case("pockets never count as excavation; the 12-dig path still clears the objective", _test_objective)
	_run_case("seeded salvage veins: placement, double yield, save and render", _test_veins)
	_run_case("every seed's veins stay off pockets and protected rock", _test_all_seed_veins)
	_finish()


func _finish() -> void:
	print("")
	if _failure_count == 0:
		print("WING LAYOUT TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("WING LAYOUT TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _legacy_cells() -> Array[int]:
	var expected: Array[int] = []
	expected.resize(MapGrid.WIDTH * MapGrid.HEIGHT)
	expected.fill(MapGrid.Tile.ROCK)
	for y in range(MapGrid.CHAMBER.position.y, MapGrid.CHAMBER.end.y):
		for x in range(MapGrid.CHAMBER.position.x, MapGrid.CHAMBER.end.x):
			expected[y * MapGrid.WIDTH + x] = MapGrid.Tile.FLOOR
	return expected


func _seeded(wing_seed: int) -> VaultGame:
	var game := _spawn_game()
	game.new_game(false, wing_seed)
	return game


func _test_legacy_map() -> void:
	_assert_equal(MapGrid.generate_layout(0)["pockets"].size(), 0, "seed 0 has no pockets")
	var game := _spawn_game()
	_assert_equal(game.wing_seed, 0, "a fresh game is the legacy wing")
	_assert_equal(game.map_grid.cells, _legacy_cells(), "fresh wing map is the hand-made chamber")
	var snapshot := game.create_snapshot()
	_assert_false(snapshot.has("map_layout"), "legacy saves carry no layout key")
	_assert_equal(game.map_grid.get_initial_floor_count(), LEGACY_FLOOR, "legacy initial floor")
	game.new_game(false, 0)
	_assert_equal(game.map_grid.cells, _legacy_cells(), "NEW WING with seed 0 is still the legacy map")
	_assert_false(game.create_snapshot().has("map_layout"), "still no layout key")
	_assert_equal(game.map_grid.layout_seed, 0, "no seeded layers")
	_dispose(game)


func _test_deterministic() -> void:
	for wing_seed in [1, 4242, 65535]:
		_assert_equal(MapGrid.generate_layout(wing_seed), MapGrid.generate_layout(wing_seed), "seed %d layout is a pure function" % wing_seed)
	var game := _seeded(4242)
	var first: Array[int] = game.map_grid.cells.duplicate()
	game.new_game(false, 77)
	game.new_game(false, 4242)
	_assert_equal(game.map_grid.cells, first, "seed 4242 draws the same map after another wing")
	_assert_true(game.map_grid.cells != _legacy_cells(), "a seeded wing differs from the legacy map")
	_dispose(game)


func _test_all_seeds() -> void:
	var protected := MapGrid.get_protected_dig_path()
	var bad_protected := 0
	var bad_connect := 0
	var bad_size := 0
	var min_cells := 1000
	var max_cells := 0
	for wing_seed in range(1, 65536):
		var pockets: Array = MapGrid.generate_layout(wing_seed)["pockets"]
		min_cells = mini(min_cells, pockets.size())
		max_cells = maxi(max_cells, pockets.size())
		var open: Dictionary = {}
		for cell: Vector2i in pockets:
			open[cell] = true
			if MapGrid.is_layout_protected(cell):
				bad_protected += 1
		for cell in protected:
			if open.has(cell):
				bad_protected += 1
		# Connected: every pocket cell reaches the chamber through pocket cells.
		var frontier: Array[Vector2i] = []
		var seen: Dictionary = {}
		for cell: Vector2i in pockets:
			for neighbor in MapGrid._offset_neighbors(cell):
				if MapGrid.CHAMBER.has_point(neighbor):
					frontier.append(cell)
					seen[cell] = true
					break
		var cursor := 0
		while cursor < frontier.size():
			var current := frontier[cursor]
			cursor += 1
			for neighbor in MapGrid._offset_neighbors(current):
				if open.has(neighbor) and not seen.has(neighbor):
					seen[neighbor] = true
					frontier.append(neighbor)
		if seen.size() != pockets.size():
			bad_connect += 1
		if pockets.size() < 4 or pockets.size() > 30:
			bad_size += 1
	_assert_equal(bad_protected, 0, "no seed opens a protected cell (chamber ring buffer, border, hatch, 12-dig row)")
	_assert_equal(bad_connect, 0, "every seed's pockets connect to the chamber")
	_assert_equal(bad_size, 0, "every seed opens 4..30 pocket cells (got %d..%d)" % [min_cells, max_cells])


func _test_distinct() -> void:
	var fingerprints: Dictionary = {}
	for wing_seed in range(1, 201):
		fingerprints[str(MapGrid.generate_layout(wing_seed)["pockets"])] = true
	_assert_true(fingerprints.size() >= 195, "200 seeds give at least 195 distinct layouts (got %d)" % fingerprints.size())


func _test_save_round_trip() -> void:
	var game := _seeded(4242)
	var pockets: int = MapGrid.generate_layout(4242)["pockets"].size()
	_assert_equal(game.map_grid.get_initial_floor_count(), LEGACY_FLOOR + pockets, "pocket floor joins the initial floor")
	_assert_equal(game.map_grid.get_floor_cells().size(), LEGACY_FLOOR + pockets, "the map opens exactly the pockets")
	var dig := MapGrid.get_protected_dig_path()[0]
	_assert_true(game.map_grid.queue_dig(dig), "the 12-dig path is diggable")
	game.map_grid.apply_dig_work(dig, 8.0)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	_assert_equal(int(snapshot.get("map_layout", 0)), VaultGame.MAP_LAYOUT_SEEDED, "a seeded save records the layout version")
	var cells: Array[int] = game.map_grid.cells.duplicate()
	game.new_game(false, 77)
	_assert_true(game.apply_snapshot(snapshot), "the seeded save loads")
	_assert_equal(game.map_grid.cells, cells, "the saved map comes back, dug cell included")
	_assert_equal(game.map_grid.layout_seed, 4242, "the layout seed comes back from wing_seed")
	_assert_equal(game.map_grid.get_initial_floor_count(), LEGACY_FLOOR + pockets, "and its initial floor")
	var resaved: Variant = JSON.parse_string(JSON.stringify(game.create_snapshot().get("map")))
	_assert_true(JSON.stringify(resaved) == JSON.stringify(snapshot.get("map")), "re-saving gives the same map bytes")
	_dispose(game)


func _test_compat_and_validation() -> void:
	var game := _seeded(4242)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	var pre_layout: Dictionary = snapshot.duplicate(true)
	pre_layout.erase("map_layout")
	_assert_true(game.apply_snapshot(pre_layout), "a #110 seeded save without map_layout still loads")
	_assert_equal(game.map_grid.layout_seed, 0, "and keeps no seeded layers")
	_assert_equal(game.map_grid.get_initial_floor_count(), LEGACY_FLOOR, "so its initial floor stays the chamber")
	_assert_false(game.create_snapshot().has("map_layout"), "re-saving it adds no layout key")
	var bad: Dictionary = snapshot.duplicate(true)
	bad["map_layout"] = 2
	_assert_false(game.apply_snapshot(bad), "an unknown layout version is rejected")
	bad["map_layout"] = "1"
	_assert_false(game.apply_snapshot(bad), "a non-integer layout version is rejected")
	bad = snapshot.duplicate(true)
	bad["wing_seed"] = 0
	_assert_true(game.apply_snapshot(bad), "a seedless save keeps loading even with a layout key")
	_assert_equal(game.map_grid.layout_seed, 0, "a seedless save derives no layout")
	_dispose(game)


func _test_objective() -> void:
	var game := _seeded(4242)
	var orders := game.player_orders
	orders.refresh()
	_assert_true(orders.checklist.text.contains("Excavate at least 12"), "the checklist lists excavation")
	_assert_false(game.map_grid.get_floor_cells().size() >= game.map_grid.get_initial_floor_count() + 12, "pockets alone do not clear the 12-dig objective")
	for cell in MapGrid.get_protected_dig_path():
		_assert_true(game.map_grid.queue_dig(cell), "path cell %s is diggable" % cell)
		_assert_true(game.map_grid.apply_dig_work(cell, 8.0), "path cell %s digs in 8 work" % cell)
	_assert_true(game.map_grid.get_floor_cells().size() >= game.map_grid.get_initial_floor_count() + 12, "the twelve path digs clear it")
	_dispose(game)
	var big_seed := 1
	while MapGrid.generate_layout(big_seed)["pockets"].size() < 12:
		big_seed += 1
	var big := _seeded(big_seed)
	_assert_true(String(big.player_orders._primary_next_step().get("text", "")).contains("mark rock"), "a wing with 12+ pocket cells still asks for the first dig")
	_dispose(big)


func _rubble_for(game: VaultGame, cell: Vector2i) -> int:
	var amounts: Array[int] = []
	var capture := func(_cell: Vector2i, amount: int) -> void: amounts.append(amount)
	game.map_grid.rubble_created.connect(capture)
	# A deep vein may not touch floor yet; mark it directly so only the yield is under test.
	game.map_grid.dig_marks[cell] = true
	game.map_grid.apply_dig_work(cell, 8.0)
	game.map_grid.rubble_created.disconnect(capture)
	return amounts[0] if amounts.size() == 1 else -1


func _hex_material(game: VaultGame, cell: Vector2i) -> Material:
	var view := game.get_node("MapView3D") as MapView3D
	var instance := view._make_hex_instance(cell)
	var mat := instance.material_override if instance.material_override != null else instance.get_surface_override_material(0)
	instance.free()
	return mat


func _test_veins() -> void:
	var legacy := _spawn_game()
	_assert_true(legacy.map_grid.vein_cells.is_empty(), "the legacy wing has no veins")
	_assert_equal(_rubble_for(legacy, MapGrid.get_protected_dig_path()[0]), 3, "legacy rock yields 3")
	_dispose(legacy)
	var game := _seeded(4242)
	var veins: Array = MapGrid.generate_layout(4242)["veins"]
	_assert_equal(game.map_grid.vein_cells.size(), veins.size(), "the wing carries its seeded veins")
	var vein: Vector2i = veins[0]
	_assert_true(game.map_grid.is_vein(vein) and game.map_grid.get_tile(vein) == MapGrid.Tile.ROCK, "a vein starts as rock")
	var view := game.get_node("MapView3D") as MapView3D
	_assert_true(_hex_material(game, vein) == view._mat_vein, "a vein renders copper")
	_assert_true(_hex_material(game, MapGrid.get_protected_dig_path()[0]) == view._mat_rock, "plain rock stays plain")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	_assert_false(JSON.stringify(snapshot).contains("vein"), "veins are never saved")
	game.new_game(false, 77)
	_assert_true(game.apply_snapshot(snapshot), "the seeded save loads")
	_assert_equal(game.map_grid.vein_cells.size(), veins.size(), "veins come back from the seed")
	_assert_equal(_rubble_for(game, vein), 6, "a dug vein yields 6 rubble")
	_assert_false(game.map_grid.is_vein(vein), "a dug vein is plain floor")
	var jobs_before := game.job_system.jobs.size()
	game.map_grid.queue_dig(MapGrid.get_protected_dig_path()[1])
	game.map_grid.apply_dig_work(MapGrid.get_protected_dig_path()[1], 8.0)
	_assert_equal(game.job_system.jobs.size(), jobs_before + 1, "the dig queues one rubble haul")
	_assert_equal(_rubble_for(game, MapGrid.get_protected_dig_path()[2]), 3, "plain rock still yields 3 on a seeded wing")
	var pre_layout: Dictionary = snapshot.duplicate(true)
	pre_layout.erase("map_layout")
	_assert_true(game.apply_snapshot(pre_layout), "a #110 seeded save loads")
	_assert_true(game.map_grid.vein_cells.is_empty(), "and keeps no veins")
	_dispose(game)


func _test_all_seed_veins() -> void:
	var protected := MapGrid.get_protected_dig_path()
	var bad := 0
	var bad_size := 0
	for wing_seed in range(1, 65536, 7):
		var layout: Dictionary = MapGrid.generate_layout(wing_seed)
		var open: Dictionary = {}
		for cell: Vector2i in layout["pockets"]:
			open[cell] = true
		var veins: Array = layout["veins"]
		if veins.size() < 3 or veins.size() > 15:
			bad_size += 1
		for cell: Vector2i in veins:
			if open.has(cell) or MapGrid.is_layout_protected(cell) or protected.has(cell):
				bad += 1
	_assert_equal(bad, 0, "no vein sits on a pocket, the 12-dig row, the chamber, the hatch or the border")
	_assert_equal(bad_size, 0, "every sampled seed has 3..15 vein cells")
