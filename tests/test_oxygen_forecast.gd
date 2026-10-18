extends SceneTree

# O2 forecast: the VAULT ATMOSPHERE readout counts down to the 15% critical
# line while oxygen falls toward it, and up to breathable while it recovers.
# Below the line with no recovery, it counts down to the first suffocation death.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var _case_count := 0
var _assertion_count := 0
var _failure_count := 0
var _current_case := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_run_case("opening wing without a recycler counts down to critical", _test_opening)
	_run_case("powered recycler above critical shows no forecast", _test_recovering_above)
	_run_case("open breach shortens the countdown", _test_open_breach)
	_run_case("recovering below critical counts up to breathable", _test_recovering_below)
	_run_case("falling below critical counts down to the first suffocation death", _test_falling_below)
	_run_case("exactly at critical while falling is already suffocating", _test_at_line)
	_run_case("exactly at critical while recovering shows no suffocation line", _test_at_line_rising)
	_run_case("suffocation countdown tracks the weakest living resident", _test_weakest_resident)
	_run_case("live suffocation ticks the HP countdown down", _test_live_suffocation)
	_run_case("lost wing drops the suffocation countdown", _test_ended_suffocating)
	_run_case("steady rate shows no forecast", _test_steady)
	_run_case("live simulation ticks the countdown down", _test_live)
	_run_case("lost wing drops the breathable forecast", _test_ended_loss)
	_run_case("won wing drops the critical forecast", _test_ended_win)
	print("OXYGEN FORECAST TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(0 if _failure_count == 0 else 1)


func _run_case(label: String, test: Callable) -> void:
	_case_count += 1
	_current_case = label
	var before := _failure_count
	print("[TEST] %s" % label)
	test.call()
	print("[%s] %s" % ["PASS" if before == _failure_count else "FAIL", label])


func _spawn_game() -> VaultGame:
	var game := MAIN_SCENE.instantiate() as VaultGame
	root.add_child(game)
	game.begin_shift()
	game.user_paused = true
	return game


func _free(game: VaultGame) -> void:
	game.queue_free()
	await process_frame


func _recycler() -> VaultBuilding:
	var building := VaultBuilding.new()
	building.kind = VaultBuilding.Kind.AIR_RECYCLER
	building.complete = true
	building.powered = true
	return building


# Stage oxygen and rates directly so each case pins one readout branch.
func _stage(game: VaultGame, oxygen: float, recyclers: int, breach_open: bool) -> String:
	var buildings: Array = []
	for _i in recyclers:
		buildings.append(_recycler())
	game.oxygen_system.oxygen = oxygen
	game.oxygen_system.refresh_rates(game.residents, buildings, breach_open)
	game.player_orders.refresh()
	for building: VaultBuilding in buildings:
		building.free()
	return game.player_orders.oxygen_label.text


func _test_opening() -> void:
	var game := _spawn_game()
	var text := _stage(game, 100.0, 0, false)
	# 4 residents x 0.08 = -0.32%/s; (100 - 15) / 0.32 = 265.6s -> 04:26.
	_assert_equal(text, "O2 100% · -0.32%/s\nUSE 0.32 · RECYCLE 0.00\nCRITICAL IN 04:26", "opening readout")
	_assert_near(game.oxygen_system.get_seconds_to_critical_crossing(), 265.625, "opening seconds")
	_free(game)


func _test_recovering_above() -> void:
	var game := _spawn_game()
	var text := _stage(game, 60.0, 1, false)
	_assert_equal(text, "O2 60% · +0.48%/s\nUSE 0.32 · RECYCLE 0.80", "recovering readout has two lines")
	_assert_near(game.oxygen_system.get_seconds_to_critical_crossing(), -1.0, "no crossing")
	_free(game)


func _test_open_breach() -> void:
	var game := _spawn_game()
	var text := _stage(game, 50.0, 1, true)
	# 0.8 - 0.32 - 2.5 = -2.02%/s; 35 / 2.02 = 17.33s -> 00:18.
	_assert_equal(text, "O2 50% · -2.02%/s\nUSE 0.32 · RECYCLE 0.80 · LEAK 2.5\nCRITICAL IN 00:18", "breach readout")
	_free(game)


func _test_recovering_below() -> void:
	var game := _spawn_game()
	var text := _stage(game, 10.0, 1, false)
	# (15 - 10) / 0.48 = 10.42s -> 00:11.
	_assert_equal(text, "O2 10% · +0.48%/s\nUSE 0.32 · RECYCLE 0.80\nBREATHABLE IN 00:11", "recovery readout")
	_free(game)


func _test_falling_below() -> void:
	var game := _spawn_game()
	var text := _stage(game, 10.0, 0, false)
	# Full health 100 / 4 HP/s suffocation = 25s.
	_assert_equal(text, "O2 10% · -0.32%/s\nUSE 0.32 · RECYCLE 0.00\nSUFFOCATING · FIRST DEATH IN 00:25", "suffocating readout")
	_assert_false("IN " in text.get_slice("\n", 0), "no forecast on the first line")
	_assert_near(game.player_orders._seconds_to_first_suffocation(), 25.0, "full-health seconds")
	_free(game)


func _test_at_line() -> void:
	var game := _spawn_game()
	var text := _stage(game, 15.0, 0, false)
	_assert_equal(text.get_slice_count("\n"), 3, "a third line at the line")
	_assert_equal(text.get_slice("\n", 2), "SUFFOCATING · FIRST DEATH IN 00:25", "suffocating at the line")
	_free(game)


func _test_at_line_rising() -> void:
	var game := _spawn_game()
	var text := _stage(game, 15.0, 1, false)
	_assert_equal(text, "O2 15% · +0.48%/s\nUSE 0.32 · RECYCLE 0.80", "rising at the line has two lines")
	_free(game)


func _test_weakest_resident() -> void:
	var game := _spawn_game()
	game.residents[0].needs.health = 30.0
	game.residents[1].needs.health = 6.0
	game.residents[1].alive = false
	var text := _stage(game, 5.0, 0, false)
	# Dead resident ignored; 3 alive x 0.08 = -0.24%/s; 30 / 4 = 7.5s -> 00:08.
	_assert_equal(text, "O2 5% · -0.24%/s\nUSE 0.24 · RECYCLE 0.00\nSUFFOCATING · FIRST DEATH IN 00:08", "weakest living resident")
	for resident: VaultResident in game.residents:
		resident.alive = false
	text = _stage(game, 5.0, 0, false)
	_assert_equal(text.get_slice_count("\n"), 2, "no living resident has no countdown")
	_free(game)


func _test_live_suffocation() -> void:
	var game := _spawn_game()
	_stage(game, 10.0, 0, false)
	game.step_simulation(5.0)
	game.player_orders.refresh()
	var text: String = game.player_orders.oxygen_label.text
	_assert_true(game.oxygen_system.oxygen < 10.0, "oxygen kept falling")
	_assert_equal(text.get_slice("\n", 2), "SUFFOCATING · FIRST DEATH IN 00:20", "five seconds later")
	_free(game)


func _test_ended_suffocating() -> void:
	var game := _spawn_game()
	var before := _stage(game, 10.0, 0, false)
	_assert_equal(before.get_slice("\n", 2), "SUFFOCATING · FIRST DEATH IN 00:25", "paused live wing keeps the countdown")
	game._finish_loss()
	game.player_orders.refresh()
	_assert_equal(game.player_orders.oxygen_label.text, "O2 10% · -0.32%/s\nUSE 0.32 · RECYCLE 0.00", "lost wing keeps only the final readout")
	_free(game)


func _test_steady() -> void:
	var game := _spawn_game()
	for resident: VaultResident in game.residents:
		resident.alive = false
	var text := _stage(game, 40.0, 0, false)
	_assert_equal(text.get_slice_count("\n"), 2, "zero rate has no forecast")
	_free(game)


func _test_live() -> void:
	var game := _spawn_game()
	game.player_orders.refresh()
	var first: String = game.player_orders.oxygen_label.text.get_slice("\n", 2)
	_assert_equal(first, "CRITICAL IN 04:26", "live opening countdown")
	game.step_simulation(10.0)
	game.player_orders.refresh()
	var later: String = game.player_orders.oxygen_label.text.get_slice("\n", 2)
	_assert_equal(later, "CRITICAL IN 04:16", "ten simulated seconds later")
	_free(game)


func _test_ended_loss() -> void:
	var game := _spawn_game()
	var before := _stage(game, 10.0, 1, false)
	_assert_equal(before.get_slice("\n", 2), "BREATHABLE IN 00:11", "paused live wing keeps its forecast")
	game._finish_loss()
	game.player_orders.refresh()
	_assert_equal(game.player_orders.oxygen_label.text, "O2 10% · +0.48%/s\nUSE 0.32 · RECYCLE 0.80", "lost wing keeps only the final readout")
	_free(game)


func _test_ended_win() -> void:
	var game := _spawn_game()
	_stage(game, 50.0, 1, true)
	game._finish_win()
	game.player_orders.refresh()
	_assert_equal(game.player_orders.oxygen_label.text, "O2 50% · -2.02%/s\nUSE 0.32 · RECYCLE 0.80 · LEAK 2.5", "won wing keeps only the final readout")
	_free(game)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	_assertion_count += 1
	if actual != expected:
		_failure_count += 1
		push_warning("[%s] %s: expected %s, got %s" % [_current_case, message, var_to_str(expected), var_to_str(actual)])
		print("  FAIL %s: expected %s, got %s" % [message, var_to_str(expected), var_to_str(actual)])


func _assert_near(actual: float, expected: float, message: String) -> void:
	_assertion_count += 1
	if absf(actual - expected) > 0.0001:
		_failure_count += 1
		print("  FAIL %s: expected %f, got %f" % [message, expected, actual])


func _assert_false(value: bool, message: String) -> void:
	_assert_equal(value, false, message)


func _assert_true(value: bool, message: String) -> void:
	_assert_equal(value, true, message)
