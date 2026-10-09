extends "res://tests/test_runner.gd"
# Once the shift ends, the bottom tool-status help must stop advertising SELECT
# drafting. After the transient death / breach-contained status message expires,
# it points at LOAD LAST CHECKPOINT or NEW WING instead.

const TICK := VaultGame.SIMULATION_TICK
const ENDED_HELP := "SHIFT ENDED // LOAD LAST CHECKPOINT or NEW WING"
const SELECT_DRAFT := "Select a living resident"
const WIN_SAVE_PATH := "user://headless_loss_screen_tool_help_win.json"


func _run() -> void:
	_run_case("a real wipe shows ended tool help after the death message expires", _test_wipe_ended_help)
	_run_case("a death message still shows while its timer is running", _test_wipe_keeps_death_message)
	_run_case("a real managed win shows ended tool help when status is idle", _test_win_ended_help)
	_run_case("a live wing keeps SELECT drafting help", _test_live_select_help)
	_run_case("victory pending keeps SELECT drafting help", _test_victory_pending_select_help)
	_run_case("New Wing restores live SELECT help after an ended screen", _test_new_wing_restores_help)
	print("LOSS SCREEN TOOL HELP TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(0 if _failure_count == 0 else 1)


func _healthy() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
	return game


func _set_all(game: VaultGame, work: String, priority: int) -> void:
	for resident: VaultResident in game.residents:
		resident.set_work_priority(work, priority)


func _warn(game: VaultGame) -> void:
	game.day_cycle.elapsed_seconds = BreachSystem.WARNING_AT_SECONDS - TICK
	game.step_simulation(TICK)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.WARNING, "real hatch WARNING")


func _managed_wing() -> VaultGame:
	var game := _spawn_game()
	var bed_cells: Array[Vector2i] = [Vector2i(18, 12), Vector2i(19, 12), Vector2i(20, 12), Vector2i(21, 12)]
	for cell: Vector2i in bed_cells:
		_add_completed_building(game, VaultBuilding.Kind.BED, cell)
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(22, 12))
	_add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(23, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(25, 12))
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(26, 12))
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(27, 12))
	_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(24, 12))
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.begin_shift()
	return game


func _expire_status(game: VaultGame) -> void:
	game.status_message_left = 0.0
	game.active_tool = "select"
	game.player_orders.refresh()


func _assert_ended_help(game: VaultGame, label: String) -> void:
	_assert_equal(game.player_orders.tool_status.text, ENDED_HELP, "%s: tool-status is the ended help" % label)
	_assert_false(SELECT_DRAFT in game.player_orders.tool_status.text, "%s: no SELECT drafting help" % label)


func _test_wipe_ended_help() -> void:
	var game := _healthy()
	var orders := game.player_orders
	_set_all(game, "haul", VaultResident.PRIORITY_DISABLED)
	_set_all(game, "craft", VaultResident.PRIORITY_DISABLED)
	_warn(game)
	game.acknowledge_breach_warning(true)
	var guard := 0
	while not game.ended and guard < 4000:
		game.user_paused = false
		game.step_simulation(TICK)
		guard += 1
	_assert_true(game.ended and game.outcome == "loss", "O2 loss wipes the wing for real")
	_assert_true(orders.outcome_panel.visible and orders.outcome_title.text == "WING LOST", "WING LOST panel shown")
	_expire_status(game)
	_assert_ended_help(game, "wipe after status expires")
	_dispose(game)


func _test_wipe_keeps_death_message() -> void:
	var game := _healthy()
	var orders := game.player_orders
	_set_all(game, "haul", VaultResident.PRIORITY_DISABLED)
	_set_all(game, "craft", VaultResident.PRIORITY_DISABLED)
	_warn(game)
	game.acknowledge_breach_warning(true)
	var guard := 0
	while not game.ended and guard < 4000:
		game.user_paused = false
		game.step_simulation(TICK)
		guard += 1
	_assert_true(game.ended and game.outcome == "loss", "wipe ended the shift")
	_assert_true(game.status_message_left > 0.0, "death status message is still running")
	_assert_true("has died" in game.status_message, "death status names the resident")
	game.active_tool = "select"
	orders.refresh()
	_assert_equal(orders.tool_status.text, "SELECT // %s" % game.status_message, "while the timer runs, tool-status shows the death message")
	_assert_false(orders.tool_status.text.begins_with("SHIFT ENDED"), "ended help waits for the timer to expire")
	_dispose(game)


func _test_win_ended_help() -> void:
	var game := _managed_wing()
	var orders := game.player_orders
	game.step_simulation(DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE + TICK)
	_assert_true(game.ended and game.outcome == "win", "managed wing wins for real")
	_assert_true(orders.outcome_panel.visible and orders.outcome_title.text == "SEAL STABILIZED", "SEAL STABILIZED panel shown")
	_expire_status(game)
	_assert_ended_help(game, "win with idle status")
	_dispose(game)


func _test_live_select_help() -> void:
	var game := _healthy()
	var orders := game.player_orders
	_expire_status(game)
	_assert_true(SELECT_DRAFT in orders.tool_status.text, "live SELECT still shows drafting help")
	_assert_false(orders.tool_status.text.begins_with("SHIFT ENDED"), "live tool-status is not an outcome line")
	_assert_true(orders.tool_status.text.begins_with("SELECT //"), "live tool-status keeps the SELECT prefix")
	_dispose(game)



func _test_victory_pending_select_help() -> void:
	# Day 7 completed with the hatch open is victory pending, not ended.
	var game := _healthy()
	var orders := game.player_orders
	_set_all(game, "haul", VaultResident.PRIORITY_DISABLED)
	_set_all(game, "craft", VaultResident.PRIORITY_DISABLED)
	var completion := DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE
	game.day_cycle.advance(completion - TICK)
	game.breach_system.advance(0.0, completion - TICK)
	game._simulation_step(TICK)
	_assert_true(game.day_cycle.completed and not game.ended, "completed clock with an open hatch is still live")
	_expire_status(game)
	_assert_true(SELECT_DRAFT in orders.tool_status.text, "victory pending keeps SELECT drafting help")
	_assert_false(orders.tool_status.text.begins_with("SHIFT ENDED"), "victory pending is not an outcome tool-status")
	_dispose(game)


func _test_new_wing_restores_help() -> void:
	_remove_test_save(WIN_SAVE_PATH)
	var game := _managed_wing()
	var orders := game.player_orders
	game.step_simulation(DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE + TICK)
	_assert_true(game.ended and game.outcome == "win", "managed wing wins for real")
	_assert_true(game.save_game(false, WIN_SAVE_PATH), "win state saves")
	_expire_status(game)
	_assert_ended_help(game, "ended before New Wing")
	game.new_game()
	_expire_status(game)
	_assert_false(game.ended, "New Wing starts live")
	_assert_true(SELECT_DRAFT in orders.tool_status.text, "New Wing restores SELECT drafting help")
	_assert_false(orders.tool_status.text.begins_with("SHIFT ENDED"), "New Wing tool-status is live again")
	_assert_true(game.load_game(WIN_SAVE_PATH), "win save loads")
	_assert_true(game.ended and game.outcome == "win", "loaded save is the win")
	_expire_status(game)
	_assert_ended_help(game, "loaded win")
	_remove_test_save(WIN_SAVE_PATH)
	_dispose(game)
