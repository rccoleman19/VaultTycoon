extends "res://tests/test_runner.gd"

const RECORDS_PATH := "user://next_urgency_rank_records.json"
const FRAME_SECONDS := 1.0 / 30.0
const FRAME_CAP := 2600
const REC_NEXT := "Next: YOU place a Rec Console · THEY recover mood"
const TOO_LATE_NEXT := "Next: Ari starving · nothing lands in time · keep crew fed where possible"

var _frame := 0
var _breach_seen_frame := -1
var _frame_accumulator := 0.0


func _run() -> void:
	_run_case("03 engaged RELAY LUMEN names Ari's starvation before optional builds", _test_engaged_relay_lumen)
	_run_case("03 no-shed RELAY LUMEN rejects late tray steps and uses timely food", _test_no_shed_relay_lumen)
	_run_case("short food runway names a resident with a real imminent food deadline", _test_food_runway_trigger)
	_run_case("05 idle kitchen crisis names Ari and places the affordable kitchen", _test_idle_kitchen_prefix)
	_run_case("food production blocked by stress breaks keeps a named actionable recovery", _test_food_work_blocker)
	_run_case("projected starvation ranks every living resident, including current health", _test_most_threatened_food)
	_run_case("available raw food with Cook OFF names the starving resident and Cook fix", _test_enable_cook)
	_run_case("cooked meal waiting with Haul OFF names the resident and delivery fix", _test_enable_haul)
	_run_case("one shared ration does not hide the next resident's starvation", _test_shared_ration)
	_run_case("suffocation names the resident and an available air fix; recovering air clears", _test_air_urgency)
	print("NEXT URGENCY RANK TESTS: %s — %d cases, %d assertions, %d failures" % [
		"FAIL" if _failure_count else "PASS", _case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _relay_lumen_game() -> VaultGame:
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
	return game


func _test_engaged_relay_lumen() -> void:
	var game := _relay_lumen_game()

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
		if not checked_healthy and elapsed >= 170.0 - 0.00001:
			checked_healthy = true
			# #115 made the perk Lumen self-powered and unsheddable. Its light
			# now preserves food work, so this replay no longer warns at 170s.
			# The full-belly runway fixture below still checks the early warning.
			_assert_false("starving ·" in game.player_orders.objective_label.text,
				"the no-shed opening still covers the food lead at 170s")
		if not checked_empty_larder and elapsed >= 217.3 - 0.00001:
			checked_empty_larder = true
			_assert_starvation_next(game, 217.3)
		if not checked_critical and elapsed >= 230.0 - 0.00001:
			checked_critical = true
			_assert_starvation_next(game, 230.0)
			_assert_true("CRITICAL: Ari" in "  ·  ".join(game.player_orders.all_alerts),
				"230s replay reaches the reported CRITICAL: Ari state")
			break
	_assert_true(checked_healthy and checked_empty_larder and checked_critical,
		"deterministic driver reaches early-runway, empty-larder and critical checkpoints (frame %d, sim %.1fs)" % [
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
		"repro food source is complete but shed at %.1fs" % expected_seconds)
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.KITCHEN), 1,
		"repro already has a powered Nutrient Station at %.1fs" % expected_seconds)
	_assert_true("Ari" in next and "starving" in next.to_lower(),
		"Next names Ari's starvation ahead of optional builds at %.1fs: %s" % [expected_seconds, next])
	_assert_equal(next, TOO_LATE_NEXT,
		"with no produced food, name the missed rescue deadline at %.1fs" % expected_seconds)
	_assert_false("Grow Tray" in next or "Charge Node" in next,
		"powering the shed tray is too slow for the exhausted runway at %.1fs: %s" % [expected_seconds, next])
	_assert_false("Rec Console" in next or "bunk" in next.to_lower(),
		"optional Rec/bunk advice cannot displace Ari's starvation at %.1fs" % expected_seconds)
	var plan: Dictionary = game.player_orders._food_fix_plan()
	print("URGENCY SNAPSHOT sim=%.1fs frame=%d Next=%s food=%.2f HP=%.2f raw=%d pending_raw=%d pending_meals=%d harvest_lead=%.2f rescue_deadline=%.2f" % [
		game.day_cycle.elapsed_seconds, _frame, next, ari.needs.food if ari != null else -1.0,
		ari.needs.health if ari != null else -1.0, game.food_system.raw_food,
		game.job_system.get_pending_raw_food(), game.job_system.get_pending_meals(),
		float(plan.seconds) + game.player_orders._food_chain_work_lead(float(plan.seconds)),
		float(game.player_orders._food_depletion_times()[ari.resident_id]) + ari.needs.health / (160.0 / DayCycle.SECONDS_PER_DAY)])


func _test_no_shed_relay_lumen() -> void:
	var game := _relay_lumen_game()
	var relay := game.get_building_at(Vector2i(18, 13))
	_assert_true(relay != null and relay.self_powered and relay.get_power_demand() == 0,
		"the real RELAY LUMEN fixture consumes no grid power")
	var checkpoints := 0
	for frame in range(1, FRAME_CAP + 1):
		_frame = frame
		_engaged_actions(game)
		_advance_frame(game)
		var elapsed := game.day_cycle.elapsed_seconds
		if (checkpoints == 0 and elapsed >= 217.3 - 0.00001) or (checkpoints == 1 and elapsed >= 230.0 - 0.00001):
			checkpoints += 1
			_assert_true(relay.powered and not game.power_grid.is_building_shed(relay.building_id),
				"perk Lumen never sheds at %.1fs" % elapsed)
			var next := game.player_orders.objective_label.text
			_assert_equal(next, TOO_LATE_NEXT,
				"no food is in flight and no complete rescue lands in time at %.1fs: %s" % [elapsed, next])
			_assert_false("Grow Tray" in next or "Charge Node" in next or "Lumen" in next or "Rec Console" in next or "bunk" in next.to_lower(),
				"late starvation cannot offer tray restoration or optional builds at %.1fs: %s" % [elapsed, next])
			if checkpoints == 2:
				break
	_assert_equal(checkpoints, 2, "no-shed replay reaches both late checkpoints")

	# A produced meal is faster than waiting for a new crop. Haul OFF must
	# remain actionable, even when the next harvest misses Ari's deadline.
	var ari := game.get_resident_by_id(1)
	ari.needs.food = 0.0
	ari.needs.health = 100.0
	var kitchen := game.get_building_at(Vector2i(21, 17))
	game.food_system.raw_food = FoodSystem.COOK_INPUT
	for resident: VaultResident in game.residents:
		resident.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, "Next: Ari starving · YOU enable Cook · THEY cook",
		"existing raw offers a timely alternative to a late tray")
	_assert_true(game.job_system.finish_cook(kitchen) > 0, "the real recipe produces a haulable meal")
	for resident: VaultResident in game.residents:
		resident.set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, "Next: Ari starving · YOU enable Haul · THEY deliver food",
		"already-cooked output offers a timely delivery instead of tray work")
	# Automatic food is counted in pantry runway, but it is still the fastest
	# rescue when the next crop is too late. Prefer its delivery even with raw
	# also available, rather than prompting another harvest or Cook job.
	for resident: VaultResident in game.residents:
		resident.set_work_priority("cook", VaultResident.DEFAULT_WORK_PRIORITY)
		resident.set_work_priority("haul", VaultResident.DEFAULT_WORK_PRIORITY)
		resident.needs.mood = 100.0
		resident.needs.rest = 100.0
	game.food_system.raw_food = FoodSystem.COOK_INPUT
	var delivery := game.player_orders._food_delivery_seconds(MapGrid.CHAMBER.get_center())
	ari.needs.health = (delivery + 0.5) * (160.0 / DayCycle.SECONDS_PER_DAY)
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, "Next: Ari starving · YOU leave Haul on · THEY deliver food",
		"automatic meal delivery beats both existing raw and the late harvest")
	_assert_true(delivery < ari.needs.health / (160.0 / DayCycle.SECONDS_PER_DAY),
		"the selected meal delivery fits Ari's remaining starvation health")
	ari.needs.health = maxf(0.1, delivery - 0.5) * (160.0 / DayCycle.SECONDS_PER_DAY)
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, TOO_LATE_NEXT,
		"aggregate pending food cannot hide Ari's shorter deadline when even delivery is too late")

	# Only zero-demand lights remain: neither can free power, even with enough
	# spare capacity to satisfy the static fixture demand in the old check.
	for lamp: VaultBuilding in game.buildings:
		if lamp.kind == VaultBuilding.Kind.LAMP:
			lamp.self_powered = true
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(24, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_true(game.get_powered_building_count(VaultBuilding.Kind.LAMP) >= 2,
		"zero-demand guard reaches the power-release check past its last-light rule")
	_assert_true(game.power_grid.supply - game.power_grid.served >= int(VaultBuilding.POWER_DEMAND[VaultBuilding.Kind.GROW_TRAY]),
		"spare capacity reaches the old zero-demand Lumen candidate condition")
	_assert_true(game.player_orders._food_power_release_step(VaultBuilding.Kind.GROW_TRAY).is_empty(),
		"disabling a zero-demand Lumen can never release food power")
	_dispose(game)
	_remove_test_save(RECORDS_PATH)


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


func _test_food_runway_trigger() -> void:
	var game := _healthy_urgency_game()
	game.food_system.meals = 0
	game.food_system.raw_food = 2
	game.residents[0].needs.food = 40.0
	for resident: VaultResident in game.residents:
		resident.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
	# Four living crew drain 60 need/day each, and one meal restores 60 need.
	# These two cookable raw units cover only 20 sim seconds. With no stored
	# ration and 40 food, Ari's own starvation deadline is 51.7 seconds, so the
	# warning names a real imminent threat before her food meter is critical.
	_assert_equal(game.get_alive_count(), 4, "runway fixture has four living consumers")
	_assert_true(game.get_powered_building_count(VaultBuilding.Kind.KITCHEN) == 1,
		"stored raw is genuinely cookable by the existing kitchen")
	game.player_orders.refresh()
	var next := game.player_orders.objective_label.text
	_assert_true("starving ·" in next and "Cook" in next,
		"20-second runway below food lead plus margin fires for a real imminent food deadline: %s" % next)
	game.food_system.meals = 24
	game.player_orders.refresh()
	next = game.player_orders.objective_label.text
	_assert_false("starving ·" in next,
		"260-second runway comfortably above food lead plus margin stays quiet: %s" % next)
	_dispose(game)


func _test_idle_kitchen_prefix() -> void:
	var game := _spawn_game()
	game.new_game(true, 4242, 5)
	game.begin_shift()
	# The idle driver only begins the shift and acknowledges the breach modal.
	# Its real-time delay holds simulation still; acknowledge immediately here
	# and reproduce the same 150-second simulation checkpoint synchronously.
	for _tick in range(1500):
		if game.breach_system.phase == BreachSystem.Phase.WARNING and not game.breach_system.warning_acknowledged:
			game.acknowledge_breach_warning(true)
		game.step_simulation(VaultGame.SIMULATION_TICK)
	game.player_orders.refresh()
	_assert_approximately(game.day_cycle.elapsed_seconds, 150.0, VaultGame.SIMULATION_TICK,
		"idle replay reaches the kitchen-crisis checkpoint")
	_assert_equal(game.get_alive_count(), 4, "every idle resident is still alive before the reported death")
	_assert_equal(game.food_system.meals, 0, "idle replay has exhausted starting meals")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.KITCHEN), 0,
		"idle replay still needs its first Nutrient Station")
	_assert_equal(game.player_orders.objective_label.text,
		"Next: Ari starving · YOU place a Nutrient Station · THEY cook",
		"05 idle kitchen crisis retains Ari's danger prefix and names the affordable kitchen")
	_dispose(game)


func _test_food_work_blocker() -> void:
	var game := _healthy_urgency_game()
	game.food_system.meals = 0
	game.food_system.raw_food = 1
	game.residents[0].needs.food = 0.0
	for resident: VaultResident in game.residents:
		resident.needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD
	var kitchen := game.get_building_at(Vector2i(21, 12))
	_assert_true(kitchen.powered and game.food_system.can_cook(), "stress-break fixture has a powered kitchen and ready ingredients")
	game.player_orders.refresh()
	var expected := "Next: Ari starving · YOU place a Rec Console · THEY recover mood"
	_assert_equal(game.player_orders.objective_label.text, expected, "ready food work blocked by breaks names Ari and the recovery action")
	var step: Dictionary = game.player_orders._primary_next_step()
	_assert_equal(str(step.get("kind", "")), "food", "stress-break recovery remains part of the food chain")
	_assert_equal(str(step.tool), "rec", "stress-break recovery highlights the Rec tool")
	for resident: VaultResident in game.residents:
		resident.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, "Next: Ari starving · YOU enable Cook · THEY cook", "Cook OFF remains the first blocker even while crew risk breaks")
	for resident: VaultResident in game.residents:
		resident.set_work_priority("cook", VaultResident.DEFAULT_WORK_PRIORITY)
		resident.needs.mood = 100.0
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, "Next: Ari starving · YOU leave Cook on · THEY cook", "recovered crew return to cooking the still-stored raw")
	_assert_true(game.job_system.finish_cook(kitchen) > 0, "real recipe moves the available raw into the meal pipeline")
	_assert_true(game.food_system.raw_food == 0 and game.food_system.meals == 0 and game.job_system.get_pending_meals() > 0, "the cooked meal awaits Haul instead of already feeding Ari")
	for resident: VaultResident in game.residents:
		resident.needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, TOO_LATE_NEXT,
		"when recovery plus meal delivery misses the runway, do not promise a late Rec build")
	_dispose(game)

	# A shed source with no raw or output cannot cook or deliver anything yet.
	# Mood recovery must not displace the actual missing-food-source diagnosis.
	game = _healthy_urgency_game()
	game.food_system.meals = 0
	game.food_system.raw_food = 0
	game.residents[0].needs.food = 0.0
	for resident: VaultResident in game.residents:
		resident.needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD
	_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(22, 12))
	_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(23, 12))
	var grow := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(24, 12))
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	_assert_true(game.power_grid.is_building_shed(grow.building_id), "the completed tray is genuinely shed")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.KITCHEN), 1, "the shed-source guard keeps the kitchen powered")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, TOO_LATE_NEXT, "a shed source with no produced food names the missed runway instead of Rec or phantom cooking")
	_dispose(game)


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
	_assert_true("nothing lands in time" in next and "Grow Tray" not in next,
		"no runway cannot promise a late Grow Tray cycle: %s" % next)
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
	_assert_true("Bo" in next and "starving" in next.to_lower() and "nothing lands in time" in next,
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
