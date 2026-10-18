extends "res://tests/test_runner.gd"

# Win-screen crew rating (QA 2026-10-18b #8) and loss cause (QA 2026-10-18c #1).
const FULL := "CREW RATING ★★★ · whole crew home, hatch held, crew steady"
const HATCH_SAVE_TEST_PATH := "user://headless_crew_grade_hatch.json"


func _run() -> void:
	_run_case("a steady full crew with a held hatch earns three stars", _test_full_marks)
	_run_case("each failed check costs one star with its reason", _test_single_failures)
	_run_case("BREAK RISK and CRITICAL boundaries match the HUD", _test_boundaries)
	_run_case("a win never drops below one star and lists every reason", _test_floor)
	_run_case("hatch history survives the seal; a legacy save is not penalized", _test_hatch_history)
	_run_case("legacy hatch history is stable across re-save and records a real opening", _test_legacy_hatch_round_trip)
	_run_case("the loss screen hides the grade and keeps its layout", _test_loss_unchanged)
	_run_case("a real managed win grades on screen and after a reload", _test_real_win)
	_run_case("the loss panel names each cause with one hint", _test_loss_causes)
	_run_case("a real idle loss reads starved and survives a reload", _test_real_idle_loss)
	_run_case("a real air loss reads suffocated", _test_real_suffocation_loss)

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


# Loss cause (QA 2026-10-18c #1).
const STARVED_HINT := "Next wing: keep a Grow Tray and Nutrient Station powered, with Cook and Haul on, before the starting meals run out."
const REST_HINT := "Next wing: build Bunks and undraft tired residents so they can sleep."
const AIR_HINT := "Next wing: keep an Air Recycler powered and patch the hatch before it opens."
const UNKNOWN_HINT := "Next wing: pause when health falls and check food, rest, mood and oxygen."


func _cause(game: VaultGame) -> String:
	return game.player_orders.format_loss_cause(game.player_orders.loss_cause())


func _die(resident: VaultResident) -> void:
	resident.needs.health = 0.0
	resident.kill()


func _test_loss_causes() -> void:
	var game := _steady_game()
	_assert_equal(_cause(game), "", "nobody dead: no cause line")
	var r: Array = game.residents
	r[0].needs.food = 0.0
	_die(r[0])
	_assert_equal(_cause(game), "LIKELY CAUSE · 1 starved\n" + STARVED_HINT, "starved")
	r[1].needs.rest = 0.0
	_die(r[1])
	r[2].needs.rest = 0.0
	_die(r[2])
	_assert_equal(_cause(game), "LIKELY CAUSE · 1 starved · 2 exhausted\n" + REST_HINT, "largest count picks the hint")
	r[3].needs.mood = ResidentNeeds.SEVERE_MOOD_THRESHOLD
	r[3].needs.rest = 0.0
	r[3].needs.food = 0.0001
	_die(r[3])
	_assert_equal(_cause(game), "LIKELY CAUSE · 1 starved · 3 exhausted\n" + REST_HINT, "rest outranks mood; food above 0 is not starvation")
	r[3].needs.rest = 0.0001
	_assert_true(_cause(game).contains("1 in despair"), "mood at the severe line is despair")
	r[3].needs.mood = ResidentNeeds.SEVERE_MOOD_THRESHOLD + 0.0001
	r[1].needs.rest = 50.0
	_assert_equal(_cause(game), "LIKELY CAUSE · 1 starved · 1 exhausted · 2 unknown\n" + UNKNOWN_HINT, "no evidence and O2 fine: unknown")
	game.oxygen_system.oxygen = OxygenSystem.CRITICAL_OXYGEN_THRESHOLD + 0.0001
	_assert_true(not _cause(game).contains("suffocated"), "O2 above 15 is not suffocation")
	game.oxygen_system.oxygen = OxygenSystem.CRITICAL_OXYGEN_THRESHOLD
	_assert_equal(_cause(game), "LIKELY CAUSE · 1 starved · 1 exhausted · 2 suffocated\n" + AIR_HINT, "low O2 only explains corpses without need evidence")
	r[1].needs.rest = 0.0
	_assert_equal(_cause(game), "LIKELY CAUSE · 1 starved · 2 exhausted · 1 suffocated\n" + REST_HINT, "frozen needs outrank current O2")
	r[2].needs.rest = 60.0
	r[2].needs.food = 0.0
	_assert_equal(_cause(game), "LIKELY CAUSE · 2 starved · 1 exhausted · 1 suffocated\n" + STARVED_HINT, "tie-free recount")
	r[3].needs.rest = 0.0
	_assert_equal(_cause(game), "LIKELY CAUSE · 2 starved · 2 exhausted\n" + STARVED_HINT, "ties keep the cause order")
	var healthy_kill := _steady_game()
	healthy_kill.residents[0].needs.food = 0.0
	healthy_kill.residents[0].kill()
	_assert_equal(_cause(healthy_kill), "LIKELY CAUSE · 1 unknown\n" + UNKNOWN_HINT, "a corpse above 0 health is unknown")
	_dispose(healthy_kill)
	var orders := game.player_orders
	orders.show_outcome(false, 0)
	_assert_true(orders.outcome_grade.visible and orders.outcome_grade.text == _cause(game), "loss panel shows the cause")
	_assert_equal(orders.outcome_grade.get_theme_color("font_color"), Color("ef6860"), "cause reads red")
	_assert_true(orders.outcome_text.text.begins_with("No residents remain alive."), "loss body unchanged")
	_assert_equal(orders.outcome_title.text, "WING LOST", "loss title unchanged")
	var before := JSON.stringify(game.create_snapshot())
	orders.show_outcome(false, 0)
	_assert_equal(JSON.stringify(game.create_snapshot()), before, "rendering the cause changes nothing saved")
	orders.show_outcome(true, 0)
	_assert_true(orders.outcome_grade.text.begins_with("CREW RATING "), "a win replaces the cause line")
	_dispose(game)


func _test_real_idle_loss() -> void:
	var game := _spawn_game()
	game.begin_shift()
	var t := 0.0
	while not game.ended and t < 400.0:
		if game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged:
			game.acknowledge_breach_warning(true)
		game.user_paused = false
		game.step_simulation(1.0)
		t += 1.0
	_assert_true(game.ended and game.outcome == "loss", "an untouched wing is lost")
	var orders := game.player_orders
	print("REAL IDLE LOSS at %.0fs: %s" % [game.day_cycle.elapsed_seconds, orders.outcome_grade.text.replace("\n", " | ")])
	_assert_equal(orders.outcome_grade.text, "LIKELY CAUSE · 4 starved\n" + STARVED_HINT, "idle loss reads starved")
	var snap := JSON.stringify(game.create_snapshot())
	_assert_true(game.apply_snapshot(JSON.parse_string(snap)), "lost snapshot reloads")
	_assert_equal(game.player_orders.outcome_grade.text, "LIKELY CAUSE · 4 starved\n" + STARVED_HINT, "reload shows the same cause")
	_dispose(game)


func _test_real_suffocation_loss() -> void:
	var game := _spawn_game()
	game.begin_shift()
	for resident: VaultResident in game.residents:
		resident.set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
		resident.set_work_priority("craft", VaultResident.PRIORITY_DISABLED)
	game.oxygen_system.oxygen = 16.0
	var t := 0.0
	while not game.ended and t < 120.0:
		if game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged:
			game.acknowledge_breach_warning(true)
		game.user_paused = false
		game.step_simulation(1.0)
		t += 1.0
	_assert_true(game.ended and game.outcome == "loss", "a wing out of air is lost")
	print("REAL AIR LOSS at %.0fs: %s" % [game.day_cycle.elapsed_seconds, game.player_orders.outcome_grade.text.replace("\n", " | ")])
	_assert_equal(game.player_orders.outcome_grade.text, "LIKELY CAUSE · 4 suffocated\n" + AIR_HINT, "air loss reads suffocated")
	_dispose(game)


func _legacy_snapshot(source: VaultGame) -> Dictionary:
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(source.create_snapshot()))
	snapshot.erase("breach")
	var jobs: Dictionary = snapshot.get("jobs", {})
	jobs.erase("breach_supply")
	snapshot.jobs = jobs
	return snapshot


func _test_legacy_hatch_round_trip() -> void:
	_remove_test_save(HATCH_SAVE_TEST_PATH)
	var source := _steady_game()
	var won := _legacy_snapshot(source)
	_dispose(source)
	won.day = {
		"elapsed_seconds": DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE,
		"current_day": DayCycle.DAYS_TO_SURVIVE,
		"completed": true,
	}
	won.ended = true
	won.outcome = "win"
	var game := _spawn_game()
	_assert_true(bool(game.save_load.save_snapshot(won, HATCH_SAVE_TEST_PATH).ok), "legacy won snapshot writes")
	_assert_true(game.load_game(HATCH_SAVE_TEST_PATH), "legacy won snapshot loads")
	_assert_true(game.breach_system.is_sealed() and not game.breach_system.has_opened(), "migrated seal is not an opening")
	_assert_equal(game.player_orders.outcome_grade.text, FULL, "legacy win shows full marks")
	_assert_true(game.save_game(false, HATCH_SAVE_TEST_PATH), "legacy win re-saves")
	_assert_false(bool(game.breach_system.serialize().open_emitted), "re-save writes no invented opening")
	_dispose(game)
	game = _spawn_game()
	_assert_true(game.load_game(HATCH_SAVE_TEST_PATH), "re-saved legacy win reloads")
	_assert_true(game.breach_system.is_sealed() and not game.breach_system.has_opened(), "reload keeps the hatch held")
	_assert_equal(game.player_orders.outcome_grade.text, FULL, "reload keeps full marks")
	_dispose(game)

	source = _spawn_game()
	source.begin_shift()
	var early := _legacy_snapshot(source)
	_dispose(source)
	game = _spawn_game()
	_assert_true(bool(game.save_load.save_snapshot(early, HATCH_SAVE_TEST_PATH).ok), "early legacy snapshot writes")
	_assert_true(game.load_game(HATCH_SAVE_TEST_PATH), "early legacy snapshot loads")
	_assert_true(game.breach_system.phase == BreachSystem.Phase.DORMANT and not game.breach_system.has_opened(), "early legacy load starts unopened")
	game.begin_shift()
	for resident: VaultResident in game.residents:
		resident.set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
		resident.set_work_priority("craft", VaultResident.PRIORITY_DISABLED)
	game.step_simulation(BreachSystem.WARNING_AT_SECONDS + BreachSystem.GRACE_SECONDS + 1.0)
	_assert_true(game.breach_system.is_open() and game.breach_system.has_opened(), "a real opening after a legacy load counts")
	_assert_true(game.save_game(false, HATCH_SAVE_TEST_PATH), "opened legacy wing saves")
	_dispose(game)
	game = _spawn_game()
	_assert_true(game.load_game(HATCH_SAVE_TEST_PATH), "opened legacy wing reloads")
	_assert_true(game.breach_system.has_opened(), "the real opening survives the reload")
	_dispose(game)
	_remove_test_save(HATCH_SAVE_TEST_PATH)
