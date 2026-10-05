extends "res://tests/test_runner.gd"

const DIG_NEXT := "Next: YOU mark rock [E] · THEY dig on Dig defaults"
const KITCHEN_NEXT := "Next: YOU place a Nutrient Station · THEY cook"
const POWER_NEXT := "Next: YOU power the Nutrient Station · THEY cook"
const CHARGE_NEXT := "Next: YOU place a Charge Node · THEY power the kitchen"
const CHARGE_HELP := "The grid lacks available power for the Nutrient Station. Place a Charge Node to add 7 power."
const REC_NEXT := "Next: YOU place a Rec Console · THEY recover mood"
const MED_NEXT := "Next: YOU place a Med Bed · THEY treat"
const BUNK_NEXT := "Next: YOU place bunks · THEY craft"
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
const GROW_CHARGE_HELP := "The grid lacks available power for the Grow Tray. Place a Charge Node to add 7 power."


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_interrupts_and_priority()
	_test_kitchen_guards()
	_test_enabled_kitchen_shed()
	_test_disabled_kitchens()
	_test_mixed_kitchen_power()
	_test_unfinished_kitchens()
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
	_test_medical_availability()
	_test_bunk_shortage()
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
	var unfinished := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(21, 12))
	unfinished.complete = false
	game.power_grid.recalculate(game.buildings)
	_assert_step(game, POWER_NEXT, "select", "Power the Nutrient Station so Cook can run.")
	completed.complete = false
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.KITCHEN), 0, "unfinished kitchens do not count as completed")
	_assert_step(game, KITCHEN_NEXT, "kitchen", "Place and power a Nutrient Station so Cook can turn raw food into meals.")
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


func _test_medical_availability() -> void:
	var game := _healthy_game()
	var resident: VaultResident = game.residents[0]
	resident.needs.health = 99.0
	var bed := _add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(20, 12))
	bed.complete = true
	bed.manually_disabled = false
	bed.reserved_by = -1
	_assert_dig(game, "free usable medical bed avoids the medical interrupt")
	bed.complete = false
	_assert_equal(game.player_orders._primary_next_step()["text"], MED_NEXT, "unfinished medical bed is not usable")
	bed.complete = true
	bed.manually_disabled = true
	_assert_equal(game.player_orders._primary_next_step()["text"], MED_NEXT, "disabled medical bed is not usable")
	bed.manually_disabled = false
	bed.reserved_by = resident.resident_id
	_assert_equal(game.player_orders._primary_next_step()["text"], MED_NEXT, "reserved medical bed is not free")
	resident.medical_bed_id = bed.building_id
	_assert_dig(game, "only injured resident already reserved does not request a med bed")
	game.residents[1].needs.health = 99.0
	_assert_equal(game.player_orders._primary_next_step()["text"], MED_NEXT, "another unreserved injured resident still needs a med bed")
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
	resident.sleeping = false
	resident.needs.rest = 28.0
	var bunk := _add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(20, 12))
	_assert_dig(game, "one free completed bunk satisfies one tired resident")
	bunk.complete = false
	_assert_equal(game.player_orders._primary_next_step()["text"], BUNK_NEXT, "unfinished bunk does not count as free")
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
