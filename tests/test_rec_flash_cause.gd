extends "res://tests/test_runner.gd"
# Rec flash on 03 s4242 at 81.6 s: right after the seal, the salvage nudge turned
# the crew's real next action ("place bunks") into "spend 8: build Rec Console";
# 2.6 s later the bunks went down and the chain named its own next build (Air).
# A salvage nudge no longer overwrites a needed bunk step; urgent needs still do.

const SPEND_REC := "Next: YOU spend 8: build Rec Console · THEY craft"


func _run() -> void:
	_run_case("needed bunks stay Next instead of a Rec nudge", _test_bunks_stay)
	_run_case("placing the bunks moves Next on without a Rec flash", _test_bunks_then_next)
	_run_case("with beds covered the idle Rec nudge still shows", _test_nudge_without_bunks)
	_run_case("a breaking crew still gets its Rec step over the bunks", _test_breaking_rec)
	_run_case("Spend follows Next: no Rec offer while bunks are Next", _test_spend_follows_bunks)
	_run_case("with beds covered Spend still offers the Rec", _test_spend_rec_without_bunks)
	print("REC FLASH CAUSE: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


# 03 s4242 at 81.6 s: the real hatch just sealed, crew idle and fed, no bunks,
# no Air Recycler, 8 salvage (Rec, not Air), no Rec yet.
func _plateau(bunks := false, air := false) -> VaultGame:
	var game := _spawn_game()
	game.new_game(false, 4242, 5)
	game.begin_shift()
	game.user_paused = true
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
		resident.drafted = false
		resident.sleeping = false
		resident.bed_id = -1
		resident.medical_bed_id = -1
		resident.state = "Idle"
	game.food_system.meals = 100
	game.food_system.raw_food = 0
	for x in range(17, 29):
		var cell := Vector2i(x, 10)
		game.map_grid.queue_dig(cell)
		game.map_grid.apply_dig_work(cell, 8.0)
	game.job_system.jobs = game.job_system.jobs.filter(func(job: Dictionary) -> bool:
		return int(job.type) not in [JobSystem.JobType.DIG, JobSystem.JobType.HAUL_RUBBLE])
	if bunks:
		_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(20, 12))
		_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(21, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(22, 12))
	var tray := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12))
	tray.upgrade_tier = VaultBuilding.UPGRADE_TIER_MAX
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(24, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(26, 12))
	if air:
		_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(25, 12))
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	game.breach_system.advance(0.0, game.breach_system.warning_at)
	game.breach_system.add_delivery(BreachSystem.PATCH_COST)
	game.breach_system.apply_patch_work(BreachSystem.PATCH_WORK_SECONDS)
	game.player_orders.show_breach_warning(false)
	_assert_true(game.breach_system.is_sealed(), "fixture seals the real level-05 hatch")
	game.food_system.salvage = 8
	return game


func _next(game: VaultGame) -> String:
	# Hold the state for the full idle window, as the live game does.
	game.player_orders.refresh()
	game.day_cycle.elapsed_seconds += 3.0
	game.player_orders.refresh()
	return game.player_orders.objective_label.text


func _test_bunks_stay() -> void:
	var game := _plateau()
	var text := _next(game)
	_assert_true(text.begins_with("Next: YOU place ") and "bunk" in text, "the bunks the crew need stay the shown Next (%s)" % text)
	_assert_false(text.begins_with("Next: YOU spend "), "stored salvage does not nudge over the bunks (%s)" % text)
	_dispose(game)


func _test_bunks_then_next() -> void:
	var game := _plateau()
	var seen: Array[String] = [_next(game)]
	var placed := 0
	for cell: Vector2i in [Vector2i(16, 16), Vector2i(17, 16), Vector2i(18, 16), Vector2i(16, 17), Vector2i(17, 17), Vector2i(18, 17)]:
		if game.place_blueprint(VaultBuilding.Kind.BED, cell):
			placed += 1
		seen.append(_next(game))
	print("REC SEQ placed=%d %s" % [placed, str(seen)])
	_assert_true(placed > 0, "bunk blueprints go down")
	_assert_false(SPEND_REC in seen, "Rec never flashes while the bunks are the next action (%s)" % str(seen))
	_assert_false("bunk" in seen[-1].get_slice(" · ", 0), "after placing the bunks Next moves on (%s)" % seen[-1])
	_dispose(game)


func _test_nudge_without_bunks() -> void:
	var game := _plateau(true, true)
	_assert_equal(_next(game), SPEND_REC, "idle crew with beds covered still turn salvage into Rec")
	_dispose(game)


func _test_breaking_rec() -> void:
	var game := _plateau()
	game.residents[1].needs.mood = 5.0
	var text := _next(game)
	_assert_true(text.begins_with("Next: YOU place a Rec Console"), "a breaking resident's Rec step outranks the bunks (%s)" % text)
	_dispose(game)


func _spend_text(game: VaultGame) -> String:
	var button: Button = game.player_orders.upgrade_offer_button
	return button.text if button.visible else ""


func _test_spend_follows_bunks() -> void:
	var game := _plateau()
	var text := _next(game)
	var spend := _spend_text(game)
	_assert_true(text.begins_with("Next: YOU place ") and "bunk" in text, "Next shows the needed bunks (%s)" % text)
	_assert_false("Rec Console" in spend, "Spend does not offer the Rec Console while Next says place bunks (%s)" % spend)
	_dispose(game)


func _test_spend_rec_without_bunks() -> void:
	var game := _plateau(true, true)
	_next(game)
	_assert_equal(_spend_text(game), "Spend 8: build Rec Console", "beds covered: Spend still offers the Rec Console")
	_dispose(game)
