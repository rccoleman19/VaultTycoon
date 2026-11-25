extends "res://tests/test_runner.gd"

# The earlier RELAY LUMEN consumer could be disabled and saved. LOAD must restore its free light
# without enabling ordinary lamps or FLOODLIGHT. Use existing APIs so the baseline fails assertions.
var _records_path := ""
var _save_path := ""


func _run() -> void:
	_records_path = "user://test_relay_lumen_old_save_records_%d.json" % OS.get_process_id()
	_save_path = "user://test_relay_lumen_old_save_%d.json" % OS.get_process_id()
	_clean()
	var store := WingRecords.new()
	store.path = _records_path
	store.record(0x0B03, true, 3, 9, 5, true)
	_run_case("03 old disabled RELAY LUMEN save restores free light and preserves a disabled player lamp", _test_old_disabled_save)
	_run_case("a disabled FLOODLIGHT stays disabled after disk save/load", _test_disabled_floodlight)
	_clean()
	print("")
	if _failure_count == 0:
		print("RELAY LUMEN OLD SAVE TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
	else:
		printerr("RELAY LUMEN OLD SAVE TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
	quit(1 if _failure_count else 0)


func _clean() -> void:
	for path: String in [_records_path, _save_path]:
		for suffix: String in ["", ".tmp", ".bak"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _wing(perk: String) -> VaultGame:
	var game := _spawn_game()
	game.records_path = _records_path
	game.equipped_perk = perk
	game.new_game(false, 4242, 3)
	_assert_equal([game.wing_perk, game.sublevel, game.wing_seed], [perk, 3, 4242], "fixture: earned requested perk on 03 at seed 4242")
	game.begin_shift()
	return game


func _load_shape(game: VaultGame) -> Array:
	return [game.power_grid.supply, game.power_grid.demand, game.power_grid.served, game.power_grid.shed_demand]


# Edit the serialized entry, not the live building: even fixed NEW WING code must load old bytes.
func _write_old_disabled_entry() -> bool:
	var file := FileAccess.open(_save_path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or not parsed.get("game") is Dictionary:
		return false
	var wrapped: Dictionary = parsed
	var matches := 0
	for entry: Dictionary in wrapped.game.buildings:
		var cell := Vector2i(int(entry.cell[0]), int(entry.cell[1]))
		if int(entry.id) == VaultGame.FLOODLIGHT_BUILDING_ID and int(entry.kind) == VaultBuilding.Kind.LAMP and cell == VaultGame.RELAY_LUMEN_CELL:
			entry.manually_disabled = true
			entry.powered = false
			matches += 1
	_assert_equal(matches, 1, "fixture: exactly one serialized perk Lumen matches id, kind and cell")
	if matches != 1:
		return false
	file = FileAccess.open(_save_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(wrapped))
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK


func _test_old_disabled_save() -> void:
	var none := _wing("")
	var game := _wing(VaultGame.PERK_RELAY_LUMEN)
	var lamp := game.get_building_at(VaultGame.RELAY_LUMEN_CELL)
	_assert_true(lamp != null and lamp.complete and lamp.building_id == VaultGame.FLOODLIGHT_BUILDING_ID, "fixture: built perk Lumen")
	if lamp == null:
		_dispose(none)
		_dispose(game)
		return
	_assert_true(lamp.self_powered and lamp.powered and not lamp.manually_disabled, "NEW WING derives an enabled, self-powered perk Lumen")
	var player_lamp := _add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(26, 13))
	_assert_true(player_lamp.building_id != VaultGame.FLOODLIGHT_BUILDING_ID, "fixture: player lamp has its own id on another cell")
	_assert_true(game.toggle_building_enabled(player_lamp.building_id), "disable the normal player lamp before saving")
	var saved := game.save_game(false, _save_path)
	_assert_true(saved, "write a normal wing save to disk")
	if not saved:
		_dispose(none)
		_dispose(game)
		return
	var edited := _write_old_disabled_entry()
	_assert_true(edited, "persist the old perk Lumen's manually_disabled=true entry")
	if not edited:
		_dispose(none)
		_dispose(game)
		return
	game.equipped_perk = ""
	game.new_game(false, 4242, 3)
	var loaded := game.load_game(_save_path)
	_assert_true(loaded, "load the edited disk save over a NONE wing")
	if loaded:
		_assert_equal([game.wing_perk, game.sublevel, game.wing_seed], [VaultGame.PERK_RELAY_LUMEN, 3, 4242], "LOAD restores the saved 03 RELAY LUMEN wing")
		lamp = game.get_building_at(VaultGame.RELAY_LUMEN_CELL)
		_assert_true(lamp != null, "loaded perk Lumen exists")
		if lamp != null:
			_assert_false(lamp.manually_disabled, "LOAD clears the obsolete perk Lumen disable flag")
			_assert_true(lamp.powered, "loaded perk Lumen is powered")
			_assert_true(lamp.self_powered, "LOAD re-derives self-powered status")
			_assert_equal([lamp.get_base_power_demand(), lamp.get_power_demand()], [0, 0], "loaded perk Lumen draws zero power")
		_assert_equal(_load_shape(game), _load_shape(none), "loaded served/demand and supply/shedding match NONE")
		_assert_equal(game.lighting_system.get_powered_lumen_count(), none.lighting_system.get_powered_lumen_count() + 1, "loaded perk Lumen counts as one additional lit lamp")
		player_lamp = game.get_building_at(Vector2i(26, 13))
		_assert_true(player_lamp != null, "loaded player lamp exists on its own cell")
		if player_lamp != null:
			_assert_true(player_lamp.manually_disabled, "LOAD preserves the player lamp's disabled flag")
			_assert_false(player_lamp.powered or player_lamp.self_powered, "disabled player lamp stays offline without self-power")
			_assert_equal([player_lamp.get_base_power_demand(), player_lamp.get_power_demand()], [1, 0], "player lamp keeps normal base demand while disabled")
	_dispose(none)
	_dispose(game)


func _test_disabled_floodlight() -> void:
	var game := _wing(VaultGame.PERK_FLOODLIGHT)
	var lamp := game.get_building_at(VaultGame.FLOODLIGHT_CELL)
	_assert_true(lamp != null, "fixture: FLOODLIGHT lamp exists")
	if lamp == null:
		_dispose(game)
		return
	_assert_true(game.toggle_building_enabled(lamp.building_id), "disable FLOODLIGHT through its normal control")
	_assert_true(game.save_game(false, _save_path), "save disabled FLOODLIGHT to disk")
	var loaded := game.load_game(_save_path)
	_assert_true(loaded, "load disabled FLOODLIGHT from disk")
	if loaded:
		lamp = game.get_building_at(VaultGame.FLOODLIGHT_CELL)
		_assert_true(lamp != null, "loaded FLOODLIGHT lamp exists")
		if lamp != null:
			_assert_true(lamp.manually_disabled, "LOAD preserves FLOODLIGHT's disabled flag")
			_assert_false(lamp.powered or lamp.self_powered, "disabled FLOODLIGHT stays offline without self-power")
			_assert_equal([lamp.get_base_power_demand(), lamp.get_power_demand()], [1, 0], "FLOODLIGHT keeps normal base demand while disabled")
	_dispose(game)
