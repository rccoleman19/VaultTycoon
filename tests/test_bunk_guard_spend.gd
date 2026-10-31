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
