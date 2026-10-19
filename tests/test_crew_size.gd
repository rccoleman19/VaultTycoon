extends "res://tests/test_runner.gd"

# One crew-size rule for NEW WING and LOAD (Codex 6277982335): 4, +1 on 03 (Fen), +1 for VOLUNTEER
# (Gil); LOAD also leaves room for the Annex resident. A VOLUNTEER wing on 03 has 6 and must reload.

var _path := ""
var _save := ""


func _run() -> void:
	_path = "user://test_crew_size_%d.json" % OS.get_process_id()
	_save = "user://test_crew_size_%d.sav" % OS.get_process_id()
	_run_case("NEW WING builds exactly the shared crew size", _test_new_wing)
	_run_case("a VOLUNTEER wing on 03 (6 residents) saves to disk and reloads", _test_volunteer_03_disk)
	_run_case("LOAD takes room for the Annex resident and rejects one more", _test_cap)
	print("")
	if _failure_count == 0:
		print("CREW SIZE TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("CREW SIZE TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _clean() -> void:
	for base: String in [_path, _save]:
		for suffix: String in ["", ".tmp", ".bak"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(base + suffix))


func _game() -> VaultGame:
	_clean()
	var store := WingRecords.new()
	store.path = _path
	for level: int in [7, 6, 5, 4, 3]:
		store.record(0x0777, true, 2, 7, level)
	var game := _spawn_game()
	game.records_path = _path
	return game


func _test_new_wing() -> void:
	_assert_equal([VaultGame.starting_crew_size(7, ""), VaultGame.starting_crew_size(3, ""), VaultGame.starting_crew_size(7, "volunteer"), VaultGame.starting_crew_size(3, "volunteer")], [4, 5, 5, 6], "4, +1 on 03, +1 for VOLUNTEER")
	_assert_equal([VaultGame.max_crew_size(7, ""), VaultGame.max_crew_size(3, "volunteer")], [5, 7], "LOAD cap = crew + 1 for the Annex resident")
	var game := _game()
	for level: int in [7, 6, 5, 4, 3]:
		for perk: String in ["", "provisioning", "volunteer"]:
			game.equipped_perk = perk
			game.new_game(false, 4242, level)
			var names := []
			for resident: VaultResident in game.residents:
				names.append(resident.resident_name)
			_assert_equal(game.residents.size(), VaultGame.starting_crew_size(level, perk), "%02d %s: crew size" % [level, perk])
			_assert_equal(names.slice(4), VaultGame.extra_crew_names(level, perk), "%02d %s: the extra hands" % [level, perk])
	_dispose(game)
	_clean()


func _test_volunteer_03_disk() -> void:
	var game := _game()
	game.equipped_perk = "volunteer"
	game.new_game(false, 4242, 3)
	_assert_equal([game.wing_perk, game.residents.size()], ["volunteer", 6], "03 + VOLUNTEER: six residents")
	_assert_true(game.save_game(false, _save), "saved to disk")
	game.equipped_perk = ""
	game.new_game(false, 4242, 7)
	_assert_true(game.load_game(_save), "the six-resident save loads")
	_assert_equal([game.wing_perk, game.sublevel, game.residents.size()], ["volunteer", 3, 6], "restored as saved")
	_dispose(game)
	_clean()


func _with_extra(snapshot: Dictionary, count: int) -> Dictionary:
	var copy: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	var list: Array = copy.residents
	var template: Dictionary = list[-1]
	for index in count:
		var entry: Dictionary = template.duplicate(true)
		entry.id = list.size() + 1
		entry.name = "Extra%d" % index
		list.append(entry)
	return copy


func _test_cap() -> void:
	var game := _game()
	for case: Array in [[7, ""], [3, ""], [3, "volunteer"]]:
		game.equipped_perk = case[1]
		game.new_game(false, 4242, case[0])
		var label := "%02d %s" % case
		var snapshot: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
		_assert_true(game.apply_snapshot(_with_extra(snapshot, 1)), label + ": one more (room for the Annex resident) loads")
		_assert_false(game.apply_snapshot(_with_extra(snapshot, 2)), label + ": one beyond the cap is rejected")
	_dispose(game)
	_clean()
