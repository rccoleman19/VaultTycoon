extends "res://tests/test_runner.gd"

# Records + ladder C1: tests, QA drivers and seed 0 never touch the player's wing records.


func _run() -> void:
	_run_case("records stay off under a test SceneTree and for seed 0", _test_isolation)
	print("")
	if _failure_count == 0:
		print("RECORDS ISOLATION TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("RECORDS ISOLATION TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _test_isolation() -> void:
	var game := _spawn_game()
	_assert_true(game.has_method("records_enabled") and game.has_method("wing_records"), "VaultGame exposes the records guard")
	if not game.has_method("records_enabled"):
		_dispose(game)
		return
	game.new_game(false, 4242)
	_assert_equal(game.wing_seed, 4242, "a seeded wing")
	_assert_false(game.records_enabled(), "a test SceneTree never records by default")
	_assert_equal(game.wing_records().path, WingRecords.DEFAULT_PATH, "the store still names the real file")
	game.records_path = "user://test_records_isolation_%d.json" % OS.get_process_id()
	_assert_true(game.records_enabled(), "an injected path opts a test in")
	_assert_equal(game.wing_records().path, game.records_path, "and the store uses it")
	game.new_game(false, 0)
	_assert_false(game.records_enabled(), "seed 0 never records, even with a path")
	_assert_false(FileAccess.file_exists(game.records_path), "nothing was written")
	_dispose(game)
