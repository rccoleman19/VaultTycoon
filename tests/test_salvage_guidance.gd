extends "res://tests/test_survival_next.gd"


func _run() -> void:
	_test_fallback_day_seven_ready()
	_test_fallback_charge_moods_and_rec()
	_test_fallback_recovery_variants()
	_test_fallback_funded_complete_cancelled()
	_test_fallback_other_kinds_and_order()
	_test_fallback_mixed_skips()
	_test_fallback_precedence()
	_test_fallback_real_recovery()
	_test_salvage_shortfall()
	_test_salvage_supplied_charge_with_reserve()
	_test_salvage_recovery_sources()
	_test_salvage_inspector()
	_test_salvage_real_recovery()
	print("Salvage guidance tests: %d assertions, %d failures" % [_assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


const SALVAGE_RECOVERY_BOUND := 120.0


func _salvage_rec_game() -> VaultGame:
	var game := _healthy_game()
	game.residents[0].needs.mood = 9.0
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(20, 12))
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(21, 12))
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(22, 12))
	_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(23, 12))
	var rec := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(24, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_equal([game.power_grid.supply, game.power_grid.demand, game.power_grid.served], [9, 10, 9], "salvage Rec fixture actual grid")
	_assert_true(game.power_grid.is_building_shed(rec.building_id), "salvage Rec genuinely shed")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(25, 12)), "unfunded Charge placed")
	game.food_system.salvage = 0
	return game


func _test_salvage_shortfall() -> void:
	var game := _salvage_rec_game()
	var charge := game.get_building_at(Vector2i(25, 12))
	_assert_salvage_tip(game, 18, 6)
	game.set_tool("bed")
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "bed", "new dig suggestion preserves active build tool")
	_assert_equal(game.player_orders.objective_label.text, "Next: YOU mark 6 rock [E] · THEY fund the Charge Node", "refresh displays new dig tip")
	game.food_system.salvage = 17
	_assert_salvage_tip(game, 1, 1)
	game.food_system.salvage = 18
	_assert_step(game, FINISH_CHARGE_NEXT, "select", FINISH_CHARGE_HELP)
	charge.add_delivery(10)
	game.food_system.salvage = 2
	_assert_salvage_tip(game, 6, 2)
	var supply := game.job_system._find_matching_job(JobSystem.JobType.SUPPLY_BUILD, charge.cell, charge.building_id)
	supply.in_transit = 4
	var carrier: VaultResident = game.residents[0]
	carrier.current_job_type = JobSystem.JobType.SUPPLY_BUILD
	carrier.current_job_id = supply.id
	carrier.carrying = 4
	_assert_salvage_tip(game, 2, 1)
	_assert_equal(game.job_system.get_build_supply_in_transit(charge.building_id), 4, "supply cargo counted once")
	supply.in_transit = 0
	_assert_salvage_tip(game, 2, 1)
	carrier.clear_job()
	carrier.carrying = 0
	_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(26, 12)), "unrelated blueprint placed")
	var bed := game.get_building_at(Vector2i(26, 12))
	var unrelated := game.job_system._find_matching_job(JobSystem.JobType.SUPPLY_BUILD, bed.cell, bed.building_id)
	unrelated.in_transit = 4
	_assert_salvage_tip(game, 6, 2)
	charge.delivered = charge.get_cost()
	game.food_system.salvage = 0
	_assert_step(game, FINISH_CHARGE_NEXT, "select", FINISH_CHARGE_HELP)
	charge.delivered = 0
	game.food_system.salvage = 18
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(27, 12)), "second Charge placed")
	_assert_salvage_tip(game, 18, 6)
	_dispose(game)


func _test_salvage_supplied_charge_with_reserve() -> void:
	var game := _salvage_rec_game()
	var charge := game.get_building_at(Vector2i(25, 12))
	_assert_equal(charge.get_cost(), 18, "supplied Charge cost")
	_assert_equal(charge.add_delivery(charge.get_cost()), 18, "Charge fully delivered")
	_assert_false(charge.complete, "supplied Charge still awaits assembly")
	game.breach_system.advance(0.0, BreachSystem.WARNING_AT_SECONDS)
	var reserve := game.job_system.get_breach_salvage_reserve()
	_assert_true(reserve > 0, "real unsupplied hatch reserves salvage")
	_assert_equal(reserve, 4, "hatch reserve amount")
	_assert_equal(game.food_system.salvage, 0, "supplied Charge has no shared stock")
	_assert_step(game, FINISH_CHARGE_NEXT, "select", FINISH_CHARGE_HELP)
	game.select_building(charge.building_id)
	var supplied_original := "Blueprint · Salvage 18/18\nAssembly remaining: %.1fs" % charge.construction_left
	game.player_orders._refresh_inspector()
	_assert_equal(game.player_orders.inspector_state.text, supplied_original, "supplied Charge inspector ignores hatch reserve")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(26, 12)), "second unfunded Charge placed beside supplied Charge")
	var unfunded := game.get_building_at(Vector2i(26, 12))
	_assert_equal(unfunded.get_cost(), 18, "second Charge cost")
	_assert_equal(unfunded.delivered, 0, "second Charge is unfunded")
	_assert_equal(game.job_system.get_uncredited_rubble(), 0, "mixed Charge fixture has no uncredited rubble")
	_assert_equal(game.map_grid.dig_marks.size(), 0, "mixed Charge fixture has no queued digs")
	var unfunded_original := "Blueprint · Salvage 0/18\nAssembly remaining: %.1fs" % unfunded.construction_left
	for sample: Dictionary in [
		{"salvage": 0, "spendable": -4, "shortfall": 22, "tiles": 8},
		{"salvage": 6, "spendable": 2, "shortfall": 16, "tiles": 6},
	]:
		game.food_system.salvage = sample.salvage
		var spendable: int = game.food_system.salvage - reserve
		var shortfall := unfunded.get_cost() - unfunded.delivered - spendable
		var tiles := ceili(float(shortfall) / 3.0) - game.map_grid.dig_marks.size()
		_assert_equal(spendable, sample.spendable, "mixed Charge spendable stock includes hatch reserve")
		_assert_equal(shortfall, sample.shortfall, "only unfunded Charge contributes remaining cost")
		_assert_equal(tiles, sample.tiles, "mixed Charge recovery tile count")
		_assert_salvage_tip(game, shortfall, tiles)
		game.select_building(unfunded.building_id)
		game.player_orders._refresh_inspector()
		_assert_equal(game.player_orders.inspector_state.text, unfunded_original + "\nShort %d salvage (shared stock) · dig %d more rock" % [shortfall, tiles], "unfunded Charge inspector includes exact shared shortage")
		game.select_building(charge.building_id)
		game.player_orders._refresh_inspector()
		_assert_equal(game.player_orders.inspector_state.text, supplied_original, "supplied Charge inspector excludes other Charge shortage")
	_dispose(game)


func _test_salvage_recovery_sources() -> void:
	var game := _salvage_rec_game()
	for x in range(17, 19):
		_assert_true(game.map_grid.queue_dig(Vector2i(x, 10)), "pending rock marked")
	_assert_salvage_tip(game, 18, 4)
	for x in range(19, 23):
		_assert_true(game.map_grid.queue_dig(Vector2i(x, 10)), "covering rock marked")
	_assert_salvage_tip(game, 18, 0)
	game.map_grid.dig_marks.clear()
	game.job_system.queue_rubble(Vector2i(18, 11), 18)
	_assert_salvage_tip(game, 18, 0)
	var rubble := game.job_system._find_matching_job(JobSystem.JobType.HAUL_RUBBLE, Vector2i(18, 11), -1)
	var carrier: VaultResident = game.residents[0]
	carrier.current_job_type = JobSystem.JobType.HAUL_RUBBLE
	carrier.current_job_id = rubble.id
	carrier.carrying = 18
	_assert_equal(game.job_system.get_uncredited_rubble(), 18, "carried rubble and job amount counted once")
	_assert_salvage_tip(game, 18, 0)
	_dispose(game)
	game = _salvage_rec_game()
	game.food_system.salvage = 18
	game.breach_system.advance(0.0, BreachSystem.WARNING_AT_SECONDS)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.WARNING, "real hatch warning")
	_assert_equal(game.job_system.get_breach_salvage_reserve(), BreachSystem.PATCH_COST, "active unsupplied patch reserve")
	_assert_salvage_tip(game, 4, 2)
	_dispose(game)
	game = _healthy_game()
	var observed: Array[int] = []
	game.map_grid.rubble_created.connect(func(_cell: Vector2i, amount: int): observed.append(amount))
	_assert_true(game.map_grid.queue_dig(Vector2i(17, 10)), "yield test marks real rock")
	_assert_true(game.map_grid.apply_dig_work(Vector2i(17, 10), 8.0), "yield test completes real dig")
	_assert_equal(observed, [PlayerOrders.DIG_SALVAGE_YIELD], "tip constant equals actual emitted dig yield")
	_dispose(game)


func _test_salvage_inspector() -> void:
	var game := _salvage_rec_game()
	var charge := game.get_building_at(Vector2i(25, 12))
	game.selected_resident_id = -1
	game.selected_building_id = charge.building_id
	var original := "Blueprint · Salvage %d/%d\nAssembly remaining: %.1fs" % [charge.delivered, charge.get_cost(), charge.construction_left]
	game.player_orders._refresh_inspector()
	_assert_equal(game.player_orders.inspector_state.text, original + "\nShort 18 salvage (shared stock) · dig 6 more rock", "inspector retains original lines and appends shortage")
	game.job_system.queue_rubble(Vector2i(18, 11), 18)
	game.player_orders._refresh_inspector()
	_assert_equal(game.player_orders.inspector_state.text, original + "\nShort 18 salvage (shared stock) · queued dig/haul covers it", "inspector covers queued recovery")
	game.food_system.salvage = 18
	game.player_orders._refresh_inspector()
	_assert_equal(game.player_orders.inspector_state.text, original, "funded inspector exactly original two lines")
	_dispose(game)
	game = _healthy_game()
	_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(26, 12)), "generic inspector blueprint")
	var bed := game.get_building_at(Vector2i(26, 12))
	game.selected_resident_id = -1
	game.selected_building_id = bed.building_id
	game.food_system.salvage = 0
	var bed_original := "Blueprint · Salvage %d/%d\nAssembly remaining: %.1fs" % [bed.delivered, bed.get_cost(), bed.construction_left]
	var tiles := ceili(float(bed.get_cost()) / PlayerOrders.DIG_SALVAGE_YIELD) - game.map_grid.dig_marks.size()
	game.player_orders._refresh_inspector()
	_assert_equal(game.player_orders.inspector_state.text, bed_original + "\nShort %d salvage (shared stock) · dig %d more rock" % [bed.get_cost(), tiles], "inspector shortfall applies to non-Charge kind")
	_dispose(game)


func _test_salvage_real_recovery() -> void:
	var game := _salvage_rec_game()
	var charge := game.get_building_at(Vector2i(25, 12))
	var original_alive := game.get_alive_count()
	game.food_system.meals = 100
	var tip: Dictionary = game.player_orders._primary_next_step()
	var count := int(String(tip.text).split(" ")[3])
	_assert_equal(count, 6, "real recovery reads six tiles from tip")
	game.set_tool("dig")
	for x in range(17, 17 + count):
		_assert_true(game.issue_order(Vector2i(x, 10)), "ordinary reachable rock order")
	game.set_tool("select")
	var ticks := 0
	var elapsed := 0.0
	var dug_at := -1.0
	var supplied_at := -1.0
	var ordinary_work := true
	while ticks < int(round(SALVAGE_RECOVERY_BOUND / VaultGame.SIMULATION_TICK)) and not charge.complete and not game.ended:
		game.step_simulation(VaultGame.SIMULATION_TICK)
		ticks += 1
		elapsed = ticks * VaultGame.SIMULATION_TICK
		for resident: VaultResident in game.residents:
			ordinary_work = ordinary_work and not resident.drafted and not resident.is_forced_job
		if dug_at < 0.0 and game.map_grid.dig_marks.is_empty():
			dug_at = elapsed
		if supplied_at < 0.0 and charge.is_supplied():
			supplied_at = elapsed
	_assert_true(charge.complete, "ordinary Dig Haul Supply Craft completes Charge within declared bound")
	_assert_true(ordinary_work, "real recovery uses undrafted crew with no forced jobs")
	_assert_true(dug_at > 0.0 and supplied_at >= dug_at, "real recovery observes dug and supplied milestones")
	_assert_equal(game.get_alive_count(), original_alive, "real recovery keeps all residents alive")
	_assert_true(game.get_building_at(Vector2i(24, 12)).powered, "real recovery powers Rec")
	_assert_equal([game.power_grid.supply, game.power_grid.demand, game.power_grid.served], [16, 10, 10], "real recovery final power")
	print("Salvage recovery: dig complete %.1fs, Charge supplied %.1fs, Charge complete %.1fs; PWR %d/%d served %d" % [dug_at, supplied_at, elapsed, game.power_grid.supply, game.power_grid.demand, game.power_grid.served])
	_dispose(game)


const FALLBACK_DAY_SEVEN_NEXT := "Next: YOU designate needs · THEY hold Day 7"
const FALLBACK_DAY_SEVEN_HELP := "Keep designating dig/build/stockpile. Defaults keep food, power, and air running."
const FALLBACK_RECOVERY_BOUND := 120.0


func _fallback_ready_game() -> VaultGame:
	var game := _air_ready_game()
	game.user_paused = true
	# Directly carving the progression fixture leaves 12 * 3 uncredited salvage.
	_assert_equal(game.job_system.get_uncredited_rubble(), 36, "fallback fixture accounts for progression rubble")
	game.job_system.jobs = game.job_system.jobs.filter(func(job: Dictionary) -> bool: return int(job.type) not in [JobSystem.JobType.DIG, JobSystem.JobType.HAUL_RUBBLE])
	_assert_equal(game.job_system.get_uncredited_rubble(), 0, "fallback fixture explicitly clears all uncredited rubble")
	_assert_true(game.map_grid.dig_marks.is_empty(), "fallback fixture has no outstanding marks")
	game.breach_system.phase = BreachSystem.Phase.SEALED
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.patch_work_left = 0.0
	_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(25, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_true(game.breach_system.is_sealed(), "fallback fixture hatch sealed")
	_assert_false(game.day_cycle.completed, "fallback fixture has not completed Day 7")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.BED), 2, "fallback fixture meets bunk progression")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.GENERATOR, true), 1, "fallback fixture already has first Charge")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.AIR_RECYCLER), 1, "fallback fixture Air powered")
	for resident: VaultResident in game.residents:
		_assert_true(resident.needs.mood > 9.0, "fallback fixture is above the Rec crisis threshold")
	return game


func _fallback_charge_game() -> VaultGame:
	var game := _fallback_ready_game()
	var rec := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(26, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_equal([game.power_grid.supply, game.power_grid.demand, game.power_grid.served], [9, 10, 9], "fallback Rec shed at nine of ten power")
	_assert_true(game.power_grid.is_building_shed(rec.building_id), "fallback Rec really shed")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(27, 12)), "fallback second Charge placed")
	game.food_system.salvage = 0
	_assert_equal(game.job_system.get_uncredited_rubble(), 0, "mark-rock fallback has no uncredited rubble")
	_assert_true(game.map_grid.dig_marks.is_empty(), "mark-rock fallback has no queued marks")
	return game


func _test_fallback_day_seven_ready() -> void:
	var game := _fallback_ready_game()
	_assert_step(game, FALLBACK_DAY_SEVEN_NEXT, "select", FALLBACK_DAY_SEVEN_HELP)
	_dispose(game)


func _test_fallback_charge_moods_and_rec() -> void:
	var game := _fallback_charge_game()
	for mood in [9.0001, 12.0, 100.0, 9.0]:
		game.residents[0].needs.mood = mood
		_assert_salvage_tip(game, 18, 6)
	game.residents[0].needs.mood = 100.0
	var rec := game.get_building_at(Vector2i(26, 12))
	rec.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	_assert_salvage_tip(game, 18, 6)
	rec.manually_disabled = false
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(28, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_true(rec.powered, "third staged Charge powers Rec beside short second Charge")
	_assert_salvage_tip(game, 18, 6)
	_assert_true(game._remove_building(rec, 0, "Staged absent Rec"), "remove Rec without salvage refund")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.RECREATION_CONSOLE), 0, "fallback Rec absent")
	_assert_salvage_tip(game, 18, 6)
	game.set_tool("bed")
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "bed", "fallback refresh preserves active build tool")
	_assert_equal(game.player_orders.objective_label.text, "Next: YOU mark 6 rock [E] · THEY fund the Charge Node", "fallback refresh displays exact mark instruction")
	_dispose(game)


func _test_fallback_recovery_variants() -> void:
	var game := _fallback_charge_game()
	for x in range(17, 19):
		_assert_true(game.map_grid.queue_dig(Vector2i(x, 9)), "fallback two ordinary rock marks")
	_assert_salvage_tip(game, 18, 4)
	for x in range(19, 23):
		_assert_true(game.map_grid.queue_dig(Vector2i(x, 9)), "fallback covering rock marks")
	_assert_salvage_tip(game, 18, 0)
	game.map_grid.dig_marks.clear()
	game.job_system.queue_rubble(Vector2i(18, 10), 18)
	_assert_salvage_tip(game, 18, 0)
	_dispose(game)
	game = _fallback_charge_game()
	var charge := game.get_building_at(Vector2i(27, 12))
	_assert_equal(charge.add_delivery(10), 10, "fallback Charge partially delivered ten of eighteen")
	game.food_system.salvage = 2
	_assert_salvage_tip(game, 6, 2)
	var supply := game.job_system._find_matching_job(JobSystem.JobType.SUPPLY_BUILD, charge.cell, charge.building_id)
	supply.in_transit = 4
	var carrier: VaultResident = game.residents[0]
	carrier.current_job_type = JobSystem.JobType.SUPPLY_BUILD
	carrier.current_job_id = supply.id
	carrier.carrying = 4
	_assert_equal(game.job_system.get_build_supply_in_transit(charge.building_id), 4, "fallback cargo appears in job and carrier but counts once")
	_assert_salvage_tip(game, 2, 1)
	supply.in_transit = 0
	_assert_salvage_tip(game, 2, 1)
	carrier.clear_job()
	carrier.carrying = 0
	_assert_equal(charge.add_delivery(8), 8, "fallback remaining delivery completes supply")
	game.food_system.salvage = 0
	_assert_false(charge.complete, "fully supplied fallback still unfinished")
	_assert_step(game, FALLBACK_DAY_SEVEN_NEXT, "select", FALLBACK_DAY_SEVEN_HELP)
	_dispose(game)


func _test_fallback_funded_complete_cancelled() -> void:
	var game := _fallback_charge_game()
	var charge := game.get_building_at(Vector2i(27, 12))
	game.food_system.salvage = 18
	_assert_false(charge.is_supplied(), "funded fallback has stock but awaits delivery")
	_assert_step(game, FALLBACK_DAY_SEVEN_NEXT, "select", FALLBACK_DAY_SEVEN_HELP)
	game.food_system.salvage = 0
	_assert_salvage_tip(game, 18, 6)
	charge.add_delivery(18)
	_assert_true(charge.apply_build_work(8.0), "staged fallback Charge completes")
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, FALLBACK_DAY_SEVEN_NEXT, "select", FALLBACK_DAY_SEVEN_HELP)
	_dispose(game)
	game = _fallback_charge_game()
	game.set_tool("cancel")
	_assert_true(game.issue_order(Vector2i(27, 12)), "ordinary cancellation removes short blueprint")
	_assert_step(game, FALLBACK_DAY_SEVEN_NEXT, "select", FALLBACK_DAY_SEVEN_HELP)
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "cancel", "Day-7 refresh preserves cancellation tool")
	_dispose(game)


func _test_fallback_other_kinds_and_order() -> void:
	for sample: Dictionary in [
		{"kind": VaultBuilding.Kind.RECREATION_CONSOLE, "name": "Rec Console"},
		{"kind": VaultBuilding.Kind.MEDICAL_BED, "name": "Medical Bed"},
		{"kind": VaultBuilding.Kind.BED, "name": "Bunk"},
	]:
		var game := _fallback_ready_game()
		_assert_true(game.place_blueprint(sample.kind, Vector2i(26, 12)), "non-Charge fallback blueprint placed")
		game.food_system.salvage = 0
		_assert_step(game, "Next: YOU mark 3 rock [E] · THEY fund the %s" % sample.name, "dig", "The %s blueprint is 8 salvage short. Each dug rock tile yields 3 salvage once hauled." % sample.name)
		_dispose(game)
	for first_kind in [VaultBuilding.Kind.BED, VaultBuilding.Kind.MEDICAL_BED]:
		var game := _fallback_ready_game()
		var second_kind := VaultBuilding.Kind.MEDICAL_BED if first_kind == VaultBuilding.Kind.BED else VaultBuilding.Kind.BED
		_assert_true(game.place_blueprint(first_kind, Vector2i(26, 12)), "oldest short kind placed")
		_assert_true(game.place_blueprint(second_kind, Vector2i(27, 12)), "newer short kind placed")
		var oldest := game.get_building_at(Vector2i(26, 12))
		_assert_true(oldest.building_id < game.get_building_at(Vector2i(27, 12)).building_id, "oldest blueprint has lower id")
		# Deliberately disagree with array order so the assertion tests building_id.
		game.buildings.reverse()
		game.food_system.salvage = 0
		var name: String = VaultBuilding.KIND_NAMES[first_kind]
		_assert_step(game, "Next: YOU mark 3 rock [E] · THEY fund the %s" % name, "dig", "The %s blueprint is 8 salvage short. Each dug rock tile yields 3 salvage once hauled." % name)
		_dispose(game)
	var game := _fallback_ready_game()
	var completed := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(26, 12))
	completed.delivered = 0
	var core := _add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(27, 12))
	core.is_emergency_core = true
	core.complete = false
	core.delivered = 0
	game.food_system.salvage = 0
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, FALLBACK_DAY_SEVEN_NEXT, "select", FALLBACK_DAY_SEVEN_HELP)
	_dispose(game)


func _test_fallback_precedence() -> void:
	var game := _fallback_charge_game()
	game.breach_system.phase = BreachSystem.Phase.DORMANT
	game.breach_system.patch_delivered = 0
	_assert_step(game, "Next: YOU keep 4 salvage · THEY haul/craft hatch", "select", "Reserve 4 salvage. Leave Haul + Craft above OFF so they auto-respond to the hatch.")
	game.food_system.salvage = 4
	_assert_step(game, "Next: YOU watch hatch · THEY auto-patch", "select", "When the hatch warns, undrafted Haul + Craft claim supply/patch without draft.")
	game.breach_system.phase = BreachSystem.Phase.SEALED
	game.food_system.salvage = 0
	game.residents[0].needs.food = 19.0
	game.food_system.meals = 0
	game.get_building_at(Vector2i(24, 12)).manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, POWER_NEXT, "select", "Power the Nutrient Station so Cook can run.")
	game.food_system.meals = 100
	game.residents[0].needs.food = 100.0
	game.get_building_at(Vector2i(24, 12)).manually_disabled = false
	game.power_grid.recalculate(game.buildings)
	for resident: VaultResident in game.residents:
		resident.needs.rest = 28.0
	_assert_step(game, BUNK_NEXT, "bed", "Place bunks so tired undrafted crew have a bed.")
	_dispose(game)
	game = _healthy_game()
	game.food_system.salvage = 0
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(25, 12)), "opening fixture includes unfunded blueprint")
	_assert_step(game, DIG_NEXT, "dig", "DIG [E] designates rock. Undrafted crew auto-claim Dig (default rank 3). Draft is optional.")
	_assert_true(game.map_grid.queue_dig(Vector2i(17, 10)), "opening fixture queues rock")
	_assert_step(game, "Next: YOU keep marking digs [E] · THEY dig/haul alone", "dig", "Keep designating connected rock. They dig then haul rubble without draft. PRIORITIES [P] only to specialize.")
	game.set_tool("medical")
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "medical", "earlier progression refresh preserves active tool")
	_dispose(game)


func _test_fallback_real_recovery() -> void:
	var game := _fallback_charge_game()
	var charge := game.get_building_at(Vector2i(27, 12))
	# This is the final fixture staging. All subsequent progress is ordinary simulation.
	game.food_system.meals = 100
	game.user_paused = false
	_assert_true(FALLBACK_RECOVERY_BOUND <= 120.0, "fallback recovery bound is at most 120 simulation seconds")
	_assert_salvage_tip(game, 18, 6)
	var tip: Dictionary = game.player_orders._primary_next_step()
	var count := int(String(tip.text).split(" ")[3])
	_assert_equal(count, 6, "fallback recovery reads six rocks from live tip")
	game.set_tool("dig")
	for x in range(17, 17 + count):
		_assert_true(game.issue_order(Vector2i(x, 9)), "fallback recovery ordinary reachable dig order")
	game.set_tool("select")
	_assert_salvage_tip(game, 18, 0)
	var ticks := 0
	var marks_done_at := -1.0
	var funded_at := -1.0
	var complete_at := -1.0
	var ordinary_work := true
	var tips_seen := {}
	while ticks < int(round(FALLBACK_RECOVERY_BOUND / VaultGame.SIMULATION_TICK)) and not charge.complete and not game.ended:
		game.step_simulation(VaultGame.SIMULATION_TICK)
		ticks += 1
		var elapsed := ticks * VaultGame.SIMULATION_TICK
		for resident: VaultResident in game.residents:
			ordinary_work = ordinary_work and not resident.drafted and not resident.is_forced_job
		tips_seen[String(game.player_orders._primary_next_step().text)] = true
		if marks_done_at < 0.0 and game.map_grid.dig_marks.is_empty():
			marks_done_at = elapsed
		if funded_at < 0.0 and game.player_orders._salvage_shortfall(VaultBuilding.Kind.GENERATOR) == 0:
			funded_at = elapsed
			_assert_step(game, FALLBACK_DAY_SEVEN_NEXT, "select", FALLBACK_DAY_SEVEN_HELP)
		if charge.complete:
			complete_at = elapsed
	_assert_true(charge.complete, "fallback ordinary Dig Haul Supply Craft completes within declared bound")
	_assert_true(ordinary_work, "fallback recovery stays undrafted and unforced every tick")
	var allowed_tips := ["Next: YOU leave Dig + Haul on · THEY fund the Charge Node", FALLBACK_DAY_SEVEN_NEXT]
	for seen: String in tips_seen:
		_assert_true(seen in allowed_tips, "fallback recovery tip per tick is leave Dig + Haul on or Day 7: %s" % seen)
	_assert_true(marks_done_at > 0.0 and funded_at >= marks_done_at and complete_at >= funded_at, "fallback recovery observes marks then funded then complete")
	_assert_step(game, FALLBACK_DAY_SEVEN_NEXT, "select", FALLBACK_DAY_SEVEN_HELP)
	_assert_equal([game.power_grid.supply, game.power_grid.demand, game.power_grid.served], [16, 10, 10], "fallback recovery final PWR")
	_assert_true(game.get_building_at(Vector2i(26, 12)).powered, "fallback recovery powers Rec")
	_assert_equal(game.get_alive_count(), 4, "fallback recovery keeps crew alive")
	print("Fallback recovery: marks done %.1fs, Charge funded %.1fs, Charge complete %.1fs; PWR %d/%d/%d" % [marks_done_at, funded_at, complete_at, game.power_grid.supply, game.power_grid.demand, game.power_grid.served])
	_dispose(game)


func _test_fallback_mixed_skips() -> void:
	for excluded_state in ["supplied", "core", "complete"]:
		var game := _fallback_ready_game()
		_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(26, 12)), "older excluded Charge placed")
		var excluded := game.get_building_at(Vector2i(26, 12))
		if excluded_state == "supplied":
			_assert_equal(excluded.add_delivery(18), 18, "oldest Charge fully supplied")
		elif excluded_state == "core":
			excluded.is_emergency_core = true
		else:
			excluded.complete = true
		_assert_true(game.place_blueprint(VaultBuilding.Kind.MEDICAL_BED, Vector2i(27, 12)), "middle Medical blueprint placed")
		var medical := game.get_building_at(Vector2i(27, 12))
		_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(28, 12)), "newer genuinely short Charge placed")
		_assert_true(excluded.building_id < medical.building_id and medical.building_id < game.get_building_at(Vector2i(28, 12)).building_id, "excluded Charge precedes Medical which precedes short Charge")
		game.food_system.salvage = 0
		_assert_equal(game.player_orders._salvage_shortfall(VaultBuilding.Kind.GENERATOR), 18, "same-kind newer Charge remains eighteen short")
		game.buildings.reverse()
		_assert_step(game, "Next: YOU mark 3 rock [E] · THEY fund the Medical Bed", "dig", "The Medical Bed blueprint is 8 salvage short. Each dug rock tile yields 3 salvage once hauled.")
		_dispose(game)
