extends "res://tests/test_runner.gd"

# Records + ladder C3: a finished seeded run merges into its wing record once, at the finish
# transition, and the outcome panel shows the record under the crew rating.

var _path := ""


func _run() -> void:
	_path = "user://test_records_finish_%d.json" % OS.get_process_id()
	_run_case("a seeded win records its grade and shows BEST with NEW RECORD", _test_win)
	_run_case("a worse later win keeps the best and drops NEW RECORD", _test_worse_win)
	_run_case("LOAD shows the record but never writes", _test_load_no_write)
	_run_case("a loss records the day reached and shows FURTHEST DAY", _test_loss)
	_run_case("seed 0 and stores that are off or unreadable record nothing", _test_off)
	print("")
	if _failure_count == 0:
		print("RECORDS FINISH TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("RECORDS FINISH TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _clean() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path + suffix))


func _game(seed_value: int) -> VaultGame:
	var game := _spawn_game()
	game.records_path = _path
	game.new_game(false, seed_value)
	game.begin_shift()
	for resident: VaultResident in game.residents:
		resident.needs.food = 80.0
		resident.needs.rest = 80.0
		resident.needs.mood = 60.0
	return game


func _win(game: VaultGame) -> void:
	game.day_cycle.current_day = DayCycle.DAYS_TO_SURVIVE
	game._finish_win()


func _bytes() -> String:
	return FileAccess.get_file_as_string(_path) if FileAccess.file_exists(_path) else ""


func _test_win() -> void:
	_clean()
	var game := _game(4242)
	_assert_true(game.has_method("_record_finish"), "VaultGame records at the finish")
	if not game.has_method("_record_finish"):
		_dispose(game)
		return
	_assert_equal(int(game.player_orders.crew_grade()["stars"]), 3, "a full-marks crew")
	_win(game)
	_assert_true(game.ended and game.outcome == "win", "the run is won")
	_assert_equal(game.wing_records().get_record(4242), {"ever_won": true, "best_stars": 3, "best_day": 7, "annex": false}, "the win is recorded with its grade")
	_assert_true(game.player_orders.outcome_record.visible, "the record line shows")
	_assert_equal(game.player_orders.outcome_record.text, "BEST ★★★ · NEW RECORD", "first win is a new record")
	var bytes := _bytes()
	game._finish_win()
	_assert_equal(_bytes(), bytes, "a second finish call records nothing more")
	_dispose(game)
	_clean()


func _test_worse_win() -> void:
	_clean()
	var game := _game(4242)
	_win(game)
	_dispose(game)
	game = _game(4242)
	game.residents[0].needs.health = 0.0
	game.residents[0].kill()
	_assert_equal(int(game.player_orders.crew_grade()["stars"]), 2, "one crew lost: two stars")
	_win(game)
	_assert_equal(int(game.wing_records().get_record(4242).best_stars), 3, "the best grade is kept")
	_assert_equal(game.player_orders.outcome_record.text, "BEST ★★★", "no NEW RECORD for a worse win")
	_assert_equal(game.player_orders.outcome_grade.text.substr(0, 17), "CREW RATING ★★☆ ·", "the crew rating still grades this run")
	_dispose(game)
	game = _game(0x0BAD)
	game.residents[0].needs.health = 0.0
	game.residents[0].kill()
	_win(game)
	_assert_equal(game.player_orders.outcome_record.text, "BEST ★★☆ · NEW RECORD", "a first 2-star win on another wing is a new record")
	_dispose(game)
	_clean()


func _test_load_no_write() -> void:
	_clean()
	var game := _game(4242)
	# A loadable win: hatch sealed and seven full days on the clock.
	game.day_cycle.deserialize({"elapsed_seconds": 100.0, "current_day": 2, "completed": false})
	game.breach_system.advance(0.0, 100.0)
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.apply_patch_work(100.0)
	game.job_system.rebuild_from_state()
	game.day_cycle.deserialize({"elapsed_seconds": DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE, "current_day": DayCycle.DAYS_TO_SURVIVE, "completed": true})
	_assert_true(game.breach_system.is_sealed(), "the hatch is sealed")
	game._finish_win()
	var snapshot := JSON.stringify(game.create_snapshot())
	_assert_false(snapshot.contains("record"), "the save carries no record data")
	var bytes := _bytes()
	game.new_game(false, 4242)
	_assert_true(game.finish_record.is_empty(), "NEW WING clears the finish record")
	# Remove the record so any write during LOAD would show up as a new file.
	_clean()
	_assert_true(game.load_game(), "the won save (written by the finish) loads")
	_assert_false(FileAccess.file_exists(_path), "LOAD writes no record")
	_assert_false(game.player_orders.outcome_record.visible, "with the record gone, LOAD shows no record line")
	var restore := FileAccess.open(_path, FileAccess.WRITE)
	restore.store_string(bytes)
	restore.close()
	_assert_true(game.load_game(), "the won save loads again with the record back")
	_assert_true(game.finish_record.is_empty(), "LOAD has no finish record")
	var best := int(game.wing_records().get_record(4242).best_stars)
	_assert_equal(game.player_orders.outcome_record.text, "BEST %s%s" % ["★".repeat(best), "☆".repeat(3 - best)], "LOAD shows the plain record, no NEW RECORD")
	_assert_equal(_bytes(), bytes, "LOAD never writes the record")
	_dispose(game)
	_clean()


func _test_loss() -> void:
	_clean()
	var game := _game(77)
	game.day_cycle.current_day = 3
	game._finish_loss()
	_assert_equal(game.wing_records().get_record(77), {"ever_won": false, "best_stars": null, "best_day": 3, "annex": false}, "the loss is recorded with its day")
	_assert_equal(game.player_orders.outcome_record.text, "FURTHEST DAY 3 · NEW RECORD", "loss shows the furthest day")
	_assert_equal(game.player_orders.outcome_title.text, "WING LOST", "loss title unchanged")
	_dispose(game)
	game = _game(77)
	game.day_cycle.current_day = 2
	game._finish_loss()
	_assert_equal(game.player_orders.outcome_record.text, "FURTHEST DAY 3", "an earlier loss keeps the furthest day")
	_dispose(game)
	_clean()


func _test_off() -> void:
	_clean()
	var game := _game(0)
	_win(game)
	_assert_false(FileAccess.file_exists(_path), "seed 0 writes nothing")
	_assert_false(game.player_orders.outcome_record.visible, "seed 0 shows no record line")
	_dispose(game)
	game = _spawn_game()
	game.new_game(false, 4242)
	game.begin_shift()
	_win(game)
	_assert_true(game.finish_record.is_empty(), "a test tree without a store records nothing")
	_assert_false(game.player_orders.outcome_record.visible, "and shows no record line")
	_dispose(game)
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 9, "wings": {}}))
	file.close()
	var future := _bytes()
	game = _game(4242)
	_win(game)
	_assert_true(game.ended and game.outcome == "win", "an unsupported store never blocks the win")
	_assert_equal(_bytes(), future, "and is never overwritten")
	_assert_false(game.player_orders.outcome_record.visible, "no record line without a readable record")
	_dispose(game)
	_clean()
