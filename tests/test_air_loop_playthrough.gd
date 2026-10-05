extends "res://tests/test_runner.gd"

const TICK_CAP := 550
const RATE_TOLERANCE := 0.00001
const FINISH_AIR := ["Next: YOU leave Haul + Craft on · THEY finish the Air Recycler", "Keep Haul + Craft above OFF so crew supply and finish the Air Recycler blueprint.", "select"]
const ENABLE_AIR := ["Next: YOU enable an Air Recycler · THEY recycle air", "Select a completed Air Recycler and click ENABLE so it can recycle air.", "select"]
const AIR_NEXT := "Next: YOU place Air Recycler · THEY craft it"
const AIR_HINT := ["air", "Designate AIR $14 and keep it powered (3). Craft auto-builds the blueprint."]
const OBSERVATION_HINTS := {
	"Next: YOU watch hatch · THEY auto-patch": ["select", "When the hatch warns, undrafted Haul + Craft claim supply/patch without draft."],
	"Next: YOU keep 4 salvage · THEY haul/craft hatch": ["select", "Reserve 4 salvage. Leave Haul + Craft above OFF so they auto-respond to the hatch."],
}
const LOAD_KINDS := [VaultBuilding.Kind.LAMP, VaultBuilding.Kind.GROW_TRAY, VaultBuilding.Kind.KITCHEN, VaultBuilding.Kind.AIR_RECYCLER]

var _hint_history: Array[String] = []
var _tick := 0
var _last_step: Dictionary = {}
var _air: VaultBuilding
var _recommended := false
var _powered_tick := -1
var _min_oxygen := 100.0


func _run() -> void:
	_run_case("Staged food-ready Next builds powered Air and raises oxygen before hatch warning", _test_staged_air)
	print("AIR LOOP PLAYTHROUGH: %s — %d cases, %d assertions, %d failures" % [
		"FAIL" if _failure_count else "PASS", _case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _test_staged_air() -> void:
	var game := _spawn_game()
	# Declared staged food-ready fixture: NOT a #46 food-loop continuation/replay,
	# untouched fresh-wing, crisis walk, or Day-7 proof. Original residents retain
	# starting needs/default work; Core, enabled Lumen, and Salvage Bay remain.
	# Same finished dig/bunk prep as #46: force-carve 12 connected cells above
	# the chamber, credit already-hauled rubble (no competing rubble jobs), and
	# pay for two completed bunks: 48 + 12*3 - 2*8 = 68 salvage.
	for x in range(MapGrid.CHAMBER.position.x, MapGrid.CHAMBER.end.x):
		var cell := Vector2i(x, MapGrid.CHAMBER.position.y - 1)
		_assert_equal(game.map_grid.get_tile(cell), MapGrid.Tile.ROCK, "prep carves original rock")
		game.map_grid.cells[cell.y * MapGrid.WIDTH + cell.x] = MapGrid.Tile.FLOOR
		game.map_grid.topology_revision += 1
		game.map_grid.tile_changed.emit(cell)
	game.food_system.add_salvage(12 * 3)
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(20, 16))
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(21, 17))
	_assert_equal(game.food_system.take_salvage(2 * 8), 16, "completed bunks pay full costs")
	_assert_equal(game.food_system.salvage, 68, "dig/bunk prep leaves 68 salvage")
	# Completed food fixtures are paid staging, not constructed by this driver.
	# No extra generator: Core 2 + Charge 7 = 9; Lumen 1 + Grow 3 + Kitchen 2
	# leaves exactly 3 power for the recommended Air Recycler.
	for fixture in [[VaultBuilding.Kind.GENERATOR, 18], [VaultBuilding.Kind.GROW_TRAY, 12], [VaultBuilding.Kind.KITCHEN, 10]]:
		var cell := _free_floor_cell(game)
		_assert_true(cell != Vector2i(-1, -1), "staged fixture has free floor")
		_add_completed_building(game, int(fixture[0]), cell)
		_assert_equal(game.food_system.take_salvage(int(fixture[1])), fixture[1], "staged food fixture pays full cost")
	game.food_system.raw_food = 0
	game.food_system.meals = 4
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, game.breach_system.is_open())
	game.begin_shift()
	var originals: Array[VaultResident] = game.residents.duplicate()
	_assert_equal(originals.size(), 4, "four original residents")
	_assert_equal(game.day_cycle.elapsed_seconds, 0.0, "staged shift starts at zero elapsed")
	_assert_equal(game.food_system.salvage, 28, "68 - 18 - 12 - 10 = 28 staged salvage")
	_assert_equal(game.food_system.raw_food, 0, "staged raw food starts empty")
	_assert_equal(game.food_system.meals, 4, "staged meals start at four")
	_assert_equal(game.map_grid.get_floor_cells().size(), 132, "twelve connected cells carved")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.BED), 2, "two completed bunks")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.GENERATOR, true), 1, "only one non-Core Charge")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.STOCKPILE), 1, "original Bay retained")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.AIR_RECYCLER), 0, "no staged Air")
	_assert_equal(game.power_grid.supply, 9, "Core plus Charge supplies nine")
	_assert_equal(game.power_grid.served, 6, "food and Lumen use six before Air")
	_assert_approximately(game.oxygen_system.net_rate, -0.32, RATE_TOLERANCE, "baseline consumption is four times 0.08")
	_last_step = game.player_orders._primary_next_step()
	_assert_equal([_last_step.text, _last_step.tool, _last_step.help], [AIR_NEXT, AIR_HINT[0], AIR_HINT[1]], "initial Next is exact Air placement tuple")
	if _failure_count or not _check_running(game, originals):
		_dispose(game)
		return

	for index in TICK_CAP:
		_tick = index + 1
		_last_step = game.player_orders._primary_next_step()
		var hint := "%s | %s | tool=%s" % [_last_step.text, _last_step.help, _last_step.tool]
		if _hint_history.is_empty() or not _hint_history.back().ends_with(hint):
			_hint_history.append("tick %d: %s" % [_tick, hint])
		if not _check_running(game, originals) or not _act_on_next(game, _last_step):
			break
		# Completion tick advances O2 before jobs. Only a subsequent full tick
		# whose starting rates already reflect powered Air can prove production.
		var observing := _powered_tick >= 0 and _tick > _powered_tick
		var oxygen_before: float = game.oxygen_system.oxygen
		game.step_simulation(VaultGame.SIMULATION_TICK)
		if not _check_running(game, originals):
			break
		if _air != null and _air.complete and _air.powered:
			if not _check_air_rates(game):
				break
			if _powered_tick < 0:
				_powered_tick = _tick
			if observing:
				if game.oxygen_system.oxygen <= oxygen_before:
					_fail_playthrough(game, "powered Air failed to raise oxygen over a later full tick (before=%.6f)" % oxygen_before)
					break
				_assert_true(_recommended and _air.complete and _air.powered, "Air was recommended, built, and powered")
				_assert_equal(game.power_grid.demand, 9, "Lumen + Grow + Kitchen + Air demand nine")
				_assert_equal(game.power_grid.served, 9, "all nine power served")
				_assert_equal(game.power_grid.shed_count, 0, "no loads shed")
				_assert_equal(game.get_alive_count(), originals.size(), "all original residents alive")
				_assert_true(game.oxygen_system.oxygen > oxygen_before, "oxygen rises after completion/power tick")
				print("Air production PASS at tick %d (%.1fs); oxygen=%.6f net_rate=%.2f; powered since tick %d; min O2=%.6f; fixture power=%s" % [
					_tick, game.day_cycle.elapsed_seconds, game.oxygen_system.oxygen, game.oxygen_system.net_rate,
					_powered_tick, _min_oxygen, _power_state(game)])
				_dispose(game)
				return
	if not _failure_count:
		_fail_playthrough(game, "550-tick cap reached without powered Air producing rising oxygen")
	_dispose(game)


func _free_floor_cell(game: VaultGame) -> Vector2i:
	var bay := game.job_system._stockpile_cell()
	var cells := game.map_grid.get_floor_cells()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(bay) < b.distance_squared_to(bay))
	for cell in cells:
		if cell != BreachSystem.HATCH_CELL and game.get_building_at(cell) == null:
			return cell
	return Vector2i(-1, -1)


func _act_on_next(game: VaultGame, step: Dictionary) -> bool:
	var tuple := [step.text, step.help, step.tool]
	if tuple == FINISH_AIR:
		if _air == null or _air.complete or not game.buildings.has(_air):
			return _fail_playthrough(game, "Air finish requires retained unfinished Air")
		for resident in game.residents:
			for work in ["haul", "craft"]:
				if resident.alive and not resident.drafted and resident.get_work_priority(work) == VaultResident.PRIORITY_DISABLED:
					resident.set_work_priority(work, VaultResident.DEFAULT_WORK_PRIORITY)
		return true
	if tuple == ENABLE_AIR:
		if _air == null or not _air.complete or not _air.manually_disabled:
			return _fail_playthrough(game, "Air enable requires completed disabled Air")
		return game.toggle_building_enabled(_air.building_id)
	if step.text == AIR_NEXT and [step.tool, step.help] == AIR_HINT:
		_recommended = true
		if _air != null:
			if not _air.complete:
				return _fail_playthrough(game, "repeated Air place tip with retained unfinished Air")
			return _fail_playthrough(game, "Next asks for another Air after completion; diagnose power/enable, never duplicate Air")
		for building in game.buildings:
			if building.kind == VaultBuilding.Kind.AIR_RECYCLER:
				return _fail_playthrough(game, "unexpected pre-existing Air; refuse duplicate placement")
		var cell := _free_floor_cell(game)
		if cell == Vector2i(-1, -1):
			return _fail_playthrough(game, "no free floor for recommended Air")
		if not game.place_blueprint(VaultBuilding.Kind.AIR_RECYCLER, cell):
			return _fail_playthrough(game, "recommended Air blueprint rejected at %s: %s" % [cell, game.status_message])
		_air = game.get_building_at(cell)
		return true
	if OBSERVATION_HINTS.get(step.text, []) == [step.tool, step.help] and _powered_tick >= 0:
		return true # Hatch-watch / reserve salvage requests time only before warning.
	return _fail_playthrough(game, "unexpected Next recommendation (only exact Air placement/finish/enable and powered observation allowed)")


func _check_air_rates(game: VaultGame) -> bool:
	if not is_equal_approx(game.oxygen_system.recycler_output_rate, 0.8) or not is_equal_approx(game.oxygen_system.net_rate, 0.48):
		return _fail_playthrough(game, "powered Air rates must be output 0.8 and net +0.48")
	return true


func _check_running(game: VaultGame, originals: Array[VaultResident]) -> bool:
	_min_oxygen = minf(_min_oxygen, game.oxygen_system.oxygen)
	if game.oxygen_system.oxygen <= 15.0:
		return _fail_playthrough(game, "O2 must stay strictly above 15 (exactly 15 is critical)")
	if game.day_cycle.elapsed_seconds >= BreachSystem.WARNING_AT_SECONDS:
		return _fail_playthrough(game, "elapsed reached hatch warning without success (<60s required)")
	if game.user_paused or game.is_simulation_paused() or game.player_orders.is_help_open() or game.player_orders.breach_warning_panel.visible:
		return _fail_playthrough(game, "unexpected pause/modal/ended state")
	for resident in originals:
		if not resident.alive:
			return _fail_playthrough(game, "original resident %d died" % resident.resident_id)
	for kind in LOAD_KINDS:
		if kind == VaultBuilding.Kind.AIR_RECYCLER and (_air == null or not _air.complete):
			continue
		if game.get_completed_building_count(kind) != 1:
			return _fail_playthrough(game, "expected exactly one completed %s" % VaultBuilding.KIND_NAMES[kind])
		for building in game.buildings:
			if building.kind == kind and (building.manually_disabled or not building.powered or game.power_grid.is_building_shed(building.building_id)):
				return _fail_playthrough(game, "%s must remain enabled, powered, and unshed" % building.get_display_name())
	return true


func _power_state(game: VaultGame) -> String:
	var fixtures: Array[String] = []
	for building in game.buildings:
		fixtures.append("%s@%s complete=%s enabled=%s powered=%s shed=%s core=%s" % [
			building.get_display_name(), building.cell, building.complete, not building.manually_disabled,
			building.powered, game.power_grid.is_building_shed(building.building_id), building.is_emergency_core])
	return "supply=%d demand=%d served=%d shed=%d; %s" % [game.power_grid.supply, game.power_grid.demand, game.power_grid.served, game.power_grid.shed_count, str(fixtures)]


func _fail_playthrough(game: VaultGame, reason: String) -> bool:
	_assert_true(false, "%s; tick=%d elapsed=%.1fs O2=%.6f min O2=%.6f output=%.2f net=%.2f powered tick=%d; last Next=%s; history=%s; inventory=%s pending raw=%d meals=%d; fixture power=%s; jobs=%s" % [
		reason, _tick, game.day_cycle.elapsed_seconds, game.oxygen_system.oxygen, _min_oxygen,
		game.oxygen_system.recycler_output_rate, game.oxygen_system.net_rate, _powered_tick,
		str(_last_step), str(_hint_history), str(game.food_system.serialize()), game.job_system.get_pending_raw_food(),
		game.job_system.get_pending_meals(), _power_state(game), str(game.job_system.jobs)])
	return false
