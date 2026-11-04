extends "res://tests/test_rec_flash_cause.gd"
# 05 s4242 busy, 76.5-280 s: Next shows "place bunks" but Spend offers Mk II fits and
# builds, the busy player taps them and Next bounces back to the bunks 8 times. The
# bunk guard (_bunks_hold_salvage_nudge) owns Spend too: Spend places the bunks, and
# the follow driver acts on the bunk step.

const FollowDriver := preload("res://tools/playtest/follow_driver.gd")


func _run() -> void:
	_run_case("Spend offers the bunks, not a Grow Tray Mk II, while Next shows bunks", _test_no_mk2)
	_run_case("pressing Spend places bunks and Next moves on", _test_press_places)
	_run_case("no free floor: Spend says dig more", _test_no_floor)
	_run_case("with beds covered Spend offers the Mk II again", _test_mk2_without_bunks)
	_run_case("the follow driver acts on place bunks", _test_follow_bunks)
	_run_case("stock 16 with 4 owed to the hatch: Spend places only what 12 buys", _test_budget_patch_owed)
	_run_case("stock 20 with an unpaid Lumen: committed + patch never exceeds stock", _test_budget_unpaid_lumen)
	_run_case("exact budgets 12 and 20 still place their bunks", _test_budget_exact)
	_run_case("a failed driver placement retries the same tip once floor frees", _test_follow_retry)
	print("BUNK GUARD SPEND: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _rich(bunks := false) -> VaultGame:
	var game := _plateau(bunks, true)
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY:
			building.upgrade_tier = VaultBuilding.UPGRADE_TIER_BASE
	game.food_system.salvage = 40
	return game


func _bunks_in(game: VaultGame) -> int:
	var count := 0
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.BED:
			count += 1
	return count


func _test_no_mk2() -> void:
	var game := _rich()
	var text := _next(game)
	var spend := _spend_text(game)
	_assert_true(text.begins_with("Next: YOU place ") and "bunk" in text, "Next shows the bunks (%s)" % text)
	_assert_false("Mk II" in spend or "Grow Tray" in spend or "Air" in spend, "Spend offers no Mk II or other build (%s)" % spend)
	_assert_true(spend.begins_with("Spend ") and "bunk" in spend, "Spend offers the bunk placement (%s)" % spend)
	_assert_false("Mk II" in text, "Next itself does not bounce to a Mk II fit (%s)" % text)
	_dispose(game)


func _test_press_places() -> void:
	var game := _rich()
	_next(game)
	var before := _bunks_in(game)
	game.player_orders.upgrade_offer_button.pressed.emit()
	_assert_true(_bunks_in(game) > before, "Spend placed bunk blueprints (%d -> %d)" % [before, _bunks_in(game)])
	_assert_equal(game.status_message, "Bunks placed · THEY build it", "the status says the bunks went down")
	var text := _next(game)
	_assert_false(text.begins_with("Next: YOU place ") and "bunk" in text, "Next leaves the bunk step (%s)" % text)
	_dispose(game)


func _test_no_floor() -> void:
	var game := _rich()
	_next(game)
	for y in MapGrid.HEIGHT:
		for x in MapGrid.WIDTH:
			var cell := Vector2i(x, y)
			if game.map_grid.is_walkable(cell) and game.get_building_at(cell) == null:
				game.map_grid.stockpile_cells[cell] = true
	game.player_orders.refresh()
	var before := _bunks_in(game)
	game.player_orders.upgrade_offer_button.pressed.emit()
	_assert_equal(_bunks_in(game), before, "no bunk goes down without free floor")
	_assert_equal(game.status_message, "No free floor for bunks · dig more", "the status says why")
	_dispose(game)


func _test_mk2_without_bunks() -> void:
	var game := _rich(true)
	_next(game)
	_assert_true("Mk II" in _spend_text(game), "beds covered: Spend offers the Mk II (%s)" % _spend_text(game))
	_dispose(game)


func _test_follow_bunks() -> void:
	_assert_equal(FollowDriver.followed_action("Next: YOU place bunks · THEY craft", []), "YOU place bunks", "the bunk step is followed")
	var game := _rich()
	_next(game)
	var before := _bunks_in(game)
	var driver = FollowDriver.new()
	driver.game = game
	driver.logf = FileAccess.open("user://follow_bunks.log", FileAccess.WRITE)
	driver._follow_next()
	driver.logf.close()
	driver.free()
	_assert_true(_bunks_in(game) > before, "the driver placed bunks (%d -> %d)" % [before, _bunks_in(game)])
	_dispose(game)


# Codex 6543410321 on #146 (P2): Spend's bunk budget sets aside the hatch patch still owed and
# every queued blueprint's unpaid cost (game.food_plan_spendable), like the food card.
func _owed(game: VaultGame, owed: int) -> void:
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST - owed


func _committed_ok(game: VaultGame) -> bool:
	return game.queued_build_commitment() + game.food_plan_patch_owed() <= game.food_system.salvage


func _press(game: VaultGame) -> void:
	game.player_orders.refresh()
	var button := game.player_orders.upgrade_offer_button
	if button.visible and not button.disabled:
		button.pressed.emit()


func _test_budget_patch_owed() -> void:
	var game := _rich()
	game.food_system.salvage = 16
	_owed(game, 4)
	_next(game)
	var spend := _spend_text(game)
	_assert_false("place 2 bunks" in spend, "Spend does not offer 2 bunks with 12 spendable (%s)" % spend)
	_assert_true(game.player_orders.spend_bunk_count() <= 12 / 8, "count is capped at 12/8 (%d)" % game.player_orders.spend_bunk_count())
	var before := _bunks_in(game)
	_press(game)
	_assert_equal(_bunks_in(game) - before, 1, "one press places exactly 1 bunk")
	_assert_true(_committed_ok(game), "hatch is never left short (commit %d + owed %d <= stock %d)" % [game.queued_build_commitment(), game.food_plan_patch_owed(), game.food_system.salvage])
	_dispose(game)


func _test_budget_unpaid_lumen() -> void:
	var game := _rich()
	game.food_system.salvage = 20
	_owed(game, 0)
	var cells: Array[Vector2i] = game.player_orders.spend_build_cells(VaultBuilding.Kind.LAMP)
	_assert_true(not cells.is_empty() and game.place_blueprint(VaultBuilding.Kind.LAMP, cells[0]), "an unpaid Lumen is queued")
	_next(game)
	var spend := _spend_text(game)
	_assert_false("place 2 bunks" in spend, "Spend does not count the Lumen's 5 twice (%s)" % spend)
	_press(game)
	_assert_true(_committed_ok(game), "committed + patch within stock (commit %d + owed %d <= stock %d)" % [game.queued_build_commitment(), game.food_plan_patch_owed(), game.food_system.salvage])
	_dispose(game)


func _test_budget_exact() -> void:
	for budget: int in [12, 20]:
		var game := _rich()
		game.food_system.salvage = budget + 4
		_owed(game, 4)
		_next(game)
		var want := mini(game.player_orders.spend_bunk_count(), budget / 8)
		_assert_true(want >= 1, "budget %d affords a bunk (%d)" % [budget, want])
		var before := _bunks_in(game)
		_press(game)
		_assert_equal(_bunks_in(game) - before, budget / 8 if want == budget / 8 else want, "budget %d places its bunks" % budget)
		_assert_true(_committed_ok(game), "budget %d keeps the hatch whole" % budget)
		_dispose(game)


# P3: a placed=0 bunk dispatch must not burn the driver's memo for that tip.
func _test_follow_retry() -> void:
	var game := _rich()
	_next(game)
	var zoned: Array[Vector2i] = []
	for y in MapGrid.HEIGHT:
		for x in MapGrid.WIDTH:
			var cell := Vector2i(x, y)
			if game.map_grid.is_walkable(cell) and game.get_building_at(cell) == null and not game.map_grid.stockpile_cells.has(cell):
				game.map_grid.stockpile_cells[cell] = true
				zoned.append(cell)
	game.player_orders.refresh()
	var driver = FollowDriver.new()
	driver.game = game
	driver.logf = FileAccess.open("user://follow_retry.log", FileAccess.WRITE)
	var before := _bunks_in(game)
	driver._follow_next()
	_assert_equal(_bunks_in(game), before, "fully zoned floor: the driver places nothing")
	for cell: Vector2i in zoned:
		game.map_grid.stockpile_cells.erase(cell)
	game.player_orders.refresh()
	driver._follow_next()
	driver.logf.close()
	driver.free()
	_assert_true(_bunks_in(game) > before, "after floor frees, the same tip places a bunk (%d -> %d)" % [before, _bunks_in(game)])
	_dispose(game)
