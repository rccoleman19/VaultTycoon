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
	_run_case("the alert bar caps visible alerts at two and counts the rest", _test_alerts_cap_two_visible)
	_run_case("alerts rank by death runway and name the most urgent critical resident", _test_alerts_rank_by_urgency)
	_run_case("alerts already stated by the displayed Next tip are removed everywhere", _test_alerts_no_duplicate_with_next)
	_run_case("mixed starvation and exhaustion keeps CRITICAL Ari outside Next", _test_alerts_uncovered_critical_resident)
	_run_case("only critical Bo stays deduped by Next", _test_alerts_only_critical_resident_covered)
	_run_case("all critical residents covered by Next keep the first-ranked fallback", _test_alerts_all_critical_residents_covered)
	_run_case("DETAILS expands the ranked alerts hidden by the alert cap", _test_alerts_details_expands_more)
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
	game.player_orders.refresh()
	game.day_cycle.elapsed_seconds += 3.0
	game.player_orders.refresh()
	var step: Dictionary = game.player_orders._refresh_objective()
	_assert_true(delivered == BreachSystem.PATCH_COST and sealed and placed,
		"the hatch is really sealed and the only unmet build link has a real bunk blueprint")
	_assert_equal(game.player_orders.objective_label.text, "Next: YOU spend 18: fit Grow Tray Mk II · bunks in progress",
		"an idle covered chain offers the affordable fit and retains queued construction")
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
	# Tips are retained per resident and cause (feat/death-recap 0350ec56).
	var ari_tips: Dictionary = tips.get(ari.resident_id, {})
	var ari_details: Dictionary = details.get(ari.resident_id, {})
	_assert_equal(str(ari_tips.get("rest", "")), PLACE_BUNKS,
		"recap stores the exact saving action after stripping every queued suffix")
	_assert_equal(str(ari_details.get("rest", {}).get("cause", "")), "rest",
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


# These helpers deliberately use Object.get for slice-2 members. The same new
# cases run on the original project as a control: absent members are assertions,
# never invalid property accesses or attempts to index a null value.
func _triage_alerts(orders: Node, member: String) -> Array:
	var value: Variant = orders.get(member)
	_assert_true(value is Array, "%s exposes its ranked alerts" % member)
	return value if value is Array else []


func _triage_hidden(orders: Node) -> int:
	var value: Variant = orders.get("alert_hidden_count")
	_assert_true(value is int, "alert_hidden_count exposes the number beyond the cap")
	return int(value) if value is int else -1


func _triage_more(orders: Node) -> Variant:
	var value: Variant = orders.get("alert_more_label")
	_assert_true(value is Control, "DETAILS owns a surface for the remaining alerts")
	return value as Control


func _triage_game() -> VaultGame:
	var game := _spawn_game()
	game.new_game(false, 4242, 5)
	game.begin_shift()
	_triage_healthy_crew(game)
	game.food_system.meals = 24
	# Advance the real fixed-step simulation, rather than setting elapsed time.
	game.step_simulation(VaultGame.SIMULATION_TICK)
	return game


func _triage_healthy_crew(game: VaultGame) -> void:
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
		resident.drafted = false
		resident.sleeping = false
		resident.bed_id = -1
		resident.medical_bed_id = -1


func _triage_many_alerts_game() -> VaultGame:
	var game := _triage_game()
	game.food_system.meals = 1
	game.residents[0].needs.rest = 25.0
	game.residents[1].needs.health = 75.0
	game.residents[2].needs.mood = 30.0
	game.step_simulation(VaultGame.SIMULATION_TICK)
	game.player_orders.refresh()
	return game


func _triage_expected_key(game: VaultGame, alert: String) -> float:
	# Compute the contract from the existing survival helpers, independently of
	# the new alert sorter. CRITICAL's current-food threshold is a warning rule;
	# its death projection deliberately uses INF, exactly as Next does.
	if alert.begins_with("CRITICAL: "):
		for resident: VaultResident in game.residents:
			if resident.alive and alert == "CRITICAL: %s" % resident.resident_name:
				return game.player_orders._projected_death_seconds(resident, INF)
		return INF
	if alert.begins_with("OXYGEN "):
		if game.oxygen_system.is_critical():
			return 0.0
		var crossing := game.oxygen_system.get_seconds_to_critical_crossing()
		return crossing if crossing >= 0.0 else INF
	if alert.begins_with("BREACH OPEN"):
		return 0.0
	if alert.begins_with("SEAL WARNING"):
		return game.breach_system.get_time_to_open()
	if alert in ["NO MEALS", "LOW MEALS"]:
		return game.player_orders._food_runway_seconds()
	return INF


func _assert_triage_sorted(game: VaultGame, alerts: Array, message: String) -> void:
	_assert_true(alerts.size() >= 2, "%s has multiple independently ranked threats" % message)
	var previous := -INF
	for alert: Variant in alerts:
		var key := _triage_expected_key(game, str(alert))
		_assert_true(key >= previous, "%s: %s has key %s after %s" % [message, str(alert), str(key), str(previous)])
		previous = key
	# The old severity grouping remains the stable tie-breaker, including INF.
	var typed_alerts: Array[String] = []
	for alert: Variant in alerts:
		typed_alerts.append(str(alert))
	var severity: Array[String] = game.player_orders._order_alerts_by_severity(typed_alerts)
	for index in range(1, alerts.size()):
		if _triage_expected_key(game, str(alerts[index - 1])) == _triage_expected_key(game, str(alerts[index])):
			_assert_true(severity.find(str(alerts[index - 1])) < severity.find(str(alerts[index])),
				"%s preserves severity order when death keys tie" % message)


func _assert_triage_count_and_bar(game: VaultGame, visible: Array, hidden: int) -> void:
	var shown := visible.size() - hidden
	_assert_true(shown == mini(2, visible.size()) or (shown == 1 and visible.size() >= 2),
		"the +N count includes exactly the alerts beyond the one or two shown")
	if visible.is_empty():
		return
	var expected := "  ·  ".join(visible.slice(0, shown))
	if hidden > 0:
		expected += "  ·  +%d more" % hidden
	_assert_equal(game.player_orders.alert_label.text.replace("\u00a0", " "), expected, "the bar renders the leading alerts plus their exact hidden count")


func _test_alerts_cap_two_visible() -> void:
	var game := _triage_many_alerts_game()
	var orders := game.player_orders
	var generated := _triage_alerts(orders, "all_alerts")
	var visible := _triage_alerts(orders, "alert_list")
	var hidden := _triage_hidden(orders)
	_assert_true("LOW MEALS" in generated and "BED SHORTAGE · crew rotate" in generated
		and "INJURED 1 · NO MED BED" in generated and "MOOD STRESSED · Cyra" in generated,
		"real low meals, tired crew, injury and stress generate the multi-alert fixture: %s" % str(generated))
	_assert_true(game.day_cycle.elapsed_seconds >= 2.0 * VaultGame.SIMULATION_TICK,
		"the multi-alert state includes real needs and fixed-tick progress")
	_assert_true(hidden >= 1, "several alerts leave at least one alert behind the cap")
	_assert_equal(orders.alert_label.text.replace("\u00a0", " ").split("  ·  ").size(), visible.size() - hidden + 1,
		"the bar has one or two alert segments and one +N segment")
	_assert_triage_count_and_bar(game, visible, hidden)
	_assert_true("DETAILS" in orders.alert_label.tooltip_text,
		"the alert tooltip explains where +N more expands")
	_assert_equal(orders.alert_label.get_theme_color("font_color"), Color("ef6860"), "live alerts keep the existing red colour")
	_dispose(game)

	game = _triage_game()
	orders = game.player_orders
	orders.refresh()
	_assert_equal(_triage_alerts(orders, "all_alerts"), [], "healthy real crew generate no alerts")
	_assert_equal(orders.alert_label.text, "STATUS NOMINAL", "no generated alerts retain the exact nominal text")
	_assert_equal(orders.alert_label.get_theme_color("font_color"), Color("75d4b4"), "nominal status retains its green colour")
	for resident: VaultResident in game.residents:
		resident.set_work_priority("cook", VaultResident.PRIORITY_DISABLED)
	orders.refresh()
	_assert_equal(_triage_alerts(orders, "alert_list"), ["NO COOK ENABLED"], "ample pantry stock leaves just the independent Cook alert")
	_assert_equal(orders.alert_label.text.replace("\u00a0", " "), "NO COOK ENABLED", "a single alert keeps its exact wording without +N more")
	_assert_equal(_triage_hidden(orders), 0, "one alert has no hidden alerts")
	var more: Variant = _triage_more(orders)
	if more != null:
		_assert_false(more.visible, "no remaining alert list is shown for a single alert")
	orders._toggle_details_rail()
	_assert_true(orders.details_box.visible, "DETAILS can still expand with only one alert")
	if more != null:
		_assert_false(more.visible, "the remaining-alert list stays hidden at N=0 even with DETAILS expanded")
	_dispose(game)


func _test_alerts_rank_by_urgency() -> void:
	var game := _triage_game()
	# Reach WARNING through ordinary ticks, preserving the seeded warning time.
	for _tick in range(1000):
		if game.breach_system.phase != BreachSystem.Phase.DORMANT:
			break
		game.step_simulation(VaultGame.SIMULATION_TICK)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.WARNING, "real simulation reaches the seeded seal warning")
	_assert_true(game.day_cycle.elapsed_seconds >= game.breach_system.warning_at,
		"warning ranking uses real elapsed simulation time")
	_triage_healthy_crew(game)
	game.food_system.meals = 24
	game.breach_system.add_delivery(BreachSystem.PATCH_COST)
	# Ari's one-second exhaustion selects bunks, leaving both oxygen and hatch
	# threats to compete in the bar instead of being covered by Next.
	var ari: VaultResident = game.residents[0]
	ari.needs.rest = 0.0
	ari.needs.health = 0.75
	game.residents[2].needs.mood = 30.0
	game.oxygen_system.oxygen = 20.0
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	var orders := game.player_orders
	orders.refresh()
	_assert_true("Ari exhausted" in orders.objective_label.text and "bunks" in orders.objective_label.text,
		"the displayed Next covers exhaustion while the air and seal alerts remain independent")
	var generated := _triage_alerts(orders, "all_alerts")
	var visible := _triage_alerts(orders, "alert_list")
	_assert_triage_sorted(game, generated, "short oxygen runway")
	_assert_triage_sorted(game, visible, "short oxygen runway after dedupe")
	var seal_alert := "SEAL WARNING · %s" % orders._format_seconds(game.breach_system.get_time_to_open())
	_assert_true(generated.find("OXYGEN LOW") >= 0 and generated.find(seal_alert) >= 0
		and generated.find("OXYGEN LOW") < generated.find(seal_alert),
		"oxygen's critical crossing comes before the real hatch-opening deadline")
	_assert_true(orders.alert_label.text.replace("\u00a0", " ").begins_with("OXYGEN LOW  ·  ")
		and visible.slice(0, 2) == ["OXYGEN LOW", seal_alert],
		"the shorter uncovered oxygen runway leads the hatch alert")
	_assert_triage_count_and_bar(game, visible, _triage_hidden(orders))

	# Raising oxygen keeps the very same alerts active but reverses their keys.
	game.oxygen_system.oxygen = 30.0
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	orders.refresh()
	generated = _triage_alerts(orders, "all_alerts")
	visible = _triage_alerts(orders, "alert_list")
	_assert_triage_sorted(game, generated, "longer oxygen runway")
	_assert_triage_sorted(game, visible, "longer oxygen runway after dedupe")
	_assert_true(generated.find(seal_alert) >= 0 and generated.find("OXYGEN LOW") >= 0
		and generated.find(seal_alert) < generated.find("OXYGEN LOW"),
		"the alert ordering flips when oxygen outlasts the hatch grace")
	_assert_true(orders.alert_label.text.replace("\u00a0", " ").begins_with(seal_alert + "  ·  ")
		and visible.slice(0, 2) == [seal_alert, "OXYGEN LOW"],
		"the earlier hatch-opening deadline leads oxygen after the flip")
	_assert_triage_count_and_bar(game, visible, _triage_hidden(orders))

	game.oxygen_system.oxygen = 10.0
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	orders.refresh()
	generated = _triage_alerts(orders, "all_alerts")
	_assert_triage_sorted(game, generated, "oxygen already critical")
	_assert_true(not generated.is_empty() and str(generated[0]) == "OXYGEN CRITICAL",
		"oxygen already at the lethal threshold ranks at zero seconds, ahead of CRITICAL and the seal")
	game.oxygen_system.oxygen = 30.0
	_add_completed_building(game, VaultBuilding.Kind.AIR_RECYCLER, Vector2i(20, 12))
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, Vector2i(21, 12))
	game.power_grid.recalculate(game.buildings)
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	orders.refresh()
	generated = _triage_alerts(orders, "all_alerts")
	_assert_true(game.oxygen_system.net_rate > 0.0 and game.oxygen_system.get_seconds_to_critical_crossing() < 0.0,
		"a genuinely powered recycler recovers low oxygen without a future critical crossing")
	_assert_triage_sorted(game, generated, "recovering low oxygen")
	_assert_true(generated.find(seal_alert) >= 0 and generated.find("OXYGEN LOW") > generated.find(seal_alert),
		"recovering low oxygen has an infinite threat key and follows the finite hatch deadline")
	_dispose(game)

	game = _triage_game()
	ari = game.residents[0]
	var bo: VaultResident = game.residents[1]
	ari.needs.rest = 0.0
	ari.needs.health = 30.0
	bo.needs.rest = 0.0
	bo.needs.health = 15.0
	orders = game.player_orders
	orders.refresh()
	# Isolate the unchanged candidate ranking from Next coverage. The mixed
	# regression below separately exercises selection with the real built step.
	orders._refresh_alerts({})
	generated = _triage_alerts(orders, "all_alerts")
	_assert_true(orders._projected_death_seconds(bo, INF) < orders._projected_death_seconds(ari, INF),
		"both residents meet the critical rule and Bo's real death projection is sooner")
	_assert_true("CRITICAL: Bo" in generated and "CRITICAL: Ari" not in generated,
		"CRITICAL names the most urgent resident rather than the first roster entry")
	_assert_triage_sorted(game, generated, "two critical residents")
	bo.needs.health = 60.0
	orders.refresh()
	orders._refresh_alerts({})
	generated = _triage_alerts(orders, "all_alerts")
	_assert_true("CRITICAL: Ari" in generated and "CRITICAL: Bo" not in generated,
		"CRITICAL switches names when the other resident's death runway becomes shortest")
	_dispose(game)


func _test_alerts_uncovered_critical_resident() -> void:
	var game := _triage_game()
	var ari: VaultResident = game.residents[0]
	var bo: VaultResident = game.residents[1]
	ari.drafted = true
	ari.needs.food = 0.0
	ari.needs.health = 100.0
	bo.drafted = true
	bo.needs.rest = 0.0
	bo.needs.health = 30.0
	game.food_system.meals = 24
	game.step_simulation(VaultGame.SIMULATION_TICK)
	var orders := game.player_orders
	orders.refresh()
	_assert_equal(game.food_system.meals, 24, "stored meals remain unavailable to drafted Ari")
	_assert_approximately(ari.needs.health, 99.6, 0.0001, "one real starvation tick leaves Ari at 99.6 HP")
	var depletion: Dictionary = orders._food_depletion_times()
	var food_deadline := orders._projected_death_seconds(ari, float(depletion[ari.resident_id]))
	_assert_approximately(food_deadline, 24.9, 0.0001, "Ari's food-inclusive projection leaves a 24.9 s starvation runway")
	_assert_equal(orders.objective_label.text, "Next: Bo exhausted · YOU undraft Bo [R] · THEY rest",
		"Next keeps its existing exhaustion ranking and exact undraft-Bo action")
	var step: Dictionary = orders._refresh_objective()
	_assert_true(orders._alert_stated_by_next("CRITICAL: Bo", step)
		and not orders._alert_stated_by_next("CRITICAL: Ari", step),
		"the real built Next step covers Bo and leaves Ari uncovered")
	var ari_deadline := orders._projected_death_seconds(ari, INF)
	var bo_deadline := orders._projected_death_seconds(bo, INF)
	_assert_true(bo_deadline < ari_deadline, "the unchanged critical projection ranks Bo before Ari")
	var generated := _triage_alerts(orders, "all_alerts")
	var visible := _triage_alerts(orders, "alert_list")
	_assert_true("CRITICAL: Ari" in generated and "CRITICAL: Bo" not in generated,
		"the generated CRITICAL warning names uncovered Ari after skipping covered Bo")
	_assert_true("CRITICAL: Ari" in visible, "CRITICAL: Ari survives Next dedupe in the showable alerts")
	_assert_approximately(orders._alert_urgency_seconds("CRITICAL: Ari"), ari_deadline, 0.0001,
		"CRITICAL: Ari uses Ari's existing projection, rather than Bo's earlier deadline")
	_assert_triage_sorted(game, generated, "mixed critical residents")
	_assert_triage_count_and_bar(game, visible, _triage_hidden(orders))
	if not orders.details_box.visible:
		orders._toggle_details_rail()
	var more: Variant = _triage_more(orders)
	var ari_visible := "CRITICAL: Ari" in orders.alert_label.text.replace("\u00a0", " ")
	if more != null:
		ari_visible = ari_visible or (more.is_visible_in_tree() and "CRITICAL: Ari" in more.text)
	_assert_true(ari_visible, "the alert bar or expanded DETAILS visibly names CRITICAL: Ari")
	_assert_false("Ari" not in orders.objective_label.text and not ari_visible,
		"Ari must not be hidden everywhere while Next names Bo")
	# Count the killing tick too: resident death pauses before day_cycle advances.
	var ticks_to_death := 0
	while ari.alive and ticks_to_death < 260:
		game.step_simulation(VaultGame.SIMULATION_TICK)
		ticks_to_death += 1
	_assert_false(ari.alive, "drafted Ari actually dies while the stored meals cannot reach her")
	_assert_approximately(ticks_to_death * VaultGame.SIMULATION_TICK, 24.9, VaultGame.SIMULATION_TICK + 0.0001,
		"the actual fixed-tick starvation runway matches the projected 24.9 s")
	_dispose(game)


func _test_alerts_only_critical_resident_covered() -> void:
	var game := _triage_game()
	var bo: VaultResident = game.residents[1]
	bo.drafted = true
	bo.needs.rest = 0.0
	bo.needs.health = 30.0
	var orders := game.player_orders
	orders.refresh()
	_assert_equal(orders.objective_label.text, "Next: Bo exhausted · YOU undraft Bo [R] · THEY rest",
		"Bo-only control retains the existing exact Next action")
	_assert_next_alert_omitted(game, "CRITICAL: Bo", "only critical resident is already named")
	_assert_equal(orders.alert_list, ["DRAFTED CREW 1 · AUTO WORK PAUSED", "INJURED 1 · NO MED BED"],
		"deduping Bo preserves the two unrelated alerts for the bar and DETAILS")
	_dispose(game)


func _test_alerts_all_critical_residents_covered() -> void:
	var game := _triage_game()
	var ari: VaultResident = game.residents[0]
	var bo: VaultResident = game.residents[1]
	ari.needs.rest = 0.0
	ari.needs.health = 60.0
	bo.drafted = true
	bo.needs.rest = 0.0
	bo.needs.health = 30.0
	var orders := game.player_orders
	var step: Dictionary = orders._refresh_objective()
	_assert_true(int(step.get("resident_id", -1)) == bo.resident_id and bool(step.get("urgent", false)),
		"the built Next step initially covers the first-ranked Bo")
	# Next currently names one urgent resident. Decorate its real built step to
	# exercise the existing text rule when every critical resident is stated.
	step["text"] = str(step.get("text", "")) + " · Ari exhausted"
	orders.objective_label.text = str(step["text"])
	orders._refresh_alerts(step)
	_assert_true(orders._alert_stated_by_next("CRITICAL: Ari", step)
		and orders._alert_stated_by_next("CRITICAL: Bo", step), "both critical candidates are stated by the displayed step")
	var generated := _triage_alerts(orders, "all_alerts")
	_assert_true("CRITICAL: Bo" in generated and "CRITICAL: Ari" not in generated,
		"when every candidate is covered, the fallback keeps first-ranked Bo rather than roster-first Ari")
	_assert_next_alert_omitted(game, "CRITICAL: Bo", "all critical candidates are already named")
	_assert_approximately(orders._alert_urgency_seconds("CRITICAL: Bo"), orders._projected_death_seconds(bo, INF), 0.0001,
		"the covered fallback keeps the first-ranked resident's urgency")
	_dispose(game)


func _assert_next_alert_omitted(game: VaultGame, alert: String, message: String) -> void:
	var orders := game.player_orders
	_assert_true(alert in _triage_alerts(orders, "all_alerts"), "%s: the simulation still generates %s" % [message, alert])
	_assert_false(alert in _triage_alerts(orders, "alert_list"), "%s: Next removes %s from the showable list" % [message, alert])
	_assert_false(alert in orders.alert_label.text.replace("\u00a0", " "), "%s: the bar does not repeat %s" % [message, alert])
	var more: Variant = _triage_more(orders)
	if more != null:
		_assert_false(alert in more.text, "%s: DETAILS does not repeat %s" % [message, alert])
	_assert_triage_count_and_bar(game, _triage_alerts(orders, "alert_list"), _triage_hidden(orders))


func _test_alerts_no_duplicate_with_next() -> void:
	var game := _triage_game()
	game.food_system.meals = 0
	game.residents[0].needs.food = 0.0
	game.residents[1].needs.health = 75.0
	game.residents[2].needs.mood = 30.0
	var orders := game.player_orders
	orders.refresh()
	_assert_equal(orders.objective_label.text, "Next: Ari starving · YOU place a Nutrient Station · THEY cook",
		"the real food crisis displays the starvation and Nutrient action used for dedupe")
	_assert_next_alert_omitted(game, "CRITICAL: Ari", "named starvation")
	_assert_next_alert_omitted(game, "NO MEALS", "food recovery action")
	_assert_true("INJURED 1 · NO MED BED" in _triage_alerts(orders, "alert_list"),
		"Next's food advice preserves Bo's unrelated injury alert")
	_assert_true(orders.alert_label.text.replace("\u00a0", " ").begins_with("INJURED 1 · NO MED BED  ·  "),
		"the uncovered injury remains visible with the count excluding deduped food alerts")
	_dispose(game)

	game = _triage_game()
	orders = game.player_orders
	game.residents[0].needs.rest = 25.0
	orders.refresh()
	_assert_equal(orders.objective_label.text, "Next: YOU place bunks · THEY craft", "a tired resident selects the real bunk shortage action")
	_assert_next_alert_omitted(game, "BED SHORTAGE · crew rotate", "bunk placement")
	_assert_equal(orders.alert_label.text, "SEE NEXT", "alerts fully covered by Next keep a visible exact SEE NEXT state")
	_assert_equal(orders.alert_label.get_theme_color("font_color"), Color("ef6860"), "SEE NEXT retains the alert red colour")
	_assert_equal(_triage_hidden(orders), 0, "a deduped shortage is not counted as hidden")
	_dispose(game)

	# Slice 1 decorates a different selected action with queued-build context.
	# That matching alert remains covered even after the build tool changes.
	game = _next_chain_game()
	orders = game.player_orders
	game.residents[0].needs.rest = 0.0
	game.residents[0].needs.health = 40.0
	_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, Vector2i(18, 12)), "queue a real unfinished bunk blueprint")
	orders.refresh()
	_assert_equal(orders.objective_label.text, PLACE_CHARGE + " · bunks in progress", "the exact displayed replacement reports queued bunks")
	_assert_next_alert_omitted(game, "BED SHORTAGE", "bunks in progress")
	_assert_alert_dedupe_rules(orders)
	_dispose(game)


func _assert_alert_dedupe_rules(orders: Node) -> void:
	_assert_true(orders.has_method("_alert_stated_by_next"), "one dedupe function exposes the explicit alert/Next content rules")
	if not orders.has_method("_alert_stated_by_next"):
		return
	# Exercise every requested mapping plus near misses. These examples supplement
	# the real displayed-Next scenarios above; an absent method fails on the base
	# without calling it, and no synthetic example replaces a simulation assertion.
	var rules := [
		["CRITICAL: Ari", {"text": "Next: Ari starving · YOU place a Nutrient Station · THEY cook"}, true],
		["CRITICAL: Ari", {"text": "Next: YOU undraft Ari [R] · THEY rest", "urgent": true, "resident_id": 1}, true],
		["CRITICAL: Ari", {"text": "Next: Bo exhausted · YOU place bunks · THEY craft", "urgent": true, "resident_id": 2}, false],
		["CRITICAL: Ari", {"text": "Next: YOU select Ari", "resident_id": 1}, false],
		["BED SHORTAGE", {"text": "Next: YOU place bunks · THEY craft", "tool": "bed"}, true],
		["BED SHORTAGE · crew rotate", {"text": PLACE_CHARGE, "in_progress": ["bunks"]}, true],
		["BED SHORTAGE", {"text": "Next: YOU place a Med Bed · THEY treat", "tool": "medical"}, false],
		["NO REC CONSOLE", {"text": "Next: YOU place a Rec Console · THEY recover mood"}, true],
		["REC CONSOLE OFFLINE", {"text": "Next: YOU enable a Rec Console · THEY recover mood"}, true],
		["MOOD STRESSED · Ari", {"text": "Next: Ari starving · YOU enable Cook · THEY cook"}, true],
		["MOOD BREAK RISK · Ari", {"text": "Next: YOU undraft crew · THEY recover mood"}, true],
		["MOOD STRESSED · Ari", {"text": "Next: Bo starving · YOU enable Cook · THEY cook"}, false],
		["NO REC CONSOLE", {"text": PLACE_CHARGE, "in_progress": ["Rec Consoles"]}, true],
		["NO COOK ENABLED", {"text": "Next: YOU enable Cook · THEY cook"}, true],
		["NO COOK ENABLED", {"text": "Next: YOU leave Cook on · THEY cook"}, false],
		["FOOD WAITING · ENABLE HAUL", {"text": "Next: YOU enable Haul · THEY deliver food"}, true],
		["FOOD WAITING · ENABLE HAUL", {"text": "Next: YOU leave Haul on · THEY deliver food"}, false],
		["NO MEALS", {"text": "Next: YOU place a Nutrient Station · THEY cook"}, true],
		["LOW MEALS", {"text": "Next: YOU place a Grow Tray · THEY grow"}, true],
		["LOW MEALS", {"text": "Next: YOU enable Cook · THEY cook"}, true],
		["NO MEALS", {"text": "Next: YOU leave Haul on · THEY deliver meals"}, true],
		["NO MEALS", {"text": "Next: YOU place a Med Bed · THEY treat"}, false],
		["OXYGEN CRITICAL", {"text": "Next: Bo suffocating · YOU place Air Recycler · THEY recycle more air"}, true],
		["OXYGEN LOW", {"text": PLACE_CHARGE, "in_progress": ["Air Recyclers"]}, true],
		["OXYGEN LOW", {"text": "Next: YOU place a Charge Node · THEY supply/build"}, false],
		["SEAL WARNING · 00:19", {"text": "Next: YOU watch hatch · THEY patch"}, true],
		["SEAL WARNING · 00:19", {"text": "Next: YOU acknowledge warning · then enable Craft [P]"}, true],
		["BREACH OPEN · O2 VENTING", {"text": "Next: YOU enable Haul + Craft [P] · THEY patch hatch"}, true],
		["SEAL WARNING · 00:19", {"text": "Next: YOU place Air Recycler · THEY recycle air"}, false],
		["POWER BROWNOUT · SHED Grow Tray", {"text": "Next: YOU place a Charge Node · THEY add power"}, true],
		["POWER BROWNOUT · SHED Grow Tray", {"text": "Next: YOU enable a Rec Console · THEY recover mood"}, false],
		["INJURED 1 · NO MED BED", {"text": "Next: YOU place a Med Bed · THEY treat"}, true],
		["INJURED 1 · MED BEDS FREE 1", {"text": "Next: YOU place a Med Bed · THEY treat"}, false],
		["DARKNESS · 2 CREW UNLIT", {"text": "Next: YOU place a Lumen · THEY light the wing"}, true],
		["DARKNESS · 2 CREW UNLIT", {"text": "Next: YOU place bunks · THEY craft"}, false],
		["DRAFTED CREW 1 · AUTO WORK PAUSED", {"text": "Next: YOU place bunks · THEY craft"}, false],
		["NO MEALS", {}, false],
	]
	for rule: Array in rules:
		_assert_equal(orders.call("_alert_stated_by_next", str(rule[0]), rule[1]), rule[2],
			"dedupe %s for %s stays %s" % [str(rule[0]), str(rule[1]), str(rule[2])])


func _test_alerts_details_expands_more() -> void:
	var game := _triage_many_alerts_game()
	var orders := game.player_orders
	var visible := _triage_alerts(orders, "alert_list")
	var hidden := _triage_hidden(orders)
	var more: Variant = _triage_more(orders)
	_assert_true(hidden >= 2, "the fixture has at least two remaining alerts for DETAILS")
	if orders.details_box.visible:
		orders._toggle_details_rail()
	_assert_false(orders.details_box.visible, "DETAILS begins collapsed for this interaction")
	if more != null:
		_assert_false(more.visible, "the remaining-alert label is hidden while DETAILS is collapsed")
	orders._toggle_details_rail()
	_assert_true(orders.details_box.visible, "pressing DETAILS expands the rail")
	if more != null:
		_assert_true(more.visible and more.is_visible_in_tree(), "expanded DETAILS makes the remaining-alert label visible")
		_assert_equal(more.text, "\n".join(visible.slice(visible.size() - _triage_hidden(orders))), "DETAILS lists exactly the hidden alerts, one per line in rank order")
		_assert_equal(more.text.split("\n").size(), hidden, "DETAILS has exactly N alert lines")
		_assert_true(more.get_parent() == orders.details_box, "the remaining-alert label belongs to details_box")
	var header: Variant = orders.get("alert_more_header")
	_assert_true(header is Label and str(header.get("text")) == "ALERTS", "the expanded list sits under its ALERTS header")
	_assert_triage_count_and_bar(game, visible, hidden)
	orders._toggle_details_rail()
	if more != null:
		_assert_false(more.visible, "collapsing DETAILS hides the remaining-alert label again")
	# A newly gained real urgency opens the same list through the auto-expand.
	game.oxygen_system.oxygen = 30.0
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	orders.refresh()
	_assert_true(orders.details_box.visible, "a new low-oxygen urgency auto-expands DETAILS")
	visible = _triage_alerts(orders, "alert_list")
	hidden = _triage_hidden(orders)
	_assert_true(hidden >= 2, "the automatic expansion still has multiple remaining alerts")
	if more != null:
		_assert_true(more.visible and more.is_visible_in_tree(), "automatic DETAILS expansion also reveals the remaining alerts")
		_assert_equal(more.text, "\n".join(visible.slice(visible.size() - _triage_hidden(orders))), "automatic expansion keeps the current ranked hidden-alert lines")
	_assert_triage_count_and_bar(game, visible, hidden)
	_dispose(game)
