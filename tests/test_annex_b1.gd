extends "res://tests/test_runner.gd"

# Annex blueprints C1/B1: BUNKROOM is earned by a first Annex badge (a record with annex) and takes
# the single perk slot: one built Bunk at the start for 14 salvage. Meals, crew, light and the
# hatch clock are untouched; records stay at 4 fields and the perk save key at version 1.

var _path := ""


func _run() -> void:
	_path = "user://test_annex_b1_%d.json" % OS.get_process_id()
	_run_case("an Annex badge unlocks BUNKROOM; plain wins and test runs do not", _test_unlock)
	_run_case("BUNKROOM buys one built Bunk for 14 salvage, nothing else", _test_effect)
	_run_case("BUNKROOM survives save and load without a second Bunk", _test_save_load)
	print("")
	if _failure_count == 0:
		print("ANNEX B1 TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("ANNEX B1 TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _clean() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path + suffix))


func _game(wins: Array, annex_level := 0) -> VaultGame:
	_clean()
	var store := WingRecords.new()
	store.path = _path
	for level: int in wins:
		store.record(0x0777, true, 2, 7, level)
	if annex_level > 0:
		store.record(0x0778, true, 2, 9, annex_level, true)
	var game := _spawn_game()
	game.records_path = _path
	return game


func _bunks(game: VaultGame) -> int:
	var count := 0
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.BED and building.complete:
			count += 1
	return count


func _lamps(game: VaultGame) -> int:
	var count := 0
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.LAMP and building.complete:
			count += 1
	return count


func _shape(game: VaultGame) -> Array:
	return [game.food_system.meals, game.food_system.salvage, game.residents.size(), _lamps(game), _bunks(game), game.breach_system.warning_at]


func _test_unlock() -> void:
	var game := _game([7, 5, 3])
	_assert_true(VaultGame.PERKS.has("bunkroom"), "VaultGame has BUNKROOM")
	if not VaultGame.PERKS.has("bunkroom"):
		_dispose(game)
		return
	game.new_game(false, 4242)
	_assert_false("bunkroom" in game.unlocked_perks(), "wins without an Annex badge do not unlock BUNKROOM")
	_dispose(game)
	game = _game([], 7)
	game.new_game(false, 4242)
	_assert_true("bunkroom" in game.unlocked_perks(), "an Annex badge (07 win) unlocks BUNKROOM")
	_assert_equal(game.unlocked_perks(), ["provisioning", "bunkroom"], "BUNKROOM sits after the perks in the slot")
	_assert_equal(VaultGame.perk_name("bunkroom"), "BUNKROOM", "named")
	_dispose(game)
	game = _game([7, 5, 3], 3)
	game.new_game(false, 4242)
	_assert_equal(game.unlocked_perks(), ["provisioning", "floodlight", "volunteer", "bunkroom"], "all perks, then the blueprint, in slot order")
	game.records_path = ""
	game.equipped_perk = "bunkroom"
	game.new_game(false, 4242)
	_assert_equal([game.wing_perk, game.get_building_at(VaultGame.BUNKROOM_CELL) == null], ["", true], "records off: NONE, no Bunk")
	game.records_path = _path
	game.new_game(false, 0)
	_assert_equal([game.wing_perk, game.get_building_at(VaultGame.BUNKROOM_CELL) == null], ["", true], "seed 0: NONE, no Bunk")
	_dispose(game)
	_clean()


func _test_effect() -> void:
	var game := _game([], 3)
	if not VaultGame.PERKS.has("bunkroom"):
		_assert_true(false, "VaultGame has BUNKROOM")
		_dispose(game)
		return
	for level: int in [7, 5, 4, 3]:
		for seed_value: int in [4242, 8, 1234]:
			game.equipped_perk = ""
			game.new_game(false, seed_value, level)
			var base := _shape(game)
			_assert_true(game.get_building_at(VaultGame.BUNKROOM_CELL) == null, "%02d/%d NONE: the Bunk cell is free" % [level, seed_value])
			game.equipped_perk = "bunkroom"
			game.new_game(false, seed_value, level)
			var label := "%02d/%d" % [level, seed_value]
			_assert_equal(game.wing_perk, "bunkroom", label + ": BUNKROOM equipped")
			_assert_equal(_shape(game), [base[0], maxi(0, base[1] - VaultGame.BUNKROOM_SALVAGE_COST), base[2], base[3], base[4] + 1, base[5]], label + ": one more built Bunk for 14 salvage, same meals, crew, light and hatch")
			var bunk: VaultBuilding = game.get_building_at(VaultGame.BUNKROOM_CELL)
			_assert_true(bunk != null and bunk.kind == VaultBuilding.Kind.BED and bunk.complete, label + ": a built Bunk on the BUNKROOM cell")
	_assert_true(VaultGame.BUNKROOM_SALVAGE_COST > VaultBuilding.COSTS[VaultBuilding.Kind.BED], "it costs more than building the Bunk")
	_dispose(game)
	_clean()


func _test_save_load() -> void:
	var game := _game([], 5)
	if not VaultGame.PERKS.has("bunkroom"):
		_assert_true(false, "VaultGame has BUNKROOM")
		_dispose(game)
		return
	game.equipped_perk = "bunkroom"
	game.new_game(false, 4242)
	var shape := _shape(game)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	_assert_equal(saved.get("perk", {}), {"version": 1.0, "id": "bunkroom"}, "saved under the version-1 perk key")
	game.equipped_perk = ""
	game.new_game(false, 4242)
	_assert_true(game.apply_snapshot(saved), "loads")
	_assert_equal([game.wing_perk, _shape(game)], ["bunkroom", shape], "restored once, no second Bunk or charge")
	_dispose(game)
	_clean()
