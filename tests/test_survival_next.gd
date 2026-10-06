extends "res://tests/test_runner.gd"

const FINISH_AIR := "Next: YOU leave Haul + Craft on · THEY finish the Air Recycler"
const FINISH_AIR_HELP := "Keep Haul + Craft above OFF so crew supply and finish the Air Recycler blueprint."
const ENABLE_AIR := "Next: YOU enable an Air Recycler · THEY recycle air"
const ENABLE_AIR_HELP := "Select a completed Air Recycler and click ENABLE so it can recycle air."
const PLACE_AIR := "Next: YOU place Air Recycler · THEY craft it"
const PLACE_AIR_HELP := "Designate AIR $14 and keep it powered (3). Craft auto-builds the blueprint."
const DIG_NEXT := "Next: YOU mark rock [E] · THEY dig on Dig defaults"
const KITCHEN_NEXT := "Next: YOU place a Nutrient Station · THEY cook"
const FINISH_NUTRIENT_NEXT := "Next: YOU leave Haul + Craft on · THEY finish the Nutrient Station"
const FINISH_NUTRIENT_HELP := "Keep Haul + Craft above OFF so crew supply and finish the Nutrient Station blueprint."
const POWER_NEXT := "Next: YOU power the Nutrient Station · THEY cook"
const FINISH_CHARGE_NEXT := "Next: YOU leave Haul + Craft on · THEY finish the Charge Node"
const FINISH_CHARGE_HELP := "Keep Haul + Craft above OFF so crew supply and finish the Charge Node blueprint."
const CHARGE_NEXT := "Next: YOU place a Charge Node · THEY power the kitchen"
const CHARGE_HELP := "The grid lacks available power for the Nutrient Station. Place a Charge Node to add 7 power."
const REC_NEXT := "Next: YOU place a Rec Console · THEY recover mood"
const FINISH_REC_NEXT := "Next: YOU leave Haul + Craft on · THEY finish the Rec Console"
const FINISH_REC_HELP := "Keep Haul + Craft above OFF so crew supply and finish the Rec Console blueprint."
const ENABLE_REC_NEXT := "Next: YOU enable a Rec Console · THEY recover mood"
const ENABLE_REC_HELP := "Select a completed Rec Console and click ENABLE so crew can recover mood."
const REC_CHARGE_NEXT := "Next: YOU place a Charge Node · THEY power the Rec Console"
const REC_CHARGE_HELP := "The grid lacks available power for the Rec Console. Place a Charge Node to add 7 power."
const MED_NEXT := "Next: YOU place a Med Bed · THEY treat"
const ENABLE_MED_NEXT := "Next: YOU enable a Med Bed · THEY treat"
const ENABLE_MED_HELP := "Select a completed Med Bed and click ENABLE so the injured can be treated."
const FINISH_MED_NEXT := "Next: YOU leave Haul + Craft on · THEY finish the Med Bed"
const FINISH_MED_HELP := "Keep Haul + Craft above OFF so crew supply and finish the Med Bed blueprint."
const BUNK_NEXT := "Next: YOU place bunks · THEY craft"
const FINISH_BUNK_NEXT := "Next: YOU leave Haul + Craft on · THEY finish the bunks"
const FINISH_BUNK_HELP := "Keep Haul + Craft above OFF so crew supply and finish the bunk blueprints."
const PLACE_ONE_BUNKS_NEXT := "Next: YOU place 1 bunk · THEY craft from Craft"
const PLACE_TWO_BUNKS_NEXT := "Next: YOU place 2 bunks · THEY craft from Craft"
const PLACE_TWO_BUNKS_HELP := "Place BUNK blueprints on carved floor. Undrafted Craft priority finishes them."
const PROGRESSION_CHARGE_NEXT := "Next: YOU place a Charge Node · THEY supply/build"
const PROGRESSION_CHARGE_HELP := "Designate CHARGE. Haul + Craft auto-claim the blueprint. Adds +7 power."
const ENABLE_COOK_NEXT := "Next: YOU enable Cook · THEY cook"
const ENABLE_COOK_HELP := "Enable Cook on a living, undrafted resident so the powered Nutrient Station can run."
const COOK_NEXT := "Next: YOU leave Cook on · THEY cook"
const COOK_HELP := "Meals are short. The powered Nutrient Station can cook."
const WAITING_COOK_HELP := "Meals are short. Leave Cook on. The powered Nutrient Station is waiting on raw food."
const ENABLE_HAUL_NEXT := "Next: YOU enable Haul · THEY deliver food"
const ENABLE_HAUL_HELP := "Open PRIORITIES [P] and enable Haul on a living, undrafted resident. Food is waiting for delivery."
const GROW_NEXT := "Next: YOU place a Grow Tray · THEY grow"
const GROW_HELP := "Place a Grow Tray and keep it powered. Its raw food output needs Haul delivery before Cook can use it."
const FINISH_GROW_NEXT := "Next: YOU leave Haul + Craft on · THEY finish the Grow Tray"
const FINISH_GROW_HELP := "Keep Haul + Craft above OFF so crew supply and finish the Grow Tray blueprint."
const ENABLE_GROW_NEXT := "Next: YOU enable a Grow Tray · THEY grow"
const ENABLE_GROW_HELP := "Enable a completed Grow Tray so it can grow raw food. Haul delivers its output for Cook."
const GROW_CHARGE_NEXT := "Next: YOU place a Charge Node · THEY power the Grow Tray"
const FOOD_CHARGE_NEXT := "Next: YOU place a Charge Node · THEY add power"
const FOOD_CHARGE_HELP := "The grid lacks power for the food chain. Place a Charge Node to add 7 power."
const FOOD_POWER_NEXT := "Next: YOU power food chain · THEY cook/haul alone"
const FOOD_POWER_HELP := "Enable Grow + Nutrient power. Keep Cook/Haul above OFF so defaults keep working."
const GROW_CHARGE_HELP := "The grid lacks available power for the Grow Tray. Place a Charge Node to add 7 power."


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_interrupts_and_priority()
	_test_kitchen_guards()
	_test_charge_finish_restore()
	_test_charge_finish_priority()
	_test_enabled_kitchen_shed()
	_test_disabled_kitchens()
	_test_mixed_kitchen_power()
	_test_unfinished_kitchens()
	_test_nutrient_finish_restore()
	_test_progression_nutrient_finish()
	_test_progression_grow_finish()
	_test_progression_grow_finish_precedence()
	_test_progression_food_capacity_restore()
	_test_progression_food_capacity_guards()
	_test_powered_kitchen()
	_test_cook_ready()
	_test_drafted_cooks()
	_test_disabled_cooks()
	_test_cook_waiting_for_raw_food()
	_test_grow_tray_supply_diagnosis()
	_test_pending_food_suppresses_grow()
	_test_in_transit_raw_suppresses_grow()
	_test_grow_crisis_guards()
	_test_interrupts_before_cook()
	_test_pending_meals_need_haul()
	_test_pending_raw_food_need_haul()
	_test_pending_raw_food_with_stock()
	_test_ineligible_haulers()
	_test_interrupts_before_haul()
	_test_no_pending_food_with_haul_off()
	_test_existing_charge_node_insufficient()
	_test_rec_finish_restore()
	_test_rec_finish_guards()
	_test_rec_enable_restore()
	_test_rec_charge_restore()
	_test_rec_guards()
	_test_kitchen_before_offline_rec()
	_test_offline_rec_priority()
	_test_medical_availability()
	_test_medical_finish_restore()
	_test_medical_enable_restore()
	_test_medical_mixed_fallbacks()
	_test_medical_admitted_patient_spare()
	_test_medical_guards()
	_test_medical_priority()
	_test_medical_brownout()
	_test_bunk_shortage()
	_test_bunk_tired_sleeper_satisfied()
	_test_bunk_tired_sleeper_free_capacity()
	_test_bunk_medical_rester_satisfied()
	_test_bunk_medical_rester_free_capacity_and_release()
	_test_bunk_medical_rester_progression()
	_test_bunk_medical_injury_guard()
	_test_bunk_finish_restore()
	_test_bunk_finish_deficit()
	_test_bunk_finish_occupied()
	_test_bunk_finish_guards()
	_test_bunk_finish_priority()
	_test_bunk_finish_before_food_work()
	_test_progression_bunk_deficit()
	_test_progression_bunk_finish_restore()
	_test_progression_bunk_dig_priority()
	_test_progression_bunk_crisis_priority()
	_test_progression_bunk_after_food_work()
	_test_air_finish_restore()
	_test_air_mixtures()
	_test_air_priority()
	_test_living_residents_only()
	print("Survival next tests: %d assertions, %d failures" % [_assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _healthy_game() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
		resident.drafted = false
		resident.sleeping = false
		resident.bed_id = -1
		resident.medical_bed_id = -1
	return game


func _progression_bunk_game() -> VaultGame:
	var game := _healthy_game()
	game.food_system.meals = game.get_alive_count()
	for x in range(17, 29):
		var cell := Vector2i(x, 10)
		_assert_true(game.map_grid.queue_dig(cell), "progression fixture queues connected rock")
		_assert_true(game.map_grid.apply_dig_work(cell, 8.0), "progression fixture carves floor")
	_assert_equal(game.map_grid.get_floor_cells().size(), 132, "progression fixture clears the floor gate")
	return game


func _assert_step(game: VaultGame, text: String, tool: String, help: String) -> void:
	var step: Dictionary = game.player_orders._primary_next_step()
	_assert_equal(step["text"], text, "recommendation text")
	_assert_equal(step["tool"], tool, "recommendation highlights the expected tool")
	_assert_equal(step["help"], help, "recommendation help")


func _assert_dig(game: VaultGame, message: String) -> void:
	_assert_equal(game.player_orders._primary_next_step()["text"], DIG_NEXT, message)


func _test_interrupts_and_priority() -> void:
	var game := _healthy_game()
	_assert_dig(game, "healthy day-one crew still get the dig hint, including in darkness")
	var resident: VaultResident = game.residents[0]
	resident.needs.food = 19.0
	game.food_system.meals = 0
	_assert_step(game, KITCHEN_NEXT, "kitchen", "Place and power a Nutrient Station so Cook can turn raw food into meals.")
	resident.needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD
	_assert_equal(game.player_orders._primary_next_step()["text"], KITCHEN_NEXT, "missing kitchen beats missing recreation")
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	kitchen.manually_disabled = true
	_assert_step(game, POWER_NEXT, "select", "Power the Nutrient Station so Cook can run.")
	_assert_equal(game.player_orders._primary_next_step()["text"], POWER_NEXT, "kitchen power beats recreation")
	resident.needs.food = 100.0
	game.food_system.meals = 12
	_assert_step(game, REC_NEXT, "rec", "Place a Rec Console so crew can recover mood.")
	resident.needs.health = 99.0
	_assert_equal(game.player_orders._primary_next_step()["text"], REC_NEXT, "recreation beats medical care")
	resident.needs.mood = 100.0
	_assert_step(game, MED_NEXT, "medical", "Place a Med Bed so the injured can be treated.")
	resident.needs.rest = 28.0
	_assert_equal(game.player_orders._primary_next_step()["text"], MED_NEXT, "medical care beats bunks")
	resident.needs.health = 100.0
	_assert_step(game, BUNK_NEXT, "bed", "Place bunks so tired undrafted crew have a bed.")
	# Refresh the highest-priority recommendation without changing the player's tool.
	resident.needs.food = 19.0
	game.food_system.meals = 0
	game.active_tool = "dig"
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "refresh preserves the active dig tool during a crisis")
	_assert_equal(game.player_orders.objective_label.text, POWER_NEXT, "refresh displays the crisis recommendation")
	_dispose(game)


func _test_kitchen_guards() -> void:
	var game := _healthy_game()
	var resident: VaultResident = game.residents[0]
	game.food_system.meals = 0
	_assert_dig(game, "low meals alone do not interrupt digging")
	resident.needs.food = 20.0
	resident.needs.rest = 15.0
	resident.drafted = true
	_assert_dig(game, "critical food and rest thresholds are strict")
	resident.needs.rest = 14.0
	_assert_equal(game.player_orders._primary_next_step()["text"], KITCHEN_NEXT, "critical rest also triggers kitchen placement")
	game.food_system.meals = game.get_alive_count()
	_assert_dig(game, "meals equal to living count do not trigger a kitchen interrupt")
	game.food_system.meals = 0
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	var spare := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(21, 12))
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.LAMP:
			building.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	_assert_true(kitchen.powered, "starter grid powers one kitchen with Lumen disabled")
	_assert_true(not spare.powered, "starter grid sheds the spare kitchen")
	_assert_true(game.player_orders._primary_next_step()["text"] != POWER_NEXT, "offline spare does not interrupt a powered kitchen")
	_assert_true(game.player_orders._primary_next_step()["text"] != CHARGE_NEXT, "powered kitchen skips Charge Node power line")
	_assert_step(game, COOK_NEXT, "select", COOK_HELP)
	_dispose(game)


func _critical_game() -> VaultGame:
	var game := _healthy_game()
	game.residents[0].needs.food = 19.0
	game.food_system.meals = 0
	return game


func _test_enabled_kitchen_shed() -> void:
	var game := _critical_game()
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.power_grid.supply, 2, "Emergency Core supplies two power")
	_assert_equal(game.power_grid.served, 1, "starting Lumen consumes one power")
	_assert_true(game.power_grid.is_building_shed(kitchen.building_id), "enabled kitchen is shed by starter grid")
	_assert_step(game, CHARGE_NEXT, "generator", CHARGE_HELP)
	_dispose(game)


func _test_disabled_kitchens() -> void:
	var game := _critical_game()
	var first := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	var second := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(21, 12))
	first.manually_disabled = true
	second.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, POWER_NEXT, "select", "Power the Nutrient Station so Cook can run.")
	first.manually_disabled = false
	game.power_grid.recalculate(game.buildings)
	_assert_true(game.power_grid.is_building_shed(first.building_id), "reenabled kitchen is shed")
	_assert_step(game, CHARGE_NEXT, "generator", CHARGE_HELP)
	_dispose(game)


func _test_mixed_kitchen_power() -> void:
	var game := _critical_game()
	var disabled := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	var enabled := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(21, 12))
	disabled.manually_disabled = true
	var starting_lumen: VaultBuilding
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.LAMP:
			starting_lumen = building
			starting_lumen.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	_assert_true(enabled.powered, "starter grid powers enabled kitchen with Lumen disabled")
	_assert_true(not disabled.powered, "disabled spare stays unpowered")
	_assert_true(game.player_orders._primary_next_step()["text"] != POWER_NEXT, "powered kitchen skips Select power line")
	_assert_true(game.player_orders._primary_next_step()["text"] != CHARGE_NEXT, "powered kitchen skips Charge Node power line")
	_assert_step(game, COOK_NEXT, "select", COOK_HELP)
	starting_lumen.manually_disabled = false
	game.power_grid.recalculate(game.buildings)
	_assert_true(game.power_grid.is_building_shed(enabled.building_id), "Lumen demand sheds enabled kitchen beside disabled spare")
	_assert_step(game, CHARGE_NEXT, "generator", CHARGE_HELP)
	_dispose(game)


func _test_unfinished_kitchens() -> void:
	var game := _critical_game()
	var completed := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	completed.manually_disabled = true
	_assert_true(game.place_blueprint(VaultBuilding.Kind.KITCHEN, Vector2i(21, 12)), "mixed kitchen case places unfinished blueprint")
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, POWER_NEXT, "select", "Power the Nutrient Station so Cook can run.")
	completed.manually_disabled = false
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, CHARGE_NEXT, "generator", CHARGE_HELP)
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(22, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, COOK_NEXT, "select", COOK_HELP)
	for resident in game.residents:
		resident.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
	_assert_step(game, ENABLE_COOK_NEXT, "select", ENABLE_COOK_HELP)
	completed.complete = false
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.KITCHEN), 0, "unfinished kitchens do not count as completed")
	_assert_step(game, FINISH_NUTRIENT_NEXT, "select", FINISH_NUTRIENT_HELP)
	_dispose(game)


func _test_nutrient_finish_restore() -> void:
	var game := _critical_game()
	_assert_step(game, KITCHEN_NEXT, "kitchen", "Place and power a Nutrient Station so Cook can turn raw food into meals.")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.KITCHEN, Vector2i(20, 12)), "Kitchen blueprint can be placed")
	var kitchen := game.get_building_at(Vector2i(20, 12))
	_assert_false(kitchen.complete, "Kitchen blueprint starts unfinished")
	_assert_equal(kitchen.delivered, 0, "Kitchen blueprint starts unsupplied")
	_assert_step(game, FINISH_NUTRIENT_NEXT, "select", FINISH_NUTRIENT_HELP)
	game.active_tool = "dig"
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "Nutrient finish refresh preserves active dig tool")
	_assert_equal(game.player_orders.objective_label.text, FINISH_NUTRIENT_NEXT, "refresh displays Nutrient finish")
	game.residents[0].needs.mood = 9.0
	_assert_true(game.place_blueprint(VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(21, 12)), "Nutrient finish priority case has unfinished Rec")
	_assert_step(game, FINISH_NUTRIENT_NEXT, "select", FINISH_NUTRIENT_HELP)
	game.residents[0].needs.mood = 100.0
	_assert_equal(kitchen.add_delivery(kitchen.get_cost()), kitchen.get_cost(), "Kitchen blueprint receives salvage cost")
	_assert_true(kitchen.is_supplied(), "Kitchen blueprint fully supplied")
	_assert_false(kitchen.complete, "supplied Kitchen still needs construction")
	_assert_step(game, FINISH_NUTRIENT_NEXT, "select", FINISH_NUTRIENT_HELP)
	game.active_tool = "cancel"
	_assert_true(game.issue_order(Vector2i(20, 12)), "cancel removes unfinished Kitchen blueprint")
	_assert_equal(game.get_building_at(Vector2i(20, 12)), null, "canceled Kitchen leaves no blueprint")
	_assert_step(game, KITCHEN_NEXT, "kitchen", "Place and power a Nutrient Station so Cook can turn raw food into meals.")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.KITCHEN, Vector2i(20, 12)), "Kitchen replaced after cancellation")
	kitchen = game.get_building_at(Vector2i(20, 12))
	_assert_equal(kitchen.add_delivery(kitchen.get_cost()), kitchen.get_cost(), "replacement Kitchen receives salvage")
	_assert_true(kitchen.apply_build_work(kitchen.get_build_time()), "ordinary work completes Kitchen")
	kitchen.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, POWER_NEXT, "select", "Power the Nutrient Station so Cook can run.")
	kitchen.manually_disabled = false
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, CHARGE_NEXT, "generator", CHARGE_HELP)
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(22, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, COOK_NEXT, "select", COOK_HELP)
	for resident in game.residents:
		resident.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
	_assert_step(game, ENABLE_COOK_NEXT, "select", ENABLE_COOK_HELP)
	_dispose(game)


func _test_progression_nutrient_finish() -> void:
	var game := _progression_bunk_game()
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(20, 12))
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(21, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(22, 12))
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12))
	game.power_grid.recalculate(game.buildings)
	var place_next := "Next: YOU place Nutrient Station · THEY cook/haul"
	var place_help := "Designate NUTRI, power it, leave Cook + Haul above OFF."
	_assert_step(game, place_next, "kitchen", place_help)
	_assert_true(game.place_blueprint(VaultBuilding.Kind.KITCHEN, Vector2i(24, 12)), "progression Kitchen blueprint placed")
	var kitchen := game.get_building_at(Vector2i(24, 12))
	_assert_step(game, FINISH_NUTRIENT_NEXT, "select", FINISH_NUTRIENT_HELP)
	_assert_equal(kitchen.add_delivery(kitchen.get_cost()), kitchen.get_cost(), "progression Kitchen supplied")
	_assert_step(game, FINISH_NUTRIENT_NEXT, "select", FINISH_NUTRIENT_HELP)
	game.active_tool = "cancel"
	_assert_true(game.issue_order(Vector2i(24, 12)), "progression Kitchen canceled")
	_assert_step(game, place_next, "kitchen", place_help)
	var completed := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(24, 12))
	completed.manually_disabled = true
	_assert_true(game.place_blueprint(VaultBuilding.Kind.KITCHEN, Vector2i(25, 12)), "progression completed Kitchen has unfinished spare")
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, "Next: YOU power food chain · THEY cook/haul alone", "select", "Enable Grow + Nutrient power. Keep Cook/Haul above OFF so defaults keep working.")
	completed.manually_disabled = false
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, "Next: YOU place Air Recycler · THEY craft it", "air", "Designate AIR $14 and keep it powered (3). Craft auto-builds the blueprint.")
	_dispose(game)


func _test_progression_grow_finish() -> void:
	var game := _progression_bunk_game()
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(20, 12))
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(21, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(22, 12))
	game.power_grid.recalculate(game.buildings)
	var place_next := "Next: YOU place Grow Tray · THEY haul output"
	var place_help := "Designate GROW and keep it powered. Haul defaults move raw food to stock."
	_assert_step(game, place_next, "grow", place_help)
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12)), "progression Grow blueprint placed")
	var tray := game.get_building_at(Vector2i(23, 12))
	_assert_false(tray.complete, "progression Grow starts unfinished")
	_assert_equal(tray.delivered, 0, "progression Grow starts unsupplied")
	_assert_step(game, FINISH_GROW_NEXT, "select", FINISH_GROW_HELP)
	game.active_tool = "dig"
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "progression Grow finish refresh preserves active dig tool")
	_assert_equal(game.player_orders.objective_label.text, FINISH_GROW_NEXT, "refresh displays progression Grow finish")
	_assert_equal(tray.add_delivery(tray.get_cost()), tray.get_cost(), "progression Grow supplied")
	_assert_true(tray.is_supplied() and not tray.complete, "supplied progression Grow still needs construction")
	_assert_step(game, FINISH_GROW_NEXT, "select", FINISH_GROW_HELP)
	game.active_tool = "cancel"
	_assert_true(game.issue_order(tray.cell), "last unfinished progression Grow canceled")
	_assert_equal(game.get_building_at(Vector2i(23, 12)), null, "cancellation removes Grow blueprint")
	_assert_step(game, place_next, "grow", place_help)
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12)), "progression Grow replaced")
	tray = game.get_building_at(Vector2i(23, 12))
	_assert_equal(tray.add_delivery(tray.get_cost()), tray.get_cost(), "replacement Grow supplied")
	_assert_true(tray.apply_build_work(tray.get_build_time()), "ordinary work completes progression Grow")
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, "Next: YOU place Nutrient Station · THEY cook/haul", "kitchen", "Designate NUTRI, power it, leave Cook + Haul above OFF.")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GROW_TRAY, Vector2i(24, 12)), "completed Grow has unfinished spare")
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(25, 12))
	tray.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, "Next: YOU power food chain · THEY cook/haul alone", "select", "Enable Grow + Nutrient power. Keep Cook/Haul above OFF so defaults keep working.")
	tray.manually_disabled = false
	var extra_kitchens: Array[VaultBuilding] = []
	for x in range(26, 29):
		extra_kitchens.append(_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(x, 12)))
	game.power_grid.recalculate(game.buildings)
	_assert_true(game.power_grid.is_building_shed(tray.building_id), "completed Grow is shed beside unfinished spare")
	_assert_step(game, FOOD_CHARGE_NEXT, "generator", FOOD_CHARGE_HELP)
	game.residents[0].needs.food = 19.0
	game.food_system.meals = 0
	game.food_system.raw_food = 0
	tray.manually_disabled = true
	_assert_step(game, ENABLE_GROW_NEXT, "select", ENABLE_GROW_HELP)
	tray.manually_disabled = false
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, GROW_CHARGE_NEXT, "generator", GROW_CHARGE_HELP)
	for kitchen: VaultBuilding in extra_kitchens:
		kitchen.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, COOK_NEXT, "select", WAITING_COOK_HELP)
	_dispose(game)


func _test_progression_grow_finish_precedence() -> void:
	var game := _healthy_game()
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12)), "unfinished Grow retained during earlier progression steps")
	_assert_dig(game, "Dig floor gate precedes progression Grow finish")
	for x in range(17, 29):
		var cell := Vector2i(x, 10)
		_assert_true(game.map_grid.queue_dig(cell), "Grow precedence fixture queues rock")
		_assert_true(game.map_grid.apply_dig_work(cell, 8.0), "Grow precedence fixture carves floor")
	_assert_step(game, PLACE_TWO_BUNKS_NEXT, "bed", PLACE_TWO_BUNKS_HELP)
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(20, 12))
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(21, 12))
	_assert_step(game, PROGRESSION_CHARGE_NEXT, "generator", PROGRESSION_CHARGE_HELP)
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(22, 12)), "unfinished Charge retained before Grow")
	_assert_step(game, FINISH_CHARGE_NEXT, "select", FINISH_CHARGE_HELP)
	game.residents[0].needs.food = 19.0
	game.food_system.meals = 0
	_assert_step(game, KITCHEN_NEXT, "kitchen", "Place and power a Nutrient Station so Cook can turn raw food into meals.")
	game.residents[0].needs.food = 100.0
	game.residents[0].needs.rest = 28.0
	game.residents[1].needs.rest = 28.0
	game.residents[2].needs.rest = 28.0
	_assert_step(game, BUNK_NEXT, "bed", "Place bunks so tired undrafted crew have a bed.")
	_dispose(game)


func _food_capacity_game(air_count: int) -> VaultGame:
	var game := _progression_bunk_game()
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(20, 12))
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(21, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(22, 12))
	# Disabled older spares must not hide enabled shed instances.
	for kind in [VaultBuilding.Kind.GROW_TRAY, VaultBuilding.Kind.KITCHEN]:
		var spare := _add_completed_building(game, kind, Vector2i(23 + int(kind == VaultBuilding.Kind.KITCHEN), 13))
		spare.manually_disabled = true
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12))
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(24, 12))
	for x in range(air_count):
		_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(20 + x, 14))
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.power_grid.supply, 9, "food capacity fixture has Core plus one completed non-Core Charge")
	_assert_true(game.player_orders._has_eligible_worker("cook"), "food capacity fixture has eligible Cook")
	_assert_true(game.player_orders._has_eligible_worker("haul"), "food capacity fixture has eligible Haul")
	_assert_true(game.power_grid.is_building_shed(game.get_building_at(Vector2i(23, 12)).building_id), "allocator sheds enabled Grow")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.GROW_TRAY), 0, "no Grow instance powered")
	if air_count >= 3:
		_assert_true(game.power_grid.is_building_shed(game.get_building_at(Vector2i(24, 12)).building_id), "allocator sheds enabled Kitchen")
		_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.KITCHEN), 0, "no Kitchen instance powered")
	else:
		_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.KITCHEN), 1, "Grow-only brownout keeps Kitchen powered")
	return game


func _test_progression_food_capacity_restore() -> void:
	# Two Air: Grow alone shed; three: Kitchen and Grow shed; six: +7 remains insufficient.
	for air_count in [2, 3, 6]:
		var game := _food_capacity_game(air_count)
		_assert_step(game, FOOD_CHARGE_NEXT, "generator", FOOD_CHARGE_HELP)
		game.active_tool = "dig"
		game.player_orders.refresh()
		_assert_equal(game.active_tool, "dig", "food capacity PLACE refresh preserves active tool")
		_assert_equal(game.player_orders.objective_label.text, FOOD_CHARGE_NEXT, "refresh displays food capacity PLACE")
		var cell := Vector2i(25, 12)
		_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, cell), "food capacity Charge placed")
		var charge := game.get_building_at(cell)
		_assert_false(charge.complete or charge.is_emergency_core, "food capacity Charge is unfinished non-Core")
		_assert_equal(charge.delivered, 0, "food capacity Charge starts unsupplied")
		var funded_stock := game.food_system.salvage
		game.food_system.salvage = 0
		_assert_salvage_tip(game, 18, 0)
		charge.delivered = charge.get_cost()
		_assert_step(game, FINISH_CHARGE_NEXT, "select", FINISH_CHARGE_HELP)
		charge.delivered = 0
		game.food_system.salvage = funded_stock
		game.power_grid.recalculate(game.buildings)
		_assert_step(game, FINISH_CHARGE_NEXT, "select", FINISH_CHARGE_HELP)
		game.player_orders.refresh()
		_assert_equal(game.active_tool, "dig", "food capacity FINISH refresh preserves active tool")
		_assert_equal(game.player_orders.objective_label.text, FINISH_CHARGE_NEXT, "refresh displays food capacity FINISH")
		_assert_equal(charge.add_delivery(1), 1, "food capacity Charge partially supplied")
		_assert_false(charge.is_supplied(), "partial Charge still needs supply")
		_assert_step(game, FINISH_CHARGE_NEXT, "select", FINISH_CHARGE_HELP)
		_assert_equal(charge.add_delivery(charge.get_cost() - 1), charge.get_cost() - 1, "food capacity Charge fully supplied")
		_assert_true(charge.is_supplied() and not charge.complete, "supplied Charge still requires work")
		_assert_step(game, FINISH_CHARGE_NEXT, "select", FINISH_CHARGE_HELP)
		game.active_tool = "cancel"
		_assert_true(game.issue_order(cell), "cancel food capacity Charge")
		_assert_equal(game.get_building_at(cell), null, "canceled Charge removed")
		game.power_grid.recalculate(game.buildings)
		_assert_step(game, FOOD_CHARGE_NEXT, "generator", FOOD_CHARGE_HELP)
		_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, cell), "replace food capacity Charge")
		charge = game.get_building_at(cell)
		_assert_step(game, FINISH_CHARGE_NEXT, "select", FINISH_CHARGE_HELP)
		_assert_equal(charge.add_delivery(charge.get_cost()), charge.get_cost(), "replacement Charge supplied")
		_assert_true(charge.apply_build_work(charge.get_build_time()), "ordinary work completes food capacity Charge")
		game.power_grid.recalculate(game.buildings)
		_assert_equal(game.power_grid.supply, 16, "completed Charge adds seven capacity")
		if air_count == 6:
			_assert_true(game.power_grid.demand > game.power_grid.supply, "overload still exceeds expanded capacity")
			_assert_true(game.power_grid.is_building_shed(game.get_building_at(Vector2i(23, 12)).building_id), "Grow still shed after one Charge")
			_assert_true(game.power_grid.is_building_shed(game.get_building_at(Vector2i(24, 12)).building_id), "Kitchen still shed after one Charge")
			_assert_step(game, FOOD_CHARGE_NEXT, "generator", FOOD_CHARGE_HELP)
		else:
			_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.GROW_TRAY), 1, "additional capacity restores Grow")
			_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.KITCHEN), 1, "additional capacity restores Kitchen")
			_assert_false(game.power_grid.is_building_shed(game.get_building_at(Vector2i(23, 12)).building_id), "recovered Grow no longer shed")
			_assert_false(game.power_grid.is_building_shed(game.get_building_at(Vector2i(24, 12)).building_id), "recovered Kitchen no longer shed")
			_assert_air_fallthrough(game)
		game.player_orders.refresh()
		_assert_equal(game.active_tool, "cancel", "completion refresh preserves active tool")
		_assert_equal(game.player_orders.objective_label.text, game.player_orders._primary_next_step()["text"], "completion refresh re-evaluates recommendation")
		_dispose(game)


func _test_progression_food_capacity_guards() -> void:
	# Each required kind independently blocks capacity diagnosis when all its completed instances are disabled.
	for disabled_kinds in [[VaultBuilding.Kind.GROW_TRAY], [VaultBuilding.Kind.KITCHEN], [VaultBuilding.Kind.GROW_TRAY, VaultBuilding.Kind.KITCHEN]]:
		var game := _food_capacity_game(3)
		for building: VaultBuilding in game.buildings:
			if building.kind in disabled_kinds:
				building.manually_disabled = true
		game.power_grid.recalculate(game.buildings)
		for kind in disabled_kinds:
			_assert_equal(game.get_powered_building_count(kind), 0, "disabled required food kind has no powered instance")
			for building: VaultBuilding in game.buildings:
				if building.kind == kind:
					_assert_false(game.power_grid.is_building_shed(building.building_id), "disabled food is not allocator shed")
		_assert_step(game, FOOD_POWER_NEXT, "select", FOOD_POWER_HELP)
		_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(25, 12)), "disabled food fixture has unfinished Charge")
		_assert_step(game, FOOD_POWER_NEXT, "select", FOOD_POWER_HELP)
		_dispose(game)
	for role in ["cook", "haul"]:
		for shed in [false, true]:
			var game := _food_capacity_game(3) if shed else _air_ready_game()
			for resident: VaultResident in game.residents:
				resident.set_work_priority(role, VaultResident.PRIORITY_DISABLED)
			_assert_false(game.player_orders._has_eligible_worker(role), "disabled role has no eligible worker")
			_assert_step(game, FOOD_POWER_NEXT, "select", FOOD_POWER_HELP)
			_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(25, 12)), "workforce fixture has unfinished Charge")
			_assert_step(game, FOOD_POWER_NEXT, "select", FOOD_POWER_HELP)
			_dispose(game)
	var game := _food_capacity_game(3)
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(25, 12)), "priority fixture has unfinished Charge")
	game.food_system.meals = 0
	game.residents[0].needs.food = 19.0
	_assert_step(game, FINISH_CHARGE_NEXT, "select", FINISH_CHARGE_HELP)
	game.food_system.meals = game.get_alive_count()
	game.residents[0].needs.food = 100.0
	game.residents[0].needs.health = 99.0
	_assert_step(game, MED_NEXT, "medical", "Place a Med Bed so the injured can be treated.")
	game.residents[0].needs.health = 100.0
	for resident: VaultResident in game.residents:
		resident.needs.rest = 28.0
	_assert_step(game, BUNK_NEXT, "bed", "Place bunks so tired undrafted crew have a bed.")
	for resident: VaultResident in game.residents:
		resident.needs.rest = 100.0
	_assert_step(game, FINISH_CHARGE_NEXT, "select", FINISH_CHARGE_HELP)
	_dispose(game)


func _test_powered_kitchen() -> void:
	var game := _critical_game()
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(21, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_true(kitchen.powered, "recalculated grid powers the kitchen")
	_assert_true(game.player_orders._primary_next_step()["text"] != POWER_NEXT, "powered kitchen skips Select power line")
	_assert_true(game.player_orders._primary_next_step()["text"] != CHARGE_NEXT, "powered kitchen skips Charge Node power line")
	_assert_step(game, COOK_NEXT, "select", COOK_HELP)
	_dispose(game)


func _powered_critical_game() -> VaultGame:
	var game := _critical_game()
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.LAMP:
			building.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	_assert_true(kitchen.powered, "Emergency Core powers the kitchen with starting Lumen disabled")
	return game


func _test_cook_ready() -> void:
	var game := _powered_critical_game()
	_assert_equal(game.food_system.raw_food, 4, "starting raw food is available to cook")
	_assert_true(game.food_system.can_cook(), "starting stock can cook")
	_assert_step(game, COOK_NEXT, "select", COOK_HELP)
	game.active_tool = "dig"
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "Cook recommendation refresh preserves active dig tool")
	_assert_equal(game.player_orders.objective_label.text, COOK_NEXT, "refresh displays the Cook recommendation")
	game.food_system.raw_food = 1
	_assert_step(game, COOK_NEXT, "select", COOK_HELP)
	game.residents[0].needs.food = 100.0
	_assert_dig(game, "healthy day-one wing with a powered kitchen still gets the dig hint")
	_dispose(game)


func _test_drafted_cooks() -> void:
	var game := _powered_critical_game()
	for resident: VaultResident in game.residents:
		if resident.alive:
			resident.drafted = true
	_assert_step(game, ENABLE_COOK_NEXT, "select", ENABLE_COOK_HELP)
	_dispose(game)


func _test_disabled_cooks() -> void:
	var game := _powered_critical_game()
	for resident: VaultResident in game.residents:
		if resident.alive:
			resident.drafted = false
			resident.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
	_assert_step(game, ENABLE_COOK_NEXT, "select", ENABLE_COOK_HELP)
	_dispose(game)


func _test_cook_waiting_for_raw_food() -> void:
	var game := _powered_critical_game()
	game.food_system.raw_food = 0
	_assert_equal(game.job_system.get_pending_raw_food(), 0, "no raw food is pending")
	_assert_step(game, GROW_NEXT, "grow", GROW_HELP)
	game.active_tool = "dig"
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "Grow recommendation refresh preserves active dig tool")
	_assert_equal(game.player_orders.objective_label.text, GROW_NEXT, "refresh displays the Grow recommendation")
	game.job_system.queue_raw_food(Vector2i(21, 12), 2)
	_assert_true(game.job_system.get_pending_raw_food() > 0, "raw food is pending haul")
	_assert_equal(game.food_system.raw_food, 0, "pending raw food does not increase stock")
	_assert_true(not game.food_system.can_cook(), "pending raw food cannot be cooked")
	_assert_step(game, COOK_NEXT, "select", WAITING_COOK_HELP)
	_assert_true(not "grow" in str(game.player_orders._primary_next_step()["text"]).to_lower(), "pending raw food does not suggest growing")
	_dispose(game)


func _test_grow_tray_supply_diagnosis() -> void:
	var game := _powered_critical_game()
	game.food_system.raw_food = 0
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GROW_TRAY, Vector2i(21, 12)), "unfinished tray blueprint can be placed")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.GROW_TRAY), 0, "blueprint is not a completed tray")
	_assert_step(game, FINISH_GROW_NEXT, "select", FINISH_GROW_HELP)
	var first := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(22, 12))
	var second := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12))
	first.manually_disabled = true
	second.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, ENABLE_GROW_NEXT, "select", ENABLE_GROW_HELP)
	first.manually_disabled = false
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.KITCHEN), 1, "kitchen stays powered while enabled tray is shed")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.GROW_TRAY), 0, "enabled tray lacks available power")
	_assert_step(game, GROW_CHARGE_NEXT, "generator", GROW_CHARGE_HELP)
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(24, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_true(first.powered, "completed enabled tray receives power")
	_assert_false(second.powered, "disabled spare tray stays unpowered")
	_assert_step(game, COOK_NEXT, "select", WAITING_COOK_HELP)
	second.manually_disabled = false
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.GROW_TRAY), 2, "both completed trays are powered")
	_assert_step(game, COOK_NEXT, "select", WAITING_COOK_HELP)
	_dispose(game)


func _test_pending_food_suppresses_grow() -> void:
	# Meals alone, raw alone, and both backlogs suppress supply diagnosis.
	for pending in [Vector2i(2, 0), Vector2i(0, 2), Vector2i(2, 2)]:
		var game := _powered_critical_game()
		game.food_system.raw_food = 0
		game.job_system.queue_meals(Vector2i(20, 12), pending.x)
		game.job_system.queue_raw_food(Vector2i(21, 12), pending.y)
		_assert_step(game, COOK_NEXT, "select", WAITING_COOK_HELP)
		for resident: VaultResident in game.residents:
			resident.set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
		_assert_step(game, ENABLE_HAUL_NEXT, "select", ENABLE_HAUL_HELP)
		_dispose(game)


func _test_in_transit_raw_suppresses_grow() -> void:
	var game := _powered_critical_game()
	game.food_system.raw_food = 0
	var source := Vector2i(21, 12)
	game.map_grid.paint_stockpile(Vector2i(27, 19))
	for resident: VaultResident in game.residents:
		resident.set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
	var worker: VaultResident = game.residents[0]
	worker.set_work_priority("haul", VaultResident.PRIORITY_HIGHEST)
	worker.position = game.map_grid.cell_to_world(source)
	game.job_system.queue_raw_food(source, 2)
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_assert_equal(worker.current_job_type, JobSystem.JobType.HAUL_RAW_FOOD, "worker claims raw-food delivery")
	_assert_equal(worker.carrying, 2, "raw food is in transit")
	for job: Dictionary in game.job_system.jobs:
		if int(job.type) == JobSystem.JobType.HAUL_RAW_FOOD:
			_assert_equal(int(job.amount), 0, "source backlog is empty after pickup")
			_assert_equal(int(job.in_transit), 2, "haul job tracks the carried raw food")
	_assert_equal(game.job_system.get_pending_raw_food(), 2, "in-transit raw food remains pending")
	_assert_equal(game.food_system.raw_food, 0, "carried raw food remains outside stored stock")
	_assert_step(game, COOK_NEXT, "select", WAITING_COOK_HELP)
	_dispose(game)


func _test_grow_crisis_guards() -> void:
	var game := _powered_critical_game()
	game.food_system.raw_food = 0
	game.residents[0].needs.food = 20.0
	_assert_dig(game, "empty raw stock without a critical resident does not suggest Grow")
	game.residents[0].needs.food = 19.0
	game.food_system.meals = game.get_alive_count()
	_assert_dig(game, "sufficient stored meals suppress Grow despite a critical resident")
	game.food_system.meals = 0
	_assert_step(game, GROW_NEXT, "grow", GROW_HELP)
	# Critical rest also diagnoses supply after the bunk requirement is satisfied.
	game.residents[0].needs.food = 100.0
	game.residents[0].needs.rest = 14.0
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(21, 12))
	_assert_step(game, GROW_NEXT, "grow", GROW_HELP)
	_dispose(game)


func _test_interrupts_before_cook() -> void:
	var game := _powered_critical_game()
	game.food_system.raw_food = 0
	var resident: VaultResident = game.residents[0]
	resident.needs.rest = 100.0
	resident.needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.RECREATION_CONSOLE), 0, "no completed rec console is available")
	_assert_step(game, REC_NEXT, "rec", "Place a Rec Console so crew can recover mood.")
	resident.needs.mood = 100.0
	resident.needs.health = 99.0
	_assert_equal(resident.medical_bed_id, -1, "injured resident has no medical reservation")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.MEDICAL_BED), 0, "no usable med bed is available")
	_assert_step(game, MED_NEXT, "medical", "Place a Med Bed so the injured can be treated.")
	resident.needs.health = 100.0
	resident.needs.rest = 28.0
	_assert_true(not resident.drafted, "tired resident is undrafted")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.BED), 0, "no completed bunk is available")
	_assert_step(game, BUNK_NEXT, "bed", "Place bunks so tired undrafted crew have a bed.")
	_dispose(game)


func _test_pending_meals_need_haul() -> void:
	var game := _powered_critical_game()
	for resident: VaultResident in game.residents:
		resident.set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
		resident.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
	game.job_system.queue_meals(Vector2i(20, 12), 2)
	_assert_equal(game.job_system.get_pending_meals(), 2, "meals are pending delivery")
	_assert_step(game, ENABLE_HAUL_NEXT, "select", ENABLE_HAUL_HELP)
	game.active_tool = "dig"
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "Haul recommendation refresh preserves active dig tool")
	_assert_equal(game.player_orders.objective_label.text, ENABLE_HAUL_NEXT, "refresh displays the Haul recommendation")
	game.residents[0].set_work_priority("cook", VaultResident.PRIORITY_HIGHEST)
	_assert_step(game, ENABLE_HAUL_NEXT, "select", ENABLE_HAUL_HELP)
	game.residents[0].set_work_priority("haul", VaultResident.PRIORITY_HIGHEST)
	_assert_step(game, COOK_NEXT, "select", COOK_HELP)
	game.residents[0].set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
	_assert_step(game, ENABLE_COOK_NEXT, "select", ENABLE_COOK_HELP)
	_dispose(game)


func _test_pending_raw_food_need_haul() -> void:
	var game := _powered_critical_game()
	game.food_system.raw_food = 0
	for resident: VaultResident in game.residents:
		resident.set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
		resident.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
	game.job_system.queue_raw_food(Vector2i(21, 12), 2)
	_assert_equal(game.job_system.get_pending_meals(), 0, "only raw food is pending")
	_assert_equal(game.job_system.get_pending_raw_food(), 2, "raw food is pending delivery")
	_assert_false(game.food_system.can_cook(), "zero raw stock cannot cook")
	_assert_step(game, ENABLE_HAUL_NEXT, "select", ENABLE_HAUL_HELP)
	game.residents[0].set_work_priority("cook", VaultResident.PRIORITY_HIGHEST)
	_assert_step(game, ENABLE_HAUL_NEXT, "select", ENABLE_HAUL_HELP)
	game.residents[0].set_work_priority("haul", VaultResident.PRIORITY_HIGHEST)
	_assert_step(game, COOK_NEXT, "select", WAITING_COOK_HELP)
	_dispose(game)


func _test_pending_raw_food_with_stock() -> void:
	var game := _powered_critical_game()
	game.food_system.raw_food = 1
	for resident: VaultResident in game.residents:
		resident.set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
		resident.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
	game.job_system.queue_raw_food(Vector2i(21, 12), 2)
	_assert_equal(game.job_system.get_pending_meals(), 0, "stocked raw-food case has no pending meals")
	_assert_equal(game.job_system.get_pending_raw_food(), 2, "stocked raw-food case still has pending raw")
	_assert_true(game.food_system.can_cook(), "exactly one raw food can cook despite pending raw")
	_assert_step(game, ENABLE_COOK_NEXT, "select", ENABLE_COOK_HELP)
	game.residents[0].set_work_priority("cook", VaultResident.PRIORITY_HIGHEST)
	_assert_step(game, COOK_NEXT, "select", COOK_HELP)
	_dispose(game)


func _test_ineligible_haulers() -> void:
	var game := _powered_critical_game()
	for resident: VaultResident in game.residents:
		resident.set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
	game.job_system.queue_meals(Vector2i(20, 12), 2)
	var hauler: VaultResident = game.residents[1]
	hauler.set_work_priority("haul", VaultResident.PRIORITY_HIGHEST)
	hauler.drafted = true
	_assert_step(game, ENABLE_HAUL_NEXT, "select", ENABLE_HAUL_HELP)
	hauler.drafted = false
	hauler.alive = false
	_assert_step(game, ENABLE_HAUL_NEXT, "select", ENABLE_HAUL_HELP)
	_dispose(game)


func _test_interrupts_before_haul() -> void:
	var game := _powered_critical_game()
	for crew: VaultResident in game.residents:
		crew.set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
	game.job_system.queue_meals(Vector2i(20, 12), 2)
	_assert_step(game, ENABLE_HAUL_NEXT, "select", ENABLE_HAUL_HELP)
	var resident: VaultResident = game.residents[0]
	resident.needs.rest = 100.0
	resident.needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.RECREATION_CONSOLE), 0, "Haul interrupt case has no rec console")
	_assert_step(game, REC_NEXT, "rec", "Place a Rec Console so crew can recover mood.")
	resident.needs.mood = 100.0
	resident.needs.health = 99.0
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.MEDICAL_BED), 0, "Haul interrupt case has no med bed")
	_assert_step(game, MED_NEXT, "medical", "Place a Med Bed so the injured can be treated.")
	resident.needs.health = 100.0
	resident.needs.rest = 28.0
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.BED), 0, "Haul interrupt case has no bunk")
	_assert_step(game, BUNK_NEXT, "bed", "Place bunks so tired undrafted crew have a bed.")
	_dispose(game)


func _test_no_pending_food_with_haul_off() -> void:
	var game := _powered_critical_game()
	for resident: VaultResident in game.residents:
		resident.set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
		resident.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
	_assert_equal(game.job_system.get_pending_meals(), 0, "no meals are pending with Haul off")
	_assert_equal(game.job_system.get_pending_raw_food(), 0, "no raw food is pending with Haul off")
	_assert_step(game, ENABLE_COOK_NEXT, "select", ENABLE_COOK_HELP)
	game.residents[0].set_work_priority("cook", VaultResident.PRIORITY_HIGHEST)
	_assert_step(game, COOK_NEXT, "select", COOK_HELP)
	game.food_system.raw_food = 0
	_assert_step(game, GROW_NEXT, "grow", GROW_HELP)
	game.residents[0].set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
	_assert_step(game, ENABLE_COOK_NEXT, "select", ENABLE_COOK_HELP)
	_dispose(game)


func _test_existing_charge_node_insufficient() -> void:
	var game := _critical_game()
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(21, 12))
	# Three higher-priority Air Recyclers consume all nine available power.
	for index in 3:
		_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(22 + index, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.power_grid.supply, 9, "extra completed Charge Node adds seven power")
	_assert_true(game.power_grid.is_building_shed(kitchen.building_id), "higher-priority demand sheds kitchen despite existing Charge Node")
	_assert_step(game, CHARGE_NEXT, "generator", CHARGE_HELP)
	_dispose(game)


func _assert_offline_rec(game: VaultGame, disabled: bool) -> void:
	if disabled:
		_assert_step(game, ENABLE_REC_NEXT, "select", ENABLE_REC_HELP)
	else:
		_assert_step(game, REC_CHARGE_NEXT, "generator", REC_CHARGE_HELP)


func _assert_rec_suppressed(game: VaultGame) -> void:
	var text: String = game.player_orders._primary_next_step()["text"]
	for rec_next in [REC_NEXT, FINISH_REC_NEXT, ENABLE_REC_NEXT, REC_CHARGE_NEXT]:
		_assert_true(text != rec_next, "Rec advice suppressed: %s" % rec_next)


func _test_rec_finish_restore() -> void:
	var game := _healthy_game()
	game.residents[0].needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD
	_assert_step(game, REC_NEXT, "rec", "Place a Rec Console so crew can recover mood.")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(20, 12)), "Rec blueprint can be placed")
	var rec := game.get_building_at(Vector2i(20, 12))
	_assert_false(rec.complete, "Rec blueprint starts unfinished")
	_assert_equal(rec.delivered, 0, "Rec blueprint starts unsupplied")
	_assert_step(game, FINISH_REC_NEXT, "select", FINISH_REC_HELP)
	game.active_tool = "dig"
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "Rec finish refresh preserves active dig tool")
	_assert_equal(game.player_orders.objective_label.text, FINISH_REC_NEXT, "refresh displays Rec finish")
	_assert_equal(rec.add_delivery(rec.get_cost()), rec.get_cost(), "Rec blueprint receives its salvage cost")
	_assert_true(rec.is_supplied(), "Rec blueprint is fully supplied")
	_assert_false(rec.complete, "supplied Rec still needs construction")
	_assert_step(game, FINISH_REC_NEXT, "select", FINISH_REC_HELP)
	game.active_tool = "cancel"
	_assert_true(game.issue_order(Vector2i(20, 12)), "cancel removes unfinished Rec blueprint")
	_assert_equal(game.get_building_at(Vector2i(20, 12)), null, "canceled Rec leaves no blueprint")
	_assert_step(game, REC_NEXT, "rec", "Place a Rec Console so crew can recover mood.")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(20, 12)), "Rec blueprint can be replaced after cancellation")
	rec = game.get_building_at(Vector2i(20, 12))
	_assert_equal(rec.add_delivery(rec.get_cost()), rec.get_cost(), "replacement Rec receives salvage")
	_assert_step(game, FINISH_REC_NEXT, "select", FINISH_REC_HELP)
	_assert_true(rec.apply_build_work(rec.get_build_time()), "normal construction work completes Rec blueprint")
	game.power_grid.recalculate(game.buildings)
	_assert_true(rec.powered, "completed Rec is powered by starter grid")
	_assert_rec_suppressed(game)
	_assert_dig(game, "completed powered Rec resolves finish recommendation")
	game.active_tool = "dig"
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, DIG_NEXT, "refresh clears resolved Rec finish")
	_assert_equal(game.active_tool, "dig", "resolved Rec finish refresh preserves dig")
	rec.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, ENABLE_REC_NEXT, "select", ENABLE_REC_HELP)
	rec.manually_disabled = false
	_add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(21, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_true(game.power_grid.is_building_shed(rec.building_id), "higher priority Lumens shed newly completed Rec")
	_assert_step(game, REC_CHARGE_NEXT, "generator", REC_CHARGE_HELP)
	_dispose(game)


func _test_rec_finish_guards() -> void:
	for supplied in [false, true]:
		var game := _healthy_game()
		_assert_true(game.place_blueprint(VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(20, 12)), "guard case has unfinished Rec")
		var rec := game.get_building_at(Vector2i(20, 12))
		if supplied:
			_assert_equal(rec.add_delivery(rec.get_cost()), rec.get_cost(), "guard Rec blueprint is supplied")
		for mood in [9.0001, 35.0, 100.0]:
			game.residents[0].needs.mood = mood
			_assert_rec_suppressed(game)
			_assert_dig(game, "mood %s does not trigger unfinished Rec" % mood)
		game.residents[0].needs.mood = ResidentNeeds.BREAK_MOOD_THRESHOLD
		_assert_step(game, FINISH_REC_NEXT, "select", FINISH_REC_HELP)
		game.residents[0].alive = false
		_assert_rec_suppressed(game)
		_assert_dig(game, "dead mood-break resident does not trigger unfinished Rec")
		_dispose(game)


func _test_rec_enable_restore() -> void:
	var game := _healthy_game()
	game.residents[0].needs.mood = 9.0
	var rec := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(20, 12))
	var spare := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(21, 12))
	rec.manually_disabled = true
	spare.manually_disabled = true
	_assert_true(game.place_blueprint(VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(22, 12)), "enabled unfinished Rec blueprint can be placed")
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.RECREATION_CONSOLE), 2, "unfinished blueprint excluded from completed Rec count")
	_assert_offline_rec(game, true)
	game.active_tool = "dig"
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "Rec enable refresh preserves active dig tool")
	_assert_equal(game.player_orders.objective_label.text, ENABLE_REC_NEXT, "refresh displays Rec enable")
	rec.manually_disabled = false
	game.power_grid.recalculate(game.buildings)
	_assert_true(rec.powered, "enabling Rec restores power on starter grid")
	_assert_false(spare.powered, "disabled spare stays offline beside powered Rec")
	_assert_rec_suppressed(game)
	_assert_dig(game, "powered Rec lets Next move on after enable")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, DIG_NEXT, "refresh clears resolved Rec enable")
	_assert_equal(game.active_tool, "dig", "resolved enable refresh preserves dig")
	_dispose(game)


func _test_rec_charge_restore() -> void:
	var game := _healthy_game()
	game.residents[0].needs.mood = 9.0
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(20, 12))
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(21, 12))
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(22, 12))
	_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(23, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.power_grid.supply, 9, "Core plus Charge supply nine power")
	_assert_equal(game.power_grid.demand, 9, "Lumen Grow Kitchen Air demand nine power")
	_assert_equal(game.power_grid.served, 9, "all existing demand is served")
	var rec := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(24, 12))
	var spare := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(25, 12))
	spare.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.power_grid.demand, 10, "enabled completed Rec raises demand to ten")
	_assert_equal(game.power_grid.served, 9, "higher priority fixtures retain nine power")
	_assert_true(game.power_grid.is_building_shed(rec.building_id), "real allocation sheds enabled Rec beside disabled spare")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.RECREATION_CONSOLE), 0, "no Rec is powered")
	_assert_offline_rec(game, false)
	game.active_tool = "dig"
	game.player_orders._set_architect_tab("dig")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, REC_CHARGE_NEXT, "refresh displays Rec Charge")
	_assert_equal(game.active_tool, "dig", "Rec Charge refresh preserves active dig tool")
	_assert_equal(game.player_orders._architect_open_tab, "build", "Rec Charge suggestion opens BUILD")
	_assert_true(game.player_orders.command_buttons["generator"].is_visible_in_tree(), "suggested CHARGE is visible in BUILD")
	_assert_equal(game.player_orders.command_buttons["generator"].modulate, Color("75d4b4"), "suggested CHARGE is highlighted teal")
	_assert_equal(game.player_orders.command_buttons["dig"].modulate, Color("efc56b"), "active dig stays gold")
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(26, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_true(rec.powered, "extra Charge capacity restores Rec power")
	_assert_false(spare.powered, "disabled spare remains offline after Charge")
	_assert_rec_suppressed(game)
	_assert_dig(game, "powered Rec lets Next move on after Charge")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, DIG_NEXT, "refresh clears resolved Rec Charge")
	_assert_equal(game.active_tool, "dig", "resolved Charge refresh preserves dig")
	_dispose(game)


func _test_rec_guards() -> void:
	for disabled in [true, false]:
		var game := _healthy_game()
		game.residents[0].needs.mood = 9.0
		_assert_step(game, REC_NEXT, "rec", "Place a Rec Console so crew can recover mood.")
		_assert_true(game.place_blueprint(VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(20, 12)), "unfinished Rec blueprint can be placed")
		game.power_grid.recalculate(game.buildings)
		_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.RECREATION_CONSOLE), 0, "blueprint alone has zero completed Rec")
		_assert_step(game, FINISH_REC_NEXT, "select", FINISH_REC_HELP)
		var rec := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(21, 12))
		rec.manually_disabled = disabled
		# With Lumen disabled, the kitchen consumes both Core power before Rec.
		for building: VaultBuilding in game.buildings:
			if building.kind == VaultBuilding.Kind.LAMP:
				building.manually_disabled = true
		_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(22, 12))
		game.power_grid.recalculate(game.buildings)
		_assert_offline_rec(game, disabled)
		for mood in [9.0001, 35.0]:
			game.residents[0].needs.mood = mood
			_assert_dig(game, "mood %s does not trigger offline Rec" % mood)
		game.residents[0].needs.mood = 9.0
		game.residents[0].alive = false
		_assert_dig(game, "dead mood-break resident does not trigger offline Rec")
		_dispose(game)


func _test_kitchen_before_offline_rec() -> void:
	for disabled in [true, false]:
		var game := _critical_game()
		game.residents[0].needs.mood = 9.0
		_assert_true(game.place_blueprint(VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(22, 12)), "kitchen crisis has unfinished Rec")
		_assert_step(game, KITCHEN_NEXT, "kitchen", "Place and power a Nutrient Station so Cook can turn raw food into meals.")
		var rec := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(20, 12))
		rec.manually_disabled = disabled
		# Two higher priority Lumens consume both Core power before Rec or kitchen.
		_add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(21, 12))
		game.power_grid.recalculate(game.buildings)
		_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.RECREATION_CONSOLE), 0, "Rec is offline during kitchen crisis")
		_assert_step(game, KITCHEN_NEXT, "kitchen", "Place and power a Nutrient Station so Cook can turn raw food into meals.")
		var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(23, 12))
		kitchen.manually_disabled = true
		game.power_grid.recalculate(game.buildings)
		_assert_step(game, POWER_NEXT, "select", "Power the Nutrient Station so Cook can run.")
		kitchen.manually_disabled = false
		game.power_grid.recalculate(game.buildings)
		_assert_true(game.power_grid.is_building_shed(kitchen.building_id), "real grid sheds enabled kitchen")
		_assert_step(game, CHARGE_NEXT, "generator", CHARGE_HELP)
		_dispose(game)


func _test_offline_rec_priority() -> void:
	for disabled in [true, false]:
		for lower_step in ["medical", "bunks", "haul", "enable_cook", "cook", "grow"]:
			var game := _powered_critical_game()
			var rec := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(21, 12))
			rec.manually_disabled = disabled
			game.power_grid.recalculate(game.buildings)
			var expected := COOK_NEXT
			match lower_step:
				"medical":
					game.residents[0].needs.food = 100.0
					game.residents[0].needs.health = 99.0
					expected = MED_NEXT
				"bunks":
					game.food_system.meals = game.get_alive_count()
					game.residents[0].needs.rest = 14.0
					expected = BUNK_NEXT
				"haul":
					game.job_system.queue_meals(Vector2i(20, 12), 2)
					for resident: VaultResident in game.residents:
						resident.set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
					expected = ENABLE_HAUL_NEXT
				"enable_cook":
					for resident: VaultResident in game.residents:
						resident.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
					expected = ENABLE_COOK_NEXT
				"grow":
					game.food_system.raw_food = 0
					expected = GROW_NEXT
			_assert_equal(game.player_orders._primary_next_step()["text"], expected, "lower priority branch is ready")
			game.residents[0].needs.mood = 9.0
			_assert_offline_rec(game, disabled)
			game.residents[0].needs.mood = 100.0
			_assert_equal(game.player_orders._primary_next_step()["text"], expected, "lower priority branch resumes above mood-break")
			_dispose(game)


func _test_medical_availability() -> void:
	var game := _healthy_game()
	var resident: VaultResident = game.residents[0]
	resident.needs.health = 99.0
	_assert_step(game, MED_NEXT, "medical", "Place a Med Bed so the injured can be treated.")
	var bed := _add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(20, 12))
	_assert_dig(game, "free usable medical bed avoids the medical interrupt")
	bed.manually_disabled = true
	_assert_step(game, ENABLE_MED_NEXT, "select", ENABLE_MED_HELP)
	bed.manually_disabled = false
	_assert_dig(game, "enabling a completed medical bed restores free care")
	bed.reserved_by = resident.resident_id
	_assert_step(game, MED_NEXT, "medical", "Place a Med Bed so the injured can be treated.")
	resident.medical_bed_id = bed.building_id
	_assert_dig(game, "only injured resident already reserved does not request a med bed")
	game.residents[1].needs.health = 99.0
	_assert_step(game, MED_NEXT, "medical", "Place a Med Bed so the injured can be treated.")
	_dispose(game)


func _test_medical_finish_restore() -> void:
	var game := _healthy_game()
	game.residents[0].needs.health = 99.0
	_assert_true(game.place_blueprint(VaultBuilding.Kind.MEDICAL_BED, Vector2i(20, 12)), "Med Bed blueprint can be placed")
	var bed := game.get_building_at(Vector2i(20, 12))
	_assert_false(bed.complete, "Med Bed blueprint starts unfinished")
	_assert_step(game, FINISH_MED_NEXT, "select", FINISH_MED_HELP)
	game.active_tool = "dig"
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "Med finish refresh preserves active dig tool")
	_assert_equal(game.player_orders.objective_label.text, FINISH_MED_NEXT, "refresh displays Med finish")
	_assert_equal(bed.add_delivery(bed.get_cost()), bed.get_cost(), "Med blueprint receives its salvage cost")
	_assert_true(bed.apply_build_work(bed.get_build_time()), "normal construction work completes Med blueprint")
	_assert_dig(game, "finished free Med Bed suppresses medical Next")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, DIG_NEXT, "refresh clears resolved Med finish")
	_assert_equal(game.active_tool, "dig", "resolved finish refresh preserves dig")
	_dispose(game)


func _test_medical_enable_restore() -> void:
	var game := _healthy_game()
	game.residents[0].needs.health = 99.0
	var bed := _add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(20, 12))
	var spare := _add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(21, 12))
	bed.manually_disabled = true
	spare.manually_disabled = true
	_assert_true(game.place_blueprint(VaultBuilding.Kind.MEDICAL_BED, Vector2i(22, 12)), "enabled unfinished Med blueprint can be placed beside disabled beds")
	_assert_false(game.get_building_at(Vector2i(22, 12)).manually_disabled, "unfinished Med blueprint is enabled")
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.MEDICAL_BED), 2, "unfinished Med blueprint is excluded from completed count")
	_assert_step(game, ENABLE_MED_NEXT, "select", ENABLE_MED_HELP)
	game.active_tool = "dig"
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "Med enable refresh preserves active dig tool")
	_assert_equal(game.player_orders.objective_label.text, ENABLE_MED_NEXT, "refresh displays Med enable")
	bed.manually_disabled = false
	_assert_dig(game, "free Med Bed suppresses medical Next beside disabled and unfinished beds")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, DIG_NEXT, "refresh clears resolved Med enable")
	_assert_equal(game.active_tool, "dig", "resolved enable refresh preserves dig")
	_dispose(game)


func _test_medical_mixed_fallbacks() -> void:
	var game := _healthy_game()
	game.residents[0].needs.health = 99.0
	var reserved := _add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(20, 12))
	reserved.reserved_by = game.residents[1].resident_id
	_assert_step(game, MED_NEXT, "medical", "Place a Med Bed so the injured can be treated.")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.MEDICAL_BED, Vector2i(21, 12)), "unfinished Med blueprint can be placed beside reserved bed")
	_assert_step(game, FINISH_MED_NEXT, "select", FINISH_MED_HELP)
	game.active_tool = "cancel"
	_assert_true(game.issue_order(Vector2i(21, 12)), "cancel last unfinished Med beside occupied bed")
	_assert_step(game, MED_NEXT, "medical", "Place a Med Bed so the injured can be treated.")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.MEDICAL_BED, Vector2i(21, 12)), "replace unfinished Med beside occupied bed")
	var spare := _add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(22, 12))
	spare.manually_disabled = true
	_assert_step(game, ENABLE_MED_NEXT, "select", ENABLE_MED_HELP)
	game.active_tool = "cancel"
	_assert_true(game.issue_order(Vector2i(21, 12)), "cancel removes unfinished Med blueprint")
	_assert_step(game, ENABLE_MED_NEXT, "select", ENABLE_MED_HELP)
	spare.reserved_by = game.residents[2].resident_id
	_assert_step(game, MED_NEXT, "medical", "Place a Med Bed so the injured can be treated.")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.MEDICAL_BED, Vector2i(21, 12)), "reserved disabled Med cannot enable but unfinished spare can finish")
	_assert_step(game, FINISH_MED_NEXT, "select", FINISH_MED_HELP)
	spare.reserved_by = -1
	_assert_step(game, ENABLE_MED_NEXT, "select", ENABLE_MED_HELP)
	_assert_true(game.toggle_building_enabled(spare.building_id), "enable free spare beside occupied bed")
	game.residents[2].needs.health = 99.0
	_assert_dig(game, "one free enabled spare suppresses Med guidance for multiple waiting injuries")
	_dispose(game)


func _test_medical_admitted_patient_spare() -> void:
	var game := _healthy_game()
	game.food_system.meals = game.get_alive_count()
	var occupied := _add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(27, 12))
	var patient: VaultResident = game.residents[0]
	patient.needs.health = 60.0
	for tick in range(200):
		game.job_system.advance(0.1)
		if patient.state == "Rest-Medical":
			break
	_assert_equal(patient.state, "Rest-Medical", "job system naturally admits first injured patient")
	_assert_equal(patient.get_cell(game.map_grid), occupied.cell, "admitted patient physically reaches Med Bed")
	_assert_equal(occupied.reserved_by, patient.resident_id, "occupied Med Bed reciprocally reserves admitted patient")
	_assert_equal(patient.medical_bed_id, occupied.building_id, "admitted patient reciprocally retains Med Bed")
	_assert_dig(game, "admitted patient alone needs no spare Med Bed")
	var waiting: VaultResident = game.residents[1]
	waiting.needs.health = 60.0
	game.job_system.advance(0.1)
	_assert_equal(waiting.medical_bed_id, -1, "second injured patient remains unreserved with occupied Med Bed")
	_assert_step(game, MED_NEXT, "medical", "Place a Med Bed so the injured can be treated.")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.MEDICAL_BED, Vector2i(21, 12)), "unfinished spare beside naturally occupied Med Bed")
	var blueprint := game.get_building_at(Vector2i(21, 12))
	_assert_step(game, FINISH_MED_NEXT, "select", FINISH_MED_HELP)
	game.active_tool = "dig"
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "occupied Med finish refresh preserves active tool")
	_assert_equal(game.player_orders.objective_label.text, FINISH_MED_NEXT, "occupied Med refresh displays exact finish")
	var spare := _add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(22, 12))
	spare.manually_disabled = true
	_assert_step(game, ENABLE_MED_NEXT, "select", ENABLE_MED_HELP)
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "occupied Med enable refresh preserves active tool")
	_assert_equal(game.player_orders.objective_label.text, ENABLE_MED_NEXT, "occupied Med refresh displays exact enable over finish")
	_assert_true(game.toggle_building_enabled(spare.building_id), "enable free spare for second injured patient")
	_assert_dig(game, "enabling free spare clears naturally occupied Med interrupt")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, DIG_NEXT, "refresh clears occupied Med enable interrupt")
	_assert_equal(game.active_tool, "dig", "resolved occupied Med enable preserves active tool")
	_assert_true(game.deconstruct_building(spare.building_id), "remove enabled spare to test completion independently")
	_assert_step(game, FINISH_MED_NEXT, "select", FINISH_MED_HELP)
	_assert_equal(blueprint.add_delivery(blueprint.get_cost()), blueprint.get_cost(), "occupied Med unfinished spare receives salvage")
	_assert_true(blueprint.apply_build_work(blueprint.get_build_time()), "ordinary construction completes free Med spare")
	_assert_dig(game, "completing free spare clears naturally occupied Med interrupt")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, DIG_NEXT, "refresh clears occupied Med finish interrupt")
	_assert_equal(game.active_tool, "dig", "resolved occupied Med finish preserves active tool")
	_dispose(game)


func _test_medical_guards() -> void:
	for unfinished in [false, true]:
		var game := _healthy_game()
		var resident: VaultResident = game.residents[0]
		if unfinished:
			_assert_true(game.place_blueprint(VaultBuilding.Kind.MEDICAL_BED, Vector2i(20, 12)), "guard case has Med blueprint")
		else:
			var bed := _add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(20, 12))
			bed.manually_disabled = true
		_assert_dig(game, "health 100 suppresses Med enable/finish")
		resident.needs.health = 99.0
		_assert_step(game, FINISH_MED_NEXT if unfinished else ENABLE_MED_NEXT, "select", FINISH_MED_HELP if unfinished else ENABLE_MED_HELP)
		resident.alive = false
		_assert_dig(game, "dead injured resident suppresses Med enable/finish")
		resident.alive = true
		resident.medical_bed_id = game.get_building_at(Vector2i(20, 12)).building_id
		_assert_dig(game, "reserved injured resident suppresses Med enable/finish")
		_dispose(game)


func _test_medical_priority() -> void:
	for unfinished in [false, true]:
		for lower_step in ["bunks", "haul", "enable_cook", "cook", "grow"]:
			var game := _powered_critical_game()
			var resident: VaultResident = game.residents[0]
			var expected := COOK_NEXT
			match lower_step:
				"bunks":
					game.food_system.meals = game.get_alive_count()
					resident.needs.rest = 28.0
					expected = BUNK_NEXT
				"haul":
					game.job_system.queue_meals(Vector2i(20, 12), 2)
					for crew: VaultResident in game.residents:
						crew.set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
					expected = ENABLE_HAUL_NEXT
				"enable_cook":
					for crew: VaultResident in game.residents:
						crew.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
					expected = ENABLE_COOK_NEXT
				"grow":
					game.food_system.raw_food = 0
					expected = GROW_NEXT
			_assert_equal(game.player_orders._primary_next_step()["text"], expected, "lower priority branch is ready before medical")
			if unfinished:
				_assert_true(game.place_blueprint(VaultBuilding.Kind.MEDICAL_BED, Vector2i(21, 12)), "priority case has Med blueprint")
			else:
				var bed := _add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(21, 12))
				bed.manually_disabled = true
			resident.needs.health = 99.0
			_assert_step(game, FINISH_MED_NEXT if unfinished else ENABLE_MED_NEXT, "select", FINISH_MED_HELP if unfinished else ENABLE_MED_HELP)
			resident.needs.mood = 9.0
			_assert_step(game, REC_NEXT, "rec", "Place a Rec Console so crew can recover mood.")
			var rec := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(22, 12))
			rec.manually_disabled = true
			game.power_grid.recalculate(game.buildings)
			_assert_offline_rec(game, true)
			rec.manually_disabled = false
			game.power_grid.recalculate(game.buildings)
			_assert_offline_rec(game, false)
			resident.needs.food = 19.0
			game.food_system.meals = 0
			var kitchen := game.get_building_at(Vector2i(20, 12))
			kitchen.manually_disabled = true
			game.power_grid.recalculate(game.buildings)
			_assert_step(game, POWER_NEXT, "select", "Power the Nutrient Station so Cook can run.")
			_dispose(game)


func _test_medical_brownout() -> void:
	var game := _healthy_game()
	game.residents[0].needs.health = 99.0
	var bed := _add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(20, 12))
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(21, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_true(game.power_grid.demand > game.power_grid.supply, "medical suppression case has insufficient grid power")
	_assert_true(game.power_grid.is_building_shed(kitchen.building_id), "real brownout sheds kitchen")
	_assert_equal(bed.get_base_power_demand(), 0, "Med Bed uses zero power")
	_assert_dig(game, "free Med Bed still suppresses medical Next during brownout")
	_dispose(game)


func _test_bunk_shortage() -> void:
	var game := _healthy_game()
	var resident: VaultResident = game.residents[0]
	resident.needs.rest = 28.0
	_assert_equal(game.player_orders._primary_next_step()["text"], BUNK_NEXT, "rest at 28 needs a bunk")
	resident.drafted = true
	_assert_dig(game, "drafted tired residents do not count toward bunk shortage")
	resident.drafted = false
	resident.needs.rest = 29.0
	_assert_dig(game, "rest above 28 does not need a bunk")
	resident.sleeping = true
	_assert_equal(game.player_orders._primary_next_step()["text"], BUNK_NEXT, "sleeping without a bed needs a bunk even above 28 rest")
	_assert_equal(resident.bed_id, -1, "rest-29 floor sleeper has no bunk")
	game.player_orders.refresh()
	_assert_true("BED SHORTAGE" in game.player_orders.alert_label.text, "rest-29 floor sleeper without a blueprint triggers shortage alert")
	resident.sleeping = false
	resident.needs.rest = 28.0
	var bunk := _add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(20, 12))
	_assert_dig(game, "one free completed bunk satisfies one tired resident")
	bunk.complete = false
	_assert_step(game, FINISH_BUNK_NEXT, "select", FINISH_BUNK_HELP)
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.BED), 0, "unfinished bunk does not count as completed")
	game.player_orders.refresh()
	_assert_true("BED SHORTAGE" in game.player_orders.alert_label.text, "unfinished bunk still leaves the shortage alert active")
	bunk.complete = true
	var sleeper: VaultResident = game.residents[1]
	sleeper.sleeping = true
	sleeper.bed_id = bunk.building_id
	_assert_equal(game.player_orders._primary_next_step()["text"], BUNK_NEXT, "occupied bunk is unavailable to another tired resident")
	sleeper.sleeping = false
	game.residents[2].needs.rest = 28.0
	_assert_equal(game.player_orders._primary_next_step()["text"], BUNK_NEXT, "two residents needing bunks outnumber one free bunk")
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(21, 12))
	_assert_dig(game, "free bunks equal to need prevent shortage")
	_dispose(game)


func _test_bunk_tired_sleeper_satisfied() -> void:
	var game := _healthy_game()
	var bunk := _add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(20, 12))
	var sleeper: VaultResident = game.residents[0]
	sleeper.sleeping = true
	sleeper.bed_id = bunk.building_id
	sleeper.needs.rest = 28.0
	_assert_dig(game, "rest-28 sleeper assigned to a completed bunk has no unmet bunk need")
	game.active_tool = "dig"
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "satisfied tired sleeper refresh preserves dig")
	_assert_equal(game.player_orders.objective_label.text, DIG_NEXT, "refresh displays dig for satisfied tired sleeper")
	_assert_false("BED SHORTAGE" in game.player_orders.alert_label.text, "satisfied tired sleeper does not trigger shortage alert")
	bunk.complete = false
	_assert_dig(game, "assigned tired sleeper does not trigger false bunk finish when bunk is unfinished")
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "assigned sleeper with unfinished bunk refresh preserves dig")
	_assert_equal(game.player_orders.objective_label.text, DIG_NEXT, "refresh displays dig with assigned sleeper and unfinished bunk")
	_assert_false("BED SHORTAGE" in game.player_orders.alert_label.text, "assigned sleeper with unfinished bunk does not trigger shortage alert")
	_dispose(game)


func _test_bunk_tired_sleeper_free_capacity() -> void:
	var game := _progression_bunk_game()
	var bunk := _add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(17, 10))
	var sleeper: VaultResident = game.residents[0]
	sleeper.sleeping = true
	sleeper.bed_id = bunk.building_id
	sleeper.needs.rest = 28.0
	_assert_step(game, PLACE_ONE_BUNKS_NEXT, "bed", PLACE_TWO_BUNKS_HELP)
	game.active_tool = "dig"
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "tired sleeper progression placement refresh preserves dig")
	_assert_equal(game.player_orders.objective_label.text, PLACE_ONE_BUNKS_NEXT, "refresh preserves legitimate progression bunk placement")
	_assert_false("BED SHORTAGE" in game.player_orders.alert_label.text, "occupied bunk satisfies tired sleeper during progression")
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(18, 10))
	game.residents[1].needs.rest = 28.0
	_assert_step(game, PROGRESSION_CHARGE_NEXT, "generator", PROGRESSION_CHARGE_HELP)
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "free capacity progression refresh preserves dig")
	_assert_equal(game.player_orders.objective_label.text, PROGRESSION_CHARGE_NEXT, "refresh advances to Charge with enough free bunk capacity")
	_assert_false("BED SHORTAGE" in game.player_orders.alert_label.text, "second completed bunk satisfies awake tired resident beside tired sleeper")
	_dispose(game)


func _admit_tired_medical_patient(game: VaultGame, rest: float) -> VaultBuilding:
	game.food_system.meals = game.get_alive_count()
	var bed := _add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(27, 12))
	var patient: VaultResident = game.residents[0]
	patient.needs.health = 60.0
	patient.needs.rest = rest
	_assert_true(bed.complete and not bed.manually_disabled, "medical fixture is completed and enabled")
	_assert_true(not game.map_grid.find_path(patient.get_cell(game.map_grid), bed.cell).is_empty(), "medical fixture is reachable")
	_assert_true(patient.needs.food > 35.0 and patient.needs.health <= 95.0, "patient meets natural admission gates")
	game.job_system.advance(0.01)
	_assert_equal(patient.medical_bed_id, bed.building_id, "job system reserves medical bed before arrival")
	_assert_equal(patient.state, "Seeking Medical Bed", "patient naturally seeks medical bed before arrival")
	_assert_step(game, BUNK_NEXT, "bed", "Place bunks so tired undrafted crew have a bed.")
	game.player_orders.refresh()
	_assert_true("BED SHORTAGE" in game.player_orders.alert_label.text, "medical reservation while seeking does not exempt tired patient")
	for tick in range(200):
		if patient.state == "Rest-Medical":
			break
		game.job_system.advance(0.1)
	_assert_equal(patient.get_cell(game.map_grid), bed.cell, "patient reaches medical bed through job system movement")
	_assert_equal(patient.state, "Rest-Medical", "job system naturally admits patient to restorative care")
	_assert_equal(patient.medical_bed_id, bed.building_id, "admitted patient retains medical bed assignment")
	_assert_false(patient.sleeping, "medical admission does not fake sleeping")
	_assert_equal(patient.bed_id, -1, "medical patient has no bunk assignment")
	_assert_equal(patient.needs.rest, rest, "admission alone does not change rest")
	return bed


func _assert_medical_rester_dig(game: VaultGame) -> void:
	_assert_step(game, DIG_NEXT, "dig", "DIG [E] designates rock. Undrafted crew auto-claim Dig (default rank 3). Draft is optional.")
	game.active_tool = "dig"
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "medical rester refresh preserves active dig tool")
	_assert_equal(game.player_orders.objective_label.text, DIG_NEXT, "refresh displays dig for medical rester")
	_assert_false("BED SHORTAGE" in game.player_orders.alert_label.text, "medical rester has no unmet bunk shortage")


func _test_bunk_medical_rester_satisfied() -> void:
	# Separate naturally admitted rest-28 boundary from recovery below the threshold.
	for initial_rest in [20.0, 28.0]:
		var game := _healthy_game()
		_admit_tired_medical_patient(game, initial_rest)
		var patient: VaultResident = game.residents[0]
		_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.BED), 0, "medical rester fixture has zero bunks")
		_assert_medical_rester_dig(game)
		if initial_rest < 28.0:
			var previous_rest := patient.needs.rest
			# Use the resident's actual needs path; it derives medical_rest from admission.
			patient.advance_needs(0.01, true, false)
			_assert_true(patient.needs.rest > previous_rest and patient.needs.rest <= 28.0, "medical care restores rest while still below bunk threshold")
			_assert_equal(patient.state, "Rest-Medical", "rest recovery happens during medical care")
			_assert_false(patient.sleeping, "rest recovery keeps medical patient awake")
			_assert_equal(patient.bed_id, -1, "rest recovery consumes no bunk")
			_assert_medical_rester_dig(game)
		_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(20, 12)), "medical rester case places covering unfinished bunk")
		_assert_false(game.get_building_at(Vector2i(20, 12)).complete, "covering bunk stays unfinished")
		_assert_medical_rester_dig(game)
		_dispose(game)


func _test_bunk_medical_rester_free_capacity_and_release() -> void:
	for covering_blueprint in [false, true]:
		var game := _healthy_game()
		var medical_bed := _admit_tired_medical_patient(game, 20.0)
		var patient: VaultResident = game.residents[0]
		game.residents[1].needs.rest = 28.0
		if covering_blueprint:
			_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(20, 12)), "one blueprint covers genuine unmet resident beside patient")
			_assert_step(game, FINISH_BUNK_NEXT, "select", FINISH_BUNK_HELP)
		else:
			_assert_step(game, BUNK_NEXT, "bed", "Place bunks so tired undrafted crew have a bed.")
		game.active_tool = "dig"
		game.player_orders.refresh()
		_assert_equal(game.active_tool, "dig", "genuine unmet need beside medical patient preserves dig")
		_assert_true("BED SHORTAGE" in game.player_orders.alert_label.text, "medical bed is not free bunk capacity for another tired resident")
		_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(21, 12))
		_assert_medical_rester_dig(game)
		# Remove the other resident's need so release tests the patient's own deficit.
		game.residents[1].needs.rest = 100.0
		_assert_true(game.deconstruct_building(game.get_building_at(Vector2i(21, 12)).building_id), "remove free bunk before testing medical release")
		patient.needs.health = 99.0
		game.job_system.advance(0.5)
		_assert_equal(patient.needs.health, 100.0, "medical treatment naturally reaches release threshold")
		_assert_equal(patient.medical_bed_id, -1, "medical recovery releases patient reservation")
		_assert_equal(medical_bed.reserved_by, -1, "medical release frees medical bed")
		_assert_true(patient.needs.rest <= 28.0, "released patient remains tired")
		_assert_false(patient.sleeping, "release has not yet assigned ordinary sleep")
		_assert_equal(patient.bed_id, -1, "released patient still has no bunk")
		if covering_blueprint:
			_assert_step(game, FINISH_BUNK_NEXT, "select", FINISH_BUNK_HELP)
		else:
			_assert_step(game, BUNK_NEXT, "bed", "Place bunks so tired undrafted crew have a bed.")
		game.player_orders.refresh()
		_assert_true("BED SHORTAGE" in game.player_orders.alert_label.text, "medical release restores patient's ordinary bunk shortage")
		_assert_equal(game.active_tool, "dig", "medical release refresh preserves dig")
		_dispose(game)


func _test_bunk_medical_rester_progression() -> void:
	var game := _progression_bunk_game()
	_admit_tired_medical_patient(game, 28.0)
	_assert_step(game, PLACE_TWO_BUNKS_NEXT, "bed", PLACE_TWO_BUNKS_HELP)
	game.active_tool = "dig"
	game.player_orders.refresh()
	_assert_false("BED SHORTAGE" in game.player_orders.alert_label.text, "medical rest preserves progression without unmet bunk alert")
	for cell in [Vector2i(20, 12), Vector2i(21, 12)]:
		_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, cell), "medical progression places legitimate bunk blueprint")
	_assert_step(game, FINISH_BUNK_NEXT, "select", FINISH_BUNK_HELP)
	game.player_orders.refresh()
	_assert_equal(game.player_orders.objective_label.text, FINISH_BUNK_NEXT, "medical rest preserves progression finish recommendation")
	_assert_false("BED SHORTAGE" in game.player_orders.alert_label.text, "progression finish beside patient has no unmet bunk alert")
	for cell in [Vector2i(20, 12), Vector2i(21, 12)]:
		var bunk := game.get_building_at(cell)
		_assert_equal(bunk.add_delivery(bunk.get_cost()), bunk.get_cost(), "medical progression bunk receives salvage")
		_assert_true(bunk.apply_build_work(bunk.get_build_time()), "normal construction finishes medical progression bunk")
	_assert_step(game, PROGRESSION_CHARGE_NEXT, "generator", PROGRESSION_CHARGE_HELP)
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "medical progression refresh preserves dig through completion")
	_assert_false("BED SHORTAGE" in game.player_orders.alert_label.text, "completed medical progression has no bunk shortage")
	_dispose(game)


func _test_bunk_medical_injury_guard() -> void:
	var game := _healthy_game()
	_add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(27, 12))
	var resident: VaultResident = game.residents[0]
	resident.needs.health = 96.0
	resident.needs.rest = 28.0
	_assert_equal(resident.medical_bed_id, -1, "injury alone has no medical reservation")
	_assert_step(game, BUNK_NEXT, "bed", "Place bunks so tired undrafted crew have a bed.")
	game.player_orders.refresh()
	_assert_true("BED SHORTAGE" in game.player_orders.alert_label.text, "injury alone does not exempt ordinary tired resident")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(20, 12)), "injury-only guard has covering bunk blueprint")
	_assert_step(game, FINISH_BUNK_NEXT, "select", FINISH_BUNK_HELP)
	game.player_orders.refresh()
	_assert_true("BED SHORTAGE" in game.player_orders.alert_label.text, "injury alone does not suppress bunk finish shortage")
	_dispose(game)


func _test_bunk_finish_restore() -> void:
	var game := _healthy_game()
	game.residents[0].needs.rest = 28.0
	_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(20, 12)), "bunk blueprint can be placed")
	var bunk := game.get_building_at(Vector2i(20, 12))
	_assert_false(bunk.complete, "bunk blueprint starts unfinished")
	_assert_step(game, FINISH_BUNK_NEXT, "select", FINISH_BUNK_HELP)
	game.active_tool = "dig"
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "bunk finish refresh preserves active dig tool")
	_assert_equal(game.player_orders.objective_label.text, FINISH_BUNK_NEXT, "refresh displays bunk finish")
	_assert_true("BED SHORTAGE" in game.player_orders.alert_label.text, "blueprint leaves bunk shortage alert active")
	_assert_equal(bunk.add_delivery(bunk.get_cost()), bunk.get_cost(), "bunk blueprint receives its salvage cost")
	_assert_true(bunk.apply_build_work(bunk.get_build_time()), "normal construction work completes bunk blueprint")
	_assert_dig(game, "finished free bunk suppresses bunk Next")
	game.player_orders.refresh()
	_assert_false("BED SHORTAGE" in game.player_orders.alert_label.text, "completed free bunk clears shortage alert")
	_assert_equal(game.player_orders.objective_label.text, DIG_NEXT, "refresh clears resolved bunk finish")
	_assert_equal(game.active_tool, "dig", "resolved bunk finish refresh preserves dig")
	_dispose(game)


func _test_bunk_finish_deficit() -> void:
	# Tired crew, free finished bunks, unfinished bunks, expected recommendation.
	for row in [[2, 1, 1, FINISH_BUNK_NEXT], [3, 0, 1, BUNK_NEXT], [3, 0, 2, BUNK_NEXT], [3, 0, 3, FINISH_BUNK_NEXT], [1, 1, 1, DIG_NEXT]]:
		var game := _healthy_game()
		for index in range(row[0]):
			game.residents[index].needs.rest = 28.0
		for index in range(row[1]):
			_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(20 + index, 12))
		for index in range(row[2]):
			_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(23 + index, 12)), "deficit case has real bunk blueprint")
		if row[3] == FINISH_BUNK_NEXT:
			_assert_step(game, FINISH_BUNK_NEXT, "select", FINISH_BUNK_HELP)
		elif row[3] == BUNK_NEXT:
			_assert_step(game, BUNK_NEXT, "bed", "Place bunks so tired undrafted crew have a bed.")
		else:
			_assert_dig(game, "spare blueprint does not interrupt when finished bunks meet need")
		_dispose(game)


func _test_bunk_finish_occupied() -> void:
	for sleeper_rest in [100.0, 28.0]:
		var game := _healthy_game()
		var bunk := _add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(20, 12))
		var sleeper: VaultResident = game.residents[0]
		sleeper.sleeping = true
		sleeper.bed_id = bunk.building_id
		sleeper.needs.rest = sleeper_rest
		game.residents[1].needs.rest = 28.0
		_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(21, 12)), "occupied case has one bunk blueprint")
		_assert_step(game, FINISH_BUNK_NEXT, "select", FINISH_BUNK_HELP)
		game.player_orders.refresh()
		_assert_true("BED SHORTAGE" in game.player_orders.alert_label.text, "one awake tired resident still needs a free completed bunk")
		game.residents[2].needs.rest = 28.0
		_assert_step(game, BUNK_NEXT, "bed", "Place bunks so tired undrafted crew have a bed.")
		game.player_orders.refresh()
		_assert_true("BED SHORTAGE" in game.player_orders.alert_label.text, "two awake tired residents still need free completed bunks")
		_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(22, 12)), "second blueprint covers remaining occupied-bunk shortage")
		_assert_step(game, FINISH_BUNK_NEXT, "select", FINISH_BUNK_HELP)
		game.player_orders.refresh()
		_assert_true("BED SHORTAGE" in game.player_orders.alert_label.text, "covering blueprints leave occupied-bunk shortage alert active")
		_dispose(game)


func _test_bunk_finish_guards() -> void:
	var game := _healthy_game()
	var resident: VaultResident = game.residents[0]
	_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(20, 12)), "guard case has covering bunk blueprint")
	resident.needs.rest = 28.0001
	_assert_dig(game, "rest just above 28 suppresses bunk finish")
	resident.needs.rest = 28.0
	_assert_step(game, FINISH_BUNK_NEXT, "select", FINISH_BUNK_HELP)
	resident.drafted = true
	_assert_dig(game, "drafted tired resident suppresses bunk finish")
	resident.drafted = false
	resident.alive = false
	_assert_dig(game, "dead tired resident suppresses bunk finish")
	resident.alive = true
	resident.needs.rest = 29.0
	resident.sleeping = true
	_assert_equal(resident.bed_id, -1, "floor sleeper has no bunk")
	_assert_step(game, FINISH_BUNK_NEXT, "select", FINISH_BUNK_HELP)
	game.player_orders.refresh()
	_assert_true("BED SHORTAGE" in game.player_orders.alert_label.text, "rest-29 floor sleeper with a blueprint still triggers shortage alert")
	_dispose(game)


func _test_bunk_finish_priority() -> void:
	var game := _healthy_game()
	var resident: VaultResident = game.residents[0]
	resident.needs.rest = 28.0
	_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(20, 12)), "priority case has covering bunk blueprint")
	resident.needs.food = 19.0
	game.food_system.meals = 0
	resident.needs.mood = 9.0
	resident.needs.health = 99.0
	_assert_step(game, KITCHEN_NEXT, "kitchen", "Place and power a Nutrient Station so Cook can turn raw food into meals.")
	resident.needs.food = 100.0
	game.food_system.meals = game.get_alive_count()
	_assert_step(game, REC_NEXT, "rec", "Place a Rec Console so crew can recover mood.")
	resident.needs.mood = 100.0
	_assert_step(game, MED_NEXT, "medical", "Place a Med Bed so the injured can be treated.")
	resident.needs.health = 100.0
	_assert_step(game, FINISH_BUNK_NEXT, "select", FINISH_BUNK_HELP)
	_dispose(game)
	for disabled in [true, false]:
		game = _powered_critical_game()
		resident = game.residents[0]
		resident.needs.rest = 28.0
		resident.needs.mood = 9.0
		resident.needs.health = 99.0
		_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(21, 12)), "offline Rec priority case has bunk blueprint")
		var rec := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(22, 12))
		rec.manually_disabled = disabled
		var kitchen := game.get_building_at(Vector2i(20, 12))
		kitchen.manually_disabled = true
		game.power_grid.recalculate(game.buildings)
		_assert_step(game, POWER_NEXT, "select", "Power the Nutrient Station so Cook can run.")
		kitchen.manually_disabled = false
		game.power_grid.recalculate(game.buildings)
		_assert_offline_rec(game, disabled)
		resident.needs.mood = 100.0
		_assert_step(game, MED_NEXT, "medical", "Place a Med Bed so the injured can be treated.")
		resident.needs.health = 100.0
		_assert_step(game, FINISH_BUNK_NEXT, "select", FINISH_BUNK_HELP)
		_dispose(game)


func _test_bunk_finish_before_food_work() -> void:
	for food_step in ["haul", "enable_cook", "cook", "grow"]:
		var game := _powered_critical_game()
		game.residents[0].needs.rest = 28.0
		var expected := COOK_NEXT
		var help := COOK_HELP
		var tool := "select"
		match food_step:
			"haul":
				game.job_system.queue_meals(Vector2i(20, 12), 2)
				for crew: VaultResident in game.residents:
					crew.set_work_priority("haul", VaultResident.PRIORITY_DISABLED)
					crew.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
				expected = ENABLE_HAUL_NEXT
				help = ENABLE_HAUL_HELP
			"enable_cook":
				for crew: VaultResident in game.residents:
					crew.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
				expected = ENABLE_COOK_NEXT
				help = ENABLE_COOK_HELP
			"grow":
				game.food_system.raw_food = 0
				expected = GROW_NEXT
				help = GROW_HELP
				tool = "grow"
		_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(21, 12)), "food priority case has covering bunk blueprint")
		var bunk := game.get_building_at(Vector2i(21, 12))
		_assert_step(game, FINISH_BUNK_NEXT, "select", FINISH_BUNK_HELP)
		_assert_equal(bunk.add_delivery(bunk.get_cost()), bunk.get_cost(), "food priority bunk receives salvage")
		_assert_true(bunk.apply_build_work(bunk.get_build_time()), "real construction resolves bunk shortage before food work")
		_assert_step(game, expected, tool, help)
		_dispose(game)


func _test_progression_bunk_deficit() -> void:
	# Completed bunks, unfinished bunks, expected recommendation.
	for row in [[0, 0, PLACE_TWO_BUNKS_NEXT], [0, 1, PLACE_ONE_BUNKS_NEXT], [1, 0, PLACE_ONE_BUNKS_NEXT], [0, 2, FINISH_BUNK_NEXT], [1, 1, FINISH_BUNK_NEXT], [0, 3, FINISH_BUNK_NEXT], [2, 0, PROGRESSION_CHARGE_NEXT], [2, 1, PROGRESSION_CHARGE_NEXT]]:
		var game := _progression_bunk_game()
		for index in range(row[0]):
			_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(17 + index, 10))
		for index in range(row[1]):
			_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(20 + index, 10)), "progression deficit case places a real bunk blueprint")
		match row[2]:
			PLACE_ONE_BUNKS_NEXT, PLACE_TWO_BUNKS_NEXT:
				_assert_step(game, row[2], "bed", PLACE_TWO_BUNKS_HELP)
			FINISH_BUNK_NEXT:
				_assert_step(game, FINISH_BUNK_NEXT, "select", FINISH_BUNK_HELP)
			PROGRESSION_CHARGE_NEXT:
				_assert_step(game, PROGRESSION_CHARGE_NEXT, "generator", PROGRESSION_CHARGE_HELP)
		_dispose(game)


func _test_progression_bunk_finish_restore() -> void:
	var game := _progression_bunk_game()
	for cell in [Vector2i(17, 10), Vector2i(18, 10)]:
		_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, cell), "progression restore places a real bunk blueprint")
	_assert_step(game, FINISH_BUNK_NEXT, "select", FINISH_BUNK_HELP)
	game.active_tool = "dig"
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "progression finish refresh preserves dig")
	_assert_equal(game.player_orders.objective_label.text, FINISH_BUNK_NEXT, "refresh displays progression bunk finish")
	_assert_false("BED SHORTAGE" in game.player_orders.alert_label.text, "healthy progression finish has no bunk shortage alert")
	game.player_orders._refresh_checklist()
	_assert_true("[    ][/color]  Assemble at least 2 bunks" in game.player_orders.checklist.text, "two blueprints leave bunk checklist incomplete")
	var first := game.get_building_at(Vector2i(17, 10))
	_assert_equal(first.add_delivery(first.get_cost()), first.get_cost(), "first progression bunk receives salvage")
	_assert_true(first.apply_build_work(first.get_build_time()), "real construction completes first progression bunk")
	_assert_step(game, FINISH_BUNK_NEXT, "select", FINISH_BUNK_HELP)
	game.player_orders._refresh_checklist()
	_assert_true("[    ][/color]  Assemble at least 2 bunks" in game.player_orders.checklist.text, "one completed bunk leaves checklist incomplete")
	var second := game.get_building_at(Vector2i(18, 10))
	_assert_equal(second.add_delivery(second.get_cost()), second.get_cost(), "second progression bunk receives salvage")
	_assert_true(second.apply_build_work(second.get_build_time()), "real construction completes second progression bunk")
	_assert_step(game, PROGRESSION_CHARGE_NEXT, "generator", PROGRESSION_CHARGE_HELP)
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "completed progression bunks preserve dig")
	_assert_equal(game.player_orders.objective_label.text, PROGRESSION_CHARGE_NEXT, "refresh advances to progression Charge")
	game.player_orders._refresh_checklist()
	_assert_true("[DONE][/color]  Assemble at least 2 bunks" in game.player_orders.checklist.text, "two completed bunks complete checklist")
	_dispose(game)


func _test_progression_bunk_dig_priority() -> void:
	var game := _healthy_game()
	game.food_system.meals = game.get_alive_count()
	for x in range(17, 28):
		var cell := Vector2i(x, 10)
		_assert_true(game.map_grid.queue_dig(cell), "dig priority case queues connected rock")
		_assert_true(game.map_grid.apply_dig_work(cell, 8.0), "dig priority case carves floor")
	_assert_equal(game.map_grid.get_floor_cells().size(), 131, "eleven carved cells leave floor gate incomplete")
	for cell in [Vector2i(17, 10), Vector2i(18, 10)]:
		_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, cell), "dig priority case has covering bunk blueprints")
	_assert_dig(game, "floor gate beats progression bunk finish")
	_assert_true(game.map_grid.queue_dig(Vector2i(28, 10)), "twelfth cell can be queued")
	_assert_true(game.map_grid.apply_dig_work(Vector2i(28, 10), 8.0), "twelfth cell completes floor gate")
	_assert_equal(game.map_grid.get_floor_cells().size(), 132, "twelve carved cells clear floor gate")
	_assert_step(game, FINISH_BUNK_NEXT, "select", FINISH_BUNK_HELP)
	_dispose(game)


func _test_progression_bunk_crisis_priority() -> void:
	var game := _progression_bunk_game()
	for cell in [Vector2i(17, 10), Vector2i(18, 10)]:
		_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, cell), "crisis priority case has covering bunk blueprints")
	game.residents[0].needs.rest = 28.0
	_assert_step(game, FINISH_BUNK_NEXT, "select", FINISH_BUNK_HELP)
	game.player_orders.refresh()
	_assert_true("BED SHORTAGE" in game.player_orders.alert_label.text, "tired resident triggers crisis shortage despite covering blueprints")
	game.residents[0].needs.rest = 100.0
	_assert_step(game, FINISH_BUNK_NEXT, "select", FINISH_BUNK_HELP)
	game.player_orders.refresh()
	_assert_false("BED SHORTAGE" in game.player_orders.alert_label.text, "restored rest leaves progression finish without crisis alert")
	_dispose(game)


func _test_progression_bunk_after_food_work() -> void:
	var game := _powered_critical_game()
	for x in range(17, 29):
		var cell := Vector2i(x, 10)
		_assert_true(game.map_grid.queue_dig(cell), "food priority case queues connected rock")
		_assert_true(game.map_grid.apply_dig_work(cell, 8.0), "food priority case carves floor")
	_assert_equal(game.map_grid.get_floor_cells().size(), 132, "food priority case clears floor gate")
	for cell in [Vector2i(17, 10), Vector2i(18, 10)]:
		_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, cell), "food priority case has covering progression bunk blueprints")
	_assert_step(game, COOK_NEXT, "select", COOK_HELP)
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
	game.food_system.meals = game.get_alive_count()
	_assert_step(game, FINISH_BUNK_NEXT, "select", FINISH_BUNK_HELP)
	_dispose(game)


func _test_living_residents_only() -> void:
	var game := _healthy_game()
	var resident: VaultResident = game.residents[0]
	resident.alive = false
	resident.needs.food = 0.0
	resident.needs.rest = 0.0
	resident.needs.mood = 0.0
	resident.needs.health = 0.0
	game.food_system.meals = 0
	_assert_dig(game, "dead residents do not trigger survival interrupts")
	_dispose(game)


func _test_charge_finish_restore() -> void:
	for context in ["kitchen", "rec", "grow", "progression"]:
		for existing_charge in [false, true]:
			if context == "progression" and existing_charge:
				continue
			var game := _healthy_game()
			var consumer: VaultBuilding
			var place_next := PROGRESSION_CHARGE_NEXT
			var place_help := PROGRESSION_CHARGE_HELP
			var resumed_next := DIG_NEXT
			var resumed_help := "DIG [E] designates rock. Undrafted crew auto-claim Dig (default rank 3). Draft is optional."
			var resumed_tool := "dig"
			if existing_charge:
				_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(26, 12))
			match context:
				"kitchen":
					game.residents[0].needs.food = 19.0
					game.food_system.meals = 0
					consumer = _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
					place_next = CHARGE_NEXT
					place_help = CHARGE_HELP
					resumed_next = COOK_NEXT
					resumed_help = COOK_HELP
					resumed_tool = "select"
				"rec":
					game.residents[0].needs.mood = 9.0
					consumer = _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(20, 12))
					_add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(21, 12))
					place_next = REC_CHARGE_NEXT
					place_help = REC_CHARGE_HELP
				"grow":
					game.residents[0].needs.food = 19.0
					game.food_system.meals = 0
					game.food_system.raw_food = 0
					_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
					consumer = _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(21, 12))
					for building: VaultBuilding in game.buildings:
						if building.kind == VaultBuilding.Kind.LAMP:
							building.manually_disabled = true
					place_next = GROW_CHARGE_NEXT
					place_help = GROW_CHARGE_HELP
					resumed_next = COOK_NEXT
					resumed_help = WAITING_COOK_HELP
					resumed_tool = "select"
				"progression":
					_dispose(game)
					game = _progression_bunk_game()
					_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(20, 12))
					_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(21, 12))
					resumed_next = "Next: YOU place Grow Tray · THEY haul output"
					resumed_help = "Designate GROW and keep it powered. Haul defaults move raw food to stock."
					resumed_tool = "grow"
			if existing_charge:
				# Consume nine power for Kitchen/Rec, six for Grow so Kitchen stays powered.
				for index in (2 if context == "grow" else 3):
					_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(22 + index, 12))
			game.power_grid.recalculate(game.buildings)
			if consumer != null:
				_assert_true(game.power_grid.is_building_shed(consumer.building_id), "%s consumer genuinely shed, existing Charge=%s" % [context, existing_charge])
			if context == "grow":
				_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.KITCHEN), 1, "Grow shortage keeps Kitchen powered")
			_assert_step(game, place_next, "generator", place_help)
			# An unfinished Emergency Core must never stand in for a Charge blueprint.
			var core: VaultBuilding
			for building: VaultBuilding in game.buildings:
				if building.is_emergency_core:
					core = building
			core.complete = false
			_assert_step(game, place_next, "generator", place_help)
			core.complete = true
			var cell := Vector2i(25, 12)
			_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, cell), "%s Charge blueprint placed" % context)
			var charge := game.get_building_at(cell)
			_assert_equal(charge.delivered, 0, "Charge starts unsupplied")
			var funded_stock := game.food_system.salvage
			game.food_system.salvage = 0
			_assert_salvage_tip(game, 18, 0 if context == "progression" else 6)
			charge.delivered = charge.get_cost()
			_assert_step(game, FINISH_CHARGE_NEXT, "select", FINISH_CHARGE_HELP)
			charge.delivered = 0
			game.food_system.salvage = funded_stock
			_assert_step(game, FINISH_CHARGE_NEXT, "select", FINISH_CHARGE_HELP)
			game.active_tool = "dig"
			game.player_orders.refresh()
			_assert_equal(game.active_tool, "dig", "Charge finish refresh preserves active tool")
			_assert_equal(game.player_orders.objective_label.text, FINISH_CHARGE_NEXT, "refresh shows Charge finish")
			if consumer != null:
				consumer.manually_disabled = true
				game.power_grid.recalculate(game.buildings)
				match context:
					"kitchen":
						_assert_step(game, POWER_NEXT, "select", "Power the Nutrient Station so Cook can run.")
					"rec":
						_assert_step(game, ENABLE_REC_NEXT, "select", ENABLE_REC_HELP)
					"grow":
						_assert_step(game, ENABLE_GROW_NEXT, "select", ENABLE_GROW_HELP)
				consumer.manually_disabled = false
				game.power_grid.recalculate(game.buildings)
			_assert_equal(charge.add_delivery(charge.get_cost()), 18, "Charge receives full salvage cost")
			_assert_false(charge.complete, "supplied Charge remains unfinished")
			_assert_step(game, FINISH_CHARGE_NEXT, "select", FINISH_CHARGE_HELP)
			game.active_tool = "cancel"
			_assert_true(game.issue_order(cell), "cancel last unfinished Charge")
			_assert_step(game, place_next, "generator", place_help)
			_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, cell), "replace canceled Charge")
			charge = game.get_building_at(cell)
			_assert_equal(charge.add_delivery(charge.get_cost()), 18, "replacement Charge supplied")
			_assert_true(charge.apply_build_work(charge.get_build_time()), "construction completes Charge")
			game.power_grid.recalculate(game.buildings)
			_assert_step(game, resumed_next, resumed_tool, resumed_help)
			_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.GENERATOR, true), 2 if existing_charge else 1, "completed non-Core count")
			_dispose(game)


func _test_charge_finish_priority() -> void:
	var game := _healthy_game()
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(25, 12)), "priority fixture retains unfinished Charge")
	_assert_dig(game, "dig progression precedes Charge finish")
	game.residents[0].needs.food = 19.0
	game.food_system.meals = 0
	_assert_step(game, KITCHEN_NEXT, "kitchen", "Place and power a Nutrient Station so Cook can turn raw food into meals.")
	game.residents[0].needs.food = 100.0
	game.residents[0].needs.mood = 9.0
	_assert_step(game, REC_NEXT, "rec", "Place a Rec Console so crew can recover mood.")
	game.residents[0].needs.mood = 100.0
	game.residents[0].needs.health = 99.0
	_assert_step(game, MED_NEXT, "medical", "Place a Med Bed so the injured can be treated.")
	game.residents[0].needs.health = 100.0
	game.residents[0].needs.rest = 28.0
	_assert_step(game, BUNK_NEXT, "bed", "Place bunks so tired undrafted crew have a bed.")
	_dispose(game)


func _air_ready_game() -> VaultGame:
	var game := _progression_bunk_game()
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(20, 12))
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(21, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(22, 12))
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12))
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(24, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.GROW_TRAY), 1, "Air fixture has powered Grow")
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.KITCHEN), 1, "Air fixture has powered Kitchen")
	return game


func _assert_air_fallthrough(game: VaultGame) -> void:
	_assert_step(game, "Next: YOU watch hatch · THEY auto-patch", "select", "When the hatch warns, undrafted Haul + Craft claim supply/patch without draft.")


func _test_air_finish_restore() -> void:
	var game := _air_ready_game()
	_assert_step(game, PLACE_AIR, "air", PLACE_AIR_HELP)
	var cell := Vector2i(25, 12)
	_assert_true(game.place_blueprint(VaultBuilding.Kind.AIR_RECYCLER, cell), "real Air blueprint placed")
	var air := game.get_building_at(cell)
	_assert_equal(air.delivered, 0, "Air starts unsupplied")
	_assert_step(game, FINISH_AIR, "select", FINISH_AIR_HELP)
	game.active_tool = "dig"
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "Air finish refresh preserves active tool")
	_assert_equal(game.player_orders.objective_label.text, FINISH_AIR, "refresh displays exact Air finish")
	_assert_equal(air.add_delivery(5), 5, "Air partially supplied")
	_assert_step(game, FINISH_AIR, "select", FINISH_AIR_HELP)
	_assert_equal(air.add_delivery(air.get_cost()), 9, "Air receives remaining salvage")
	_assert_true(air.is_supplied() and not air.complete, "supplied Air still unfinished")
	_assert_step(game, FINISH_AIR, "select", FINISH_AIR_HELP)
	game.active_tool = "cancel"
	_assert_true(game.issue_order(cell), "cancel last unfinished Air")
	_assert_equal(game.get_building_at(cell), null, "canceled Air removed")
	_assert_step(game, PLACE_AIR, "air", PLACE_AIR_HELP)
	_assert_true(game.place_blueprint(VaultBuilding.Kind.AIR_RECYCLER, cell), "replacement Air placed")
	air = game.get_building_at(cell)
	_assert_equal(air.add_delivery(air.get_cost()), 14, "replacement Air supplied")
	_assert_true(air.apply_build_work(air.get_build_time()), "ordinary work completes Air")
	game.power_grid.recalculate(game.buildings)
	_assert_true(air.powered, "completed Air powered by actual grid")
	_assert_air_fallthrough(game)
	_dispose(game)


func _test_air_mixtures() -> void:
	var game := _air_ready_game()
	var air := _add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(25, 12))
	air.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, ENABLE_AIR, "select", ENABLE_AIR_HELP)
	_assert_true(game.place_blueprint(VaultBuilding.Kind.AIR_RECYCLER, Vector2i(26, 12)), "disabled Air has unfinished spare")
	_assert_step(game, ENABLE_AIR, "select", ENABLE_AIR_HELP)
	var disabled_spare := _add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(27, 12))
	disabled_spare.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, ENABLE_AIR, "select", ENABLE_AIR_HELP)
	game.active_tool = "dig"
	game.player_orders.refresh()
	_assert_equal(game.active_tool, "dig", "Air enable refresh preserves active tool")
	_assert_equal(game.player_orders.objective_label.text, ENABLE_AIR, "refresh displays exact Air enable")
	_assert_true(game.toggle_building_enabled(air.building_id), "real enable restores Air")
	game.power_grid.recalculate(game.buildings)
	_assert_true(air.powered, "enabled Air powered beside disabled and unfinished spares")
	_assert_air_fallthrough(game)
	# Completing/enabling Air does not promise Day-7: food retains precedence.
	var grow := game.get_building_at(Vector2i(23, 12))
	grow.manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, "Next: YOU power food chain · THEY cook/haul alone", "select", "Enable Grow + Nutrient power. Keep Cook/Haul above OFF so defaults keep working.")
	grow.manually_disabled = false
	game.power_grid.recalculate(game.buildings)
	_assert_air_fallthrough(game)
	# Air is the highest allocator priority: genuine Air shedding also sheds
	# food, so the earlier food gate owns that state. Never fabricate .powered.
	_assert_true(game.toggle_building_enabled(disabled_spare.building_id), "enable second completed Air")
	var third := _add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(28, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_true(third.powered, "actual allocator spends nine supply on three Air")
	_assert_true(game.power_grid.is_building_shed(game.get_building_at(Vector2i(23, 12)).building_id), "actual Air load sheds Grow")
	var fourth := _add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(29, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_true(game.power_grid.is_building_shed(fourth.building_id), "fourth completed enabled Air genuinely shed")
	_assert_step(game, FOOD_CHARGE_NEXT, "generator", FOOD_CHARGE_HELP)
	_dispose(game)


func _test_air_priority() -> void:
	var game := _healthy_game()
	_assert_true(game.place_blueprint(VaultBuilding.Kind.AIR_RECYCLER, Vector2i(25, 12)), "unfinished Air retained across priorities")
	_assert_dig(game, "Dig gate precedes Air finish")
	game.residents[0].needs.food = 19.0
	game.food_system.meals = 0
	_assert_step(game, KITCHEN_NEXT, "kitchen", "Place and power a Nutrient Station so Cook can turn raw food into meals.")
	game.residents[0].needs.food = 100.0
	game.food_system.meals = game.get_alive_count()
	game.residents[0].needs.mood = 9.0
	_assert_step(game, REC_NEXT, "rec", "Place a Rec Console so crew can recover mood.")
	game.residents[0].needs.mood = 100.0
	game.residents[0].needs.health = 99.0
	_assert_step(game, MED_NEXT, "medical", "Place a Med Bed so the injured can be treated.")
	game.residents[0].needs.health = 100.0
	for x in range(17, 29):
		var cell := Vector2i(x, 10)
		_assert_true(game.map_grid.queue_dig(cell), "Air priority fixture queues rock")
		_assert_true(game.map_grid.apply_dig_work(cell, 8.0), "Air priority fixture carves floor")
	_assert_step(game, PLACE_TWO_BUNKS_NEXT, "bed", PLACE_TWO_BUNKS_HELP)
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(20, 12))
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(21, 12))
	_assert_step(game, PROGRESSION_CHARGE_NEXT, "generator", PROGRESSION_CHARGE_HELP)
	_assert_true(game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(22, 12)), "unfinished Charge before Air")
	_assert_step(game, FINISH_CHARGE_NEXT, "select", FINISH_CHARGE_HELP)
	var charge := game.get_building_at(Vector2i(22, 12))
	charge.add_delivery(charge.get_cost())
	_assert_true(charge.apply_build_work(charge.get_build_time()), "Charge construction clears earlier gate")
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, "Next: YOU place Grow Tray · THEY haul output", "grow", "Designate GROW and keep it powered. Haul defaults move raw food to stock.")
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, "Next: YOU place Nutrient Station · THEY cook/haul", "kitchen", "Designate NUTRI, power it, leave Cook + Haul above OFF.")
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(24, 12))
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, FINISH_AIR, "select", FINISH_AIR_HELP)
	game.get_building_at(Vector2i(23, 12)).manually_disabled = true
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, "Next: YOU power food chain · THEY cook/haul alone", "select", "Enable Grow + Nutrient power. Keep Cook/Haul above OFF so defaults keep working.")
	_dispose(game)


func _assert_salvage_tip(game: VaultGame, shortfall: int, tiles: int) -> void:
	_assert_step(game,
		"Next: YOU mark %d rock [E] · THEY fund the Charge Node" % tiles if tiles > 0 else "Next: YOU leave Dig + Haul on · THEY fund the Charge Node",
		"dig" if tiles > 0 else "select",
		"The Charge Node blueprint is %d salvage short. Each dug rock tile yields %d salvage once hauled." % [shortfall, PlayerOrders.DIG_SALVAGE_YIELD])
