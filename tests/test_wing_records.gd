extends "res://tests/test_runner.gd"

# Wing-seed slice 4 store: the per-wing sidecar record. Every case uses its own temporary
# user:// directory, never the real user://wing_records.json.

var _dir := ""


func _run() -> void:
	_run_case("seed 0 records nothing and touches no file", _test_seed_zero)
	_run_case("a missing sidecar reads as no records", _test_missing)
	_run_case("records keep the best grade, best day and won flag per wing", _test_maxima)
	_run_case("bad inputs are refused without writing", _test_bad_inputs)
	_run_case("a corrupt sidecar is ignored, kept aside, and replaced on the next record", _test_corrupt)
	_run_case("a corrupt primary with a valid backup recovers the backup", _test_corrupt_with_backup)
	_run_case("an interrupted promotion (backup only) recovers", _test_backup_only)
	_run_case("a future-version sidecar is never overwritten", _test_future_version)
	_run_case("malformed entries make the file corrupt, not half-read", _test_malformed)
	_run_case("a failed write at any step leaves the last record intact", _test_failures)
	_finish()


func _finish() -> void:
	print("")
	if _failure_count == 0:
		print("WING RECORDS TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("WING RECORDS TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _store() -> WingRecords:
	_dir = "user://test_wing_records_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	var store := WingRecords.new()
	store.path = _dir + "/wing_records.json"
	_assert_false(store.path.begins_with(WingRecords.DEFAULT_PATH), "test store is not the real sidecar")
	return store


func _files() -> PackedStringArray:
	return DirAccess.get_files_at(ProjectSettings.globalize_path(_dir))


func _bytes(file_path: String) -> String:
	return FileAccess.get_file_as_string(file_path) if FileAccess.file_exists(file_path) else "<missing>"


func _put(file_path: String, text: String) -> void:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _cleanup() -> void:
	for name in _files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir + "/" + name))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir))


func _test_seed_zero() -> void:
	var store := _store()
	_assert_false(store.record(0, true, 3, 7), "seed 0 is not recorded")
	_assert_equal(_files().size(), 0, "no file is created for seed 0")
	_assert_equal(store.get_record(0), {}, "seed 0 has no record")
	_cleanup()


func _test_missing() -> void:
	var store := _store()
	_assert_equal(int(store.read().status), WingRecords.Status.MISSING, "missing sidecar")
	_assert_equal(store.get_record(4242), {}, "no record yet")
	_assert_equal(_files().size(), 0, "reading writes nothing")
	_cleanup()


func _test_maxima() -> void:
	var store := _store()
	_assert_true(store.record(4242, false, null, 3), "a day-3 loss records")
	_assert_equal(store.get_record(4242), {"ever_won": false, "best_stars": null, "best_day": 3}, "loss only: no win, no grade")
	_assert_true(store.record(4242, false, null, 7), "a day-7 loss records")
	_assert_false(bool(store.get_record(4242).ever_won), "a day-7 loss is still not a win")
	_assert_true(store.record(4242, true, 2, 7), "a 2-star win records")
	_assert_true(store.record(4242, false, null, 2), "a later early loss records")
	_assert_true(store.record(4242, true, 1, 7), "a worse win records")
	_assert_equal(store.get_record(4242), {"ever_won": true, "best_stars": 2, "best_day": 7}, "best grade and day survive worse runs")
	_assert_true(store.record(4242, true, 3, 7), "a 3-star win records")
	_assert_equal(int(store.get_record(4242).best_stars), 3, "three stars kept")
	_assert_true(store.record(1, true, null, 7), "an ungraded win records")
	_assert_equal(store.get_record(1), {"ever_won": true, "best_stars": null, "best_day": 7}, "an ungraded win stays ungraded")
	_assert_equal(int(store.get_record(4242).best_stars), 3, "another wing is untouched")
	_assert_equal(int(store.read().status), WingRecords.Status.VALID, "file is valid")
	_assert_equal(_files(), PackedStringArray(["wing_records.json"]), "no tmp or backup left behind")
	var parsed: Dictionary = JSON.parse_string(_bytes(store.path))
	_assert_equal(int(parsed.version), 1, "versioned document")
	_assert_true((parsed.wings as Dictionary).has("07-1092"), "keyed by wing id")
	_cleanup()


func _test_bad_inputs() -> void:
	var store := _store()
	_assert_false(store.record(4242, false, 2, 4), "a loss cannot carry stars")
	_assert_false(store.record(4242, true, 4, 7), "stars above 3 are refused")
	_assert_false(store.record(4242, true, 0, 7), "zero stars are refused")
	_assert_false(store.record(4242, true, 2.0, 7), "non-integer stars are refused")
	_assert_false(store.record(4242, false, null, 0), "day 0 is refused")
	_assert_false(store.record(4242, false, null, 8), "day 8 is refused")
	_assert_false(store.record(70000, false, null, 3), "out-of-range seed is refused")
	_assert_equal(_files().size(), 0, "nothing was written")
	_cleanup()


func _test_corrupt() -> void:
	var store := _store()
	_put(store.path, "{not json")
	_assert_equal(int(store.read().status), WingRecords.Status.CORRUPT, "corrupt sidecar")
	_assert_equal(store.get_record(4242), {}, "corrupt sidecar shows no record")
	_assert_equal(_bytes(store.path), "{not json", "reading never repairs or deletes")
	_assert_true(store.record(4242, true, 3, 7), "the next record replaces it")
	_assert_equal(store.get_record(4242), {"ever_won": true, "best_stars": 3, "best_day": 7}, "fresh record")
	var kept := ""
	for name in _files():
		if name.begins_with("wing_records.json.corrupt-"):
			kept = name
	_assert_true(kept != "", "the damaged file is kept aside")
	_assert_equal(_bytes(_dir + "/" + kept), "{not json", "with its bytes intact")
	_put(store.path, "garbage again")
	_assert_true(store.record(4242, false, null, 2), "a second corruption is also replaced")
	var quarantined := 0
	for name in _files():
		if name.begins_with("wing_records.json.corrupt-"):
			quarantined += 1
	_assert_equal(quarantined, 2, "each damaged copy gets its own name")
	_cleanup()


func _test_corrupt_with_backup() -> void:
	var store := _store()
	_assert_true(store.record(4242, true, 2, 7), "seed a record")
	var good := _bytes(store.path)
	_put(store.path + ".bak", good)
	_put(store.path, "{broken")
	var read := store.read()
	_assert_equal(int(read.status), WingRecords.Status.RECOVERED, "the valid backup is used")
	_assert_equal(int(store.get_record(4242).best_stars), 2, "recovered record")
	_assert_true(store.record(4242, false, null, 4), "recording over a recovered file works")
	_assert_equal(store.get_record(4242), {"ever_won": true, "best_stars": 2, "best_day": 7}, "recovered data is merged, not lost")
	_assert_false(FileAccess.file_exists(store.path + ".bak"), "the stale backup is retired after promotion")
	_cleanup()


func _test_backup_only() -> void:
	var store := _store()
	_assert_true(store.record(4242, true, 1, 7), "seed a record")
	DirAccess.rename_absolute(ProjectSettings.globalize_path(store.path), ProjectSettings.globalize_path(store.path + ".bak"))
	_assert_equal(int(store.read().status), WingRecords.Status.RECOVERED, "backup alone recovers")
	_assert_equal(int(store.get_record(4242).best_stars), 1, "with its record")
	_cleanup()


func _test_future_version() -> void:
	var store := _store()
	var future := JSON.stringify({"version": 2, "wings": {"07-1092": {"something": "new"}}})
	_put(store.path, future)
	_assert_equal(int(store.read().status), WingRecords.Status.UNSUPPORTED, "future version is unsupported")
	_assert_equal(store.get_record(4242), {}, "and shows no record")
	_assert_false(store.record(4242, true, 3, 7), "and is never overwritten")
	_assert_equal(_bytes(store.path), future, "bytes unchanged")
	_assert_equal(_files().size(), 1, "no side files")
	_cleanup()


func _test_malformed() -> void:
	var store := _store()
	var good := {"ever_won": true, "best_stars": 2, "best_day": 7}
	var cases := [
		{"version": 1},
		{"version": 1, "wings": []},
		{"version": "1", "wings": {}},
		{"version": 0, "wings": {}},
		{"version": 1, "wings": {"07-0000": good}},
		{"version": 1, "wings": {"07-10g2": good}},
		{"version": 1, "wings": {"4242": good}},
		{"version": 1, "wings": {"07-1092": {"ever_won": false, "best_stars": 2, "best_day": 7}}},
		{"version": 1, "wings": {"07-1092": {"ever_won": true, "best_stars": 2.5, "best_day": 7}}},
		{"version": 1, "wings": {"07-1092": {"ever_won": true, "best_stars": 2, "best_day": 8}}},
		{"version": 1, "wings": {"07-1092": {"ever_won": 1, "best_stars": 2, "best_day": 7}}},
		{"version": 1, "wings": {"07-1092": {"ever_won": true, "best_stars": 2, "best_day": 7, "extra": 1}}},
		{"version": 1, "wings": {"07-1092": good, "07-0001": {"ever_won": true}}},
	]
	for index in cases.size():
		_put(store.path, JSON.stringify(cases[index]))
		_assert_equal(int(store.read().status), WingRecords.Status.CORRUPT, "malformed case %d is corrupt" % index)
		_assert_equal(store.get_record(4242), {}, "malformed case %d shows nothing" % index)
	_put(store.path, JSON.stringify({"version": 1, "wings": {"07-1092": good}}))
	_assert_equal(int(store.read().status), WingRecords.Status.VALID, "a well-formed file is valid")
	_cleanup()


func _test_failures() -> void:
	for step: String in ["open", "write", "rotate", "promote"]:
		var store := _store()
		_assert_true(store.record(4242, true, 2, 7), "%s: seed a record" % step)
		var before := _bytes(store.path)
		store.fail_step = step
		_assert_false(store.record(4242, true, 3, 7), "%s: a failing write reports failure" % step)
		store.fail_step = ""
		_assert_equal(_bytes(store.path), before, "%s: the primary keeps the last record byte for byte" % step)
		_assert_equal(int(store.get_record(4242).best_stars), 2, "%s: the last record still reads" % step)
		_assert_false(FileAccess.file_exists(store.path + ".tmp"), "%s: no temporary file is left" % step)
		_cleanup()
