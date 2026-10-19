extends "res://tests/test_runner.gd"

# Mid-game salvage sink (QA 2026-10-18c #3, slice 1): Grow Tray Mk II after the seal.


func _run() -> void:
	_run_case("the upgrade is locked until the hatch is sealed", _test_locked_until_sealed)
	_run_case("a purchase needs the full price and happens once", _test_price_and_once)
	_run_case("only completed Grow Trays can be fitted", _test_eligibility)
	_run_case("Mk II grows every 6 s, keeps progress and power, and leaves other trays alone", _test_production)
	_run_case("Mk II output still goes through Haul", _test_output_hauled)
	_run_case("the offer sits outside Next and selects a tray; the inspector buys while paused", _test_ui_flow)
	_run_case("a save round-trips the tier; old saves load as Mk I; bad tiers are rejected", _test_save)
	_run_case("refunds are 6 for Mk I and 15 for Mk II; a new wing resets", _test_refund_and_new_wing)
	_run_case("Mk II fixtures wear a glowing salvage-gold trim on the map, derived from the tier", _test_mk2_trim)
	_run_case("a managed wing buys Mk II after the seal, grows more food and still wins", _test_playthrough)

	print("")
	if _failure_count == 0:
		print("MIDGAME UPGRADE TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("MIDGAME UPGRADE TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
			_failed_case_count,
			_case_count,
			_failure_count,
			_assertion_count,
		])
		quit(1)


func _tray_game(salvage := 40) -> Array:
	var game := _spawn_game()
	game.begin_shift()
	var tray := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(22, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(24, 12))
	game.power_grid.recalculate(game.buildings)
	game.food_system.salvage = salvage
	return [game, tray]


func _seal(game: VaultGame) -> void:
	game.breach_system._enter_sealed(true)


func _test_locked_until_sealed() -> void:
	var setup := _tray_game()
	var game: VaultGame = setup[0]
	var tray: VaultBuilding = setup[1]
	_assert_false(game.upgrade_building(tray.building_id), "DORMANT rejects")
	game.breach_system.advance(0.0, 60.0)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.WARNING, "warning phase")
	_assert_false(game.upgrade_building(tray.building_id), "WARNING rejects")
	game.breach_system.advance(0.0, 80.0)
	_assert_true(game.breach_system.is_open(), "open phase")
	_assert_false(game.upgrade_building(tray.building_id), "OPEN rejects")
	_assert_equal(game.food_system.salvage, 40, "no salvage spent while locked")
	_assert_equal(tray.upgrade_tier, 1, "still Mk I")
	_seal(game)
	_assert_true(game.upgrade_building(tray.building_id), "SEALED permits")
	_assert_equal(tray.upgrade_tier, 2, "now Mk II")
	_dispose(game)


func _test_price_and_once() -> void:
	var setup := _tray_game(17)
	var game: VaultGame = setup[0]
	var tray: VaultBuilding = setup[1]
	_seal(game)
	_assert_false(game.upgrade_building(tray.building_id), "17 salvage is not enough")
	_assert_equal(game.food_system.salvage, 17, "no partial debit")
	_assert_equal(tray.upgrade_tier, 1, "no upgrade on a failed purchase")
	game.food_system.salvage = 18
	_assert_true(game.upgrade_building(tray.building_id), "18 salvage buys Mk II")
	_assert_equal(game.food_system.salvage, 0, "exactly 18 debited")
	game.food_system.salvage = 50
	_assert_false(game.upgrade_building(tray.building_id), "a second purchase is rejected")
	_assert_equal(game.food_system.salvage, 50, "no repeat charge")
	game.ended = true
	var other := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(20, 12))
	_assert_false(game.upgrade_building(other.building_id), "an ended wing rejects")
	_assert_equal(other.upgrade_tier, 1, "and nothing is upgraded automatically")
	_dispose(game)


func _test_eligibility() -> void:
	var setup := _tray_game()
	var game: VaultGame = setup[0]
	_seal(game)
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(26, 12))
	_assert_false(game.upgrade_building(kitchen.building_id), "a Nutrient Station cannot be fitted")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GROW_TRAY, Vector2i(27, 12)), "a Grow Tray blueprint is placed")
	var blueprint: VaultBuilding = game.buildings[game.buildings.size() - 1]
	_assert_false(blueprint.complete, "the blueprint is unfinished")
	_assert_false(game.upgrade_building(blueprint.building_id), "an unfinished tray cannot be fitted")
	_assert_false(game.upgrade_building(99999), "a stale id is rejected")
	_assert_equal(game.food_system.salvage, 40 - blueprint.delivered, "no salvage spent on rejections")
	_dispose(game)


func _test_production() -> void:
	var setup := _tray_game()
	var game: VaultGame = setup[0]
	var tray: VaultBuilding = setup[1]
	var plain := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(20, 12))
	game.power_grid.recalculate(game.buildings)
	var power_before := game.power_grid.get_status_text()
	_seal(game)
	tray.production_progress = 4.5
	_assert_true(game.upgrade_building(tray.building_id), "upgrade bought")
	_assert_approximately(tray.production_progress, 3.0, 0.0001, "4.5/9 becomes 3/6")
	_assert_equal(tray.get_base_power_demand(), 3, "Mk II still draws 3 power")
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.power_grid.get_status_text(), power_before, "power grid unchanged")
	_assert_equal(tray.get_display_name(), "Grow Tray Mk II", "display name shows Mk II")
	var counts := {}
	game.food_system.raw_food_produced.connect(func(cell: Vector2i, _amount: int) -> void:
		counts[cell] = int(counts.get(cell, 0)) + 1
	)
	tray.production_progress = 0.0
	plain.production_progress = 0.0
	for _i in 181:
		game.food_system.advance(0.1, game.buildings)
	_assert_equal(int(counts.get(tray.cell, 0)), 3, "Mk II makes 3 raw in 18 s")
	_assert_equal(int(counts.get(plain.cell, 0)), 2, "a Mk I tray still makes 2 raw in 18 s")
	tray.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	var before := int(counts.get(tray.cell, 0))
	for _i in 120:
		game.food_system.advance(0.1, game.buildings)
	_assert_equal(int(counts.get(tray.cell, 0)), before, "a disabled Mk II pauses")
	_dispose(game)


func _test_output_hauled() -> void:
	var setup := _tray_game()
	var game: VaultGame = setup[0]
	var tray: VaultBuilding = setup[1]
	_seal(game)
	_assert_true(game.upgrade_building(tray.building_id), "upgrade bought")
	var raw_before := game.food_system.raw_food
	tray.production_progress = 5.95
	game.food_system.advance(0.1, game.buildings)
	_assert_equal(game.food_system.raw_food, raw_before, "raw is not credited directly to stores")
	_assert_equal(game.job_system.get_pending_raw_food_at(tray.cell), 1, "raw waits for Haul at the tray")
	_dispose(game)


func _test_ui_flow() -> void:
	var setup := _tray_game(10)
	var game: VaultGame = setup[0]
	var tray: VaultBuilding = setup[1]
	var orders := game.player_orders
	orders.refresh()
	_assert_false(orders.upgrade_offer_button.visible, "no offer before the seal")
	var next_before: String = orders.objective_label.text
	_seal(game)
	orders.refresh()
	_assert_true(orders.upgrade_offer_button.visible, "the offer appears after the seal")
	_assert_equal(orders.upgrade_offer_button.text, "Grow Tray Mk II · 18 salvage", "offer text (short, so the rail keeps its width)")
	_assert_false(orders.details_box.visible, "the offer shows with DETAILS collapsed")
	_assert_true(orders.upgrade_offer_button.get_parent() != orders.details_box, "the offer is outside DETAILS")
	_assert_false(orders.objective_label.text.contains("Mk II"), "Next is not used for the offer")
	game.user_paused = true
	orders.upgrade_offer_button.pressed.emit()
	_assert_equal(game.selected_building_id, tray.building_id, "the offer selects the tray")
	orders.refresh()
	_assert_true(orders.fixture_upgrade_row.visible, "the inspector shows the fit row")
	_assert_true(orders.fixture_upgrade_button.disabled, "unaffordable: the button is disabled")
	_assert_equal(orders.fixture_upgrade_button.tooltip_text, "Needs 18 salvage (have 10).", "it says what is missing")
	game.food_system.salvage = 30
	orders.refresh()
	_assert_false(orders.fixture_upgrade_button.disabled, "affordable: the button is enabled")
	_assert_equal(orders.fixture_upgrade_button.text, "FIT MK II · 18 SALVAGE", "button text")
	orders.fixture_upgrade_button.pressed.emit()
	_assert_equal(tray.upgrade_tier, 2, "the inspector button buys Mk II")
	_assert_equal(game.food_system.salvage, 12, "and charges 18")
	_assert_true(game.user_paused, "buying does not resume the shift")
	tray.production_progress = 3.0
	orders.refresh()
	_assert_true(orders.inspector_state.text.contains("Growth: 50%"), "the inspector uses the 6 s interval (%s)" % orders.inspector_state.text)
	_assert_equal(orders.inspector_title.text, "GROW TRAY MK II", "the inspector title shows Mk II")
	_assert_false(orders.fixture_upgrade_row.visible, "no fit row once fitted")
	_assert_false(orders.upgrade_offer_button.visible, "the offer goes away once every tray is fitted")
	_dispose(game)


func _test_save() -> void:
	var setup := _tray_game()
	var game: VaultGame = setup[0]
	var tray: VaultBuilding = setup[1]
	# A savable seal: patch the hatch during WARNING, as a crew would.
	game.day_cycle.deserialize({"elapsed_seconds": 70.0, "current_day": 2, "completed": false})
	game.breach_system.advance(0.0, 70.0)
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	_assert_true(game.breach_system.apply_patch_work(100.0), "the hatch seals")
	game.job_system.rebuild_from_state()
	tray.production_progress = 4.5
	_assert_true(game.upgrade_building(tray.building_id), "upgrade bought")
	var tray_id := tray.building_id
	var snap: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	_assert_true(game.apply_snapshot(snap), "a Mk II save loads")
	var loaded := game.get_building_by_id(tray_id)
	_assert_equal(loaded.upgrade_tier, 2, "tier survives a JSON round trip")
	_assert_approximately(loaded.production_progress, 3.0, 0.0001, "progress survives")
	_assert_equal(game.food_system.salvage, 22, "salvage survives")
	var old := snap.duplicate(true)
	for entry: Dictionary in old["buildings"]:
		entry.erase("upgrade_tier")
	_assert_true(game.apply_snapshot(old), "a save without upgrade_tier loads")
	_assert_equal(game.get_building_by_id(tray_id).upgrade_tier, 1, "and every fixture is Mk I")
	var index := -1
	var other_index := -1
	for i in snap["buildings"].size():
		if int(snap["buildings"][i]["id"]) == tray_id:
			index = i
		elif (
			int(snap["buildings"][i]["kind"]) != VaultBuilding.Kind.GROW_TRAY
			and snap["buildings"][i]["complete"] == true
			and snap["buildings"][i]["is_emergency_core"] != true
			and other_index < 0
		):
			other_index = i
	var live_salvage := game.food_system.salvage
	for bad: Variant in [0, 3, 1.5, "2", true]:
		var tampered := snap.duplicate(true)
		tampered["buildings"][index]["upgrade_tier"] = bad
		_assert_false(game.apply_snapshot(tampered), "upgrade_tier %s rejected" % str(bad))
	var wrong_kind := snap.duplicate(true)
	wrong_kind["buildings"][other_index]["upgrade_tier"] = 2
	_assert_true(other_index >= 0, "the save has a completed non-tray fixture")
	_assert_false(game.apply_snapshot(wrong_kind), "Mk II on a completed non-tray is rejected")
	var unfinished := snap.duplicate(true)
	unfinished["buildings"][index]["complete"] = false
	_assert_false(game.apply_snapshot(unfinished), "Mk II on an unfinished tray is rejected")
	_assert_equal(game.food_system.salvage, live_salvage, "rejections leave the live wing alone")
	var float_tier := snap.duplicate(true)
	float_tier["buildings"][index]["upgrade_tier"] = 2.0
	_assert_true(game.apply_snapshot(float_tier), "a JSON float 2.0 is accepted")
	_assert_equal(game.get_building_by_id(tray_id).upgrade_tier, 2, "and loads as Mk II")
	_dispose(game)


func _test_refund_and_new_wing() -> void:
	var setup := _tray_game()
	var game: VaultGame = setup[0]
	var tray: VaultBuilding = setup[1]
	var plain := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(20, 12))
	_assert_equal(plain.get_deconstruct_refund(), 6, "Mk I refund unchanged at 6")
	_seal(game)
	_assert_true(game.upgrade_building(tray.building_id), "upgrade bought")
	_assert_equal(tray.get_deconstruct_refund(), 15, "Mk II refunds half of 12 + 18")
	var before := game.food_system.salvage
	_assert_true(game.deconstruct_building(tray.building_id), "Mk II deconstructs")
	_assert_equal(game.food_system.salvage, before + 15, "15 salvage recovered")
	game.new_game(false)
	for building: VaultBuilding in game.buildings:
		_assert_equal(building.upgrade_tier, 1, "a new wing starts every fixture at Mk I")
	game.player_orders.refresh()
	_assert_false(game.player_orders.upgrade_offer_button.visible, "and hides the offer")
	_dispose(game)


func _managed_wing(buy: bool) -> Dictionary:
	var game := _spawn_game()
	for cell: Vector2i in [Vector2i(18, 12), Vector2i(19, 12), Vector2i(20, 12), Vector2i(21, 12)]:
		_add_completed_building(game, VaultBuilding.Kind.BED, cell)
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(22, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(25, 12))
	var tray := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(26, 12))
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(27, 12))
	_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(24, 12))
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.begin_shift()
	var produced := {"after_seal": 0}
	game.food_system.raw_food_produced.connect(func(_cell: Vector2i, _amount: int) -> void:
		if game.breach_system.is_sealed():
			produced["after_seal"] = int(produced["after_seal"]) + 1
	)
	var bought_at := -1.0
	while not game.ended and game.day_cycle.elapsed_seconds < DayCycle.SECONDS_PER_DAY * DayCycle.DAYS_TO_SURVIVE + 1.0:
		if game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged:
			game.acknowledge_breach_warning(true)
		if buy and bought_at < 0.0 and game.breach_system.is_sealed():
			game.food_system.salvage = maxi(game.food_system.salvage, VaultBuilding.GROW_MK2_COST)
			game.player_orders.refresh()
			game.player_orders.upgrade_offer_button.pressed.emit()
			game.player_orders.refresh()
			game.player_orders.fixture_upgrade_button.pressed.emit()
			bought_at = game.day_cycle.elapsed_seconds
		game.user_paused = false
		game.step_simulation(0.5)
	return {"game": game, "tray": tray, "after_seal": int(produced["after_seal"]), "bought_at": bought_at}


func _test_playthrough() -> void:
	var control := _managed_wing(false)
	var bought := _managed_wing(true)
	var cg: VaultGame = control["game"]
	var bg: VaultGame = bought["game"]
	_assert_true(cg.ended and cg.outcome == "win", "the control wing wins")
	_assert_true(bg.ended and bg.outcome == "win", "the upgraded wing wins")
	_assert_true(float(bought["bought_at"]) > 0.0 and float(bought["bought_at"]) < 120.0, "Mk II bought soon after the seal (%.1f s)" % float(bought["bought_at"]))
	_assert_equal((bought["tray"] as VaultBuilding).upgrade_tier, 2, "through the real UI path")
	_assert_true(int(bought["after_seal"]) > int(control["after_seal"]), "more raw after the seal with Mk II (%d vs %d)" % [bought["after_seal"], control["after_seal"]])
	_assert_true(bg.food_system.meals + bg.food_system.raw_food > cg.food_system.meals + cg.food_system.raw_food, "more food in stores at the end (%d vs %d)" % [bg.food_system.meals + bg.food_system.raw_food, cg.food_system.meals + cg.food_system.raw_food])
	_dispose(cg)
	_dispose(bg)


# Midgame slice 4: the map shows Mk II without the inspector.
func _trim(view: MapView3D, building: VaultBuilding) -> MeshInstance3D:
	var root: Node3D = view._building_proxies[building.building_id]
	return root.get_node_or_null(MapView3D.MK2_TRIM_NAME) as MeshInstance3D


func _test_mk2_trim() -> void:
	var setup := _tray_game(60)
	var game: VaultGame = setup[0]
	var tray: VaultBuilding = setup[1]
	var view := game.get_node("MapView3D") as MapView3D
	var node := _add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(26, 12))
	var bunk := _add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(18, 12))
	game.power_grid.recalculate(game.buildings)
	view.sync_actors([], game.buildings, false)
	var tray_parts: int = (view._building_proxies[tray.building_id] as Node3D).get_child_count()
	_assert_true(_trim(view, tray) == null and _trim(view, node) == null and _trim(view, bunk) == null, "Mk I fixtures have no trim")
	# A save-valid seal (the same recipe as the wing-orders suite), so the Mk II save loads.
	game.day_cycle.deserialize({"elapsed_seconds": 70.0, "current_day": 2, "completed": false})
	game.breach_system.advance(0.0, 70.0)
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.apply_patch_work(100.0)
	game.job_system.rebuild_from_state()
	_assert_true(game.upgrade_building(tray.building_id), "Grow Mk II bought")
	view.sync_actors([], game.buildings, false)
	var trim := _trim(view, tray)
	_assert_true(trim != null, "a Mk II tray wears the trim")
	_assert_equal((view._building_proxies[tray.building_id] as Node3D).get_child_count(), tray_parts + 1, "the trim is one extra part")
	_assert_true(trim != null and trim.mesh is TorusMesh, "the trim is a ring at the foot")
	var mat := trim.material_override as StandardMaterial3D
	_assert_equal(mat.albedo_color, Color("efc56b"), "salvage-gold trim, the outcome panel's gold")
	_assert_true(tray.powered and mat.emission_enabled, "a working Mk II tray's trim glows")
	_assert_true(is_equal_approx(mat.emission_energy_multiplier, MapView3D.MK2_TRIM_ENERGY), "at the trim energy")
	game.toggle_building_enabled(tray.building_id)
	view.sync_actors([], game.buildings, false)
	_assert_false((_trim(view, tray).material_override as StandardMaterial3D).emission_enabled, "a disabled Mk II stops glowing but keeps its trim")
	game.toggle_building_enabled(tray.building_id)
	node.upgrade_tier = VaultBuilding.UPGRADE_TIER_MAX
	view.sync_actors([], game.buildings, false)
	_assert_true(_trim(view, node) != null and (_trim(view, node).material_override as StandardMaterial3D).emission_enabled, "a Charge Mk II, not a consumer, still glows")
	_assert_true(_trim(view, bunk) == null, "other fixtures stay plain")
	var tray_id := tray.building_id
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	_assert_false(JSON.stringify(snapshot).contains("Trim"), "nothing about the trim is saved")
	node.upgrade_tier = VaultBuilding.UPGRADE_TIER_BASE
	view.sync_actors([], game.buildings, false)
	_assert_true(_trim(view, node) == null, "back at Mk I the trim comes off")
	_assert_true(VaultGame.ORDER_FIT_GROW_MK2 in game.wing_orders_claimed, "fitting the tray claimed its wing order")
	snapshot = JSON.parse_string(JSON.stringify(game.create_snapshot()))
	_assert_true(game.apply_snapshot(snapshot), "the save loads")
	view.sync_actors([], game.buildings, false)
	_assert_true(_trim(view, game.get_building_by_id(tray_id)) != null, "a loaded Mk II tray wears the trim again")
	_dispose(game)
