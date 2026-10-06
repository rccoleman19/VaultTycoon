extends "res://tests/test_runner.gd"

const T := JobSystem.JobType
const EXPECTED_HELP := "Like RimWorld: click to cycle 1 (do first) → 2 → 3 → 4 → OFF. Same rank goes by job, not column: build, food, rubble, then digs; nearest first. Everyone starts at 3 for all four — auto work runs without opening this board. Draft/force is optional override. Hatch urgency beats ranks; OFF still blocks. HAUL = salvage + food."
const EXPECTED_EYEBROW := "WORK TAB // RANK 1 FIRST · TIES GO BY JOB"
const EXPECTED_TOOLTIP := "RimWorld-style work tab: ranks 1 (highest) to 4, OFF never claims. Same rank goes by job: build, food, rubble, then digs. Defaults already on at 3 — open only to specialize."
# 680 px panel − 2×22 margin − 2×3 border.
const HELP_TEXT_WIDTH := 630
const EXPECTED_CHECKLIST_LINE := "[color=#8faeb7][OPTIONAL][/color]  PRIORITIES [P]: 1 highest · 4 lowest · OFF disabled · same rank: build, food, rubble, then digs (defaults 3)"
const STALE_CLAIMS := ["Dig→Haul→Craft→Cook", "Dig·Haul·Craft·Cook", "left to right", "left→right", "Left-to-right", "LEFT → RIGHT", "WITHIN EACH RANK"]


func _run() -> void:
	_run_case("work board help states the job-type tie order", _test_board_help_text)
	_run_case("board eyebrow and roster tooltip drop the column-order claim", _test_eyebrow_and_tooltip)
	_run_case("Help checklist states the job tie order", _test_help_checklist_line)
	_run_case("no work-board or Help text claims column order", _test_no_stale_column_claims)
	_run_case("equal ranks follow the documented job order", _test_equal_rank_job_order)
	_run_case("the help text still wraps to four lines", _test_board_fits)
	_run_case("while the hatch is short of patch salvage, rubble then new digs jump ahead at equal rank", _test_hatch_shortfall_order)
	_run_case("meal hauls count as needed at exactly two per living resident", _test_meal_threshold_boundary)
	print("WORK TIE HELP TEXT TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _test_board_help_text() -> void:
	var game := _spawn_game()
	var help := game.player_orders.work_priorities_panel.find_child("WorkPrioritiesHelp", true, false) as Label
	_assert_true(help != null, "work board exposes its help label as WorkPrioritiesHelp")
	if help != null:
		_assert_equal(help.text, EXPECTED_HELP, "work board help text matches the scheduler")
	_dispose(game)


func _test_eyebrow_and_tooltip() -> void:
	var game := _spawn_game()
	var eyebrow := game.player_orders.work_priorities_panel.find_child("WorkPrioritiesEyebrow", true, false) as Label
	_assert_true(eyebrow != null, "work board exposes its eyebrow as WorkPrioritiesEyebrow")
	if eyebrow != null:
		_assert_equal(eyebrow.text, EXPECTED_EYEBROW, "eyebrow states rank first, ties by job")
	_assert_equal(game.player_orders.work_priorities_button.tooltip_text, EXPECTED_TOOLTIP, "roster PRIORITIES tooltip states the job tie order")
	_dispose(game)


func _test_help_checklist_line() -> void:
	var game := _spawn_game()
	game.begin_shift()
	game.player_orders._refresh_checklist()
	var lines := game.player_orders.checklist.text.split("\n")
	_assert_true(EXPECTED_CHECKLIST_LINE in lines, "reopened Help lists the priorities line with the job tie order")
	_assert_true("PRIORITIES [P]: 1 highest · 4 lowest · OFF disabled" in game.player_orders.checklist.text, "the runner's checklist prefix is preserved")
	_dispose(game)


func _test_no_stale_column_claims() -> void:
	var game := _spawn_game()
	game.begin_shift()
	game.player_orders.refresh()
	game.player_orders._refresh_checklist()
	var texts: Array[String] = [game.player_orders.work_priorities_button.tooltip_text, game.player_orders.checklist.text]
	_collect_texts(game.player_orders.work_priorities_overlay, texts)
	var hits := 0
	for text: String in texts:
		for stale: String in STALE_CLAIMS:
			if stale in text:
				hits += 1
				printerr("stale column claim: %s in %s" % [stale, text])
	_assert_true(texts.size() > 20, "collected the board's visible labels, buttons, and tooltips")
	_assert_equal(hits, 0, "no board text claims a left-to-right column order")
	_dispose(game)


func _test_equal_rank_job_order() -> void:
	# [offered jobs, expected claim, message]. All four categories at rank 3.
	var scenarios := [
		[["supply", "build"], T.SUPPLY_BUILD, "blueprint supply comes before assembly"],
		[["build", "cook"], T.BUILD, "assembly comes before food"],
		[["build", "raw"], T.BUILD, "assembly comes before food hauling"],
		[["cook", "rubble"], T.COOK, "cooking comes before rubble"],
		[["raw", "rubble"], T.HAUL_RAW_FOOD, "food hauling comes before rubble"],
		[["low_meal", "rubble"], T.HAUL_MEAL, "needed meals come before rubble"],
		[["rubble", "dig"], T.HAUL_RUBBLE, "rubble comes before new digs"],
		[["dig", "spare_meal"], T.DIG, "spare meals wait until after digs"],
		[["dig", "build"], T.BUILD, "the leftmost DIG column does not go first"],
		[["dig", "cook"], T.COOK, "the rightmost COOK column does not go last"],
	]
	for scenario: Array in scenarios:
		var game := _equal_rank_game()
		var ari: VaultResident = game.residents[0]
		var offers: Array = scenario[0]
		if "dig" in offers:
			var dig_cell := MapGrid.CHAMBER.position + Vector2i.LEFT
			_assert_true(game.map_grid.queue_dig(dig_cell), "fixture queues a reachable dig")
			game.job_system.queue_dig(dig_cell)
		if "rubble" in offers:
			game.job_system.queue_rubble(ari.get_cell(game.map_grid), 3)
		if "build" in offers:
			_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(26, 19)), "fixture places a bunk blueprint")
			var blueprint := game.get_building_at(Vector2i(26, 19))
			if blueprint == null:
				_assert_true(false, "fixture finds the bunk blueprint")
				_dispose(game)
				continue
			game.job_system.cancel_building(blueprint.building_id)
			blueprint.add_delivery(blueprint.get_cost())
			game.job_system.queue_building(blueprint)
		if "supply" in offers:
			_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(26, 17)), "fixture places an unsupplied blueprint")
		if "cook" in offers:
			_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(23, 12))
			_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(25, 12))
			game.power_grid.recalculate(game.buildings)
		if "raw" in offers:
			game.food_system.raw_food = 0
			game.job_system.queue_raw_food(Vector2i(21, 12), 2)
		if "low_meal" in offers:
			game.food_system.meals = 0
			game.job_system.queue_meals(Vector2i(22, 12), 2)
		if "spare_meal" in offers:
			game.food_system.meals = game.get_alive_count() * 2 + 1
			game.job_system.queue_meals(Vector2i(22, 12), 2)
		game.job_system.advance(0.0)
		_assert_equal(ari.current_job_type, int(scenario[1]), str(scenario[2]))
		_dispose(game)


func _test_board_fits() -> void:
	# The old help wrapped to 4 lines at the same 630 px label width.
	var game := _spawn_game()
	var help := game.player_orders.work_priorities_panel.find_child("WorkPrioritiesHelp", true, false) as Label
	_assert_true(help != null, "fit check finds WorkPrioritiesHelp")
	if help != null:
		var probe := Label.new()
		probe.autowrap_mode = help.autowrap_mode
		game.player_orders.add_child(probe)
		probe.size = Vector2(HELP_TEXT_WIDTH, 10.0)
		probe.text = help.text
		_assert_true(probe.get_line_count() <= 4, "help text wraps to at most 4 lines at %d px (got %d)" % [HELP_TEXT_WIDTH, probe.get_line_count()])
		probe.free()
	_dispose(game)


func _test_hatch_shortfall_order() -> void:
	# [offered jobs, salvage, patch already delivered, Ari hauls?, expected claim, message].
	# Shortfall = patch cost - delivered - in transit - salvage; promotion only while it is > 0.
	var cost := BreachSystem.PATCH_COST
	var scenarios := [
		[["rubble", "build"], 0, 0, true, T.HAUL_RUBBLE, "short hatch: rubble jumps ahead of assembly"],
		[["rubble", "cook"], 0, 0, true, T.HAUL_RUBBLE, "short hatch: rubble jumps ahead of cooking"],
		[["rubble", "low_meal"], 0, 0, true, T.HAUL_RUBBLE, "short hatch: rubble jumps ahead of needed meals"],
		[["rubble", "dig"], 0, 0, true, T.HAUL_RUBBLE, "short hatch: rubble still comes before new digs"],
		[["dig", "build"], 0, 0, true, T.DIG, "short hatch: new digs jump ahead of assembly"],
		[["dig", "raw"], 0, 0, true, T.DIG, "short hatch: new digs jump ahead of food hauling"],
		[["dig", "build"], cost - 1, 0, false, T.DIG, "one salvage short: digs still jump ahead of assembly"],
		[["dig", "build"], cost, 0, false, T.BUILD, "salvage covers the patch: assembly comes before digs again"],
		[["dig", "cook"], cost, 0, false, T.COOK, "salvage covers the patch: cooking comes before digs again"],
		[["dig", "build"], cost - 2, 2, false, T.BUILD, "delivered + salvage cover the patch: normal order"],
	]
	for scenario: Array in scenarios:
		var game := _equal_rank_game()
		var ari: VaultResident = game.residents[0]
		if not bool(scenario[3]):
			# Haul OFF keeps Ari off the emergency supply job when salvage is on hand.
			_assert_true(ari.set_work_priority("haul", VaultResident.PRIORITY_DISABLED), "fixture turns Ari's Haul OFF")
		game.breach_system.advance(0.0, BreachSystem.WARNING_AT_SECONDS)
		_assert_true(game.breach_system.is_response_active(), "fixture: hatch response is active")
		if int(scenario[2]) > 0:
			_assert_equal(game.breach_system.add_delivery(int(scenario[2])), int(scenario[2]), "fixture: part of the patch is already delivered")
		game.food_system.salvage = int(scenario[1])
		_assert_true(game.breach_system.needs_supply(), "fixture: hatch still needs supply")
		if not _stage_offers(game, ari, scenario[0]):
			_dispose(game)
			continue
		game.job_system.advance(0.0)
		_assert_equal(ari.current_job_type, int(scenario[4]), str(scenario[5]))
		_dispose(game)
	# Salvage already in a hauler's hands counts too: [salvage left on hand, expected, message].
	_assert_transit_scenario(BreachSystem.PATCH_COST - 2, T.BUILD, "2 in transit + salvage cover the patch: assembly comes before digs")
	_assert_transit_scenario(BreachSystem.PATCH_COST - 3, T.DIG, "2 in transit + salvage one short: digs jump ahead of assembly")


func _assert_transit_scenario(salvage_left: int, expected: int, message: String) -> void:
	var game := _equal_rank_game()
	var ari: VaultResident = game.residents[0]
	var bo: VaultResident = game.residents[1]
	_assert_true(ari.set_work_priority("haul", VaultResident.PRIORITY_DISABLED), "transit fixture turns Ari's Haul OFF")
	_assert_true(bo.set_work_priority("haul", 1), "transit fixture gives Bo Haul at rank 1")
	game.breach_system.advance(0.0, BreachSystem.WARNING_AT_SECONDS)
	game.food_system.salvage = 2
	for _tick: int in 200:
		game.job_system.advance(VaultGame.SIMULATION_TICK)
		if bo.carrying > 0:
			break
	_assert_equal(bo.current_job_type, JobSystem.JobType.SUPPLY_BREACH, "transit fixture: Bo hauls hatch supply")
	_assert_equal(bo.carrying, 2, "transit fixture: Bo carries 2 salvage")
	_assert_equal(game.job_system._breach_supply_in_transit(), 2, "transit fixture: 2 salvage in transit")
	_assert_equal(game.breach_system.patch_delivered, 0, "transit fixture: nothing delivered yet")
	_assert_true(ari.current_job_id < 0, "transit fixture: Ari is idle before the offers")
	game.food_system.salvage = salvage_left
	if not _stage_offers(game, ari, ["dig", "build"]):
		_dispose(game)
		return
	game.job_system.advance(0.0)
	_assert_equal(ari.current_job_type, expected, message)
	_dispose(game)


func _test_meal_threshold_boundary() -> void:
	# [meals as a multiple of living crew (+ offset), kill one crewmate?, expected claim, message]. All vs a reachable dig.
	var scenarios := [
		[0, false, T.HAUL_MEAL, "meals == 2 x living crew: meal haul is still needed and beats digs"],
		[1, false, T.DIG, "meals == 2 x living crew + 1: spare meals wait for digs (control)"],
		[0, true, T.HAUL_MEAL, "one crewmate dead, meals == 2 x living: still needed"],
		[1, true, T.DIG, "one crewmate dead, meals == 2 x living + 1: spare even though it is under 2 x roster"],
	]
	for scenario: Array in scenarios:
		var game := _equal_rank_game()
		var ari: VaultResident = game.residents[0]
		if bool(scenario[1]):
			var victim: VaultResident = game.residents[game.residents.size() - 1]
			victim.kill()
			_assert_equal(game.get_alive_count(), game.residents.size() - 1, "fixture: one crewmate is dead")
		game.food_system.meals = game.get_alive_count() * 2 + int(scenario[0])
		if bool(scenario[1]) and int(scenario[0]) == 1:
			_assert_true(game.food_system.meals <= game.residents.size() * 2, "fixture: meals are within 2 x the full roster")
		if not _stage_offers(game, ari, ["meal", "dig"]):
			_dispose(game)
			continue
		game.job_system.advance(0.0)
		_assert_equal(ari.current_job_type, int(scenario[2]), str(scenario[3]))
		_dispose(game)


func _stage_offers(game: VaultGame, ari: VaultResident, offers: Array) -> bool:
	if "dig" in offers:
		var dig_cell := MapGrid.CHAMBER.position + Vector2i.LEFT
		_assert_true(game.map_grid.queue_dig(dig_cell), "fixture queues a reachable dig")
		game.job_system.queue_dig(dig_cell)
	if "rubble" in offers:
		game.job_system.queue_rubble(ari.get_cell(game.map_grid), 3)
	if "build" in offers:
		_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(26, 19)), "fixture places a bunk blueprint")
		var blueprint := game.get_building_at(Vector2i(26, 19))
		if blueprint == null:
			_assert_true(false, "fixture finds the bunk blueprint")
			return false
		game.job_system.cancel_building(blueprint.building_id)
		blueprint.add_delivery(blueprint.get_cost())
		game.job_system.queue_building(blueprint)
	if "cook" in offers:
		_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(23, 12))
		_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(25, 12))
		game.power_grid.recalculate(game.buildings)
	if "raw" in offers:
		game.food_system.raw_food = 0
		game.job_system.queue_raw_food(Vector2i(21, 12), 2)
	if "low_meal" in offers:
		game.food_system.meals = 0
		game.job_system.queue_meals(Vector2i(22, 12), 2)
	if "meal" in offers:
		game.job_system.queue_meals(Vector2i(22, 12), 2)
	return true


func _equal_rank_game() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
		resident.sleeping = false
		resident.bed_id = -1
		resident.stress_break_left = 0.0
		game.job_system.release_resident(resident)
		for work_type: String in VaultResident.WORK_TYPES:
			if not resident.set_work_priority(work_type, VaultResident.PRIORITY_DISABLED):
				_assert_true(false, "fixture disables %s for %s" % [work_type, resident.resident_name])
	var ari: VaultResident = game.residents[0]
	for work_type: String in VaultResident.WORK_TYPES:
		if not ari.set_work_priority(work_type, 3):
			_assert_true(false, "fixture sets Ari's %s to rank 3" % work_type)
	return game


func _collect_texts(node: Node, texts: Array[String]) -> void:
	if node == null:
		_assert_true(false, "text sweep finds its node")
		return
	if node is Label:
		texts.append((node as Label).text)
	if node is Button:
		texts.append((node as Button).text)
	if node is Control and not (node as Control).tooltip_text.is_empty():
		texts.append((node as Control).tooltip_text)
	for child: Node in node.get_children():
		_collect_texts(child, texts)
