extends "res://tests/test_runner.gd"

# Plain 30-fps replays of next-urgency-engineer/v4/playtest_driver.gd. No Next
# action is followed: engaged/idle only perform the original scheduled actions.
const FRAME_SECONDS := 1.0 / 30.0
const FRAME_CAP := 9000

# Observe the real selector/sampler, independently of what the recap retains.
# Tick observations include the final pre-damage selection even when the
# half-second retention cadence skips that particular simulation tick.
class SamplingOrders extends PlayerOrders:
	var first_actionable := {}
	var sampled_steps: Array[Dictionary] = []
	var tick_steps: Array[Dictionary] = []

	func clear_survival_tips() -> void:
		first_actionable.clear()
		sampled_steps.clear()
		tick_steps.clear()
		super.clear_survival_tips()

	func record_survival_tip(delta_seconds := 0.5) -> void:
		if game.outcome == "" and not game.ended:
			var step := keep_running_next_step() if game.keep_running else _primary_next_step()
			tick_steps.append(_observation(step))
		super.record_survival_tip(delta_seconds)

	func _remember_survival_tip(step: Dictionary) -> void:
		if game.outcome == "" and not game.ended:
			var observation := _observation(step)
			sampled_steps.append(observation)
			var resident := game.get_resident_by_id(int(step.get("resident_id", -1)))
			var text := str(step.get("text", ""))
			if resident != null and resident.alive and not bool(step.get("too_late", false)) and not bool(step.get("recovering", false)) and text.begins_with("Next: ") and resident.resident_name in text:
				if not first_actionable.has(resident.resident_id):
					first_actionable[resident.resident_id] = observation
		super._remember_survival_tip(step)

	func _observation(step: Dictionary) -> Dictionary:
		return {
			"text": str(step.get("text", "")),
			"resident_id": int(step.get("resident_id", -1)),
			"cause": str(step.get("cause", "")),
			"too_late": bool(step.get("too_late", false)),
			"recovering": bool(step.get("recovering", false)),
			"seconds": game.keep_running_seconds if game.keep_running else game.day_cycle.elapsed_seconds,
		}

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
	_case("e", _test_first_actionable_tip)
	_case("f", _test_loss_and_death_save_load)
	_case("g", _test_keep_running_day_checkpoints)
	_case("h", _test_real_death_clock)
	_case("i", _test_mid_tick_death_clock)
	_case("j", _test_earlier_tip_and_reload)
	_case("k", _test_real_first_tip)
	_case("l", _test_fatal_tick_tip_is_not_saving)
	_case("m", _test_tip_cause_and_resets)
	_case("n", _test_recap_button_chrome_and_retry_focus)
	_case("o", _test_recap_without_checkpoint_button_and_focus)
	_case("p", _test_named_continue_and_dynamic_button_width)
	_case("q", _test_keep_running_named_continue)
	_case("r", _test_doomed_survivors_cannot_continue)
	_case("s", _test_named_continue_then_final_wipe)
	_case("t", _test_saving_tip_per_cause)
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


func _game(sublevel := 3, relay := false, tutorial := false, observe_tips := false) -> VaultGame:
	_player_path = _path("save")
	_checkpoint_path = _path("checkpoint")
	_records_path = _path("records")
	_autosave_path = _path("autosave")
	if relay:
		var store := WingRecords.new()
		store.path = _records_path
		_assert_true(store.record(0x0B01, true, 3, 9, 7, true), "earned record unlocks RELAY LUMEN")
	var game := MAIN_SCENE.instantiate() as VaultGame
	if observe_tips:
		game.get_node("PlayerOrders").set_script(SamplingOrders)
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
	# These replays play idle: veto the Cook's auto food step (as if each Cook blueprint was cancelled).
	if "cook_auto_vetoed" in game:
		for kind_id in VaultGame.COOK_AUTO_CHAIN:
			game.cook_auto_vetoed[kind_id] = true
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
	_assert_true(not recap.is_empty(), "death records resident, cause, simulation time and first saving tip")
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
	var saving_line := "This would have saved %s: %s" % [str(recap.get("name", "")), tip.trim_prefix("Next: ")]
	_assert_true((tip.begins_with("Next: ") and saving_line in body) or (tip.is_empty() and "No tip could have saved them." in body), "recap explains the first saving tip or plainly says no tip could save them")
	_assert_false("nothing lands in time" in tip, "too_late is never recorded as an actionable tip")
	var resume := _button(orders, "outcome_resume_button")
	var can_resume := game.get_alive_count() > 0 and game.outcome == "death"
	if can_resume and game.has_method("can_still_win_shift"):
		can_resume = bool(game.call("can_still_win_shift"))
	_assert_true(resume != null, "recap has a Resume button")
	if resume != null:
		_assert_equal(resume.visible and not resume.disabled, can_resume, "Continue is available iff survivors can still win or keep running")
		_assert_equal(resume.visible, can_resume, "a wipe or a proven doomed shift hides Continue")
		if can_resume and not str(recap.get("name", "")).is_empty():
			_assert_equal(resume.text, "Continue without %s" % str(recap.name), "Continue names the dead resident from the recap")
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


func _test_first_actionable_tip() -> void:
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
		var sampled: Dictionary = game.player_orders.get("_survival_tips")
		# Accept the parent tree's flat map for the regression control run.
		var retained: Variant = sampled.get(target.resident_id, "")
		var sampled_tip := str(retained.get(str(live_step.get("cause", "")), "")) if retained is Dictionary else str(retained)
		_assert_equal(sampled_tip, str(live_step.get("text", "")), "simulation sampling retains the exact actionable tip without UI refresh")
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
	_assert_equal(str(_recap(game).get("tip", "")), str(live_step.get("text", "")), "recap preserves the earliest actionable exact Next label for the dead resident")
	_assert_true(_saving_line(target, str(live_step.get("text", ""))) in game.player_orders.outcome_text.text, "recap identifies the earliest live Next action as what would have saved the resident")
	_dispose(game)


func _saving_line(resident: VaultResident, tip: String) -> String:
	return "This would have saved %s: %s" % [resident.resident_name, tip.trim_prefix("Next: ")]


func _saving_tip_fixture(game: VaultGame) -> Dictionary:
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(21, 17))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(25, 16))
	game.power_grid.recalculate(game.buildings)
	_assert_true(kitchen.powered, "saving-tip fixture starts with a powered kitchen")
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
	var target: VaultResident = game.residents[0]
	target.needs.food = 0.0
	target.drafted = true
	game.food_system.meals = 0
	game.food_system.raw_food = FoodSystem.COOK_INPUT
	return {"target": target, "kitchen": kitchen}


func _assert_tip_round_trip(game: VaultGame) -> void:
	var recap := _recap(game).duplicate(true)
	var body := game.player_orders.outcome_text.text
	_assert_true(game.save_game(false, _player_path), "saving-tip death snapshot saves through SaveLoad")
	game.new_game(false, 4242, game.sublevel)
	_assert_true(game.load_game(_player_path), "saving-tip death snapshot loads through SaveLoad")
	game.player_orders.refresh()
	_assert_equal(_recap(game).get("tip", "missing"), recap.get("tip", ""), "Load preserves the raw earliest saving tip")
	_assert_equal(game.player_orders.outcome_text.text, body, "Load preserves the complete saving-tip recap text")


func _test_earlier_tip_and_reload() -> void:
	var game := _game(3, false, false, true)
	game.begin_shift()
	var fixture := _saving_tip_fixture(game)
	var target: VaultResident = fixture.target
	var kitchen: VaultBuilding = fixture.kitchen
	var observer := game.player_orders as SamplingOrders
	# No HUD refresh: the real pre-damage sampler must retain the first tip.
	game.step_simulation(VaultGame.SIMULATION_TICK)
	var first: Dictionary = observer.first_actionable.get(target.resident_id, {})
	var earlier := str(first.get("text", ""))
	_assert_true(earlier.begins_with("Next: ") and target.resident_name in earlier and "undraft" in earlier, "first real sample names the resident and the available food rescue")
	_assert_equal(first.get("cause", ""), "food", "first saving tip is the food-runway warning")
	# The same resident now needs a different food intervention. Sampling it
	# must not erase the first warning while there was still time to rescue.
	target.drafted = false
	kitchen.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	var later_step := game.player_orders._primary_next_step()
	var later := str(later_step.get("text", ""))
	_assert_true(later.begins_with("Next: ") and later != earlier and target.resident_name in later, "changed situation has a different named live Next tip")
	_assert_true(not bool(later_step.get("too_late", false)) and not bool(later_step.get("recovering", false)), "later tip is still actionable")
	_assert_equal(later_step.get("cause", ""), "food", "both tips concern the eventual starvation cause")
	game.step_simulation(1.0)
	var later_was_sampled := false
	for sample: Dictionary in observer.sampled_steps:
		if str(sample.text) == later:
			later_was_sampled = true
	_assert_true(later_was_sampled, "real simulation cadence samples the distinct later actionable tip")
	_force_starvation(game, target)
	_assert_equal(game.outcome, "death", "earlier-tip fixture ends in a real resident death")
	_assert_equal(_recap(game).get("tip", ""), earlier, "recap retains the earliest raw Next string instead of the later actionable sample")
	var body := game.player_orders.outcome_text.text
	_assert_true(_saving_line(target, earlier) in body, "panel says This would have saved the named resident with the earliest action")
	_assert_false(later in body or later.trim_prefix("Next: ") in body, "panel excludes the later actionable tip")
	_assert_false("Next: " in body, "saving-tip panel strips the live label's Next prefix")
	_assert_tip_round_trip(game)
	_dispose(game)


func _test_saving_tip_per_cause() -> void:
	var game := _game(3, false, false, true)
	game.begin_shift()
	var fixture := _saving_tip_fixture(game)
	var target: VaultResident = fixture.target
	var kitchen: VaultBuilding = fixture.kitchen
	var observer := game.player_orders as SamplingOrders
	# Controlled needs transition: the first named warning concerns rest,
	# with ample food. Use the real selector and pre-damage sampler throughout.
	target.needs.food = 100.0
	target.needs.rest = 0.0
	target.needs.health = 30.0
	game.food_system.meals = 100
	var rest_step := game.player_orders._primary_next_step()
	var rest_tip := str(rest_step.get("text", ""))
	_assert_equal(rest_step.get("resident_id", -1), target.resident_id, "rest warning names the controlled resident")
	_assert_equal(rest_step.get("cause", ""), "rest", "first warning concerns exhaustion rather than food")
	_assert_true(rest_tip.begins_with("Next: ") and target.resident_name in rest_tip and "undraft" in rest_tip and "rest" in rest_tip, "first rest warning offers a named actionable rescue")
	game.step_simulation(VaultGame.SIMULATION_TICK)
	var first: Dictionary = observer.first_actionable.get(target.resident_id, {})
	_assert_equal(first.get("text", ""), rest_tip, "real sampling encounters the exhaustion warning first")
	_assert_equal(first.get("cause", ""), "rest", "resident's first sampled cause is rest")
	# The same resident later needs food. A previous rest warning must not
	# lock out this still-actionable starvation warning.
	target.needs.rest = 100.0
	target.needs.health = 100.0
	target.needs.food = 0.0
	game.food_system.meals = 0
	game.food_system.raw_food = FoodSystem.COOK_INPUT
	var food_step := game.player_orders._primary_next_step()
	var food_tip := str(food_step.get("text", ""))
	_assert_equal(food_step.get("resident_id", -1), target.resident_id, "later food warning names the same resident")
	_assert_equal(food_step.get("cause", ""), "food", "later warning concerns starvation")
	_assert_true(food_tip.begins_with("Next: ") and target.resident_name in food_tip and "undraft" in food_tip and "eat/work" in food_tip, "later food warning offers the available eating rescue")
	_assert_false(bool(food_step.get("too_late", false)) or bool(food_step.get("recovering", false)), "first food warning is still actionable")
	game.step_simulation(1.0)
	# A second, distinct food intervention must not replace the first food
	# warning, even though food was not the resident's first-ever cause.
	target.drafted = false
	kitchen.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	var later_step := game.player_orders._primary_next_step()
	var later_tip := str(later_step.get("text", ""))
	_assert_equal(later_step.get("cause", ""), "food", "second food warning has the same starvation cause")
	_assert_true(later_tip.begins_with("Next: ") and target.resident_name in later_tip and later_tip != food_tip, "second food warning offers a distinct named intervention")
	_assert_false(bool(later_step.get("too_late", false)) or bool(later_step.get("recovering", false)), "second food warning is still actionable")
	game.step_simulation(1.0)
	var rest_at := -1.0
	var food_at := -1.0
	var later_at := -1.0
	for sample: Dictionary in observer.sampled_steps:
		if str(sample.text) == rest_tip and rest_at < 0.0:
			rest_at = float(sample.seconds)
		if str(sample.text) == food_tip and food_at < 0.0:
			food_at = float(sample.seconds)
		if str(sample.text) == later_tip and later_at < 0.0:
			later_at = float(sample.seconds)
	_assert_true(rest_at >= 0.0 and food_at > rest_at, "real sampler encounters the food rescue strictly after the rest rescue")
	_assert_true(later_at > food_at, "real sampler encounters the distinct same-cause warning later")
	_force_starvation(game, target)
	_assert_equal(game.outcome, "death", "per-cause fixture ends in a real resident death")
	_assert_equal(_recap(game).get("cause", ""), "starvation", "the controlled transition ends in starvation")
	_assert_equal(_recap(game).get("tip", ""), food_tip, "recap retains the earliest food tip after the earlier exhaustion warning")
	var body := game.player_orders.outcome_text.text
	_assert_true(_saving_line(target, food_tip) in body, "starvation recap explains which food action would have saved the resident")
	_assert_false("No tip could have saved them." in body, "an earlier actionable food warning prevents the no-tip claim")
	_assert_false(rest_tip in body or rest_tip.trim_prefix("Next: ") in body, "starvation recap excludes the retained exhaustion warning")
	_assert_false(later_tip in body or later_tip.trim_prefix("Next: ") in body, "earliest-per-cause recap excludes the later food intervention")
	print("[SAVING TIP PER CAUSE] rest=%.1fs %s / food=%.1fs %s / later=%.1fs %s / recap=%s" % [rest_at, rest_tip, food_at, food_tip, later_at, later_tip, body.replace("\n", " / ")])
	_dispose(game)


func _test_real_first_tip() -> void:
	# Keep a03's scheduled player actions and real clock/damage. Start Ari
	# with a genuine 51.7-second food deadline and no edible reserve, so the
	# first kitchen warning is actionable before the later crop misses it.
	var game := _game(3, true, true, true)
	game.residents[0].needs.food = 40.0
	game.food_system.meals = 0
	game.food_system.raw_food = 0
	var observer := game.player_orders as SamplingOrders
	for frame in range(1, FRAME_CAP + 1):
		_frame = frame
		_engaged(game)
		_advance_frame(game)
		if game.outcome != "":
			break
	_assert_equal(game.outcome, "death", "real saving-tip replay reaches death before the frame cap")
	var target := _first_dead(game)
	_assert_true(target != null, "real saving-tip replay has a dead resident")
	if target == null:
		_dispose(game)
		return
	# Evidence comes from the wrapper at sampling time, never from the recap.
	var first: Dictionary = observer.first_actionable.get(target.resident_id, {})
	var earlier := str(first.get("text", ""))
	_assert_true(earlier.begins_with("Next: ") and target.resident_name in earlier, "observer captured the dead resident's first-ever actionable live tip")
	_assert_true(not observer.tick_steps.is_empty(), "observer captured real pre-damage tick selections")
	var final: Dictionary = observer.tick_steps.back() if not observer.tick_steps.is_empty() else {}
	_assert_approximately(float(final.get("seconds", -1.0)), game.day_cycle.elapsed_seconds, 0.000001, "final observed selection belongs to the fatal tick")
	_assert_true(float(first.get("seconds", INF)) < float(final.get("seconds", -1.0)), "first-ever saving tip predates the fatal tick")
	_assert_true(earlier != str(final.get("text", "")), "first-ever saving tip differs from the final tick's live selection")
	_assert_equal(_recap(game).get("tip", ""), earlier, "real-play recap retains the independently observed first-ever tip")
	_assert_true(_saving_line(target, earlier) in game.player_orders.outcome_text.text, "real-play panel explains which first warning would have saved the resident")
	_assert_true(str(_recap(game).get("tip", "")) != str(final.get("text", "")), "real-play recap never uses the fatal tick's tip")
	print("[SAVING TIP REAL] first=%.1fs %s / death=%.1fs %s" % [float(first.get("seconds", -1.0)), earlier, float(final.get("seconds", -1.0)), str(final.get("text", ""))])
	_assert_tip_round_trip(game)
	_dispose(game)


func _test_fatal_tick_tip_is_not_saving() -> void:
	var game := _game(3, false, false, true)
	game.begin_shift()
	var observer := game.player_orders as SamplingOrders
	_assert_true(observer.first_actionable.is_empty(), "no actionable tip has been shown before the fatal-tick fixture")
	var fixture := _saving_tip_fixture(game)
	var target: VaultResident = fixture.target
	game.job_system.release_resident(target)
	target.drafted = true
	target.needs.food = 0.0
	target.needs.rest = 100.0
	target.needs.mood = 100.0
	target.needs.health = 0.1
	# Do not refresh the HUD: first sampling happens in this actual death tick.
	game._simulation_step(VaultGame.SIMULATION_TICK)
	_assert_equal(game.outcome, "death", "fatal-tick fixture dies inside advance_needs")
	var first: Dictionary = observer.first_actionable.get(target.resident_id, {})
	_assert_true(str(first.get("text", "")).begins_with("Next: ") and "undraft" in str(first.get("text", "")), "real fatal-tick sampler encounters an otherwise actionable named tip")
	_assert_approximately(float(first.get("seconds", -1.0)), game.day_cycle.elapsed_seconds, 0.000001, "first actionable sample occurs at the frozen death time")
	_assert_equal(_recap(game).get("tip", "missing"), "", "a tip first sampled on the death tick is excluded from the recap")
	_assert_true("No tip could have saved them." in game.player_orders.outcome_text.text, "death without an earlier actionable tip shows the existing no-tip line")
	_assert_false("This would have saved" in game.player_orders.outcome_text.text, "fatal-tick-only tip never claims it could save the resident")
	_assert_false(str(first.get("text", "missing")) in game.player_orders.outcome_text.text, "fatal-tick live tip is absent from the panel")
	_assert_tip_round_trip(game)
	_dispose(game)


func _test_tip_cause_and_resets() -> void:
	var game := _game(3, false, false, true)
	game.begin_shift()
	var clean := game.create_snapshot()
	var fixture := _saving_tip_fixture(game)
	var target: VaultResident = fixture.target
	var observer := game.player_orders as SamplingOrders
	game.step_simulation(VaultGame.SIMULATION_TICK)
	var first: Dictionary = observer.first_actionable.get(target.resident_id, {})
	_assert_equal(first.get("cause", ""), "food", "cause-matching fixture first records a hunger warning")
	target.needs.food = 100.0
	target.needs.rest = 0.0
	target.needs.mood = 100.0
	target.needs.health = 0.01
	target.advance_needs(VaultGame.SIMULATION_TICK / DayCycle.SECONDS_PER_DAY, true, false)
	_assert_equal(_recap(game).get("cause", ""), "exhaustion", "a different threat actually kills the warned resident")
	_assert_equal(_recap(game).get("tip", "missing"), "", "a hunger tip is not offered as a rescue for exhaustion")
	_assert_true("No tip could have saved them." in game.player_orders.outcome_text.text, "unrelated earliest warning uses the no-tip line")
	_assert_false("This would have saved" in game.player_orders.outcome_text.text, "unrelated warning never claims it would save this death")
	game.new_game(false, 4242, 3)
	game.begin_shift()
	_force_starvation(game, game.residents[0])
	_assert_equal(_recap(game).get("tip", "missing"), "", "new_game clears the prior resident's earliest warning")
	_assert_true(game.apply_snapshot(clean), "live snapshot restores through the normal load path")
	fixture = _saving_tip_fixture(game)
	target = fixture.target
	game.step_simulation(VaultGame.SIMULATION_TICK)
	_assert_true(observer.first_actionable.has(target.resident_id), "load-clear fixture records another real warning")
	_assert_true(game.apply_snapshot(clean), "applying a live snapshot clears warning history again")
	_force_starvation(game, game.residents[0])
	_assert_equal(_recap(game).get("tip", "missing"), "", "apply_snapshot clears prior earliest warning and its metadata")
	_assert_true("No tip could have saved them." in game.player_orders.outcome_text.text, "restored live game cannot inherit another timeline's saving tip")
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
	_assert_true(_recap(game).has("elapsed_seconds"), "a wipe's recap keeps the simulated time of the final death, not the WING LOST label")
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
	_assert_equal(_recap(game).get("elapsed_seconds", -1.0), game.keep_running_seconds, "keep-running recap records its own simulated clock rather than the completed shift's clock")
	_assert_true(game.has_method("retry_day_checkpoint"), "keep-running recap can Retry its current day")
	if game.has_method("retry_day_checkpoint"):
		_assert_true(bool(game.call("retry_day_checkpoint")), "keep-running Retry loads the day-nine checkpoint")
		_assert_json_equal(game, game.create_snapshot(), day_nine, "keep-running Retry restores the exact day-nine snapshot JSON")
		_assert_true(game.keep_running and game.keep_running_day() == 9, "Retry preserves keep-running on day nine")
		_assert_equal(game.get_alive_count(), game.residents.size(), "day-nine Retry undoes the death")
		_assert_true(game.outcome == "" and not game.player_orders.outcome_panel.visible, "day-nine Retry clears the outcome and hides the recap")
	_dispose(game)


func _test_real_death_clock() -> void:
	# Replay a05's actual player inputs: no needs, health, clock or damage edits.
	var game := _game(5, false, true)
	var at_death := {}
	for resident: VaultResident in game.residents:
		resident.died.connect(_capture_death_clock.bind(game, at_death))
	for frame in range(1, FRAME_CAP + 1):
		_frame = frame
		_idle(game)
		_advance_frame(game)
		if game.outcome != "":
			break
	_assert_equal(game.outcome, "death", "real play reaches a resumable death")
	_assert_true(game.get_alive_count() > 0, "real death leaves a resident who can Resume")
	_assert_true(not at_death.is_empty(), "the resident's real died signal records the instant of death")
	_assert_equal(int(at_death.get("day", 0)), 5, "seed 4242 level 05 dies on day five, beyond a fresh day one")
	_assert_death_clock(game, at_death)
	print("[CLOCK REAL] frame=%d instant=%s" % [_frame, JSON.stringify(at_death)])
	var recap := _recap(game).duplicate(true)
	_assert_true(game.save_game(false, _player_path), "real death saves through the atomic player snapshot path")
	game.new_game(false, 4242, 5)
	_assert_true(game.load_game(_player_path), "real death snapshot loads")
	game.player_orders.refresh()
	_assert_equal(str(_recap(game).get("time", "")), str(recap.get("time", "")), "Load retains the real death's exact time")
	_assert_true(_recap(game).has("elapsed_seconds"), "Load retains the additive death elapsed_seconds field")
	_assert_equal(_recap(game).get("elapsed_seconds", -1.0), recap.get("elapsed_seconds", -2.0), "Load retains the real death's exact simulated seconds")
	_assert_equal(game.player_orders.clock_label.text, str(recap.get("time", "")), "loaded HUD agrees with the retained death clock")
	_assert_true(str(recap.get("time", "")) in game.player_orders.outcome_text.text, "loaded recap panel contains the retained time")
	# Version 1 remains compatible with death recaps saved before this field.
	var legacy := game.create_snapshot()
	legacy[VaultGame.DEATH_RECAP_KEY].erase("elapsed_seconds")
	_assert_true(game.apply_snapshot(legacy), "a version-one death recap without elapsed_seconds still loads")
	_assert_equal(str(_recap(game).get("time", "")), str(recap.get("time", "")), "legacy death recap retains its time")
	# Exercise the field's real load validation, including finite numeric checks.
	for bad: Variant in ["188.2", true, null, NAN, INF]:
		var invalid := legacy.duplicate(true)
		invalid[VaultGame.DEATH_RECAP_KEY]["elapsed_seconds"] = bad
		_assert_false(game.apply_snapshot(invalid), "death recap rejects elapsed_seconds=%s" % str(bad))
	_dispose(game)


func _test_mid_tick_death_clock() -> void:
	var game := _game()
	game.begin_shift()
	# If the rest of this tick ran, the HUD would cross into day two. The death
	# callback happens inside advance_needs, before day_cycle.advance.
	game.day_cycle.advance(DayCycle.SECONDS_PER_DAY - VaultGame.SIMULATION_TICK * 0.5)
	var before := game.day_cycle.elapsed_seconds
	var at_death := {}
	var target := game.residents[0]
	target.died.connect(_capture_death_clock.bind(game, at_death))
	game.job_system.release_resident(target)
	target.drafted = true
	target.needs.food = 0.0
	target.needs.rest = 100.0
	target.needs.mood = 100.0
	target.needs.health = 0.1
	game._simulation_step(VaultGame.SIMULATION_TICK)
	_assert_equal(game.outcome, "death", "starvation death fires inside the fixed tick")
	_assert_approximately(game.day_cycle.elapsed_seconds, before, 0.000001, "a death aborts the tick before the clock can advance")
	_assert_equal(game.day_cycle.current_day, 1, "the aborted tick does not cross the day boundary")
	_assert_death_clock(game, at_death)
	print("[CLOCK MID TICK] before=%.6f attempted_delta=%.6f instant=%s" % [before, VaultGame.SIMULATION_TICK, JSON.stringify(at_death)])
	_dispose(game)


func _capture_death_clock(_resident: VaultResident, game: VaultGame, evidence: Dictionary) -> void:
	# Connected after VaultGame's handler, so the recap exists while the died
	# signal is still being delivered, before control returns to the tick loop.
	game.player_orders.refresh()
	evidence.assign({
		"elapsed_seconds": game.day_cycle.elapsed_seconds,
		"day": game.day_cycle.current_day,
		"hud": game.player_orders.clock_label.text,
		"recap": _recap(game).duplicate(true),
	})


func _assert_death_clock(game: VaultGame, at_death: Dictionary) -> void:
	var recap := _recap(game)
	game.player_orders.refresh()
	_assert_equal(str(recap.get("time", "")), str(at_death.get("hud", "missing")), "recap time equals the HUD refreshed inside the death signal")
	_assert_equal(str(recap.get("time", "")), game.player_orders.clock_label.text, "recap time still equals the refreshed HUD after the tick returns")
	_assert_true(recap.has("elapsed_seconds"), "recap records the death's simulated elapsed_seconds")
	_assert_equal(typeof(recap.get("elapsed_seconds")), TYPE_FLOAT, "death elapsed_seconds is a float")
	var elapsed := float(recap.get("elapsed_seconds", -1.0))
	_assert_approximately(elapsed, float(at_death.get("elapsed_seconds", -2.0)), 0.000001, "recap elapsed_seconds equals the clock inside the death signal")
	_assert_approximately(game.day_cycle.elapsed_seconds, float(at_death.get("elapsed_seconds", -2.0)), 0.000001, "the HUD clock remains frozen at the instant of death")
	var derived := DayCycle.new()
	derived.deserialize({"elapsed_seconds": maxf(0.0, elapsed), "current_day": mini(DayCycle.DAYS_TO_SURVIVE, floori(maxf(0.0, elapsed) / DayCycle.SECONDS_PER_DAY) + 1)})
	_assert_equal(derived.current_day, int(at_death.get("day", 0)), "recap elapsed_seconds derives the death's actual day")
	_assert_equal(derived.get_clock_text(), str(recap.get("time", "")), "recap elapsed_seconds derives exactly the recorded day and time")
	derived.free()
	_assert_true(str(recap.get("time", "")) in game.player_orders.outcome_text.text, "the recap panel includes the recorded clock text")


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


func _assert_recap_button_chrome(orders: PlayerOrders, button: Button, label: String) -> void:
	var panel := orders.outcome_panel.get_theme_stylebox("panel") as StyleBoxFlat
	var backdrop := orders.get("_outcome_backdrop") as ColorRect
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := button.get_theme_stylebox(state) as StyleBoxFlat
		_assert_true(button.has_theme_stylebox_override(state) and style != null, "%s %s has an explicit StyleBoxFlat override" % [label, state])
		if style == null:
			continue
		_assert_true(style.border_width_left > 0 and style.border_width_top > 0 and style.border_width_right > 0 and style.border_width_bottom > 0, "%s %s has a visible border on every side" % [label, state])
		_assert_true(style.bg_color.a > 0.0 and panel != null and backdrop != null and style.bg_color != panel.bg_color and style.bg_color != backdrop.color, "%s %s has a visible fill distinct from the panel and backdrop" % [label, state])


func _assert_recap_focus_cleared(game: VaultGame, resume: Button, retry: Button, context: String) -> void:
	var focus := game.get_viewport().gui_get_focus_owner()
	_assert_false(resume.has_focus() or retry.has_focus() or focus == resume or focus == retry, "%s clears recap button focus" % context)


func _test_recap_button_chrome_and_retry_focus() -> void:
	var game := _game()
	game.begin_shift()
	_force_starvation(game, game.residents[0])
	var orders := game.player_orders
	var resume := _button(orders, "outcome_resume_button")
	var retry := _button(orders, "outcome_retry_button")
	_assert_true(game.outcome == "death" and orders.outcome_panel.is_visible_in_tree(), "a real resident death opens the recap in the SceneTree")
	_assert_true(resume != null and retry != null, "the shown death recap has both action buttons")
	if resume == null or retry == null:
		_dispose(game)
		return
	_assert_true(resume.is_visible_in_tree() and retry.is_visible_in_tree() and not resume.disabled and not retry.disabled, "Resume and checkpoint Retry are both visible and enabled")
	_assert_recap_button_chrome(orders, resume, "Resume")
	_assert_recap_button_chrome(orders, retry, "Retry")
	_assert_true(resume.custom_minimum_size == retry.custom_minimum_size and retry.custom_minimum_size.x >= 120 and retry.custom_minimum_size.y >= 30, "both recap buttons have an equal usable minimum size")
	_assert_true(retry.has_focus() and game.get_viewport().gui_get_focus_owner() == retry, "enabled Retry gets default focus after a real death")
	orders.hide_outcome()
	_assert_false(orders.outcome_panel.visible, "hide_outcome closes the recap")
	_assert_recap_focus_cleared(game, resume, retry, "hide_outcome")
	orders.show_outcome(false, game.get_alive_count())
	_assert_true(retry.has_focus(), "reopening the death recap restores Retry focus")
	retry.pressed.emit()
	_assert_true(game.outcome == "" and not orders.outcome_panel.visible and game.get_alive_count() == game.residents.size(), "pressing Retry restores the checkpoint and closes the recap")
	_assert_recap_focus_cleared(game, resume, retry, "Retry")
	for resident: VaultResident in game.residents:
		if resident.alive:
			_force_starvation(game, resident)
	_assert_true(game.outcome == "loss" and game.ended and orders.outcome_panel.is_visible_in_tree(), "the final real death opens the loss recap")
	_assert_true(retry.is_visible_in_tree() and not retry.disabled, "final loss still offers the available checkpoint Retry")
	_assert_true(retry.has_focus() and game.get_viewport().gui_get_focus_owner() == retry, "enabled Retry gets default focus on the final loss recap")
	orders.hide_outcome()
	_assert_recap_focus_cleared(game, resume, retry, "hiding final loss")
	_dispose(game)


func _test_recap_without_checkpoint_button_and_focus() -> void:
	var game := _game()
	game.begin_shift()
	_remove_test_save(_checkpoint_path)
	_force_starvation(game, game.residents[0])
	var orders := game.player_orders
	var resume := _button(orders, "outcome_resume_button")
	var retry := _button(orders, "outcome_retry_button")
	_assert_true(game.outcome == "death" and orders.outcome_panel.is_visible_in_tree(), "a real death without a checkpoint opens the recap")
	_assert_true(resume != null and retry != null, "the no-checkpoint recap retains both action buttons")
	if resume == null or retry == null:
		_dispose(game)
		return
	_assert_true(resume.is_visible_in_tree() and retry.is_visible_in_tree() and not resume.disabled and retry.disabled, "missing checkpoint keeps Retry visible but disabled beside enabled Resume")
	_assert_recap_button_chrome(orders, retry, "disabled Retry")
	var normal := retry.get_theme_stylebox("normal") as StyleBoxFlat
	var disabled := retry.get_theme_stylebox("disabled") as StyleBoxFlat
	_assert_true(normal != null and disabled != null and disabled.bg_color.get_luminance() < normal.bg_color.get_luminance(), "disabled Retry keeps its button fill but visibly dims it")
	_assert_true(resume.custom_minimum_size == retry.custom_minimum_size and retry.custom_minimum_size.x >= 120 and retry.custom_minimum_size.y >= 30, "disabled Retry keeps the same usable minimum size as Resume")
	_assert_true(resume.has_focus() and game.get_viewport().gui_get_focus_owner() == resume and not retry.has_focus(), "disabled Retry falls back to visible enabled Resume for focus")
	orders.hide_outcome()
	_assert_recap_focus_cleared(game, resume, retry, "hiding no-checkpoint recap")
	_dispose(game)


func _prepare_breathable_sealed_recap(game: VaultGame, elapsed_seconds := 0.0) -> void:
	game.oxygen_system.oxygen = 100.0
	game.breach_system.advance(0.0, game.breach_system.warning_at)
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.apply_patch_work(100.0)
	game.player_orders.show_breach_warning(false)
	game.day_cycle.deserialize({"elapsed_seconds": elapsed_seconds, "current_day": mini(7, floori(elapsed_seconds / DayCycle.SECONDS_PER_DAY) + 1), "completed": false})
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0


func _assert_continue_width(resume: Button, retry: Button, context: String) -> void:
	var font := resume.get_theme_font("font")
	var font_size := resume.get_theme_font_size("font_size")
	var text_width := font.get_string_size(resume.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var style_width := resume.get_theme_stylebox("normal").get_minimum_size().x
	_assert_true(resume.custom_minimum_size.x >= ceilf(text_width + style_width), "%s sets a minimum width covering the full label and button padding" % context)
	_assert_true(resume.custom_minimum_size == retry.custom_minimum_size, "%s keeps Continue and Retry at equal minimum sizes" % context)
	_assert_equal(resume.get_combined_minimum_size().x, retry.get_combined_minimum_size().x, "%s gives both buttons the same effective width" % context)


func _assert_shift_can_continue(game: VaultGame, expected: bool, context: String) -> void:
	# The control commit must fail an assertion instead of calling an absent method.
	_assert_true(game.has_method("can_still_win_shift"), "%s uses the game's documented winnability predicate" % context)
	if game.has_method("can_still_win_shift"):
		_assert_equal(bool(game.call("can_still_win_shift")), expected, context)


func _test_named_continue_and_dynamic_button_width() -> void:
	var game := _game()
	game.begin_shift()
	_prepare_breathable_sealed_recap(game, 278.0)
	var target: VaultResident = game.residents[0]
	target.resident_name = "Ari"
	_force_starvation(game, target)
	var orders := game.player_orders
	var resume := _button(orders, "outcome_resume_button")
	var retry := _button(orders, "outcome_retry_button")
	_assert_true(game.outcome == "death" and game.get_alive_count() > 0, "winnable day-seven fixture records a real death with living survivors")
	_assert_shift_can_continue(game, true, "healthy survivors can reach day seven in sealed breathable air")
	_assert_true(resume != null and retry != null, "a winnable death retains both recap actions")
	if resume == null or retry == null:
		_dispose(game)
		return
	_assert_true(resume.visible and not resume.disabled, "winnable death shows enabled Continue")
	_assert_equal(resume.text, "Continue without Ari", "winnable death uses the exact dead resident name")
	_assert_continue_width(resume, retry, "short dead name")
	var old_width := resume.custom_minimum_size.x
	# Changing only the saved recap name proves show_outcome reads that key and
	# recomputes sizes after setting its label, including repeated presentations.
	var long_name := "Alexandria Marigold Montgomery"
	game.death_recap["name"] = long_name
	orders.show_outcome(false, game.get_alive_count())
	_assert_equal(resume.text, "Continue without %s" % long_name, "reopening uses the recap name instead of the resident object's name")
	_assert_true(resume.custom_minimum_size.x > old_width, "a longer recap name recomputes the previously built button minimum")
	_assert_continue_width(resume, retry, "long dead name")
	_assert_true(retry.visible and not retry.disabled and retry.has_focus(), "named Continue preserves enabled Retry and its default focus")
	_assert_false((orders.get("_outcome_legacy_row") as HBoxContainer).visible, "a winnable recap keeps the legacy row hidden")
	game.death_recap.erase("name")
	orders.show_outcome(false, game.get_alive_count())
	_assert_true(resume.visible and not resume.disabled and not resume.text.is_empty() and not "Resume" in resume.text, "a missing recap name uses Continue wording without Resume")
	_assert_continue_width(resume, retry, "missing dead name")
	_assert_true(game.resume_after_death(), "the named winnable death permits the direct continuation path")
	game.step_simulation(2.1)
	_assert_true(game.ended and game.outcome == "win", "the surviving crew actually reaches the real day-seven win after continuing")
	_dispose(game)


func _test_keep_running_named_continue() -> void:
	var game := _game()
	game.begin_shift()
	_prepare_breathable_sealed_recap(game, DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE - VaultGame.SIMULATION_TICK)
	game.food_system.meals = 1000
	game.step_simulation(VaultGame.SIMULATION_TICK * 2.0)
	_assert_true(game.outcome == "win" and game.ended, "endless-mode fixture first earns a real day-seven win")
	_assert_true(game.start_keep_running(), "a real win enters keep-running mode")
	# Endless mode has no further win condition. Even the food proof that
	# blocks finite-shift continuation must allow living crew to keep running.
	game.food_system.meals = 0
	game.food_system.raw_food = 0
	game.job_system.reset()
	for resident: VaultResident in game.residents:
		resident.needs.food = 0.0
		resident.needs.health = 1.0
		resident.medical_bed_id = -1
		resident.state = "Idle"
	var target: VaultResident = game.residents[0]
	target.resident_name = "Noel"
	_force_starvation(game, target)
	var resume := _button(game.player_orders, "outcome_resume_button")
	var retry := _button(game.player_orders, "outcome_retry_button")
	_assert_true(game.keep_running and game.outcome == "death" and game.get_alive_count() > 0, "keep-running death retains living survivors")
	_assert_shift_can_continue(game, true, "endless mode permits surviving residents to continue")
	_assert_true(resume != null and retry != null, "keep-running death retains both recap buttons")
	if resume != null and retry != null:
		_assert_true(resume.visible and not resume.disabled, "keep-running death always shows enabled Continue for survivors")
		_assert_equal(resume.text, "Continue without Noel", "keep-running Continue uses the exact dead resident name")
		_assert_continue_width(resume, retry, "keep-running death")
	_dispose(game)


func _test_doomed_survivors_cannot_continue() -> void:
	var game := _game()
	game.begin_shift()
	_prepare_breathable_sealed_recap(game)
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(21, 17))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(25, 16))
	game.power_grid.recalculate(game.buildings)
	game.food_system.meals = 0
	game.food_system.raw_food = 0
	game.food_system.salvage = 0
	game.job_system.reset()
	for resident: VaultResident in game.residents:
		resident.needs.food = 0.0
		resident.needs.health = 1.0
		resident.medical_bed_id = -1
		resident.state = "Idle"
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY:
			building.production_progress = 0.0
	var target: VaultResident = game.residents[0]
	target.resident_name = "Devin"
	_force_starvation(game, target)
	var orders := game.player_orders
	var resume := _button(orders, "outcome_resume_button")
	var retry := _button(orders, "outcome_retry_button")
	_assert_true(game.outcome == "death" and game.get_alive_count() > 0, "doomed fixture has living survivors instead of a final wipe")
	_assert_true(game.food_system.meals == 0 and game.food_system.raw_food == 0 and game.job_system.get_pending_raw_food() == 0 and game.job_system.get_pending_meals() == 0, "doomed crew has no stored or already-produced food")
	_assert_shift_can_continue(game, false, "all survivors starve before day seven and before any possible new harvest")
	_assert_true(resume != null and retry != null, "doomed death keeps both button objects for inspection")
	if resume != null and retry != null:
		_assert_true(not resume.visible and resume.disabled, "doomed surviving crew hides and disables Continue")
		_assert_true(retry.visible and not retry.disabled, "doomed surviving crew keeps checkpoint Retry visible and enabled")
		_assert_true(retry.has_focus() and game.get_viewport().gui_get_focus_owner() == retry, "doomed surviving crew gives checkpoint Retry default focus")
	_assert_true((orders.get("_outcome_legacy_row") as HBoxContainer).visible, "doomed surviving crew restores the legacy row alongside Retry")
	var before := game.create_snapshot()
	_assert_false(game.resume_after_death(), "calling the Resume path directly refuses a proven doomed finite shift")
	_assert_json_equal(game, game.create_snapshot(), before, "refused continuation preserves the complete death snapshot")
	_assert_true(game.outcome == "death" and game.user_paused and orders.outcome_panel.visible, "refused continuation retains the paused death recap")
	# These are deliberate conservative escape hatches: an uncertain available
	# fix must keep the option visible, even if the regular urgency tip is late.
	var survivor: VaultResident = null
	for resident: VaultResident in game.residents:
		if resident.alive:
			survivor = resident
			break
	_assert_true(survivor != null, "doomed fixture retains a living resident for conservative checks")
	if survivor != null:
		survivor.needs.food = 100.0
		_assert_shift_can_continue(game, true, "one survivor with a full belly prevents hiding Continue")
		survivor.needs.food = 0.0
		game.food_system.raw_food = FoodSystem.COOK_INPUT
		_assert_shift_can_continue(game, true, "cookable raw stock preserves an available food rescue")
		game.food_system.raw_food = 0
		game.job_system.queue_meals(game.map_grid.nearest_stockpile(survivor.get_cell(game.map_grid)), 1)
		_assert_shift_can_continue(game, true, "a produced meal awaiting haul preserves an available rescue")
		game.job_system.reset()
		survivor.medical_bed_id = 999
		survivor.state = "Rest-Medical"
		_assert_shift_can_continue(game, true, "assigned medical recovery remains conservatively continuable")
		survivor.medical_bed_id = -1
		survivor.state = "Idle"
		game.day_cycle.deserialize({"elapsed_seconds": DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE - 0.1, "current_day": 7, "completed": false})
		_assert_shift_can_continue(game, true, "a survivor who can reach the imminent day-seven boundary keeps Continue")
		game.day_cycle.reset()
		var tray := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(22, 17))
		tray.production_progress = tray.get_grow_seconds() - 0.01
		game.power_grid.recalculate(game.buildings)
		_assert_shift_can_continue(game, true, "a tray with an imminent harvest leaves enough uncertainty to keep Continue")
	_dispose(game)


func _test_named_continue_then_final_wipe() -> void:
	var game := _game()
	game.begin_shift()
	_prepare_breathable_sealed_recap(game)
	game.residents[0].resident_name = "Mira"
	_force_starvation(game, game.residents[0])
	var orders := game.player_orders
	var resume := _button(orders, "outcome_resume_button")
	var retry := _button(orders, "outcome_retry_button")
	_assert_true(resume != null and resume.visible and not resume.disabled, "before the wipe healthy survivors can continue")
	if resume != null:
		_assert_equal(resume.text, "Continue without Mira", "the pre-wipe recap uses the named Continue label")
	for resident: VaultResident in game.residents:
		if resident.alive:
			_force_starvation(game, resident)
	_assert_true(game.outcome == "loss" and game.ended and game.get_alive_count() == 0, "the final resident death still ends in a real wipe")
	_assert_shift_can_continue(game, false, "a final wipe cannot win or continue")
	_assert_true(resume != null and not resume.visible and resume.disabled, "a wipe still hides and disables Continue")
	_assert_true(retry != null and retry.visible and not retry.disabled and retry.has_focus(), "a wipe keeps checkpoint Retry enabled with default focus")
	_assert_true((orders.get("_outcome_legacy_row") as HBoxContainer).visible, "the wipe keeps the legacy outcome row")
	_assert_false(game.resume_after_death(), "the direct Resume path still refuses a final wipe")
	_dispose(game)


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
