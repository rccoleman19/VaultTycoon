extends "res://tests/test_runner.gd"

# Records + ladder C4: a wing's sublevel (07 base, down to 03) names it, saves additively below 07,
# survives LOAD and REPLAY, and keys its record.


func _run() -> void:
	_run_case("07 and seed 0 keep today's labels and save bytes", _test_base)
	_run_case("a lower sublevel names the wing and saves an additive key", _test_lower)
	_run_case("LOAD restores the sublevel and REPLAY keeps it", _test_load_replay)
	_run_case("malformed sublevel keys make the save invalid", _test_validation)
	_run_case("a finish records under the sublevel's key", _test_record_key)
	print("")
	if _failure_count == 0:
		print("SUBLEVEL TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("SUBLEVEL TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _guard(game: VaultGame) -> bool:
	var ok: bool = "sublevel" in game
	_assert_true(ok, "VaultGame has a sublevel")
	return ok


func _test_base() -> void:
	var game := _spawn_game()
	if not _guard(game):
		_dispose(game)
		return
	game.new_game(false, 4242)
	_assert_equal(game.sublevel, 7, "new_game defaults to 07")
	_assert_false(game.create_snapshot().has("sublevel"), "07 writes no sublevel key")
	_assert_equal(game.player_orders.wing_brand_label.text, "VAULT WING // 07-1092", "07 top bar unchanged")
	_assert_true(game.player_orders.wing_briefing_title.text.begins_with("VAULT WING 07-1092 // SEAL STABILIZATION"), "07 briefing title unchanged")
	game.new_game(false, 0, 5)
	_assert_equal(game.sublevel, 7, "seed 0 is always 07")
	_assert_false(game.create_snapshot().has("sublevel"), "seed 0 writes no sublevel key")
	_assert_equal(game.player_orders.wing_brand_label.text, "VAULT WING // SUBLEVEL 07", "seed 0 top bar unchanged")
	_assert_equal(PlayerOrders.wing_id(4242), "07-1092", "wing_id defaults to 07")
	_dispose(game)


func _test_lower() -> void:
	var game := _spawn_game()
	if not _guard(game):
		_dispose(game)
		return
	game.new_game(false, 4242, 6)
	_assert_equal(game.sublevel, 6, "sublevel 06")
	_assert_equal(game.create_snapshot().get("sublevel"), {"version": 1, "level": 6}, "06 saves the additive key")
	_assert_equal(game.player_orders.wing_brand_label.text, "VAULT WING // 06-1092", "top bar names 06")
	_assert_true(game.player_orders.wing_briefing_title.text.begins_with("VAULT WING 06-1092 // SEAL STABILIZATION"), "briefing names 06")
	game.new_game(false, 4242, 1)
	_assert_equal(game.sublevel, 3, "below 03 clamps to 03")
	game.new_game(false, 4242, 9)
	_assert_equal(game.sublevel, 7, "above 07 clamps to 07")
	_assert_false(game.create_snapshot().has("sublevel"), "and writes no key")
	_dispose(game)


func _test_load_replay() -> void:
	var game := _spawn_game()
	if not _guard(game):
		_dispose(game)
		return
	game.new_game(false, 4242, 5)
	var low: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	game.new_game(false, 4242)
	var base: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	_assert_true(game.apply_snapshot(low), "the 05 save loads")
	_assert_equal(game.sublevel, 5, "LOAD restores 05")
	_assert_equal(game.player_orders.wing_brand_label.text, "VAULT WING // 05-1092", "top bar after LOAD")
	_assert_true(game.apply_snapshot(base), "the 07 save loads")
	_assert_equal(game.sublevel, 7, "a save without the key is 07")
	_assert_true(game.apply_snapshot(low), "the 05 save loads again")
	game.player_orders.replay_wing()
	_assert_equal([game.wing_seed, game.sublevel], [4242, 5], "REPLAY keeps the seed and the sublevel")
	_assert_false(game.ended, "REPLAY starts a fresh run")
	_dispose(game)


func _test_validation() -> void:
	var game := _spawn_game()
	if not _guard(game):
		_dispose(game)
		return
	game.new_game(false, 4242, 6)
	var good: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	_assert_true(game._is_snapshot_shape_valid(good), "a 06 save is valid")
	var bad_values := [
		{"version": 1, "level": 7},
		{"version": 1, "level": 2},
		{"version": 2, "level": 6},
		{"version": 1, "level": "6"},
		{"version": 1, "level": 6.5},
		{"version": 1, "level": 6, "extra": 1},
		{"level": 6},
		6,
	]
	for index in bad_values.size():
		var copy := good.duplicate(true)
		copy["sublevel"] = bad_values[index]
		_assert_false(game._is_snapshot_shape_valid(copy), "malformed sublevel %d is invalid" % index)
	game.new_game(false, 0)
	var legacy: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	legacy["sublevel"] = {"version": 1, "level": 6}
	_assert_false(game._is_snapshot_shape_valid(legacy), "seed 0 cannot carry a sublevel")
	_dispose(game)


func _test_record_key() -> void:
	var path := "user://test_sublevel_%d.json" % OS.get_process_id()
	var game := _spawn_game()
	if not _guard(game):
		_dispose(game)
		return
	game.records_path = path
	game.new_game(false, 4242, 6)
	game.begin_shift()
	game.day_cycle.current_day = DayCycle.DAYS_TO_SURVIVE
	game._finish_win()
	_assert_true(bool(game.wing_records().get_record(4242, 6).get("ever_won", false)), "the win is recorded under 06-1092")
	_assert_equal(game.wing_records().get_record(4242), {}, "07-1092 is untouched")
	_assert_true(game.player_orders.outcome_record.text.begins_with("BEST "), "the outcome shows the 06 record")
	_dispose(game)
	for suffix: String in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
