extends "res://tests/test_runner.gd"

# Seed-visible slice: the NEW WING briefing names what a seeded wing holds, so its variety shows
# on the first turn even though most pockets start off camera. Seed 0 stays byte-identical.


func _run() -> void:
	_run_case("seed 0 and seedless wings keep the legacy briefing and camera", _test_legacy)
	_run_case("a seeded briefing names its rock pockets and salvage veins", _test_seeded)
	_run_case("every seed names 2-3 pockets and 2-3 veins that match its layout", _test_all_seeds)
	_run_case("the named briefing still fits the 1280x720 panel", _test_fits)
	_finish()


func _finish() -> void:
	print("")
	if _failure_count == 0:
		print("SEED VISIBLE TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("SEED VISIBLE TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _title(game: VaultGame) -> String:
	return game.player_orders.wing_briefing_title.text


func _test_legacy() -> void:
	var game := _spawn_game()
	var legacy := "VAULT WING %s // SEAL STABILIZATION" % game.player_orders.wing_id(0)
	_assert_equal(_title(game), legacy, "the spawned legacy briefing title is unchanged")
	var camera := game.world_camera.position
	game.new_game(false, 0)
	_assert_equal(_title(game), legacy, "seed 0 briefing title is unchanged")
	_assert_false(_title(game).contains("POCKETS"), "seed 0 names no pockets")
	_assert_equal(game.world_camera.position, camera, "seed 0 camera is unchanged")
	_assert_equal(MapGrid.pocket_count_for_seed(0), 0, "seed 0 has no pockets to name")
	_assert_equal(MapGrid.vein_count_for_seed(0), 0, "seed 0 has no veins to name")
	_dispose(game)


func _test_seeded() -> void:
	var game := _spawn_game()
	var camera := game.world_camera.position
	for wing_seed in [1, 4242, 65535]:
		game.new_game(false, wing_seed)
		var lines := _title(game).split("\n")
		_assert_equal(lines.size(), 3, "seed %d title has id, hatch test and contents lines" % wing_seed)
		_assert_true(lines[1].begins_with("HATCH TEST AT"), "seed %d keeps the hatch line second" % wing_seed)
		var expected := "%d ROCK POCKETS · %d SALVAGE VEINS" % [MapGrid.pocket_count_for_seed(wing_seed), MapGrid.vein_count_for_seed(wing_seed)]
		_assert_equal(lines[2], expected, "seed %d names its contents" % wing_seed)
		_assert_equal(game.world_camera.position, camera, "seed %d keeps the chamber camera" % wing_seed)
	_assert_equal(game.player_orders.wing_layout_summary(65535), "%d ROCK POCKETS · %d SALVAGE VEINS" % [2 + BreachSystem.seed_hash(65535, 100) % 2, 2 + BreachSystem.seed_hash(65535, 200) % 2], "summary uses the layout salts")
	game.new_game(false, 0)
	_assert_false(_title(game).contains("POCKETS"), "returning to seed 0 drops the contents line")
	_dispose(game)


# Vein runs started from distinct seeds of the walk; count connected runs as an upper-bound check.
func _test_all_seeds() -> void:
	var bad_range := 0
	var bad_pockets := 0
	var bad_veins := 0
	var seen := {}
	for wing_seed in range(1, 65536):
		var pockets := MapGrid.pocket_count_for_seed(wing_seed)
		var veins := MapGrid.vein_count_for_seed(wing_seed)
		seen["%d/%d" % [pockets, veins]] = true
		if pockets < 2 or pockets > 3 or veins < 2 or veins > 3:
			bad_range += 1
		if wing_seed % 97 != 0:
			continue
		var layout := MapGrid.generate_layout(wing_seed)
		# pockets sit on different walls, so each is its own region; each vein run places 1+ cells
		if _components(layout["pockets"]) != pockets:
			bad_pockets += 1
		if layout["veins"].size() < veins:
			bad_veins += 1
	_assert_equal(bad_range, 0, "every seed names 2-3 pockets and 2-3 veins")
	_assert_equal(bad_pockets, 0, "each named pocket is one separate opened region (sampled)")
	_assert_equal(bad_veins, 0, "named veins are backed by vein cells")
	_assert_equal(seen.size(), 4, "all four pocket/vein combinations occur")


func _test_fits() -> void:
	var game := _spawn_game()
	var widest := 1
	for wing_seed in range(1, 200):
		if MapGrid.pocket_count_for_seed(wing_seed) == 3 and MapGrid.vein_count_for_seed(wing_seed) == 3:
			widest = wing_seed
			break
	game.new_game(true, widest)
	var orders := game.player_orders
	var title := orders.wing_briefing_title
	var title_size := title.get_combined_minimum_size()
	_assert_true(title_size.x <= 560.0 - 36.0, "the named title fits inside the 560 px panel margins (min %.0f)" % title_size.x)
	var line_height := title.get_line_height()
	_assert_true(title_size.y <= line_height * 3 + 8, "the contents add exactly one title line (min %.0f, line %d)" % [title_size.y, line_height])
	_assert_true(orders.briefing_begin_button.visible, "BEGIN SHIFT is still offered")
	_dispose(game)


func _components(cells: Array) -> int:
	var left := {}
	for cell: Vector2i in cells:
		left[cell] = true
	var regions := 0
	while not left.is_empty():
		regions += 1
		var stack: Array = [left.keys()[0]]
		left.erase(stack[0])
		while not stack.is_empty():
			var cell: Vector2i = stack.pop_back()
			for neighbor: Vector2i in MapGrid._offset_neighbors(cell):
				if left.has(neighbor):
					left.erase(neighbor)
					stack.append(neighbor)
	return regions
