extends "res://tests/test_runner.gd"
# The hatch path search behind DETAILS "NO PATH TO HATCH" and the Next tunnel tip
# is cached: repeated paused frames search at most once, and the answer always
# equals an uncached search on the same call after a dig, undraft, toggle or move.

const TICK := VaultGame.SIMULATION_TICK
const SUPPLY := JobSystem.JobType.SUPPLY_BREACH
const PATCH := JobSystem.JobType.PATCH_BREACH
const POCKET: Array[Vector2i] = [Vector2i(14, 14), Vector2i(15, 14), Vector2i(14, 15), Vector2i(15, 15)]
const TUNNEL := Vector2i(16, 14)
const SAVE_PATH := "user://hatch_path_cache.json"
const NO_PATH := "BLOCKED · NO PATH TO HATCH"


func _run() -> void:
	_run_case("paused salvage-short WARNING frames search at most once", _test_cached_frames)
	_run_case("a dug tunnel is seen on the same call", _test_fresh_dig)
	_run_case("an undraft is seen on the same call", _test_fresh_undraft)
	_run_case("a work toggle is seen on the same call", _test_fresh_toggle)
	_run_case("a move, a death and the job type are part of the answer", _test_fresh_move_death_type)
	_run_case("every tick of a tunnel walk matches the uncached search", _test_walk_matches_reference)
	print("HATCH PATH CACHE TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(0 if _failure_count == 0 else 1)


func _searches(game: VaultGame) -> int:
	var count: Variant = game.job_system.get("hatch_path_searches")
	return int(count) if count != null else -1


# The pre-cache search, verbatim.
func _reference(game: VaultGame, type: int) -> bool:
	for resident: VaultResident in game.residents:
		if resident.alive and not resident.drafted and game.job_system._resident_allows(resident, type):
			if not game.map_grid.find_path(resident.get_cell(game.map_grid), BreachSystem.HATCH_CELL).is_empty():
				return true
	return false


func _assert_fresh(game: VaultGame, expected: bool, message: String) -> void:
	var type := SUPPLY if game.breach_system.needs_supply() else PATCH
	_assert_equal(_reference(game, type), expected, message + " (reference)")
	_assert_equal(game.job_system.has_hatch_worker_path(), expected, message)
	_assert_equal(game.job_system.get_breach_response_status() == NO_PATH, not expected, message + " (DETAILS)")


func _healthy() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
		resident.drafted = false
		resident.sleeping = false
		resident.bed_id = -1
		resident.medical_bed_id = -1
	return game


func _warn(game: VaultGame) -> void:
	game.day_cycle.elapsed_seconds = BreachSystem.WARNING_AT_SECONDS - TICK
	game.step_simulation(TICK)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.WARNING, "real hatch WARNING")


func _load_pocket(pocket_residents: Array) -> VaultGame:
	var game := _healthy()
	var snapshot: Dictionary = game.create_snapshot()
	for cell: Vector2i in POCKET:
		snapshot.map.cells[cell.y * MapGrid.WIDTH + cell.x] = MapGrid.Tile.FLOOR
	for slot in pocket_residents.size():
		var spot: Vector2 = game.map_grid.cell_to_world(POCKET[slot % POCKET.size()])
		snapshot.residents[int(pocket_residents[slot])].position = [spot.x, spot.y]
	snapshot.food["salvage"] = 48
	_assert_true(bool(game.save_load.save_snapshot(snapshot, SAVE_PATH).ok), "pocket snapshot saved")
	_assert_true(game.load_game(SAVE_PATH), "pocket snapshot loads")
	_remove_test_save(SAVE_PATH)
	game.user_paused = false
	return game


func _test_cached_frames() -> void:
	var game := _healthy()
	_warn(game)
	game.acknowledge_breach_warning(false)
	game.food_system.salvage = 0
	game.user_paused = true
	var step: Dictionary = game.player_orders._primary_next_step()
	_assert_true(str(step.text).contains("fund the hatch patch"), "salvage-short WARNING tip is shown")
	game.player_orders.refresh()
	var before := _searches(game)
	_assert_true(before >= 0, "the search counter exists")
	for _frame in 30:
		game.player_orders.refresh()
		game.job_system.get_breach_response_status()
		game.job_system.has_hatch_worker_path()
	_assert_equal(_searches(game) - before, 0, "30 paused frames reuse the cached search")
	_assert_fresh(game, true, "cached answer equals the uncached search")
	game.step_simulation(TICK)
	before = _searches(game)
	game.player_orders.refresh()
	game.player_orders.refresh()
	_assert_true(_searches(game) - before <= 1 and before >= 0, "one tick then two frames: at most one search")
	_dispose(game)


func _test_fresh_dig() -> void:
	var game := _load_pocket([0, 1, 2, 3])
	_warn(game)
	_assert_fresh(game, false, "crew cut off")
	_assert_fresh(game, false, "crew cut off (cached)")
	_assert_true(game.map_grid.queue_dig(TUNNEL), "tunnel marked")
	_assert_true(game.map_grid.apply_dig_work(TUNNEL, 8.0), "tunnel dug")
	_assert_fresh(game, true, "dug tunnel connects on the same call")
	# A raw tile write without a topology bump is still seen.
	game.map_grid.cells[TUNNEL.y * MapGrid.WIDTH + TUNNEL.x] = MapGrid.Tile.ROCK
	_assert_fresh(game, false, "raw rock write cuts the crew off again")
	_dispose(game)


func _test_fresh_undraft() -> void:
	var game := _load_pocket([1, 2, 3])
	_warn(game)
	game.acknowledge_breach_warning(false)
	game.toggle_resident_draft(game.residents[0].resident_id)
	_assert_true(game.residents[0].drafted, "draft the chamber resident through R")
	_assert_fresh(game, false, "only pocket crew undrafted")
	game.toggle_resident_draft(game.residents[0].resident_id)
	_assert_false(game.residents[0].drafted, "undraft the chamber resident through R")
	_assert_fresh(game, true, "undraft is seen on the same call")
	_dispose(game)


func _test_fresh_toggle() -> void:
	var game := _load_pocket([1, 2, 3])
	_warn(game)
	game.residents[0].set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
	_assert_fresh(game, false, "chamber resident Haul OFF")
	game.residents[0].set_work_priority("haul", VaultResident.DEFAULT_WORK_PRIORITY)
	_assert_fresh(game, true, "Haul back on is seen on the same call")
	game.residents[0].set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
	_assert_fresh(game, false, "Haul OFF again is seen on the same call")
	_dispose(game)


func _test_fresh_move_death_type() -> void:
	var game := _load_pocket([1, 2, 3])
	_warn(game)
	game.residents[0].set_work_priority("craft", VaultResident.PRIORITY_DISABLED)
	_assert_equal(game.job_system._has_worker_path(SUPPLY), true, "Haul crew in the chamber")
	_assert_equal(game.job_system._has_worker_path(PATCH), false, "Craft crew all in the pocket")
	_assert_equal(game.job_system._has_worker_path(SUPPLY), true, "Haul answer back after a type switch")
	var spot: Vector2 = game.map_grid.cell_to_world(POCKET[0])
	game.residents[0].position = spot
	_assert_fresh(game, false, "teleport into the pocket is seen on the same call")
	game.residents[0].position = game.map_grid.cell_to_world(game.map_grid.get_chamber_center())
	_assert_fresh(game, true, "teleport back is seen on the same call")
	game.residents[0].kill()
	_assert_fresh(game, false, "the only connected Haul resident died")
	_dispose(game)


func _test_walk_matches_reference() -> void:
	var game := _load_pocket([0, 1, 2, 3])
	_warn(game)
	game.acknowledge_breach_warning(false)
	game.set_tool("dig")
	_assert_true(game.issue_order(TUNNEL), "tunnel order")
	game.set_tool("select")
	var mismatches: Array[String] = []
	var flips := 0
	var last := false
	for _tick in 600:
		game.step_simulation(TICK)
		var type := SUPPLY if game.breach_system.needs_supply() else PATCH
		var cached: bool = game.job_system.has_hatch_worker_path()
		if cached != _reference(game, type) and mismatches.size() < 3:
			mismatches.append("%.1fs" % game.day_cycle.elapsed_seconds)
		if cached != last:
			flips += 1
			last = cached
		if game.breach_system.is_sealed():
			break
	_assert_equal(mismatches, [] as Array[String], "cached answer matches the uncached search every tick")
	_assert_true(flips >= 1, "the walk crosses from cut off to connected")
	_dispose(game)
