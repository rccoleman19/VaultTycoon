extends "res://tests/test_runner.gd"

# Records x Keep Running seam (merge plan, #110 x #111): the win counts once, kept-running days raise
# best_day, a finished Annex sets the annex badge, a later loss keeps the win, and 03 FIFTH MOUTH's
# Annex resident is a sixth.

var _path := ""


func _run() -> void:
	_path = "user://test_records_keep_running_%d.json" % OS.get_process_id()
	_run_case("the win counts once and kept-running days raise best_day", _test_days)
	_run_case("a finished Annex sets the annex badge, not stars", _test_annex)
	_run_case("a kept-running loss keeps the win and shows the furthest day", _test_loss)
	_run_case("03 FIFTH MOUTH: Fen is 5 and the Annex brings a sixth", _test_fifth_mouth)
	_run_case("03 with VOLUNTEER: Fen 5, Gil 6, and the Annex still brings Eko as a seventh", _test_volunteer_annex)
	print("")
	if _failure_count == 0:
		print("RECORDS KEEP RUNNING TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("RECORDS KEEP RUNNING TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _clean() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path + suffix))


func _bytes() -> String:
	return FileAccess.get_file_as_string(_path) if FileAccess.file_exists(_path) else ""


func _calm(game: VaultGame) -> void:
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0


# A seeded wing won at Day 7 (recorded) and kept running.
func _won_running(level := 7, perk := "") -> VaultGame:
	var game := _spawn_game()
	game.records_path = _path
	game.equipped_perk = perk
	game.new_game(false, 4242, level)
	game.begin_shift()
	game.day_cycle.deserialize({"elapsed_seconds": 100.0, "current_day": 2, "completed": false})
	game.breach_system.advance(0.0, 100.0)
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.apply_patch_work(100.0)
	game.job_system.rebuild_from_state()
	game.day_cycle.deserialize({"elapsed_seconds": 279.5, "current_day": 7, "completed": false})
	game.oxygen_system.oxygen = 100.0
	_calm(game)
	game.step_simulation(1.0)
	_assert_true(game.ended and game.outcome == "win", "the wing is won")
	_assert_true(game.start_keep_running(), "keep running starts")
	_calm(game)
	return game


func _finish_annex(game: VaultGame) -> void:
	game.annex_meals = VaultGame.ANNEX_MEALS - 1
	game.annex_salvage = VaultGame.ANNEX_SALVAGE - 1
	game.food_system.meals = 20
	game.food_system.salvage = 20
	for i in 60:
		game._advance_annex(0.1)


func _test_days() -> void:
	_clean()
	var game := _won_running()
	var won := game.wing_records().get_record(4242)
	_assert_equal([won.ever_won, won.best_day, won.annex], [true, 7, false], "the win is recorded at Day 7")
	var bytes := _bytes()
	_assert_equal(game.keep_running_day(), 8, "keep running starts on day 8")
	game._advance_keep_running(1.0)
	_assert_equal(_bytes(), bytes, "starting and ticking within a day records nothing")
	game._advance_keep_running(DayCycle.SECONDS_PER_DAY)
	_assert_equal(int(game.wing_records().get_record(4242).best_day), 9, "the day 9 rollover raises best_day")
	game._advance_keep_running(DayCycle.SECONDS_PER_DAY)
	var rec := game.wing_records().get_record(4242)
	_assert_equal([rec.ever_won, rec.best_stars, rec.best_day], [true, won.best_stars, 10], "day 10, stars unchanged")
	_dispose(game)
	_clean()


func _test_annex() -> void:
	_clean()
	var game := _won_running()
	var stars: Variant = game.wing_records().get_record(4242).best_stars
	_finish_annex(game)
	_assert_true(game.annex_resident() != null, "the Annex opens")
	var rec := game.wing_records().get_record(4242)
	_assert_true(bool(rec.annex), "the annex badge is set")
	_assert_equal(rec.best_stars, stars, "the Annex adds no stars")
	_dispose(game)
	_clean()


func _test_loss() -> void:
	_clean()
	var game := _won_running()
	game._advance_keep_running(1.0)
	for resident: VaultResident in game.residents:
		resident.needs.health = 0.0
		resident.kill()
	game._finish_loss()
	_assert_true(game.ended and game.outcome == "loss", "the kept-running vault is lost")
	var rec := game.wing_records().get_record(4242)
	_assert_true(bool(rec.ever_won), "the earlier win is kept")
	_assert_equal(int(rec.best_day), 8, "the loss day is the keep-running day, with no rollover")
	_assert_true(game.player_orders.outcome_record.text.begins_with("FURTHEST DAY 8"), "the loss shows the furthest day: %s" % game.player_orders.outcome_record.text)
	_dispose(game)
	_clean()


func _test_fifth_mouth() -> void:
	_clean()
	var game := _won_running(3)
	_assert_equal(game.residents.size(), 5, "five crew on 03")
	_assert_true(game.annex_resident() == null, "Fen (5) is not the Annex resident")
	_assert_true(game.annex_waiting_for_room() == false, "the Annex is not paid yet")
	_finish_annex(game)
	var eko := game.annex_resident()
	_assert_true(eko != null and eko.resident_name == "Eko" and eko.resident_id == 6, "Eko moves in as resident 6")
	_assert_equal(game.residents.size(), 6, "six crew")
	_assert_equal(game.residents[4].resident_name, "Fen", "Fen is still resident 5")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	_assert_true(game._is_snapshot_shape_valid(snapshot), "a six-crew 03 save is valid")
	_assert_true(game.apply_snapshot(snapshot), "and loads")
	_assert_equal(game.residents.size(), 6, "with six crew")
	var base := snapshot.duplicate(true)
	base.erase("sublevel")
	_assert_false(game._is_snapshot_shape_valid(base), "six crew outside 03 stays invalid")
	_dispose(game)
	_clean()


func _test_volunteer_annex() -> void:
	_clean()
	var store := WingRecords.new()
	store.path = _path
	store.record(0x0777, true, 2, 7, 3)
	var save_path := "user://test_records_keep_running_vol_%d.sav" % OS.get_process_id()
	for case: Array in [[7, 5, 6], [3, 6, 7]]:
		var game := _won_running(case[0], "volunteer")
		var label := "%02d VOLUNTEER" % case[0]
		_assert_equal([game.wing_perk, game.residents.size()], ["volunteer", case[1]], label + ": starting crew")
		_assert_equal(game.residents[-1].resident_name, "Gil", label + ": Gil is the last starter")
		_finish_annex(game)
		var eko := game.annex_resident()
		_assert_true(eko != null and eko.resident_name == "Eko" and eko.resident_id == case[2], label + ": Eko moves in under the next free id")
		_assert_equal(game.residents.size(), case[2], label + ": crew with Eko")
		var names := {}
		for resident: VaultResident in game.residents:
			names[resident.resident_id] = resident.resident_name
		_assert_equal(names.size(), case[2], label + ": every resident id is unique")
		_assert_true(game.save_game(false, save_path), label + ": saved to disk")
		_assert_true(game.load_game(save_path), label + ": the save with Eko loads")
		_assert_equal([game.wing_perk, game.residents.size(), game.annex_resident() != null], ["volunteer", case[2], true], label + ": restored with Eko")
		_finish_annex(game)
		_assert_equal(game.residents.size(), case[2], label + ": no second Eko after LOAD")
		_dispose(game)
	for suffix: String in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))
	_clean()
