extends "res://tests/test_runner.gd"

# Air fund tip: an Air Recycler blueprint the stockpile cannot pay for used to say
# "THEY finish the Air Recycler" while nobody could, and the wing suffocated
# following it. Now a salvage-short Air blueprint gets the same mark-rock / fund
# tip the Charge Node already uses; a funded one keeps the finish tip.

const FINISH_AIR := "Next: YOU leave Haul + Craft on · THEY finish the Air Recycler"
const FINISH_AIR_HELP := "Keep Haul + Craft above OFF so crew supply and finish the Air Recycler blueprint."
const FUND_AIR_COVERED := "Next: YOU leave Dig + Haul on · THEY fund the Air Recycler"
const AIR_CELL := Vector2i(25, 12)
const RECOVERY_BOUND := 120.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_case("salvage-short Air blueprint names the rock to mark", _test_short_tip)
	_case("funded Air keeps the finish tip; queued digs read as covered", _test_funded_and_covered)
	_case("following the tip funds and finishes the Air Recycler", _test_real_recovery)
	print("AIR FUND TIP TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(0 if _failure_count == 0 else 1)


func _case(label: String, test: Callable) -> void:
	_case_count += 1
	_current_case = label
	var before := _failure_count
	print("[TEST] %s" % label)
	test.call()
	print("[%s] %s" % ["PASS" if before == _failure_count else "FAIL", label])


func _fund_text(rock: int) -> String:
	return "Next: YOU mark %d rock [E] · THEY fund the Air Recycler" % rock


func _fund_help(short: int) -> String:
	return "The Air Recycler blueprint is %d salvage short. Each dug rock tile yields 3 salvage once hauled." % short


func _assert_step(game: VaultGame, text: String, tool: String, help: String) -> void:
	var step: Dictionary = game.player_orders._primary_next_step()
	_assert_equal(step["text"], text, "recommendation text")
	_assert_equal(step["tool"], tool, "recommendation tool")
	_assert_equal(step["help"], help, "recommendation help")


func _air_game() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	game.user_paused = true
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
		resident.drafted = false
		resident.sleeping = false
		resident.bed_id = -1
		resident.medical_bed_id = -1
	game.food_system.meals = 100
	for x in range(17, 29):
		var cell := Vector2i(x, 10)
		_assert_true(game.map_grid.queue_dig(cell) and game.map_grid.apply_dig_work(cell, 8.0), "fixture carves floor")
	game.job_system.jobs = game.job_system.jobs.filter(func(job: Dictionary) -> bool: return int(job.type) not in [JobSystem.JobType.DIG, JobSystem.JobType.HAUL_RUBBLE])
	_assert_equal(game.job_system.get_uncredited_rubble(), 0, "fixture has no uncredited rubble")
	for pair in [[VaultBuilding.Kind.BED, Vector2i(20, 12)], [VaultBuilding.Kind.BED, Vector2i(21, 12)], [VaultBuilding.Kind.GENERATOR, Vector2i(22, 12)], [VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12)], [VaultBuilding.Kind.KITCHEN, Vector2i(24, 12)]]:
		_add_completed_building(game, int(pair[0]), pair[1])
	game.breach_system.phase = BreachSystem.Phase.SEALED
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.patch_work_left = 0.0
	game.power_grid.recalculate(game.buildings)
	_assert_true(game.place_blueprint(VaultBuilding.Kind.AIR_RECYCLER, AIR_CELL), "Air blueprint placed")
	_assert_true(game.map_grid.dig_marks.is_empty(), "fixture has no queued marks")
	return game


func _test_short_tip() -> void:
	var game := _air_game()
	var air := game.get_building_at(AIR_CELL)
	game.food_system.salvage = 0
	_assert_step(game, _fund_text(5), "dig", _fund_help(14))
	game.active_tool = "select"
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, _fund_text(5), "HUD shows the Air fund tip")
	game.food_system.salvage = 8
	_assert_step(game, _fund_text(2), "dig", _fund_help(6))
	game.food_system.salvage = 0
	_assert_equal(air.add_delivery(10), 10, "Air partly supplied")
	_assert_step(game, _fund_text(2), "dig", _fund_help(4))
	_assert_true(game.place_blueprint(VaultBuilding.Kind.AIR_RECYCLER, Vector2i(26, 12)), "second Air blueprint placed")
	_assert_step(game, _fund_text(6), "dig", _fund_help(18))
	_dispose(game)


func _test_funded_and_covered() -> void:
	var game := _air_game()
	var air := game.get_building_at(AIR_CELL)
	game.food_system.salvage = 14
	_assert_step(game, FINISH_AIR, "select", FINISH_AIR_HELP)
	game.food_system.salvage = 48
	_assert_step(game, FINISH_AIR, "select", FINISH_AIR_HELP)
	game.food_system.salvage = 0
	_assert_equal(air.add_delivery(14), 14, "Air fully supplied")
	_assert_step(game, FINISH_AIR, "select", FINISH_AIR_HELP)
	_dispose(game)
	game = _air_game()
	game.food_system.salvage = 0
	game.set_tool("dig")
	for x in range(17, 22):
		_assert_true(game.issue_order(Vector2i(x, 9)), "reachable rock marked")
	game.set_tool("select")
	_assert_step(game, FUND_AIR_COVERED, "select", _fund_help(14))
	_dispose(game)


func _test_real_recovery() -> void:
	var game := _air_game()
	var air := game.get_building_at(AIR_CELL)
	game.food_system.salvage = 0
	game.user_paused = false
	var tip: Dictionary = game.player_orders._primary_next_step()
	_assert_equal(tip.text, _fund_text(5), "live tip asks for five rock")
	var count := int(String(tip.text).split(" ")[3])
	game.set_tool("dig")
	for x in range(17, 17 + count):
		_assert_true(game.issue_order(Vector2i(x, 9)), "ordinary dig order from the tip")
	game.set_tool("select")
	var ticks := 0
	var funded_at := -1.0
	var complete_at := -1.0
	var ordinary := true
	var seen := {}
	while ticks < int(round(RECOVERY_BOUND / VaultGame.SIMULATION_TICK)) and not air.complete and not game.ended:
		seen[String(game.player_orders._primary_next_step().text)] = true
		game.step_simulation(VaultGame.SIMULATION_TICK)
		ticks += 1
		for resident: VaultResident in game.residents:
			ordinary = ordinary and not resident.drafted and not resident.is_forced_job
		if funded_at < 0.0 and game.player_orders._salvage_shortfall(VaultBuilding.Kind.AIR_RECYCLER) == 0:
			funded_at = ticks * VaultGame.SIMULATION_TICK
		if air.complete:
			complete_at = ticks * VaultGame.SIMULATION_TICK
	_assert_true(air.complete, "ordinary Dig/Haul/Craft finishes the Air Recycler within %ds" % int(RECOVERY_BOUND))
	_assert_true(ordinary, "recovery stays undrafted and unforced")
	_assert_true(funded_at > 0.0 and complete_at >= funded_at, "funded before complete")
	for text: String in seen:
		_assert_true(text in [FUND_AIR_COVERED, FINISH_AIR], "recovery tip is fund-covered or finish: %s" % text)
	_assert_true(FUND_AIR_COVERED in seen and FINISH_AIR in seen, "recovery shows covered then finish")
	game.power_grid.recalculate(game.buildings)
	_assert_true(air.powered, "finished Air is powered")
	print("Air fund recovery: funded %.1fs, complete %.1fs" % [funded_at, complete_at])
	_dispose(game)
