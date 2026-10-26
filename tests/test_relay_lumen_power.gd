extends "res://tests/test_runner.gd"

# The earned Lumen must add light without competing with the NONE wing's power load.
# Use only existing APIs here so the original production code fails assertions, not parsing.
var _records_path := ""
var _save_path := ""


func _run() -> void:
	_records_path = "user://test_relay_lumen_power_records_%d.json" % OS.get_process_id()
	_save_path = "user://test_relay_lumen_power_save_%d.json" % OS.get_process_id()
	_clean()
	var store := WingRecords.new()
	store.path = _records_path
	store.record(0x0B03, true, 3, 9, 5, true)
	_run_case("03 RELAY LUMEN stays lit for 30 real sim seconds with the same load as NONE", _test_simulation)
	_run_case("the zero demand and active light are re-derived after a disk save/load", _test_zero_demand_load)
	_run_case("FLOODLIGHT keeps its normal demand and shedding behavior", _test_floodlight_power)
	_run_case("a replacement Lumen on the relay cell keeps normal demand across load", _test_replacement)
	_clean()
	print("")
	if _failure_count == 0:
		print("RELAY LUMEN POWER TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
	else:
		printerr("RELAY LUMEN POWER TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
	quit(1 if _failure_count else 0)


func _clean() -> void:
	for path: String in [_records_path, _save_path]:
		for suffix: String in ["", ".tmp", ".bak"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _wing(perk: String) -> VaultGame:
	var game := _spawn_game()
	game.records_path = _records_path
	game.equipped_perk = perk
	game.new_game(false, 4242, 3)
	_assert_equal([game.wing_perk, game.sublevel, game.wing_seed], [perk, 3, 4242], "fixture: requested perk on 03 at seed 4242")
	game.begin_shift()
	return game


# The reported opening: a normal Lumen consumes the core's spare power before a Charge Node
# finishes. Queue real orders and let hauling/construction run through normal simulation ticks.
func _opening_orders(game: VaultGame, tick: int) -> void:
	if tick == 0:
		for cell: Vector2i in [Vector2i(24, 11), Vector2i(25, 11), Vector2i(26, 11), Vector2i(27, 13)]:
			game.map_grid.paint_stockpile(cell)
	if tick == 6:
		_assert_true(game.place_blueprint(VaultBuilding.Kind.LAMP, Vector2i(26, 13)), "queue ordinary Lumen")
		_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(20, 13)), "queue Bunk")
		game.set_tool("dig")
		for x: int in range(22, 28):
			_assert_true(game.issue_order(Vector2i(x, 10)), "queue opening dig")
		game.set_tool("select")
	if tick == 116:
		_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(25, 16)), "queue Charge Node")
		game.set_tool("dig")
		for cell: Vector2i in [Vector2i(25, 9), Vector2i(26, 9), Vector2i(27, 9), Vector2i(26, 8), Vector2i(27, 8), Vector2i(28, 8)]:
			_assert_true(game.issue_order(cell), "queue northern dig")
		game.set_tool("select")


func _load_shape(game: VaultGame) -> Array:
	return [game.power_grid.supply, game.power_grid.demand, game.power_grid.served, game.power_grid.shed_demand]


func _test_simulation() -> void:
	var none := _wing("")
	var game := _wing(VaultGame.PERK_RELAY_LUMEN)
	var lamp := game.get_building_at(VaultGame.RELAY_LUMEN_CELL)
	_assert_true(lamp != null and lamp.complete and lamp.building_id == VaultGame.FLOODLIGHT_BUILDING_ID, "fixture: built perk Lumen")
	if lamp == null:
		_dispose(none)
		_dispose(game)
		return
	var observed := {"allocations": 0, "unpowered": 0, "shed": 0, "brownouts_shedding_lumen": 0}
	game.power_grid.allocation_changed.connect(func() -> void:
		observed.allocations += 1
		if not lamp.powered:
			observed.unpowered += 1
		if game.power_grid.is_building_shed(lamp.building_id):
			observed.shed += 1
	)
	game.power_grid.brownout_started.connect(func(_count: int, _demand: int) -> void:
		if game.power_grid.is_building_shed(lamp.building_id):
			observed.brownouts_shedding_lumen += 1
	)
	_assert_true(lamp.powered, "perk Lumen starts lit")
	_assert_equal(_load_shape(game), _load_shape(none), "initial served/demand matches NONE")
	var mismatched_ticks := 0
	var first_mismatch := ""
	for tick in 300:
		_opening_orders(none, tick)
		_opening_orders(game, tick)
		none.step_simulation(VaultGame.SIMULATION_TICK)
		game.step_simulation(VaultGame.SIMULATION_TICK)
		if _load_shape(game) != _load_shape(none):
			mismatched_ticks += 1
			if first_mismatch.is_empty():
				first_mismatch = "at %.1fs: RELAY %s / NONE %s" % [game.day_cycle.elapsed_seconds, _load_shape(game), _load_shape(none)]
	_assert_approximately(game.day_cycle.elapsed_seconds, 30.0, 0.00001, "300 real ticks advance 30 sim seconds")
	_assert_approximately(none.day_cycle.elapsed_seconds, 30.0, 0.00001, "NONE also advances 30 sim seconds")
	_assert_true(observed.allocations >= 600, "observed both power allocations in every real tick")
	_assert_equal(observed.unpowered, 0, "perk Lumen is never unpowered during any allocation")
	_assert_equal(observed.shed, 0, "perk Lumen is never in shed consumers")
	_assert_equal(observed.brownouts_shedding_lumen, 0, "no brownout event sheds the perk Lumen")
	_assert_equal(mismatched_ticks, 0, "served/demand matches NONE at every tick; first difference " + first_mismatch)
	_assert_true(game.get_building_at(Vector2i(26, 13)).complete, "ordinary Lumen really finished construction")
	_assert_true(game.get_building_at(Vector2i(25, 16)).complete, "Charge Node really finished construction")
	# Also exercise a live brownout with no generator in the allocation: only the ordinary lamp sheds.
	game.power_grid.recalculate([lamp, game.get_building_at(Vector2i(26, 13))])
	_assert_true(game.power_grid.brownout_active and lamp.powered, "perk Lumen stays lit with zero grid supply during brownout")
	_assert_false(game.power_grid.is_building_shed(lamp.building_id), "zero-supply brownout excludes the perk Lumen")
	_assert_equal(observed.brownouts_shedding_lumen, 0, "forced brownout event also excludes it")
	_dispose(none)
	_dispose(game)


func _assert_free_light(game: VaultGame) -> void:
	var lamp := game.get_building_at(VaultGame.RELAY_LUMEN_CELL)
	_assert_equal([lamp.get_base_power_demand(), lamp.get_power_demand()], [0, 0], "perk Lumen draws zero power")
	_assert_true(lamp.powered and not game.power_grid.is_building_shed(lamp.building_id), "perk Lumen is lit and unshed")
	game.select_building(lamp.building_id)
	game.player_orders._refresh_inspector()
	_assert_true(game.player_orders.inspector_state.text.contains("Power: 0 demand / 0 output"), "inspector reports zero demand")
	_assert_true(game.player_orders.inspector_state.text.contains("Light: ACTIVE"), "inspector reports active light")


func _test_zero_demand_load() -> void:
	var game := _wing(VaultGame.PERK_RELAY_LUMEN)
	_assert_free_light(game)
	var lamp := game.get_building_at(VaultGame.RELAY_LUMEN_CELL)
	# Neither derived flag belongs in the save; the serialized powered state is not authoritative.
	_assert_false(lamp.serialize().has("self_powered") or lamp.serialize().has("shed_first"), "perk flags are not serialized")
	lamp.powered = false
	_assert_true(game.save_game(false, _save_path), "save perk wing to disk")
	game.equipped_perk = ""
	game.new_game(false, 4242, 3)
	_assert_true(game.load_game(_save_path), "load over a NONE wing")
	_assert_equal(game.wing_perk, VaultGame.PERK_RELAY_LUMEN, "saved wing perk is restored")
	_assert_free_light(game)
	_assert_equal(_load_shape(game), [2, 1, 1, 0], "loaded grid charges only the starter Lumen")
	var stripped := game.create_snapshot()
	stripped.erase("perk")
	_assert_true(game.apply_snapshot(stripped), "load identical lamp without the wing perk")
	_assert_equal(game.get_building_at(VaultGame.RELAY_LUMEN_CELL).get_power_demand(), 1, "same id and cell without RELAY LUMEN have normal demand")
	_dispose(game)


func _test_floodlight_power() -> void:
	var game := _wing(VaultGame.PERK_FLOODLIGHT)
	var lamp := game.get_building_at(VaultGame.FLOODLIGHT_CELL)
	_assert_equal([lamp.get_base_power_demand(), lamp.get_power_demand()], [1, 1], "FLOODLIGHT still draws one power")
	_assert_true(lamp.shed_first and lamp.powered, "FLOODLIGHT keeps its optional priority and starts powered")
	_assert_equal(_load_shape(game), [2, 2, 2, 0], "FLOODLIGHT uses the core's spare power")
	_assert_true(game.save_game(false, _save_path), "save FLOODLIGHT")
	_assert_true(game.load_game(_save_path), "load FLOODLIGHT")
	lamp = game.get_building_at(VaultGame.FLOODLIGHT_CELL)
	_assert_equal(lamp.get_power_demand(), 1, "FLOODLIGHT still draws one after load")
	_add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(26, 13))
	game.power_grid.recalculate(game.buildings)
	_assert_true(game.power_grid.is_building_shed(lamp.building_id) and not lamp.powered, "FLOODLIGHT still sheds first under load")
	_dispose(game)


func _test_replacement() -> void:
	var game := _wing(VaultGame.PERK_RELAY_LUMEN)
	var lamp := game.get_building_at(VaultGame.RELAY_LUMEN_CELL)
	_assert_true(game.deconstruct_building(lamp.building_id), "deconstruct perk Lumen")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.LAMP, VaultGame.RELAY_LUMEN_CELL), "player places replacement on relay cell")
	lamp = game.get_building_at(VaultGame.RELAY_LUMEN_CELL)
	lamp.add_delivery(lamp.get_cost())
	lamp.apply_build_work(1000.0)
	game._mark_floodlight()
	_assert_true(lamp.complete and lamp.building_id != VaultGame.FLOODLIGHT_BUILDING_ID, "replacement has its own id")
	_assert_equal([lamp.get_base_power_demand(), lamp.get_power_demand(), lamp.shed_first], [1, 1, false], "replacement has normal demand and priority")
	_assert_true(game.save_game(false, _save_path), "save replacement")
	_assert_true(game.load_game(_save_path), "load replacement")
	lamp = game.get_building_at(VaultGame.RELAY_LUMEN_CELL)
	_assert_equal([lamp.get_base_power_demand(), lamp.get_power_demand(), lamp.shed_first], [1, 1, false], "replacement still has normal demand after load")
	_dispose(game)
