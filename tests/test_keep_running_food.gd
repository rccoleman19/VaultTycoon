extends "res://tests/test_runner.gd"

# Codex P2 on #111 (issuecomment-6268052674): past Day 7 the food chain keeps its recovery steps.
# A food emergency in a kept-running vault must show Cook / Haul / Grow Tray steps, not the Annex
# Next, before and after the Annex opens and across a save/load. Opening steps still give way.

const KR_FOOD_SAVE := "user://test_keep_running_food.json"
const ENABLE_COOK := "Next: Ari starving · YOU enable Cook · THEY cook"
const ENABLE_HAUL := "Next: Ari starving · YOU enable Haul · THEY deliver food"
const PLACE_TRAY := "Next: Ari starving · YOU place a Grow Tray · THEY grow"
const FINISH_TRAY := "Next: Ari starving · YOU leave Haul + Craft on · THEY finish the Grow Tray"
const ENABLE_TRAY := "Next: Ari starving · YOU enable a Grow Tray · THEY grow"
const PLACE_TRAY_CALM := "Next: YOU place Grow Tray · THEY haul output"


func _run() -> void:
	_run_case("Cook OFF in a food emergency shows Enable Cook, before and after the Annex", _test_cook_off)
	_run_case("Haul OFF with food awaiting delivery shows Enable Haul, before and after the Annex", _test_haul_off)
	_run_case("no Grow Tray in a food emergency asks for one, before and after the Annex", _test_no_tray)
	_run_case("an unfinished Grow Tray asks to finish it, before and after the Annex", _test_unfinished_tray)
	_run_case("a disabled Grow Tray asks to enable it, before and after the Annex", _test_disabled_tray)
	_run_case("a calm kept-running vault without a Grow Tray asks for one", _test_calm_no_tray)
	_run_case("the food step survives a save and load", _test_save_load)
	_run_case("once fed, the Next goes back to the Annex", _test_recovery)
	_run_case("a food emergency beats a latched Med Bed suggestion", _test_beats_latch)
	_run_case("opening steps (mark rock, first bunks) still give way to the keep-running Next", _test_opening_gives_way)
	print("")
	if _failure_count == 0:
		print("KEEP RUNNING FOOD TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("KEEP RUNNING FOOD TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _calm(game: VaultGame) -> void:
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0


func _won_running() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	game.day_cycle.deserialize({"elapsed_seconds": 70.0, "current_day": 2, "completed": false})
	game.breach_system.advance(0.0, 70.0)
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.apply_patch_work(100.0)
	game.job_system.rebuild_from_state()
	game.day_cycle.deserialize({"elapsed_seconds": 279.5, "current_day": 7, "completed": false})
	game.oxygen_system.oxygen = 100.0
	game.step_simulation(1.0)
	game.start_keep_running()
	_calm(game)
	return game


# A won vault with a powered Nutrient Station (and Rec + Med Bed so comfort is not pending).
# annex_open: finish the Annex first, so Eko and the payoff fixtures are in.
func _vault(annex_open: bool, with_tray := true) -> VaultGame:
	var game := _won_running()
	var cells: Array[Vector2i] = game._annex_free_cells(5)
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, cells[0])
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, cells[1])
	_add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, cells[2])
	_add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, cells[3])
	if with_tray:
		_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, cells[4])
	if annex_open:
		game.annex_meals = VaultGame.ANNEX_MEALS - 1
		game.annex_salvage = VaultGame.ANNEX_SALVAGE - 1
		game.food_system.meals = 20
		game.food_system.salvage = 20
		for i in 60:
			game._advance_annex(0.1)
		_calm(game)
		if not with_tray:
			for tray: VaultBuilding in _trays(game):
				game.deconstruct_building(tray.building_id)
	game.power_grid.recalculate(game.buildings)
	game.status_message_left = 0.0
	return game


func _trays(game: VaultGame) -> Array[VaultBuilding]:
	var trays: Array[VaultBuilding] = []
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY:
			trays.append(building)
	return trays


func _kitchen(game: VaultGame) -> VaultBuilding:
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.KITCHEN and building.complete:
			return building
	return null


# 0 meals, nothing raw, one resident at food 19 (critical).
func _starve(game: VaultGame) -> void:
	game.food_system.meals = 0
	game.food_system.raw_food = 0
	game.residents[0].needs.food = 19.0


func _set_work(game: VaultGame, work: String, priority: int) -> void:
	for resident: VaultResident in game.residents:
		resident.set_work_priority(work, priority)


func _label(open: bool) -> String:
	return "after the Annex" if open else "Annex building"


func _next(game: VaultGame) -> String:
	game.player_orders.refresh()
	return game.player_orders.objective_label.text


func _assert_food_next(game: VaultGame, expected: String, open: bool, what: String) -> void:
	_assert_true(game.keep_running and not game.ended, "%s (%s): still keeping running" % [what, _label(open)])
	_assert_equal(game.annex_done, open, "%s (%s): annex state" % [what, _label(open)])
	var primary: Dictionary = game.player_orders._primary_next_step()
	_assert_equal(str(primary.text), expected, "%s (%s): the diagnosis" % [what, _label(open)])
	_assert_equal(str(primary.get("kind", "")), "food", "%s (%s): classified as food chain" % [what, _label(open)])
	_assert_equal(_next(game), expected, "%s (%s): Next keeps the food step" % [what, _label(open)])
	_assert_false(_next(game) == str(game.player_orders.keep_running_default_step().text), "%s (%s): not the Annex/stable Next" % [what, _label(open)])
	game.status_message_left = 0.0
	game.active_tool = "select"
	game.player_orders.refresh()
	_assert_true(game.player_orders.tool_status.text.contains(str(primary.help)), "%s (%s): help line carries the step help" % [what, _label(open)])
	_assert_equal(str(game.player_orders.keep_running_next_step().tool), str(primary.tool), "%s (%s): suggested tool" % [what, _label(open)])


func _test_cook_off() -> void:
	for open: bool in [false, true]:
		var game := _vault(open)
		_starve(game)
		_set_work(game, "cook", VaultResident.PRIORITY_DISABLED)
		_assert_food_next(game, ENABLE_COOK, open, "Cook OFF")
		_dispose(game)


func _test_haul_off() -> void:
	for open: bool in [false, true]:
		var game := _vault(open)
		_starve(game)
		game.job_system.queue_meals(_kitchen(game).cell, 2)
		_set_work(game, "haul", VaultResident.PRIORITY_DISABLED)
		_assert_food_next(game, ENABLE_HAUL, open, "Haul OFF")
		_dispose(game)


func _test_no_tray() -> void:
	for open: bool in [false, true]:
		var game := _vault(open, false)
		_assert_equal(_trays(game).size(), 0, "no Grow Tray (%s)" % _label(open))
		_starve(game)
		_assert_food_next(game, PLACE_TRAY, open, "no Grow Tray")
		_dispose(game)


func _test_unfinished_tray() -> void:
	for open: bool in [false, true]:
		var game := _vault(open, false)
		_assert_true(game.place_blueprint(VaultBuilding.Kind.GROW_TRAY, game._annex_free_cells(1)[0]), "Grow Tray blueprint (%s)" % _label(open))
		game.status_message_left = 0.0
		_starve(game)
		_assert_food_next(game, FINISH_TRAY, open, "unfinished Grow Tray")
		_dispose(game)


func _test_disabled_tray() -> void:
	for open: bool in [false, true]:
		var game := _vault(open)
		for tray: VaultBuilding in _trays(game):
			game.toggle_building_enabled(tray.building_id)
		game.status_message_left = 0.0
		_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.GROW_TRAY), 0, "every Grow Tray off (%s)" % _label(open))
		_starve(game)
		_assert_food_next(game, ENABLE_TRAY, open, "disabled Grow Tray")
		_dispose(game)


func _carve(game: VaultGame, count: int) -> void:
	var dug := 0
	var guard := 0
	while dug < count and guard < 400:
		guard += 1
		for cell: Vector2i in game.map_grid.get_floor_cells():
			var done := false
			for n: Vector2i in game.map_grid.get_neighbors(cell):
				if n != BreachSystem.HATCH_CELL and game.map_grid.can_queue_dig(n) and game.map_grid.queue_dig(n):
					game.map_grid.apply_dig_work(n, 100.0)
					dug += 1
					done = true
					break
			if done:
				break


func _test_calm_no_tray() -> void:
	var game := _vault(false, false)
	_carve(game, 12)
	_add_completed_building(game, VaultBuilding.Kind.BED, game._annex_free_cells(1)[0])
	_add_completed_building(game, VaultBuilding.Kind.BED, game._annex_free_cells(1)[0])
	game.power_grid.recalculate(game.buildings)
	_assert_food_next(game, PLACE_TRAY_CALM, false, "calm, no Grow Tray")
	_dispose(game)


func _test_save_load() -> void:
	for open: bool in [false, true]:
		for with_tray: bool in [true, false]:
			var game := _vault(open, with_tray)
			_starve(game)
			if with_tray:
				_set_work(game, "cook", VaultResident.PRIORITY_DISABLED)
			var expected := ENABLE_COOK if with_tray else PLACE_TRAY
			var what := "reloaded %s" % ("Cook OFF" if with_tray else "no Grow Tray")
			_remove_test_save(KR_FOOD_SAVE)
			_assert_true(game.save_game(false, KR_FOOD_SAVE), "%s (%s): saved" % [what, _label(open)])
			game.new_game(false)
			_assert_false(game.keep_running, "%s: new game clears" % what)
			_assert_true(game.load_game(KR_FOOD_SAVE), "%s (%s): loaded" % [what, _label(open)])
			game.status_message_left = 0.0
			_assert_equal(game.residents.size(), 5 if open else 4, "%s (%s): crew restored" % [what, _label(open)])
			_assert_food_next(game, expected, open, what)
			_remove_test_save(KR_FOOD_SAVE)
			_dispose(game)


func _test_recovery() -> void:
	for open: bool in [false, true]:
		var game := _vault(open)
		_starve(game)
		_set_work(game, "cook", VaultResident.PRIORITY_DISABLED)
		_assert_equal(_next(game), ENABLE_COOK, "starving (%s)" % _label(open))
		_set_work(game, "cook", 3)
		_calm(game)
		game.food_system.meals = 20
		var expected := PlayerOrders.ANNEX_TEXT.stable_next if open else PlayerOrders.ANNEX_TEXT.next
		_assert_equal(_next(game), expected, "fed again, the %s Next returns" % ("stable" if open else "Annex"))
		_dispose(game)


func _test_beats_latch() -> void:
	var game := _vault(false)
	for bed: VaultBuilding in game.buildings.duplicate():
		if bed.kind == VaultBuilding.Kind.MEDICAL_BED:
			game.deconstruct_building(bed.building_id)
	# With no Med Bed at all the comfort card leads (Rec-45); an unfinished Med Bed blueprint keeps
	# comfort satisfied, so the plain Med Bed suggestion latches.
	_assert_equal(_next(game), str(PlayerOrders.COMFORT_TEXT.next), "no Med Bed: Next points at the comfort card")
	_starve(game)
	_set_work(game, "cook", VaultResident.PRIORITY_DISABLED)
	_assert_equal(_next(game), ENABLE_COOK, "the food emergency shows through the comfort Next")
	_dispose(game)
	game = _vault(false)
	for bed: VaultBuilding in game.buildings.duplicate():
		if bed.kind == VaultBuilding.Kind.MEDICAL_BED:
			var cell := bed.cell
			game.deconstruct_building(bed.building_id)
			var blueprint := VaultBuilding.new()
			game.building_root.add_child(blueprint)
			blueprint.configure(game.next_building_id, VaultBuilding.Kind.MEDICAL_BED, cell, false)
			game.next_building_id += 1
			game.buildings.append(blueprint)
	_assert_false(game.comfort_pending(), "a Med Bed blueprint keeps comfort satisfied")
	var ari: VaultResident = game.residents[0]
	ari.needs.health = 50.0
	_assert_true(_next(game).contains("Med Bed"), "an injury latches a Med Bed: %s" % _next(game))
	ari.needs.health = 100.0
	_assert_true(_next(game).contains("Med Bed"), "the Med Bed suggestion holds after the injury heals")
	_starve(game)
	_set_work(game, "cook", VaultResident.PRIORITY_DISABLED)
	_assert_equal(_next(game), ENABLE_COOK, "the food emergency shows through the latch")
	_dispose(game)


func _test_opening_gives_way() -> void:
	for open: bool in [false, true]:
		var game := _vault(open)
		var primary: Dictionary = game.player_orders._primary_next_step()
		_assert_true(str(primary.text).begins_with("Next: YOU mark rock"), "the fixture's diagnosis is the opening dig (%s): %s" % [_label(open), primary.text])
		_assert_equal(str(primary.get("kind", "")), "", "the opening dig is not food chain")
		_assert_equal(_next(game), str(game.player_orders.keep_running_default_step().text), "mark rock gives way (%s)" % _label(open))
		_carve(game, 12)
		for bed: VaultBuilding in game.buildings.duplicate():
			if bed.kind == VaultBuilding.Kind.BED:
				game.deconstruct_building(bed.building_id)
		game.status_message_left = 0.0
		primary = game.player_orders._primary_next_step()
		_assert_equal(str(primary.text), "Next: YOU place 2 bunks · THEY craft from Craft", "the fixture's diagnosis is the first bunks (%s)" % _label(open))
		_assert_equal(str(primary.get("kind", "")), "", "first bunks are not food chain")
		_assert_equal(_next(game), str(game.player_orders.keep_running_default_step().text), "first bunks give way (%s)" % _label(open))
		_dispose(game)
