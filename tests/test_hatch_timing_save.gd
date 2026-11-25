extends "res://tests/test_runner.gd"

# Exercise hatch gameplay through the real JSON/file APIs, retaining the live
# source as the unsaved control. Never share a player/test save slot.
const HATCH_TICK := VaultGame.SIMULATION_TICK
const FOLLOW_TICKS := 240
# Captured by _carrier_game(false) + save_game on the pre-fix scripts. It is
# deliberately missing hatch_continuation and uses the original JSON precision.
const PRE_CHANGE_FIXTURE := "res://tests/fixtures/hatch_timing_pre_change_save.json"

var _scratch_dir := ""
var _save_serial := 0


func _run() -> void:
	_scratch_dir = "/tmp/vault-hatch-timing-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_assert_equal(DirAccess.make_dir_absolute(_scratch_dir), OK, "unique scratch save directory created")
	_run_case("WARNING 1/4, forced Haul OFF carrier: immediate round trip", _test_carrier.bind(false, false))
	_run_case("WARNING 1/4, forced Haul OFF carrier: identical future ticks", _test_carrier.bind(false, true))
	_run_case("Haul ON control: mid-edge route and future ticks", _test_carrier.bind(true, true))
	_run_case("forced supply before pickup preserves its live state text", _test_pickup)
	_run_case("forced PATCH_BREACH preserves partial work and seals identically", _test_partial_patch)
	_run_case("unacknowledged warning restores modal without replaying signals", _test_unacknowledged)
	_run_case("hatch gameplay survives custom HUD and simulation controls", _test_hud_choices)
	_run_case("seeded EARLY HATCH restores derived warning threshold", _test_seeded_warning)
	_run_case("open hatch restores low air, damage and atmosphere consequences", _test_open_oxygen)
	_run_case("seal history survives with and without a prior opening", _test_sealed_history)
	_run_case("pre-change WARNING save loads with legacy continuation defaults", _test_pre_change_fixture)
	DirAccess.remove_absolute(_scratch_dir)
	print("HATCH TIMING SAVE TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _warning_game(seed_value := 0, level := WingRecords.BASE_SUBLEVEL) -> VaultGame:
	var game := _isolated_game()
	if seed_value != 0:
		game.new_game(false, seed_value, level)
	game.begin_shift()
	for resident: VaultResident in game.residents:
		game.job_system.release_resident(resident)
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
		resident.sleeping = false
		resident.bed_id = -1
		resident.stress_break_left = 0.0
		for work_type: String in VaultResident.WORK_TYPES:
			resident.set_work_priority(work_type, VaultResident.PRIORITY_DISABLED)
	# Synchronize both real clocks; an inconsistent WARNING snapshot is rejected.
	game.day_cycle.advance(game.breach_system.warning_at)
	game.breach_system.advance(0.0, game.day_cycle.elapsed_seconds)
	game.acknowledge_breach_warning(false)
	game.user_paused = true
	return game


func _isolated_game() -> VaultGame:
	var game := _spawn_game()
	# The production day-start callback autosaves to SaveLoad.DEFAULT_PATH.
	# Suppress only that callback in both controls; keep the actual clock and
	# hatch signals live, and route all explicit saves through our unique path.
	game.day_cycle.day_started.disconnect(game._on_day_started)
	return game


func _partial_supply(game: VaultGame) -> void:
	_assert_equal(game.food_system.take_salvage(1), 1, "one salvage removed from stores")
	_assert_equal(game.breach_system.add_delivery(1), 1, "hatch receives 1/4 salvage")


func _force_response(game: VaultGame, type: int) -> void:
	var resident: VaultResident = game.residents[0]
	game.select_resident(resident.resident_id)
	_assert_true(game.issue_context_order(BreachSystem.HATCH_CELL), "existing hatch context-order API accepts force")
	_assert_true(resident.is_forced_job, "responder is forced")
	_assert_equal(resident.current_job_type, type, "responder has the requested breach job")
	var job := game.job_system._find_job(resident.current_job_id)
	_assert_equal(int(job.get("reserved_by", -1)), resident.resident_id, "live job is reserved by responder")
	_assert_false(bool(job.get("done", true)), "reserved job is unfinished")


func _carrier_game(haul_enabled: bool) -> VaultGame:
	var game := _warning_game()
	_partial_supply(game)
	var resident: VaultResident = game.residents[0]
	if haul_enabled:
		resident.set_work_priority("haul", VaultResident.DEFAULT_WORK_PRIORITY)
	# Pick up through the actual supply pipeline, then save 0.68 hex along an
	# edge. This exposes resampling of the unsaved discrete occupancy cell.
	resident.position = game.map_grid.cell_to_world(game.job_system._stockpile_cell())
	resident.clear_path()
	_force_response(game, JobSystem.JobType.SUPPLY_BREACH)
	game.step_simulation(HATCH_TICK)
	game.step_simulation(HATCH_TICK)
	_assert_equal(resident.carrying, 3, "fixture carries the remaining three patch salvage")
	_assert_equal(game.job_system.get_breach_supply_in_transit(), 3, "three salvage are in transit")
	_assert_equal(game.breach_system.patch_delivered, 1, "fixture remains at 1/4 delivered")
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.WARNING, "fixture is mid-WARNING")
	_assert_approximately(game.breach_system.get_time_to_open(), 19.8, 0.0001, "fixture has about 00:20 to opening")
	_assert_true(not resident._path.is_empty(), "fixture has a live movement route")
	game.focus_breach()
	return game


func _test_carrier(haul_enabled: bool, follow: bool) -> void:
	var source := _carrier_game(haul_enabled)
	var loaded := _round_trip(source)
	if loaded != null:
		if follow:
			_compare_future(source, loaded, FOLLOW_TICKS)
		_dispose(loaded)
	_dispose(source)


func _test_pickup() -> void:
	var source := _warning_game()
	_partial_supply(source)
	var resident: VaultResident = source.residents[0]
	resident.position = source.map_grid.cell_to_world(Vector2i(18, 18))
	resident.clear_path()
	_force_response(source, JobSystem.JobType.SUPPLY_BREACH)
	source.step_simulation(HATCH_TICK)
	_assert_equal(resident.job_phase, "pickup", "fixture is walking to pickup")
	_assert_equal(resident.carrying, 0, "fixture has not picked up cargo")
	_assert_equal(resident.state, "Collecting patch salvage", "fixture has live pickup status text")
	var loaded := _round_trip(source)
	if loaded != null:
		_compare_future(source, loaded, FOLLOW_TICKS)
		_dispose(loaded)
	_dispose(source)


func _test_partial_patch() -> void:
	var source := _warning_game()
	_supply_fully(source)
	_force_response(source, JobSystem.JobType.PATCH_BREACH)
	source.step_simulation(0.5)
	_assert_true(source.breach_system.patch_work_left < BreachSystem.PATCH_WORK_SECONDS, "fixture has partial patch work")
	_assert_true(source.breach_system.patch_work_left > 0.0, "fixture is not sealed yet")
	var loaded := _round_trip(source)
	if loaded != null:
		_compare_future(source, loaded, 100)
		_assert_true(source.breach_system.is_sealed() and loaded.breach_system.is_sealed(), "both forced patch runs seal")
		_dispose(loaded)
	_dispose(source)


func _supply_fully(game: VaultGame) -> void:
	var resident: VaultResident = game.residents[0]
	resident.position = game.map_grid.cell_to_world(game.job_system._stockpile_cell())
	resident.clear_path()
	_force_response(game, JobSystem.JobType.SUPPLY_BREACH)
	for tick: int in 100:
		game.step_simulation(HATCH_TICK)
		if game.breach_system.is_supplied():
			break
	_assert_true(game.breach_system.is_supplied(), "normal supply pipeline delivers all patch salvage")
	_assert_false(resident.is_forced_job, "one-shot supply finishes before the patch fixture")
	_assert_true((game.job_system.serialize().breach_supply as Array).is_empty(), "normal delivery leaves no stale supply job")


func _test_unacknowledged() -> void:
	var source := _warning_game()
	source.breach_system.warning_acknowledged = false
	source.player_orders.show_breach_warning(true)
	source.focus_breach()
	_assert_true(source.player_orders.breach_warning_panel.visible, "unacknowledged fixture shows modal")
	var loaded := _round_trip(source)
	if loaded != null:
		_compare_future(source, loaded, 210)
		_dispose(loaded)
	_dispose(source)


func _test_hud_choices() -> void:
	var source := _warning_game()
	source.focus_breach()
	source.player_orders.refresh()
	# Set non-default values after urgency has expanded DETAILS once.
	source.player_orders._toggle_details_rail()
	source.simulation_speed = 3
	source.user_paused = false
	source._simulation_accumulator = 0.025
	source.set_tool("dig")
	var loaded := _round_trip(source)
	if loaded != null:
		_compare_future(source, loaded, 20)
		_dispose(loaded)
	_dispose(source)


func _test_seeded_warning() -> void:
	var source := _warning_game(17, 6)
	_partial_supply(source)
	_force_response(source, JobSystem.JobType.SUPPLY_BREACH)
	source.step_simulation(HATCH_TICK)
	_assert_approximately(source.breach_system.warning_at, BreachSystem.warning_at_for_seed(17) - VaultGame.EARLY_HATCH_ADVANCE_SECONDS, 0.0001, "seed and sublevel define warning threshold")
	var loaded := _round_trip(source)
	if loaded != null:
		_compare_future(source, loaded, FOLLOW_TICKS)
		_dispose(loaded)
	_dispose(source)


func _test_open_oxygen() -> void:
	var source := _warning_game()
	source.day_cycle.advance(BreachSystem.GRACE_SECONDS)
	source.breach_system.advance(0.0, source.day_cycle.elapsed_seconds)
	source.oxygen_system.oxygen = 15.2
	source.oxygen_system.refresh_rates(source.residents, source.buildings, true)
	source.step_simulation(HATCH_TICK)
	_assert_true(source.breach_system.is_open(), "oxygen fixture has an open hatch")
	_assert_true(source.oxygen_system.is_critical(), "oxygen fixture crosses the critical threshold")
	_assert_true(source.residents[0].needs.health < 100.0, "fixture has actual suffocation damage")
	var loaded := _round_trip(source)
	if loaded != null:
		_compare_future(source, loaded, 20)
		_dispose(loaded)
	_dispose(source)


func _test_sealed_history() -> void:
	for opened: bool in [false, true]:
		var source := _warning_game()
		_supply_fully(source)
		if opened:
			source.day_cycle.advance(source.breach_system.get_open_at() - source.day_cycle.elapsed_seconds)
			source.breach_system.advance(0.0, source.day_cycle.elapsed_seconds)
		_force_response(source, JobSystem.JobType.PATCH_BREACH)
		for tick: int in 100:
			source.step_simulation(HATCH_TICK)
			if source.breach_system.is_sealed():
				break
		_assert_true(source.breach_system.is_sealed(), "normal patch pipeline seals without stale jobs")
		# Keep the existing named food warning real while comparing the HUD;
		# a loaded run intentionally starts a fresh optional-spend idle window.
		source.residents[0].needs.food = 40.0
		source.food_system.meals = 0
		var loaded := _round_trip(source)
		if loaded != null:
			_assert_equal(loaded.breach_system.has_opened(), opened, "ever-opened rating flag round trips")
			_compare_future(source, loaded, 10)
			_dispose(loaded)
		_dispose(source)


func _test_pre_change_fixture() -> void:
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(PRE_CHANGE_FIXTURE))
	_assert_true(disk is Dictionary and disk.get("game") is Dictionary, "pre-change fixture is real save JSON")
	if not disk is Dictionary or not disk.get("game") is Dictionary:
		return
	var snapshot: Dictionary = disk.game
	_assert_equal(int(disk.get("version", -1)), SaveLoad.SAVE_VERSION, "fixture uses the supported wrapper version")
	_assert_false(snapshot.residents[0].has("hatch_continuation"), "fixture predates optional hatch continuation fields")
	var loaded := _isolated_game()
	var load_events: Array[int] = [0, 0, 0]
	_watch_transitions(loaded, load_events)
	var ok := loaded.load_game(PRE_CHANGE_FIXTURE)
	_assert_true(ok, "pre-change fixture loads without new save keys")
	if not ok:
		_dispose(loaded)
		return
	_assert_equal(load_events, [0, 0, 0], "legacy load does not replay hatch transitions")
	var breach := loaded.breach_system
	var resident: VaultResident = loaded.residents[0]
	var job := loaded.job_system._find_job(resident.current_job_id)
	_assert_equal(breach.phase, BreachSystem.Phase.WARNING, "legacy fixture remains mid-WARNING")
	_assert_approximately(loaded.day_cycle.elapsed_seconds, 60.2, 0.0001, "legacy numeric clock loads without an extra precision field")
	_assert_approximately(breach.get_time_to_open(), 19.8, 0.0001, "legacy countdown keeps its remaining grace")
	_assert_equal(breach.patch_delivered, 1, "legacy fixture retains 1/4 delivered")
	_assert_approximately(breach.patch_work_left, BreachSystem.PATCH_WORK_SECONDS, 0.0001, "legacy unfinished patch defaults remain sensible")
	_assert_true(breach.warning_acknowledged and breach._warning_emitted, "legacy warning acknowledgement and emitted flag survive")
	_assert_false(breach._open_emitted or breach._sealed_emitted, "legacy fixture has not opened or sealed")
	_assert_true(resident.is_forced_job, "legacy forced hatch order reattaches")
	_assert_equal(int(resident.forced_order.get("type", -1)), JobSystem.JobType.SUPPLY_BREACH, "legacy forced descriptor retains supply type")
	_assert_equal(resident.get_work_priority("haul"), VaultResident.PRIORITY_DISABLED, "legacy responder still has Haul OFF")
	_assert_equal(resident.current_job_type, JobSystem.JobType.SUPPLY_BREACH, "legacy responder has its supply job")
	_assert_equal(job.get("target"), BreachSystem.HATCH_CELL, "legacy supply job targets the hatch")
	_assert_equal(int(job.get("reserved_by", -1)), resident.resident_id, "legacy job reserves the forced responder")
	_assert_equal(resident.job_phase, "target", "legacy phase is inferred from saved transit")
	_assert_equal(resident.carrying, 3, "legacy forced carrier retains three salvage")
	_assert_equal(resident.carrying_kind, "salvage", "legacy carried resource kind is inferred")
	_assert_equal(loaded.job_system.get_breach_supply_in_transit(), 3, "legacy cargo remains in transit")
	_assert_equal(loaded.food_system.salvage, 44, "legacy forced cargo is not refunded")
	_assert_equal(loaded.job_system.get_breach_salvage_reserve(), 0, "legacy cargo needs no additional reserve")
	_assert_equal(resident.state, "Hauling emergency patch", "legacy state text falls back to rebuilt assignment")
	_assert_true(resident._path.is_empty(), "missing legacy route defaults to re-pathing")
	_assert_equal(resident._path_index, 0, "missing legacy route cursor defaults to zero")
	_assert_equal(resident._path_destination, Vector2i(-999, -999), "missing legacy destination defaults to the unset sentinel")
	_assert_equal(resident.get_cell(loaded.map_grid), loaded.map_grid.world_to_cell(resident.position), "legacy occupancy defaults to the saved world position")
	var oxygen_before := loaded.oxygen_system.oxygen
	loaded.user_paused = false
	loaded.simulation_speed = 1
	loaded.step_simulation(HATCH_TICK)
	_assert_true(not resident._path.is_empty(), "first legacy tick rebuilds the missing route")
	_assert_equal(resident.carrying, 3, "legacy first tick retains forced cargo")
	_assert_true(loaded.oxygen_system.oxygen < oxygen_before, "legacy atmosphere continues advancing")
	for tick: int in 100:
		if breach.is_supplied():
			break
		loaded.step_simulation(HATCH_TICK)
	_assert_equal(breach.patch_delivered, BreachSystem.PATCH_COST, "legacy forced responder completes supply normally")
	_assert_equal(loaded.job_system.get_breach_supply_in_transit(), 0, "legacy delivery clears transit normally")
	_dispose(loaded)


func _round_trip(source: VaultGame) -> VaultGame:
	_save_serial += 1
	var path := "%s/save-%d.json" % [_scratch_dir, _save_serial]
	var before := _live_fields(source)
	var runtime_before := _runtime_fields(source)
	_assert_true(source.save_game(false, path), "save_game writes a unique real JSON save")
	_assert_variants_equal(before, _live_fields(source), "saving does not change the original live run")
	_assert_variants_equal(runtime_before, _runtime_fields(source), "saving does not change the original route")
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_assert_true(disk is Dictionary and disk.get("version") == SaveLoad.SAVE_VERSION, "disk has the existing save wrapper version")
	if disk is Dictionary and disk.get("game") is Dictionary:
		_assert_variants_equal(source.create_snapshot(), disk.game, "JSON contains the source snapshot, including live breach cargo")
	var loaded := _isolated_game()
	var load_events: Array[int] = [0, 0, 0]
	_watch_transitions(loaded, load_events)
	var ok := loaded.load_game(path)
	_assert_true(ok, "load_game accepts the save in a fresh game")
	_remove_test_save(path)
	if not ok:
		_dispose(loaded)
		return null
	_assert_equal(load_events, [0, 0, 0], "load never re-emits hatch transition signals")
	_compare_fields(before, _live_fields(loaded), "immediate")
	_compare_fields(runtime_before, _runtime_fields(loaded), "immediate runtime")
	return loaded


func _live_fields(game: VaultGame) -> Dictionary:
	var breach := game.breach_system
	var oxygen := game.oxygen_system
	var resident: VaultResident = game.residents[0]
	game.player_orders.refresh()
	game._sync_3d_play_view(false)
	var job := game.job_system._find_job(resident.current_job_id)
	var semantic_job := job.duplicate(true)
	semantic_job.erase("id") # Jobs are compared by type, target and reservation.
	var health: Array = []
	for member: VaultResident in game.residents:
		health.append([member.resident_id, member.alive, member.needs.health, member.needs.mood, member.short_of_air])
	return {
		"phase": breach.phase,
		"elapsed": breach._elapsed_seconds,
		"warning_at": breach.warning_at,
		"open_at": breach.get_open_at(),
		"time_to_warning": breach.get_time_to_warning(),
		"time_to_open": breach.get_time_to_open(),
		"pressure_percent": breach.get_pressure_percent(),
		"patch_delivered": breach.patch_delivered,
		"patch_work_left": breach.patch_work_left,
		"warning_acknowledged": breach.warning_acknowledged,
		"warning_emitted": breach._warning_emitted,
		"open_emitted": breach._open_emitted,
		"sealed_emitted": breach._sealed_emitted,
		"ever_opened": breach.has_opened(),
		"day": game.day_cycle.serialize(),
		"wing_lost": game.day_cycle.wing_lost,
		"seed_and_sublevel": [game.wing_seed, game.sublevel],
		"forced_order": resident.forced_order.duplicate(true),
		"is_forced_job": resident.is_forced_job,
		"job_type": resident.current_job_type,
		"job_phase": resident.job_phase,
		"job_and_reservation": semantic_job,
		"breach_jobs": game.job_system.serialize(),
		"carrying": resident.carrying,
		"carrying_kind": resident.carrying_kind,
		"in_transit": game.job_system.get_breach_supply_in_transit(),
		"salvage": game.food_system.salvage,
		"salvage_conserved": game.food_system.salvage + game.job_system.get_breach_supply_in_transit() + breach.patch_delivered,
		"position": [resident.position.x, resident.position.y],
		"occupancy_cell": resident.get_cell(game.map_grid),
		"resident_state_text": resident.state,
		"resident_work": resident.serialize().work_priorities,
		"resident_manual_control": [resident.alive, resident.drafted, resident.manual_destination],
		"resident_needs": resident.needs.serialize(),
		"resident_work_speed_inputs": [resident.rec_boost_left, resident.stress_break_left, resident.trait_id, resident.get_work_multiplier()],
		"oxygen": oxygen.oxygen,
		"oxygen_rates": [oxygen.living_resident_count, oxygen.powered_recycler_count, oxygen.consumption_rate, oxygen.recycler_output_rate, oxygen.breach_loss_rate, oxygen.net_rate],
		"oxygen_status": oxygen.get_status_text(),
		"critical_crossing": oxygen.get_seconds_to_critical_crossing(),
		"resident_air_consequences": health,
		"hatch_response_text": game.job_system.get_breach_response_status(),
		"hud_breach_text": game.player_orders.breach_label.text,
		"hud_pressure_bar": game.player_orders.breach_bar.value,
		"hud_oxygen_text": game.player_orders.oxygen_label.text,
		"hud_next_text": game.player_orders.objective_label.text,
		"warning_modal": game.player_orders.breach_warning_panel.visible,
		"cached_path_result": game.job_system.has_hatch_worker_path(),
		"fresh_path_result": _fresh_worker_path(game),
		"salvage_reserve": game.job_system.get_breach_salvage_reserve(),
		"walkable_map": game.map_grid.serialize(),
	}


func _runtime_fields(game: VaultGame) -> Dictionary:
	var resident: VaultResident = game.residents[0]
	return {
		"path": resident._path.duplicate(),
		"path_index": resident._path_index,
		"path_destination": resident._path_destination,
	}


func _fresh_worker_path(game: VaultGame) -> bool:
	var type := JobSystem.JobType.SUPPLY_BREACH if game.breach_system.needs_supply() else JobSystem.JobType.PATCH_BREACH
	var forced := game.job_system._forced_breach_responder(type)
	if forced != null:
		return not game.map_grid.find_path(forced.get_cell(game.map_grid), BreachSystem.HATCH_CELL).is_empty()
	for resident: VaultResident in game.residents:
		if resident.alive and not resident.drafted and game.job_system._resident_allows(resident, type):
			if not game.map_grid.find_path(resident.get_cell(game.map_grid), BreachSystem.HATCH_CELL).is_empty():
				return true
	return false


func _compare_fields(expected: Dictionary, actual: Dictionary, label: String) -> void:
	for field: String in expected:
		_assert_variants_equal(expected[field], actual.get(field), "%s: %s" % [label, field])


func _watch_transitions(game: VaultGame, counts: Array[int]) -> void:
	game.breach_system.warning_started.connect(func(): counts[0] += 1)
	game.breach_system.breach_opened.connect(func(): counts[1] += 1)
	game.breach_system.breach_sealed.connect(func(): counts[2] += 1)


func _compare_future(source: VaultGame, loaded: VaultGame, ticks: int) -> void:
	# Loading intentionally pauses and resets speed. Give both runs identical
	# controls before comparing subsequent hatch gameplay ticks.
	source.user_paused = false
	loaded.user_paused = false
	source.simulation_speed = 1
	loaded.simulation_speed = 1
	var source_events: Array[int] = [0, 0, 0]
	var loaded_events: Array[int] = [0, 0, 0]
	_watch_transitions(source, source_events)
	_watch_transitions(loaded, loaded_events)
	var first_differences := {}
	var checked_fields := {}
	var cache_errors := 0
	# Aggregate by field to keep failures readable while examining EVERY tick.
	for tick: int in ticks:
		source.step_simulation(HATCH_TICK)
		loaded.step_simulation(HATCH_TICK)
		var expected := _live_fields(source)
		var actual := _live_fields(loaded)
		expected.merge(_runtime_fields(source))
		actual.merge(_runtime_fields(loaded))
		expected["transition_events"] = source_events.duplicate()
		actual["transition_events"] = loaded_events.duplicate()
		for state: Dictionary in [expected, actual]:
			if state.cached_path_result != state.fresh_path_result:
				cache_errors += 1
		for field: String in expected:
			checked_fields[field] = true
			var difference := _first_variant_difference(expected[field], actual.get(field), "$")
			if not difference.is_empty() and not first_differences.has(field):
				first_differences[field] = "tick %d (+%.1fs): %s" % [tick + 1, float(tick + 1) * HATCH_TICK, difference]
				if field == "hud_breach_text" and expected.pressure_percent != actual.pressure_percent:
					print("[HATCH ROUNDING] tick %d elapsed %.17f / %.17f; pressure %.17f / %.17f" % [tick + 1, expected.elapsed, actual.elapsed, expected.pressure_percent, actual.pressure_percent])
	for field: String in checked_fields:
		_assert_equal(str(first_differences.get(field, "")), "", "all %d identical future ticks: %s" % [ticks, field])
	_assert_equal(cache_errors, 0, "both runtime path caches agree with fresh path searches on every tick")
	print("[HATCH TRACE] checked %d ticks x %d fields; %d fields diverged" % [ticks, checked_fields.size(), first_differences.size()])
