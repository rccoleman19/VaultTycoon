extends "res://tests/test_runner.gd"

# Win-screen crew rating (QA 2026-10-18b #8).
const FULL := "CREW RATING ★★★ · whole crew home, hatch held, crew steady"


func _run() -> void:
	_run_case("a steady full crew with a held hatch earns three stars", _test_full_marks)
	_run_case("each failed check costs one star with its reason", _test_single_failures)
	_run_case("BREAK RISK and CRITICAL boundaries match the HUD", _test_boundaries)
	_run_case("a win never drops below one star and lists every reason", _test_floor)
	_run_case("hatch history survives the seal; a legacy save is not penalized", _test_hatch_history)
	_run_case("the loss screen hides the grade and keeps its layout", _test_loss_unchanged)
	_run_case("a real managed win grades on screen and after a reload", _test_real_win)

	print("")
	if _failure_count == 0:
		print("CREW GRADE TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("CREW GRADE TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
			_failed_case_count,
			_case_count,
			_failure_count,
			_assertion_count,
		])
		quit(1)


func _steady_game() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	for resident: VaultResident in game.residents:
		resident.needs.food = 80.0
		resident.needs.rest = 80.0
		resident.needs.mood = 60.0
	return game


func _line(game: VaultGame) -> String:
	return game.player_orders.format_crew_grade(game.player_orders.crew_grade())


func _open_then_seal(game: VaultGame) -> void:
	game.breach_system.deserialize({
		"phase": BreachSystem.Phase.SEALED,
		"patch_delivered": BreachSystem.PATCH_COST,
		"patch_work_left": 0.0,
		"warning_acknowledged": true,
		"warning_emitted": true,
		"open_emitted": true,
		"sealed_emitted": true,
	}, 200.0)


func _test_full_marks() -> void:
	var game := _steady_game()
	_assert_equal(game.residents.size(), 4, "starting crew of four")
	_assert_equal(_line(game), FULL, "full marks line")
	game.player_orders.show_outcome(true, game.get_alive_count())
	_assert_true(game.player_orders.outcome_grade.visible, "grade shown on the win screen")
	_assert_equal(game.player_orders.outcome_grade.text, FULL, "win screen shows the full-marks line")
	_assert_true(game.player_orders.outcome_text.text.ends_with("Your local victory state has been saved."), "win body text unchanged")
	game.player_orders.show_outcome(true, game.get_alive_count())
	_assert_equal(game.player_orders.outcome_grade.text, FULL, "repeat show replaces, never appends")
	_dispose(game)


func _test_single_failures() -> void:
	var game := _steady_game()
	game.residents[3].kill()
	_assert_equal(_line(game), "CREW RATING ★★☆ · 1 of 4 crew lost", "one death")
	game.residents[2].kill()
	_assert_equal(_line(game), "CREW RATING ★★☆ · 2 of 4 crew lost", "two deaths still one star")
	_dispose(game)

	game = _steady_game()
	_open_then_seal(game)
	_assert_equal(_line(game), "CREW RATING ★★☆ · hatch opened", "hatch opened")
	_dispose(game)

	game = _steady_game()
	game.residents[0].needs.mood = 5.0
	game.residents[1].needs.mood = 9.0
	_assert_equal(_line(game), "CREW RATING ★★☆ · 2 survivors at BREAK RISK", "two at BREAK RISK")
	game.residents[1].needs.mood = 60.0
	_assert_equal(_line(game), "CREW RATING ★★☆ · 1 survivor at BREAK RISK", "singular BREAK RISK")
	game.residents[2].needs.food = 10.0
	_assert_equal(_line(game), "CREW RATING ★★☆ · 1 survivor at BREAK RISK · 1 survivor CRITICAL", "BREAK RISK and CRITICAL share one star")
	_dispose(game)

	game = _steady_game()
	game.residents[0].needs.food = 10.0
	game.residents[0].needs.rest = 5.0
	game.residents[0].needs.mood = 0.0
	game.residents[1].needs.rest = 5.0
	_assert_equal(_line(game), "CREW RATING ★★☆ · 1 survivor at BREAK RISK · 2 survivors CRITICAL", "a resident counts once as CRITICAL")
	_dispose(game)

	game = _steady_game()
	game.residents[3].needs.mood = 0.0
	game.residents[3].needs.food = 0.0
	game.residents[3].kill()
	_assert_equal(_line(game), "CREW RATING ★★☆ · 1 of 4 crew lost", "the dead are never BREAK RISK or CRITICAL")
	_dispose(game)


func _test_boundaries() -> void:
	var game := _steady_game()
	var r: VaultResident = game.residents[0]
	r.needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD
	_assert_equal(int(game.player_orders.crew_grade()["stars"]), 2, "mood 9 is BREAK RISK")
	r.needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD + 0.0001
	_assert_equal(int(game.player_orders.crew_grade()["stars"]), 3, "mood 9.0001 is not")
	r.needs.food = 19.9999
	_assert_equal(int(game.player_orders.crew_grade()["stars"]), 2, "food 19.9999 is CRITICAL")
	r.needs.food = 20.0
	_assert_equal(int(game.player_orders.crew_grade()["stars"]), 3, "food 20 is not")
	r.needs.rest = 14.9999
	_assert_equal(int(game.player_orders.crew_grade()["stars"]), 2, "rest 14.9999 is CRITICAL")
	r.needs.rest = 15.0
	_assert_equal(int(game.player_orders.crew_grade()["stars"]), 3, "rest 15 is not")
	_dispose(game)


func _test_floor() -> void:
	var game := _steady_game()
	game.residents[3].kill()
	_open_then_seal(game)
	_assert_equal(_line(game), "CREW RATING ★☆☆ · 1 of 4 crew lost · hatch opened", "two failures leave one star")
	game.residents[0].needs.mood = 1.0
	_assert_equal(_line(game), "CREW RATING ★☆☆ · 1 of 4 crew lost · hatch opened · 1 survivor at BREAK RISK", "three failures floor at one star")
	game.player_orders.show_outcome(true, game.get_alive_count())
	_assert_equal(game.player_orders.outcome_grade.get_theme_color("font_color"), Color("ef6860"), "one star reads red")
	_dispose(game)


func _test_hatch_history() -> void:
	var game := _steady_game()
	_assert_true(not game.breach_system.has_opened(), "fresh wing: hatch never opened")
	_open_then_seal(game)
	_assert_true(game.breach_system.is_sealed() and game.breach_system.has_opened(), "opened then sealed still counts")
	game.breach_system.deserialize({}, 200.0)
	_assert_true(game.breach_system.is_sealed() and not game.breach_system.has_opened(), "legacy synthesized seal is not an opening")
	game.breach_system.reset()
	_assert_true(not game.breach_system.has_opened(), "reset clears history")
	_dispose(game)

	game = _spawn_game()
	game.begin_shift()
	for resident: VaultResident in game.residents:
		resident.set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
		resident.set_work_priority("craft", VaultResident.PRIORITY_DISABLED)
	game.step_simulation(BreachSystem.WARNING_AT_SECONDS + BreachSystem.GRACE_SECONDS + 1.0)
	_assert_true(game.breach_system.is_open() and game.breach_system.has_opened(), "a real unpatched hatch opens")
	_assert_true(game.apply_snapshot(JSON.parse_string(JSON.stringify(game.create_snapshot()))), "open wing reloads")
	_assert_true(game.breach_system.has_opened(), "opened flag survives a reload")
	_dispose(game)


func _test_loss_unchanged() -> void:
	var game := _steady_game()
	var orders := game.player_orders
	var loss_pos := orders.outcome_panel.position
	var loss_size := orders.outcome_panel.size
	orders.show_outcome(false, 0)
	var loss_text := orders.outcome_text.text
	orders.show_outcome(true, 4)
	orders.show_outcome(false, 0)
	_assert_equal(orders.outcome_text.text, loss_text, "loss text identical after a win was shown")
	_assert_true(not orders.outcome_grade.visible and orders.outcome_grade.text == "", "loss hides and clears the grade")
	_assert_equal(orders.outcome_title.text, "WING LOST", "loss title")
	_assert_true(orders.outcome_text.text.begins_with("No residents remain alive."), "loss body unchanged")
	_assert_equal(orders.outcome_panel.position, loss_pos, "panel position never moved")
	_assert_equal(orders.outcome_panel.size, loss_size, "panel size never changed")
	_dispose(game)


func _test_real_win() -> void:
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
	game.step_simulation(DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE + VaultGame.SIMULATION_TICK)
	_assert_true(game.ended and game.outcome == "win", "managed wing wins")
	var orders := game.player_orders
	var shown := orders.outcome_grade.text
	print("REAL WIN GRADE: ", shown)
	_assert_true(orders.outcome_grade.visible and shown == _line(game), "real win shows its derived grade")
	_assert_equal(orders.outcome_title.text, "SEAL STABILIZED", "win title unchanged")
	var before := JSON.stringify(game.create_snapshot())
	orders.show_outcome(true, game.get_alive_count())
	_assert_equal(JSON.stringify(game.create_snapshot()), before, "rendering the grade does not change the snapshot")
	_assert_true(game.apply_snapshot(JSON.parse_string(before)), "won snapshot reloads")
	_assert_equal(game.player_orders.outcome_grade.text, shown, "reload shows the same grade")
	_dispose(game)
