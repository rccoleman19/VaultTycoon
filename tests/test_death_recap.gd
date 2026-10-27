extends "res://tests/test_runner.gd"

# Plain 30-fps replays of next-urgency-engineer/v4/playtest_driver.gd. No Next
# action is followed: engaged/idle only perform the original scheduled actions.
const FRAME_SECONDS := 1.0 / 30.0
const FRAME_CAP := 9000

var _paths: Array[String] = []
var _frame := 0
var _breach_seen_frame := -1
var _player_path := ""
var _checkpoint_path := ""
var _records_path := ""
var _autosave_path := ""
var _frame_accumulator := 0.0
var _ui_refresh_frame := 0


func _run() -> void:
	_case("a03", _test_plain.bind(3, true, true))
	_case("a05", _test_plain.bind(5, false, false))
	_case("b", _test_retry_exact_checkpoint)
	_case("c", _test_player_slot_isolation)
	_case("d", _test_cap_and_resume_are_not_wins)
	_case("e", _test_last_actionable_tip)
	_case("f", _test_loss_and_death_save_load)
	_case("g", _test_keep_running_day_checkpoints)
	for path: String in _paths:
		_remove_test_save(path)
	print("DEATH RECAP TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(0 if _failure_count == 0 else 1)


func _case(label: String, callback: Callable) -> void:
	var selected := OS.get_environment("DR_CASE")
	if selected != "" and selected != label:
		return
	var failures_before := _failure_count
	var assertions_before := _assertion_count
	var started := Time.get_ticks_msec()
	_run_case(label, callback)
	print("[CASE RESULT] %s: %d assertions, %d failures, %.2fs" % [label, _assertion_count - assertions_before, _failure_count - failures_before, float(Time.get_ticks_msec() - started) / 1000.0])


func _path(label: String) -> String:
	var path := "user://test_death_recap_%d_%s_%s.json" % [OS.get_process_id(), _current_case, label]
	_remove_test_save(path)
	_paths.append(path)
	return path


func _game(sublevel := 3, relay := false, tutorial := false) -> VaultGame:
	_player_path = _path("save")
	_checkpoint_path = _path("checkpoint")
	_records_path = _path("records")
	_autosave_path = _path("autosave")
	if relay:
		var store := WingRecords.new()
		store.path = _records_path
		_assert_true(store.record(0x0B01, true, 3, 9, 7, true), "earned record unlocks RELAY LUMEN")
	var game := MAIN_SCENE.instantiate() as VaultGame
	game.records_path = _records_path
	if "save_path" in game:
		game.set("save_path", _autosave_path)
	if "checkpoint_path" in game:
		game.set("checkpoint_path", _checkpoint_path)
	root.add_child(game)
	game.set_process(false)
	# The base control lacks injectable autosave paths. Disconnect its old day
	# autosave only, so running the control cannot write the DEFAULT player slot.
	# New code keeps the real day-start hook and writes to the injected autosave.
	if not "save_path" in game:
		var day_hook := Callable(game, "_on_day_started")
		if game.day_cycle.day_started.is_connected(day_hook):
			game.day_cycle.day_started.disconnect(day_hook)
	if relay:
		game.equipped_perk = VaultGame.PERK_RELAY_LUMEN
	game.new_game(tutorial, 4242, sublevel)
	_frame = 0
	_breach_seen_frame = -1
	_frame_accumulator = 0.0
	_ui_refresh_frame = 0
	return game


func _test_plain(sublevel: int, engaged: bool, relay: bool) -> void:
	var game := _game(sublevel, relay, true)
	var silent_pause := false
	var outcome_frame := -1
	for frame in range(1, FRAME_CAP + 1):
		_frame = frame
		if engaged:
			_engaged(game)
		else:
			_idle(game)
		_advance_frame(game)
		if game.user_paused and game.outcome == "" and "has died" in game.status_message:
			silent_pause = true
		if game.outcome != "":
			outcome_frame = frame
			break
		# Fail quickly on the old silent-death state rather than waiting through
		# 9000 identical frozen frames. The required real outcome assertion fails.
		if _any_dead(game) and game.user_paused:
			break
	_assert_true(game.outcome in ["death", "loss"], "plain driver ends with a real death outcome before the cap")
	_assert_true(outcome_frame > 0 and outcome_frame < FRAME_CAP, "death interrupts the plain replay before frame 9000")
	_assert_false(silent_pause, "a death never silently pauses with outcome empty")
	_assert_true(game.is_simulation_paused() and game.user_paused, "the death recap pauses the simulation")
	_assert_recap(game)
	_assert_equal(_end_reason(game, outcome_frame, FRAME_CAP), "death", "plain driver's end reason reports death")
	print("[REPLAY] %s frame=%d sim=%.1f outcome=%s survivors=%d" % [_current_case, _frame, game.day_cycle.elapsed_seconds, game.outcome, game.get_alive_count()])
	print("[RECAP] %s" % game.player_orders.outcome_text.text.replace("\n", " / "))
	_dispose(game)


func _assert_recap(game: VaultGame) -> void:
	var orders := game.player_orders
	_assert_true(orders.outcome_panel.visible, "death recap panel is visible")
	var recap := _recap(game)
	_assert_true(not recap.is_empty(), "death records resident, cause, simulation time and last tip")
	var dead := game.get_resident_by_id(int(recap.get("resident_id", -1)))
	if dead == null:
		dead = _first_dead(game)
	var body: String = orders.outcome_text.text
	_assert_true(dead != null and dead.resident_name in body, "recap names the resident who died")
	var cause := str(recap.get("cause", ""))
	_assert_true(not cause.is_empty() and cause.to_lower() in body.to_lower(), "recap displays the recorded cause")
	var clock := str(recap.get("time", ""))
	_assert_true("DAY " in clock and ":" in clock and clock in body, "recap displays the HUD-style day and clock")
	var tip := str(recap.get("tip", ""))
	_assert_true((tip.begins_with("Next: ") and tip in body) or ("no tip" in body.to_lower() and "saved" in body.to_lower()), "recap shows one recorded Next tip or plainly says no tip could save them")
	_assert_false("nothing lands in time" in tip, "too_late is never recorded as an actionable tip")
	var resume := _button(orders, "outcome_resume_button")
	var can_resume := game.get_alive_count() > 0 and game.outcome == "death"
	_assert_true(resume != null, "recap has a Resume button")
	if resume != null:
		_assert_equal(resume.visible and not resume.disabled, can_resume, "Resume is available iff this death leaves survivors")
		_assert_equal(resume.visible, can_resume, "loss hides Resume")
	var retry := _button(orders, "outcome_retry_button")
	_assert_true(retry != null, "recap has a Retry from day checkpoint button")
	if retry != null:
		_assert_true(retry.visible and not retry.disabled, "an existing day checkpoint enables Retry")


func _test_retry_exact_checkpoint() -> void:
	var game := _game()
	game.begin_shift()
	var day_one := game.create_snapshot()
	var day_one_file := game.save_load.load_snapshot(_checkpoint_path)
	_assert_true(bool(day_one_file.ok), "begin_shift writes a day-one checkpoint")
	if bool(day_one_file.ok):
		_assert_json_equal(game, day_one, day_one_file.snapshot, "day-one checkpoint matches the shift's initial state")
	# Real signal boundary: capture immediately after the day-start hook returns.
	game.day_cycle.advance(DayCycle.SECONDS_PER_DAY)
	var day_start := game.create_snapshot()
	var loaded := game.save_load.load_snapshot(_checkpoint_path)
	_assert_true(bool(loaded.ok), "the day-start signal replaces the separate checkpoint slot")
	if bool(loaded.ok):
		_assert_json_equal(game, day_start, loaded.snapshot, "checkpoint slot is exactly the day-start snapshot")
	_force_starvation(game, game.residents[0])
	_assert_equal(game.outcome, "death", "one death offers a retry rather than silently freezing")
	_assert_true(game.has_method("retry_day_checkpoint"), "Retry has an explicit checkpoint restoration path")
	if game.has_method("retry_day_checkpoint") and bool(loaded.ok):
		_assert_true(bool(game.call("retry_day_checkpoint")), "Retry loads the checkpoint through SaveLoad")
		_assert_json_equal(game, game.create_snapshot(), loaded.snapshot, "Retry snapshot JSON equals the checkpoint slot JSON")
		_assert_json_equal(game, game.create_snapshot(), day_start, "Retry snapshot JSON equals the captured day-start JSON")
		_assert_equal(game.get_alive_count(), game.residents.size(), "Retry undoes the resident death")
		_assert_equal(game.outcome, "", "Retry clears the death outcome")
		_assert_false(game.player_orders.outcome_panel.visible, "Retry hides the recap")
		_assert_true(game.user_paused, "Retry leaves the restored checkpoint paused, like Load")
		_remove_test_save(_checkpoint_path)
		_force_starvation(game, game.residents[0])
		var retry := _button(game.player_orders, "outcome_retry_button")
		_assert_true(retry != null and (retry.disabled or not retry.visible), "without a checkpoint Retry is disabled or hidden")
	_dispose(game)


func _test_player_slot_isolation() -> void:
	var game := _game()
	# The protected player slot is an injected sentinel. Existing day-start
	# autosaves go to a DIFFERENT injected slot; those intended writes are out
	# of scope. No test writes to SaveLoad.DEFAULT_PATH.
	var sentinel := "player save sentinel\nunchanged exact bytes\n"
	var file := FileAccess.open(_player_path, FileAccess.WRITE)
	file.store_string(sentinel)
	file.close()
	var before := FileAccess.get_file_as_bytes(_player_path)
	var before_time := FileAccess.get_modified_time(_player_path)
	game.begin_shift()
	game.step_simulation(DayCycle.SECONDS_PER_DAY)
	game.step_simulation(DayCycle.SECONDS_PER_DAY)
	_assert_equal(FileAccess.get_file_as_bytes(_player_path), before, "day checkpoints leave the sentinel player's bytes untouched")
	_assert_true(FileAccess.file_exists(_checkpoint_path), "day starts wrote a real independent checkpoint slot")
	# From now on even the configured player slot is the sentinel: death/retry
	# must use checkpoint_path and must never save over this player slot.
	if "save_path" in game:
		game.set("save_path", _player_path)
	_force_starvation(game, game.residents[0])
	_assert_true(game.has_method("retry_day_checkpoint"), "Retry exists independently of player Load")
	if game.has_method("retry_day_checkpoint"):
		_assert_true(bool(game.call("retry_day_checkpoint")), "Retry succeeds from the independent checkpoint")
	_assert_equal(FileAccess.get_file_as_bytes(_player_path), before, "death and Retry preserve the player's exact bytes")
	_assert_equal(FileAccess.get_modified_time(_player_path), before_time, "death and Retry preserve the player's modification time")
	for suffix: String in [".tmp", ".bak"]:
		_assert_false(FileAccess.file_exists(_player_path + suffix), "checkpointing leaves no player-slot %s file" % suffix)
	_dispose(game)


func _test_cap_and_resume_are_not_wins() -> void:
	var game := _game()
	game.begin_shift()
	# A player can leave a living shift paused for the entire observation
	# window. First simulate 30 frames, then deliberately pause: even 9000
	# observed frames prove no win. No needs, clock or survival rules are changed.
	var cap := FRAME_CAP
	for frame in range(1, cap + 1):
		if frame == 31:
			game.user_paused = true
		_advance_frame(game)
	_assert_equal(game.outcome, "", "a living shift at the observation cap has no outcome")
	_assert_equal(_end_reason(game, -1, cap), "cap", "alive frame cap reports cap, never win")
	_assert_false(game.outcome == "win", "reaching a frame cap never creates a win")
	# A separate replay dies at its 31st simulation frame, well before 9000.
	game.new_game(false, 4242, 3)
	game.begin_shift()
	_frame_accumulator = 0.0
	_ui_refresh_frame = 0
	for frame in 30:
		_advance_frame(game)
	_force_starvation(game, game.residents[0])
	_assert_equal(game.outcome, "death", "a death interrupts the living run before frame 9000")
	_assert_equal(_end_reason(game, 31, FRAME_CAP), "death", "the same driver's helper reports a death at the next simulation frame before cap")
	_assert_false(game.ended, "a death with survivors leaves the wing resumable")
	_assert_true(game.has_method("resume_after_death"), "the death recap exposes Resume")
	var resume := _button(game.player_orders, "outcome_resume_button")
	if game.has_method("resume_after_death") and resume != null:
		resume.pressed.emit()
		_assert_equal(game.outcome, "", "Resume clears the death outcome")
		_assert_false(game.user_paused or game.player_orders.outcome_panel.visible, "Resume unpauses and hides the recap")
		for frame in 60:
			_advance_frame(game)
		_assert_true(game.day_cycle.elapsed_seconds > 1.0, "survivors actually continue simulating")
		_assert_false(game.outcome == "win", "Resume and continued play do not invent a win")
		_assert_false(bool(game.wing_records().get_record(4242, game.sublevel).get("ever_won", false)), "death never records a win")
		# Let the real condition fire: day seven completes, hatch sealed, O2
		# breathable, and surviving crew healthy. Death must not block that win.
		for resident: VaultResident in game.residents:
			if resident.alive:
				resident.needs.food = 100.0
				resident.needs.rest = 100.0
				resident.needs.mood = 100.0
				resident.needs.health = 100.0
		game.oxygen_system.oxygen = 100.0
		game.breach_system.advance(0.0, game.breach_system.warning_at)
		game.breach_system.patch_delivered = BreachSystem.PATCH_COST
		game.breach_system.apply_patch_work(100.0)
		_assert_true(game.breach_system.is_sealed(), "the real-win fixture has sealed the seeded hatch")
		game.player_orders.show_breach_warning(false)
		game.user_paused = false
		game.day_cycle.deserialize({"elapsed_seconds": DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE - VaultGame.SIMULATION_TICK, "current_day": 7, "completed": false})
		game.step_simulation(VaultGame.SIMULATION_TICK * 2.0)
		_assert_true(game.ended and game.outcome == "win", "a later real day-seven win remains possible after Resume")
		_assert_equal(_end_reason(game, 100, FRAME_CAP), "win", "driver reports win only for the real win before cap")
		_assert_equal(_end_reason(game, FRAME_CAP, FRAME_CAP), "death", "even outcome win at the cap is not classified as a win")
	_dispose(game)


func _test_last_actionable_tip() -> void:
	var game := _game()
	game.begin_shift()
	# An available kitchen makes the fixture exercise the existing rescue
	# deadline branch; absent kitchens always recommend building one first.
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(21, 17))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(25, 16))
	game.power_grid.recalculate(game.buildings)
	_assert_true(kitchen.powered, "the rescue-deadline fixture has a powered kitchen")
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
	var target: VaultResident = game.residents[0]
	target.needs.food = 0.0
	target.drafted = true
	game.food_system.meals = 0
	game.food_system.raw_food = FoodSystem.COOK_INPUT
	var live_step: Dictionary = game.player_orders._primary_next_step()
	# Exercise the sampler before any UI refresh. Rendering and refresh cadence
	# cannot be prerequisites for retaining the tip shown by live Next logic.
	game.step_simulation(VaultGame.SIMULATION_TICK)
	_assert_true(game.player_orders.has_method("death_recap_for"), "headless sampling can retrieve a resident's saved live Next tip")
	if game.player_orders.has_method("death_recap_for"):
		var sampled: Dictionary = game.player_orders.call("death_recap_for", target)
		_assert_equal(str(sampled.get("tip", "")), str(live_step.get("text", "")), "simulation sampling retains the exact actionable tip without UI refresh")
	game.player_orders.refresh()
	var next: String = game.player_orders.objective_label.text
	_assert_true(next.begins_with("Next: ") and target.resident_name in next and "undraft" in next, "live Next names the drafted starving resident and a real rescue action")
	_assert_true(game.player_orders.has_method("record_survival_tip"), "headless simulation has a live Next sampling method")
	if game.player_orders.has_method("record_survival_tip"):
		game.player_orders.call("record_survival_tip")
	# The rescue deadline now passes. The old actionable tip must survive the
	# too_late message rather than being replaced by a tip that cannot land.
	target.drafted = false
	target.needs.health = 0.2
	game.food_system.meals = 0
	game.food_system.raw_food = 0
	game.food_system.salvage = 0
	game.player_orders.refresh()
	var too_late: Dictionary = game.player_orders._resident_urgency_step()
	_assert_true(bool(too_late.get("too_late", false)), "fixture reaches the existing too_late urgency branch")
	if game.player_orders.has_method("record_survival_tip"):
		game.player_orders.call("record_survival_tip")
	_force_starvation(game, target)
	_assert_equal(str(_recap(game).get("tip", "")), next, "recap preserves the last actionable exact Next label for the dead resident")
	_assert_true(next in game.player_orders.outcome_text.text, "recap displays that exact recorded live Next string")
	_dispose(game)


func _test_loss_and_death_save_load() -> void:
	var game := _game()
	game.begin_shift()
	var legacy := game.create_snapshot()
	_force_starvation(game, game.residents[0])
	_assert_equal(game.outcome, "death", "a saved partial loss has the explicit death outcome")
	_assert_equal(str(_recap(game).get("tip", "")), "", "a resident killed before any live warning has no invented tip")
	_assert_true("No tip could have saved them." in game.player_orders.outcome_text.text, "recap plainly states when no actionable tip ever existed")
	var snapshot := game.create_snapshot()
	_assert_true(game.save_game(false, _player_path), "a death snapshot uses the existing atomic SaveLoad path")
	game.new_game(false, 4242, 3)
	_assert_true(game.load_game(_player_path), "a saved death snapshot validates and loads")
	_assert_equal(game.outcome, "death", "loaded death remains resumable")
	_assert_true(game.player_orders.outcome_panel.visible, "Load reopens the death recap")
	_assert_json_equal(game, game.create_snapshot(), snapshot, "loaded death snapshot preserves its canonical serialized state")
	# Finish the actual wipe; the shared recap remains and Resume disappears.
	for resident: VaultResident in game.residents:
		if resident.alive:
			_force_starvation(game, resident)
	_assert_true(game.ended and game.outcome == "loss", "the final death still uses the real loss path")
	_assert_recap(game)
	_assert_equal(game.player_orders.outcome_title.text, "WING LOST", "a wipe keeps the loss title")
	# No death keys are emitted for this ordinary live snapshot. Loading it is
	# the same path an old save takes and must restore its serialized state.
	var legacy_path := _path("legacy")
	_assert_true(bool(game.save_load.save_snapshot(legacy, legacy_path).ok), "legacy-shaped live snapshot saves through SaveLoad")
	_assert_true(game.load_game(legacy_path), "a save without death keys still loads")
	_assert_json_equal(game, game.create_snapshot(), legacy, "old save without death keys loads unchanged")
	_dispose(game)


func _test_keep_running_day_checkpoints() -> void:
	var game := _game()
	# Old code's KEEP RUNNING writes only the default player save. The missing
	# injectable checkpoint is an assertion failure; stop before that old write.
	_assert_true("checkpoint_path" in game and "save_path" in game, "keep-running days have an independent injectable checkpoint slot")
	if not "checkpoint_path" in game or not "save_path" in game:
		_dispose(game)
		return
	game.begin_shift()
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
	game.food_system.meals = 1000
	game.oxygen_system.oxygen = 100.0
	game.breach_system.advance(0.0, game.breach_system.warning_at)
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.apply_patch_work(100.0)
	game.job_system.rebuild_from_state()
	game.day_cycle.deserialize({"elapsed_seconds": DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE - VaultGame.SIMULATION_TICK, "current_day": 7, "completed": false})
	game.step_simulation(VaultGame.SIMULATION_TICK * 2.0)
	_assert_true(game.ended and game.outcome == "win", "the keep-running fixture wins through the real survival condition")
	_assert_true(game.start_keep_running(), "a real win starts keep-running day eight")
	var day_eight := game.create_snapshot()
	var slot := game.save_load.load_snapshot(_checkpoint_path)
	_assert_true(bool(slot.ok), "keep-running starts with a day-eight checkpoint")
	if bool(slot.ok):
		_assert_json_equal(game, day_eight, slot.snapshot, "day-eight checkpoint matches the start of keep-running")
	# Advance the actual keep-running clock hook, as the existing records tests
	# do. Physical resident state stays healthy; a new day still checkpoints it.
	game._advance_keep_running(DayCycle.SECONDS_PER_DAY)
	_assert_equal(game.keep_running_day(), 9, "keep-running reaches the next real day")
	var day_nine := game.create_snapshot()
	slot = game.save_load.load_snapshot(_checkpoint_path)
	_assert_true(bool(slot.ok), "day nine replaces the keep-running checkpoint")
	if bool(slot.ok):
		_assert_json_equal(game, day_nine, slot.snapshot, "day-nine checkpoint matches that day's initial state")
	_force_starvation(game, game.residents[0])
	_assert_equal(game.outcome, "death", "keep-running death remains resumable with survivors")
	var clock := str(_recap(game).get("time", ""))
	_assert_true("DAY 9" in clock and ":" in clock and not "/7" in clock, "keep-running recap shows its actual day and clock")
	_assert_true(game.has_method("retry_day_checkpoint"), "keep-running recap can Retry its current day")
	if game.has_method("retry_day_checkpoint"):
		_assert_true(bool(game.call("retry_day_checkpoint")), "keep-running Retry loads the day-nine checkpoint")
		_assert_json_equal(game, game.create_snapshot(), day_nine, "keep-running Retry restores the exact day-nine snapshot JSON")
		_assert_true(game.keep_running and game.keep_running_day() == 9, "Retry preserves keep-running on day nine")
		_assert_equal(game.get_alive_count(), game.residents.size(), "day-nine Retry undoes the death")
		_assert_true(game.outcome == "" and not game.player_orders.outcome_panel.visible, "day-nine Retry clears the outcome and hides the recap")
	_dispose(game)


# Canonical JSON: keys sorted, every number normalized to a float (JSON loads ints as floats), so
# the comparison is about state, not about int-vs-float lexemes.
func _canonical_json(value: Variant) -> String:
	return JSON.stringify(_normalize_numbers(value), "", true, true)


func _normalize_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = _normalize_numbers(value[key])
		return out
	if value is Array:
		var items := []
		for item: Variant in value:
			items.append(_normalize_numbers(item))
		return items
	if typeof(value) == TYPE_INT:
		return float(value)
	return value


func _assert_json_equal(_game_value: VaultGame, actual: Dictionary, expected: Dictionary, message: String) -> void:
	var actual_json := _canonical_json(actual)
	var expected_json := _canonical_json(expected)
	var detail := ""
	if actual_json != expected_json:
		var offset := 0
		while offset < mini(actual_json.length(), expected_json.length()) and actual_json[offset] == expected_json[offset]:
			offset += 1
		detail = " (%s; JSON byte %d: expected %s; actual %s)" % [_first_variant_difference(expected, actual, "$"), offset, expected_json.substr(maxi(0, offset - 35), 100), actual_json.substr(maxi(0, offset - 35), 100)]
	_assert_true(actual_json == expected_json, message + detail)


func _recap(game: VaultGame) -> Dictionary:
	if "death_recap" in game:
		var value: Variant = game.get("death_recap")
		if value is Dictionary:
			return value
	return {}


func _button(orders: PlayerOrders, property: String) -> Button:
	return orders.get(property) as Button if property in orders else null


func _force_starvation(game: VaultGame, resident: VaultResident) -> void:
	resident.needs.food = 0.0
	resident.needs.rest = 100.0
	resident.needs.mood = 100.0
	resident.needs.health = 0.2
	resident.advance_needs(VaultGame.SIMULATION_TICK / DayCycle.SECONDS_PER_DAY, true, false)
	game.player_orders.refresh()


func _first_dead(game: VaultGame) -> VaultResident:
	for resident: VaultResident in game.residents:
		if not resident.alive:
			return resident
	return null


func _any_dead(game: VaultGame) -> bool:
	return _first_dead(game) != null


func _end_reason(game: VaultGame, ended_frame: int, total: int) -> String:
	# Exact logic from the supplied plain driver's _end_reason helper.
	if game.outcome == "win" and ended_frame > 0 and ended_frame < total:
		return "win"
	if game.outcome == "loss" or _any_dead(game):
		return "death"
	return "cap"


func _advance_frame(game: VaultGame) -> void:
	# Same 30-fps accumulator and fixed ticks as VaultGame._process and the
	# existing next-urgency-rank replay. Skip camera/3D synchronization, whose
	# renderer work cannot affect these synchronous headless simulations.
	game.status_message_left = maxf(0.0, game.status_message_left - FRAME_SECONDS)
	if not game.is_simulation_paused():
		_frame_accumulator += FRAME_SECONDS * float(game.simulation_speed)
		while _frame_accumulator >= VaultGame.SIMULATION_TICK:
			game.step_simulation(VaultGame.SIMULATION_TICK)
			_frame_accumulator -= VaultGame.SIMULATION_TICK
			if game.is_simulation_paused():
				_frame_accumulator = 0.0
				break
	# The plain player never follows Next. Throttle only HUD work to once per
	# real second, retaining all gameplay ticks/actions and independent live
	# tip sampling. Outcomes refresh immediately so their recap is inspectable.
	_ui_refresh_frame += 1
	if _ui_refresh_frame % 30 == 0 or game.outcome != "":
		game.player_orders.refresh()


func _idle(game: VaultGame) -> void:
	if _frame == 25:
		game.begin_shift()
		game.set_speed(2)
	_ack(game, 2)


func _ack(game: VaultGame, speed: int) -> void:
	if game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged:
		if _breach_seen_frame < 0:
			_breach_seen_frame = _frame
		elif _frame == _breach_seen_frame + 75:
			if game.player_orders.breach_resume_button != null:
				game.player_orders.breach_resume_button.pressed.emit()
			game.set_speed(speed)


func _digs(game: VaultGame, cells: Array) -> void:
	game.set_tool("dig")
	for cell: Vector2i in cells:
		game.issue_order(cell)
	game.set_tool("select")


func _engaged(game: VaultGame) -> void:
	if _frame == 25:
		game.begin_shift()
		game.set_speed(2)
		for cell: Vector2i in [Vector2i(24, 11), Vector2i(25, 11), Vector2i(26, 11), Vector2i(27, 13)]:
			game.map_grid.paint_stockpile(cell)
	if _frame == 35:
		game.place_blueprint(VaultBuilding.Kind.LAMP, Vector2i(26, 13))
		game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(20, 13))
		_digs(game, [Vector2i(22, 10), Vector2i(23, 10), Vector2i(24, 10), Vector2i(25, 10), Vector2i(26, 10), Vector2i(27, 10)])
	if _frame == 90:
		game.select_resident(1)
	if _frame == 200:
		game.set_speed(3)
		game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(25, 16))
		_digs(game, [Vector2i(25, 9), Vector2i(26, 9), Vector2i(27, 9), Vector2i(26, 8), Vector2i(27, 8), Vector2i(28, 8)])
	if _frame == 380:
		game.place_blueprint(VaultBuilding.Kind.KITCHEN, Vector2i(21, 17))
		_digs(game, [Vector2i(29, 12), Vector2i(29, 13), Vector2i(29, 14), Vector2i(29, 15)])
		game.select_resident(2)
	if _frame == 520:
		game.place_blueprint(VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 17))
		_digs(game, [Vector2i(30, 12), Vector2i(30, 13), Vector2i(30, 14), Vector2i(30, 15)])
		game.select_resident(3)
	if _frame == 1000:
		game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(20, 15))
		game.select_resident(4)
	if _frame == 1400:
		game.place_blueprint(VaultBuilding.Kind.AIR_RECYCLER, Vector2i(19, 16))
	_ack(game, 3 if _frame > 200 else 2)
