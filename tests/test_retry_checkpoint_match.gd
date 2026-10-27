extends "res://tests/test_death_recap.gd"

# Reuse the death-recap suite's injected save slots, real idle replay, UI
# queries and death signals. New APIs stay dynamic so the unfixed control runs.
func _run() -> void:
	_case("cross-wing", _test_cross_wing)
	_case("same-wing", _test_same_wing)
	_case("seed-only", _test_identity_mismatch.bind(6262, 5))
	_case("sublevel-only", _test_identity_mismatch.bind(4242, 6))
	_case("future-shift", _test_future_shift)
	_case("finite-to-endless", _test_mode_mismatch.bind(false))
	_case("endless-to-finite", _test_mode_mismatch.bind(true))
	_case("future-endless", _test_future_endless)
	_case("absent-sublevel", _test_absent_sublevel)
	_case("wipe-focus", _test_wipe_focus)
	for path: String in _paths:
		_remove_test_save(path)
	print("RETRY CHECKPOINT MATCH TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(0 if _failure_count == 0 else 1)


func _idle_until(game: VaultGame, stop_seconds := INF) -> void:
	for frame in range(_frame + 1, FRAME_CAP + 1):
		_frame = frame
		_idle(game)
		_advance_frame(game)
		if game.outcome != "" or game.day_cycle.elapsed_seconds >= stop_seconds:
			return
	_assert_true(false, "the real idle replay reaches its stop before the frame cap")


func _test_cross_wing() -> void:
	var game := _game(5, false, true)
	_idle_until(game, 185.1)
	_assert_true(game.outcome == "" and game.residents[0].alive, "wing A is still live at the ordinary player save")
	_assert_equal(game.residents[0].resident_name, "Ari", "the real idle fixture follows Ari")
	_assert_true(game.save_game(false, _player_path), "wing A seed 4242/sublevel 5 is saved through the player path")
	var saved_a := game.create_snapshot()
	game.new_game(false, 8080, 7)
	game.begin_shift()
	var wing_b := game.save_load.load_snapshot(_checkpoint_path)
	_assert_true(bool(wing_b.ok), "NEW WING B begin_shift writes the shared day-one checkpoint")
	if bool(wing_b.ok):
		_assert_equal(int(wing_b.snapshot.wing_seed), 8080, "the shared checkpoint belongs to B")
		_assert_approximately(float(wing_b.snapshot.day.elapsed_seconds), 0.0, 0.0001, "B's checkpoint is day one")
	var checkpoint_bytes := _checkpoint_files()
	_assert_true(game.load_game(_player_path), "ordinary Load restores A after B replaced the checkpoint")
	_assert_equal(_checkpoint_files(), checkpoint_bytes, "Load never overwrites the foreign checkpoint")
	_assert_equal(game.wing_seed, 4242, "Load restores A's seed")
	_assert_equal(game.sublevel, 5, "Load restores A's sublevel")
	_assert_approximately(game.day_cycle.elapsed_seconds, float(saved_a.day.elapsed_seconds), 0.0001, "Load restores A's saved time")
	game.user_paused = false
	game.set_speed(2)
	_idle_until(game)
	_assert_equal(game.outcome, "death", "Ari dies naturally after reloading A")
	_assert_equal(str(_recap(game).get("name", "")), "Ari", "the real death recap belongs to Ari")
	_assert_approximately(game.day_cycle.elapsed_seconds, 188.2, 0.11, "the unchanged real replay dies at the expected day-five time")
	_assert_rejected_checkpoint(game, "wing")
	_assert_equal(_checkpoint_files(), checkpoint_bytes, "death, peeks and refused Retry preserve B's exact checkpoint bytes")
	_dispose(game)


func _test_same_wing() -> void:
	var game := _game(5, false, true)
	_idle_until(game)
	_assert_equal(game.outcome, "death", "the same-wing control reaches its natural death")
	var checkpoint := game.save_load.load_snapshot(_checkpoint_path)
	_assert_true(bool(checkpoint.ok), "the ordinary replay retains its day-five checkpoint")
	_assert_enabled_checkpoint(game)
	if bool(checkpoint.ok):
		_assert_approximately(float(checkpoint.snapshot.day.elapsed_seconds), 160.1, 0.11, "the real day-start hook checkpointed day five")
		var files_before := _checkpoint_files()
		var retry := _button(game.player_orders, "outcome_retry_button")
		if retry != null:
			retry.pressed.emit()
		_assert_json_equal(game, game.create_snapshot(), checkpoint.snapshot, "Retry restores the exact same-wing day checkpoint")
		_assert_equal(game.wing_seed, 4242, "same-wing Retry retains A's seed")
		_assert_equal(game.sublevel, 5, "same-wing Retry retains A's sublevel")
		_assert_true(game.outcome == "" and game.user_paused and not game.player_orders.outcome_panel.visible, "successful Retry clears the recap and pauses restored play")
		_assert_equal(game.get_alive_count(), game.residents.size(), "same-wing Retry undoes Ari's death")
		_assert_equal(_checkpoint_files(), files_before, "successful Retry only reads the checkpoint")
	_dispose(game)


func _test_identity_mismatch(other_seed: int, other_sublevel: int) -> void:
	var game := _game(5)
	game.begin_shift()
	game.day_cycle.advance(10.0)
	var current := game.create_snapshot()
	# Build an actual valid other wing rather than altering its seed/sublevel
	# metadata: breach timing and the sublevel rules must agree with the file.
	game.new_game(false, other_seed, other_sublevel)
	game.begin_shift()
	_assert_checkpoint_valid(game)
	_assert_true(game.apply_snapshot(current), "the live wing is restored while retaining the other wing's checkpoint")
	_force_starvation(game, game.residents[0])
	_assert_rejected_checkpoint(game, "wing")
	_dispose(game)


func _test_future_shift() -> void:
	var game := _game(5)
	game.begin_shift()
	game.day_cycle.advance(10.0)
	var current := game.create_snapshot()
	game.day_cycle.advance(10.0)
	_assert_true(bool(game.call("_save_day_checkpoint")), "a valid later checkpoint is written in the same wing")
	_assert_checkpoint_valid(game)
	_assert_true(game.apply_snapshot(current), "the current shift is earlier than its shared checkpoint")
	_force_starvation(game, game.residents[0])
	_assert_rejected_checkpoint(game, "time")
	_dispose(game)


func _start_endless(game: VaultGame) -> void:
	game.begin_shift()
	_prepare_breathable_sealed_recap(game, DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE - VaultGame.SIMULATION_TICK)
	game.food_system.meals = 1000
	game.job_system.rebuild_from_state()
	game.step_simulation(VaultGame.SIMULATION_TICK * 2.0)
	_assert_true(game.outcome == "win" and game.ended, "the mode fixture earns a real sealed-wing win")
	_assert_true(game.start_keep_running(), "the real win enters keep-running and writes its checkpoint")


func _test_mode_mismatch(checkpoint_is_endless: bool) -> void:
	var game := _game(5)
	_start_endless(game)
	var endless := game.create_snapshot()
	var finite := endless.duplicate(true)
	finite.erase("keep_running")
	finite.erase("annex")
	# Both states deliberately have the same completed day clock and identity.
	# Only the mode differs, so clock ordering cannot hide a missing mode guard.
	var checkpoint := endless if checkpoint_is_endless else finite
	var current := finite if checkpoint_is_endless else endless
	_assert_true(bool(game.save_load.save_snapshot(checkpoint, _checkpoint_path).ok), "a checkpoint in the other keep-running state is written")
	_assert_checkpoint_valid(game)
	_assert_true(game.apply_snapshot(current), "the live wing has the opposite keep-running state")
	_force_starvation(game, game.residents[0])
	_assert_rejected_checkpoint(game, "time")
	_dispose(game)


func _test_future_endless() -> void:
	var game := _game(5)
	_start_endless(game)
	game.call("_advance_keep_running", 5.0)
	var current := game.create_snapshot()
	game.call("_advance_keep_running", DayCycle.SECONDS_PER_DAY)
	_assert_checkpoint_valid(game)
	var checkpoint := game.save_load.load_snapshot(_checkpoint_path)
	if bool(checkpoint.ok):
		_assert_equal(float(checkpoint.snapshot.day.elapsed_seconds), float(current.day.elapsed_seconds), "ordinary day time is frozen in both endless snapshots")
		_assert_true(float(checkpoint.snapshot.keep_running.seconds) > float(current.keep_running.seconds), "the checkpoint's endless clock is later than the live wing")
	_assert_true(game.apply_snapshot(current), "the live endless clock is restored to the earlier time")
	_force_starvation(game, game.residents[0])
	_assert_rejected_checkpoint(game, "time")
	_dispose(game)


func _test_absent_sublevel() -> void:
	var game := _game(7)
	game.begin_shift()
	var checkpoint := game.save_load.load_snapshot(_checkpoint_path)
	_assert_true(bool(checkpoint.ok) and not checkpoint.get("snapshot", {}).has("sublevel"), "base sublevel 07 uses the existing absent-key save format")
	# Equality is allowed; peeking at the day-one checkpoint must not advance time.
	_assert_true(bool(game.call("can_retry_day_checkpoint")), "absent sublevel equals current 07, including equal checkpoint time")
	_force_starvation(game, game.residents[0])
	_assert_enabled_checkpoint(game)
	_assert_true(bool(game.call("retry_day_checkpoint")), "Retry accepts absent sublevel as 07")
	_assert_equal(game.sublevel, 7, "Retry restores base sublevel 07")
	_assert_approximately(game.day_cycle.elapsed_seconds, 0.0, 0.0001, "Retry permits an equal-time checkpoint")
	game.new_game(false, 4242, 5)
	# Do not begin this shift: keep the genuine 07 checkpoint in the shared path.
	_force_starvation(game, game.residents[0])
	_assert_rejected_checkpoint(game, "wing")
	_dispose(game)


func _test_wipe_focus() -> void:
	var game := _game(5)
	game.begin_shift()
	var current := game.create_snapshot()
	game.new_game(false, 6262, 5)
	game.begin_shift()
	_assert_true(game.apply_snapshot(current), "wipe fixture retains a foreign checkpoint")
	for resident: VaultResident in game.residents:
		_force_starvation(game, resident)
	_assert_equal(game.outcome, "loss", "the final real death opens the loss recap")
	_assert_rejected_checkpoint(game, "wing")
	var row := game.player_orders.get("_outcome_legacy_row") as HBoxContainer
	var first := row.get_child(0) as Button if row != null else null
	_assert_true(first != null and first.is_visible_in_tree() and not first.disabled and first.has_focus(), "a wipe with disabled Retry focuses the next enabled legacy action")
	_dispose(game)


func _assert_checkpoint_valid(game: VaultGame) -> void:
	var checkpoint := game.save_load.load_snapshot(_checkpoint_path)
	_assert_true(bool(checkpoint.ok), "mismatch fixture is a readable checkpoint")
	if bool(checkpoint.ok):
		_assert_true(bool(game.call("_is_snapshot_shape_valid", checkpoint.snapshot)), "mismatch fixture passes real snapshot validation")


func _retry_status(game: VaultGame) -> Dictionary:
	_assert_true(game.has_method("day_checkpoint_retry_status"), "one read-only helper exposes Retry eligibility and a short reason")
	if game.has_method("day_checkpoint_retry_status"):
		var status: Variant = game.call("day_checkpoint_retry_status")
		_assert_true(status is Dictionary, "Retry status is a dictionary")
		if status is Dictionary:
			return status
	return {}


func _assert_enabled_checkpoint(game: VaultGame) -> void:
	var before := game.create_snapshot()
	var transient := _transient_state(game)
	var files_before := _all_slot_files()
	var retry := _button(game.player_orders, "outcome_retry_button")
	_assert_true(retry != null and retry.is_visible_in_tree() and not retry.disabled, "matching checkpoint enables the visible Retry button")
	_assert_true(retry != null and retry.has_focus(), "matching Retry has default recap focus")
	_assert_true(bool(game.call("can_retry_day_checkpoint")), "matching checkpoint is available to callers")
	var status := _retry_status(game)
	_assert_true(bool(status.get("ok", false)) and str(status.get("reason", "missing")).is_empty(), "matching checkpoint returns ok with no disabled reason")
	var reason := game.player_orders.get("outcome_retry_reason") as Label if "outcome_retry_reason" in game.player_orders else null
	_assert_true(reason != null and not reason.is_visible_in_tree(), "matching Retry hides the disabled reason label")
	_assert_true(retry != null and retry.tooltip_text.is_empty(), "matching Retry clears any disabled tooltip")
	_assert_json_equal(game, game.create_snapshot(), before, "matching checkpoint peeks do not mutate the wing")
	_assert_equal(_transient_state(game), transient, "matching checkpoint peeks leave transient state unchanged")
	_assert_equal(_all_slot_files(), files_before, "matching checkpoint peeks leave every slot file unchanged")


func _assert_rejected_checkpoint(game: VaultGame, reason_kind: String) -> void:
	var before := game.create_snapshot()
	var transient := _transient_state(game)
	var files_before := _all_slot_files()
	var retry := _button(game.player_orders, "outcome_retry_button")
	_assert_true(retry != null and retry.is_visible_in_tree() and retry.disabled, "foreign/future checkpoint leaves Retry visible and disabled")
	_assert_false(bool(game.call("can_retry_day_checkpoint")), "mismatched checkpoint is unavailable to callers")
	var status := _retry_status(game)
	_assert_false(bool(status.get("ok", true)), "mismatched checkpoint status refuses Retry")
	var text := str(status.get("reason", ""))
	_assert_true(not text.is_empty() and text.length() <= 60, "disabled Retry provides a short reason")
	if reason_kind == "wing":
		_assert_equal(text, "No checkpoint for this wing", "seed and sublevel mismatch explain the foreign wing")
	else:
		_assert_true(not text.is_empty() and text != "No checkpoint for this wing", "mode and future-time mismatch use a distinct reason")
	var reason := game.player_orders.get("outcome_retry_reason") as Label if "outcome_retry_reason" in game.player_orders else null
	_assert_true(reason != null and reason.is_visible_in_tree() and not reason.text.is_empty() and reason.text == text, "the disabled reason is visibly rendered on the recap")
	_assert_true(retry != null and not retry.tooltip_text.is_empty() and retry.tooltip_text == text, "the Retry tooltip also explains why it is disabled")
	var resume := _button(game.player_orders, "outcome_resume_button")
	if resume != null and resume.is_visible_in_tree() and not resume.disabled:
		_assert_true(resume.has_focus() and not retry.has_focus(), "disabled Retry defaults focus to enabled Continue")
	_assert_json_equal(game, game.create_snapshot(), before, "read-only checkpoint peeks leave the complete wing unchanged")
	_assert_equal(_transient_state(game), transient, "read-only checkpoint peeks leave transient state unchanged")
	_assert_equal(_all_slot_files(), files_before, "read-only checkpoint peeks leave all slot bytes unchanged")
	# Bypass the button explicitly: M4 must fail even with correct UI eligibility.
	_assert_false(bool(game.call("retry_day_checkpoint")), "direct Retry refuses the mismatched checkpoint")
	_assert_equal(game.wing_seed, int(before.wing_seed), "refused Retry preserves the live seed")
	_assert_equal(game.sublevel, int(before.get("sublevel", {}).get("level", 7)), "refused Retry preserves the live sublevel")
	_assert_equal(game.day_cycle.elapsed_seconds, float(before.day.elapsed_seconds), "refused Retry preserves elapsed shift time")
	_assert_equal(game.keep_running, before.has("keep_running"), "refused Retry preserves the keep-running state")
	if before.has("keep_running"):
		_assert_equal(game.keep_running_seconds, float(before.keep_running.seconds), "refused Retry preserves elapsed keep-running time")
	_assert_json_equal(game, game.create_snapshot(), before, "refused Retry preserves the complete wing snapshot")
	_assert_equal(_transient_state(game), transient, "refused Retry preserves pause, status, recap and focus")
	_assert_equal(_all_slot_files(), files_before, "refused Retry preserves every player/checkpoint/autosave/records file byte")


func _transient_state(game: VaultGame) -> Dictionary:
	return {
		"paused": game.user_paused,
		"tutorial": game.tutorial_open,
		"status": game.status_message,
		"status_left": game.status_message_left,
		"panel": game.player_orders.outcome_panel.visible,
		"focus": game.get_viewport().gui_get_focus_owner(),
		"accumulator": game.get("_simulation_accumulator"),
	}


func _checkpoint_files() -> Dictionary:
	return _slot_files([_checkpoint_path])


func _all_slot_files() -> Dictionary:
	return _slot_files([_player_path, _checkpoint_path, _autosave_path, _records_path])


func _slot_files(paths: Array) -> Dictionary:
	var files := {}
	for path: String in paths:
		for suffix: String in ["", ".bak", ".tmp"]:
			var full_path := path + suffix
			var exists := FileAccess.file_exists(full_path)
			files[full_path] = [exists, FileAccess.get_file_as_bytes(full_path) if exists else PackedByteArray()]
	return files
