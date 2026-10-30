extends "res://tests/test_air_early_warning.gd"

# QA idle 05 seed 8 after the 58.7 s seal: the air alert counted down to O2 LOW (35%), then
# showed a bare "OXYGEN LOW", and Next called Bo "suffocating" at 25% O2. Taps measured on
# that run: an Air Recycler placed at 240 or 250 s kept all four alive, one placed at 258 s
# lost Ari and Bo. The alert and Next now count down to the last safe tap (O2 reaches 15%
# minus the recycler's spin-up), escalate at 60 s and 30 s left, keep counting below 35%,
# and say "suffocating" only below 15%. Assertions read the alert list and Next.

const NextCountdown := preload("res://scripts/next_countdown.gd")
const MEASURED_WIN_TAP_S := 250.0
const MEASURED_LOSS_TAP_S := 258.0


func _run() -> void:
	_run_case("idle 05 s8: the air alert counts down to the last safe tap, not to 35% or 15%", _test_deadline)
	_run_case("idle 05 s8: the countdown escalates at 60 s and 30 s and survives O2 < 35%", _test_escalation)
	_run_case("idle 05 s8: Next says 'suffocating' only while O2 is below 15%", _test_suffocating)
	_run_case("the flicker counter counts stage-word changes but not clock-only ticks", _test_flicker_counter)
	print("")
	if _failure_count == 0:
		print("AIR DEADLINE TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("AIR DEADLINE TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
			_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _air_alert(game: VaultGame) -> String:
	for alert: String in game.player_orders.all_alerts:
		if alert.begins_with("OXYGEN "):
			return alert
	return ""


# Seconds from an "m:ss" clock at the end of the alert or Next, or -1.
func _clock_seconds(text: String) -> float:
	var regex := RegEx.create_from_string("(\\d+):(\\d\\d)(?: LEFT)?$")
	var found := regex.search(text)
	if found == null:
		return -1.0
	return float(int(found.get_string(1)) * 60 + int(found.get_string(2)))


func _step_until(game: VaultGame, done: Callable, limit_s := 280.0) -> void:
	while game.day_cycle.elapsed_seconds < limit_s and not game.ended:
		game.step_simulation(SAMPLE_S)
		game.player_orders.refresh()
		if done.call():
			return


func _test_deadline() -> void:
	var game := _idle_05_s8()
	_step_until(game, func() -> bool: return _air_alert(game).contains("BUILD AIR"), 200.0)
	var now := game.day_cycle.elapsed_seconds
	var alert := _air_alert(game)
	var left := _clock_seconds(alert)
	_assert_true(alert.begins_with("OXYGEN · BUILD AIR IN "), "the first air alert reads BUILD AIR IN m:ss (%s at %.1f s)" % [alert, now])
	_assert_true(now >= 120.0 and now <= 160.0, "it shows near 140 s (%.1f s)" % now)
	var deadline := now + left
	_assert_true(deadline <= MEASURED_WIN_TAP_S and deadline >= MEASURED_WIN_TAP_S - 15.0,
		"the deadline (%.1f s) is at or before the measured winning tap at 250 s and within 15 s of it" % deadline)
	var to_15 := (game.oxygen_system.oxygen - OxygenSystem.CRITICAL_OXYGEN_THRESHOLD) / -game.oxygen_system.net_rate
	_assert_true(left <= to_15 - 20.0, "the countdown (%.0f s) leaves the 20-24 s spin-up before O2 hits 15%% (%.0f s)" % [left, to_15])
	var next := game.player_orders.objective_label.text
	_assert_true("Air Recycler" in next and absf(_clock_seconds(next) - left) <= 1.0, "Next names the Air Recycler with the same countdown (%s)" % next)
	_dispose(game)


func _test_escalation() -> void:
	var game := _idle_05_s8()
	_step_until(game, func() -> bool: return _air_alert(game).contains("BUILD AIR NOW"), 240.0)
	var left := _clock_seconds(_air_alert(game))
	_assert_true(left > 30.0 and left <= 60.0, "BUILD AIR NOW first shows with 60 s or less left (%s)" % _air_alert(game))
	_assert_true("BUILD AIR NOW" in game.player_orders.objective_label.text, "Next escalates with the alert (%s)" % game.player_orders.objective_label.text)
	_step_until(game, func() -> bool: return _air_alert(game).contains("LAST CHANCE"), 240.0)
	left = _clock_seconds(_air_alert(game))
	_assert_true(_air_alert(game).contains("LAST CHANCE") and left > 0.0 and left <= 30.0, "LAST CHANCE first shows with 30 s or less left (%s)" % _air_alert(game))
	_step_until(game, func() -> bool: return game.oxygen_system.is_low(), 240.0)
	_assert_true(game.oxygen_system.is_low() and _air_alert(game).contains("BUILD AIR"),
		"below 35%% O2 (%.1f) the alert keeps the countdown (%s)" % [game.oxygen_system.oxygen, _air_alert(game)])
	_dispose(game)


func _test_suffocating() -> void:
	var game := _idle_05_s8()
	var early_words: Array[String] = []
	var saw_late := false
	var saw_air_step := false
	while game.day_cycle.elapsed_seconds < 280.0 and not game.ended:
		game.step_simulation(SAMPLE_S)
		game.player_orders.refresh()
		var next := game.player_orders.objective_label.text
		if "Air Recycler" in next and next.get_slice(" · ", 0).split(" ").size() > 2:
			saw_air_step = true
		if "suffocating" in next:
			if game.oxygen_system.is_breathable():
				early_words.append("%.1f s O2 %.1f: %s" % [game.day_cycle.elapsed_seconds, game.oxygen_system.oxygen, next])
			else:
				saw_late = true
	_assert_true(saw_air_step, "a named resident's air step shows before 280 s")
	_assert_true(early_words.is_empty(), "no 'suffocating' at O2 >= 15%%: %s" % str(early_words.slice(0, 2)))
	_assert_true(saw_late, "'suffocating' shows once O2 is below 15%")
	_dispose(game)


func _test_flicker_counter() -> void:
	var step := "Next: YOU spend 14: build Air Recycler · THEY craft it"
	var ticks := [step + " · BUILD AIR IN 1:39", step + " · BUILD AIR IN 1:38", step + " · BUILD AIR IN 1:01"]
	_assert_equal(NextCountdown.count_changes(ticks), 1, "clock-only ticks count as one Next")
	var stages := ticks + [step + " · BUILD AIR NOW · 0:59 LEFT", step + " · BUILD AIR NOW · 0:31 LEFT",
		step + " · LAST CHANCE · BUILD AIR IN 0:30", step + " · LAST CHANCE · BUILD AIR IN 0:01", step]
	_assert_equal(NextCountdown.count_changes(stages), 4, "each stage word change counts: IN, NOW, LAST CHANCE, plain")
	_assert_equal(NextCountdown.strip_clock(step + " · BUILD AIR NOW · 0:59 LEFT"), step + " · BUILD AIR NOW · LEFT",
		"only the clock is stripped")
	_assert_equal(NextCountdown.count_changes([step, "Next: YOU place a Charge Node"]), 2, "a step change still counts")
	# Live: while Next holds the one spend step, its ticking clock counts as exactly the three stages.
	var game := _idle_05_s8()
	var texts: Array = []
	while game.day_cycle.elapsed_seconds < 260.0 and not game.ended:
		game.step_simulation(SAMPLE_S)
		game.player_orders.refresh()
		var t: String = game.player_orders.objective_label.text
		if game.day_cycle.elapsed_seconds >= 140.0 and t.begins_with("Next: YOU spend 14: build Air Recycler") and _clock_seconds(t) >= 0.0:
			texts.append(t)
	_assert_true(texts.size() > 60, "Next ticked its air clock %d times" % texts.size())
	_assert_equal(NextCountdown.count_changes(texts), 3, "live countdown Next counts as its 3 stages")
	_dispose(game)
