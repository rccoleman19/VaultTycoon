extends "res://tests/test_runner.gd"

# Annex blueprints C1/B3: RELAY LUMEN is earned by an Annex badge on a 3-star win and takes the single
# perk slot: one built Lumen on a far corner tile at the start, at no cost, at the lowest power priority
# (it sheds before food and air). Stores, crew, the starter Lumen and the hatch clock are untouched.

var _path := ""


func _run() -> void:
	_path = "user://test_annex_b3_%d.json" % OS.get_process_id()
	_run_case("an Annex badge on a 3-star win unlocks RELAY LUMEN; 2 stars or no badge do not", _test_unlock)
	_run_case("RELAY LUMEN adds one built, shed-first Lumen for free and nothing else", _test_effect)
	_run_case("RELAY LUMEN survives save and load without a second Lumen", _test_save_load)
	print("")
	if _failure_count == 0:
		print("ANNEX B3 TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("ANNEX B3 TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _clean() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path + suffix))


# entries: [sublevel, stars, annex] per finished (won) wing.
func _game(entries: Array) -> VaultGame:
	_clean()
	var store := WingRecords.new()
	store.path = _path
	var seed_value := 0x0B00
	for entry: Array in entries:
		seed_value += 1
		store.record(seed_value, true, entry[1], 9, entry[0], entry[2])
	var game := _spawn_game()
	game.records_path = _path
	return game


func _lamps(game: VaultGame, built: bool) -> int:
	var count := 0
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.LAMP and building.complete == built:
			count += 1
	return count


func _shape(game: VaultGame) -> Array:
	return [game.food_system.meals, game.food_system.salvage, game.residents.size(), _lamps(game, true), _lamps(game, false), game.buildings.size(), game.breach_system.warning_at]


func _has() -> bool:
	_assert_true(VaultGame.PERKS.has("relay_lumen"), "VaultGame has RELAY LUMEN")
	return VaultGame.PERKS.has("relay_lumen")


func _test_unlock() -> void:
	var game := _game([[7, 2, true], [5, 2, true], [3, 3, false]])
	if not _has():
		_dispose(game)
		return
	game.new_game(false, 4242)
	_assert_equal(game.unlocked_perks(), ["provisioning", "floodlight", "volunteer", "bunkroom", "grow_nook"], "badges at 2 stars and a 3-star win without a badge: no RELAY LUMEN")
	_dispose(game)
	game = _game([[7, 3, true]])
	game.new_game(false, 4242)
	_assert_equal(game.unlocked_perks(), ["provisioning", "bunkroom", "relay_lumen"], "one Annex badge on a 3-star win: RELAY LUMEN after BUNKROOM")
	_dispose(game)
	game = _game([[7, 3, true], [5, 2, true]])
	game.new_game(false, 4242)
	_assert_equal(game.unlocked_perks(), ["provisioning", "floodlight", "bunkroom", "grow_nook", "relay_lumen"], "with GROW NOOK unlocked too: RELAY LUMEN comes last")
	_assert_equal(VaultGame.perk_name("relay_lumen"), "RELAY LUMEN", "named")
	_assert_equal(str(VaultGame.PERKS.relay_lumen.detail), "blueprint: +1 low Lumen, free", "short blueprint detail")
	game.records_path = ""
	game.equipped_perk = "relay_lumen"
	game.new_game(false, 4242)
	_assert_equal([game.wing_perk, game.get_building_at(VaultGame.RELAY_LUMEN_CELL) == null], ["", true], "records off: NONE, no Lumen")
	game.records_path = _path
	game.new_game(false, 0)
	_assert_equal([game.wing_perk, game.get_building_at(VaultGame.RELAY_LUMEN_CELL) == null], ["", true], "seed 0: NONE, no Lumen")
	_dispose(game)
	_clean()


func _test_effect() -> void:
	var game := _game([[5, 3, true]])
	if not _has():
		_dispose(game)
		return
	for level: int in [7, 6, 5, 4, 3]:
		for seed_value: int in [4242, 8, 1234]:
			var label := "%02d/%d" % [level, seed_value]
			game.equipped_perk = ""
			game.new_game(false, seed_value, level)
			var base := _shape(game)
			_assert_true(game.get_building_at(VaultGame.RELAY_LUMEN_CELL) == null and game.map_grid.is_walkable(VaultGame.RELAY_LUMEN_CELL), label + " NONE: the relay cell is free floor")
			game.equipped_perk = "relay_lumen"
			game.new_game(false, seed_value, level)
			_assert_equal(game.wing_perk, "relay_lumen", label + ": RELAY LUMEN equipped")
			_assert_equal(_shape(game), [base[0], base[1], base[2], base[3] + 1, base[4], base[5] + 1, base[6]], label + ": one built Lumen at no cost; same meals, salvage, crew, starter Lumen and hatch")
			var lamp: VaultBuilding = game.get_building_at(VaultGame.RELAY_LUMEN_CELL)
			_assert_true(lamp != null and lamp.kind == VaultBuilding.Kind.LAMP and lamp.complete and lamp.building_id == VaultGame.FLOODLIGHT_BUILDING_ID, label + ": a built Lumen with the perk id on the relay cell")
			_assert_equal(lamp.get_power_priority() if lamp != null else -1, VaultBuilding.PowerPriority.OPTIONAL, label + ": sheds before food and air")
			_assert_true(lamp != null and not lamp.is_emergency_core, label + ": not an emergency core")
			var starter: VaultBuilding = game.get_building_at(Vector2i(22, 14))
			_assert_equal(starter.get_power_priority() if starter != null else -1, VaultBuilding.PowerPriority.HIGH, label + ": the starter Lumen keeps HIGH")
	_dispose(game)
	_clean()


func _test_save_load() -> void:
	var game := _game([[7, 3, true]])
	if not _has():
		_dispose(game)
		return
	game.equipped_perk = "relay_lumen"
	game.new_game(false, 4242)
	var shape := _shape(game)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	_assert_equal(saved.get("perk", {}), {"version": 1.0, "id": "relay_lumen"}, "saved under the version-1 perk key")
	game.equipped_perk = ""
	game.new_game(false, 4242)
	_assert_true(game.apply_snapshot(saved), "loads")
	_assert_equal([game.wing_perk, _shape(game)], ["relay_lumen", shape], "restored once, no second Lumen")
	var lamp: VaultBuilding = game.get_building_at(VaultGame.RELAY_LUMEN_CELL)
	_assert_true(lamp != null and lamp.shed_first, "still sheds first after load")
	_dispose(game)
	_clean()
