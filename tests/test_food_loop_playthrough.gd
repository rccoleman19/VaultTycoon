extends "res://tests/test_runner.gd"

const TICK_CAP := 550
const CHARGE_NEXT := "Next: YOU place a Charge Node · THEY supply/build"
const GROW_NEXT := "Next: YOU place Grow Tray · THEY haul output"
const KITCHEN_NEXT := "Next: YOU place Nutrient Station · THEY cook/haul"
const AIR_NEXT := "Next: YOU place Air Recycler · THEY craft it"
const POWER_NEXT := "Next: YOU power food chain · THEY cook/haul alone"
const FINISH_CHARGE_NEXT := "Next: YOU leave Haul + Craft on · THEY finish the Charge Node"
const FINISH_NUTRIENT_NEXT := "Next: YOU leave Haul + Craft on · THEY finish the Nutrient Station"
const FINISH_GROW_NEXT := "Next: YOU leave Haul + Craft on · THEY finish the Grow Tray"
const ENABLE_GROW_NEXT := "Next: YOU enable a Grow Tray · THEY grow"
const ENABLE_KITCHEN_NEXT := "Next: YOU power the Nutrient Station · THEY cook"
const ENABLE_COOK_NEXT := "Next: YOU enable Cook · THEY cook"
const ENABLE_HAUL_NEXT := "Next: YOU enable Haul · THEY deliver food"
const COOK_NEXT := "Next: YOU leave Cook on · THEY cook"
const HATCH_NEXT := "Next: YOU watch hatch · THEY auto-patch"

# Match the whole recommendation: "select" alone cannot identify an action.
const PLACEMENT_HINTS := {
	CHARGE_NEXT: ["generator", "Designate CHARGE. Haul + Craft auto-claim the blueprint. Adds +7 power."],
	GROW_NEXT: ["grow", "Designate GROW and keep it powered. Haul defaults move raw food to stock."],
	KITCHEN_NEXT: ["kitchen", "Designate NUTRI, power it, leave Cook + Haul above OFF."],
	AIR_NEXT: ["air", "Designate AIR $14 and keep it powered (3). Craft auto-builds the blueprint."],
	"Next: YOU place bunks · THEY craft": ["bed", "Place bunks so tired undrafted crew have a bed."],
}
const SELECT_HINTS := {
	POWER_NEXT: "Enable Grow + Nutrient power. Keep Cook/Haul above OFF so defaults keep working.",
	FINISH_CHARGE_NEXT: "Keep Haul + Craft above OFF so crew supply and finish the Charge Node blueprint.",
	FINISH_NUTRIENT_NEXT: "Keep Haul + Craft above OFF so crew supply and finish the Nutrient Station blueprint.",
	FINISH_GROW_NEXT: "Keep Haul + Craft above OFF so crew supply and finish the Grow Tray blueprint.",
	ENABLE_GROW_NEXT: "Enable a completed Grow Tray so it can grow raw food. Haul delivers its output for Cook.",
	ENABLE_KITCHEN_NEXT: "Power the Nutrient Station so Cook can run.",
	ENABLE_COOK_NEXT: "Enable Cook on a living, undrafted resident so the powered Nutrient Station can run.",
	ENABLE_HAUL_NEXT: "Open PRIORITIES [P] and enable Haul on a living, undrafted resident. Food is waiting for delivery.",
	HATCH_NEXT: "When the hatch warns, undrafted Haul + Craft claim supply/patch without draft.",
}

var _hint_history: Array[String] = []
var _min_food := 100.0
var _tick := 0
var _last_step: Dictionary = {}
var _chain := {"harvest": false, "raw_deposit": false, "cook": false, "pending_meal": false, "meal_deposit": false}
var _last_raw := 0
var _last_meals := 4


func _run() -> void:
	_run_case("Day-1 staged opening follows Next to a stocked Grow-derived meal", _test_staged_opening)
	print("FOOD LOOP PLAYTHROUGH: %s — %d cases, %d assertions, %d failures" % [
		"FAIL" if _failure_count else "PASS", _case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _test_staged_opening() -> void:
	var game := _spawn_game()
	# Declared staged fixture: the four original residents keep their starting
	# needs and default work. Core, enabled Lumen, and Salvage Bay are retained.
	# Twelve connected cells beside the chamber and two completed bunks represent
	# finished dig/bunk prep, NOT an untouched fresh-wing or crisis-chain proof.
	# Force-carve with the already-hauled dig yield: queue_dig/apply_dig_work would
	# leave 12 rubble haul jobs competing with this opening and credit salvage a
	# second time. Finished prep includes that hauling, with no pending rubble.
	for x in range(MapGrid.CHAMBER.position.x, MapGrid.CHAMBER.end.x):
		var cell := Vector2i(x, MapGrid.CHAMBER.position.y - 1)
		_assert_equal(game.map_grid.get_tile(cell), MapGrid.Tile.ROCK, "prep carves original rock")
		game.map_grid.cells[cell.y * MapGrid.WIDTH + cell.x] = MapGrid.Tile.FLOOR
		game.map_grid.topology_revision += 1
		game.map_grid.tile_changed.emit(cell)
	game.food_system.add_salvage(12 * 3)
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(20, 16))
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(21, 17))
	# Exactly 48 + 12×3 − 2×8 = 68; no Charge/Grow/Kitchen beyond the Core.
	_assert_equal(game.food_system.take_salvage(2 * 8), 16, "finished bunks pay their full costs")
	game.food_system.raw_food = 0
	game.food_system.meals = 4
	game.begin_shift()
	_assert_equal(game.residents.size(), 4, "four original residents")
	_assert_equal(game.food_system.salvage, 68, "staged salvage includes rubble minus bunk costs")
	_assert_equal(game.map_grid.get_floor_cells().size(), 132, "twelve cells carved beside the chamber")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.BED), 2, "two finished bunks")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.GENERATOR, true), 0, "no non-Core Charge yet")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.GROW_TRAY), 0, "no Grow yet")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.KITCHEN), 0, "no Kitchen yet")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.LAMP), 1, "starting Lumen stays enabled and powered")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.STOCKPILE), 1, "starting Bay retained")
	var originals: Array[VaultResident] = game.residents.duplicate()
	_last_raw = game.food_system.raw_food
	_last_meals = game.food_system.meals # Baseline 4 never counts as production.
	game.food_system.raw_food_produced.connect(_observe_harvest.bind(game))
	game.food_system.inventory_changed.connect(_observe_inventory.bind(game))
	if _failure_count:
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
		# Needs drain before job_system can eat. Check that intermediate value so
		# a consume_meal/eat later in this same tick cannot conceal food <20.
		var safe := true
		for resident in originals:
			var drained := maxf(0.0, resident.needs.food - 60.0 * VaultGame.SIMULATION_TICK / DayCycle.SECONDS_PER_DAY)
			_min_food = minf(_min_food, drained)
			if drained < 20.0:
				_fail_playthrough(game, "impending hunger drain puts resident %d below 20" % resident.resident_id)
				safe = false
				break
		if not safe:
			break
		game.step_simulation(VaultGame.SIMULATION_TICK)
		if _chain.cook and game.job_system.get_pending_meals() > 0:
			_chain.pending_meal = true
		if not _check_running(game, originals):
			break
		if _chain.meal_deposit:
			_assert_true(_chain.harvest and _chain.raw_deposit and _chain.cook and _chain.pending_meal,
				"stocked meal follows organic Grow → raw haul → Cook → meal haul")
			print("Stocked Grow-derived meal at tick %d (%.1fs); min food including drain %.2f; chain=%s" % [
				_tick, game.day_cycle.elapsed_seconds, _min_food, str(_chain)])
			_dispose(game)
			return
	if not _failure_count:
		_fail_playthrough(game, "550-tick cap reached without a stocked Grow-derived meal")
	_dispose(game)


func _observe_harvest(source: Vector2i, amount: int, game: VaultGame) -> void:
	var tray := game.get_building_at(source)
	if tray != null and tray.kind == VaultBuilding.Kind.GROW_TRAY and tray.complete and tray.powered and amount > 0:
		# Only natural food_system.advance can emit this signal in this driver;
		# the game's earlier-connected handler has already queued the raw cargo.
		_chain.harvest = game.job_system.get_pending_raw_food_at(source) > 0


func _observe_inventory(game: VaultGame) -> void:
	var raw: int = game.food_system.raw_food
	var meals: int = game.food_system.meals
	# Read at each signal, not tick endpoints: another worker may consume a
	# deposited unit in the same tick. In-transit cargo still exists at add_*.
	if _chain.harvest and raw > _last_raw and _has_deposit_cargo(game, JobSystem.JobType.HAUL_RAW_FOOD):
		_chain.raw_deposit = true
	if _chain.raw_deposit and raw < _last_raw:
		_chain.cook = true # finish_cooking is the only raw withdrawal in this run.
	if _chain.cook and meals > _last_meals and _has_deposit_cargo(game, JobSystem.JobType.HAUL_MEAL):
		_chain.pending_meal = game.job_system.get_pending_meals() > 0
		_chain.meal_deposit = _chain.pending_meal
	_last_raw = raw
	_last_meals = meals


func _has_deposit_cargo(game: VaultGame, type: int) -> bool:
	for job: Dictionary in game.job_system.jobs:
		if int(job.type) == type and not bool(job.get("done", false)) and int(job.get("in_transit", 0)) > 0:
			return true
	return false


func _act_on_next(game: VaultGame, step: Dictionary) -> bool:
	var text: String = step.text
	var help: String = step.help
	var tool: String = step.tool
	if tool == "dig":
		return _fail_playthrough(game, "Dig hint means the staged +12 floor fixture is wrong")
	if PLACEMENT_HINTS.has(text) and PLACEMENT_HINTS[text] == [tool, help]:
		# The repo names the tool map BUILD_KIND_BY_TOOL (not TOOL_TO_KIND).
		var kind := int(game.BUILD_KIND_BY_TOOL[tool])
		for building in game.buildings:
			if building.kind == kind and not building.complete:
				return true # Idempotent: time only until the crew finish it.
		# Choose the nearest empty floor to the Bay, keeping deliveries short.
		var bay := game.job_system._stockpile_cell()
		var cells := game.map_grid.get_floor_cells()
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.distance_squared_to(bay) < b.distance_squared_to(bay))
		for cell in cells:
			if cell != BreachSystem.HATCH_CELL and game.get_building_at(cell) == null:
				if game.place_blueprint(kind, cell):
					return true
				return _fail_playthrough(game, "recommended blueprint rejected at %s: %s" % [cell, game.status_message])
		return _fail_playthrough(game, "no free walkable floor for recommended blueprint")
	if text == COOK_NEXT and tool == "select" and help in [
		"Meals are short. The powered Nutrient Station can cook.",
		"Meals are short. Leave Cook on. The powered Nutrient Station is waiting on raw food."]:
		return true # Ready/waiting Cook is time only.
	if tool != "select" or SELECT_HINTS.get(text, "") != help:
		return _fail_playthrough(game, "unexpected Next recommendation")
	match text:
		POWER_NEXT:
			return _enable_buildings(game, [VaultBuilding.Kind.GROW_TRAY, VaultBuilding.Kind.KITCHEN])
		ENABLE_GROW_NEXT:
			return _enable_buildings(game, [VaultBuilding.Kind.GROW_TRAY])
		ENABLE_KITCHEN_NEXT:
			return _enable_buildings(game, [VaultBuilding.Kind.KITCHEN])
		ENABLE_COOK_NEXT:
			return _enable_work(game, "cook")
		ENABLE_HAUL_NEXT:
			return _enable_work(game, "haul")
		FINISH_GROW_NEXT, FINISH_NUTRIENT_NEXT, FINISH_CHARGE_NEXT:
			return _enable_work(game, "haul") and _enable_work(game, "craft")
		HATCH_NEXT:
			return true # No response is requested until the hatch actually warns.
	return _fail_playthrough(game, "unhandled Next recommendation")


func _enable_buildings(game: VaultGame, kinds: Array) -> bool:
	for building in game.buildings:
		if building.kind in kinds and building.complete and building.manually_disabled:
			if not game.toggle_building_enabled(building.building_id):
				return _fail_playthrough(game, "recommended building enable rejected")
	return true


func _enable_work(game: VaultGame, work: String) -> bool:
	for resident in game.residents:
		if resident.alive and not resident.drafted and resident.get_work_priority(work) == VaultResident.PRIORITY_DISABLED:
			if not resident.set_work_priority(work, VaultResident.DEFAULT_WORK_PRIORITY):
				return _fail_playthrough(game, "recommended %s enable rejected" % work)
			break
	return true


func _check_running(game: VaultGame, originals: Array[VaultResident]) -> bool:
	for resident in originals:
		if not resident.alive:
			return _fail_playthrough(game, "original resident %d died" % resident.resident_id)
		_min_food = minf(_min_food, resident.needs.food)
		if resident.needs.food < 20.0:
			return _fail_playthrough(game, "original resident %d food <20" % resident.resident_id)
	if game.user_paused or game.is_simulation_paused() or game.player_orders.is_help_open():
		return _fail_playthrough(game, "unexpected pause/modal/ended state")
	return true


func _fail_playthrough(game: VaultGame, reason: String) -> bool:
	var fixtures: Array[String] = []
	for kind in [VaultBuilding.Kind.GENERATOR, VaultBuilding.Kind.GROW_TRAY, VaultBuilding.Kind.KITCHEN]:
		var complete := 0
		var powered := 0
		for building in game.buildings:
			if building.kind == kind and not building.is_emergency_core:
				complete += int(building.complete)
				powered += int(building.powered)
		fixtures.append("%s complete=%d powered=%d" % [VaultBuilding.KIND_NAMES[kind], complete, powered])
	_assert_true(false, "%s; tick=%d elapsed=%.1fs min food=%.2f; last Next=%s; history=%s; inventory=%s pending raw=%d meals=%d; fixture=%s; chain=%s" % [
		reason, _tick, game.day_cycle.elapsed_seconds, _min_food, str(_last_step), str(_hint_history),
		str(game.food_system.serialize()), game.job_system.get_pending_raw_food(), game.job_system.get_pending_meals(),
		str(fixtures), str(_chain)])
	return false
