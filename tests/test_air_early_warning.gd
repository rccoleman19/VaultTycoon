extends "res://tests/test_cook_auto_food_step.gd"

# QA idle 05 seed 8: "OXYGEN LOW" first showed at 203 s and Next only named the Air Recycler at
# 230 s, flickering through Rec Console in between, so an idle crew suffocated on the last tick.
# After the seal the alert list now warns when O2 will reach LOW (35) within about 60 s at the
# current drain; from then on, with no Air Recycler, Next names the Air Recycler (a Charge Node
# first when power is short) and the Spend button agrees. A death at exactly 280.0 s records a
# day-and-clock recap, not "DAY 7 COMPLETE". Assertions read the alerts, Next, Spend and recap.

# The early alert now counts down to the last safe Air Recycler tap (test_air_deadline.gd).
const EARLY_PREFIX := "OXYGEN · BUILD AIR IN "
# Sample like a watching player; refreshing every tick floods the headless message queue.
const SAMPLE_S := 0.5


func _run() -> void:
	_run_case("idle 05 seed 8: the early air warning shows about 60 s before OXYGEN LOW", _test_natural_warning)
	_run_case("early warning: Next names the Air Recycler and never flickers to Rec Console", _test_next_holds_air)
	_run_case("no early warning before the seal, with air to spare, or with a recycler", _test_warning_controls)
	_run_case("a despairing resident's Rec Console step yields to the Air Recycler", _test_rec_yields)
	_run_case("power short: Next and Spend name the Charge Node for the Air Recycler", _test_power_short)
	_run_case("a death at exactly 280.0 s records the day and clock", _test_recap_day_end)
	print("")
	if _failure_count == 0:
		print("AIR EARLY WARNING TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("AIR EARLY WARNING TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
			_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _early_alert(game: VaultGame) -> String:
	for alert: String in game.player_orders.all_alerts:
		if alert.begins_with(EARLY_PREFIX):
			return alert
	return ""


func _has_alert(game: VaultGame, text: String) -> bool:
	return game.player_orders.all_alerts.has(text)


func _idle_05_s8() -> VaultGame:
	var game := _spawn_game()
	game.new_game(false, 8, 5)
	game.begin_shift()
	return game


func _spend_text(game: VaultGame) -> String:
	var button: Button = game.player_orders.upgrade_offer_button
	return button.text if button != null and button.is_visible_in_tree() else ""


# Steps the idle game to the first frame showing the early warning, or OXYGEN LOW, or 240 s.
func _to_first_warning(game: VaultGame) -> float:
	while game.day_cycle.elapsed_seconds < 240.0 and not game.ended:
		game.step_simulation(SAMPLE_S)
		game.player_orders.refresh()
		if not _early_alert(game).is_empty() or _has_alert(game, "OXYGEN LOW"):
			break
	return game.day_cycle.elapsed_seconds


func _test_natural_warning() -> void:
	var game := _idle_05_s8()
	var shown := _to_first_warning(game)
	_assert_true(not _early_alert(game).is_empty(), "the early warning shows before OXYGEN LOW (first alert at %.1f s)" % shown)
	_assert_true(shown >= 120.0 and shown <= 160.0, "it first shows near 140 s, not 203 s (%.1f s)" % shown)
	_assert_true(game.breach_system.is_sealed(), "it shows after the seal")
	var o2 := game.oxygen_system.oxygen
	_assert_true(o2 > OxygenSystem.LOW_OXYGEN_THRESHOLD, "O2 is still above LOW when it shows (%.1f)" % o2)
	var lead: float = game.oxygen_system.call("get_seconds_to_low") if game.oxygen_system.has_method("get_seconds_to_low") else -1.0
	_assert_true(lead > 0.0 and lead <= 60.0, "the projected time to LOW is within 60 s (%.1f)" % lead)
	_assert_true(_early_alert(game).contains(":"), "the warning states the time left (%s)" % _early_alert(game))
	_dispose(game)


func _test_next_holds_air() -> void:
	var game := _idle_05_s8()
	_to_first_warning(game)
	var first_next := _next(game)
	_assert_true("Air Recycler" in first_next, "Next names the Air Recycler as the warning shows: %s" % first_next)
	var rec_frames := 0
	var off_air := 0
	var bad_spend := 0
	var sample := ""
	var frames := 0
	while game.day_cycle.elapsed_seconds < 235.0 and not game.ended and game.player_orders._count_kind(VaultBuilding.Kind.AIR_RECYCLER) == 0:
		game.step_simulation(SAMPLE_S)
		game.player_orders.refresh()
		frames += 1
		var text := _next(game)
		if "Rec Console" in text:
			rec_frames += 1
			sample = text
		elif not "Air Recycler" in text and not _resident_step(game, text):
			off_air += 1
			sample = text
		var spend := _spend_text(game)
		if not spend.is_empty() and not ("Air Recycler" in spend or "Charge Node" in spend):
			bad_spend += 1
			sample = spend
	_assert_true(frames > 60, "the warning stays live over the idle run (%d frames)" % frames)
	_assert_equal(rec_frames, 0, "Next never names Rec Console while air is short (%s)" % sample)
	_assert_equal(off_air, 0, "Next keeps naming the Air Recycler (%s)" % sample)
	_assert_equal(bad_spend, 0, "Spend never offers a build other than Air or its Charge Node (%s)" % sample)
	_dispose(game)


# A resident's own urgent step (Bo starving · ...) still outranks the air build.
func _resident_step(game: VaultGame, text: String) -> bool:
	for resident: VaultResident in game.residents:
		if text.begins_with("Next: %s " % resident.resident_name):
			return true
	return false


func _test_warning_controls() -> void:
	# Unsealed: same oxygen, no early warning.
	var game := _game(30, false)
	game.oxygen_system.oxygen = 40.0
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.player_orders.refresh()
	_assert_true(_early_alert(game).is_empty(), "no early warning before the seal")
	_dispose(game)
	# Sealed, 4 crew drain 0.32/s: 54 O2 is 59 s from LOW, 56 is 66 s.
	game = _game(30, true)
	game.oxygen_system.oxygen = 56.0
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.player_orders.refresh()
	_assert_true(game.oxygen_system.net_rate < 0.0, "the crew drains air")
	var lead := (56.0 - OxygenSystem.LOW_OXYGEN_THRESHOLD) / -game.oxygen_system.net_rate
	_assert_equal(_early_alert(game) == "", lead > 60.0, "no warning more than 60 s out (%.1f s)" % lead)
	game.oxygen_system.oxygen = OxygenSystem.LOW_OXYGEN_THRESHOLD + (-game.oxygen_system.net_rate) * 50.0
	game.player_orders.refresh()
	# 50 s to LOW is 51 O2: (51 - 15) / 0.32 - 24 s spin-up = 88.5 s to the last safe tap.
	_assert_true(_early_alert(game) == "OXYGEN · BUILD AIR IN 1:29", "a 50 s lead to LOW reads BUILD AIR IN 1:29 (%s)" % _early_alert(game))
	_assert_true("Air Recycler" in _next(game), "and Next names the Air Recycler: %s" % _next(game))
	# A powered recycler stops the drain: no warning, Next released.
	_add_complete(game, VaultBuilding.Kind.GENERATOR)
	_add_complete(game, VaultBuilding.Kind.AIR_RECYCLER)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.player_orders.refresh()
	_assert_true(game.oxygen_system.net_rate > 0.0, "the powered Air Recycler outbreathes the crew (%.2f/s)" % game.oxygen_system.net_rate)
	_assert_true(_early_alert(game).is_empty(), "a powered Air Recycler clears the warning")
	_dispose(game)


func _test_rec_yields() -> void:
	var game := _game(30, true)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.oxygen_system.oxygen = OxygenSystem.LOW_OXYGEN_THRESHOLD + (-game.oxygen_system.net_rate) * 40.0
	var resident: VaultResident = game.residents[0]
	resident.needs.mood = 0.0
	resident.needs.health = 10.0
	game.player_orders.refresh()
	var urgent_rec: Dictionary = game.player_orders._primary_next_step_chain({})
	_assert_true(bool(urgent_rec.get("urgent", false)) and "Rec Console" in str(urgent_rec.get("text", "")), "the fixture's own urgent step is %s's Rec Console (%s)" % [resident.resident_name, urgent_rec.get("text", "")])
	_assert_true(not _early_alert(game).is_empty(), "the early warning is live")
	var next := _next(game)
	_assert_true(not "Rec Console" in next, "Next does not send the player to Rec Console: %s" % next)
	_assert_true("Air Recycler" in next, "Next names the Air Recycler: %s" % next)
	# Control: with air to spare the same resident still gets the Rec step.
	game.oxygen_system.oxygen = 100.0
	_add_complete(game, VaultBuilding.Kind.GENERATOR)
	_add_complete(game, VaultBuilding.Kind.AIR_RECYCLER)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.player_orders.refresh()
	_assert_true("Rec Console" in _next(game), "without the warning the despair step names Rec Console: %s" % _next(game))
	_dispose(game)


func _test_power_short() -> void:
	var game := _game(40, true)
	while game.player_orders._planned_power_spare() >= int(VaultBuilding.POWER_DEMAND[VaultBuilding.Kind.AIR_RECYCLER]):
		_add_complete(game, VaultBuilding.Kind.GROW_TRAY)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.oxygen_system.oxygen = OxygenSystem.LOW_OXYGEN_THRESHOLD + (-game.oxygen_system.net_rate) * 30.0
	game.player_orders.refresh()
	_assert_true(not _early_alert(game).is_empty(), "the early warning is live")
	var next := _next(game)
	_assert_true("Charge Node" in next and "Air Recycler" in next, "Next names the Charge Node for the Air Recycler: %s" % next)
	_assert_true("Charge Node" in _spend_text(game), "Spend offers the Charge Node too: %s" % _spend_text(game))
	# The drain eases so LOW is 2 minutes out: Next must not flicker away from air.
	game.oxygen_system.oxygen = OxygenSystem.LOW_OXYGEN_THRESHOLD + (-game.oxygen_system.net_rate) * 120.0
	game.player_orders.refresh()
	var held := _next(game)
	_assert_true("Charge Node" in held and "Air Recycler" in held, "Next keeps the air step once shown: %s" % held)
	_dispose(game)


func _test_recap_day_end() -> void:
	var game := _game(0, true)
	game.oxygen_system.oxygen = 5.0
	game.day_cycle.advance(DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE)
	_assert_true(game.day_cycle.completed, "the clock reached 280.0 s")
	var resident: VaultResident = game.residents[0]
	var recap: Dictionary = game.player_orders.death_recap_for(resident)
	var clock := str(recap.get("time", ""))
	_assert_true(not "COMPLETE" in clock, "the recap does not claim day 7 complete (%s)" % clock)
	_assert_true(clock.begins_with("DAY 7/7") and ":" in clock, "the recap shows the HUD-style day and clock (%s)" % clock)
	_dispose(game)
