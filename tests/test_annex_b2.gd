extends "res://tests/test_runner.gd"

# Annex blueprints C1/B2: GROW NOOK is earned by Annex badges on two different sublevels and takes the
# single perk slot: a Grow Tray blueprint at the start (unbuilt; the crew haul and build it), paid
# with meals. Salvage, crew, light and the hatch clock are untouched.

var _path := ""


func _run() -> void:
	_path = "user://test_annex_b2_%d.json" % OS.get_process_id()
	_run_case("Annex badges on two sublevels unlock GROW NOOK; one sublevel does not", _test_unlock)
	_run_case("GROW NOOK places an unbuilt Grow Tray and costs meals, nothing else", _test_effect)
	_run_case("GROW NOOK survives save and load without a second plan or charge", _test_save_load)
	print("")
	if _failure_count == 0:
		print("ANNEX B2 TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("ANNEX B2 TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _clean() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path + suffix))


func _game(annex: Array) -> VaultGame:
	_clean()
	var store := WingRecords.new()
	store.path = _path
	var seed_value := 0x0700
	for level: int in annex:
		seed_value += 1
		store.record(seed_value, true, 2, 9, level, true)
	var game := _spawn_game()
	game.records_path = _path
	return game


func _count(game: VaultGame, kind: int, built: bool) -> int:
	var count := 0
	for building: VaultBuilding in game.buildings:
		if building.kind == kind and building.complete == built:
			count += 1
	return count


func _shape(game: VaultGame) -> Array:
	return [game.food_system.meals, game.food_system.salvage, game.residents.size(), _count(game, VaultBuilding.Kind.LAMP, true), _count(game, VaultBuilding.Kind.GROW_TRAY, true), _count(game, VaultBuilding.Kind.GROW_TRAY, false), game.breach_system.warning_at]


func _has() -> bool:
	_assert_true(VaultGame.PERKS.has("grow_nook"), "VaultGame has GROW NOOK")
	return VaultGame.PERKS.has("grow_nook")


func _test_unlock() -> void:
	var game := _game([7, 7])
	if not _has():
		_dispose(game)
		return
	game.new_game(false, 4242)
	_assert_equal(game.unlocked_perks(), ["provisioning", "bunkroom"], "two badges on one sublevel: BUNKROOM only")
	_dispose(game)
	game = _game([7, 5])
	game.new_game(false, 4242)
	_assert_equal(game.unlocked_perks(), ["provisioning", "floodlight", "bunkroom", "grow_nook"], "badges on 07 and 05: GROW NOOK after BUNKROOM")
	_assert_equal(VaultGame.perk_name("grow_nook"), "GROW NOOK", "named")
	_assert_equal([str(VaultGame.PERKS.bunkroom.detail), str(VaultGame.PERKS.grow_nook.detail)], ["blueprint: +1 Bunk, -14 salvage", "blueprint: Grow Tray plan, -2 meals"], "short blueprint details that clear the row arrow")
	game.records_path = ""
	game.equipped_perk = "grow_nook"
	game.new_game(false, 4242)
	_assert_equal([game.wing_perk, game.get_building_at(VaultGame.GROW_NOOK_CELL) == null], ["", true], "records off: NONE, no plan")
	game.records_path = _path
	game.new_game(false, 0)
	_assert_equal([game.wing_perk, game.get_building_at(VaultGame.GROW_NOOK_CELL) == null], ["", true], "seed 0: NONE, no plan")
	_dispose(game)
	_clean()


func _test_effect() -> void:
	var game := _game([5, 3])
	if not _has():
		_dispose(game)
		return
	for level: int in [7, 6, 5, 4, 3]:
		for seed_value: int in [4242, 8, 1234]:
			var label := "%02d/%d" % [level, seed_value]
			game.equipped_perk = ""
			game.new_game(false, seed_value, level)
			var base := _shape(game)
			_assert_true(game.get_building_at(VaultGame.GROW_NOOK_CELL) == null and game.map_grid.is_walkable(VaultGame.GROW_NOOK_CELL), label + " NONE: the nook cell is free floor")
			game.equipped_perk = "grow_nook"
			game.new_game(false, seed_value, level)
			_assert_equal(game.wing_perk, "grow_nook", label + ": GROW NOOK equipped")
			_assert_equal(_shape(game), [maxi(0, base[0] - VaultGame.GROW_NOOK_MEALS_COST), base[1], base[2], base[3], base[4], base[5] + 1, base[6]], label + ": one unbuilt Grow Tray for its meals; same salvage, crew, light and hatch")
			var tray: VaultBuilding = game.get_building_at(VaultGame.GROW_NOOK_CELL)
			_assert_true(tray != null and tray.kind == VaultBuilding.Kind.GROW_TRAY and not tray.complete and tray.is_supplied(), label + ": a supplied, unbuilt Grow Tray plan on the nook cell")
	_assert_true(VaultGame.GROW_NOOK_MEALS_COST > 0, "a trade-off, not a gift")
	_dispose(game)
	_clean()


func _test_save_load() -> void:
	var game := _game([7, 3])
	if not _has():
		_dispose(game)
		return
	game.equipped_perk = "grow_nook"
	game.new_game(false, 4242)
	var shape := _shape(game)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	_assert_equal(saved.get("perk", {}), {"version": 1.0, "id": "grow_nook"}, "saved under the version-1 perk key")
	game.equipped_perk = ""
	game.new_game(false, 4242)
	_assert_true(game.apply_snapshot(saved), "loads")
	_assert_equal([game.wing_perk, _shape(game)], ["grow_nook", shape], "restored once, no second plan or charge")
	_dispose(game)
	_clean()
