extends "res://tests/test_runner.gd"

const TICK_CAP := 1600
const SEAL_DEADLINE := BreachSystem.WARNING_AT_SECONDS + BreachSystem.GRACE_SECONDS
const AIR := ["Next: YOU place Air Recycler · THEY craft it", "Designate AIR $14 and keep it powered (3). Craft auto-builds the blueprint.", "air"]
const CHARGE := ["Next: YOU place a Charge Node · THEY supply/build", "Designate CHARGE. Haul + Craft auto-claim the blueprint. Adds +7 power.", "generator"]
const FINISH_CHARGE := ["Next: YOU leave Haul + Craft on · THEY finish the Charge Node", "Keep Haul + Craft above OFF so crew supply and finish the Charge Node blueprint.", "select"]
const GROW := ["Next: YOU place Grow Tray · THEY haul output", "Designate GROW and keep it powered. Haul defaults move raw food to stock.", "grow"]
const FINISH_NUTRIENT := ["Next: YOU leave Haul + Craft on · THEY finish the Nutrient Station", "Keep Haul + Craft above OFF so crew supply and finish the Nutrient Station blueprint.", "select"]
const FINISH_GROW := ["Next: YOU leave Haul + Craft on · THEY finish the Grow Tray", "Keep Haul + Craft above OFF so crew supply and finish the Grow Tray blueprint.", "select"]
const NUTRIENT := ["Next: YOU place Nutrient Station · THEY cook/haul", "Designate NUTRI, power it, leave Cook + Haul above OFF.", "kitchen"]
const DIG_NEXT := [
	["Next: YOU mark rock [E] · THEY dig on Dig defaults", "DIG [E] designates rock. Undrafted crew auto-claim Dig (default rank 3). Draft is optional.", "dig"],
	["Next: YOU keep marking digs [E] · THEY dig/haul alone", "Keep designating connected rock. They dig then haul rubble without draft. PRIORITIES [P] only to specialize.", "dig"],
]
const PLACE_CRISIS := ["Next: YOU place bunks · THEY craft", "Place bunks so tired undrafted crew have a bed.", "bed"]
const PLACE_TWO := ["Next: YOU place 2 bunks · THEY craft from Craft", "Place BUNK blueprints on carved floor. Undrafted Craft priority finishes them.", "bed"]
const FINISH := ["Next: YOU leave Haul + Craft on · THEY finish the bunks", "Keep Haul + Craft above OFF so crew supply and finish the bunk blueprints.", "select"]
# Disclosed deterministic empty chamber floor, matching the sibling walks.
# This fixture is untouched begin_shift; no staged dig/bunks or meal/Air claim.
const BUNK_CELLS := [Vector2i(20, 16), Vector2i(21, 17)]

# Empty walkable chamber floor beside Bay; not bunks, hatch, or starters.
const CHARGE_CELL := Vector2i(20, 17)
# Empty chamber floor beside starter Bay (19,17), within Lumen (22,14).
const GROW_CELL := Vector2i(19, 16)
const THIRD_BUNK_CELL := Vector2i(19, 18)
# Bay-adjacent empty chamber floor, distinct from every opening fixture.
const KITCHEN_CELL := Vector2i(18, 17)
# Empty chamber floor northwest of Bay, within starter Lumen coverage.
const AIR_CELL := Vector2i(18, 16)
const DAY7 := ["Next: YOU designate needs · THEY hold Day 7", "Keep designating dig/build/stockpile. Defaults keep food, power, and air running.", "select"]

var _air: VaultBuilding
var _air_placements := 0
var _air_supplied := false
var _air_craft_claimed := false
var _air_crafted := false
var _air_complete_elapsed := -1.0
var _day7_tip_elapsed := -1.0

var _kitchen: VaultBuilding
var _kitchen_placements := 0
var _nutrient_finish_observed := false
var _kitchen_supplied := false
var _kitchen_craft_claimed := false
var _kitchen_crafted := false
var _kitchen_complete_elapsed := -1.0
var _air_tip_elapsed := -1.0
var _seal_elapsed := -1.0
var _hatch_supplied := false
var _hatch_craft_claimed := false
var _hatch_crafted := false

var _third_bunk: VaultBuilding
var _third_bunk_elapsed := -1.0
var _grow: VaultBuilding
var _grow_complete_elapsed := -1.0
var _nutrient_tip_elapsed := -1.0
var _grow_placements := 0
var _grow_finish_observed := false
var _grow_supplied := false
var _grow_craft_claimed := false
var _grow_crafted := false
var _charge: VaultBuilding
var _charge_tip_elapsed := -1.0
var _charge_complete_elapsed := -1.0
var _grow_tip_elapsed := -1.0
var _warning_resumed := false
var _warning_count := 0
var _open_count := 0
var _charge_placements := 0
var _charge_supplied := false
var _charge_craft_claimed := false
var _charge_crafted := false
var _refunds := 0
var _targets: Array[Vector2i] = []
var _designated: Dictionary = {}
var _excavated: Dictionary = {}
var _crafted: Dictionary = {}
var _bunks: Array[VaultBuilding] = []
var _starters: Array[VaultBuilding] = []
var _history: Array[String] = []
var _last_tuple: Array = []
var _tick := 0
var _min_food := 100.0
var _min_rest := 100.0
var _last_salvage := 48
var _rubble_deliveries := 0
var _last_raw := 4
var _last_meals := 12
# First observations persist even if cargo clears or another resident eats.
var _meal_proof := {"cook_claim": -1.0, "cook_work": -1.0, "raw_withdraw": -1.0,
	"meal_cargo": -1.0, "haul_pickup": -1.0, "haul_deposit": -1.0}
var _kitchen_meal_jobs: Dictionary = {}
var _meal_stock_deltas: Array[String] = []


func _run() -> void:
	_run_case("Untouched Next-driven Dig + two opening bunks + Charge + crisis third bunk + powered Grow + Kitchen + Air to Day-7 tip and one O2 tick with natural seal by 80", _walk)
	print("FRESH WING AIR FINISH: %s — %d assertions, %d failures" % ["FAIL" if _failure_count else "PASS", _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _walk() -> void:
	var game := _spawn_game()
	game.begin_shift()
	var originals: Array[VaultResident] = game.residents.duplicate()
	_starters.assign(game.buildings)
	_assert_equal(game.food_system.salvage, 48, "untouched starting salvage")
	_assert_equal(game.food_system.meals, 12, "untouched starting meals")
	_assert_equal(game.food_system.raw_food, 4, "untouched starting raw food")
	_assert_equal(game.day_cycle.elapsed_seconds, 0.0, "untouched starting clock")
	_assert_equal(originals.size(), 4, "four originals")
	_assert_equal(_starters.size(), 3, "only starter Core/Lumen/Bay")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.GENERATOR), 1, "starter Core")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.LAMP), 1, "starter Lumen")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.STOCKPILE), 1, "starter Bay")
	_assert_equal(game.power_grid.supply, 2, "starter grid supply")
	_assert_true(CHARGE_CELL not in BUNK_CELLS and CHARGE_CELL != BreachSystem.HATCH_CELL, "Charge cell excludes bunks/hatch")
	_assert_true(game.map_grid.is_walkable(CHARGE_CELL) and game.get_building_at(CHARGE_CELL) == null, "disclosed Charge cell starts empty walkable floor")
	_assert_true(MapGrid.CHAMBER.has_point(GROW_CELL) and game.map_grid.get_tile(GROW_CELL) == MapGrid.Tile.FLOOR, "Grow starts on chamber floor")
	_assert_true(game.map_grid.is_walkable(GROW_CELL) and game.get_building_at(GROW_CELL) == null, "Grow starts empty and walkable")
	_assert_true(GROW_CELL not in BUNK_CELLS and GROW_CELL != CHARGE_CELL and GROW_CELL != BreachSystem.HATCH_CELL, "Grow excludes bunks/Charge/hatch")
	var bay := game.get_building_at(Vector2i(19, 17))
	_assert_true(bay != null and bay.kind == VaultBuilding.Kind.STOCKPILE and bay in _starters and GROW_CELL.distance_to(bay.cell) == 1.0, "Grow beside starter Bay (19,17)")
	var lumen := game.get_building_at(Vector2i(22, 14))
	_assert_true(lumen != null and lumen.kind == VaultBuilding.Kind.LAMP and lumen in _starters, "starter Lumen at (22,14)")
	_assert_true(game.lighting_system.is_cell_lit(GROW_CELL), "Grow in starter Lumen coverage")
	for starter in _starters:
		_assert_true(GROW_CELL != starter.cell, "Grow distinct from starter: %s" % starter.cell)
	game.breach_system.warning_started.connect(func() -> void: _warning_count += 1)
	game.breach_system.breach_opened.connect(func() -> void: _open_count += 1)
	for cell in BUNK_CELLS:
		_assert_true(game.map_grid.get_tile(cell) == MapGrid.Tile.FLOOR and game.get_building_at(cell) == null, "disclosed bunk cell starts empty floor: %s" % cell)
	for x in range(MapGrid.CHAMBER.position.x, MapGrid.CHAMBER.end.x):
		var cell := Vector2i(x, MapGrid.CHAMBER.position.y - 1)
		_targets.append(cell)
		_assert_equal(game.map_grid.get_tile(cell), MapGrid.Tile.ROCK, "target starts rock: %s" % cell)
	game.map_grid.rubble_created.connect(_observe_excavation.bind(game))
	_last_raw = game.food_system.raw_food
	_last_meals = game.food_system.meals # Starting 12 never counts as a deposit.
	game.food_system.inventory_changed.connect(_observe_inventory.bind(game))
	if _failure_count:
		_dispose(game)
		return
	for index in TICK_CAP:
		_tick = index + 1
		if not _check_state(game, originals):
			break
		if game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged:
			if not _resume_warning(game):
				break
		var step: Dictionary = game.player_orders._primary_next_step()
		var tuple := [step.text, step.help, step.tool]
		if tuple != _last_tuple:
			_history.append("tick=%d elapsed=%.1f: %s" % [_tick, game.day_cycle.elapsed_seconds, str(tuple)])
			_last_tuple = tuple
		if not _check_state(game, originals):
			break
		var tool_before: String = game.active_tool
		if tuple == DAY7:
			_day7_tip_elapsed = game.day_cycle.elapsed_seconds
			_check_day7_success(game)
			if _failure_count or not _check_intermediate_drain(game, originals):
				_diagnostics(game)
				_dispose(game)
				return
			var oxygen_before: float = game.oxygen_system.oxygen
			game.step_simulation(VaultGame.SIMULATION_TICK) # Exactly one post-tip tick; no Day-7 action.
			var oxygen_after: float = game.oxygen_system.oxygen
			_check_state(game, originals)
			var after: Dictionary = game.player_orders._primary_next_step()
			_assert_equal([after.text, after.help, after.tool], DAY7, "same exact Day-7 tuple after one tick")
			_assert_equal(game.active_tool, tool_before, "Day-7 observation/tick preserves active tool")
			_assert_approximately(game.day_cycle.elapsed_seconds, _day7_tip_elapsed + VaultGame.SIMULATION_TICK, 0.00001, "exactly one post-tip tick")
			_assert_approximately(oxygen_after - oxygen_before, 0.048, 0.0001, "sealed powered Air raises O2 by 0.048 in one tick")
			_check_day7_success(game)
			if not _failure_count:
				print("fresh-wing stocked-meal proof PASS: latch timings (seconds)=%s; meal stock deltas=%s; starting-raw (4) Kitchen cook->haul; not Grow provenance or sustainable food supply" % [str(_meal_proof), str(_meal_stock_deltas)])
				print("Fresh wing Air finish PASS: Air tip=%.1fs Air complete=%.1fs Day-7 tip=%.1fs; O2 %.6f->%.6f delta=%.6f; WARNING Resume=%s count=%d; Air cell=%s powered=%s delivered=%d; PWR %d/%d demand=%d no shedding; SEALED at %.1fs zero OPEN; ten buildings; salvage form: stock(%d)+rubble(%d)+hatch delivered(%d)+transit(%d)+third bunk delivered(%d)+transit(%d)+Kitchen delivered(%d)+transit(%d)+Air delivered(%d)+transit(%d)=38; min food=%.2f min rest=%.2f" % [_air_tip_elapsed, _air_complete_elapsed, _day7_tip_elapsed, oxygen_before, oxygen_after, oxygen_after - oxygen_before, _warning_resumed, _warning_count, AIR_CELL, _air.powered, _air.delivered, game.power_grid.supply, game.power_grid.served, game.power_grid.demand, _seal_elapsed, game.food_system.salvage, _uncredited_rubble(game), game.breach_system.patch_delivered, game.job_system.get_breach_supply_in_transit(), _third_bunk.delivered, _third_bunk_transit(game), _kitchen.delivered, _kitchen_transit(game), _air.delivered, _air_transit(game), _min_food, _min_rest])
			else:
				_diagnostics(game)
			_dispose(game)
			return
		var acted := _act(game, tuple)
		_assert_equal(game.active_tool, tool_before, "recommended act preserves active tool")
		if not acted or _failure_count:
			break
		if not _check_intermediate_drain(game, originals):
			break
		var work_before: Dictionary = {}
		for bunk in _bunks:
			work_before[bunk.building_id] = bunk.construction_left
		var charge_work_before: float = _charge.construction_left if _charge != null else 0.0
		var grow_work_before: float = _grow.construction_left if _grow != null else 0.0
		var kitchen_work_before: float = _kitchen.construction_left if _kitchen != null else 0.0
		var air_work_before: float = _air.construction_left if _air != null else 0.0
		var patch_work_before: float = game.breach_system.patch_work_left
		game.step_simulation(VaultGame.SIMULATION_TICK)
		if game.breach_system.patch_work_left < patch_work_before and game.breach_system.is_supplied():
			_hatch_crafted = true
		if _air != null:
			if _air.construction_left < air_work_before and _air.delivered == 14:
				_air_crafted = true
			if _air.complete and _air_complete_elapsed < 0.0:
				_air_complete_elapsed = game.day_cycle.elapsed_seconds
		if _kitchen != null:
			if _kitchen.construction_left < kitchen_work_before and _kitchen.delivered == 10:
				_kitchen_crafted = true
			if _kitchen.complete and _kitchen_complete_elapsed < 0.0:
				_kitchen_complete_elapsed = game.day_cycle.elapsed_seconds
		if _grow != null:
			if _grow.construction_left < grow_work_before and _grow.delivered == 12:
				_grow_crafted = true
			if _grow.complete and _grow_complete_elapsed < 0.0:
				_grow_complete_elapsed = game.day_cycle.elapsed_seconds
		if _charge != null:
			if _charge.construction_left < charge_work_before and _charge.delivered == 18:
				_charge_crafted = true
			if _charge.complete and _charge_complete_elapsed < 0.0:
				_charge_complete_elapsed = game.day_cycle.elapsed_seconds
		for bunk in _bunks:
			if bunk.construction_left < float(work_before[bunk.building_id]) and bunk.delivered == bunk.get_cost():
				_crafted[bunk.building_id] = true
		if not _check_state(game, originals):
			break
	if not _failure_count:
		_stop(game, "1600-tick cap without powered Air/Day-7 milestone")
	_dispose(game)


func _act(game: VaultGame, tuple: Array) -> bool:
	if _air != null and tuple != AIR and tuple != FINISH:
		return _stop(game, "post-Air Rec/medical/unexpected Next blocks walk: %s" % str(tuple))
	if tuple == AIR:
		if _air != null:
			return _enable_supply_and_craft(game) # Exact repeated tip never duplicates Air.
		_air_tip_elapsed = game.day_cycle.elapsed_seconds
		_check_air_checkpoint(game)
		_assert_true(MapGrid.CHAMBER.has_point(AIR_CELL) and game.map_grid.get_tile(AIR_CELL) == MapGrid.Tile.FLOOR, "Air on disclosed chamber floor")
		_assert_true(game.map_grid.is_walkable(AIR_CELL) and game.get_building_at(AIR_CELL) == null, "Air empty walkable at placement")
		_assert_true(game.lighting_system.is_cell_lit(AIR_CELL), "Air lit at placement")
		_assert_true(AIR_CELL not in BUNK_CELLS and AIR_CELL not in [CHARGE_CELL, GROW_CELL, THIRD_BUNK_CELL, KITCHEN_CELL, BreachSystem.HATCH_CELL], "Air distinct from retained fixtures/hatch")
		for starter in _starters:
			_assert_true(AIR_CELL != starter.cell, "Air distinct from starter %s" % starter.cell)
		var bay := game.get_building_at(Vector2i(19, 17))
		_assert_false(game.map_grid.find_path(bay.cell, AIR_CELL).is_empty(), "Air reachable from Bay")
		for resident in game.residents:
			_assert_false(game.map_grid.find_path(resident.get_cell(game.map_grid), AIR_CELL).is_empty(), "Air reachable by original %d" % resident.resident_id)
		if _failure_count:
			return false
		if not game.place_blueprint(VaultBuilding.Kind.AIR_RECYCLER, AIR_CELL):
			return _stop(game, "real Air placement rejected: %s" % game.status_message)
		_air = game.get_building_at(AIR_CELL)
		_air_placements += 1
		_assert_true(_air != null and not _air.complete and _air.get_cost() == 14, "one real incomplete Air costing 14")
		_assert_equal(game.buildings.size(), 10, "ten buildings at Air placement")
		return _failure_count == 0
	if tuple == FINISH_NUTRIENT:
		if _kitchen == null or _kitchen.complete:
			return _stop(game, "Nutrient finish requires the retained unfinished Kitchen")
		_nutrient_finish_observed = true
		return _enable_supply_and_craft(game)
	if tuple == NUTRIENT:
		if _kitchen != null:
			return _enable_supply_and_craft(game) # Repeated Nutrient tip never duplicates Kitchen.
		_nutrient_tip_elapsed = game.day_cycle.elapsed_seconds
		_check_nutrient_checkpoint(game)
		print("Nutrient checkpoint elapsed=%.1fs breach phase=%s patch_delivered=%d patch_work_left=%.3f seal elapsed=%.1fs" % [_nutrient_tip_elapsed, BreachSystem.Phase.keys()[game.breach_system.phase], game.breach_system.patch_delivered, game.breach_system.patch_work_left, _seal_elapsed])
		_assert_true(MapGrid.CHAMBER.has_point(KITCHEN_CELL) and game.map_grid.get_tile(KITCHEN_CELL) == MapGrid.Tile.FLOOR, "Kitchen on disclosed chamber floor")
		_assert_true(game.map_grid.is_walkable(KITCHEN_CELL) and game.get_building_at(KITCHEN_CELL) == null, "Kitchen empty walkable at placement")
		_assert_true(game.lighting_system.is_cell_lit(KITCHEN_CELL), "Kitchen lit at placement")
		_assert_true(KITCHEN_CELL not in BUNK_CELLS and KITCHEN_CELL not in [CHARGE_CELL, GROW_CELL, THIRD_BUNK_CELL, BreachSystem.HATCH_CELL], "Kitchen distinct from all designated fixtures/hatch")
		var bay := game.get_building_at(Vector2i(19, 17))
		_assert_true(bay != null and bay in _starters and bay.kind == VaultBuilding.Kind.STOCKPILE and KITCHEN_CELL.distance_to(bay.cell) == 1.0, "Kitchen adjacent to starter Bay")
		_assert_false(game.map_grid.find_path(bay.cell, KITCHEN_CELL).is_empty(), "Kitchen reachable from Bay")
		for resident in game.residents:
			_assert_false(game.map_grid.find_path(resident.get_cell(game.map_grid), KITCHEN_CELL).is_empty(), "Kitchen reachable by original %d" % resident.resident_id)
		for starter in _starters:
			_assert_true(KITCHEN_CELL != starter.cell, "Kitchen distinct from starter %s" % starter.cell)
		if _failure_count:
			return false
		if not game.place_blueprint(VaultBuilding.Kind.KITCHEN, KITCHEN_CELL):
			return _stop(game, "real Kitchen placement rejected: %s" % game.status_message)
		_kitchen = game.get_building_at(KITCHEN_CELL)
		_kitchen_placements += 1
		_assert_true(_kitchen != null and not _kitchen.complete and _kitchen.get_cost() == 10, "one real incomplete Kitchen costing 10")
		_assert_equal(game.buildings.size(), 9, "nine buildings at Kitchen placement")
		var after := game.player_orders._primary_next_step()
		_assert_equal([after.text, after.help, after.tool], FINISH_NUTRIENT, "Kitchen placement immediately gives exact Nutrient finish tuple")
		return _failure_count == 0
	if tuple == FINISH_GROW:
		if _grow == null or _grow.complete or not game.buildings.has(_grow):
			return _stop(game, "Grow finish without retained unfinished blueprint")
		_grow_finish_observed = true
		return _enable_supply_and_craft(game)
	if tuple == GROW:
		if _grow == null:
			_grow_tip_elapsed = game.day_cycle.elapsed_seconds
			_check_grow_checkpoint(game)
			_assert_true(_grow_tip_elapsed < 60.0, "Grow tip/placement strictly before 60s")
			if _failure_count:
				return false
			if not game.place_blueprint(VaultBuilding.Kind.GROW_TRAY, GROW_CELL):
				return _stop(game, "real Grow placement rejected: %s" % game.status_message)
			_grow = game.get_building_at(GROW_CELL)
			_grow_placements += 1
			_assert_true(_grow != null and not _grow.complete and _grow.get_cost() == 12, "one real incomplete Grow blueprint costing 12")
			var after: Dictionary = game.player_orders._primary_next_step()
			_assert_equal([after.text, after.help, after.tool], FINISH_GROW, "Grow placement immediately gives exact finish tuple")
			return _failure_count == 0
		if _grow.complete:
			return _stop(game, "Grow tip asks to place after Grow already complete")
		return _stop(game, "repeated Grow place tip with retained unfinished blueprint")
	if tuple == FINISH_CHARGE:
		if _charge == null or _charge.complete or not game.buildings.has(_charge):
			return _stop(game, "Charge finish without retained unfinished blueprint")
		return _enable_supply_and_craft(game)
	if tuple == CHARGE:
		if _charge == null:
			_charge_tip_elapsed = game.day_cycle.elapsed_seconds
			_check_charge_checkpoint(game)
			if _failure_count:
				return false
			if not game.place_blueprint(VaultBuilding.Kind.GENERATOR, CHARGE_CELL):
				return _stop(game, "real Charge placement rejected: %s" % game.status_message)
			_charge = game.get_building_at(CHARGE_CELL)
			_charge_placements += 1
			_assert_true(_charge != null and not _charge.complete and not _charge.is_emergency_core, "one real incomplete non-Core Charge blueprint")
			_assert_true(game.day_cycle.elapsed_seconds < 60.0, "Charge placed strictly before 60s")
			var after: Dictionary = game.player_orders._primary_next_step()
			_assert_equal([after.text, after.help, after.tool], FINISH_CHARGE, "Charge placement immediately gives exact finish tuple")
			return _failure_count == 0
		if _charge.complete:
			return _stop(game, "Charge tip asks to place after Charge already complete")
		return _stop(game, "repeated Charge place tip with retained unfinished blueprint")
	if tuple in DIG_NEXT:
		for cell in _targets:
			if game.map_grid.get_tile(cell) == MapGrid.Tile.FLOOR or game.map_grid.dig_marks.has(cell):
				continue
			if not game.map_grid.queue_dig(cell):
				return _stop(game, "real dig designation rejected at %s" % cell)
			_designated[cell] = true
			game.job_system.queue_dig(cell)
			return true
		return true # All twelve already marked; time only for unfinished work.
	if tuple == PLACE_CRISIS or tuple == PLACE_TWO:
		if _grow != null:
			if _third_bunk != null or _bunks.size() == 3:
				return _stop(game, "fourth bunk request forbidden")
			if tuple != PLACE_CRISIS or _bunks.size() != 2:
				return _stop(game, "third bunk requires exact post-Grow crisis place tuple and two opening bunks")
			_assert_true(game.buildings.has(_grow) and _grow_placements == 1, "Grow blueprint exists before third bunk placement")
			_assert_true(MapGrid.CHAMBER.has_point(THIRD_BUNK_CELL) and game.map_grid.get_tile(THIRD_BUNK_CELL) == MapGrid.Tile.FLOOR, "third bunk on chamber floor")
			_assert_true(game.map_grid.is_walkable(THIRD_BUNK_CELL) and game.get_building_at(THIRD_BUNK_CELL) == null, "third bunk empty walkable floor with no fixture overlap")
			_assert_true(game.lighting_system.is_cell_lit(THIRD_BUNK_CELL), "third bunk lit at placement")
			var bay := game.get_building_at(Vector2i(19, 17))
			_assert_true(bay != null and bay in _starters and bay.kind == VaultBuilding.Kind.STOCKPILE and THIRD_BUNK_CELL.distance_to(bay.cell) == 1.0, "third bunk adjacent to starter Bay")
			_assert_true(THIRD_BUNK_CELL != BreachSystem.HATCH_CELL and THIRD_BUNK_CELL not in BUNK_CELLS and THIRD_BUNK_CELL != CHARGE_CELL and THIRD_BUNK_CELL != GROW_CELL, "third bunk excludes hatch and other designated fixtures")
			if _failure_count:
				return false
			if not game.place_blueprint(VaultBuilding.Kind.BED, THIRD_BUNK_CELL):
				return _stop(game, "real third bunk placement rejected: %s" % game.status_message)
			_third_bunk = game.get_building_at(THIRD_BUNK_CELL)
			_third_bunk_elapsed = game.day_cycle.elapsed_seconds
			_bunks.append(_third_bunk)
			_assert_true(_third_bunk != null and not _third_bunk.complete and _third_bunk.get_cost() == 8, "exactly one real incomplete third bunk costing 8")
			return _failure_count == 0
		# Opening place-2 and mid-dig crises still place only the original pair.
		if _bunks.size() != 0:
			return _stop(game, "additional bunk request before Grow placement forbidden")
		for cell in BUNK_CELLS:
			if game.get_building_at(cell) != null or not game.place_blueprint(VaultBuilding.Kind.BED, cell):
				return _stop(game, "real opening bunk placement rejected at %s: %s" % [cell, game.status_message])
			_bunks.append(game.get_building_at(cell))
		return true
	if tuple == FINISH:
		if _air != null and (_third_bunk == null or _third_bunk.complete or not _bunks[0].complete or not _bunks[1].complete):
			return _stop(game, "post-Air finish-bunk tip requires unfinished third bunk only")
		var incomplete := false
		for bunk in _bunks:
			incomplete = incomplete or not bunk.complete
		if not incomplete:
			return _stop(game, "finish recommendation without incomplete bunks")
		return _enable_supply_and_craft(game)

	return _stop(game, "Rec/medical/unexpected full Next tuple blocks walk: %s" % str(tuple))


func _uncredited_rubble(game: VaultGame) -> int:
	var amount := 0
	var carriers: Dictionary = {}
	for resident in game.residents:
		if resident.current_job_type == JobSystem.JobType.HAUL_RUBBLE and resident.carrying > 0:
			amount += resident.carrying
			carriers[resident.current_job_id] = true
	for job: Dictionary in game.job_system.jobs:
		# HAUL_RUBBLE.amount remains populated during carry. Exclude that job
		# when its carrier was counted above; supply-build cargo is separate.
		if int(job.type) == JobSystem.JobType.HAUL_RUBBLE and not bool(job.done) and not carriers.has(int(job.id)):
			amount += int(job.amount)
	return amount


func _check_state(game: VaultGame, originals: Array[VaultResident]) -> bool:
	_observe_stocked_meal(game)
	if _open_count > 0 or game.breach_system.phase == BreachSystem.Phase.OPEN or game.breach_system.serialize().open_emitted:
		return _stop(game, "OPEN event/phase/history forbidden")
	if game.breach_system.is_sealed() and _seal_elapsed < 0.0:
		_seal_elapsed = game.day_cycle.elapsed_seconds
		print("Natural hatch SEALED elapsed=%.1fs patch_delivered=%d patch_work_left=%.3f" % [_seal_elapsed, game.breach_system.patch_delivered, game.breach_system.patch_work_left])
	if game.day_cycle.elapsed_seconds >= SEAL_DEADLINE and not game.breach_system.is_sealed():
		return _stop(game, "natural hatch not SEALED by elapsed 80; continuation forbidden")
	if _seal_elapsed > SEAL_DEADLINE:
		return _stop(game, "natural seal missed elapsed 80")
	if _seal_elapsed >= 0.0 and not game.breach_system.is_sealed():
		return _stop(game, "post-seal path must stay SEALED")
	if game.power_grid.brownout_active:
		return _stop(game, "power shedding forbidden")
	if _kitchen != null and _kitchen.complete and (not _kitchen.powered or _kitchen.manually_disabled):
		return _stop(game, "completed Kitchen must stay powered/enabled")
	if _air != null and _air.complete:
		if not _air.powered or _air.manually_disabled or game.power_grid.supply != 9 or game.power_grid.demand != 9 or game.power_grid.served != 9:
			return _stop(game, "completed Air must stay powered/enabled with PWR supply=demand=served=9")
	if _grow != null and _grow.complete and (not _grow.powered or _grow.manually_disabled):
		return _stop(game, "completed Grow must stay powered/enabled")
	var expected_warning := game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged and not _warning_resumed and _warning_count == 1
	if game.ended or game.tutorial_open or game.player_orders.is_help_open() or game.player_orders.is_work_priorities_open() or game.player_orders.is_briefing_open():
		return _stop(game, "unexpected modal/ended")
	if expected_warning:
		if not game.user_paused or not game.is_simulation_paused() or not game.player_orders.breach_warning_panel.visible:
			return _stop(game, "real WARNING must pause with visible modal")
	elif game.is_simulation_paused() or game.player_orders.breach_warning_panel.visible:
		return _stop(game, "unexpected/second pause or warning modal")

	for resident in originals:
		_min_food = minf(_min_food, resident.needs.food)
		_min_rest = minf(_min_rest, resident.needs.rest)
		if not resident.alive or resident.drafted or resident.needs.food < 20.0 or resident.needs.rest < 15.0:
			return _stop(game, "original died/drafted or food<20/rest<15: %d" % resident.resident_id)
	for starter in _starters:
		if not game.buildings.has(starter) or not starter.complete or starter.manually_disabled or (starter.kind == VaultBuilding.Kind.LAMP and not starter.powered):
			return _stop(game, "starter Core/Lumen/Bay not retained/enabled or Lumen unpowered")
	var expected_buildings := _starters.size() + _bunks.size() + (1 if _charge != null else 0) + (1 if _grow != null else 0) + (1 if _kitchen != null else 0) + (1 if _air != null else 0)
	if game.buildings.size() != expected_buildings or _bunks.size() > 3 or _charge_placements > 1 or _grow_placements > 1 or _kitchen_placements > 1 or _air_placements > 1:
		return _stop(game, "unexpected/duplicate construction")
	if _third_bunk != null and (_grow == null or _third_bunk_elapsed < _grow_tip_elapsed or _bunks.size() != 3 or not game.buildings.has(_third_bunk)):
		return _stop(game, "third bunk without prior Grow or missing third blueprint")
	var charges := 0
	for building in game.buildings:
		if building.kind == VaultBuilding.Kind.GENERATOR and not building.is_emergency_core:
			charges += 1
	if charges != _charge_placements or (_charge != null and not game.buildings.has(_charge)):
		return _stop(game, "missing/duplicate non-Core Charge")
	var grows := 0
	var kitchens := 0
	var airs := 0
	for building in game.buildings:
		if building.kind == VaultBuilding.Kind.KITCHEN:
			kitchens += 1
		if building.kind == VaultBuilding.Kind.AIR_RECYCLER:
			airs += 1
		if building.kind == VaultBuilding.Kind.GROW_TRAY:
			grows += 1
	if grows != _grow_placements or (_grow != null and not game.buildings.has(_grow)):
		return _stop(game, "missing/duplicate Grow")
	if kitchens != _kitchen_placements or (_kitchen != null and not game.buildings.has(_kitchen)):
		return _stop(game, "missing/duplicate Kitchen")
	if airs != _air_placements or (_air != null and not game.buildings.has(_air)):
		return _stop(game, "missing/duplicate Air")
	var paid := game.breach_system.patch_delivered
	for bunk in _bunks:
		paid += bunk.delivered
	if _charge != null:
		paid += _charge.delivered
	if _grow != null:
		paid += _grow.delivered
	if _kitchen != null:
		paid += _kitchen.delivered
	if _air != null:
		paid += _air.delivered
	for resident in game.residents:
		if resident.is_forced_job:
			return _stop(game, "forced work forbidden")
		if resident.current_job_type in [JobSystem.JobType.SUPPLY_BUILD, JobSystem.JobType.BUILD]:
			var job: Dictionary = game.job_system._find_job(resident.current_job_id)
			var building := game.get_building_by_id(int(job.get("building_id", -1)))
			if building not in _bunks and building != _charge and building != _grow and building != _kitchen and building != _air:
				return _stop(game, "supply/Craft targets unexpected building")
			var work := "haul" if resident.current_job_type == JobSystem.JobType.SUPPLY_BUILD else "craft"
			if resident.is_forced_job or resident.get_work_priority(work) <= 0:
				return _stop(game, "supply/Craft must be ordinary enabled undrafted work")
			if resident.current_job_type == JobSystem.JobType.SUPPLY_BUILD:
				paid += resident.carrying
				if building == _air and resident.carrying == 14 and int(job.get("in_transit", 0)) == 14:
					_air_supplied = true
				if building == _kitchen and resident.carrying == 10 and int(job.get("in_transit", 0)) == 10:
					_kitchen_supplied = true
				if building == _charge and resident.carrying == 18 and int(job.get("in_transit", 0)) == 18:
					_charge_supplied = true
				if building == _grow and resident.carrying == 12 and int(job.get("in_transit", 0)) == 12:
					_grow_supplied = true
			elif building == _air and _air.delivered == 14:
				_air_craft_claimed = true
			elif building == _kitchen and _kitchen.delivered == 10:
				_kitchen_craft_claimed = true
			elif building == _grow and _grow.delivered == 12:
				_grow_craft_claimed = true
			elif building == _charge and _charge.delivered == 18:
				_charge_craft_claimed = true
		elif resident.current_job_type in [JobSystem.JobType.SUPPLY_BREACH, JobSystem.JobType.PATCH_BREACH]:
			var work := "haul" if resident.current_job_type == JobSystem.JobType.SUPPLY_BREACH else "craft"
			if resident.get_work_priority(work) <= 0:
				return _stop(game, "hatch supply/patch must be ordinary enabled work")
			if resident.current_job_type == JobSystem.JobType.SUPPLY_BREACH:
				paid += resident.carrying
				if resident.carrying == BreachSystem.PATCH_COST:
					_hatch_supplied = true
			elif game.breach_system.is_supplied():
				_hatch_craft_claimed = true
	if game.food_system.salvage + _uncredited_rubble(game) + paid != 48 + 3 * _excavated.size():
		return _stop(game, "salvage conservation violation (bunk/Charge/Grow/Kitchen/Air deliveries + rubble/build/hatch cargo counted once)")
	if _grow != null and _grow.delivered == 12:
		_assert_equal(_grow_residual(game) + (_third_bunk.delivered if _third_bunk != null else 0) + _third_bunk_transit(game) + (_kitchen.delivered if _kitchen != null else 0) + _kitchen_transit(game) + (_air.delivered if _air != null else 0) + _air_transit(game), 38, "Grow-supplied residual: stock + rubble + hatch delivered/transit + third bunk delivered/transit + Kitchen delivered/transit + Air delivered/transit = 38")
		if _third_bunk != null and _third_bunk.delivered == 8 and _kitchen != null and _kitchen.delivered == 10:
			_assert_equal(_grow_residual(game) + (_air.delivered if _air != null else 0) + _air_transit(game), 20, "third bunk/Kitchen paid: residual + Air delivered/transit = 20")
	return _failure_count == 0


func _kitchen_transit(game: VaultGame) -> int:
	var amount := 0
	if _kitchen != null:
		for job: Dictionary in game.job_system.jobs:
			if int(job.type) == JobSystem.JobType.SUPPLY_BUILD and not bool(job.done) and int(job.get("building_id", -1)) == _kitchen.building_id:
				amount += int(job.get("in_transit", 0))
	return amount


func _check_air_checkpoint(game: VaultGame) -> void:
	_assert_true(_nutrient_tip_elapsed >= _grow_complete_elapsed and _kitchen_complete_elapsed >= _nutrient_tip_elapsed and _air_tip_elapsed >= _kitchen_complete_elapsed, "Grow/Nutrient/Kitchen/Air milestones ordered")
	_assert_true(_nutrient_finish_observed, "driver observed and handled exact Nutrient finish tuple")
	_assert_equal(_kitchen_placements, 1, "exactly one Kitchen placement")
	_assert_true(_kitchen != null and _kitchen.complete and _kitchen.delivered == 10 and _kitchen.construction_left <= 0.0, "Kitchen genuinely supplied and completed")
	_assert_true(_kitchen_supplied and _kitchen_craft_claimed and _kitchen_crafted, "observed real Kitchen supply 10 and ordinary Craft claim/work")
	_assert_true(_kitchen.powered and not _kitchen.manually_disabled, "Kitchen powered and enabled")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.KITCHEN), 1, "one completed Kitchen")
	_assert_true(_grow.complete and _grow.powered and not _grow.manually_disabled, "Grow retained powered/enabled")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.AIR_RECYCLER), 0, "zero completed Air")
	for building in game.buildings:
		_assert_true(building.kind != VaultBuilding.Kind.AIR_RECYCLER, "no Air blueprint")
	_assert_equal(game.buildings.size(), 9, "starters + three bunks + Charge + Grow + Kitchen")
	_assert_equal(_bunks.size(), 3, "no fourth bunk")
	for bunk in _bunks.slice(0, 2):
		_assert_true(bunk.complete and bunk.delivered == 8, "opening bunk retained")
	_assert_true(_third_bunk != null and game.buildings.has(_third_bunk), "third bunk retained, unfinished allowed")
	_assert_true(_charge.complete and _charge.delivered == 18, "Charge retained")
	_assert_true(_warning_resumed, "exactly one WARNING Resume")
	_assert_equal(_warning_count, 1, "one WARNING event")
	_assert_equal(_open_count, 0, "zero OPEN events")
	_assert_false(game.breach_system.serialize().open_emitted, "zero OPEN history")
	_assert_true(game.breach_system.is_sealed() and _seal_elapsed >= BreachSystem.WARNING_AT_SECONDS and _seal_elapsed <= SEAL_DEADLINE, "natural hatch SEALED by 80")
	_assert_true(_hatch_supplied and _hatch_craft_claimed and _hatch_crafted, "observed automatic hatch supply and ordinary patch claim/work")
	_assert_equal(game.breach_system.patch_delivered, BreachSystem.PATCH_COST, "hatch fully supplied")
	_assert_equal(game.breach_system.patch_work_left, 0.0, "hatch patch finished")
	_assert_equal(_grow_residual(game) + _third_bunk.delivered + _third_bunk_transit(game) + _kitchen.delivered + _kitchen_transit(game), 38, "Kitchen extends Grow residual conservation by delivered/transit 10")
	_assert_equal(game.power_grid.supply, 9, "grid supply 9")
	_assert_equal(game.power_grid.served, 6, "Lumen 1 + Grow 3 + Kitchen 2 served")


func _third_bunk_transit(game: VaultGame) -> int:
	var amount := 0
	if _third_bunk != null:
		for job: Dictionary in game.job_system.jobs:
			if int(job.type) == JobSystem.JobType.SUPPLY_BUILD and not bool(job.done) and int(job.get("building_id", -1)) == _third_bunk.building_id:
				amount += int(job.get("in_transit", 0))
	return amount


func _grow_residual(game: VaultGame) -> int:
	return game.food_system.salvage + _uncredited_rubble(game) + game.breach_system.patch_delivered + game.job_system.get_breach_supply_in_transit()


func _check_charge_checkpoint(game: VaultGame) -> void:
	_assert_equal(_designated.size(), 12, "all twelve designated via real APIs")
	_assert_equal(_excavated.size(), 12, "all twelve emitted real dig rubble")
	for cell in _targets:
		_assert_equal(game.map_grid.get_tile(cell), MapGrid.Tile.FLOOR, "target genuinely excavated: %s" % cell)
	_assert_equal(game.map_grid.get_floor_cells().size(), 132, "exact twelve-floor expansion")
	_assert_equal(_bunks.size(), 2, "exactly two placed bunks")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.BED), 2, "two complete bunks")
	for bunk in _bunks:
		_assert_true(bunk.complete and bunk.delivered == 8 and bunk.construction_left <= 0.0 and _crafted.has(bunk.building_id), "bunk genuinely supplied and crafted")
	_assert_true(_rubble_deliveries > 0, "observed real rubble stock delivery")
	_assert_equal(game.food_system.salvage + _uncredited_rubble(game), 68, "48 + twelve dig yields - two paid bunks")
	if _uncredited_rubble(game) == 0:
		_assert_equal(game.food_system.salvage, 68, "all rubble credited stock")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.GENERATOR, true), 0, "stop before Charge placement")
	_assert_equal(game.buildings.size(), 5, "only starters plus two bunks")
	_assert_true(game.day_cycle.elapsed_seconds < 60.0, "strictly before warning")


func _check_grow_checkpoint(game: VaultGame) -> void:
	_assert_true(_charge_tip_elapsed >= 0.0 and _charge_tip_elapsed < 60.0, "Charge checkpoint before 60s")
	_assert_true(_charge_complete_elapsed >= _charge_tip_elapsed and _charge_complete_elapsed <= _grow_tip_elapsed and _grow_tip_elapsed < 80.0, "Charge then Grow strictly before 80s")
	_assert_equal(_charge_placements, 1, "exactly one Charge placement")
	_assert_true(_charge != null and _charge.complete and _charge.delivered == 18 and _charge.construction_left <= 0.0, "Charge fully supplied and complete")
	_assert_true(_charge_supplied, "observed real undrafted Haul carrying all 18 Charge salvage")
	_assert_true(_charge_craft_claimed, "observed ordinary enabled undrafted Craft claim supplied Charge")
	_assert_true(_charge_crafted, "observed real supplied Charge work reduction to completion")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.GENERATOR, true), 1, "one completed non-Core Charge")
	_assert_equal(game.power_grid.supply, 9, "grid supply corroborates 2 to 9")
	_assert_equal(game.buildings.size(), 6, "only starters, two bunks, one Charge; no Grow")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.BED), 2, "two bunks remain complete")
	_assert_equal(game.food_system.salvage + _uncredited_rubble(game) + game.breach_system.patch_delivered + game.job_system.get_breach_supply_in_transit(), 50, "68 minus 18 Charge, including any hatch salvage")
	_assert_equal(_open_count, 0, "no OPEN event")
	_assert_equal(_warning_count, 1 if _warning_resumed else 0, "at most one real warning Resume; never manufacture warning")


func _check_nutrient_checkpoint(game: VaultGame) -> void:
	_assert_true(_grow_tip_elapsed >= _charge_complete_elapsed and _grow_tip_elapsed < 60.0, "Charge then Grow placed before WARNING")
	_assert_true(_grow_complete_elapsed >= _grow_tip_elapsed and _grow_complete_elapsed <= _nutrient_tip_elapsed and _nutrient_tip_elapsed < 80.0, "Grow complete then exact Nutrient before 80s")
	_assert_true(_grow_finish_observed, "driver observed and handled exact Grow finish tuple")
	_assert_equal(_grow_placements, 1, "exactly one Grow placement")
	_assert_true(_grow != null and _grow.complete and _grow.delivered == 12 and _grow.construction_left <= 0.0, "Grow fully supplied and crafted complete")
	_assert_true(_grow.powered and not _grow.manually_disabled, "Grow independently powered and enabled")
	_assert_equal(_grow.get_power_demand(), 3, "Grow demand 3")
	_assert_true(_grow_supplied, "observed ordinary undrafted Haul carrying all 12 Grow salvage")
	_assert_true(_grow_craft_claimed, "observed ordinary enabled undrafted Craft claim supplied Grow")
	_assert_true(_grow_crafted, "observed real supplied Grow work reduction to completion")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.GROW_TRAY), 1, "one completed Grow")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.KITCHEN), 0, "zero completed Kitchen")
	var kitchens := 0
	for building in game.buildings:
		if building.kind == VaultBuilding.Kind.KITCHEN:
			kitchens += 1
	_assert_equal(kitchens, 0, "zero Kitchen blueprints or complete buildings")
	_assert_equal(game.buildings.size(), 8, "Core/Lumen/Bay/three bunks/Charge/Grow only")
	_assert_equal(_bunks.size(), 3, "exactly three bunks")
	_assert_true(_third_bunk != null and _third_bunk.cell == THIRD_BUNK_CELL and _third_bunk_elapsed >= _grow_tip_elapsed, "authorized post-Grow third bunk retained")
	for bunk in _bunks.slice(0, 2):
		_assert_true(bunk.complete and bunk.delivered == 8, "original complete bunk retained")
	_assert_true(_charge.complete and _charge.delivered == 18, "complete Charge retained")
	_assert_equal(game.power_grid.supply, 9, "grid supply 9")
	_assert_equal(game.power_grid.served, 4, "Lumen 1 plus Grow 3 served")
	_assert_equal(_grow_residual(game) + _third_bunk.delivered + _third_bunk_transit(game), 38, "stock + uncredited rubble + hatch delivered/transit + third-bunk delivered/transit = 38")
	if _third_bunk.delivered == 8:
		_assert_equal(_grow_residual(game), 30, "fully delivered third bunk leaves residual 30")
	_assert_true(_warning_resumed, "completed run requires genuine WARNING Resume")
	_assert_equal(_warning_count, 1, "exactly one genuine WARNING event")
	_assert_equal(_open_count, 0, "no OPEN history")


func _enable_supply_and_craft(game: VaultGame) -> bool:
	for resident in game.residents:
		if resident.alive and not resident.drafted:
			for work in ["haul", "craft"]:
				if resident.get_work_priority(work) == VaultResident.PRIORITY_DISABLED:
					if not resident.set_work_priority(work, VaultResident.DEFAULT_WORK_PRIORITY):
						return _stop(game, "recommended work enable rejected")
	return true


func _resume_warning(game: VaultGame) -> bool:
	_assert_false(_warning_resumed, "Resume at most once")
	_assert_equal(_warning_count, 1, "one real warning event")
	_assert_true(game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged, "real unacknowledged WARNING")
	_assert_true(game.user_paused and game.is_simulation_paused() and game.player_orders.breach_warning_panel.visible, "real modal/pause before Resume")
	_assert_approximately(game.day_cycle.elapsed_seconds, BreachSystem.WARNING_AT_SECONDS, 0.00001, "real WARNING at 60s")
	if _failure_count:
		return false
	# Sole exception to Next acts; WARNING's tool switch happens separately.
	game.acknowledge_breach_warning(true)
	_warning_resumed = true
	_assert_true(game.breach_system.warning_acknowledged, "Resume acknowledged")
	_assert_false(game.user_paused or game.is_simulation_paused() or game.player_orders.breach_warning_panel.visible, "Resume unpaused and modal hidden")
	return _failure_count == 0


func _observe_excavation(cell: Vector2i, amount: int, game: VaultGame) -> void:
	_assert_true(_designated.has(cell) and not _excavated.has(cell) and amount == 3, "organic excavation of unique designated target")
	var working := false
	for resident in game.residents:
		var job: Dictionary = game.job_system._find_job(resident.current_job_id)
		if resident.current_job_type == JobSystem.JobType.DIG and job.get("target") == cell and resident.alive and not resident.drafted and not resident.is_forced_job:
			working = true
	_assert_true(working, "dig signal occurs during real undrafted Dig job")
	_excavated[cell] = true


func _observe_inventory(game: VaultGame) -> void:
	_observe_stocked_meal(game)
	var raw: int = game.food_system.raw_food
	var meals: int = game.food_system.meals
	if _last_raw - raw == FoodSystem.COOK_INPUT:
		for resident in game.residents:
			if _is_kitchen_cook(game, resident) and resident.state == "Preparing meals" and resident.work_accumulator >= 4.0:
				_latch_meal("raw_withdraw", game)
	if meals != _last_meals:
		_meal_stock_deltas.append("%.1fs %d->%d" % [game.day_cycle.elapsed_seconds, _last_meals, meals])
	if meals > _last_meals and float(_meal_proof.raw_withdraw) >= 0.0:
		for resident in game.residents:
			var job: Dictionary = game.job_system._find_job(resident.current_job_id)
			if _is_kitchen_meal_carrier(resident, job) and _kitchen_meal_jobs.has(int(job.id)) and meals - _last_meals == int(job.in_transit):
				# add_meals emits before clearing in_transit/carrying; a later
				# eat in this same tick cannot erase this positive stock credit.
				_latch_meal("haul_deposit", game)
	_last_raw = raw
	_last_meals = meals
	if game.food_system.salvage > _last_salvage:
		var increase := game.food_system.salvage - _last_salvage
		var evidenced := false
		for resident in game.residents:
			if resident.current_job_type == JobSystem.JobType.HAUL_RUBBLE and resident.job_phase == "deposit" and resident.carrying == 3 and increase == 3:
				evidenced = true
				_rubble_deliveries += 1
			elif resident.current_job_type in [JobSystem.JobType.SUPPLY_BUILD, JobSystem.JobType.SUPPLY_BREACH]:
				# release_resident emits inventory_changed before clearing cargo.
				var job: Dictionary = game.job_system._find_job(resident.current_job_id)
				if resident.carrying == increase and int(job.get("in_transit", 0)) == increase and increase > 0:
					evidenced = true
					_refunds += 1
		_assert_true(evidenced, "stock increase is evidenced real rubble delivery or supply refund")
	_last_salvage = game.food_system.salvage


func _latch_meal(stage: String, game: VaultGame) -> void:
	if float(_meal_proof[stage]) < 0.0:
		_meal_proof[stage] = game.day_cycle.elapsed_seconds


func _is_kitchen_cook(game: VaultGame, resident: VaultResident) -> bool:
	if _kitchen == null or not _kitchen.complete or not _kitchen.powered or _kitchen.manually_disabled:
		return false
	var job: Dictionary = game.job_system._find_job(resident.current_job_id)
	return resident.alive and not resident.drafted and not resident.is_forced_job and resident.get_work_priority("cook") > 0 and resident.current_job_type == JobSystem.JobType.COOK and int(job.get("building_id", -1)) == _kitchen.building_id and job.get("target") == KITCHEN_CELL and not bool(job.get("done", false)) and int(job.get("reserved_by", -1)) == resident.resident_id


func _is_kitchen_meal_carrier(resident: VaultResident, job: Dictionary) -> bool:
	return resident.alive and not resident.drafted and not resident.is_forced_job and resident.get_work_priority("haul") > 0 and resident.current_job_type == JobSystem.JobType.HAUL_MEAL and int(job.get("type", -1)) == JobSystem.JobType.HAUL_MEAL and job.get("target") == KITCHEN_CELL and not bool(job.get("done", false)) and int(job.get("reserved_by", -1)) == resident.resident_id and resident.job_phase == "deposit" and resident.carrying_kind == "meal" and resident.carrying > 0 and resident.carrying == int(job.get("in_transit", 0))


func _observe_stocked_meal(game: VaultGame) -> void:
	for resident in game.residents:
		if _is_kitchen_cook(game, resident):
			_latch_meal("cook_claim", game)
			if resident.state == "Preparing meals" and resident.work_accumulator > 0.0:
				_latch_meal("cook_work", game)
	if float(_meal_proof.raw_withdraw) < 0.0:
		return
	for job: Dictionary in game.job_system.jobs:
		if int(job.type) == JobSystem.JobType.HAUL_MEAL and job.target == KITCHEN_CELL and not bool(job.get("done", false)) and int(job.get("amount", 0)) + int(job.get("in_transit", 0)) >= FoodSystem.COOK_OUTPUT:
			_kitchen_meal_jobs[int(job.id)] = true
			_latch_meal("meal_cargo", game)
	for resident in game.residents:
		var job: Dictionary = game.job_system._find_job(resident.current_job_id)
		if _is_kitchen_meal_carrier(resident, job) and _kitchen_meal_jobs.has(int(job.id)):
			_latch_meal("haul_pickup", game)


func _stop(game: VaultGame, reason: String) -> bool:
	_assert_true(false, reason)
	_diagnostics(game)
	return false


func _diagnostics(game: VaultGame) -> void:
	printerr("fresh-wing stocked-meal proof: elapsed=%.1fs timings=%s raw=%d meals=%d pending Kitchen=%d Kitchen cargo jobs=%s meal stock deltas=%s" % [game.day_cycle.elapsed_seconds, str(_meal_proof), game.food_system.raw_food, game.food_system.meals, game.job_system.get_pending_meals_at(KITCHEN_CELL), str(_kitchen_meal_jobs), str(_meal_stock_deltas)])
	printerr("Fresh wing FAIL: tick=%d elapsed=%.1fs salvage=%d rubble=%d dug=%d/12 bunks=%d min food=%.3f min rest=%.3f" % [_tick, game.day_cycle.elapsed_seconds, game.food_system.salvage, _uncredited_rubble(game), _excavated.size(), game.get_completed_building_count(VaultBuilding.Kind.BED), _min_food, _min_rest])
	printerr("Charge tip=%.1f complete=%.1f Grow tip=%.1f WARNING Resume=%s warnings=%d opens=%d breach=%s power=%d" % [_charge_tip_elapsed, _charge_complete_elapsed, _grow_tip_elapsed, _warning_resumed, _warning_count, _open_count, str(game.breach_system.serialize()), game.power_grid.supply])
	printerr("Grow tip=%.1f complete=%.1f Nutrient tip=%.1f" % [_grow_tip_elapsed, _grow_complete_elapsed, _nutrient_tip_elapsed])
	printerr("Kitchen complete=%.1fs Air tip=%.1fs seal elapsed=%.1fs; Kitchen delivered=%d transit=%d powered=%s; hatch supplied=%s claimed=%s crafted=%s" % [_kitchen_complete_elapsed, _air_tip_elapsed, _seal_elapsed, _kitchen.delivered if _kitchen != null else 0, _kitchen_transit(game), _kitchen.powered if _kitchen != null else false, _hatch_supplied, _hatch_craft_claimed, _hatch_crafted])
	printerr("WARNING Resume=%s; salvage form: stock + uncredited rubble + hatch delivered/transit + third-bunk delivered/transit + Kitchen delivered/transit + Air delivered/transit = 38 once Grow fully supplied; third transit=%d" % ["yes" if _warning_resumed else "no", _third_bunk_transit(game)])
	if _third_bunk != null:
		printerr("third bunk delivered=%d work_left=%.3f complete=%s placed=%.1fs" % [_third_bunk.delivered, _third_bunk.construction_left, _third_bunk.complete, _third_bunk_elapsed])
	else:
		printerr("third bunk absent delivered=0 work_left=n/a complete=no")
	if _grow != null:
		printerr("Grow %s complete=%s powered=%s delivered=%d work_left=%.3f supplied=%s crafted=%s" % [_grow.cell, _grow.complete, _grow.powered, _grow.delivered, _grow.construction_left, _grow_supplied, _grow_crafted])
	if _charge != null:
		printerr("Charge %s complete=%s delivered=%d work_left=%.3f supplied=%s crafted=%s" % [_charge.cell, _charge.complete, _charge.delivered, _charge.construction_left, _charge_supplied, _charge_crafted])
	printerr("Air complete=%.1fs Day-7 tip=%.1fs placements=%d supplied=%s claimed=%s crafted=%s delivered=%d transit=%d work_left=%.3f powered=%s; current tip=%s" % [_air_complete_elapsed, _day7_tip_elapsed, _air_placements, _air_supplied, _air_craft_claimed, _air_crafted, _air.delivered if _air != null else 0, _air_transit(game), _air.construction_left if _air != null else -1.0, _air.powered if _air != null else false, str(game.player_orders._primary_next_step())])
	for hint in _history:
		printerr(hint)
	for bunk in _bunks:
		printerr("bunk %s complete=%s delivered=%d work_left=%.3f" % [bunk.cell, bunk.complete, bunk.delivered, bunk.construction_left])
	for resident in game.residents:
		printerr("resident=%d state=%s job=%d phase=%s carrying=%d food=%.3f rest=%.3f mood=%.3f" % [resident.resident_id, resident.state, resident.current_job_type, resident.job_phase, resident.carrying, resident.needs.food, resident.needs.rest, resident.needs.mood])


func _air_transit(game: VaultGame) -> int:
	var amount := 0
	if _air != null:
		for job: Dictionary in game.job_system.jobs:
			if int(job.type) == JobSystem.JobType.SUPPLY_BUILD and not bool(job.done) and int(job.get("building_id", -1)) == _air.building_id:
				amount += int(job.get("in_transit", 0))
	return amount


func _check_intermediate_drain(game: VaultGame, originals: Array[VaultResident]) -> bool:
	# Needs advance before jobs eat/sleep: include that intermediate drain.
	for resident in originals:
		var food := maxf(0.0, resident.needs.food - 60.0 * VaultGame.SIMULATION_TICK / DayCycle.SECONDS_PER_DAY)
		var rest: float = resident.needs.rest if resident.sleeping else maxf(0.0, resident.needs.rest - 34.0 * VaultGame.SIMULATION_TICK / DayCycle.SECONDS_PER_DAY)
		_min_food = minf(_min_food, food)
		_min_rest = minf(_min_rest, rest)
		if food < 20.0 or rest < 15.0:
			return _stop(game, "impending need drain resident=%d food=%.3f rest=%.3f" % [resident.resident_id, food, rest])
	return true


func _check_day7_success(game: VaultGame) -> void:
	for stage in _meal_proof:
		_assert_true(float(_meal_proof[stage]) >= 0.0, "fresh-wing stocked-meal proof: observed %s at constructed Kitchen" % stage)
	_assert_true(float(_meal_proof.cook_claim) <= float(_meal_proof.cook_work) and float(_meal_proof.cook_work) <= float(_meal_proof.raw_withdraw) and float(_meal_proof.raw_withdraw) <= float(_meal_proof.meal_cargo) and float(_meal_proof.meal_cargo) <= float(_meal_proof.haul_pickup) and float(_meal_proof.haul_pickup) <= float(_meal_proof.haul_deposit), "fresh-wing stocked-meal proof: ordinary Cook work -> recipe raw withdrawal -> Kitchen cargo -> ordinary Haul pickup/deposit ordered")
	_assert_true(_air != null and _air.complete and _air.delivered == 14 and _air.construction_left <= 0.0, "Air genuinely supplied and complete")
	_assert_true(_air_supplied and _air_craft_claimed and _air_crafted, "observed real Air supply 14 and ordinary Craft claim/work")
	_assert_equal(_air_placements, 1, "exactly one Air placement")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.AIR_RECYCLER), 1, "one completed Air")
	_assert_true(_air.powered and not _air.manually_disabled, "Air powered/enabled")
	_assert_true(_air_tip_elapsed >= _kitchen_complete_elapsed and _air_complete_elapsed >= _air_tip_elapsed and _day7_tip_elapsed >= _air_complete_elapsed, "Kitchen/Air tip/Air complete/Day-7 ordered")
	_assert_true(_kitchen_supplied and _kitchen_craft_claimed and _kitchen_crafted and _kitchen.complete and _kitchen.powered, "Kitchen retained supplied/crafted/powered")
	_assert_true(_grow.complete and _grow.powered and _charge.complete, "Grow and Charge retained")
	_assert_equal(game.buildings.size(), 10, "starters + two opening bunks + Charge + Grow + third bunk + Kitchen + Air")
	_assert_equal(_bunks.size(), 3, "no fourth bunk")
	_assert_equal(_warning_count, 1, "exactly one WARNING")
	_assert_true(_warning_resumed, "one WARNING Resume")
	_assert_equal(_open_count, 0, "zero OPEN events")
	_assert_false(game.breach_system.serialize().open_emitted, "zero OPEN history")
	_assert_true(game.breach_system.is_sealed() and _seal_elapsed <= SEAL_DEADLINE, "natural SEALED by 80 and retained")
	_assert_true(_hatch_supplied and _hatch_craft_claimed and _hatch_crafted, "ordinary hatch supply/claim/work")
	_assert_equal(game.power_grid.supply, 9, "Core + Charge supply 9")
	_assert_equal(game.power_grid.demand, 9, "Lumen1 + Grow3 + Kitchen2 + Air3 demand 9")
	_assert_equal(game.power_grid.served, 9, "all nine power served")
	_assert_false(game.power_grid.brownout_active, "no shedding")
	_assert_approximately(game.oxygen_system.recycler_output_rate, 0.8, 0.0001, "one powered recycler output")
	_assert_approximately(game.oxygen_system.consumption_rate, 0.32, 0.0001, "four living residents consumption")
	_assert_approximately(game.oxygen_system.net_rate, 0.48, 0.0001, "sealed net O2 +0.48/s")
	_assert_equal(_grow_residual(game) + _third_bunk.delivered + _third_bunk_transit(game) + _kitchen.delivered + _kitchen_transit(game) + _air.delivered + _air_transit(game), 38, "stock + rubble + hatch + third bunk + Kitchen + Air delivered/transit = 38 after Grow supplied")
