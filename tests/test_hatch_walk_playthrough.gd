extends "res://tests/test_runner.gd"

const TICK_CAP := 250
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


func _run() -> void:
	_run_case("Staged Day-2 Next hatch-watch resumes real WARNING and auto-seals without OPEN", _test_staged_hatch)
	print("HATCH WALK PLAYTHROUGH: %s — %d cases, %d assertions, %d failures" % [
		"FAIL" if _failure_count else "PASS", _case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _test_staged_hatch() -> void:
	var game := _spawn_game()
	# Declared staged fixture: same #47-style dig/bunk prep as air-loop.
	# Force-carve twelve cells above the chamber, credit hauled rubble, pay
	# for two completed bunks: 48 + 36 - 16 = 68 salvage.
	# Needs at the staged clock were NOT simulated for the first 55 seconds.
	# This is NOT #47 continuation, fresh-wing, continuous Food→Air→Hatch,
	# Day-7, or mechanical-breach coverage. Defaults and original residents stay.
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
			# The sole exception to Next-only acts: honest Resume Response.
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
			if not _failure_count:
				print("Hatch SEALED PASS tick=%d elapsed=%.1fs phase=%s patch_delivered=%d patch_work_left=%.1f O2=%.6f min_O2=%.6f power=%s" % [
					_tick, game.day_cycle.elapsed_seconds, BreachSystem.Phase.keys()[game.breach_system.phase],
					game.breach_system.patch_delivered, game.breach_system.patch_work_left,
					game.oxygen_system.oxygen, _min_oxygen, _power_state(game)])
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
	if game.day_cycle.elapsed_seconds > OPEN_AT or (game.day_cycle.elapsed_seconds >= OPEN_AT and not game.breach_system.is_sealed()):
		return _fail_playthrough(game, "elapsed cap reached without SEALED")
	var expected_pause := _expected_warning(game) and _ack_count == 0 and _warning_count == 1
	if game.ended or game.tutorial_open or game.player_orders.is_help_open() or game.player_orders.is_work_priorities_open() or game.player_orders.is_briefing_open():
		return _fail_playthrough(game, "unexpected modal/ended")
	if expected_pause:
		if not game.user_paused or not game.player_orders.breach_warning_panel.visible:
			return _fail_playthrough(game, "real warning must show modal and pause before ack")
	elif game.is_simulation_paused() or game.player_orders.breach_warning_panel.visible:
		return _fail_playthrough(game, "unexpected pause/warning modal")
	for resident in originals:
		if not resident.alive or resident.drafted:
			return _fail_playthrough(game, "original resident %d died or drafted" % resident.resident_id)
		if resident.current_job_type in [JobSystem.JobType.SUPPLY_BREACH, JobSystem.JobType.PATCH_BREACH]:
			if resident.is_forced_job:
				return _fail_playthrough(game, "forced hatch job forbidden")
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
	_assert_true(false, "%s; tick=%d elapsed=%.6fs phase=%s breach=%s warnings=%d acks=%d opens=%d observed=[supply:%s transit:%s delivered:%s patch:%s work:%s] O2=%.6f min O2=%.6f paused=%s modal=%s ended=%s; last Next=%s history=%s inventory=%s power=%s jobs=%s residents=%s" % [
		reason, _tick, game.day_cycle.elapsed_seconds, BreachSystem.Phase.keys()[game.breach_system.phase],
		str(game.breach_system.serialize()), _warning_count, _ack_count, _open_count,
		_saw_supply, _saw_transit, _saw_delivered, _saw_patch, _saw_work,
		game.oxygen_system.oxygen, _min_oxygen, game.user_paused, game.player_orders.breach_warning_panel.visible,
		game.ended, str(_last_step), str(_hint_history), str(game.food_system.serialize()),
		_power_state(game), str(game.job_system.jobs), str(residents)])
	return false
