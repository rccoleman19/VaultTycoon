extends "res://tests/test_runner.gd"

const TICK_CAP := 599
const CHARGE := ["Next: YOU place a Charge Node · THEY supply/build", "Designate CHARGE. Haul + Craft auto-claim the blueprint. Adds +7 power.", "generator"]
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


func _run() -> void:
	_run_case("Untouched Next-driven Dig + two bunks to Charge", _walk)
	print("FRESH WING NEXT WALK: %s — %d assertions, %d failures" % ["FAIL" if _failure_count else "PASS", _assertion_count, _failure_count])
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
	for cell in BUNK_CELLS:
		_assert_true(game.map_grid.get_tile(cell) == MapGrid.Tile.FLOOR and game.get_building_at(cell) == null, "disclosed bunk cell starts empty floor: %s" % cell)
	for x in range(MapGrid.CHAMBER.position.x, MapGrid.CHAMBER.end.x):
		var cell := Vector2i(x, MapGrid.CHAMBER.position.y - 1)
		_targets.append(cell)
		_assert_equal(game.map_grid.get_tile(cell), MapGrid.Tile.ROCK, "target starts rock: %s" % cell)
	game.map_grid.rubble_created.connect(_observe_excavation.bind(game))
	game.food_system.inventory_changed.connect(_observe_inventory.bind(game))
	if _failure_count:
		_dispose(game)
		return
	for index in TICK_CAP:
		_tick = index + 1
		var step: Dictionary = game.player_orders._primary_next_step()
		var tuple := [step.text, step.help, step.tool]
		if tuple != _last_tuple:
			_history.append("tick=%d elapsed=%.1f: %s" % [_tick, game.day_cycle.elapsed_seconds, str(tuple)])
			_last_tuple = tuple
		if not _check_state(game, originals):
			break
		var tool_before: String = game.active_tool
		if tuple == CHARGE:
			_check_success(game)
			_assert_equal(game.active_tool, tool_before, "Charge observation preserves active tool")
			if not _failure_count:
				print("Fresh wing PASS: tick=%d elapsed=%.1fs salvage=%d uncredited rubble=%d floors=%d bunks=%d deliveries=%d min food=%.2f min rest=%.2f; Charge observed, never placed; bunk cells=%s" % [_tick, game.day_cycle.elapsed_seconds, game.food_system.salvage, _uncredited_rubble(game), _excavated.size(), _bunks.size(), _rubble_deliveries, _min_food, _min_rest, str(BUNK_CELLS)])
			else:
				_diagnostics(game)
			_dispose(game)
			return
		var acted := _act(game, tuple)
		_assert_equal(game.active_tool, tool_before, "recommended act preserves active tool")
		if not acted or _failure_count:
			break
		# Needs advance before jobs eat/sleep: test the intermediate drain too.
		var safe := true
		for resident in originals:
			var food := maxf(0.0, resident.needs.food - 60.0 * VaultGame.SIMULATION_TICK / DayCycle.SECONDS_PER_DAY)
			var rest: float = resident.needs.rest if resident.sleeping else maxf(0.0, resident.needs.rest - 34.0 * VaultGame.SIMULATION_TICK / DayCycle.SECONDS_PER_DAY)
			_min_food = minf(_min_food, food)
			_min_rest = minf(_min_rest, rest)
			if food < 20.0 or rest < 15.0:
				safe = _stop(game, "impending need drain resident=%d food=%.3f rest=%.3f" % [resident.resident_id, food, rest])
				break
		if not safe:
			break
		var work_before: Dictionary = {}
		for bunk in _bunks:
			work_before[bunk.building_id] = bunk.construction_left
		game.step_simulation(VaultGame.SIMULATION_TICK)
		for bunk in _bunks:
			if bunk.construction_left < float(work_before[bunk.building_id]) and bunk.delivered == bunk.get_cost():
				_crafted[bunk.building_id] = true
		if not _check_state(game, originals):
			break
	if not _failure_count:
		_stop(game, "599-tick cap without Charge milestone")
	_dispose(game)


func _act(game: VaultGame, tuple: Array) -> bool:
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
		# Place all missing bunks now, including during a tired mid-dig tip.
		# Never serialize place-2 behind one unfinished blueprint.
		if _bunks.size() >= 2:
			return _stop(game, "Next requests a third/repeated bunk")
		while _bunks.size() < 2:
			var cell: Vector2i = BUNK_CELLS[_bunks.size()]
			if game.get_building_at(cell) != null or not game.place_blueprint(VaultBuilding.Kind.BED, cell):
				return _stop(game, "real bunk placement rejected at %s: %s" % [cell, game.status_message])
			_bunks.append(game.get_building_at(cell))
		return true
	if tuple == FINISH:
		var incomplete := false
		for bunk in _bunks:
			incomplete = incomplete or not bunk.complete
		if not incomplete:
			return _stop(game, "finish recommendation without incomplete bunks")
		for resident in game.residents:
			if resident.alive and not resident.drafted:
				for work in ["haul", "craft"]:
					if resident.get_work_priority(work) == VaultResident.PRIORITY_DISABLED:
						if not resident.set_work_priority(work, VaultResident.DEFAULT_WORK_PRIORITY):
							return _stop(game, "recommended work enable rejected")
		return true
	return _stop(game, "unexpected full Next tuple: %s" % str(tuple))


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
	if game.day_cycle.elapsed_seconds >= 60.0 or game.breach_system.phase == BreachSystem.Phase.WARNING:
		return _stop(game, "WARNING / elapsed >=60s")
	if game.is_simulation_paused() or game.player_orders.is_help_open() or game.player_orders.is_work_priorities_open() or game.player_orders.breach_warning_panel.visible:
		return _stop(game, "unexpected pause/modal/ended")
	for resident in originals:
		_min_food = minf(_min_food, resident.needs.food)
		_min_rest = minf(_min_rest, resident.needs.rest)
		if not resident.alive or resident.drafted or resident.needs.food < 20.0 or resident.needs.rest < 15.0:
			return _stop(game, "original died/drafted or food<20/rest<15: %d" % resident.resident_id)
	for starter in _starters:
		if not game.buildings.has(starter) or not starter.complete or starter.manually_disabled or (starter.kind == VaultBuilding.Kind.LAMP and not starter.powered):
			return _stop(game, "starter Core/Lumen/Bay not retained/enabled or Lumen unpowered")
	if game.buildings.size() != _starters.size() + _bunks.size() or _bunks.size() > 2:
		return _stop(game, "unexpected/duplicate construction")
	var paid := 0
	for bunk in _bunks:
		paid += bunk.delivered
	for resident in game.residents:
		if resident.current_job_type == JobSystem.JobType.SUPPLY_BUILD:
			paid += resident.carrying
	if game.food_system.salvage + _uncredited_rubble(game) + paid != 48 + 3 * _excavated.size():
		return _stop(game, "salvage conservation violation (including bunk supply cargo)")
	return _failure_count == 0


func _check_success(game: VaultGame) -> void:
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
	if game.food_system.salvage > _last_salvage:
		var delivering := false
		for resident in game.residents:
			if resident.current_job_type == JobSystem.JobType.HAUL_RUBBLE and resident.job_phase == "deposit" and resident.carrying == 3:
				delivering = true
		_assert_true(delivering and game.food_system.salvage - _last_salvage == 3, "stock increase is real rubble delivery")
		_rubble_deliveries += 1
	_last_salvage = game.food_system.salvage


func _stop(game: VaultGame, reason: String) -> bool:
	_assert_true(false, reason)
	_diagnostics(game)
	return false


func _diagnostics(game: VaultGame) -> void:
	printerr("Fresh wing FAIL: tick=%d elapsed=%.1fs salvage=%d rubble=%d dug=%d/12 bunks=%d min food=%.3f min rest=%.3f" % [_tick, game.day_cycle.elapsed_seconds, game.food_system.salvage, _uncredited_rubble(game), _excavated.size(), game.get_completed_building_count(VaultBuilding.Kind.BED), _min_food, _min_rest])
	for hint in _history:
		printerr(hint)
	for bunk in _bunks:
		printerr("bunk %s complete=%s delivered=%d work_left=%.3f" % [bunk.cell, bunk.complete, bunk.delivered, bunk.construction_left])
	for resident in game.residents:
		printerr("resident=%d state=%s job=%d phase=%s carrying=%d food=%.3f rest=%.3f" % [resident.resident_id, resident.state, resident.current_job_type, resident.job_phase, resident.carrying, resident.needs.food, resident.needs.rest])
