extends "res://tests/test_runner.gd"

const PLACE_BUNKS := "Next: Ari exhausted · YOU place bunks · THEY craft"
const PLACE_CHARGE := "Next: YOU place a Charge Node · THEY supply/build"
const FINISH_CHARGE := "Next: YOU leave Haul + Craft on · THEY finish the Charge Node"
const PLACE_REC := "Next: Ari in despair · YOU place a Rec Console · THEY recover mood"


func _run() -> void:
	_run_case("Next skips queued bunks and continues the normal build chain", _test_next_queued_bunks_drop_out)
	_run_case("Next skips queued Rec and preserves queued Charge construction advice", _test_next_queued_other_builds_drop_out)
	_run_case("Next text and urgency metadata stay unchanged with no queued build", _test_next_nothing_queued_unchanged)
	_run_case("Next can suppress more than one queued build in chain order", _test_next_multiple_queued_builds)
	_run_case("Next falls back to queued construction when the chain is otherwise covered", _test_next_queued_only_fallback)
	_run_case("Next keeps saving-tip actions clean and does not remember suppressed urgency", _test_next_urgency_recap)
	_run_case("Next skips a queued extra Air Recycler during a short suffocation runway", _test_next_queued_extra_air)
	print("ALERT TRIAGE TESTS: %s — %d cases, %d assertions, %d failures" % [
		"FAIL" if _failure_count else "PASS", _case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _next_chain_game() -> VaultGame:
	var game := _spawn_game()
	game.new_game(false, 4242, 5)
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
	game.food_system.meals = 24
	# Rest and mood death warnings need low HP. An available real Med Bed
	# leaves the subsequent recommendation on the ordinary build chain.
	_add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(20, 12))
	# Clear the real twelve-tile Dig gate, as in test_survival_next.gd.
	for x in range(17, 29):
		var cell := Vector2i(x, 10)
		game.map_grid.queue_dig(cell)
		game.map_grid.apply_dig_work(cell, 8.0)
	return game


func _test_next_queued_bunks_drop_out() -> void:
	var game := _next_chain_game()
	var ari: VaultResident = game.residents[0]
	ari.needs.rest = 0.0
	ari.needs.health = 40.0
	game.player_orders.refresh()
	var before := game.player_orders.objective_label.text
	var had_no_bunks := game.get_completed_building_count(VaultBuilding.Kind.BED) == 0
	var placed := game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(18, 12))
	var bunk := game.get_building_at(Vector2i(18, 12))
	var step: Dictionary = game.player_orders._refresh_objective()
	var next := game.player_orders.objective_label.text
	# Combine the before-state proof with the changed result: every assertion
	# in the regression cases fails against the original repeated-placement bug.
	_assert_true(before == PLACE_BUNKS and had_no_bunks and placed and bunk != null and not bunk.complete
		and "place bunks" not in next and "place 1 bunk" not in next and "place 2 bunks" not in next,
		"real exhausted crew need bunks before placement, then no second bunk placement is suggested: %s -> %s" % [before, next])
	_assert_true("bunks in progress" in next,
		"the replacement Next acknowledges the queued bunks: %s" % next)
	_assert_equal(step.get("in_progress", []), ["bunks"], "queued bunks are exposed as structured in-progress names")
	_assert_equal(next, PLACE_CHARGE + " · bunks in progress",
		"skipping the queued bunk requirement reaches the following Charge Node chain link")
	_assert_true(str(step.get("tool", "")) == "generator" and "bunks in progress" in next,
		"the displayed replacement highlights the next build tool")
	_dispose(game)


func _test_next_queued_other_builds_drop_out() -> void:
	var game := _next_chain_game()
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(21, 12))
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(22, 12))
	var ari: VaultResident = game.residents[0]
	ari.needs.rest = 0.0
	ari.needs.health = 40.0
	game.player_orders.refresh()
	var before := game.player_orders.objective_label.text
	var placed_bunk := game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(18, 12))
	var next_charge: Dictionary = game.player_orders._refresh_objective()
	_assert_true(before == PLACE_BUNKS and placed_bunk
		and str(next_charge.get("text", "")) == PLACE_CHARGE + " · bunks in progress",
		"queued rest recovery exposes the next real Charge Node placement")
	var placed_charge := game.place_blueprint(VaultBuilding.Kind.GENERATOR, Vector2i(19, 12))
	var charge := game.get_building_at(Vector2i(19, 12))
	var step: Dictionary = game.player_orders._refresh_objective()
	var next := game.player_orders.objective_label.text
	_assert_true(placed_charge and charge != null and not charge.complete and "place a Charge Node" not in next
		and next == FINISH_CHARGE + " · bunks in progress",
		"a queued Charge Node keeps the established Haul + Craft finish action: %s" % next)
	_assert_true(str(step.get("tool", "")) == "select" and step.get("in_progress", []) == ["bunks"],
		"Charge finish advice uses Select and only records the actually suppressed bunk placement")
	_dispose(game)

	game = _next_chain_game()
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(21, 12))
	_add_completed_building(game, VaultBuilding.Kind.BED, Vector2i(22, 12))
	ari = game.residents[0]
	ari.needs.mood = 0.0
	ari.needs.health = 5.0
	game.player_orders.refresh()
	before = game.player_orders.objective_label.text
	var placed_rec := game.place_blueprint(VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(18, 12))
	var rec := game.get_building_at(Vector2i(18, 12))
	step = game.player_orders._refresh_objective()
	next = game.player_orders.objective_label.text
	_assert_true(before == PLACE_REC and placed_rec and rec != null and not rec.complete
		and "place a Rec Console" not in next and "Rec Consoles in progress" in next,
		"real despair urgency stops repeating Rec placement after its blueprint is queued: %s -> %s" % [before, next])
	_assert_equal(step.get("in_progress", []), ["Rec Consoles"], "queued Rec Consoles use the same structured suppression mechanism")
	_assert_equal(next, PLACE_CHARGE + " · Rec Consoles in progress",
		"the suppressed Rec requirement falls through to the next normal chain link")
	_dispose(game)


func _test_next_nothing_queued_unchanged() -> void:
	var game := _spawn_game()
	game.new_game(false, 4242, 5)
	game.begin_shift()
	var step: Dictionary = game.player_orders._refresh_objective()
	_assert_equal(game.player_orders.objective_label.text, "Next: YOU mark rock [E] · THEY dig on Dig defaults",
		"the fresh-wing tip retains the exact original text")
	_assert_true("in progress" not in str(step.text) and not step.has("in_progress"),
		"a fresh wing does not receive queued-build text or metadata")
	_dispose(game)

	game = _next_chain_game()
	var ari: VaultResident = game.residents[0]
	ari.needs.rest = 0.0
	ari.needs.health = 40.0
	step = game.player_orders._refresh_objective()
	_assert_equal(game.player_orders.objective_label.text, PLACE_BUNKS,
		"rest urgency retains its exact original text before any blueprint exists")
	_assert_true("in progress" not in str(step.text) and not step.has("in_progress"),
		"an unsuppressed urgency has no queued-build suffix or metadata")
	_assert_true(bool(step.get("urgent", false)) and int(step.get("resident_id", -1)) == ari.resident_id
		and str(step.get("cause", "")) == "rest",
		"unsuppressed urgency retains its flag, resident and cause")
	_assert_approximately(float(step.get("death_seconds", -1.0)), 40.0 / (30.0 / DayCycle.SECONDS_PER_DAY), 0.0001,
		"unsuppressed urgency retains the projected death runway")
	_dispose(game)


func _test_next_multiple_queued_builds() -> void:
	var game := _next_chain_game()
	var ari: VaultResident = game.residents[0]
	ari.needs.mood = 0.0
	ari.needs.health = 5.0
	var placed_rec := game.place_blueprint(VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(18, 12))
	var placed_bunk := game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(19, 12))
	var step: Dictionary = game.player_orders._refresh_objective()
	_assert_true(placed_rec and placed_bunk, "two different real unfinished blueprints are queued")
	_assert_equal(step.get("in_progress", []), ["Rec Consoles", "bunks"],
		"suppression records each selected queued kind once, in chain order")
	_assert_equal(game.player_orders.objective_label.text,
		PLACE_CHARGE + " · Rec Consoles in progress · bunks in progress",
		"Rec urgency and the remaining bunk link both fall through to Charge")
	_dispose(game)


func _test_next_queued_only_fallback() -> void:
	var game := _next_chain_game()
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(21, 12))
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(22, 12))
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(23, 12))
	_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(25, 12))
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	# Enter the actual warning, deliver its salvage, and finish the real patch.
	game.breach_system.advance(0.0, game.breach_system.warning_at)
	var delivered := game.breach_system.add_delivery(BreachSystem.PATCH_COST)
	var sealed := game.breach_system.apply_patch_work(BreachSystem.PATCH_WORK_SECONDS)
	game.player_orders.show_breach_warning(false)
	game.food_system.salvage = 100
	var placed := game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(18, 12))
	var step: Dictionary = game.player_orders._refresh_objective()
	_assert_true(delivered == BreachSystem.PATCH_COST and sealed and placed,
		"the hatch is really sealed and the only unmet build link has a real bunk blueprint")
	_assert_equal(game.player_orders.objective_label.text, "Next: bunks in progress · THEY finish it",
		"a fully covered chain leaves the short queued-only fallback")
	_assert_equal(step.get("in_progress", []), ["bunks"], "the fallback retains structured queued-kind names")
	_assert_equal(str(step.get("tool", "")), "select", "queued-only fallback keeps Select available")
	_dispose(game)


func _test_next_urgency_recap() -> void:
	var game := _next_chain_game()
	var ari: VaultResident = game.residents[0]
	ari.needs.rest = 0.0
	ari.needs.health = 40.0
	var original: Dictionary = game.player_orders._primary_next_step()
	# Exercise recap storage with a decorated copy of a real selected urgency.
	# The selected action and all its original urgency facts must survive.
	var decorated := original.duplicate(true)
	decorated["in_progress"] = ["Rec Consoles", "bunks"]
	decorated["text"] = str(original.text) + " · Rec Consoles in progress · bunks in progress"
	game.player_orders.clear_survival_tips()
	game.player_orders._remember_survival_tip(decorated)
	var tips: Dictionary = game.player_orders.get("_survival_tips")
	var details: Dictionary = game.player_orders.get("_survival_tip_details")
	_assert_equal(str(tips.get(ari.resident_id, "")), PLACE_BUNKS,
		"recap stores the exact saving action after stripping every queued suffix")
	_assert_equal(str(details.get(ari.resident_id, {}).get("cause", "")), "rest",
		"recap retains the real urgency's cause")
	_assert_true(bool(decorated.get("urgent", false)) and int(decorated.get("resident_id", -1)) == ari.resident_id
		and str(decorated.get("cause", "")) == "rest"
		and float(decorated.get("death_seconds", -1.0)) == float(original.get("death_seconds", -2.0)),
		"remembering a decorated action preserves urgency, resident, cause and death runway")
	game.day_cycle.advance(VaultGame.SIMULATION_TICK)
	ari.needs.health = 0.0
	var recap: Dictionary = game.player_orders.death_recap_for(ari)
	_assert_equal(str(recap.get("tip", "")), PLACE_BUNKS,
		"death-recap extraction can still find the earlier saving action without queued context")
	ari.needs.health = 40.0

	game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(18, 12))
	game.player_orders.clear_survival_tips()
	var step: Dictionary = game.player_orders._refresh_objective()
	tips = game.player_orders.get("_survival_tips")
	details = game.player_orders.get("_survival_tip_details")
	_assert_true(step.get("in_progress", []) == ["bunks"] and not tips.has(ari.resident_id) and not details.has(ari.resident_id),
		"the queued bunk action is suppressed before refresh can remember it as Ari's saving tip")
	_dispose(game)


func _test_next_queued_extra_air() -> void:
	var game := _next_chain_game()
	_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(21, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(22, 12))
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.oxygen = 10.0
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	var bo: VaultResident = game.residents[1]
	bo.needs.health = 20.0
	var before: Dictionary = game.player_orders._primary_next_step()
	var placed := game.place_blueprint(VaultBuilding.Kind.AIR_RECYCLER, Vector2i(18, 12))
	var step: Dictionary = game.player_orders._refresh_objective()
	_assert_true(game.get_powered_building_count(VaultBuilding.Kind.AIR_RECYCLER) == 1 and game.oxygen_system.net_rate > 0.0,
		"the existing Air Recycler is genuinely powered and recovering air")
	_assert_true(bool(before.get("urgent", false)) and str(before.get("cause", "")) == "air"
		and int(before.get("resident_id", -1)) == bo.resident_id and str(before.get("tool", "")) == "air",
		"the real five-second suffocation deadline asks for extra air before placement")
	_assert_true(placed and str(step.get("tool", "")) == "bed" and step.get("in_progress", []) == ["Air Recyclers"],
		"the queued extra recycler falls through to the normal bunk link")
	_assert_equal(game.player_orders.objective_label.text,
		"Next: YOU place 2 bunks · THEY craft from Craft · Air Recyclers in progress",
		"the replacement tip keeps the next normal link and queued Air context")
	_dispose(game)
