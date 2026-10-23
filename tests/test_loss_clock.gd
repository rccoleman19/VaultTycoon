extends "res://tests/test_runner.gd"

# Loss clock: a wing that suffocated after the seven-day clock ran out showed
# "DAY 7 COMPLETE" in the top bar next to WING LOST. A lost wing now reads
# "DAY N · WING LOST"; a won or still-pending Day 7 keeps "DAY 7 COMPLETE".

const LOSS_SAVE_TEST_PATH := "user://headless_loss_clock_round_trip.json"
const CLOCK_MIN_WIDTH := 170.0
const SUFFOCATION_BOUND := 60.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_case("suffocating after Day 7 completes reads WING LOST, not COMPLETE", _test_loss_after_day_seven)
	_case("a mid-shift loss names the day it was lost", _test_mid_shift_loss)
	_case("a won wing and a pending Day 7 keep DAY 7 COMPLETE", _test_win_and_pending)
	_case("a saved loss reloads as WING LOST; a new wing clears it", _test_save_load_and_new_game)
	print("LOSS CLOCK TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(0 if _failure_count == 0 else 1)


func _case(label: String, test: Callable) -> void:
	_case_count += 1
	_current_case = label
	var before := _failure_count
	print("[TEST] %s" % label)
	test.call()
	print("[%s] %s" % ["PASS" if before == _failure_count else "FAIL", label])


func _clock(game: VaultGame) -> String:
	game.player_orders.refresh()
	return game.player_orders.clock_label.text


# The QA 2026-10-18 shape: hatch never answered, clock runs out, crew suffocates.
func _day_seven_pending_game() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	for resident: VaultResident in game.residents:
		resident.work_allowed.haul = false
		resident.work_allowed.craft = false
	var boundary := DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE
	game.day_cycle.advance(boundary - VaultGame.SIMULATION_TICK)
	game.breach_system.advance(0.0, boundary - VaultGame.SIMULATION_TICK)
	game._simulation_step(VaultGame.SIMULATION_TICK)
	return game


func _suffocate(game: VaultGame) -> void:
	var ticks := 0
	while not game.ended and ticks < int(round(SUFFOCATION_BOUND / VaultGame.SIMULATION_TICK)):
		game.oxygen_system.oxygen = 0.0
		game._simulation_step(VaultGame.SIMULATION_TICK)
		ticks += 1


func _test_loss_after_day_seven() -> void:
	var game := _day_seven_pending_game()
	_assert_true(game.day_cycle.completed, "clock completed with the hatch open")
	_assert_false(game.ended, "no outcome yet")
	_assert_equal(_clock(game), "DAY 7 COMPLETE", "pending Day 7 still reads complete before the loss")
	_suffocate(game)
	_assert_true(game.ended, "crew suffocates within %ds" % int(SUFFOCATION_BOUND))
	_assert_equal(game.outcome, "loss", "outcome is loss")
	_assert_equal(game.get_alive_count(), 0, "nobody survived")
	var text := _clock(game)
	_assert_equal(text, "DAY 7 · WING LOST", "top bar names the loss")
	_assert_false("COMPLETE" in text, "a lost wing never reads COMPLETE")
	var width := game.player_orders.clock_label.get_minimum_size().x
	_assert_true(width <= CLOCK_MIN_WIDTH, "loss clock fits the 170px slot (%.1f)" % width)
	print("Loss clock width: %.1fpx (slot %.0fpx)" % [width, CLOCK_MIN_WIDTH])
	_dispose(game)


func _test_mid_shift_loss() -> void:
	var game := _spawn_game()
	game.begin_shift()
	game.day_cycle.advance(DayCycle.SECONDS_PER_DAY * 2.5)
	_assert_equal(game.day_cycle.current_day, 3, "day three")
	_assert_equal(_clock(game), "DAY 3/7  ·  12:00", "live clock before the loss")
	for resident: VaultResident in game.residents:
		resident.kill()
	_assert_true(game.ended, "last death ends the wing")
	_assert_equal(game.outcome, "loss", "outcome is loss")
	_assert_equal(_clock(game), "DAY 3 · WING LOST", "frozen clock names the lost day")
	_dispose(game)


func _test_win_and_pending() -> void:
	var game := _day_seven_pending_game()
	_assert_equal(_clock(game), "DAY 7 COMPLETE", "pending Day 7 reads complete")
	game._finish_win()
	_assert_equal(game.outcome, "win", "outcome is win")
	_assert_false(game.day_cycle.wing_lost, "a win is not a lost wing")
	_assert_equal(_clock(game), "DAY 7 COMPLETE", "won wing keeps DAY 7 COMPLETE")
	_dispose(game)


func _test_save_load_and_new_game() -> void:
	var game := _day_seven_pending_game()
	_suffocate(game)
	_assert_equal(game.outcome, "loss", "outcome is loss before save")
	_assert_true(game.save_game(false, LOSS_SAVE_TEST_PATH), "lost wing saves")
	var loaded := _spawn_game()
	_assert_equal(_clock(loaded), "DAY 1/7  ·  00:00", "fresh wing clock before load")
	_assert_true(loaded.load_game(LOSS_SAVE_TEST_PATH), "lost wing loads")
	_assert_true(loaded.ended and loaded.outcome == "loss", "loaded wing is lost")
	_assert_equal(_clock(loaded), "DAY 7 · WING LOST", "loaded loss reads WING LOST")
	loaded.new_game(false)
	_assert_equal(loaded.outcome, "", "new wing has no outcome")
	_assert_false(loaded.day_cycle.wing_lost, "new wing clears the lost flag")
	_assert_equal(_clock(loaded), "DAY 1/7  ·  00:00", "new wing clock restarts")
	_dispose(loaded)
	_dispose(game)
	_remove_test_save(LOSS_SAVE_TEST_PATH)
