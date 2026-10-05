extends "res://tests/test_runner.gd"

const TICK_CAP := 550
const RATE_TOLERANCE := 0.00001
const LOAD_KINDS := [VaultBuilding.Kind.LAMP, VaultBuilding.Kind.GROW_TRAY, VaultBuilding.Kind.KITCHEN, VaultBuilding.Kind.AIR_RECYCLER]
const CHARGE_NEXT := "Next: YOU place a Charge Node · THEY supply/build"
const GROW_NEXT := "Next: YOU place Grow Tray · THEY haul output"
const KITCHEN_NEXT := "Next: YOU place Nutrient Station · THEY cook/haul"
const AIR_NEXT := "Next: YOU place Air Recycler · THEY craft it"
const POWER_NEXT := "Next: YOU power food chain · THEY cook/haul alone"
const FINISH_GROW_NEXT := "Next: YOU leave Haul + Craft on · THEY finish the Grow Tray"
const ENABLE_GROW_NEXT := "Next: YOU enable a Grow Tray · THEY grow"
const ENABLE_KITCHEN_NEXT := "Next: YOU power the Nutrient Station · THEY cook"
const ENABLE_COOK_NEXT := "Next: YOU enable Cook · THEY cook"
const ENABLE_HAUL_NEXT := "Next: YOU enable Haul · THEY deliver food"
const COOK_NEXT := "Next: YOU leave Cook on · THEY cook"
const RESERVE_NEXT := "Next: YOU keep 4 salvage · THEY haul/craft hatch"
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
	FINISH_GROW_NEXT: "Keep Haul + Craft above OFF so crew supply and finish the Grow Tray blueprint.",
	ENABLE_GROW_NEXT: "Enable a completed Grow Tray so it can grow raw food. Haul delivers its output for Cook.",
	ENABLE_KITCHEN_NEXT: "Power the Nutrient Station so Cook can run.",
	ENABLE_COOK_NEXT: "Enable Cook on a living, undrafted resident so the powered Nutrient Station can run.",
	ENABLE_HAUL_NEXT: "Open PRIORITIES [P] and enable Haul on a living, undrafted resident. Food is waiting for delivery.",
	RESERVE_NEXT: "Reserve 4 salvage. Leave Haul + Craft above OFF so they auto-respond to the hatch.",
	HATCH_NEXT: "When the hatch warns, undrafted Haul + Craft claim supply/patch without draft.",
}

var _hint_history: Array[String] = []
var _min_food := 100.0
var _tick := 0
var _last_step: Dictionary = {}
var _chain := {"harvest": false, "raw_deposit": false, "cook": false, "pending_meal": false, "meal_deposit": false}
var _air: VaultBuilding
var _air_recommended := false
var _air_blueprints := 0
var _powered_tick := -1
var _air_rise_tick := -1
var _meal_tick := -1
var _meal_elapsed := -1.0
var _air_elapsed := -1.0
var _min_oxygen := 100.0
var _last_raw := 0
var _last_meals := 4


func _run() -> void:
	_run_case("Continuous Next-guided Food then Air from elapsed zero", _test_staged_opening)
	print("CONTINUOUS FOOD AIR WALK: %s — %d cases, %d assertions, %d failures" % [
		"FAIL" if _failure_count else "PASS", _case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _test_staged_opening() -> void:
	var game := _spawn_game()
	# Declared staged fixture: exact #46 dig/bunk opening at elapsed zero.
	# Originals keep starting needs/default work; Core, enabled Lumen, and
	# Salvage Bay are retained. Force-carve 12 cells above the chamber, credit
	# 12*3 salvage, add two completed bunks, and pay 2*8: salvage is 68.
	# This is staged dig/bunk prep, NOT fresh-wing, continuous hatch seal,
	# #47/#48 snapshots, or Day-7 proof. Food and Air must be built organically
	# under one clock from zero; no 55s staging or clock teleport.
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
	_assert_equal(game.day_cycle.elapsed_seconds, 0.0, "shift starts at elapsed zero")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.AIR_RECYCLER), 0, "no Air yet")
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
		# Completion advances O2 before jobs: observe a full tick after power-up.
		var observing_air := _powered_tick >= 0 and _tick > _powered_tick
		var oxygen_before: float = game.oxygen_system.oxygen
		game.step_simulation(VaultGame.SIMULATION_TICK)
		if _chain.cook and game.job_system.get_pending_meals() > 0:
			_chain.pending_meal = true
		if not _check_running(game, originals):
			break
		if _chain.meal_deposit and _meal_tick < 0:
			_meal_tick = _tick
			_meal_elapsed = game.day_cycle.elapsed_seconds
		if _air != null and _air.complete and _air.powered:
			if not _check_air_state(game):
				break
			if _powered_tick < 0:
				_powered_tick = _tick
			if observing_air and _air_rise_tick < 0:
				if game.oxygen_system.oxygen <= oxygen_before:
					_fail_playthrough(game, "powered Air failed to raise O2 over a full later tick (before=%.6f)" % oxygen_before)
					break
				_air_rise_tick = _tick
				_air_elapsed = game.day_cycle.elapsed_seconds
		if _meal_tick >= 0 and _air_rise_tick >= 0:
			if not _check_air_state(game):
				break
			_assert_true(_chain.harvest and _chain.raw_deposit and _chain.cook and _chain.pending_meal and _chain.meal_deposit,
				"A: stocked meal follows organic Grow → raw haul → Cook → meal haul")
			_assert_true(_air_recommended and _air_blueprints == 1 and _air_rise_tick > _powered_tick,
				"B: exactly one recommended Air raises O2 after its power-up tick")
			_assert_equal(game.food_system.salvage, 14, "68 - Charge18 - Grow12 - Kitchen10 - Air14 leaves future hatch reserve 14")
			_assert_equal(game.get_alive_count(), originals.size(), "all originals remain alive")
			_assert_true(game.day_cycle.elapsed_seconds < BreachSystem.WARNING_AT_SECONDS, "both latches before warning")
			print("Continuous Food+Air %s: meal credit tick=%d elapsed=%.1fs; Air rise tick=%d elapsed=%.1fs powered tick=%d; elapsed=%.1fs O2=%.6f net=%.2f salvage=%d min food=%.2f min O2=%.6f; A=%s B=%s" % [
				"FAIL" if _failure_count else "PASS", _meal_tick, _meal_elapsed, _air_rise_tick, _air_elapsed, _powered_tick,
				game.day_cycle.elapsed_seconds, game.oxygen_system.oxygen, game.oxygen_system.net_rate,
				game.food_system.salvage, _min_food, _min_oxygen, str(_chain), str(_air_flags())])
			if _failure_count:
				_fail_playthrough(game, "success diagnostics failed")
			_dispose(game)
			return
	if not _failure_count:
		_fail_playthrough(game, "550-tick cap reached without BOTH organic meal credit and Air rise")
	_dispose(game)


func _observe_harvest(source: Vector2i, amount: int, game: VaultGame) -> void:
	var tray := game.get_building_at(source)
	if tray != null and tray.kind == VaultBuilding.Kind.GROW_TRAY and tray.complete and tray.powered and amount > 0:
		# Only natural food_system.advance can emit this signal in this driver;
		# the game's earlier-connected handler has already queued the raw cargo.
		_chain.harvest = _chain.harvest or game.job_system.get_pending_raw_food_at(source) > 0


func _observe_inventory(game: VaultGame) -> void:
	var raw: int = game.food_system.raw_food
	var meals: int = game.food_system.meals
	# Read at each signal, not tick endpoints: another worker may consume a
	# deposited unit in the same tick. In-transit cargo still exists at add_*.
	if _chain.harvest and raw > _last_raw and _has_deposit_cargo(game, JobSystem.JobType.HAUL_RAW_FOOD):
		_chain.raw_deposit = true
	if _chain.raw_deposit and raw < _last_raw:
		_chain.cook = true # finish_cooking is the only raw withdrawal in this run.
	if not _chain.meal_deposit and _chain.cook and meals > _last_meals and _has_deposit_cargo(game, JobSystem.JobType.HAUL_MEAL):
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
		if kind == VaultBuilding.Kind.AIR_RECYCLER:
			_air_recommended = true
			for building in game.buildings:
				if building.kind == kind and building.complete:
					return _fail_playthrough(game, "Next asks to place Air after completion; refuse duplicate Air")
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
					if kind == VaultBuilding.Kind.AIR_RECYCLER:
						_air = game.get_building_at(cell)
						_air_blueprints += 1
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
		FINISH_GROW_NEXT:
			return _enable_work(game, "haul") and _enable_work(game, "craft")
		HATCH_NEXT, RESERVE_NEXT:
			if _air == null or not _air.complete or game.get_completed_building_count(VaultBuilding.Kind.GROW_TRAY) != 1 or game.get_completed_building_count(VaultBuilding.Kind.KITCHEN) != 1:
				return _fail_playthrough(game, "hatch observation before food fixtures and Air are complete")
			if game.food_system.salvage < 4:
				return _fail_playthrough(game, "hatch observation unexpectedly lacks salvage reserve 4")
			return true # Time only; this slice finishes before WARNING, no seal required.
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
	_min_oxygen = minf(_min_oxygen, game.oxygen_system.oxygen)
	if game.oxygen_system.oxygen <= 15.0:
		return _fail_playthrough(game, "O2 must stay strictly above 15")
	if game.day_cycle.elapsed_seconds >= BreachSystem.WARNING_AT_SECONDS or game.breach_system.phase == BreachSystem.Phase.WARNING:
		return _fail_playthrough(game, "WARNING / elapsed >=60s is forbidden")
	for resident in originals:
		if resident.drafted:
			return _fail_playthrough(game, "original resident %d drafted" % resident.resident_id)
		if not resident.alive:
			return _fail_playthrough(game, "original resident %d died" % resident.resident_id)
		_min_food = minf(_min_food, resident.needs.food)
		if resident.needs.food < 20.0:
			return _fail_playthrough(game, "original resident %d food <20" % resident.resident_id)
	if game.user_paused or game.is_simulation_paused() or game.player_orders.is_help_open() or game.player_orders.is_work_priorities_open() or game.player_orders.breach_warning_panel.visible:
		return _fail_playthrough(game, "unexpected pause/modal/ended state")
	return true


func _check_air_state(game: VaultGame) -> bool:
	if absf(game.oxygen_system.recycler_output_rate - 0.8) > RATE_TOLERANCE or absf(game.oxygen_system.net_rate - 0.48) > RATE_TOLERANCE:
		return _fail_playthrough(game, "powered Air requires recycler output 0.8 and net +0.48")
	for kind in LOAD_KINDS:
		if game.get_completed_building_count(kind) != 1:
			return _fail_playthrough(game, "expected exactly one completed %s" % VaultBuilding.KIND_NAMES[kind])
		for building in game.buildings:
			if building.kind == kind and (building.manually_disabled or not building.powered or game.power_grid.is_building_shed(building.building_id)):
				return _fail_playthrough(game, "%s must remain enabled, powered, unshed" % building.get_display_name())
	if game.power_grid.demand != 9 or game.power_grid.served != 9 or game.power_grid.shed_count != 0:
		return _fail_playthrough(game, "Air production requires demand/served 9/9 and shed 0")
	if game.food_system.salvage != 14:
		return _fail_playthrough(game, "Air production must leave salvage 14 for future hatch slice")
	return true


func _air_flags() -> Dictionary:
	return {"recommended": _air_recommended, "blueprints": _air_blueprints, "powered_tick": _powered_tick, "rise_tick": _air_rise_tick}


func _power_state(game: VaultGame) -> String:
	var fixtures: Array[String] = []
	for building in game.buildings:
		fixtures.append("%s@%s complete=%s enabled=%s powered=%s shed=%s core=%s" % [
			building.get_display_name(), building.cell, building.complete, not building.manually_disabled,
			building.powered, game.power_grid.is_building_shed(building.building_id), building.is_emergency_core])
	return "supply=%d demand=%d served=%d shed=%d; %s" % [game.power_grid.supply, game.power_grid.demand, game.power_grid.served, game.power_grid.shed_count, str(fixtures)]


func _fail_playthrough(game: VaultGame, reason: String) -> bool:
	_assert_true(false, "%s; tick=%d elapsed=%.1fs min food=%.2f O2=%.6f min O2=%.6f output=%.2f net=%.2f; last Next=%s; hint history=%s; inventory=%s pending raw=%d meals=%d; fixture power=%s; A=%s meal tick=%d; B=%s; jobs=%s" % [
		reason, _tick, game.day_cycle.elapsed_seconds, _min_food, game.oxygen_system.oxygen, _min_oxygen,
		game.oxygen_system.recycler_output_rate, game.oxygen_system.net_rate, str(_last_step), str(_hint_history),
		str(game.food_system.serialize()), game.job_system.get_pending_raw_food(), game.job_system.get_pending_meals(),
		_power_state(game), str(_chain), _meal_tick, str(_air_flags()), str(game.job_system.jobs)])
	return false
