extends "res://tests/test_runner.gd"

const RECORDS_PATH := "user://next_urgency_rank_records.json"
const FRAME_SECONDS := 1.0 / 30.0
const FRAME_CAP := 2600
const REC_NEXT := "Next: YOU place a Rec Console · THEY recover mood"

var _frame := 0
var _breach_seen_frame := -1
var _frame_accumulator := 0.0


func _run() -> void:
	_run_case("03 engaged RELAY LUMEN names Ari's starvation before optional builds", _test_engaged_relay_lumen)
	_run_case("projected starvation ranks every living resident, including current health", _test_most_threatened_food)
	_run_case("available raw food with Cook OFF names the starving resident and Cook fix", _test_enable_cook)
	_run_case("cooked meal waiting with Haul OFF names the resident and delivery fix", _test_enable_haul)
	_run_case("one shared ration does not hide the next resident's starvation", _test_shared_ration)
	_run_case("suffocation names the resident and an available air fix; recovering air clears", _test_air_urgency)
	print("NEXT URGENCY RANK TESTS: %s — %d cases, %d assertions, %d failures" % [
		"FAIL" if _failure_count else "PASS", _case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _test_engaged_relay_lumen() -> void:
	_remove_test_save(RECORDS_PATH)
	# Earn the perk through the same real WingRecords path as playtest_driver.gd;
	# setting wing_perk directly would skip its free low-priority Lumen fixture.
	var records := WingRecords.new()
	records.path = RECORDS_PATH
	_assert_true(records.record(0x0B01, true, 3, 9, 7, true), "three-star Annex record earns RELAY LUMEN")
	var game := MAIN_SCENE.instantiate() as VaultGame
	game.records_path = RECORDS_PATH
	root.add_child(game)
	game.equipped_perk = VaultGame.PERK_RELAY_LUMEN
	game.new_game(true, 4242, 3)
	_assert_true(VaultGame.PERK_RELAY_LUMEN in game.unlocked_perks(), "RELAY LUMEN is unlocked through records")
	_assert_equal(game.wing_perk, VaultGame.PERK_RELAY_LUMEN, "replay equips the earned perk")
	_assert_equal(game.sublevel, 3, "replay starts on sublevel 03")
	_assert_equal(game.residents.size(), 5, "03 replay starts with five real residents")
	_frame = 0
	_breach_seen_frame = -1
	_frame_accumulator = 0.0

	# Use the playthrough tests' fixed simulation tick, while preserving the real
	# driver's 30-fps action schedule and speed changes. The synchronous run never
	# yields to render frames, so host performance cannot advance the game for us.
	var checked_healthy := false
	var checked_empty_larder := false
	var checked_critical := false
	for frame in range(1, FRAME_CAP + 1):
		_frame = frame
		_engaged_actions(game)
		_advance_frame(game)
		var elapsed := game.day_cycle.elapsed_seconds
		if not checked_healthy and elapsed >= 130.0 - 0.00001:
			checked_healthy = true
			_assert_equal(game.player_orders.objective_label.text, REC_NEXT,
				"healthy replay still offers Rec Console build advice at 130s")
		if not checked_empty_larder and elapsed >= 217.3 - 0.00001:
			checked_empty_larder = true
			_assert_starvation_next(game, 217.3)
		if not checked_critical and elapsed >= 230.0 - 0.00001:
			checked_critical = true
			_assert_starvation_next(game, 230.0)
			_assert_true("CRITICAL: Ari" in game.player_orders.alert_label.text,
				"230s replay reaches the reported CRITICAL: Ari state")
			break
	_assert_true(checked_healthy and checked_empty_larder and checked_critical,
		"deterministic driver reaches healthy, empty-larder and critical checkpoints (frame %d, sim %.1fs)" % [
			_frame, game.day_cycle.elapsed_seconds])

	# Recovery guard: with the same buildings, the sealed hatch, full bellies and
	# stocked meals, the named life threat clears and optional build advice returns.
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.health = 100.0
	game.food_system.meals = 24
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, REC_NEXT,
		"removing imminent death restores the existing Rec Console build advice")
	_dispose(game)
	_remove_test_save(RECORDS_PATH)


func _assert_starvation_next(game: VaultGame, expected_seconds: float) -> void:
	game.player_orders.refresh()
	var next := game.player_orders.objective_label.text
	var ari := game.get_resident_by_id(1)
	_assert_approximately(game.day_cycle.elapsed_seconds, expected_seconds, VaultGame.SIMULATION_TICK,
		"checkpoint is at the reported simulation time")
	_assert_true(ari != null and ari.alive and ari.resident_name == "Ari",
		"the threatened Ari is still alive at %.1fs" % expected_seconds)
	_assert_equal(game.food_system.meals, 0, "reported checkpoint has no meals at %.1fs" % expected_seconds)
	var grow := game.get_building_at(Vector2i(23, 17))
	_assert_true(grow != null and grow.complete and game.power_grid.is_building_shed(grow.building_id),
		"repro food source is complete but shed, so its fix is power at %.1fs" % expected_seconds)
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.KITCHEN), 1,
		"repro already has a powered Nutrient Station at %.1fs" % expected_seconds)
	_assert_true("Ari" in next and "starving" in next.to_lower(),
		"Next names Ari's starvation ahead of optional builds at %.1fs: %s" % [expected_seconds, next])
	_assert_true("YOU place a Charge Node" in next,
		"Next fixes the repro's shed food source with power at %.1fs: %s" % [expected_seconds, next])
	_assert_false("Rec Console" in next or "bunk" in next.to_lower(),
		"optional Rec/bunk advice cannot displace Ari's starvation at %.1fs" % expected_seconds)
	print("URGENCY SNAPSHOT sim=%.1fs frame=%d Next=%s food=%.2f HP=%.2f raw=%d pending_raw=%d pending_meals=%d" % [
		game.day_cycle.elapsed_seconds, _frame, next, ari.needs.food if ari != null else -1.0,
		ari.needs.health if ari != null else -1.0, game.food_system.raw_food,
		game.job_system.get_pending_raw_food(), game.job_system.get_pending_meals()])


func _healthy_urgency_game() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(20, 12))
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(21, 12))
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	return game


func _test_most_threatened_food() -> void:
	var game := _healthy_urgency_game()
	game.food_system.meals = 0
	game.food_system.raw_food = 0
	for resident: VaultResident in game.residents:
		resident.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
	var ari: VaultResident = game.residents[0]
	var bo: VaultResident = game.residents[1]
	# Ari's food is lower, but 90 HP gives her 22.5 starvation seconds. Bo's
	# ten food lasts 6.7 seconds and ten HP buys just another 2.5 seconds.
	ari.needs.food = 0.0
	ari.needs.health = 90.0
	bo.needs.food = 10.0
	bo.needs.health = 10.0
	game.player_orders.refresh()
	var next := game.player_orders.objective_label.text
	_assert_true("Bo" in next and "starving" in next.to_lower() and "Ari" not in next,
		"shortest projected life beats the lowest food meter: %s" % next)
	_assert_true("Grow Tray" in next, "no raw-food source asks for a Grow Tray: %s" % next)
	# A dead resident can have the lowest need/HP values without taking Next.
	ari.alive = false
	ari.needs.health = 0.0
	game.player_orders.refresh()
	next = game.player_orders.objective_label.text
	_assert_true("Bo" in next and "Ari" not in next, "dead Ari cannot displace the living Bo: %s" % next)
	_dispose(game)


func _test_air_urgency() -> void:
	var game := _healthy_urgency_game()
	var bo: VaultResident = game.residents[1]
	bo.needs.health = 20.0
	game.residents[0].needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD
	game.oxygen_system.oxygen = 10.0
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.player_orders.refresh()
	var next := game.player_orders.objective_label.text
	_assert_true("Bo" in next and "suffocating" in next.to_lower(),
		"air threat names the living resident with least time: %s" % next)
	_assert_true("place Air Recycler" in next,
		"missing air supply asks to place an Air Recycler: %s" % next)
	var recycler := _add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(22, 12))
	recycler.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.player_orders.refresh()
	next = game.player_orders.objective_label.text
	_assert_true("Bo" in next and "enable an Air Recycler" in next,
		"existing disabled recycler asks to enable it: %s" % next)
	_assert_true(game.toggle_building_enabled(recycler.building_id), "real enable powers the existing recycler")
	game.oxygen_system.oxygen = 14.0
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	_assert_true(game.oxygen_system.net_rate > 0.0, "enabled recycler is genuinely recovering air")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, REC_NEXT,
		"rising air crosses safety before Bo can die, so Rec build advice returns")
	_dispose(game)


func _test_enable_cook() -> void:
	var game := _healthy_urgency_game()
	game.food_system.meals = 0
	game.residents[0].needs.food = 0.0
	for resident: VaultResident in game.residents:
		resident.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
	_assert_true(game.food_system.can_cook(), "raw food is already available for cooking")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.KITCHEN), 1, "existing Nutrient Station is powered")
	game.player_orders.refresh()
	var next := game.player_orders.objective_label.text
	_assert_true("Ari" in next and "starving" in next.to_lower() and "YOU enable Cook" in next,
		"available ingredients and Cook OFF ask to enable Cook for Ari: %s" % next)
	_dispose(game)


func _test_enable_haul() -> void:
	var game := _healthy_urgency_game()
	game.food_system.meals = 0
	game.residents[0].needs.food = 0.0
	for resident: VaultResident in game.residents:
		resident.set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
	# Complete the real recipe; the cooked meal remains outside stock until Haul.
	var kitchen := game.get_building_at(Vector2i(21, 12))
	_assert_true(game.job_system.finish_cook(kitchen) > 0, "real cooking produces a meal awaiting delivery")
	_assert_true(game.job_system.get_pending_meals() > 0, "cooked meal is genuinely pending Haul")
	_assert_equal(game.food_system.meals, 0, "pending meal is not yet edible from stock")
	game.player_orders.refresh()
	var next := game.player_orders.objective_label.text
	_assert_true("Ari" in next and "starving" in next.to_lower() and "YOU enable Haul" in next,
		"pending cooked meal and Haul OFF ask to deliver food for Ari: %s" % next)
	_dispose(game)


func _test_shared_ration() -> void:
	var game := _healthy_urgency_game()
	game.food_system.meals = 1
	game.food_system.raw_food = 0
	var ari: VaultResident = game.residents[0]
	var bo: VaultResident = game.residents[1]
	ari.needs.food = 0.0
	bo.needs.food = 0.0
	# Equal hunger: the real scheduler visits Ari first, so only Ari gets the
	# single ration. Bo still has just 25 seconds of health without food.
	game.player_orders.refresh()
	var next := game.player_orders.objective_label.text
	_assert_true("Bo" in next and "starving" in next.to_lower() and "Grow Tray" in next,
		"one shared meal reserves Ari's runway without hiding unfed Bo: %s" % next)
	game.step_simulation(VaultGame.SIMULATION_TICK)
	_assert_equal(game.food_system.meals, 0, "one real simulation tick consumes the single ration")
	_assert_true(ari.needs.food > 35.0 and bo.needs.food == 0.0,
		"the real scheduler feeds Ari first and leaves Bo hungry")
	game.player_orders.refresh()
	next = game.player_orders.objective_label.text
	_assert_true("Bo" in next and "starving" in next.to_lower(),
		"the named forecast agrees with the actual ration consumer: %s" % next)
	_dispose(game)


func _advance_frame(game: VaultGame) -> void:
	if not game.is_simulation_paused():
		_frame_accumulator += FRAME_SECONDS * float(game.simulation_speed)
		while _frame_accumulator >= VaultGame.SIMULATION_TICK:
			game.step_simulation(VaultGame.SIMULATION_TICK)
			_frame_accumulator -= VaultGame.SIMULATION_TICK
			if game.is_simulation_paused():
				_frame_accumulator = 0.0
				break
	game.player_orders.refresh()


func _digs(game: VaultGame, cells: Array) -> void:
	game.set_tool("dig")
	for cell: Vector2i in cells:
		_assert_true(game.issue_order(cell), "engaged frame %d marks rock at %s" % [_frame, cell])
	game.set_tool("select")


func _engaged_actions(game: VaultGame) -> void:
	# Keep these action frames and cells aligned with the supplied engaged driver.
	if _frame == 25:
		game.begin_shift()
		game.set_speed(2)
		for cell: Vector2i in [Vector2i(24, 11), Vector2i(25, 11), Vector2i(26, 11), Vector2i(27, 13)]:
			game.map_grid.paint_stockpile(cell)
	if _frame == 35:
		_assert_true(game.place_blueprint(VaultBuilding.Kind.LAMP, Vector2i(26, 13)), "engaged frame 35 places Lumen")
		_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(20, 13)), "engaged frame 35 places bunk")
		_digs(game, [Vector2i(22, 10), Vector2i(23, 10), Vector2i(24, 10), Vector2i(25, 10), Vector2i(26, 10), Vector2i(27, 10)])
	if _frame == 90:
		game.select_resident(1)
	if _frame == 200:
		game.set_speed(3)
		_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(25, 16)), "engaged frame 200 places Charge Node")
		_digs(game, [Vector2i(25, 9), Vector2i(26, 9), Vector2i(27, 9), Vector2i(26, 8), Vector2i(27, 8), Vector2i(28, 8)])
	if _frame == 380:
		_assert_true(game.place_blueprint(VaultBuilding.Kind.KITCHEN, Vector2i(21, 17)), "engaged frame 380 places Nutrient Station")
		_digs(game, [Vector2i(29, 12), Vector2i(29, 13), Vector2i(29, 14), Vector2i(29, 15)])
		game.select_resident(2)
	if _frame == 520:
		_assert_true(game.place_blueprint(VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 17)), "engaged frame 520 places Grow Tray")
		_digs(game, [Vector2i(30, 12), Vector2i(30, 13), Vector2i(30, 14), Vector2i(30, 15)])
		game.select_resident(3)
	if _frame == 1000:
		_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(20, 15)), "engaged frame 1000 places second bunk")
		game.select_resident(4)
	if _frame == 1400:
		_assert_true(game.place_blueprint(VaultBuilding.Kind.AIR_RECYCLER, Vector2i(19, 16)), "engaged frame 1400 places Air Recycler")
	if game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged:
		if _breach_seen_frame < 0:
			_breach_seen_frame = _frame
		elif _frame == _breach_seen_frame + 75:
			game.player_orders.breach_resume_button.pressed.emit()
			game.set_speed(3 if _frame > 200 else 2)
