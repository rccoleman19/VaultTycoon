extends "res://tests/test_runner.gd"
# QA playtest 3 dead time: on 03 s8 / s1234 Next held "YOU mark rock [E] · THEY dig on Dig
# defaults" for 0-31.8 s while the starter chamber had reachable floor and 48 salvage, and the
# follow driver ignored mark-rock, so nothing happened. Now the affordable opening bunks come
# first (before the +12 expansion gate), then Dig continues; the driver follows both mark-rock
# and keep-marking. Assertions read Next, Spend status, placed bunks, and dig marks.

const FollowDriver := preload("res://tools/playtest/follow_driver.gd")


func _run() -> void:
	_run_case("fresh 03 s8 and s1234: opening Next places 1 bunk (hard max), not mark rock", _test_opening_bunks)
	_run_case("following the opening Next places the bunks at once", _test_follow_places)
	_run_case("spendable buys one bunk: Next says 1 bunk", _test_one_affordable)
	_run_case("no money for a bunk: no bunk step and never 'no free floor'", _test_no_money)
	_run_case("no reachable free cell: mark rock is Next even past +12 floor", _test_no_cell)
	_run_case("the driver follows mark rock and keep marking digs", _test_follow_marks)
	print("OPENING BUNKS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _fresh(seed: int) -> VaultGame:
	var game := _spawn_game()
	game.new_game(false, seed, 3)
	game.begin_shift()
	game.user_paused = true
	game.player_orders.refresh()
	return game


func _next(game: VaultGame) -> String:
	game.player_orders.refresh()
	return game.player_orders.objective_label.text


func _bunks_in(game: VaultGame) -> int:
	var count := 0
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.BED:
			count += 1
	return count


func _follow(game: VaultGame, log_name: String) -> void:
	var driver = FollowDriver.new()
	driver.game = game
	driver.logf = FileAccess.open("user://%s.log" % log_name, FileAccess.WRITE)
	driver._follow_next()
	driver.logf.close()
	driver.free()


func _test_opening_bunks() -> void:
	for seed in [8, 1234]:
		var game := _fresh(seed)
		var text := _next(game)
		_assert_equal(text, "Next: YOU place 1 bunk · THEY craft from Craft", "03 s%d opening Next (hard max 1)" % seed)
		_assert_equal(str(game.player_orders._displayed_next_step.get("tool", "")), "bed", "03 s%d opening tool is bed" % seed)
		_assert_false("mark rock" in text, "03 s%d opening is not mark rock" % seed)
		_dispose(game)


func _test_follow_places() -> void:
	var game := _fresh(1234)
	_next(game)
	_follow(game, "opening_follow")
	_assert_equal(_bunks_in(game), 1, "the driver placed the stated 1 bunk (never 2)")
	var text := _next(game)
	_assert_false(text.begins_with("Next: YOU place ") and "bunk" in text, "Next leaves the bunk step (%s)" % text)
	_dispose(game)


func _test_one_affordable() -> void:
	var game := _fresh(8)
	game.food_system.meals = 100  # food runway is fine; only the bunk budget is tight
	game.food_system.salvage = game.food_plan_patch_owed() + int(VaultBuilding.COSTS[VaultBuilding.Kind.BED]) + 7
	_assert_equal(_next(game), "Next: YOU place 1 bunk · THEY craft from Craft", "one bunk's worth of spendable states 1 bunk")
	_follow(game, "opening_one")
	_assert_equal(_bunks_in(game), 1, "exactly the one affordable bunk was placed")
	_dispose(game)


func _test_no_money() -> void:
	var game := _fresh(8)
	game.food_system.meals = 100  # food runway is fine; only the bunk budget is tight
	game.food_system.salvage = game.food_plan_patch_owed() + int(VaultBuilding.COSTS[VaultBuilding.Kind.BED]) - 1
	var text := _next(game)
	_assert_false("bunk" in text, "no bunk step when spendable cannot pay one (%s)" % text)
	_follow(game, "opening_no_money")
	_assert_equal(_bunks_in(game), 0, "no bunk placed without money")
	_assert_false("No free floor" in game.status_message, "money is not reported as no free floor (%s)" % game.status_message)
	_dispose(game)


func _test_no_cell() -> void:
	var game := _fresh(1234)
	for x in range(17, 29):
		var cell := Vector2i(x, 10)
		game.map_grid.queue_dig(cell)
		game.map_grid.apply_dig_work(cell, 8.0)
	game.map_grid.dig_marks.clear()
	for y in MapGrid.HEIGHT:
		for x in MapGrid.WIDTH:
			var cell := Vector2i(x, y)
			if game.map_grid.is_walkable(cell) and game.get_building_at(cell) == null:
				game.map_grid.stockpile_cells[cell] = true
	var initial_floor := MapGrid.CHAMBER.size.x * MapGrid.CHAMBER.size.y
	var floor_count := game.map_grid.get_floor_cells().size() - game.map_grid.layout_pocket_count
	_assert_true(floor_count >= initial_floor + 12, "fixture meets the +12 floor quota (%d)" % floor_count)
	var text := _next(game)
	_assert_true(text.begins_with("Next: YOU mark rock [E]") or text.begins_with("Next: YOU keep marking digs"), "no usable cell: Next is the honest dig step (%s)" % text)
	_dispose(game)


func _test_follow_marks() -> void:
	_assert_equal(FollowDriver.followed_action("Next: YOU mark rock [E] · THEY dig on Dig defaults", []), "YOU mark rock [E]", "mark rock is followed")
	_assert_equal(FollowDriver.followed_action("Next: YOU keep marking digs [E] · THEY dig/haul alone", []), "YOU keep marking digs [E]", "keep marking is followed")
	var game := _fresh(1234)
	_next(game)
	game.player_orders.objective_label.text = "Next: YOU keep marking digs [E] · THEY dig/haul alone"
	var before: int = game.map_grid.dig_marks.size()
	_follow(game, "opening_keep_marking")
	_assert_true(game.map_grid.dig_marks.size() > before, "keep marking designates rock (%d -> %d)" % [before, game.map_grid.dig_marks.size()])
	_dispose(game)
