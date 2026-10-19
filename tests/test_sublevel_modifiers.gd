extends "res://tests/test_runner.gd"

# Records + ladder C5: one named modifier per sublevel below 07 (not cumulative), restored on LOAD,
# and a win on N unlocks N-1.

var _path := ""


func _run() -> void:
	_path = "user://test_sublevel_modifiers_%d.json" % OS.get_process_id()
	_run_case("07 and seed 0 carry no modifier", _test_base)
	_run_case("06 EARLY HATCH moves the hatch test 15 s earlier, kept on LOAD and in validation", _test_early_hatch)
	_run_case("05 THIN VEINS digs veins for 4 salvage, kept on LOAD", _test_thin_veins)
	_run_case("04 DARK START has no starter Lumen", _test_dark_start)
	_run_case("03 FIFTH MOUTH starts five residents", _test_fifth_mouth)
	_run_case("a win on N unlocks N-1 and the win screen says so", _test_unlock)
	print("")
	if _failure_count == 0:
		print("SUBLEVEL MODIFIER TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("SUBLEVEL MODIFIER TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _guard(game: VaultGame) -> bool:
	var ok := game.has_method("_apply_sublevel_rules")
	_assert_true(ok, "VaultGame applies sublevel rules")
	return ok


func _lamps(game: VaultGame) -> int:
	var count := 0
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.LAMP:
			count += 1
	return count


func _round_trip(game: VaultGame) -> bool:
	return game.apply_snapshot(JSON.parse_string(JSON.stringify(game.create_snapshot())))


func _vein(game: VaultGame) -> Vector2i:
	return game.map_grid.vein_cells.keys()[0]


func _test_base() -> void:
	var game := _spawn_game()
	if not _guard(game):
		_dispose(game)
		return
	for args: Array in [[4242, 7], [0, 4], [0, 3], [0, 6]]:
		game.new_game(false, args[0], args[1])
		_assert_equal(game.breach_system.warning_at, BreachSystem.warning_at_for_seed(args[0]), "%s: hatch time unchanged" % [args])
		_assert_equal(game.map_grid.vein_yield, MapGrid.VEIN_SALVAGE_YIELD, "%s: vein yield unchanged" % [args])
		_assert_equal(_lamps(game), 1, "%s: starter Lumen" % [args])
		_assert_equal(game.residents.size(), 4, "%s: four crew" % [args])
		_assert_false(game.player_orders.wing_brand_label.text.contains("·"), "%s: no modifier in the top bar" % [args])
	_dispose(game)


func _test_early_hatch() -> void:
	var game := _spawn_game()
	if not _guard(game):
		_dispose(game)
		return
	game.new_game(false, 4242, 6)
	var base := BreachSystem.warning_at_for_seed(4242)
	_assert_equal(game.breach_system.warning_at, base - 15.0, "warning 15 s earlier")
	_assert_equal(game.breach_system.get_open_at(), base - 15.0 + BreachSystem.GRACE_SECONDS, "the 20 s grace is kept")
	_assert_equal(game.player_orders.wing_brand_label.text, "VAULT WING // 06-1092 · EARLY HATCH", "top bar names the modifier")
	var warn := roundi(base - 15.0)
	_assert_true(game.player_orders.wing_briefing_title.text.contains("HATCH TEST AT %02d:%02d" % [warn / 60, warn % 60]), "briefing shows the earlier hatch test")
	_assert_true(game.player_orders.wing_briefing_title.text.contains("SUBLEVEL 06 · EARLY HATCH: hatch test 15 s earlier"), "briefing names the modifier")
	_assert_equal(_vein_yield_and_lamps(game), [MapGrid.VEIN_SALVAGE_YIELD, 1, 4], "not cumulative")
	game.begin_shift()
	game.step_simulation(base - 10.0)
	_assert_true(game.breach_system.phase == BreachSystem.Phase.WARNING, "the warning fires before the 07 time")
	var early: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	game.new_game(false, 4242)
	_assert_equal(game.breach_system.warning_at, base, "a 07 wing is back to the seed's time")
	_assert_true(game.apply_snapshot(early), "a 06 save mid-warning is valid and loads over a 07 wing")
	_assert_equal(game.breach_system.warning_at, base - 15.0, "LOAD restores the earlier hatch")
	_dispose(game)


func _vein_yield_and_lamps(game: VaultGame) -> Array:
	return [game.map_grid.vein_yield, _lamps(game), game.residents.size()]


func _test_thin_veins() -> void:
	var game := _spawn_game()
	if not _guard(game):
		_dispose(game)
		return
	game.new_game(false, 4242, 5)
	_assert_equal(game.map_grid.get_dig_yield(_vein(game)), 4, "a vein yields 4")
	_assert_equal(game.map_grid.get_dig_yield(Vector2i(0, 0)), 3, "plain rock still yields 3")
	_assert_equal(game.breach_system.warning_at, BreachSystem.warning_at_for_seed(4242), "not cumulative: hatch unchanged")
	_assert_true(game.player_orders.wing_brand_label.text.ends_with("· THIN VEINS"), "top bar names THIN VEINS")
	var low: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	game.new_game(false, 4242)
	_assert_equal(game.map_grid.get_dig_yield(_vein(game)), MapGrid.VEIN_SALVAGE_YIELD, "07 veins yield 6 again")
	_assert_true(game.apply_snapshot(low), "a 05 save loads over a 07 wing")
	_assert_equal(game.map_grid.get_dig_yield(_vein(game)), 4, "LOAD restores thin veins")
	_dispose(game)


func _test_dark_start() -> void:
	var game := _spawn_game()
	if not _guard(game):
		_dispose(game)
		return
	game.new_game(false, 4242, 4)
	_assert_equal(_lamps(game), 0, "no starter Lumen")
	_assert_equal(game.residents.size(), 4, "four crew")
	_assert_true(_round_trip(game), "a 04 save loads")
	_assert_equal(_lamps(game), 0, "LOAD adds no Lumen")
	_dispose(game)


func _test_fifth_mouth() -> void:
	var game := _spawn_game()
	if not _guard(game):
		_dispose(game)
		return
	game.new_game(false, 4242, 3)
	_assert_equal(game.residents.size(), 5, "five residents")
	var fen: VaultResident = game.residents[4]
	_assert_equal([fen.resident_id, fen.resident_name], [5, "Fen"], "the fifth is Fen, id 5")
	_assert_equal(fen.trait_id, VaultResident.crew_traits_for_seed(4242)[4], "Fen takes the fifth trait slot")
	_assert_equal(_lamps(game), 1, "not cumulative: Lumen kept")
	_assert_true(_round_trip(game), "a 03 save loads")
	_assert_equal(game.residents.size(), 5, "LOAD keeps five")
	_dispose(game)


func _win(game: VaultGame) -> void:
	game.day_cycle.current_day = DayCycle.DAYS_TO_SURVIVE
	game._finish_win()


func _clean() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path + suffix))


func _seeded(level: int) -> VaultGame:
	var game := _spawn_game()
	game.records_path = _path
	game.new_game(false, 4242, level)
	game.begin_shift()
	return game


func _test_unlock() -> void:
	_clean()
	var probe := _spawn_game()
	var ok := _guard(probe)
	_dispose(probe)
	if not ok:
		return
	var game := _seeded(7)
	_assert_equal(game.wing_records().unlocked_sublevel(), 7, "nothing unlocked yet")
	_win(game)
	_assert_equal(int(game.finish_record.get("unlocked", 0)), 6, "a 07 win unlocks 06")
	_assert_true(game.player_orders.outcome_record.text.ends_with("\nSUBLEVEL 06 UNLOCKED · EARLY HATCH"), "the win screen says so: %s" % game.player_orders.outcome_record.text)
	_dispose(game)
	game = _seeded(7)
	_win(game)
	_assert_false(game.finish_record.has("unlocked"), "a second 07 win unlocks nothing new")
	_assert_false(game.player_orders.outcome_record.text.contains("UNLOCKED"), "and says nothing")
	_dispose(game)
	game = _seeded(6)
	game.day_cycle.current_day = 3
	game._finish_loss()
	_assert_false(game.finish_record.has("unlocked"), "a 06 loss unlocks nothing")
	_dispose(game)
	game = _seeded(6)
	_win(game)
	_assert_true(game.player_orders.outcome_record.text.ends_with("SUBLEVEL 05 UNLOCKED · THIN VEINS"), "a 06 win unlocks 05")
	_dispose(game)
	game = _seeded(3)
	_win(game)
	_assert_false(game.finish_record.has("unlocked"), "03 is the floor: a win there unlocks nothing")
	_assert_equal(game.wing_records().unlocked_sublevel(), 3, "03 stays the deepest")
	_dispose(game)
	_clean()
