extends "res://tests/test_runner.gd"

# Meta perks P3: FLOODLIGHT (first win on 05) lights a second starter Lumen on the core's last spare
# power; VOLUNTEER (first win on 03) adds one more hand for 8 salvage. Both are trade-offs that leave
# the hatch clock, the stores they do not name and the work rates alone.

var _path := ""


func _run() -> void:
	_path = "user://test_perks_p3_%d.json" % OS.get_process_id()
	_run_case("wins on 05 and 03 unlock FLOODLIGHT and VOLUNTEER, in order; test runs stay on NONE", _test_unlock)
	_run_case("FLOODLIGHT buys a second lit Lumen with salvage; it takes the spare power but sheds first", _test_floodlight)
	_run_case("VOLUNTEER adds a fifth (or sixth) resident and costs 8 salvage, nothing else", _test_volunteer)
	_run_case("both perks survive save and load without being granted twice", _test_save_load)
	print("")
	if _failure_count == 0:
		print("PERKS P3 TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("PERKS P3 TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _clean() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path + suffix))


func _game(won_levels: Array) -> VaultGame:
	_clean()
	var store := WingRecords.new()
	store.path = _path
	for level: int in won_levels:
		store.record(0x0777, true, 2, 7, level)
	var game := _spawn_game()
	game.records_path = _path
	return game


func _guard(game: VaultGame) -> bool:
	var ok := VaultGame.PERKS.has("floodlight") and VaultGame.PERKS.has("volunteer")
	_assert_true(ok, "VaultGame has the P3 perks")
	return ok


func _lit_lamps(game: VaultGame) -> int:
	var count := 0
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.LAMP and building.complete:
			count += 1
	return count


func _shape(game: VaultGame) -> Array:
	return [game.food_system.meals, game.food_system.salvage, game.residents.size(), _lit_lamps(game), game.breach_system.warning_at]


func _test_unlock() -> void:
	var game := _game([5])
	if not _guard(game):
		_dispose(game)
		return
	game.new_game(false, 4242)
	_assert_equal(game.unlocked_perks(), ["floodlight"], "a win on 05 alone unlocks FLOODLIGHT only")
	_dispose(game)
	game = _game([7, 5, 3])
	game.new_game(false, 4242)
	_assert_equal(game.unlocked_perks(), ["provisioning", "floodlight", "volunteer"], "07, 05, 03 unlock all three in order")
	_assert_equal([VaultGame.perk_name("floodlight"), VaultGame.perk_name("volunteer")], ["FLOODLIGHT", "VOLUNTEER"], "named")
	_assert_equal([int(VaultGame.PERKS.floodlight.unlock_level), int(VaultGame.PERKS.volunteer.unlock_level)], [5, 3], "unlock levels")
	game.records_path = ""
	game.equipped_perk = "volunteer"
	game.new_game(false, 4242)
	_assert_equal([game.wing_perk, game.residents.size()], ["", 4], "records off: NONE, four crew")
	game.records_path = _path
	game.new_game(false, 0)
	_assert_equal([game.wing_perk, game.residents.size()], ["", 4], "seed 0: NONE, four crew")
	_dispose(game)
	_clean()


func _test_floodlight() -> void:
	var game := _game([5])
	if not _guard(game):
		_dispose(game)
		return
	for level: int in [7, 5, 3]:
		for seed_value: int in [4242, 8, 1234]:
			game.equipped_perk = ""
			game.new_game(false, seed_value, level)
			var base := _shape(game)
			game.equipped_perk = "floodlight"
			game.new_game(false, seed_value, level)
			var lit := _shape(game)
			var label := "%02d/%d" % [level, seed_value]
			_assert_equal(game.wing_perk, "floodlight", label + ": FLOODLIGHT equipped")
			_assert_equal(lit, [base[0], maxi(0, base[1] - VaultGame.FLOODLIGHT_SALVAGE_COST), base[2], base[3] + 1, base[4]], label + ": one more lit Lumen for salvage, same meals, crew and hatch")
			var flood: VaultBuilding = game.get_building_at(VaultGame.FLOODLIGHT_CELL)
			_assert_true(flood != null and flood.shed_first and flood.get_power_priority() == VaultBuilding.PowerPriority.OPTIONAL, label + ": the FLOODLIGHT Lumen sheds first")
			_assert_true(game.map_grid.is_walkable(VaultGame.FLOODLIGHT_CELL) or game.get_building_at(VaultGame.FLOODLIGHT_CELL) != null, label + ": the Lumen stands in the chamber")
			_assert_equal([game.power_grid.supply, game.power_grid.demand], [2, 2], label + ": the core's 2 power is all used")
	_dispose(game)
	_clean()


func _test_volunteer() -> void:
	var game := _game([3])
	if not _guard(game):
		_dispose(game)
		return
	for level: int in [7, 4, 3]:
		game.equipped_perk = ""
		game.new_game(false, 4242, level)
		var base := _shape(game)
		game.equipped_perk = "volunteer"
		game.new_game(false, 4242, level)
		var label := "%02d" % level
		_assert_equal(_shape(game), [base[0], maxi(0, base[1] - VaultGame.VOLUNTEER_SALVAGE_COST), base[2] + 1, base[3], base[4]], label + ": one more resident, 8 less salvage, same meals, light and hatch")
		var last: VaultResident = game.residents[-1]
		_assert_equal(last.resident_name, "Gil", label + ": the volunteer is Gil")
		_assert_true(game.map_grid.is_walkable(game.map_grid.world_to_cell(last.position)), label + ": standing on floor")
	_assert_true(VaultGame.VOLUNTEER_SALVAGE_COST > 0 and VaultGame.FLOODLIGHT_SALVAGE_COST > 0, "trade-offs, not gifts")
	game.equipped_perk = ""
	game.new_game(false, 4242)
	_assert_false(game.get_building_at(VaultGame.FLOODLIGHT_CELL) != null, "NONE: no Lumen at the FLOODLIGHT cell")
	game._spawn_starting_fixture(VaultBuilding.Kind.LAMP, VaultGame.FLOODLIGHT_CELL, false)
	game._mark_floodlight()
	var plain: VaultBuilding = game.get_building_at(VaultGame.FLOODLIGHT_CELL)
	_assert_true(plain != null and not plain.shed_first, "NONE: a Lumen built on that cell keeps its normal priority")
	_dispose(game)
	_clean()


func _test_save_load() -> void:
	var game := _game([5, 3])
	if not _guard(game):
		_dispose(game)
		return
	for perk: String in ["floodlight", "volunteer"]:
		game.equipped_perk = perk
		game.new_game(false, 4242)
		var shape := _shape(game)
		var saved: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
		_assert_equal(saved.get("perk", {}).get("id", ""), perk, perk + ": saved as the perk key")
		game.equipped_perk = ""
		game.new_game(false, 4242)
		_assert_true(game.apply_snapshot(saved), perk + ": loads")
		_assert_equal([game.wing_perk, _shape(game)], [perk, shape], perk + ": restored once, not granted again")
		var flood: VaultBuilding = game.get_building_at(VaultGame.FLOODLIGHT_CELL)
		_assert_equal(flood != null and flood.shed_first, perk == "floodlight", perk + ": shed-first is re-derived on LOAD")
	_dispose(game)
	_clean()
