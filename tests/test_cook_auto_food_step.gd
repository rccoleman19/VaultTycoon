extends "res://tests/test_food_card_next_step.gd"

# QA idle-starve (05 seed 8): an idle player never places a food fixture, so Dax starved on day 6
# with salvage unspent. With food short the Cook takes one food step per shortage: one tap's worth,
# the whole missing chain (Charge Node when power is short, Station, Grow Tray) or nothing, paid
# from salvage left after the hatch reserve and queued unpaid costs, never while anyone is critical
# (air critical, or a fed resident at <= 50 HP), gated on air/power order (QA-d #8). After the seal,
# when only salvage blocks the step, the Cook starts reclamation ("Cook started reclamation").
# A player tap always wins. Assertions read the alert list, salvage and the map.

const COOK_PREFIX := "Cook queued "
# Literals, not VaultGame constants, so this file still runs (and fails) on the pre-rework head.
const MEDICAL_HP := 50.0
const RECLAIM_ALERT := "Cook started reclamation"
const RECLAIM_ALERT_SECONDS := 10.0


func _run() -> void:
	_run_case("a starving sealed vault: the Cook queues the step and says so once", _test_queues_and_alerts)
	_run_case("with power to spare the Cook queues the card's own build", _test_queues_card_build)
	_run_case("fed crew: the Cook queues nothing", _test_gate_fed)
	_run_case("before the seal the hatch reserve is held and a live hatch blocks it", _test_hatch_reserve)
	_run_case("air first: an unfinished Air Recycler or low air without one blocks it", _test_air_first)
	_run_case("power order: never a consumer that would shed Air or Rec", _test_power_order)
	_run_case("a player tap overrides the Cook", _test_tap_overrides)
	_run_case("no Cook build while anyone is critical (air or medical, not starvation)", _test_critical_block)
	_run_case("one step per shortage: a gap reopened mid-shortage waits for the next one", _test_one_per_shortage)
	_run_case("queued unpaid costs are reserved like the hatch patch", _test_queued_reserved)
	_run_case("salvage-short after the seal: the Cook starts reclamation and says so", _test_reclaim_alert)
	_run_case("a player tap on the reclaim button pauses the Cook's reclamation", _test_reclaim_tap)
	print("")
	if _failure_count == 0:
		print("COOK AUTO FOOD STEP TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("COOK AUTO FOOD STEP TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
			_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _starving_game(salvage: int, sealed: bool) -> VaultGame:
	var game := _game(salvage, sealed)
	_starve(game, 1)
	game.residents[1].needs.health = 90.0
	return game


func _run_for(game: VaultGame, seconds: float) -> void:
	game.step_simulation(seconds)
	game.player_orders.refresh()


func _cook_alerts(game: VaultGame) -> Array[String]:
	var found: Array[String] = []
	for alert: String in game.player_orders.all_alerts:
		if alert.begins_with(COOK_PREFIX):
			found.append(alert)
	return found


func _new_kinds(game: VaultGame, before: int) -> Array[int]:
	var kinds: Array[int] = []
	for index in range(before, game.buildings.size()):
		kinds.append(game.buildings[index].kind)
	return kinds


func _name(kind: int) -> String:
	return str(VaultBuilding.KIND_NAMES.get(kind, "?"))


func _add_complete(game: VaultGame, kind: int) -> VaultBuilding:
	var cells: Array[Vector2i] = game._annex_free_cells(1)
	game._spawn_starting_fixture(kind, cells[0], false)
	var building: VaultBuilding = game.buildings[-1]
	game.power_grid.recalculate(game.buildings)
	return building


const CHAIN := [VaultBuilding.Kind.GENERATOR, VaultBuilding.Kind.KITCHEN, VaultBuilding.Kind.GROW_TRAY]


func _chain() -> Array[int]:
	var kinds: Array[int] = []
	kinds.assign(CHAIN)
	return kinds


func _chain_cost() -> int:
	var cost := 0
	for kind: int in CHAIN:
		cost += int(VaultBuilding.COSTS[kind])
	return cost


func _complete_all(game: VaultGame) -> void:
	for building: VaultBuilding in game.buildings:
		building.complete = true
	game.power_grid.recalculate(game.buildings)


func _press_reclaim(game: VaultGame) -> void:
	game.player_orders.reclaim_button.pressed.emit()
	game.player_orders.refresh()


func _test_queues_and_alerts() -> void:
	var game := _starving_game(_chain_cost(), true)
	var before := game.buildings.size()
	_run_for(game, 2.0)
	_assert_equal(_new_kinds(game, before), _chain(), "one tap's worth: Charge Node (1 spare power), Station and Grow Tray together")
	_assert_equal(_cook_alerts(game), ["Cook queued Charge Node"] as Array[String], "one alert line names the first build: %s" % [game.player_orders.all_alerts])
	_run_for(game, 3.0)
	_assert_equal(_new_kinds(game, before).size(), 3, "nothing more while the chain is unbuilt")
	_assert_equal(_cook_alerts(game).size(), 1, "still exactly one Cook alert: %s" % [game.player_orders.all_alerts])
	_assert_true(not game.reclaim_active, "the chain was affordable, so no reclamation")
	_dispose(game)


func _test_queues_card_build() -> void:
	var game := _starving_game(22, true)
	game.start_reclamation()
	game.food_system.salvage = 22
	_add_complete(game, VaultBuilding.Kind.GENERATOR)
	game.player_orders.refresh()
	var before := game.buildings.size()
	_run_for(game, 2.0)
	_assert_equal(_new_kinds(game, before), [VaultBuilding.Kind.KITCHEN, VaultBuilding.Kind.GROW_TRAY] as Array[int], "with power to spare: Station and Grow Tray, no Charge Node")
	_assert_equal(_cook_alerts(game), ["Cook queued Nutrient Station"] as Array[String], "the alert names the actual build: %s" % [game.player_orders.all_alerts])
	_dispose(game)


func _test_gate_fed() -> void:
	var game := _game(60, true)
	game.food_system.meals = 40
	game.food_system.raw_food = 20
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
	game.player_orders.refresh()
	var before := game.buildings.size()
	_run_for(game, 3.0)
	_assert_equal(_new_kinds(game, before), [] as Array[int], "a fed vault with 40 meals: the Cook queues nothing")
	_assert_equal(_cook_alerts(game).size(), 0, "and no Cook alert")
	_assert_true(not game.reclaim_active, "and starts no reclamation")
	_dispose(game)


func _test_hatch_reserve() -> void:
	var cost := _chain_cost()
	var game := _starving_game(cost + BreachSystem.PATCH_COST - 1, false)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.DORMANT, "fixture: hatch dormant, patch owed")
	var before := game.buildings.size()
	_run_for(game, 2.0)
	_assert_equal(_new_kinds(game, before), [] as Array[int], "%d salvage minus the %d patch reserve cannot pay the %d chain, and no part of it is queued" % [cost + BreachSystem.PATCH_COST - 1, BreachSystem.PATCH_COST, cost])
	_dispose(game)
	game = _starving_game(cost + BreachSystem.PATCH_COST, false)
	before = game.buildings.size()
	_run_for(game, 2.0)
	_assert_equal(_new_kinds(game, before), _chain(), "with the reserve covered the Cook queues the chain before the seal")
	_assert_true(not game.reclaim_active, "no reclamation before the seal")
	_dispose(game)
	game = _starving_game(60, false)
	game.breach_system.phase = BreachSystem.Phase.WARNING
	before = game.buildings.size()
	_run_for(game, 2.0)
	_assert_equal(_new_kinds(game, before), [] as Array[int], "a live hatch warning blocks the Cook")
	_dispose(game)


func _test_air_first() -> void:
	var game := _starving_game(60, true)
	var cells: Array[Vector2i] = game._annex_free_cells(1)
	game.place_blueprint(VaultBuilding.Kind.AIR_RECYCLER, cells[0])
	var before := game.buildings.size()
	_run_for(game, 2.0)
	_assert_equal(_new_kinds(game, before), [] as Array[int], "an unfinished Air Recycler keeps its salvage")
	_assert_equal(_cook_alerts(game).size(), 0, "and no Cook alert")
	_dispose(game)
	game = _starving_game(60, true)
	game.oxygen_system.oxygen = OxygenSystem.LOW_OXYGEN_THRESHOLD - 5.0
	before = game.buildings.size()
	_run_for(game, 2.0)
	_assert_equal(_new_kinds(game, before), [] as Array[int], "low air with no powered recycler: air comes first")
	_dispose(game)


func _test_power_order() -> void:
	var game := _starving_game(60, true)
	var air := _add_complete(game, VaultBuilding.Kind.AIR_RECYCLER)
	var rec := _add_complete(game, VaultBuilding.Kind.RECREATION_CONSOLE)
	_add_complete(game, VaultBuilding.Kind.GENERATOR)
	game.player_orders.refresh()
	var before := game.buildings.size()
	for _round in 4:
		_run_for(game, 2.0)
		# Post-seal the Charge Node takes supply first (job_system LIFE_SUPPORT_KINDS), so the crew
		# finishes the chain in queue order: one build per round here.
		for building: VaultBuilding in game.buildings:
			if building.kind != VaultBuilding.Kind.AIR_RECYCLER and not building.complete:
				building.complete = true
				break
		game.power_grid.recalculate(game.buildings)
		_assert_true(air.powered, "the Air Recycler stays powered (round %d)" % _round)
		_assert_true(rec.powered, "the Rec Console stays powered (round %d)" % _round)
	var kinds := _new_kinds(game, before)
	_assert_true(not kinds.is_empty(), "the Cook queued something: %s" % [kinds])
	for index in kinds.size():
		var kind := kinds[index]
		if VaultBuilding.POWER_DEMAND.get(kind, 0) > 0:
			_assert_true(kinds.slice(0, index).has(VaultBuilding.Kind.GENERATOR) or game._planned_power_spare() >= 0, "%s only with planned power" % _name(kind))
	_assert_true(game._planned_power_spare() >= 0, "planned power never goes negative: %d" % game._planned_power_spare())
	_dispose(game)
	# 1 spare power: a Station (2) would shed a load, so the chain leads with a Charge Node.
	game = _starving_game(60, true)
	before = game.buildings.size()
	_run_for(game, 2.0)
	var queued := _new_kinds(game, before)
	_assert_true(not queued.is_empty() and queued[0] == VaultBuilding.Kind.GENERATOR, "power short: Charge Node first: %s" % [queued])
	_dispose(game)


func _test_tap_overrides() -> void:
	var game := _starving_game(60, true)
	var before := game.buildings.size()
	_run_for(game, 2.0)
	var queued: VaultBuilding = game.buildings[before] if game.buildings.size() > before else null
	_assert_true(queued != null, "fixture: the Cook queued a blueprint")
	if queued != null:
		var salvage := game.food_system.salvage
		game.active_tool = "cancel"
		for index in range(game.buildings.size() - 1, before - 1, -1):
			_assert_true(game.issue_order(game.buildings[index].cell), "the player cancels the Cook's blueprint %d" % index)
		game.active_tool = "select"
		_assert_true(game.food_system.salvage >= salvage, "refunded")
		var count := game.buildings.size()
		_run_for(game, 5.0)
		_assert_equal(game.buildings.size(), count, "the Cook does not re-queue what the player cancelled")
		_assert_equal(_cook_alerts(game).size(), 0, "and its alert is gone: %s" % [game.player_orders.all_alerts])
		game.food_system.meals = 40
		for resident: VaultResident in game.residents:
			resident.needs.food = 100.0
		_run_for(game, 2.0)
		_starve(game, 1)
		game.residents[1].needs.health = 90.0
		_run_for(game, 3.0)
		_assert_equal(game.buildings.size(), count, "nor in the next shortage")
	_dispose(game)
	# The player's own food blueprint comes first; the Cook waits instead of adding another.
	game = _starving_game(60, true)
	var cells: Array[Vector2i] = game._annex_free_cells(1)
	game.active_tool = "kitchen"
	_assert_true(game.issue_order(cells[0]), "fixture: the player places a Nutrient Station")
	game.active_tool = "select"
	before = game.buildings.size()
	_run_for(game, 3.0)
	_assert_equal(_new_kinds(game, before), [] as Array[int], "the Cook adds nothing while the player's Station is unbuilt")
	_assert_equal(_cook_alerts(game).size(), 0, "no Cook alert for the player's own build")
	_dispose(game)


func _test_critical_block() -> void:
	var game := _starving_game(60, true)
	_add_complete(game, VaultBuilding.Kind.AIR_RECYCLER)
	_add_complete(game, VaultBuilding.Kind.GENERATOR)
	game.oxygen_system.oxygen = OxygenSystem.CRITICAL_OXYGEN_THRESHOLD - 10.0
	var before := game.buildings.size()
	_run_for(game, 2.0)
	_assert_equal(_new_kinds(game, before), [] as Array[int], "air critical (even with a powered recycler): no Cook build")
	_dispose(game)
	game = _starving_game(60, true)
	game.residents[2].needs.food = 60.0
	game.residents[2].needs.health = MEDICAL_HP
	before = game.buildings.size()
	_run_for(game, 2.0)
	_assert_equal(_new_kinds(game, before), [] as Array[int], "a fed resident at %d HP is a medical emergency: no Cook build" % int(MEDICAL_HP))
	_assert_true(not game.reclaim_active, "and no reclamation either")
	_dispose(game)
	game = _starving_game(60, true)
	game.residents[1].needs.health = 20.0
	before = game.buildings.size()
	_run_for(game, 2.0)
	_assert_equal(_new_kinds(game, before), _chain(), "a starving resident at 20 HP does not block it: food is the cure")
	_dispose(game)


func _test_one_per_shortage() -> void:
	var game := _starving_game(80, true)
	var before := game.buildings.size()
	_run_for(game, 2.0)
	_assert_equal(_new_kinds(game, before), _chain(), "fixture: the Cook's step")
	_complete_all(game)
	var grow: VaultBuilding = game.buildings[-1]
	_assert_true(game.deconstruct_building(grow.building_id), "fixture: the Grow Tray is torn down mid-shortage")
	var count := game.buildings.size()
	_run_for(game, 3.0)
	_assert_equal(game.buildings.size(), count, "same shortage: the Cook does not take a second step")
	game.food_system.meals = 40
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
	_run_for(game, 2.0)
	_starve(game, 1)
	game.residents[1].needs.health = 90.0
	_run_for(game, 2.0)
	_assert_equal(_new_kinds(game, count), [VaultBuilding.Kind.GROW_TRAY] as Array[int], "a new shortage: one new step")
	_dispose(game)


func _test_queued_reserved() -> void:
	var game := _starving_game(60, true)
	game.start_reclamation()
	var cells: Array[Vector2i] = game._annex_free_cells(1)
	game.place_blueprint(VaultBuilding.Kind.BED, cells[0])
	var bed_cost := int(VaultBuilding.COSTS[VaultBuilding.Kind.BED])
	game.food_system.salvage = _chain_cost() + bed_cost - 1
	var before := game.buildings.size()
	_run_for(game, 2.0)
	_assert_equal(_new_kinds(game, before), [] as Array[int], "%d salvage with a %d bunk queued cannot pay the %d chain" % [_chain_cost() + bed_cost - 1, bed_cost, _chain_cost()])
	game.food_system.salvage = _chain_cost() + bed_cost
	_run_for(game, 2.0)
	_assert_equal(_new_kinds(game, before), _chain(), "one more salvage pays it")
	_dispose(game)


func _test_reclaim_alert() -> void:
	var game := _starving_game(26, true)
	var before := game.buildings.size()
	_run_for(game, 2.0)
	_assert_true(game.reclaim_active, "26 salvage < 40: the Cook starts reclamation")
	_assert_equal(_new_kinds(game, before), _chain(), "and queues the chain with it")
	_assert_true(game.player_orders.all_alerts.has(RECLAIM_ALERT), "alert says so: %s" % [game.player_orders.all_alerts])
	_assert_true(game.player_orders.reclaim_button_text().contains("Cook"), "the reclaim button names the Cook: %s" % game.player_orders.reclaim_button_text())
	_run_for(game, RECLAIM_ALERT_SECONDS)
	_assert_true(not game.player_orders.all_alerts.has(RECLAIM_ALERT), "the line clears after %d s" % int(RECLAIM_ALERT_SECONDS))
	_dispose(game)


func _test_reclaim_tap() -> void:
	var game := _starving_game(26, true)
	_run_for(game, 2.0)
	_assert_true(game.reclaim_active and (game.get("cook_auto_started_reclaim") == true), "fixture: the Cook started reclamation")
	_assert_true(not game.player_orders.reclaim_button.disabled, "the reclaim button is tappable")
	_press_reclaim(game)
	_assert_true((game.get("reclaim_paused") == true), "the tap pauses it")
	_assert_true(not game.player_orders.all_alerts.has(RECLAIM_ALERT), "and the Cook line is gone: %s" % [game.player_orders.all_alerts])
	var paid := game.reclaim_paid
	_run_for(game, VaultGame.RECLAIM_INTERVAL + 2.0)
	_assert_equal(game.reclaim_paid, paid, "no deliveries while paused")
	_assert_true((game.get("reclaim_paused") == true), "the Cook does not restart it")
	_press_reclaim(game)
	_assert_true(not (game.get("reclaim_paused") == true) and game.reclaim_active, "a second tap resumes it")
	_run_for(game, VaultGame.RECLAIM_INTERVAL + 2.0)
	_assert_true(game.reclaim_paid > paid, "and deliveries continue")
	_dispose(game)
