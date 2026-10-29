extends "res://tests/test_runner.gd"

# All best-feature APIs are optional here: the pre-feature commit must fail
# assertions, never fail to parse. UI assertions inspect actual visible labels.
const BEST_SCRIPT_PATH := "res://scripts/wing_best.gd"
const SEED := 4242
const LEVEL := 5
const WING_KEY := "05-1092"
const TICK_CAP := 10000

var _best_script: Script
var _slot_dirs: Array[String] = []
var _slots: Dictionary = {}


func _run() -> void:
	if ResourceLoader.exists(BEST_SCRIPT_PATH):
		_best_script = ResourceLoader.load(BEST_SCRIPT_PATH) as Script
	_run_case("a: opening briefing with and without a stored best", _test_entry)
	_run_case("b: a death finish beats the stored best on the visible recap", _test_death_finish)
	_run_case("c: Retry's equal finish preserves bytes and has no NEW BEST", _test_retry)
	_run_case("d: a frame-cap END is never stored as a win", _test_cap)
	_run_case("e: corrupt best is empty and leaves wing records intact", _test_corrupt)
	_run_case("f: Retry's identical inexact-clock loss stays a tie", _test_inexact_retry)
	_run_case("g: direct Keep Running deaths never repeat the win unlock", _test_direct_keep_running_deaths)
	_run_case("h: a true wing loss still merges fresh unlock details into Best", _test_loss_unlock_details)
	_cleanup_slots()
	print("WING BEST BEHAVIOR TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(0 if _failure_count == 0 else 1)


func _make_slots() -> void:
	var directory := "user://test_wing_best_behavior_%d_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec(), _case_count]
	_assert_equal(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)), OK, "isolated user directory opens")
	_slot_dirs.append(directory)
	_slots = {
		"records_path": directory.path_join("wing_records.json"),
		"save_path": directory.path_join("save.json"),
		"checkpoint_path": directory.path_join("checkpoint.json"),
		"best_path": directory.path_join("wing_best.json"),
	}


func _game() -> VaultGame:
	var game := MAIN_SCENE.instantiate() as VaultGame
	for property: String in _slots:
		if property in game:
			game.set(property, _slots[property])
		else:
			_assert_true(false, "game exposes injectable %s" % property)
	root.add_child(game)
	game.set_process(false)
	return game


func _put(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_assert_true(file != null, "fixture opens at an isolated path")
	if file != null:
		file.store_string(content)
		file.close()


func _seed_best(day := 1, elapsed := 0.0) -> void:
	_put(_slots.best_path, JSON.stringify({"version": 1, "wings": {
		WING_KEY: {"won": false, "day": day, "elapsed": elapsed, "survivors": ["Ari", "Bo", "Cyra", "Dax"]},
	}}))


func _visible_labels(node: Node) -> Array[String]:
	var texts: Array[String] = []
	if node is Label and (node as Label).is_visible_in_tree():
		texts.append((node as Label).text)
	elif node is RichTextLabel and (node as RichTextLabel).is_visible_in_tree():
		texts.append((node as RichTextLabel).get_parsed_text())
	for child: Node in node.get_children():
		texts.append_array(_visible_labels(child))
	return texts


func _screen_text(panel: Variant) -> String:
	_assert_true(panel is Control, "screen has a real Control panel")
	if not panel is Control:
		return ""
	_assert_true(panel.is_visible_in_tree(), "screen panel is visible in the tree")
	var text := "\n".join(_visible_labels(panel))
	_assert_false(text.is_empty(), "visible panel contains rendered label text")
	print("[VISIBLE %s] %s" % [_current_case, text.replace("\n", " / ")])
	return text


func _assert_merged_best(game: VaultGame, text: String, expected: String) -> void:
	var labels := _visible_labels(game.player_orders.outcome_panel)
	_assert_true(labels.has(expected), "recap renders the complete merged Best label: %s" % expected)
	_assert_equal(text.count("Best:"), 1, "recap renders exactly one Best line")
	_assert_false(text.contains("FURTHEST DAY"), "no separate FURTHEST DAY label is visible with Best")
	_assert_false(game.player_orders.outcome_record.is_visible_in_tree(), "the separate record label is hidden")


func _finished_best_text(game: VaultGame) -> String:
	var clock := DayCycle.new()
	clock.elapsed_seconds = game.day_cycle.elapsed_seconds
	var time := clock.get_clock_text().get_slice("·", 1).strip_edges()
	clock.free()
	return "Best: DAY %d · %s · 0 survived" % [game.day_cycle.current_day, time]


func _test_entry() -> void:
	_make_slots()
	_assert_true(_best_script != null, "best-run store script exists")
	var game := _game()
	game.new_game(true, SEED, LEVEL)
	var text := _screen_text(game.player_orders.get("briefing_panel"))
	_assert_false(text.contains("Best:"), "a missing store shows no Best line on entry")
	_seed_best(4, 125.5)
	game.new_game(true, SEED, LEVEL)
	text = _screen_text(game.player_orders.get("briefing_panel"))
	_assert_true(text.contains("Best: DAY 4 · 03:18 · 4 survived"), "entry shows the stored non-win best in game-clock time")
	_assert_true(text.contains("4 survived"), "entry includes the stored survivor count")
	_assert_false(text.contains("NEW BEST"), "entry does not claim a newly finished run")
	_dispose(game)


func _advance_idle_to_outcome(game: VaultGame) -> void:
	for tick in TICK_CAP:
		if game.outcome != "" or game.ended:
			break
		if game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged:
			game.acknowledge_breach_warning(true)
		if game.is_simulation_paused():
			_assert_true(false, "idle run has no unexplained pause before death")
			break
		game.step_simulation(VaultGame.SIMULATION_TICK)


func _idle_until_death(game: VaultGame) -> void:
	# A truly idle wipe: the Cook's auto food step is vetoed (as if each Cook blueprint was cancelled).
	for kind in VaultGame.COOK_AUTO_CHAIN:
		game.cook_auto_vetoed[kind] = true
	game.begin_shift()
	_advance_idle_to_outcome(game)
	_assert_equal(game.outcome, "death", "untouched level-05 supplies reach a real death before the tick cap")
	_assert_true(game.get_alive_count() > 0, "first death leaves survivors")


func _finish_deaths(game: VaultGame) -> void:
	# A recoverable first death is not a finished wing. Use the normal Continue
	# API after each interruption and let the original idle supplies run out.
	# No needs, health, resident death flags, outcome or clock are injected.
	for interruption in game.residents.size():
		if game.ended:
			break
		var resumed := false
		if game.has_method("resume_after_death"):
			resumed = bool(game.call("resume_after_death"))
		_assert_true(resumed, "normal Continue resumes the surviving idle residents")
		if not resumed:
			break
		_advance_idle_to_outcome(game)
	game.player_orders.refresh()
	_assert_equal(game.get_alive_count(), 0, "natural idle run has no living residents")
	_assert_true(game.ended and game.outcome == "loss", "the actual final died signal finishes the wing")


func _test_death_finish() -> void:
	_make_slots()
	_seed_best()
	var before := FileAccess.get_file_as_bytes(_slots.best_path)
	var game := _game()
	game.new_game(false, SEED, LEVEL)
	_idle_until_death(game)
	_finish_deaths(game)
	var text := _screen_text(game.player_orders.get("outcome_panel"))
	_assert_merged_best(game, text, _finished_best_text(game) + " · NEW BEST")
	_assert_true(text.contains("NEW BEST"), "better death finish visibly announces NEW BEST")
	_assert_true(FileAccess.get_file_as_bytes(_slots.best_path) != before, "better death finish replaces the stored run")
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(_slots.best_path))
	if document is Dictionary:
		var entry: Dictionary = document.get("wings", {}).get(WING_KEY, {})
		_assert_equal(entry.get("won"), false, "death best is stored as a non-win")
		_assert_equal(int(entry.get("day", 0)), game.day_cycle.current_day, "stored best is the actual finish day")
		_assert_equal(entry.get("survivors"), [], "stored best reflects the natural final death")
	_dispose(game)


func _test_retry() -> void:
	_make_slots()
	var game := _game()
	game.new_game(false, SEED, LEVEL)
	_idle_until_death(game)
	_finish_deaths(game)
	var first_text := _screen_text(game.player_orders.get("outcome_panel"))
	_assert_merged_best(game, first_text, _finished_best_text(game) + " · NEW BEST")
	_assert_true(first_text.contains("Best:") and first_text.contains("NEW BEST"), "first finish establishes the retry's best")
	_assert_true(FileAccess.file_exists(_slots.best_path), "a best exists before Retry")
	var before := FileAccess.get_file_as_bytes(_slots.best_path)
	_assert_true(FileAccess.file_exists(_slots.checkpoint_path), "real day-start hook wrote an isolated checkpoint")
	var retried := false
	if game.has_method("retry_day_checkpoint"):
		retried = bool(game.call("retry_day_checkpoint"))
	_assert_true(retried, "Retry restores the actual day checkpoint")
	if retried:
		_assert_equal(FileAccess.get_file_as_bytes(_slots.best_path), before, "Retry itself leaves every best byte intact")
		_assert_false((game.player_orders.get("outcome_panel") as Control).is_visible_in_tree(), "Retry hides the old recap")
		# The latest day checkpoint may already contain earlier natural deaths.
		game.begin_shift()
		_advance_idle_to_outcome(game)
		_finish_deaths(game)
		var text := _screen_text(game.player_orders.get("outcome_panel"))
		_assert_merged_best(game, text, _finished_best_text(game))
		_assert_false(text.contains("NEW BEST"), "equal retry finish has no NEW BEST mark")
		_assert_equal(FileAccess.get_file_as_bytes(_slots.best_path), before, "equal retry finish leaves wing_best.json byte-for-byte unchanged")
	_dispose(game)


func _inexact_clock_loss(game: VaultGame) -> void:
	# Induce the same loss through real resident death signals on both attempts.
	# No simulation tick or clock assignment may hide the checkpoint's precision.
	for resident: VaultResident in game.residents:
		resident.kill()
	game.player_orders.refresh()
	_assert_equal(game.get_alive_count(), 0, "induced loss has no living residents")
	_assert_true(game.ended and game.outcome == "loss", "final resident death runs the real finish path")


func _test_inexact_retry() -> void:
	_make_slots()
	var game := _game()
	game.new_game(false, SEED, LEVEL)
	game.begin_shift()
	_assert_false(game.is_simulation_paused(), "precision fixture starts a live shift")
	for tick in 3:
		game.step_simulation(0.1)
	var elapsed := game.day_cycle.elapsed_seconds
	_assert_true(elapsed == 0.30000000000000004, "three real 0.1 ticks produce the inexact clock")
	_assert_true(elapsed != 0.3, "the fixture distinguishes the clock from rounded JSON")
	_assert_true(bool(game.call("_save_day_checkpoint")), "real checkpoint writer saves the inexact clock")
	var checkpoint := game.save_load.load_snapshot(_slots.checkpoint_path)
	_assert_true(bool(checkpoint.ok), "inexact-clock checkpoint loads through SaveLoad")
	if bool(checkpoint.ok):
		_assert_true(float(checkpoint.snapshot.day.elapsed_seconds) == elapsed, "checkpoint elapsed round-trips exactly")
	_inexact_clock_loss(game)
	var first: Dictionary = game.get("finish_best") if "finish_best" in game else {}
	_assert_equal(first.get("new_best"), true, "first inexact-clock loss establishes the best")
	_assert_true(float(first.get("current", {}).get("elapsed", -1.0)) == elapsed, "first finish submits the exact simulation clock")
	_assert_merged_best(game, _screen_text(game.player_orders.get("outcome_panel")), "Best: DAY 1 · 00:10 · 0 survived · NEW BEST")
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(_slots.best_path))
	_assert_true(document is Dictionary, "first inexact-clock best has readable JSON")
	if document is Dictionary:
		_assert_true(float(document.get("wings", {}).get(WING_KEY, {}).get("elapsed", -1.0)) == elapsed, "stored best elapsed round-trips exactly")
	var before := FileAccess.get_file_as_bytes(_slots.best_path)
	var retried := bool(game.call("retry_day_checkpoint"))
	_assert_true(retried, "real Retry restores the inexact-clock checkpoint")
	if retried:
		_assert_true(game.day_cycle.elapsed_seconds == elapsed, "Retry restores the exact inexact clock")
		_assert_equal(game.get_alive_count(), game.residents.size(), "Retry restores every resident before the identical loss")
		_assert_equal(game.get("finish_best"), {}, "Retry clears the first finish result")
		_assert_equal(FileAccess.get_file_as_bytes(_slots.best_path), before, "inexact-clock Retry leaves best bytes intact")
		_assert_false((game.player_orders.get("outcome_panel") as Control).is_visible_in_tree(), "inexact-clock Retry hides the first recap")
		game.begin_shift()
		_inexact_clock_loss(game)
		_assert_true(game.day_cycle.elapsed_seconds == elapsed, "identical loss finishes at exactly the same clock")
		var second: Dictionary = game.get("finish_best") if "finish_best" in game else {}
		_assert_equal(second.get("new_best"), false, "identical inexact-clock Retry loss is not a new best")
		_assert_true(float(second.get("current", {}).get("elapsed", -1.0)) == elapsed, "Retry finish reads the exact stored best elapsed")
		var text := _screen_text(game.player_orders.get("outcome_panel"))
		_assert_merged_best(game, text, "Best: DAY 1 · 00:10 · 0 survived")
		_assert_false(text.contains("NEW BEST"), "identical inexact-clock Retry recap has no NEW BEST")
		_assert_equal(FileAccess.get_file_as_bytes(_slots.best_path), before, "identical inexact-clock loss preserves every best byte")
		game.new_game(true, SEED, LEVEL)
		var entry_text := _screen_text(game.player_orders.get("briefing_panel"))
		_assert_true(entry_text.contains("Best: DAY 1 · 00:10 · 0 survived"), "entry displays the inexact-clock stored best in game-clock time")
		_assert_false(entry_text.contains("NEW BEST"), "entry after the identical Retry loss has no NEW BEST")
	_dispose(game)


func _test_cap() -> void:
	_make_slots()
	var game := _game()
	game.new_game(false, SEED, LEVEL)
	game.begin_shift()
	# A harness frame cap is an observation limit, not the game's win outcome.
	# Leave a living run paused after 30 frames, just as test_death_recap does.
	for frame in range(1, 121):
		if frame == 31:
			game.user_paused = true
		if not game.is_simulation_paused():
			game.step_simulation(VaultGame.SIMULATION_TICK)
	_assert_equal(game.outcome, "", "frame-cap END leaves the game's outcome empty")
	_assert_false(game.ended, "a frame cap does not finish a living wing")
	_assert_false(FileAccess.file_exists(_slots.best_path), "observing cap END never invents a stored win")
	# Also test a consumer which explicitly submits its cap END through the
	# store API. The actual outcome string, not survival past a cap, sets won.
	if _best_script != null and _best_script.has_method("run_from"):
		var store: Variant = _best_script.new()
		if store.has_method("submit"):
			store.set("path", _slots.best_path)
			for end_reason: String in ["cap", "frame_cap"]:
				var run: Variant = _best_script.call("run_from", end_reason, 8, 280.0, ["Ari"])
				store.call("submit", SEED, LEVEL, run)
			var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(_slots.best_path))
			_assert_true(document is Dictionary, "cap submission has a readable best document")
			if document is Dictionary:
				_assert_equal(document.get("wings", {}).get(WING_KEY, {}).get("won"), false, "cap END is stored as won=false")
	else:
		_assert_true(false, "best store can convert cap outcomes without inventing wins")
	game.new_game(true, SEED, LEVEL)
	var text := _screen_text(game.player_orders.get("briefing_panel"))
	_assert_true(text.contains("Best: DAY 8 · 00:00 · 1 survived"), "entry renders the cap's stored best as a day and game-clock result")
	_assert_false(text.contains("Best: WIN"), "cap END is never presented as a win")
	_dispose(game)


func _test_corrupt() -> void:
	_make_slots()
	var records := WingRecords.new()
	records.path = _slots.records_path
	_assert_true(records.record(SEED, true, 2, 7, LEVEL), "independent wing record fixture is valid")
	var before := FileAccess.get_file_as_bytes(_slots.records_path)
	var loaded_before: Dictionary = records.read().wings.duplicate(true)
	_seed_best(4, 125.5)
	var game := _game()
	game.new_game(true, SEED, LEVEL)
	_assert_true(_screen_text(game.player_orders.get("briefing_panel")).contains("Best: DAY 4 · 03:18 · 4 survived"), "valid best fixture is visible in game-clock time before corrupting it")
	var corrupt := "{broken wing_best.json"
	_put(_slots.best_path, corrupt)
	game.new_game(true, SEED, LEVEL)
	var text := _screen_text(game.player_orders.get("briefing_panel"))
	_assert_false(text.contains("Best:"), "corrupt best shows no Best line or stale cached text")
	_assert_true(text.contains("RECORD 05-1092"), "independent wing record remains visible")
	_assert_true(text.contains("FURTHEST DAY 7"), "independent record's day remains visible")
	if game.has_method("wing_best"):
		var store: Variant = game.call("wing_best")
		if store != null and store.has_method("get_best"):
			_assert_equal(store.call("get_best", SEED, LEVEL), {}, "corrupt best loads as an empty entry")
	else:
		_assert_true(false, "game has the optional best store integration")
	_assert_equal(FileAccess.get_file_as_string(_slots.best_path), corrupt, "opening corrupt best is read-only")
	_assert_equal(FileAccess.get_file_as_bytes(_slots.records_path), before, "wing_records.json bytes remain intact")
	_assert_equal(game.wing_records().read().wings, loaded_before, "game-loaded records remain intact")
	_assert_equal(records.read().wings, loaded_before, "freshly read independent records remain intact")
	_dispose(game)


func _win_unlock() -> VaultGame:
	_make_slots()
	var game := _game()
	game.new_game(false, SEED, WingRecords.BASE_SUBLEVEL)
	game.begin_shift()
	game.day_cycle.deserialize({"elapsed_seconds": 100.0, "current_day": 3, "completed": false})
	game.breach_system.advance(0.0, 100.0)
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.apply_patch_work(100.0)
	game.job_system.rebuild_from_state()
	game.day_cycle.deserialize({"elapsed_seconds": 279.5, "current_day": 7, "completed": false})
	game.oxygen_system.oxygen = 100.0
	game.step_simulation(1.0)
	_assert_true(game.ended and game.outcome == "win", "sealed breathable wing reaches the real day-seven win")
	_assert_equal(game.finish_record.get("unlocked"), 6, "fresh win really unlocks sublevel 06")
	_assert_true(_screen_text(game.player_orders.outcome_panel).contains("SUBLEVEL 06 UNLOCKED · EARLY HATCH"), "win visibly announces the fresh unlock")
	return game


func _press_keep_running(game: VaultGame) -> void:
	var button := game.player_orders.keep_running_button
	_assert_true(button.is_visible_in_tree() and not button.disabled, "win offers an enabled Keep Running button")
	var record := game.finish_record.duplicate(true)
	button.pressed.emit()
	_assert_true(game.keep_running and not game.ended and game.outcome == "", "Keep Running button resumes the won wing directly without LOAD")
	_assert_false(game.player_orders.outcome_panel.is_visible_in_tree(), "Keep Running button hides the win recap")
	_assert_equal(game.finish_record, record, "Keep Running preserves the fresh finish record including its unlock")


func _test_direct_keep_running_deaths() -> void:
	var game := _win_unlock()
	_press_keep_running(game)
	var record := game.finish_record.duplicate(true)
	var best_before := FileAccess.get_file_as_bytes(_slots.best_path)
	for index in 2:
		game.residents[index].kill()
		_assert_equal(game.outcome, "death", "resident %d opens a recoverable death recap" % (index + 1))
		_assert_false(game.ended, "resident death leaves the wing resumable")
		_assert_equal(game.player_orders.outcome_title.text, "RESIDENT LOST", "recap visibly says RESIDENT LOST")
		var text := _screen_text(game.player_orders.outcome_panel)
		var best := game.player_orders.outcome_best
		_assert_true(best.is_visible_in_tree(), "recoverable recap renders Best")
		_assert_equal(best.text, "Best: WIN · 4 survived", "each direct Keep Running death shows plain Best")
		_assert_false(best.text.contains("UNLOCKED"), "recoverable Best never replays the fresh unlock")
		_assert_false(best.text.contains("\n"), "recoverable Best remains a single line")
		_assert_false(text.contains("UNLOCKED"), "no visible recap label repeats the unlock")
		_assert_false(game.player_orders.outcome_record.is_visible_in_tree(), "recoverable recap hides the separate record label")
		_assert_equal(game.finish_record, record, "death recap retains the fresh win record unchanged")
		_assert_equal(FileAccess.get_file_as_bytes(_slots.best_path), best_before, "recoverable death leaves stored Best bytes intact")
		if index == 0:
			var resume := game.player_orders.outcome_resume_button
			_assert_true(resume.is_visible_in_tree() and not resume.disabled, "first death offers an enabled Continue button")
			resume.pressed.emit()
			_assert_true(game.outcome == "" and not game.user_paused, "Continue button resumes before the second death")
			_assert_false(game.player_orders.outcome_panel.is_visible_in_tree(), "Continue button hides the first death recap")
	_dispose(game)


func _test_loss_unlock_details() -> void:
	var game := _win_unlock()
	var unlocked := int(game.finish_record.unlocked)
	_press_keep_running(game)
	_inexact_clock_loss(game)
	# A real final death replaces finish_record. Supply the just-earned unlock
	# as a presentation fixture, like test_wing_best's merged-details control.
	game.finish_record["unlocked"] = unlocked
	game.player_orders.show_outcome(false, game.get_alive_count())
	_assert_equal(game.player_orders.outcome_title.text, "WING LOST", "true finish visibly says WING LOST")
	_assert_false(game.player_orders.outcome_resume_button.is_visible_in_tree(), "true wing loss cannot offer Continue")
	var text := _screen_text(game.player_orders.outcome_panel)
	_assert_merged_best(game, text, "Best: WIN · 4 survived\nSUBLEVEL 06 UNLOCKED · EARLY HATCH")
	_assert_true(game.player_orders.outcome_best.is_visible_in_tree(), "true loss renders the merged Best label")
	_assert_true(game.player_orders.outcome_best.text.contains("SUBLEVEL 06 UNLOCKED · EARLY HATCH"), "true finish retains the unlock suffix in Best")
	_dispose(game)


func _cleanup_slots() -> void:
	for directory: String in _slot_dirs:
		for filename: String in DirAccess.get_files_at(directory):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join(filename)))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
