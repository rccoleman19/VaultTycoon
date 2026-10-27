extends "res://tests/test_runner.gd"

# All fixtures use the real level-05 wing, real completed fixtures and hatch
# sealing, but no elapsed simulation. New step fields are read with get(), so
# the exact same file can run against b70444f2 as a regression control.
const AIR_CELL := Vector2i(25, 12)
const RECLAIM_HELP := "Reclamation: +18 salvage now, +18 every 30 s, 6 times"


func _run() -> void:
	_run_case("T1 reclamation leads salvage-short actions and preserves danger ranking", _test_reclamation_lead)
	_run_case("T2 funding never waits on digging that is not happening", _test_no_passive_funding)
	_run_case("T3 idle crew are prompted to spend affordable survival salvage", _test_spend_nudge)
	print("LATE SHIFT GOALS TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _sealed_wing(complete_air := true, complete_bunks := true) -> VaultGame:
	var game := _spawn_game()
	game.new_game(false, 4242, 5)
	game.begin_shift()
	game.user_paused = true
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
		resident.drafted = false
		resident.sleeping = false
		resident.bed_id = -1
		resident.medical_bed_id = -1
		resident.state = "Idle"
	game.food_system.meals = 100
	game.food_system.raw_food = 0
	# Clear the real twelve-rock progression gate, then remove its deliberately
	# unhauled fixture rubble so it cannot silently pay for the test blueprint.
	for x in range(17, 29):
		var cell := Vector2i(x, 10)
		_assert_true(game.map_grid.queue_dig(cell) and game.map_grid.apply_dig_work(cell, 8.0), "level-05 fixture carves the required floor")
	game.job_system.jobs = game.job_system.jobs.filter(func(job: Dictionary) -> bool:
		return int(job.type) not in [JobSystem.JobType.DIG, JobSystem.JobType.HAUL_RUBBLE])
	if complete_bunks:
		_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(20, 12))
		_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(21, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(22, 12))
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12))
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(24, 12))
	# Extra ordinary generation makes the optional Rec sink affordable in power.
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(26, 12))
	if complete_air:
		_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, AIR_CELL)
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.breach_system.advance(0.0, game.breach_system.warning_at)
	var delivered := game.breach_system.add_delivery(BreachSystem.PATCH_COST)
	var sealed := game.breach_system.apply_patch_work(BreachSystem.PATCH_WORK_SECONDS)
	game.player_orders.show_breach_warning(false)
	_assert_true(delivered == BreachSystem.PATCH_COST and sealed and game.breach_system.is_sealed(), "fixture seals the real level-05 hatch")
	_assert_true(game.map_grid.dig_marks.is_empty() and game.job_system.get_uncredited_rubble() == 0, "fixture starts without marks or uncredited/in-transit rubble")
	return game


func _air_funding_wing() -> VaultGame:
	var game := _sealed_wing(false)
	_assert_true(game.place_blueprint(VaultBuilding.Kind.AIR_RECYCLER, AIR_CELL), "real unfunded Air Recycler blueprint is placed")
	game.food_system.salvage = 0
	_assert_true(game.can_start_reclamation(), "sealed unfinished Air wing can begin reclamation")
	return game


func _next_step(game: VaultGame) -> Dictionary:
	return game.player_orders._primary_next_step()


func _assert_reclaim(step: Dictionary, expected: String, message: String) -> void:
	_assert_equal(str(step.get("text", "")), expected, message)
	_assert_equal(str(step.get("tool", "")), "select", message + " keeps Select")
	_assert_equal(str(step.get("action", "")), "reclaim", message + " exposes the reclaim action")
	_assert_true(RECLAIM_HELP in str(step.get("help", "")), message + " explains the immediate and finite deliveries")


func _test_reclamation_lead() -> void:
	var game := _air_funding_wing()
	var step := _next_step(game)
	_assert_reclaim(step, "Next: YOU begin reclamation · +18 · THEY fund the Air Recycler", "T1 non-danger funding names the usable free salvage")
	_assert_equal(game.food_system.salvage, 0, "Next advice does not start reclamation or change inventory")
	_assert_false(game.reclaim_active, "Next advice leaves reclamation a player action")

	var ari: VaultResident = game.residents[0]
	var bo: VaultResident = game.residents[1]
	game.oxygen_system.oxygen = 10.0
	ari.needs.health = 40.0
	bo.needs.health = 20.0
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	# Disabling the new opportunity provides the original urgency choice in the
	# same live state. Enabling it must change only the funding action slot.
	game.reclaim_active = true
	var without_reclaim := _next_step(game)
	game.reclaim_active = false
	step = _next_step(game)
	_assert_reclaim(step, "Next: Bo suffocating · YOU begin reclamation · +18 · THEY fund the Air Recycler", "T1 danger funding preserves the exact resident prefix")
	_assert_true(bool(step.get("urgent", false)) and int(step.get("resident_id", -1)) == bo.resident_id
		and str(step.get("cause", "")) == "air", "T1 keeps the selected danger metadata")
	_assert_equal(step.get("resident_id", -1), without_reclaim.get("resident_id", -2), "T1 reclamation does not rerank competing residents")
	_assert_equal(step.get("death_seconds", -1.0), without_reclaim.get("death_seconds", -2.0), "T1 reclamation does not change the selected death runway")
	_assert_true(game.player_orders._alert_stated_by_next("CRITICAL: Bo", step), "T1 the named CRITICAL alert remains deduped")
	_assert_false(game.player_orders._alert_stated_by_next("CRITICAL: Ari", step), "T1 the other resident's CRITICAL alert remains visible")
	_dispose(game)


	game = _air_funding_wing()
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(27, 12)), "T1 suffix fixture also retains a real unfunded Charge blueprint")
	# Reproduce the queued-build decorator on existing real funding steps. The
	# new helper is optional on the baseline control and is called dynamically.
	# A bunk suffix must never become the fixture the selected Air/Charge funds.
	if game.player_orders.has_method("_next_named_build_kind") and game.player_orders.has_method("_salvage_next_step"):
		for kind: int in [VaultBuilding.Kind.AIR_RECYCLER, VaultBuilding.Kind.GENERATOR]:
			var decorated: Dictionary = game.player_orders._fund_blueprint_step(kind).duplicate(true)
			decorated["in_progress"] = ["bunks"]
			decorated["text"] = str(decorated.get("text", "")) + " · bunks in progress"
			_assert_equal(int(game.player_orders.call("_next_named_build_kind", decorated)), kind, "T1 queued bunk suffix retains the selected %s funding target" % VaultBuilding.KIND_NAMES[kind])
			var transformed: Dictionary = game.player_orders.call("_salvage_next_step", decorated)
			_assert_reclaim(transformed, "Next: YOU begin reclamation · +18 · THEY fund the %s · bunks in progress" % VaultBuilding.KIND_NAMES[kind], "T1 the funding target and queued suffix survive reclamation decoration")
	_dispose(game)

	game = _sealed_wing(true, false)
	game.residents[0].needs.rest = 10.0
	game.food_system.salvage = 2
	step = _next_step(game)
	_assert_reclaim(step, "Next: YOU begin reclamation · +18 · THEY fund the Bunk", "T1 salvage-short place-bunks advice leads with reclamation")
	_dispose(game)

	game = _air_funding_wing()
	_assert_true(game.start_reclamation(), "T1 active-negative fixture starts through the player API")
	game.food_system.salvage = 0
	step = _next_step(game)
	_assert_true("begin reclamation" not in str(step.get("text", "")) and str(step.get("action", "")) != "reclaim", "T1 active reclamation is not offered again")
	game.reclaim_active = false
	game.breach_system.reset()
	step = _next_step(game)
	_assert_false(game.can_start_reclamation(), "T1 unsealed-negative fixture cannot reclaim")
	_assert_true("begin reclamation" not in str(step.get("text", "")) and str(step.get("action", "")) != "reclaim", "T1 an unsealed wing never receives the lead")
	_dispose(game)

	game = _sealed_wing(true, false)
	ari = game.residents[0]
	ari.needs.rest = 0.0
	ari.needs.health = 20.0
	ari.drafted = true
	game.food_system.salvage = 0
	step = _next_step(game)
	_assert_equal(str(step.get("text", "")), "Next: Ari exhausted · YOU undraft Ari [R] · THEY rest", "T1 non-salvage danger undraft action is unchanged")
	_assert_true(str(step.get("action", "")) not in ["reclaim", "spend"], "T1 idle crisis never replaces an urgent undraft")
	_dispose(game)


	game = _sealed_wing()
	game.residents[0].needs.rest = 10.0
	game.food_system.salvage = 8
	game.reclaim_active = true
	var passive := _next_step(game)
	_assert_true(not bool(passive.get("urgent", false)) and "THEY fund the" not in str(passive.get("text", ""))
		and game.player_orders.salvage_nudge_kind() == VaultBuilding.Kind.RECREATION_CONSOLE, "T1 passive-crisis fixture has no selected funding shortage and has an affordable sink")
	game.reclaim_active = false
	game.player_orders.alert_label.text = ""
	step = _next_step(game)
	_assert_reclaim(step, "Next: YOU begin reclamation · +18 · THEY fund the Bunk", "T1 idle crew plus real rest crisis reclaim even though existing bunks cover placement")
	for resident: VaultResident in game.residents:
		resident.state = "Preparing meals"
	step = _next_step(game)
	_assert_true("begin reclamation" not in str(step.get("text", "")), "T1 a covered passive crisis needs genuinely idle crew to lead with reclamation")
	game.residents[0].state = "Idle"
	game.residents[0].needs.rest = 100.0
	game.player_orders.alert_label.text = "CRITICAL: Ari"
	step = _next_step(game)
	_assert_true("begin reclamation" not in str(step.get("text", "")), "T1 alert text cannot manufacture a simulation crisis")
	_dispose(game)

	game = _sealed_wing()
	var recycler := game.get_building_at(AIR_CELL)
	recycler.manually_disabled = true
	game.oxygen_system.oxygen = 10.0
	game.residents[0].needs.health = 20.0
	game.food_system.salvage = 0
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	step = _next_step(game)
	_assert_equal(str(step.get("text", "")), "Next: Ari suffocating · YOU enable an Air Recycler · THEY recycle air", "T1 non-salvage danger enable action is unchanged")
	_assert_true(str(step.get("action", "")) not in ["reclaim", "spend"], "T1 free salvage cannot replace an urgent enable switch")
	_dispose(game)

	game = _air_funding_wing()
	game.ended = true
	step = _next_step(game)
	_assert_false(game.can_start_reclamation(), "T1 ended wings cannot begin reclamation")
	_assert_true("begin reclamation" not in str(step.get("text", "")), "T1 ended wings never receive reclamation advice")
	_dispose(game)


func _test_no_passive_funding() -> void:
	var game := _air_funding_wing()
	var step := _next_step(game)
	_assert_equal(str(step.get("text", "")), "Next: YOU begin reclamation · +18 · THEY fund the Air Recycler", "T2 available reclamation leads instead of passive funding")
	_assert_true("leave Dig + Haul on" not in str(step.get("text", "")), "T2 no marks or rubble never suggest leaving nonexistent work on")
	_assert_true(game.start_reclamation(), "T2 active fixture uses the player reclamation API")
	game.food_system.salvage = 0
	step = _next_step(game)
	_assert_equal(str(step.get("text", "")), "Next: YOU mark 5 rock [E] · THEY fund the Air Recycler", "T2 unavailable reclamation actively designates the uncovered shortfall")
	_assert_equal(str(step.get("tool", "")), "dig", "T2 uncovered funding highlights Dig")
	game.job_system.queue_rubble(Vector2i(18, 12), 3)
	step = _next_step(game)
	_assert_equal(str(step.get("text", "")), "Next: YOU mark 4 rock [E] · THEY fund the Air Recycler", "T2 partial rubble still designates the remaining shortfall")
	game.job_system.jobs = game.job_system.jobs.filter(func(job: Dictionary) -> bool:
		return int(job.type) != JobSystem.JobType.HAUL_RUBBLE)
	for x in range(17, 22):
		_assert_true(game.map_grid.queue_dig(Vector2i(x, 9)), "T2 genuine connected open dig marks cover the blueprint")
	step = _next_step(game)
	_assert_equal(str(step.get("text", "")), "Next: YOU leave Dig + Haul on · THEY fund the Air Recycler", "T2 enough open dig marks retain the correct passive advice")
	_assert_equal(str(step.get("tool", "")), "select", "T2 covered funding leaves Select available")
	for cell: Vector2i in game.map_grid.dig_marks.keys():
		game.map_grid.cancel_dig(cell)
	game.job_system.queue_rubble(Vector2i(18, 12), 14)
	step = _next_step(game)
	_assert_equal(str(step.get("text", "")), "Next: YOU leave Dig + Haul on · THEY fund the Air Recycler", "T2 enough uncredited rubble also keeps existing work running")
	_dispose(game)


func _nudge_wing(salvage: int, fittable_grow := false) -> VaultGame:
	var game := _sealed_wing()
	if not fittable_grow:
		for building: VaultBuilding in game.buildings:
			if building.kind == VaultBuilding.Kind.GROW_TRAY:
				building.upgrade_tier = VaultBuilding.UPGRADE_TIER_MAX
	game.food_system.salvage = salvage
	return game


func _test_spend_nudge() -> void:
	var game := _nudge_wing(8)
	_assert_equal(game.player_orders.salvage_nudge_kind(), VaultBuilding.Kind.RECREATION_CONSOLE, "T3 the existing affordable sink selects Rec")
	_assert_true(game.player_orders._upgrade_offer_target() == null, "T3 build fixture has no competing Mk II offer")
	var step := _next_step(game)
	_assert_equal(str(step.get("text", "")), "Next: YOU spend 8: build Rec Console · THEY craft", "T3 idle default turns stored salvage into useful building advice")
	_assert_equal(str(step.get("action", "")), "spend", "T3 affordable construction exposes the spend action")
	_assert_equal(game.food_system.salvage, 8, "T3 spend advice leaves purchase to the player")
	# Any real idle resident is enough; a string containing Idle is not the
	# simulation's exact Idle state and cannot qualify by substring matching.
	for resident: VaultResident in game.residents:
		resident.state = "Excavating rock"
	step = _next_step(game)
	_assert_true("YOU spend" not in str(step.get("text", "")), "T3 busy crew never receive an idle spend nudge")
	for resident: VaultResident in game.residents:
		resident.state = "Idle on defaults"
	step = _next_step(game)
	_assert_true("YOU spend" not in str(step.get("text", "")), "T3 only the real Idle state qualifies")
	game.residents[0].state = "Idle"
	step = _next_step(game)
	_assert_equal(str(step.get("text", "")), "Next: YOU spend 8: build Rec Console · THEY craft", "T3 one live undrafted idle resident enables useful spend advice")
	game.residents[0].drafted = true
	step = _next_step(game)
	_assert_true("YOU spend" not in str(step.get("text", "")), "T3 drafted idle crew do not qualify")
	game.residents[0].drafted = false
	game.food_system.salvage = 7
	step = _next_step(game)
	_assert_true("YOU spend" not in str(step.get("text", "")), "T3 salvage below the sink cost never receives a spend nudge")
	_dispose(game)


	game = _nudge_wing(8)
	game.residents[0].needs.health = 95.0
	_assert_true(game.place_blueprint(VaultBuilding.Kind.MEDICAL_BED, Vector2i(27, 12)), "T3 real unfinished Med Bed provides a non-danger leave-on action")
	for resident: VaultResident in game.residents:
		resident.state = "Preparing meals"
	step = _next_step(game)
	_assert_equal(str(step.get("text", "")), "Next: YOU leave Haul + Craft on · THEY finish the Med Bed", "T3 busy passive fixture retains its existing leave-on step")
	game.residents[0].state = "Idle"
	step = _next_step(game)
	_assert_equal(str(step.get("text", "")), "Next: YOU spend 8: build Rec Console · THEY craft", "T3 a non-danger leave-on step also exposes an affordable idle spend")
	_dispose(game)

	game = _nudge_wing(8)
	game.keep_running = true
	step = game.player_orders.keep_running_next_step()
	_assert_equal(str(step.get("text", "")), "Next: YOU spend 8: build Rec Console · THEY craft", "T3 keep-running comfort/default routing preserves actionable spend advice")
	_assert_equal(str(step.get("action", "")), "spend", "T3 keep-running preserves the structured spend action")
	_assert_false(game.player_orders._is_default_step(step), "T3 a spend action cannot be discarded as a calm keep-running default")
	_dispose(game)

	game = _nudge_wing(18, true)
	var target: Variant = game.player_orders._upgrade_offer_target()
	_assert_true(target is VaultBuilding and target.kind == VaultBuilding.Kind.GROW_TRAY
		and game.can_upgrade_building(target.building_id), "T3 real affordable Mk II target is available")
	step = _next_step(game)
	_assert_equal(str(step.get("text", "")), "Next: YOU spend 18: fit Grow Tray Mk II", "T3 affordable Grow Mk II is named with the exact fit action")
	_assert_equal(str(step.get("action", "")), "spend", "T3 the Mk II fit exposes the spend action")
	_dispose(game)

	game = _nudge_wing(18)
	game.residents[0].needs.rest = 0.0
	game.residents[0].needs.health = 20.0
	game.residents[0].drafted = true
	step = _next_step(game)
	_assert_true(str(step.get("text", "")).begins_with("Next: Ari exhausted · YOU undraft Ari")
		and "YOU spend" not in str(step.get("text", "")), "T3 a danger action outranks every affordable sink")
	_dispose(game)
