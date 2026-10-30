extends "res://tests/test_runner.gd"

const AIR_TIP := "Next: YOU spend 14: build Air Recycler"
const BUNK_TIP := "Next: YOU place bunks · THEY craft"
const CHARGE_TIP := "Next: YOU spend 18: build Charge Node · THEY craft"


func _run() -> void:
	_run_case("single-tray surplus offers the affordable first Air", _test_surplus)
	_run_case("trait-adjusted deficit preserves ordinary Next", _test_deficit)
	_run_case("13 salvage cannot buy Air", _test_short)
	_run_case("existing Air fixture or blueprint prevents duplicate advice", _test_existing_air)
	_run_case("pre-seal keeps existing advice", _test_pre_seal)
	_run_case("Charge comes first to preserve Rec power", _test_power)
	_run_case("resident danger keeps priority", _test_danger)
	_run_case("reclamation and material commitments gate the opportunity", _test_commitments)
	_run_case("multiple trays and Mk II are outside the single-tray plateau", _test_trays)
	_run_case("Keep Running opening bunks preserve the Annex Next", _test_keep_running_opening)
	print("POST-SEAL AIR TIP: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _plateau(power_room := true) -> VaultGame:
	var game := _spawn_game()
	game.new_game(false, 4242, 5)
	game.begin_shift()
	game.user_paused = true
	game.breach_system._enter_sealed(true)
	game.reclaim_active = true
	game.food_system.salvage = 14
	game.food_system.meals = 12
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
		resident.needs.food_drain_scale = 1.0
	# An ordinary tired crew member creates the diagnosis's bunk plateau.
	game.residents[0].needs.rest = 28.0
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(20, 12))
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(21, 12))
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(22, 12))
	_add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(23, 12))
	if power_room:
		_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(24, 12))
	game.power_grid.recalculate(game.buildings)
	return game


func _next(game: VaultGame) -> String:
	game.player_orders.refresh()
	return game.player_orders.objective_label.text


func _test_surplus() -> void:
	var game := _plateau()
	_assert_equal(_next(game), AIR_TIP, "displayed Next gives exact driver-readable Air purchase at 14 salvage")
	_dispose(game)


func _test_deficit() -> void:
	var game := _plateau()
	# Four residents consuming 1.25 meals/day each exceed 40/9 production.
	for resident: VaultResident in game.residents:
		resident.needs.food_drain_scale = 1.25
	_assert_equal(_next(game), BUNK_TIP, "nominal food deficit does not promote Air")
	_dispose(game)


func _test_short() -> void:
	var game := _plateau()
	game.food_system.salvage = 13
	_assert_equal(_next(game), BUNK_TIP, "13 salvage leaves the ordinary bunk step")
	_dispose(game)


func _test_existing_air() -> void:
	for complete: bool in [true, false]:
		var game := _plateau()
		var air := _add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(25, 12))
		air.complete = complete
		game.power_grid.recalculate(game.buildings)
		_assert_equal(_next(game), BUNK_TIP, "Air complete=%s prevents duplicate purchase" % complete)
		_dispose(game)


func _test_pre_seal() -> void:
	var game := _plateau()
	game.breach_system.phase = BreachSystem.Phase.DORMANT
	_assert_equal(_next(game), BUNK_TIP, "pre-seal does not offer Air")
	_dispose(game)


func _test_power() -> void:
	var game := _plateau(false)
	game.food_system.salvage = 18
	_assert_equal([game.power_grid.supply, game.power_grid.demand], [9, 7], "real 05 grid has only two spare power")
	_assert_equal(_next(game), CHARGE_TIP, "affordable Charge purchase precedes Air to preserve Rec")
	game.food_system.salvage = 14
	_assert_equal(_next(game), "Next: YOU place a Charge Node · THEY power the Air Recycler", "unaffordable Charge still names the power prerequisite")
	_dispose(game)


func _test_danger() -> void:
	var game := _plateau()
	game.oxygen_system.oxygen = 10.0
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	var text := _next(game)
	_assert_true(text.begins_with("Next: Ari suffocating · YOU place Air Recycler"), "named resident danger outranks spending: " + text)
	_dispose(game)


func _test_commitments() -> void:
	var game := _plateau()
	game.reclaim_active = false
	_assert_equal(_next(game), BUNK_TIP, "reclamation must be active")
	game.reclaim_active = true
	_assert_true(game.place_blueprint(VaultBuilding.Kind.MEDICAL_BED, Vector2i(25, 12)), "unfunded material claim placed")
	_assert_equal(_next(game), BUNK_TIP, "existing material claim is preserved")
	_dispose(game)


func _test_trays() -> void:
	var game := _plateau()
	var tray := game.get_building_at(Vector2i(21, 12))
	tray.upgrade_tier = VaultBuilding.UPGRADE_TIER_MAX
	_assert_equal(_next(game), BUNK_TIP, "Mk II leaves the single-Mk-I predicate")
	tray.upgrade_tier = VaultBuilding.UPGRADE_TIER_BASE
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(25, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_equal(_next(game), BUNK_TIP, "two trays leave the single-tray predicate")
	_dispose(game)


func _test_keep_running_opening() -> void:
	for power_room: bool in [false, true]:
		var game := _plateau(power_room)
		game.food_system.salvage = 18
		game.residents[0].needs.rest = 100.0
		for building: VaultBuilding in game.buildings.duplicate():
			if building.kind == VaultBuilding.Kind.BED:
				game.deconstruct_building(building.building_id)
		# Reach the opening bunk diagnosis without introducing any pending digs.
		for i in 12:
			var dug := false
			for cell: Vector2i in game.map_grid.get_floor_cells():
				for neighbor: Vector2i in game.map_grid.get_neighbors(cell):
					if neighbor != BreachSystem.HATCH_CELL and game.map_grid.can_queue_dig(neighbor) and game.map_grid.queue_dig(neighbor):
						game.map_grid.apply_dig_work(neighbor, 100.0)
						dug = true
						break
				if dug:
					break
		_add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(26, 12))
		game.power_grid.recalculate(game.buildings)
		game.ended = true
		game.outcome = "win"
		_assert_true(game.start_keep_running(), "enter Keep Running with power_room=%s" % power_room)
		game.user_paused = true
		game.status_message_left = 0.0
		var primary: Dictionary = game.player_orders._primary_next_step()
		_assert_equal(str(primary.text), "Next: YOU place 2 bunks · THEY craft from Craft", "Air/Charge eligibility preserves the opening diagnosis with power_room=%s" % power_room)
		_assert_equal(_next(game), "Next: YOU set the meal reserve · THEY build the Annex", "opening bunks still give way to Annex with power_room=%s" % power_room)
		_dispose(game)
