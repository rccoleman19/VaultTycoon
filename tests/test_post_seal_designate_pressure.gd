extends "res://tests/test_runner.gd"

const TICK_CAP := 250
const HOLD_TICKS := 200 # Exactly 20.0s; total driver cap is 250 + 200 = 450.
const DESIGNATE_HINT := ["Next: YOU designate needs · THEY hold Day 7", "select", "Keep designating dig/build/stockpile. Defaults keep food, power, and air running."]
const STAGED_ELAPSED := 55.0
const OPEN_AT := BreachSystem.WARNING_AT_SECONDS + BreachSystem.GRACE_SECONDS
const WATCH_HINT := ["Next: YOU watch hatch · THEY auto-patch", "select", "When the hatch warns, undrafted Haul + Craft claim supply/patch without draft."]
const KEEP_SALVAGE := "Next: YOU keep 4 salvage · THEY haul/craft hatch"
const LOAD_KINDS := [VaultBuilding.Kind.LAMP, VaultBuilding.Kind.GROW_TRAY, VaultBuilding.Kind.KITCHEN, VaultBuilding.Kind.AIR_RECYCLER]

var _hint_history: Array[String] = []
var _tick := 0
var _last_step: Dictionary = {}
var _min_oxygen := 100.0
var _warning_count := 0
var _open_count := 0
var _ack_count := 0
var _saw_supply := false
var _saw_transit := false
var _saw_delivered := false
var _saw_patch := false
var _saw_work := false
var _seal_tick := -1
var _seal_elapsed := -1.0
var _hold_ticks := 0
var _min_food := 100.0
var _min_rest := 100.0
var _hold_min_oxygen := 100.0
var _dig_cell := Vector2i(-1, -1)
var _zone_cell := Vector2i(-1, -1)
var _saw_dig := false
var _salvage_at_dig_complete := -1
var _pre_dig_salvage := -1
var _last_salvage := -1
var _saw_zone_deposit := false
var _saw_harvest := false


func _run() -> void:
	_run_case("Staged hatch seal then exact 20s Next-aware dig and stockpile pressure", _test_staged_hatch)
	print("POST-SEAL DESIGNATE PRESSURE: %s — %d cases, %d assertions, %d failures" % [
		"FAIL" if _failure_count else "PASS", _case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _test_staged_hatch() -> void:
	var game := _spawn_game()
	# Declared staged fixture: exact #48 air-ready staging at elapsed 55s.
	# Force-carve twelve cells above the chamber, credit hauled rubble, pay
	# for two completed bunks: 48 + 36 - 16 = 68 salvage.
	# Needs at the staged clock were NOT simulated for the first 55 seconds.
	# This is NOT fresh-wing, continuous Food→Air→Hatch from dig/bunk,
	# a Day-7 win, or #49 continuation through seal. Defaults/originals stay.
	# Replay real WARNING@60 → one Resume → undrafted Haul/Craft → SEALED.
	# After seal, no needs, position, inventory, or clock resets are allowed.
	for x in range(MapGrid.CHAMBER.position.x, MapGrid.CHAMBER.end.x):
		var cell := Vector2i(x, MapGrid.CHAMBER.position.y - 1)
		_assert_equal(game.map_grid.get_tile(cell), MapGrid.Tile.ROCK, "prep carves original rock")
		game.map_grid.cells[cell.y * MapGrid.WIDTH + cell.x] = MapGrid.Tile.FLOOR
		game.map_grid.topology_revision += 1
		game.map_grid.tile_changed.emit(cell)
	game.food_system.add_salvage(36)
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(20, 16))
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(21, 17))
	_assert_equal(game.food_system.take_salvage(16), 16, "completed bunks pay full costs")
	_assert_equal(game.food_system.salvage, 68, "dig/bunk prep leaves 68 salvage")
	# Paid completed Charge/Grow/Kitchen/Air; retain Core, enabled Lumen, Bay.
	# No extra generators or changes to residents' needs, positions, or work.
	for fixture in [[VaultBuilding.Kind.GENERATOR, 18], [VaultBuilding.Kind.GROW_TRAY, 12], [VaultBuilding.Kind.KITCHEN, 10], [VaultBuilding.Kind.AIR_RECYCLER, 14]]:
		var cell := _free_floor_cell(game)
		_assert_true(cell != Vector2i(-1, -1), "staged fixture has free floor")
		_add_completed_building(game, int(fixture[0]), cell)
		_assert_equal(game.food_system.take_salvage(int(fixture[1])), fixture[1], "staged fixture pays full cost")
	game.food_system.raw_food = 0
	game.food_system.meals = 4
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, game.breach_system.is_open())
	game.begin_shift()
	_assert_equal(game.day_cycle.elapsed_seconds, 0.0, "begin shift before staging clock")
	var originals: Array[VaultResident] = game.residents.duplicate()
	_assert_equal(originals.size(), 4, "four original residents")
	_assert_equal(game.food_system.salvage, 14, "48+36−16−18−12−10−14=14 staged salvage")
	_assert_equal(game.food_system.raw_food, 0, "staged raw food empty")
	_assert_equal(game.food_system.meals, 4, "staged meals four")
	_assert_equal(game.map_grid.get_floor_cells().size(), 132, "twelve connected cells carved")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.BED), 2, "two completed bunks")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.GENERATOR, true), 1, "only one non-Core Charge")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.STOCKPILE), 1, "original Bay retained")
	game.day_cycle.deserialize({"elapsed_seconds": 55.0, "current_day": 2, "completed": false})
	var dormant := {
		"phase": BreachSystem.Phase.DORMANT, "patch_delivered": 0,
		"patch_work_left": BreachSystem.PATCH_WORK_SECONDS,
		"warning_acknowledged": false, "warning_emitted": false,
		"open_emitted": false, "sealed_emitted": false,
	}
	_assert_true(game.breach_system.is_serialized_data_valid(dormant, STAGED_ELAPSED), "coherent DORMANT snapshot at 55s")
	game.breach_system.deserialize(dormant, STAGED_ELAPSED)
	_assert_equal(game.day_cycle.elapsed_seconds, STAGED_ELAPSED, "staged elapsed 55 seconds")
	_assert_equal(game.day_cycle.current_day, 2, "40s/day staged Day-2 clock")
	_assert_equal(game.breach_system.serialize(), dormant, "staging retains DORMANT, never forces WARNING")
	game.breach_system.warning_started.connect(func() -> void: _warning_count += 1)
	game.breach_system.breach_opened.connect(func() -> void: _open_count += 1)
	_last_step = game.player_orders._primary_next_step()
	_assert_equal([_last_step.text, _last_step.tool, _last_step.help], WATCH_HINT, "initial Next is exact watch-hatch tuple")
	if _failure_count or not _check_running(game, originals):
		_dispose(game)
		return

	for index in TICK_CAP:
		_tick = index + 1
		if not _check_running(game, originals):
			break
		if _expected_warning(game):
			# Seal phase exception to time-only watch: honest Resume Response.
			# Never step while this expected pause remains unacknowledged.
			_assert_true(game.user_paused, "real WARNING pauses before Resume")
			_assert_true(game.player_orders.breach_warning_panel.visible, "real WARNING modal visible before Resume")
			_assert_false(game.breach_system.warning_acknowledged, "real WARNING unacknowledged before Resume")
			_assert_equal(_warning_count, 1, "one real warning event via DORMANT advance")
			_assert_equal(_ack_count, 0, "Resume called exactly once")
			_assert_approximately(game.day_cycle.elapsed_seconds, BreachSystem.WARNING_AT_SECONDS, 0.00001, "real warning at 60 seconds")
			if _failure_count:
				break
			game.acknowledge_breach_warning(true)
			_ack_count += 1
			_assert_true(game.breach_system.warning_acknowledged, "Resume acknowledges warning")
			_assert_false(game.player_orders.breach_warning_panel.visible, "Resume hides modal")
			_assert_false(game.user_paused, "Resume unpauses response")
			if _failure_count or not _check_running(game, originals):
				break
		else:
			_last_step = game.player_orders._primary_next_step()
			var hint := "%s | %s | tool=%s" % [_last_step.text, _last_step.help, _last_step.tool]
			if _hint_history.is_empty() or not _hint_history.back().ends_with(hint):
				_hint_history.append("tick %d: %s" % [_tick, hint])
			if _last_step.text == KEEP_SALVAGE:
				_fail_playthrough(game, "keep-salvage readiness regression; never time-only")
				break
			if [_last_step.text, _last_step.tool, _last_step.help] != WATCH_HINT:
				_fail_playthrough(game, "unexpected Next; only exact hatch-watch allows time")
				break
		# Full ordinary scheduling only. Observe; never inject jobs/delivery/work.
		var work_before: float = game.breach_system.patch_work_left
		game.step_simulation(VaultGame.SIMULATION_TICK)
		if not _check_running(game, originals):
			break
		_saw_work = _saw_work or game.breach_system.patch_work_left < work_before
		_saw_delivered = _saw_delivered or game.breach_system.patch_delivered == 4
		if game.breach_system.is_sealed():
			_assert_equal(_warning_count, 1, "exactly one real WARNING")
			_assert_equal(_ack_count, 1, "exactly one honest Resume ack")
			_assert_true(_saw_supply, "observed undrafted Haul claim SUPPLY_BREACH")
			_assert_true(_saw_transit, "observed four salvage in transit toward hatch")
			_assert_true(_saw_delivered, "observed exactly four delivered")
			_assert_true(_saw_patch, "observed undrafted Craft claim PATCH_BREACH")
			_assert_true(_saw_work, "observed patch work decrease")
			_assert_equal(game.breach_system.patch_delivered, 4, "sealed patch delivered exactly four")
			_assert_equal(game.breach_system.patch_work_left, 0.0, "SEALED has zero patch work")
			_assert_equal(_open_count, 0, "no breach_opened event ever")
			_assert_equal(game.food_system.salvage, 10, "only four hatch salvage consumed")
			_seal_tick = _tick
			_seal_elapsed = game.day_cycle.elapsed_seconds
			_last_step = game.player_orders._primary_next_step()
			_assert_equal([_last_step.text, _last_step.tool, _last_step.help], DESIGNATE_HINT, "SEALED has exact designate tuple")
			if not _failure_count:
				_hold_designate_pressure(game, originals)
			_dispose(game)
			return
	if not _failure_count:
		_fail_playthrough(game, "250-tick / 55→80s cap without SEALED")
	_dispose(game)


func _expected_warning(game: VaultGame) -> bool:
	return game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged


func _check_running(game: VaultGame, originals: Array[VaultResident]) -> bool:
	# Readiness must hold even on the modal/ack and completion ticks.
	if game.player_orders._primary_next_step().text == KEEP_SALVAGE:
		return _fail_playthrough(game, "keep-salvage readiness regression after setup")
	_min_oxygen = minf(_min_oxygen, game.oxygen_system.oxygen)
	if game.oxygen_system.oxygen <= 15.0:
		return _fail_playthrough(game, "O2 must remain strictly above 15")
	if _open_count > 0 or game.breach_system.phase == BreachSystem.Phase.OPEN or game.breach_system.serialize().open_emitted:
		return _fail_playthrough(game, "OPEN phase/event forbidden; no fallback")
	if _seal_tick < 0 and (game.day_cycle.elapsed_seconds > OPEN_AT or (game.day_cycle.elapsed_seconds >= OPEN_AT and not game.breach_system.is_sealed())):
		return _fail_playthrough(game, "elapsed cap reached without SEALED")
	var expected_pause := _expected_warning(game) and _ack_count == 0 and _warning_count == 1
	if game.ended or game.tutorial_open or game.player_orders.is_help_open() or game.player_orders.is_work_priorities_open() or game.player_orders.is_briefing_open():
		return _fail_playthrough(game, "unexpected modal/ended")
	if expected_pause:
		if not game.user_paused or not game.player_orders.breach_warning_panel.visible:
			return _fail_playthrough(game, "real warning must show modal and pause before ack")
	elif game.is_simulation_paused() or game.player_orders.breach_warning_panel.visible:
		return _fail_playthrough(game, "unexpected pause/warning modal")
	if game.day_cycle.completed:
		return _fail_playthrough(game, "Day-7 completion forbidden in bounded slice")
	if _seal_tick >= 0:
		_last_step = game.player_orders._primary_next_step()
		if [_last_step.text, _last_step.tool, _last_step.help] != DESIGNATE_HINT:
			return _fail_playthrough(game, "hold requires exact designate tuple; crisis/unknown Next forbidden")
		if not game.breach_system.is_sealed() or game.active_tool != "select":
			return _fail_playthrough(game, "hold must remain SEALED with select restored")
		_hold_min_oxygen = minf(_hold_min_oxygen, game.oxygen_system.oxygen)
	for resident in originals:
		if resident.is_forced_job:
			return _fail_playthrough(game, "forced hatch/manual jobs forbidden")
		if _seal_tick >= 0:
			_min_food = minf(_min_food, resident.needs.food)
			_min_rest = minf(_min_rest, resident.needs.rest)
			if resident.needs.food < 20.0 or resident.needs.rest < 15.0:
				return _fail_playthrough(game, "hold needs below food20/rest15")
			if resident.current_job_type == JobSystem.JobType.DIG:
				if resident.get_work_priority("dig") <= 0:
					return _fail_playthrough(game, "Dig claimant lacks enabled Dig")
				_saw_dig = true
		if not resident.alive or resident.drafted:
			return _fail_playthrough(game, "original resident %d died or drafted" % resident.resident_id)
		if resident.current_job_type in [JobSystem.JobType.SUPPLY_BREACH, JobSystem.JobType.PATCH_BREACH]:
			if resident.current_job_type == JobSystem.JobType.SUPPLY_BREACH:
				if resident.get_work_priority("haul") <= 0:
					return _fail_playthrough(game, "supply claimant must have Haul enabled")
				_saw_supply = true
				if resident.job_phase == "target" and resident.carrying == 4 and game.job_system.get_breach_supply_in_transit() == 4:
					_saw_transit = true
			else:
				if resident.get_work_priority("craft") <= 0 or game.breach_system.patch_delivered != 4:
					return _fail_playthrough(game, "patch claimant needs enabled Craft and exactly four supplied")
				_saw_patch = true
	for kind in LOAD_KINDS:
		if game.get_completed_building_count(kind) != 1:
			return _fail_playthrough(game, "expected one complete %s" % VaultBuilding.KIND_NAMES[kind])
		for building in game.buildings:
			if building.kind == kind and (building.manually_disabled or not building.powered or game.power_grid.is_building_shed(building.building_id)):
				return _fail_playthrough(game, "%s must remain enabled, powered, unshed" % building.get_display_name())
	if game.power_grid.supply != 9 or game.power_grid.demand != 9 or game.power_grid.served != 9 or game.power_grid.shed_count != 0:
		return _fail_playthrough(game, "all nine power must be served without shedding")
	return true


func _free_floor_cell(game: VaultGame) -> Vector2i:
	var bay := game.job_system._stockpile_cell()
	var cells := game.map_grid.get_floor_cells()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(bay) < b.distance_squared_to(bay))
	for cell in cells:
		if cell != BreachSystem.HATCH_CELL and game.get_building_at(cell) == null:
			return cell
	return Vector2i(-1, -1)


func _power_state(game: VaultGame) -> String:
	var fixtures: Array[String] = []
	for building in game.buildings:
		fixtures.append("%s@%s complete=%s enabled=%s powered=%s shed=%s core=%s" % [
			building.get_display_name(), building.cell, building.complete, not building.manually_disabled,
			building.powered, game.power_grid.is_building_shed(building.building_id), building.is_emergency_core])
	return "supply=%d demand=%d served=%d shed=%d; %s" % [game.power_grid.supply, game.power_grid.demand, game.power_grid.served, game.power_grid.shed_count, str(fixtures)]


func _fail_playthrough(game: VaultGame, reason: String) -> bool:
	var residents: Array = []
	for resident in game.residents:
		residents.append(resident.serialize())
	_assert_true(false, "%s; hold=%s; tick=%d elapsed=%.6fs phase=%s breach=%s warnings=%d acks=%d opens=%d observed=[supply:%s transit:%s delivered:%s patch:%s work:%s] O2=%.6f min O2=%.6f paused=%s modal=%s ended=%s; last Next=%s history=%s inventory=%s power=%s jobs=%s residents=%s" % [
		reason, str({"seal_tick": _seal_tick, "seal_elapsed": _seal_elapsed, "ticks": _hold_ticks, "dig": _dig_cell, "zone": _zone_cell, "dig_claim": _saw_dig, "salvage_at_dig_complete": _salvage_at_dig_complete, "zone_deposit": _saw_zone_deposit, "harvest": _saw_harvest, "min_food": _min_food, "min_rest": _min_rest, "min_O2": _hold_min_oxygen}), _tick, game.day_cycle.elapsed_seconds, BreachSystem.Phase.keys()[game.breach_system.phase],
		str(game.breach_system.serialize()), _warning_count, _ack_count, _open_count,
		_saw_supply, _saw_transit, _saw_delivered, _saw_patch, _saw_work,
		game.oxygen_system.oxygen, _min_oxygen, game.user_paused, game.player_orders.breach_warning_panel.visible,
		game.ended, str(_last_step), str(_hint_history), str(game.food_system.serialize()),
		_power_state(game), str(game.job_system.jobs), str(residents)])
	return false


func _hold_designate_pressure(game: VaultGame, originals: Array[VaultResident]) -> void:
	# Bounded post-seal pressure only, not the ~206s Day-7 hold. The select Next
	# supplies no coordinates and never issues digs. These are help-prompted
	# player choices via ordinary APIs, once at hold start; then full simulation.
	_assert_equal(game.map_grid.dig_marks.size(), 0, "no staged pending digs")
	_assert_equal(game.map_grid.stockpile_cells.size(), 0, "no staged painted zones")
	# Choose reachable empty floor beside connected rock, nearest the live crew.
	# This keeps the single real dig/haul feasible without moving any resident.
	var best_distance := INF
	for floor_cell in game.map_grid.get_floor_cells():
		if floor_cell == BreachSystem.HATCH_CELL or game.get_building_at(floor_cell) != null or not game.map_grid.can_paint_stockpile(floor_cell):
			continue
		var occupied := false
		for resident in originals:
			occupied = occupied or resident.get_cell(game.map_grid) == floor_cell
		if occupied:
			continue
		for rock_cell in game.map_grid.get_neighbors(floor_cell):
			if game.map_grid.get_tile(rock_cell) != MapGrid.Tile.ROCK or not game.map_grid.can_queue_dig(rock_cell):
				continue
			for resident in originals:
				var path := game.map_grid.find_path(resident.get_cell(game.map_grid), floor_cell)
				if resident.get_work_priority("dig") > 0 and not path.is_empty() and path.size() < best_distance:
					best_distance = path.size()
					_dig_cell = rock_cell
					_zone_cell = floor_cell
	_assert_true(_dig_cell != Vector2i(-1, -1) and _zone_cell != Vector2i(-1, -1), "reachable rock/floor pair for real dig and haul")
	if _failure_count:
		return
	_pre_dig_salvage = game.food_system.salvage
	_last_salvage = _pre_dig_salvage
	game.food_system.inventory_changed.connect(_observe_hold_inventory.bind(game))
	game.food_system.raw_food_produced.connect(_observe_hold_harvest.bind(game))
	game.set_tool("dig")
	var dig_issued := game.issue_order(_dig_cell)
	game.set_tool("select")
	_assert_true(dig_issued and game.map_grid.dig_marks.has(_dig_cell), "ordinary dig order accepted once after seal")
	game.set_tool("zone")
	var zone_issued := game.issue_order(_zone_cell)
	game.set_tool("select")
	_assert_true(zone_issued and game.map_grid.stockpile_cells.has(_zone_cell), "ordinary zone order accepted once after seal")
	if _failure_count:
		return
	for index in HOLD_TICKS:
		_tick = _seal_tick + index + 1
		if not _check_running(game, originals):
			return
		# Needs drain before scheduling/eating. Observe that intermediate low so
		# same-tick eating/sleep decisions cannot conceal food<20 or rest<15.
		for resident in originals:
			var drained_food := maxf(0.0, resident.needs.food - 60.0 * VaultGame.SIMULATION_TICK / DayCycle.SECONDS_PER_DAY)
			var drained_rest: float = resident.needs.rest if resident.sleeping else maxf(0.0, resident.needs.rest - 34.0 * VaultGame.SIMULATION_TICK / DayCycle.SECONDS_PER_DAY)
			_min_food = minf(_min_food, drained_food)
			_min_rest = minf(_min_rest, drained_rest)
			if drained_food < 20.0 or drained_rest < 15.0:
				_fail_playthrough(game, "impending hold needs drain below food20/rest15")
				return
		game.step_simulation(VaultGame.SIMULATION_TICK)
		_hold_ticks += 1
		if _salvage_at_dig_complete < 0 and game.map_grid.get_tile(_dig_cell) == MapGrid.Tile.FLOOR:
			_salvage_at_dig_complete = game.food_system.salvage
		if not _check_running(game, originals):
			return
		# Never stop early when either latch completes: ride all 200 ticks.
	_assert_equal(_hold_ticks, HOLD_TICKS, "exactly 200 full simulation ticks after seal")
	_assert_true(_tick <= TICK_CAP + HOLD_TICKS, "total suite cap 450 ticks")
	_assert_true(_saw_dig, "observed undrafted enabled Dig claimant")
	_assert_equal(game.map_grid.get_tile(_dig_cell), MapGrid.Tile.FLOOR, "real dig completed rock→floor")
	_assert_false(game.map_grid.dig_marks.has(_dig_cell), "completed dig mark gone")
	_assert_true(_salvage_at_dig_complete >= 0, "dig completion observed in hold")
	_assert_true(_saw_zone_deposit, "rubble +3 credited by undrafted hauler at painted zone")
	_assert_equal(game.food_system.salvage - _pre_dig_salvage, 3, "only real rubble haul adds three salvage")
	# Deposit may share the completion tick; the pre-dig baseline accounts for
	# its +3 even then. No inventory writes or construction costs during hold.
	_assert_true(_saw_harvest, "natural powered Grow output observed strictly after seal")
	_assert_equal(game.get_alive_count(), 4, "four originals alive at end")
	_assert_false(game.day_cycle.completed, "bounded hold is not Day-7 completion")
	_assert_false(game.ended, "game remains running")
	_assert_approximately(game.day_cycle.elapsed_seconds, _seal_elapsed + 20.0, 0.00001, "one clock advances exactly seal+20s")
	_assert_equal(game.day_cycle.current_day, 3, "bounded hold reaches Day 3")
	_last_step = game.player_orders._primary_next_step()
	_assert_equal([_last_step.text, _last_step.tool, _last_step.help], DESIGNATE_HINT, "end retains exact designate tuple")
	_assert_equal(game.active_tool, "select", "select restored throughout simulation and at end")
	if not _failure_count:
		print("Post-seal designate pressure PASS seal_tick=%d seal_elapsed=%.1fs hold_ticks=%d elapsed=%.1fs Day=%d salvage_delta=%d salvage_at_dig_complete=%d min_food=%.2f min_rest=%.2f min_O2=%.6f dig=%s zone=%s" % [
			_seal_tick, _seal_elapsed, _hold_ticks, game.day_cycle.elapsed_seconds, game.day_cycle.current_day,
			game.food_system.salvage - _pre_dig_salvage, _salvage_at_dig_complete,
			_min_food, _min_rest, _hold_min_oxygen, _dig_cell, _zone_cell])


func _observe_hold_harvest(source: Vector2i, amount: int, game: VaultGame) -> void:
	var tray := game.get_building_at(source)
	if tray != null and tray.kind == VaultBuilding.Kind.GROW_TRAY and tray.complete and tray.powered and not tray.manually_disabled and amount > 0:
		_saw_harvest = _saw_harvest or game.job_system.get_pending_raw_food_at(source) > 0


func _observe_hold_inventory(game: VaultGame) -> void:
	var salvage: int = game.food_system.salvage
	# add_salvage emits before carrying/current job are cleared, allowing proof
	# that the +3 credit came from this dig's rubble at the painted destination.
	if salvage - _last_salvage == 3 and game.map_grid.stockpile_cells.has(_zone_cell):
		for resident in game.residents:
			var job: Dictionary = game.job_system._find_job(resident.current_job_id)
			if resident.current_job_type == JobSystem.JobType.HAUL_RUBBLE and resident.job_phase == "deposit" and resident.carrying == 3 and resident.get_cell(game.map_grid) == _zone_cell and job.get("target", Vector2i(-1, -1)) == _dig_cell:
				_assert_true(resident.alive and not resident.drafted and not resident.is_forced_job and resident.get_work_priority("haul") > 0, "natural enabled Haul deposits dig rubble")
				_saw_zone_deposit = true
	_last_salvage = salvage
