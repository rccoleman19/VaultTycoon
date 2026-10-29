extends "res://tests/test_food_card_next_step.gd"

# QA idle-starve (05 seed 8): an idle player never places a food fixture, so Dax starved on day 6
# with salvage unspent. With food short and the food card's step affordable after the hatch reserve,
# the Cook queues that step itself, gated on air/power order (QA-d #8), with one alert line
# "Cook queued <build>". A player tap always wins. Assertions read the alert list and the map.

const COOK_PREFIX := "Cook queued "


func _run() -> void:
	_run_case("a starving sealed vault: the Cook queues the step and says so once", _test_queues_and_alerts)
	_run_case("with power to spare the Cook queues the card's own build", _test_queues_card_build)
	_run_case("fed crew: the Cook queues nothing", _test_gate_fed)
	_run_case("before the seal the hatch reserve is held and a live hatch blocks it", _test_hatch_reserve)
	_run_case("air first: an unfinished Air Recycler or low air without one blocks it", _test_air_first)
	_run_case("power order: never a consumer that would shed Air or Rec", _test_power_order)
	_run_case("a player tap overrides the Cook", _test_tap_overrides)
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


func _test_queues_and_alerts() -> void:
	var game := _starving_game(35, true)
	var before := game.buildings.size()
	_run_for(game, 2.0)
	var kinds := _new_kinds(game, before)
	_assert_equal(kinds.size(), 1, "the Cook queues exactly one blueprint: %s" % [kinds])
	if kinds.size() >= 1:
		_assert_equal(kinds[0], VaultBuilding.Kind.GENERATOR, "Station needs 2 power and 1 is spare, so a Charge Node first")
		_assert_equal(_cook_alerts(game), ["Cook queued Charge Node"] as Array[String], "one alert line names it: %s" % [game.player_orders.all_alerts])
	_run_for(game, 3.0)
	_assert_equal(_new_kinds(game, before).size(), 1, "no second blueprint while the first is unbuilt")
	_assert_equal(_cook_alerts(game).size(), 1, "still exactly one Cook alert: %s" % [game.player_orders.all_alerts])
	_dispose(game)


func _test_queues_card_build() -> void:
	var game := _starving_game(35, true)
	_add_complete(game, VaultBuilding.Kind.GENERATOR)
	game.player_orders.refresh()
	var card := _button(game).text if _card_shown(game) else ""
	var before := game.buildings.size()
	_run_for(game, 2.0)
	var kinds := _new_kinds(game, before)
	_assert_equal(kinds, [VaultBuilding.Kind.KITCHEN] as Array[int], "with power to spare the Cook queues the Station")
	_assert_true(card.contains("Station"), "fixture: the card offered the Station: %s" % card)
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
	_dispose(game)


func _test_hatch_reserve() -> void:
	var cost := int(VaultBuilding.COSTS[VaultBuilding.Kind.GENERATOR])
	var game := _starving_game(cost + BreachSystem.PATCH_COST - 1, false)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.DORMANT, "fixture: hatch dormant, patch owed")
	var before := game.buildings.size()
	_run_for(game, 2.0)
	_assert_equal(_new_kinds(game, before), [] as Array[int], "%d salvage minus the %d patch reserve cannot pay the Charge Node" % [cost + BreachSystem.PATCH_COST - 1, BreachSystem.PATCH_COST])
	_dispose(game)
	game = _starving_game(cost + BreachSystem.PATCH_COST, false)
	before = game.buildings.size()
	_run_for(game, 2.0)
	_assert_equal(_new_kinds(game, before), [VaultBuilding.Kind.GENERATOR] as Array[int], "with the reserve covered the Cook queues it before the seal")
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
		for building: VaultBuilding in game.buildings:
			if building.kind != VaultBuilding.Kind.AIR_RECYCLER and not building.complete and building.get_base_power_demand() > 0:
				building.complete = true
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
	# 1 spare power: a Station (2) would shed a load, so the Cook places a Charge Node.
	game = _starving_game(60, true)
	before = game.buildings.size()
	_run_for(game, 2.0)
	_assert_equal(_new_kinds(game, before), [VaultBuilding.Kind.GENERATOR] as Array[int], "power short: Charge Node, not an unpowered Station")
	_dispose(game)


func _test_tap_overrides() -> void:
	var game := _starving_game(60, true)
	var before := game.buildings.size()
	_run_for(game, 2.0)
	var queued: VaultBuilding = game.buildings[-1] if game.buildings.size() > before else null
	_assert_true(queued != null, "fixture: the Cook queued a blueprint")
	if queued != null:
		var salvage := game.food_system.salvage
		game.active_tool = "cancel"
		_assert_true(game.issue_order(queued.cell), "the player cancels the Cook's blueprint")
		_assert_true(game.food_system.salvage >= salvage, "refunded")
		var count := game.buildings.size()
		_run_for(game, 5.0)
		_assert_equal(game.buildings.size(), count, "the Cook does not re-queue what the player cancelled")
		_assert_equal(_cook_alerts(game).size(), 0, "and its alert is gone: %s" % [game.player_orders.all_alerts])
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
