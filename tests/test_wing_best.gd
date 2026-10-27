extends "res://tests/test_runner.gd"

# Load dynamically so this suite reports an assertion failure on the pre-feature commit.
var _best_script: Script
var _dir := ""


func _run() -> void:
	if ResourceLoader.exists("res://scripts/wing_best.gd"):
		_best_script = load("res://scripts/wing_best.gd")
	_run_case("the best-run store exists", func() -> void:
		_assert_true(_best_script != null, "scripts/wing_best.gd must exist"))
	if _best_script != null:
		_run_case("missing and unreadable stores are empty; round trip is independent", _test_round_trip)
		_run_case("invalid submissions do no I/O", _test_invalid_inputs)
		_run_case("invalid documents load entirely empty", _test_bad_files)
		_run_case("ranking and worse submissions preserve the best", _test_ranking)
		_run_case("atomic failures retain the old best", _test_atomic)
		_run_case("backup recovery survives failed promotion", _test_backup)
		_run_case("only the win outcome is a win", _test_outcomes)
		_run_case("finish, recap, briefing, retry and LOAD integration", _test_game)
		_run_case("win, Continue and Keep Running never rewrite a better run", _test_keep_running)
		_run_case("scripted games cannot use the real best sidecar", _test_isolation)
	print("WING BEST TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(0 if _failure_count == 0 else 1)


func _store() -> Variant:
	_dir = "res://tests/.wing_best_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	var store: Variant = _best_script.new()
	store.path = _dir.path_join("wing_best.json")
	return store


func _run_entry(won := false, day := 5, elapsed := 172.3, names: Array = ["Ada", "Bo"]) -> Dictionary:
	return {"won": won, "day": day, "elapsed": elapsed, "survivors": names}


func _put(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_assert_true(file != null, "fixture file opens")
	if file != null:
		file.store_string(content)
		file.close()


func _bytes(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "<missing>"


func _cleanup() -> void:
	for name: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir.path_join(name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir))


func _test_round_trip() -> void:
	var store: Variant = _store()
	_assert_equal(store.read().wings, {}, "missing file is empty")
	_assert_equal(store.get_best(4242), {}, "missing wing is empty")
	_assert_equal(DirAccess.get_files_at(_dir).size(), 0, "reads do not write")
	var entry := _run_entry()
	_assert_equal(store.submit(4242, 7, entry), {"previous": {}, "current": entry, "new_best": true}, "first run wins")
	var loaded: Variant = _best_script.new()
	loaded.path = store.path
	_assert_equal(loaded.get_best(4242), entry, "round trip preserves the entry")
	var document: Dictionary = JSON.parse_string(_bytes(store.path))
	_assert_variants_equal({"version": 1, "wings": {"07-1092": entry}}, document, "versioned document and wing key")
	_assert_true(store.submit(4242, 6, _run_entry(true)).new_best, "same seed has a separate sublevel")
	_assert_true(store.submit(7, 7, _run_entry(true)).new_best, "another seed has a separate best")
	_assert_equal(store.get_best(4242), entry, "other wings leave original alone")
	var copy: Dictionary = loaded.get_best(4242)
	copy.survivors.append("changed")
	_assert_equal(loaded.get_best(4242), entry, "caller mutations never alter stored data")
	loaded.path = _dir.path_join("missing_directory/wing_best.json")
	_assert_equal(loaded.read().wings, {}, "unreadable location is empty")
	_assert_false(loaded.submit(4242, 7, entry).new_best, "unwritable location does not claim a new best")
	_cleanup()


func _test_invalid_inputs() -> void:
	var store: Variant = _store()
	for args: Array in [[0, 7], [-1, 7], [65536, 7], [1.5, 7], ["4242", 7], [4242, 2], [4242, 8], [4242, 7.5]]:
		_assert_equal(store.submit(args[0], args[1], _run_entry()), {}, "invalid seed/sublevel refused")
	for entry: Variant in _invalid_entries():
		_assert_equal(store.submit(4242, 7, entry), {}, "invalid run refused")
	_assert_equal(DirAccess.get_files_at(_dir).size(), 0, "invalid submissions create no files")
	_cleanup()


func _invalid_entries() -> Array:
	var invalid: Array = [null, [], {}, {"won": false, "day": 1, "elapsed": 0.0}]
	for field: String in ["won", "day", "elapsed", "survivors"]:
		var bad_values: Array
		match field:
			"won": bad_values = [1, "true", null]
			"day": bad_values = [0, 1000, 1.5, "5", true, INF, NAN, null]
			"elapsed": bad_values = [-0.1, INF, NAN, "1", true, null]
			"survivors": bad_values = ["Ada", [1], ["Ada", false], null]
		for value: Variant in bad_values:
			var entry := _run_entry()
			entry[field] = value
			invalid.append(entry)
	var extra := _run_entry()
	extra.extra = true
	invalid.append(extra)
	return invalid


func _test_bad_files() -> void:
	var store: Variant = _store()
	var documents: Array = ["{broken", "null", "[]"]
	for document: Variant in [
		{"version": 2, "wings": {}}, {"version": 0, "wings": {}},
		{"version": "1", "wings": {}}, {"version": true, "wings": {}},
		{"version": 1.5, "wings": {}}, {"version": 1},
		{"version": 1, "wings": []}, {"version": 1, "wings": {}, "extra": 0},
	]:
		documents.append(JSON.stringify(document))
	for key: String in ["07-0000", "02-1092", "08-1092", "7-1092", "07-10a2", "07-10G2", "4242"]:
		documents.append(JSON.stringify({"version": 1, "wings": {key: _run_entry()}}))
	for entry: Variant in _invalid_entries():
		if entry is Dictionary and ((typeof(entry.get("day")) == TYPE_FLOAT and not is_finite(entry.day)) or (typeof(entry.get("elapsed")) == TYPE_FLOAT and not is_finite(entry.elapsed))):
			continue
		documents.append(JSON.stringify({"version": 1, "wings": {"07-1092": _run_entry(), "06-1092": entry}}))
	for content: String in documents:
		_put(store.path, content)
		_assert_equal(store.read().wings, {}, "invalid file is entirely empty")
		_assert_equal(_bytes(store.path), content, "read never modifies invalid data")
	_cleanup()


func _test_ranking() -> void:
	var store: Variant = _store()
	var loss := _run_entry()
	var win := _run_entry(true, 7, 280.0, ["Ada"])
	var cases: Array = [
		[loss, {}, true], [win, loss, true], [loss, win, false],
		[_run_entry(true, 7, 280.0, ["Ada", "Bo"]), win, true],
		[win, _run_entry(true), false],
		[_run_entry(true, 999, 99999.0, ["Ada"]), win, false],
		[_run_entry(false, 6, 1.0), loss, true],
		[_run_entry(false, 4, 999.0), loss, false],
		[_run_entry(false, 5, 173.0), loss, true],
		[_run_entry(false, 5, 170.0), loss, false], [loss, loss, false],
		[_run_entry(false, 5, 172.3, ["more", "names", "here"]), loss, false],
	]
	for values: Array in cases:
		_assert_equal(_best_script.is_better(values[0], values[1]), values[2], "ranking comparison")
	_assert_true(store.submit(4242, 7, loss).new_best, "initial loss saved")
	var before := _bytes(store.path)
	for worse: Dictionary in [loss, _run_entry(false, 4, 999.0), _run_entry(false, 5, 170.0)]:
		_assert_equal(store.submit(4242, 7, worse), {"previous": loss, "current": loss, "new_best": false}, "equal/worse returns existing best")
		_assert_equal(_bytes(store.path), before, "equal/worse leaves file byte-for-byte intact")
	_assert_true(store.submit(4242, 7, win).new_best, "win replaces loss")
	_assert_false(store.submit(4242, 7, _run_entry(false, 999, 99999.0)).new_best, "long loss cannot replace win")
	_assert_equal(store.get_best(4242), win, "win stays best")
	_cleanup()


func _test_atomic() -> void:
	for step: String in ["open", "write", "rotate", "promote"]:
		var store: Variant = _store()
		var old := _run_entry()
		_assert_true(store.submit(4242, 7, old).new_best, "seed prior best")
		var before := _bytes(store.path)
		store.fail_step = step
		_assert_equal(store.submit(4242, 7, _run_entry(true)), {"previous": old, "current": old, "new_best": false}, "%s: failed promotion reports old best" % step)
		_assert_equal(_bytes(store.path), before, "%s: preserves primary bytes" % step)
		_assert_equal(store.get_best(4242), old, "%s: old best still readable" % step)
		_assert_false(FileAccess.file_exists(store.path + ".tmp"), "no temporary file remains")
		_cleanup()


func _test_backup() -> void:
	var store: Variant = _store()
	var old := _run_entry()
	store.submit(4242, 7, old)
	var before := _bytes(store.path)
	DirAccess.rename_absolute(ProjectSettings.globalize_path(store.path), ProjectSettings.globalize_path(store.path + ".bak"))
	_assert_equal(store.get_best(4242), old, "backup alone recovers")
	_put(store.path, "broken primary")
	_assert_equal(store.get_best(4242), old, "corrupt primary recovers backup")
	store.fail_step = "promote"
	_assert_false(store.submit(4242, 7, _run_entry(true)).new_best, "failed recovered write reports failure")
	_assert_equal(_bytes(store.path + ".bak"), before, "backup retained until successful promotion")
	_assert_equal(store.get_best(4242), old, "backup still readable after failed promotion")
	store.fail_step = ""
	_assert_true(store.submit(4242, 7, _run_entry(true)).new_best, "recovered write can promote")
	_assert_false(FileAccess.file_exists(store.path + ".bak"), "backup retired after promotion")
	_assert_true(store.get_best(4242).won, "new best reads")
	_cleanup()


func _test_outcomes() -> void:
	_assert_true(_best_script.run_from("win", 7, 280.0, []).won, "only explicit win is won")
	for outcome: String in ["loss", "death", "cap", "frame_cap", "harness frame cap", "", "WIN"]:
		var run: Dictionary = _best_script.run_from(outcome, 7, 280.0, ["Ada"])
		_assert_equal(run, {"won": false, "day": 7, "elapsed": 280.0, "survivors": ["Ada"]}, "%s stays a non-win" % outcome)


func _game() -> VaultGame:
	var game := MAIN_SCENE.instantiate() as VaultGame
	game.records_path = _dir.path_join("wing_records.json")
	game.set("save_path", _dir.path_join("save.json"))
	game.set("checkpoint_path", _dir.path_join("checkpoint.json"))
	root.add_child(game)
	game.new_game(false, 4242)
	game.begin_shift()
	return game


func _best_label(game: VaultGame) -> Label:
	var label: Variant = game.player_orders.get("outcome_best")
	_assert_true(label is Label, "outcome has a Best label")
	return label as Label


func _test_game() -> void:
	var store: Variant = _store()
	var game := _game()
	game.day_cycle.elapsed_seconds = 172.3
	game.day_cycle.current_day = 5
	var names: Array = []
	for resident: VaultResident in game.residents:
		names.append(resident.resident_name)
	game._finish_loss()
	_assert_equal(game.get("finish_best"), {"previous": {}, "current": _run_entry(false, 5, 172.3, names), "new_best": true}, "loss submits run and alive names")
	var label := _best_label(game)
	if label != null:
		_assert_equal(label.text, "Best: DAY 5 · 12.3s · 4 survived · NEW BEST", "loss recap shows new best")
	var before := _bytes(store.path)
	_assert_true(before != "<missing>", "injected records directory also receives best file")
	_assert_true(game.retry_day_checkpoint(), "Retry restores day checkpoint")
	_assert_equal(game.get("finish_best"), {}, "Retry clears transient best")
	_assert_equal(_bytes(store.path), before, "Retry never writes best")
	game.day_cycle.current_day = 2
	game.day_cycle.elapsed_seconds = 45.0
	game._finish_loss()
	label = _best_label(game)
	if label != null:
		_assert_true(label.text.begins_with("Best:") and not label.text.contains("NEW BEST"), "worse recap shows best without new mark")
	_assert_equal(_bytes(store.path), before, "worse finish leaves best file unchanged")
	_assert_false(bool(game.get("finish_best").new_best), "worse finish is not a new best")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.records_path))
	game.new_game(true, 4242)
	_assert_equal(game.get("finish_best"), {}, "new wing resets best result")
	_assert_true(game.player_orders.briefing_record_text().contains("Best: DAY 5 · 12.3s · 4 survived"), "briefing displays best even without a wing record")
	_assert_true(game.player_orders.briefing_record_label.visible, "briefing best line is visible")
	# LOAD-style outcome rendering reads the sidecar and never submits.
	game.player_orders.show_outcome(false, 4)
	_assert_equal(_bytes(store.path), before, "show_outcome does not write")
	_assert_false(_best_label(game).text.contains("NEW BEST"), "LOAD-style recap has no fresh mark")
	_dispose(game)
	_cleanup()


func _test_keep_running() -> void:
	var store: Variant = _store()
	var game := _game()
	game.day_cycle.deserialize({"elapsed_seconds": 100.0, "current_day": 3, "completed": false})
	game.breach_system.advance(0.0, 100.0)
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.apply_patch_work(100.0)
	game.job_system.rebuild_from_state()
	game.day_cycle.deserialize({"elapsed_seconds": 280.0, "current_day": 7, "completed": true})
	game._finish_win()
	_assert_true(store.get_best(4242).won, "_finish_win submits a win")
	var before := _bytes(store.path)
	_assert_equal(_best_label(game).text, "Best: WIN · 4 survived · NEW BEST", "win recap shows best")
	_assert_true(game.load_game(), "won save loads")
	_assert_equal(game.get("finish_best"), {}, "LOAD clears transient best")
	_assert_equal(_bytes(store.path), before, "LOAD leaves best bytes unchanged")
	_assert_false(JSON.stringify(game.create_snapshot()).contains("best"), "save/checkpoint snapshot carries no best data")
	_assert_equal(_best_label(game).text, "Best: WIN · 4 survived", "LOAD shows plain best")
	_assert_true(game.start_keep_running(), "Keep Running starts")
	game._advance_keep_running(53.5)
	_assert_equal(_bytes(store.path), before, "Keep Running day progress never writes best")
	game.residents[0].kill()
	_assert_equal(game.outcome, "death", "partial death opens recap")
	_assert_true(_best_label(game).visible and _best_label(game).text.begins_with("Best:"), "death recap shows existing best")
	_assert_false(_best_label(game).text.contains("NEW BEST"), "later death does not repeat win's mark")
	_assert_true(game.resume_after_death(), "Continue resumes endless shift")
	_assert_equal(_bytes(store.path), before, "Continue does not write best")
	game._finish_loss()
	_assert_false(bool(game.get("finish_best").new_best), "endless loss cannot replace win")
	_assert_equal(_bytes(store.path), before, "endless loss leaves win unchanged")
	# A distinct wing with no prior win verifies the absolute elapsed clock after day 7.
	game.new_game(false, 7)
	game.keep_running = true
	game.keep_running_seconds = 53.5
	game._finish_loss()
	var endless: Dictionary = store.get_best(7)
	_assert_equal([endless.won, endless.day, endless.elapsed], [false, 9, 333.5], "endless loss uses consistent day and seconds into run")
	_dispose(game)
	_cleanup()


func _test_isolation() -> void:
	var store: Variant = _store()
	var game := _game()
	game.records_path = ""
	game._record_finish(false)
	_assert_equal(game.get("finish_best"), {}, "scripted game without injected records stays off")
	game.records_path = "user://test_wing_best_records_unused.json"
	_assert_false(game.call("best_enabled"), "root-level records injection cannot reach player best")
	game.set("best_path", store.path)
	_assert_true(game.call("best_enabled"), "explicit isolated best path opts in")
	game.new_game(false, 0)
	game._finish_win()
	_assert_equal(game.get("finish_best"), {}, "seed zero never submits")
	_assert_false(FileAccess.file_exists(store.path), "seed zero never writes best")
	_dispose(game)
	_cleanup()
