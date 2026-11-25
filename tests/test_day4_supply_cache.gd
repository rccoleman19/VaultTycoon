extends "res://tests/test_runner.gd"

# New API is discovered at runtime so the same tests fail cleanly on 1e9fafe2.
const CACHE_KEY := "day4_supply_cache"
const CACHE_SAVE := "user://day4_cache_test.json"


func _run() -> void:
	_run_case("cache placement is seeded rock and locked until exactly Day 4", _test_gate)
	_run_case("a restored clock reveals the cache without a day-start signal", _test_clock_restore)
	_run_case("Dig labor and Haul arrival pay exact contents once", _test_labor_and_claim)
	_run_case("canceling the expedition is persistent and never auto-grants", _test_cancel)
	_run_case("save/load preserves partial dig, exposed cache and claimed latch", _test_save)
	_run_case("one informational notice follows excavation until claim without changing Next", _test_notice)
	_run_case("excavated cache names Haul instead of unsupported Cancel through save/load", _test_excavated_notice)
	_run_case("excavated cache advice counts only living undrafted haulers", _test_cache_hauler_advice)
	_run_case("keep-running hides an unclaimed designated cache notice", _test_keep_running_notice)
	_run_case("malformed cache saves reject atomically and old saves stay compatible", _test_validation)
	print("DAY4 SUPPLY CACHE TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _cache_wing(seed_value := 4242) -> VaultGame:
	var game := _spawn_game()
	game.new_game(false, seed_value, 5)
	var available := game.has_method("claim_supply_cache") and game.has_method("supply_cache_alert") and game.get("supply_cache_claimed") != null
	_assert_true(available, "Day-4 cache API exists")
	if not available:
		_dispose(game)
		return null
	game.begin_shift()
	game.user_paused = true
	return game


func _cell(game: VaultGame) -> Vector2i:
	return game.map_grid.get("supply_cache_cell")


func _seal_hatch(game: VaultGame) -> void:
	game.breach_system.advance(0.0, game.breach_system.warning_at)
	game.breach_system.add_delivery(BreachSystem.PATCH_COST)
	game.breach_system.apply_patch_work(BreachSystem.PATCH_WORK_SECONDS)
	game.breach_system.warning_acknowledged = true
	game.player_orders.show_breach_warning(false)
	game.job_system.reset()


func _day4(game: VaultGame) -> void:
	_seal_hatch(game)
	game.day_cycle.advance(120.0 - game.day_cycle.elapsed_seconds)


func _round_trip(game: VaultGame) -> void:
	_assert_true(game.save_load.save_snapshot(game.create_snapshot(), CACHE_SAVE).ok, "real JSON save succeeds")
	var loaded := game.save_load.load_snapshot(CACHE_SAVE)
	_assert_true(loaded.ok and game.apply_snapshot(loaded.snapshot), "real JSON load succeeds")
	_remove_test_save(CACHE_SAVE)


func _cache_job(game: VaultGame, type: int) -> Dictionary:
	for job: Dictionary in game.job_system.jobs:
		if int(job.type) == type and job.target == _cell(game) and not bool(job.done):
			return job
	return {}


func _collect(game: VaultGame) -> void:
	# Drive actual job selection/travel, without advancing hunger, air or the clock.
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
	for _tick in range(1000):
		game.job_system.advance(0.1)
		if bool(game.get("supply_cache_claimed")):
			break
	_assert_true(bool(game.get("supply_cache_claimed")), "normal worker travel and pickup collect the cache")


func _test_gate() -> void:
	for seed_value in [4242, 8, 1234, 0, 99]:
		var game := _cache_wing(seed_value)
		if game == null:
			return
		var cell := _cell(game)
		_assert_equal(game.map_grid.get_tile(cell), MapGrid.Tile.ROCK, "seed %d cache starts in actual rock" % seed_value)
		_assert_true(game.map_grid.has_walkable_neighbor(cell), "cache face is accessible from starting chamber")
		_assert_true(game.map_grid.find_path(game.residents[0].get_cell(game.map_grid), cell).is_empty(), "no floor route to cache")
		_assert_false(game.map_grid.queue_dig(cell), "early designation cannot bypass time lock")
		game.day_cycle.advance(119.9)
		_assert_false(game.map_grid.is_diggable(cell), "still sealed immediately before Day 4")
		_assert_false(bool(game.call("claim_supply_cache", game.residents[0])), "early claim rejected")
		_assert_equal(str(game.call("supply_cache_alert")), "", "no early announcement")
		_day4(game)
		_assert_equal(game.day_cycle.current_day, 4, "unlocks on the real Day-4 boundary")
		_assert_true(game.map_grid.dig_marks.has(cell), "Day 4 queues one real Dig designation")
		_assert_equal(game.map_grid.get_tile(cell), MapGrid.Tile.ROCK, "unlock does not open rock")
		_assert_false(bool(game.get("supply_cache_claimed")), "unlock grants nothing")
		game.new_game(false, seed_value, 5)
		_assert_equal(_cell(game), cell, "same seed resets to exactly the same cache")
		_assert_false(bool(game.get("supply_cache_claimed")), "new wing resets claim")
		_dispose(game)


func _test_clock_restore() -> void:
	var game := _cache_wing()
	if game == null:
		return
	# Keep the hatch coherent with the late clock so this isolates cache validation.
	_seal_hatch(game)
	# Restoring the clock does not emit day_started, including a completed Day 7.
	game.day_cycle.deserialize({"elapsed_seconds": 280.0, "current_day": 7, "completed": true})
	_assert_false(bool(game.get("supply_cache_announced")), "clock restoration alone emits no announcement")
	var restored := game.create_snapshot()
	_round_trip(game)
	_assert_equal(game.create_snapshot(), restored, "saving/loading a restored clock preserves the pending announcement without work or rewards")
	game.step_simulation(0.1)
	_assert_true(bool(game.get("supply_cache_announced")), "simulation reconciles the elapsed-time gate even when the clock is complete")
	_assert_true(game.map_grid.dig_marks.has(_cell(game)), "restored clock queues the normal expedition")
	_assert_true(game._is_snapshot_shape_valid(game.create_snapshot()), "the reconciled snapshot is valid")
	_assert_true(game.ended and game.outcome == "win", "a restored complete clock and sealed hatch finish normally")
	_round_trip(game)
	_assert_true(game.start_keep_running(), "Keep Running permits canceling after the restored win")
	game.set_tool("cancel")
	_assert_true(game.issue_order(_cell(game)), "the reconciled expedition can be canceled")
	game.step_simulation(0.1)
	_assert_false(game.map_grid.dig_marks.has(_cell(game)), "subsequent simulation does not re-queue canceled work")
	_dispose(game)


func _test_labor_and_claim() -> void:
	var game := _cache_wing()
	if game == null:
		return
	var initial := game.food_system.serialize()
	_day4(game)
	for resident: VaultResident in game.residents:
		resident.set_work_priority("dig", VaultResident.PRIORITY_DISABLED)
		resident.set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
	for _tick in range(100):
		game.job_system.advance(0.1)
	_assert_equal(game.food_system.serialize(), initial, "disabled work cannot receive a free rescue")
	_assert_equal(game.map_grid.get_tile(_cell(game)), MapGrid.Tile.ROCK, "Dig OFF leaves the cache in rock")
	_assert_false(game.map_grid.apply_dig_work(_cell(game), 7.9), "less than eight work cannot excavate")
	_assert_false(bool(game.get("supply_cache_claimed")), "partial dig grants nothing")
	_assert_true(game.map_grid.apply_dig_work(_cell(game), 0.1), "full normal excavation opens the cache")
	_assert_equal(game.food_system.serialize(), initial, "finishing excavation alone grants nothing")
	_assert_false(_cache_job(game, JobSystem.JobType.HAUL_RUBBLE).is_empty(), "excavation creates real haul task")
	for _tick in range(100):
		game.job_system.advance(0.1)
	_assert_false(bool(game.get("supply_cache_claimed")), "Haul OFF leaves exposed cache unclaimed")
	for resident: VaultResident in game.residents:
		resident.set_work_priority("haul", VaultResident.DEFAULT_WORK_PRIORITY)
	_collect(game)
	_assert_equal(game.food_system.salvage, int(initial.salvage) + 6, "pickup pays exactly six bonus salvage before ordinary rubble deposit")
	_assert_equal(game.food_system.meals, int(initial.meals) + 2, "pickup pays exactly two meals")
	_assert_false(bool(game.call("claim_supply_cache", game.residents[0])), "second claim rejected")
	for _tick in range(300):
		game.job_system.advance(0.1)
	_assert_equal(game.food_system.salvage, int(initial.salvage) + 6 + game.map_grid.get_dig_yield(_cell(game)), "ordinary rubble pays separately, bonus never repeats")
	_assert_equal(game.food_system.meals, int(initial.meals) + 2, "no double food after repeated worker updates")
	_dispose(game)


func _test_cancel() -> void:
	var game := _cache_wing()
	if game == null:
		return
	_day4(game)
	var notice := str(game.call("supply_cache_alert"))
	_assert_false(notice.is_empty(), "designated cache has a notice before cancel")
	_assert_true("CANCEL to skip" in notice, "pre-excavation notice advertises the supported Cancel action")
	game.set_tool("cancel")
	_assert_true(game.issue_order(_cell(game)), "player can abandon the expedition with CANCEL")
	_assert_equal(str(game.call("supply_cache_alert")), "", "cancel hides the cache notice immediately")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.all_alerts.count(notice), 0, "canceled notice leaves the alert list")
	var initial := game.food_system.serialize()
	_round_trip(game)
	game.day_cycle.advance(40.0)
	for _tick in range(300):
		game.job_system.advance(0.1)
	_assert_false(game.map_grid.dig_marks.has(_cell(game)), "load and next day do not re-queue canceled work")
	_assert_equal(str(game.call("supply_cache_alert")), "", "canceled notice stays hidden after load and next day")
	_assert_equal(game.food_system.serialize(), initial, "abandoned cache grants no supplies")
	game.set_tool("dig")
	_assert_true(game.issue_order(_cell(game)), "player can choose to resume the expedition")
	_assert_equal(str(game.call("supply_cache_alert")), notice, "resuming restores the same notice")
	_collect(game)
	_dispose(game)


func _test_save() -> void:
	var game := _cache_wing()
	if game == null:
		return
	_round_trip(game)
	_assert_false(game.map_grid.is_diggable(_cell(game)), "pre-Day-4 lock survives load")
	_day4(game)
	game.map_grid.apply_dig_work(_cell(game), 3.0)
	_round_trip(game)
	_assert_equal(game.map_grid.dig_progress.get(_cell(game)), 3.0, "partial excavation survives JSON")
	_assert_true(game.map_grid.apply_dig_work(_cell(game), 5.0), "remaining labor completes after load")
	_round_trip(game)
	_assert_false(bool(game.get("supply_cache_claimed")), "exposed uncollected cache survives load")
	_assert_false(_cache_job(game, JobSystem.JobType.HAUL_RUBBLE).is_empty(), "exposed haul task is restored")
	_collect(game)
	var initial := game.food_system.serialize()
	_round_trip(game)
	_assert_true(bool(game.get("supply_cache_claimed")), "claimed latch survives real JSON load")
	_assert_equal(game.food_system.serialize(), initial, "loading does not repay supplies")
	_assert_false(bool(game.call("claim_supply_cache", game.residents[0])), "loaded cache rejects duplicate claim")
	_assert_false(bool(game.map_grid.get("supply_cache_visible")), "claimed marker stays hidden after load")
	_dispose(game)


func _test_notice() -> void:
	var game := _cache_wing()
	if game == null:
		return
	_day4(game)
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
	game.food_system.meals = 24
	var notice := str(game.call("supply_cache_alert"))
	_assert_true("DAY-4 CACHE" in notice and "6 salvage + 2 meals" in notice and "Dig/Haul" in notice, "notice states contents and work cost")
	var next_before := str(game.player_orders._primary_next_step().get("text", ""))
	for _refresh in range(20):
		game.player_orders.refresh()
		_assert_equal(game.player_orders.all_alerts.count(notice), 1, "refresh shows exactly one latched cache notice")
		_assert_equal(str(game.player_orders._primary_next_step().get("text", "")), next_before, "cache notice does not churn Next at unchanged time")
	_assert_equal(game.player_orders.all_alerts, [notice], "healthy crew have only the informational cache notice")
	_assert_equal(game.player_orders.alert_label.get_theme_color("font_color"), Color("75d4b4"), "cache notice alone stays green")
	game.food_system.meals = 0
	game.player_orders.refresh()
	_assert_equal(game.player_orders.alert_label.get_theme_color("font_color"), Color("ef6860"), "a real alert alongside the notice stays red")
	game.food_system.meals = 24
	game.map_view_3d.rebuild_map()
	var marker := game.map_view_3d.marker_root.get_node_or_null("SupplyCache")
	_assert_true(marker != null and marker.visible, "visible static 3D marker identifies the pocket")
	_round_trip(game)
	game.day_cycle.advance(40.0)
	_assert_equal(game.day_cycle.current_day, 5, "unclaimed notice is checked on Day 5")
	_assert_false(bool(game.get("supply_cache_claimed")), "Day-5 cache is still unclaimed")
	_assert_true(game.map_grid.dig_marks.has(_cell(game)), "Day-5 expedition is still designated")
	_assert_equal(str(game.call("supply_cache_alert")), notice, "load and Day 5 retain the identical unclaimed notice")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.all_alerts.count(notice), 1, "Day 5 shows exactly one unclaimed notice")
	_assert_true(game.map_grid.apply_dig_work(_cell(game), 8.0), "excavation opens the cache before haul")
	var exposed_notice := str(game.call("supply_cache_alert"))
	_assert_true("dug out" in exposed_notice and "Haul on" in exposed_notice, "exposed cache explains collection with Haul enabled")
	_assert_false("CANCEL" in exposed_notice, "exposed cache never advertises unsupported Cancel")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.all_alerts.count(notice), 0, "excavation removes the pre-dig advice")
	_assert_equal(game.player_orders.all_alerts.count(exposed_notice), 1, "excavation retains exactly one updated cache notice")
	_round_trip(game)
	_assert_equal(str(game.call("supply_cache_alert")), exposed_notice, "exposed unclaimed notice survives load")
	_collect(game)
	_assert_equal(str(game.call("supply_cache_alert")), "", "claim hides the notice immediately")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.all_alerts.count(notice), 0, "claimed notice leaves the alert list")
	_assert_equal(game.player_orders.all_alerts.count(exposed_notice), 0, "claimed exposed notice leaves the alert list")
	_round_trip(game)
	game.player_orders.refresh()
	_assert_equal(str(game.call("supply_cache_alert")), "", "claimed notice stays hidden after load")
	_assert_equal(game.player_orders.all_alerts.count(notice), 0, "load does not restore a claimed notice")
	_dispose(game)


func _test_excavated_notice() -> void:
	var game := _cache_wing()
	if game == null:
		return
	_day4(game)
	for resident: VaultResident in game.residents:
		resident.set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
	_assert_true(game.map_grid.apply_dig_work(_cell(game), 8.0), "fixture excavates the cache")
	_assert_false(game.map_grid.dig_marks.has(_cell(game)), "excavated cache has no cancelable dig mark")
	_assert_true(game.map_grid.is_walkable(_cell(game)), "excavated cache is walkable")
	_assert_false(game.supply_cache_claimed, "excavated cache is still unclaimed")
	_assert_false(_cache_job(game, JobSystem.JobType.HAUL_RUBBLE).is_empty(), "excavated cache keeps its pending haul job")
	var notice := str(game.call("supply_cache_alert"))
	_assert_true("DAY-4 CACHE (%d,%d): 6 salvage + 2 meals" % [_cell(game).x, _cell(game).y] in notice, "post-dig notice retains location and contents")
	_assert_true("dug out" in notice, "post-dig notice explains completed excavation")
	_assert_false("CANCEL" in notice, "Haul-off post-dig notice does not advertise unsupported Cancel")
	_assert_true("YOU turn Haul on to collect" in notice, "Haul-off notice names the supported player action")
	game.set_tool("cancel")
	_assert_false(game.issue_order(_cell(game)), "Cancel still cannot skip an excavated cache")
	_round_trip(game)
	_assert_equal(str(game.call("supply_cache_alert")), notice, "save/reload retains the post-dig Haul-off advice")
	_assert_false(game.supply_cache_claimed, "save/reload leaves collection pending")
	_assert_false(_cache_job(game, JobSystem.JobType.HAUL_RUBBLE).is_empty(), "save/reload retains the pending haul job")
	_dispose(game)


func _test_cache_hauler_advice() -> void:
	var game := _cache_wing()
	if game == null:
		return
	_day4(game)
	_assert_true(game.map_grid.apply_dig_work(_cell(game), 8.0), "fixture excavates the cache")
	for resident: VaultResident in game.residents:
		resident.set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
	game.residents[0].set_work_priority("haul", VaultResident.DEFAULT_WORK_PRIORITY)
	game.residents[0].drafted = true
	_assert_true("YOU turn Haul on to collect" in game.supply_cache_alert(), "drafted hauler does not count as automatic crew")
	game.residents[0].drafted = false
	game.residents[0].alive = false
	_assert_true("YOU turn Haul on to collect" in game.supply_cache_alert(), "dead hauler does not count as automatic crew")
	game.residents[0].alive = true
	var notice := game.supply_cache_alert()
	_assert_true("dug out; a hauler collects it (Haul on)" in notice, "one living undrafted hauler is enough for collection advice")
	_assert_false("YOU turn Haul on" in notice or "CANCEL" in notice, "available Haul needs neither enablement advice nor unsupported Cancel")
	_dispose(game)


func _test_keep_running_notice() -> void:
	var game := _cache_wing()
	if game == null:
		return
	_day4(game)
	var notice := str(game.call("supply_cache_alert"))
	_assert_false(notice.is_empty(), "cache notice is visible before the seal win")
	game.day_cycle.advance(160.0)
	game.step_simulation(0.1)
	_assert_true(game.start_keep_running(), "sealed wing enters keep-running after the win")
	_assert_false(bool(game.get("supply_cache_claimed")), "keep-running fixture leaves the cache unclaimed")
	_assert_true(game.map_grid.dig_marks.has(_cell(game)), "keep-running fixture leaves the dig designated")
	_assert_equal(str(game.call("supply_cache_alert")), "", "keep-running hides even an unclaimed designated cache notice")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.all_alerts.count(notice), 0, "keep-running alert list omits the cache notice")
	_round_trip(game)
	_assert_equal(str(game.call("supply_cache_alert")), "", "keep-running notice stays hidden after load")
	_dispose(game)


func _test_validation() -> void:
	var game := _cache_wing()
	if game == null:
		return
	var original := game.create_snapshot()
	for field in ["version", "position", "announced", "claimed"]:
		var bad := original.duplicate(true)
		bad[CACHE_KEY][field] = "invalid"
		_assert_false(game.apply_snapshot(bad), "bad %s rejected without script errors" % field)
		_assert_equal(game.create_snapshot(), original, "rejected cache data leaves wing unchanged")
	for position in [[0, 0], [20, 15], [23], [23, 21, 0], [23.5, 21]]:
		var bad := original.duplicate(true)
		bad[CACHE_KEY].position = position
		_assert_false(game.apply_snapshot(bad), "invalid cache position rejected")
	var early := original.duplicate(true)
	early[CACHE_KEY].claimed = true
	_assert_false(game.apply_snapshot(early), "early claim save rejected")
	var announced_early := original.duplicate(true)
	announced_early[CACHE_KEY].announced = true
	_assert_false(game.apply_snapshot(announced_early), "announcement before Day 4 still rejects")
	_assert_equal(game.create_snapshot(), original, "early announcement rejection is atomic")
	for elapsed in [120.0, 280.0]:
		var pending := original.duplicate(true)
		pending.day = {"elapsed_seconds": elapsed, "current_day": mini(7, int(elapsed / DayCycle.SECONDS_PER_DAY) + 1), "completed": elapsed == 280.0}
		pending.breach = {
			"phase": BreachSystem.Phase.SEALED, "patch_delivered": BreachSystem.PATCH_COST,
			"patch_work_left": 0.0, "warning_acknowledged": true,
			"warning_emitted": true, "open_emitted": false, "sealed_emitted": true,
		}
		_assert_true(game._is_snapshot_shape_valid(pending), "late clock permits an unreconciled announcement")
		var cell := _cell(game)
		var opened := pending.duplicate(true)
		opened.map.cells[cell.y * MapGrid.WIDTH + cell.x] = MapGrid.Tile.FLOOR
		_assert_false(game.apply_snapshot(opened), "unannounced cache must still be sealed rock after clock restore")
		var marked := pending.duplicate(true)
		marked.map.dig_marks.append([cell.x, cell.y])
		_assert_false(game.apply_snapshot(marked), "unannounced cache must still have no dig designation after clock restore")
		_assert_equal(game.create_snapshot(), original, "late clock does not permit invalid sealed-cache mutations")
	var legacy := original.duplicate(true)
	legacy.erase(CACHE_KEY)
	_assert_true(game.apply_snapshot(legacy), "older snapshots without cache remain loadable")
	_assert_false(game.create_snapshot().has(CACHE_KEY), "old wing does not silently gain a new expedition")
	_dispose(game)
