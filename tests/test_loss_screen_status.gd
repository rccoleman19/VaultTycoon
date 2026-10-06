extends "res://tests/test_runner.gd"
# Once the shift ends (WING LOST or SEAL STABILIZED), the HUD stops giving live
# advice: the alert line is one outcome line, the hatch response line says the
# response ended, and a win reports its result instead of a Next tip. Live
# screens keep their real blockers until the outcome.

const TICK := VaultGame.SIMULATION_TICK
const LOSS_ALERT := "SHIFT ENDED · WING LOST"
const WIN_ALERT := "SHIFT ENDED · SEAL STABILIZED"
const RESPONSE_ENDED := "NO LIVING CREW · RESPONSE ENDED"
const RED := Color("ef6860")
const GREEN := Color("75d4b4")
const WIN_SAVE_PATH := "user://headless_loss_screen_win.json"


func _run() -> void:
	_run_case("a real wipe in OPEN ends the alert and hatch advice", _test_real_wipe_open)
	_run_case("a wipe during WARNING ends the response line", _test_wipe_warning)
	_run_case("a real managed win reports the result instead of a Next tip", _test_real_win)
	_run_case("a lone survivor reads singular", _test_single_survivor)
	_run_case("live screens keep their advice until the shift ends", _test_live_controls)
	_run_case("a win save reloads the result; a new wing restores live texts", _test_win_save_load)
	print("LOSS SCREEN STATUS TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
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
	# Real path: one simulation tick across 60 s raises the warning modal.
	game.day_cycle.elapsed_seconds = BreachSystem.WARNING_AT_SECONDS - TICK
	game.step_simulation(TICK)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.WARNING, "real hatch WARNING")


func _open_breach_text(game: VaultGame, response: String) -> String:
	return "BREACH OPEN · O2 -%.1f%%/s\nPATCH %d/%d · WORK %.1fs\n%s" % [
		OxygenSystem.OPEN_BREACH_LOSS_PER_SECOND,
		game.breach_system.patch_delivered,
		BreachSystem.PATCH_COST,
		game.breach_system.patch_work_left,
		response,
	]


func _last_line(text: String) -> String:
	var lines := text.split("\n")
	return lines[lines.size() - 1]


func _managed_wing() -> VaultGame:
	# Same fixture as test_runner's managed day-seven win.
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


func _assert_win_texts(game: VaultGame, survivors: int, label: String) -> void:
	var orders := game.player_orders
	var noun := "resident" if survivors == 1 else "residents"
	_assert_equal(orders.objective_label.text, "SEAL STABILIZED // %d %s survived" % [survivors, noun], "%s: Next reports the win" % label)
	_assert_equal(orders.objective_label.get_theme_color("font_color"), GREEN, "%s: win line uses the outcome green" % label)
	_assert_equal(orders.alert_label.text, WIN_ALERT, "%s: alert line is the win outcome" % label)
	_assert_equal(orders.alert_label.get_theme_color("font_color"), GREEN, "%s: win alert uses the outcome green" % label)


func _test_real_wipe_open() -> void:
	var game := _healthy()
	var orders := game.player_orders
	_set_all(game, "haul", VaultResident.PRIORITY_DISABLED)
	_set_all(game, "craft", VaultResident.PRIORITY_DISABLED)
	_warn(game)
	game.acknowledge_breach_warning(true)
	_assert_true(game.selected_breach, "the warning focused the hatch inspector")
	var guard := 0
	var saw_live_blocker := false
	while not game.ended and guard < 4000:
		game.user_paused = false
		game.step_simulation(TICK)
		guard += 1
		if game.breach_system.phase == BreachSystem.Phase.OPEN and not saw_live_blocker:
			orders.refresh()
			saw_live_blocker = true
			_assert_equal(_last_line(orders.breach_label.text), "BLOCKED · ENABLE HAUL", "live OPEN still names the Haul blocker")
			_assert_true("BREACH OPEN · O2 VENTING" in orders.alert_label.text, "live OPEN alert names the venting breach")
	_assert_true(saw_live_blocker, "the wing reached OPEN before the wipe")
	_assert_true(game.ended and game.outcome == "loss", "O2 loss wipes the wing for real")
	_assert_equal(game.get_alive_count(), 0, "no residents remain")
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.OPEN, "the hatch is still open at the wipe")
	_assert_true(orders.outcome_panel.visible and orders.outcome_title.text == "WING LOST", "WING LOST panel shown")
	for _i: int in 3:
		orders.refresh()
	_assert_equal(orders.alert_label.text, LOSS_ALERT, "alert line is the loss outcome")
	_assert_equal(orders.alert_label.get_theme_color("font_color"), RED, "loss alert uses the outcome red")
	_assert_false("NO COOK ENABLED" in orders.alert_label.text, "no cook advice for a dead crew")
	_assert_false(orders.objective_label.text.begins_with("SEAL STABILIZED"), "a loss never reads as the win line")
	_assert_equal(orders.breach_label.text, _open_breach_text(game, RESPONSE_ENDED), "DETAILS keeps the final hatch numbers and ends the response")
	_assert_true(game.selected_breach, "hatch inspector still selected")
	_assert_equal(orders.inspector_title.text, "MAINTENANCE HATCH", "hatch inspector shown")
	_assert_equal(_last_line(orders.inspector_state.text), RESPONSE_ENDED, "hatch inspector ends the response too")
	_assert_false("BLOCKED" in orders.inspector_state.text, "hatch inspector names no blocker")
	_dispose(game)


func _test_wipe_warning() -> void:
	var game := _healthy()
	var orders := game.player_orders
	_set_all(game, "haul", VaultResident.PRIORITY_DISABLED)
	_warn(game)
	orders.refresh()
	_assert_equal(_last_line(orders.breach_label.text), "BLOCKED · ENABLE HAUL", "live WARNING names the Haul blocker")
	for resident: VaultResident in game.residents:
		resident.kill()
	_assert_true(game.ended and game.outcome == "loss", "a wipe during WARNING ends the shift")
	orders.refresh()
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.WARNING, "the hatch is still in WARNING")
	_assert_true(orders.breach_label.text.begins_with("WARNING · SEAL LOAD "), "DETAILS keeps the final WARNING numbers")
	_assert_equal(_last_line(orders.breach_label.text), RESPONSE_ENDED, "DETAILS WARNING ends the response")
	_assert_equal(orders.alert_label.text, LOSS_ALERT, "WARNING wipe alert is the loss outcome")
	_assert_equal(orders.alert_label.get_theme_color("font_color"), RED, "WARNING wipe alert uses the outcome red")
	_assert_true(game.selected_breach and orders.inspector_title.text == "MAINTENANCE HATCH", "hatch inspector shown")
	_assert_equal(_last_line(orders.inspector_state.text), RESPONSE_ENDED, "hatch inspector WARNING ends the response")
	_dispose(game)


func _test_real_win() -> void:
	var game := _managed_wing()
	var orders := game.player_orders
	game.step_simulation(DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE + TICK)
	_assert_true(game.ended and game.outcome == "win", "managed wing wins for real")
	_assert_equal(game.get_alive_count(), 4, "all four survive")
	_assert_true(orders.outcome_panel.visible and orders.outcome_title.text == "SEAL STABILIZED", "SEAL STABILIZED panel shown")
	orders.refresh()
	_assert_win_texts(game, 4, "real win")
	_assert_equal(orders.breach_label.text, "CONTAINED · PATCH COMPLETE\nHATCH STABLE · NO ACTIVE LEAK", "sealed hatch DETAILS unchanged on the win")
	# Late-game states that nag on a live screen stay quiet once the shift is won.
	_set_all(game, "cook", VaultResident.PRIORITY_DISABLED)
	_set_all(game, "haul", VaultResident.PRIORITY_DISABLED)
	game.food_system.meals = 0
	game.residents[0].needs.food = 10.0
	orders.refresh()
	_assert_win_texts(game, 4, "win with Cook/Haul OFF and no meals")
	_dispose(game)


func _test_single_survivor() -> void:
	var game := _managed_wing()
	game.step_simulation(DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE - 1.0)
	_assert_false(game.ended, "still live one second before Day 7 ends")
	for index: int in range(1, game.residents.size()):
		game.residents[index].kill()
	_assert_equal(game.get_alive_count(), 1, "one resident left alive")
	game.step_simulation(2.0)
	_assert_true(game.ended and game.outcome == "win", "a lone survivor still wins")
	game.player_orders.refresh()
	_assert_win_texts(game, 1, "lone survivor")
	_dispose(game)


func _test_live_controls() -> void:
	# Cook OFF on a living wing still warns.
	var game := _healthy()
	var orders := game.player_orders
	_set_all(game, "cook", VaultResident.PRIORITY_DISABLED)
	orders.refresh()
	_assert_true("NO COOK ENABLED" in orders.alert_label.text, "living wing with Cook OFF still warns")
	_assert_false(orders.alert_label.text.begins_with("SHIFT ENDED"), "live alert is not an outcome line")
	_assert_true(orders.objective_label.text.begins_with("Next: "), "live Next stays a tip")
	_dispose(game)
	# Day 7 completed with the hatch open is victory pending, not ended.
	game = _healthy()
	orders = game.player_orders
	_set_all(game, "haul", VaultResident.PRIORITY_DISABLED)
	_set_all(game, "craft", VaultResident.PRIORITY_DISABLED)
	var completion := DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE
	game.day_cycle.advance(completion - TICK)
	game.breach_system.advance(0.0, completion - TICK)
	game._simulation_step(TICK)
	_assert_true(game.day_cycle.completed and not game.ended, "completed clock with an open hatch is still live")
	orders.refresh()
	_assert_equal(orders.objective_label.text, "VICTORY PENDING // SEAL HATCH", "victory pending keeps its blocker")
	_assert_true("VICTORY PENDING · SEAL HATCH" in orders.alert_label.text, "victory pending alert keeps its blocker")
	_assert_equal(_last_line(orders.breach_label.text), "BLOCKED · ENABLE HAUL", "live OPEN DETAILS keeps the Haul blocker")
	_dispose(game)


func _test_win_save_load() -> void:
	_remove_test_save(WIN_SAVE_PATH)
	var game := _managed_wing()
	var orders := game.player_orders
	game.step_simulation(DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE + TICK)
	_assert_true(game.ended and game.outcome == "win", "managed wing wins for real")
	_assert_true(game.save_game(false, WIN_SAVE_PATH), "win state saves")
	game.new_game()
	orders.refresh()
	_assert_false(game.ended, "New Wing starts live")
	_assert_false(orders.alert_label.text.begins_with("SHIFT ENDED"), "New Wing alert is live again")
	_assert_true(orders.objective_label.text.begins_with("Next: "), "New Wing Next is a tip again")
	_assert_true(game.load_game(WIN_SAVE_PATH), "win save loads")
	_assert_true(game.ended and game.outcome == "win", "loaded save is the win")
	orders.refresh()
	_assert_win_texts(game, game.get_alive_count(), "loaded win")
	_remove_test_save(WIN_SAVE_PATH)
	_dispose(game)
