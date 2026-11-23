extends "res://tests/test_rec_flash_cause.gd"

# After the seal, a non-urgent Next that names an affordable NUDGE build reads as a
# spend, Spend offers that same build ahead of a Mk II fit, and affordability
# subtracts unpaid queued blueprints (food_plan_spendable).


func _run() -> void:
	_run_case("Air: affordable place reads as spend, with and without the early warning", _test_air)
	_run_case("Rec: Next and Spend name the Rec, not the competing Charge Mk II", _test_rec)
	_run_case("Shed Rec: Next and Spend name a Charge Node, not the competing Grow Tray Mk II", _test_shed_rec)
	_run_case("Commit-aware, build: unpaid blueprints keep Air as place until stock covers both", _test_commit_build)
	_run_case("Commit-aware, Mk II: a fit and the fallback sink respect queued commitments", _test_commit_mk2)
	_run_case("Commit-aware, Mk II purchase: inspector, Spend and Also cannot spend a queued build's stock", _test_commit_mk2_purchase)
	_run_case("Held spend afford: Spend hides and cannot place once the named build is unaffordable", _test_held_spend_afford)
	_run_case("Fallback nudge spendable: Air and salvage nudges count only free stock", _test_fallback_nudge_spendable)
	_run_case("Threshold crossing: place lasts at most one hold window after it becomes affordable", _test_threshold)
	_run_case("All five NUDGE kinds rewrite the first clause and keep the THEY suffix", _test_all_five_kinds)
	_run_case("Food card: a non-urgent spend food build stays aligned with Next and Spend", _test_food_card)
	_run_case("Negatives: urgent, pre-seal, unaffordable, keep-running, bunks, Med Bed, hold-Air", _test_negatives)
	_run_case("Hold Day 7, Mk II, crew busy: Next and Spend name the fit without an idle wait", _test_hold_day7_mk2_busy)
	_run_case("Hold Day 7, Mk II short: spendable 17 keeps the designate hold", _test_hold_day7_mk2_short)
	_run_case("Hold Day 7, power-blocked Charge, crew busy, raw 0: Next and Spend name Charge", _test_hold_day7_charge_busy)
	_run_case("Hold Day 7, Charge unaffordable: spendable 17 keeps the designate hold", _test_hold_day7_charge_short)
	_run_case("Hold Day 7, power covers a second kitchen: no invented kitchen or Charge spend", _test_hold_day7_power_covers_kitchen)
	_run_case("Hold Day 7, tray power-blocked at spare 2: Charge is named", _test_hold_day7_charge_tray_blocked)
	_run_case("Hold Day 7, affordable Rec outranks a power-blocked Charge", _test_hold_day7_rec_outranks_charge)
	_run_case("Hold Day 7, commit-aware short: raw 22 / spendable 17 keeps the hold", _test_hold_day7_commit_short)
	_run_case("Hold Day 7, committed stock: salvage 18 covering a Charge does not name Mk II", _test_hold_day7_mk2_committed_stock)
	_run_case("Hold Day 7, 17 to 18 threshold: the fit appears after one hold window", _test_hold_day7_threshold)
	print("POSTSEAL SPEND NAMED BUILD: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _show(game: VaultGame) -> String:
	game.player_orders.refresh()
	return game.player_orders.objective_label.text


func _press(game: VaultGame) -> void:
	var button: Button = game.player_orders.upgrade_offer_button
	if button != null and button.visible and not button.disabled:
		button.pressed.emit()


func _count_kind(game: VaultGame, kind: int) -> int:
	var count := 0
	for building: VaultBuilding in game.buildings:
		if building.kind == kind:
			count += 1
	return count


func _target_kind(game: VaultGame) -> int:
	var target = game.player_orders._upgrade_offer_target()
	return -1 if target == null else int(target.kind)


func _food_button(game: VaultGame) -> Button:
	return game.player_orders.find_child("FoodPlanButton", true, false)


func _idle(game: VaultGame) -> void:
	game.player_orders.refresh()
	game.day_cycle.elapsed_seconds += 3.0
	game.player_orders.refresh()


func _expire_hold(game: VaultGame) -> void:
	game.day_cycle.elapsed_seconds += PlayerOrders.NEXT_HOLD_S + 0.1
	game.player_orders.refresh()


func _seal_base(bunks := true, air := false, rec := false) -> VaultGame:
	var game := _plateau(bunks, air)
	if rec:
		_add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, Vector2i(27, 12))
		game.power_grid.recalculate(game.buildings)
	game.reclaim_active = true
	game.oxygen_system.oxygen = 100.0
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	return game


func _add_lumens(game: VaultGame, count: int) -> void:
	for i in count:
		_add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(16 + (i % 8), 11 - int(i / 8)))
	game.power_grid.recalculate(game.buildings)


func _warn_o2(game: VaultGame) -> void:
	game.oxygen_system.refresh_rates(game.residents, game.buildings, false)
	var rate := game.oxygen_system.net_rate
	if rate >= 0.0:
		rate = -0.5
		game.oxygen_system.net_rate = rate
	game.oxygen_system.oxygen = OxygenSystem.LOW_OXYGEN_THRESHOLD + 40.0 * (-rate)
	game.player_orders._air_warning_latched = false


func _air_game(warn: bool, salvage: int) -> VaultGame:
	var game := _seal_base(true, false, false)
	game.food_system.salvage = salvage
	if warn:
		_warn_o2(game)
	else:
		game.oxygen_system.oxygen = 100.0
	return game


func _queue_unpaid(game: VaultGame, kind: int, transit: int) -> VaultBuilding:
	var placed: VaultBuilding = null
	for cell: Vector2i in game.player_orders.spend_build_cells(kind):
		if game.get_building_at(cell) == null and game.place_blueprint(kind, cell):
			placed = game.get_building_at(cell)
			break
	_assert_true(placed != null, "queued an unpaid %s" % VaultBuilding.KIND_NAMES[kind])
	if placed == null:
		return null
	var job: Dictionary = game.job_system._find_matching_job(JobSystem.JobType.SUPPLY_BUILD, placed.cell, placed.building_id)
	if job.is_empty():
		game.job_system._add_job(JobSystem.JobType.SUPPLY_BUILD, placed.cell, placed.building_id, placed.get_cost())
		job = game.job_system._find_matching_job(JobSystem.JobType.SUPPLY_BUILD, placed.cell, placed.building_id)
	if not job.is_empty():
		job["in_transit"] = transit
	return placed


func _rec_game(salvage: int) -> VaultGame:
	var game := _seal_base(true, true, false)
	# 7 lumens: planned spare is 0 so the Rec nudge yields, and Charge Mk II competes.
	_add_lumens(game, 7)
	game.wing_orders_claimed.append(VaultGame.ORDER_FIT_GROW_MK2)
	game.residents[1].needs.mood = 9.0
	game.food_system.salvage = salvage
	return game


func _shed_game(salvage: int) -> VaultGame:
	var game := _seal_base(true, true, true)
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY:
			building.upgrade_tier = VaultBuilding.UPGRADE_TIER_BASE
	# 7 lumens sheds only Rec (demand 17 / supply 16); tray and Air stay powered.
	_add_lumens(game, 7)
	game.residents[1].needs.mood = 35.0
	game.food_system.salvage = salvage
	return game


func _station_game(salvage: int) -> VaultGame:
	var game := _seal_base(true, true, true)
	var drop: Array[VaultBuilding] = []
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.KITCHEN:
			drop.append(building)
	for building: VaultBuilding in drop:
		game.buildings.erase(building)
		if building.get_parent() != null:
			building.get_parent().remove_child(building)
		building.free()
	game.power_grid.recalculate(game.buildings)
	game.food_system.salvage = salvage
	game.food_system.meals = 100
	return game


func _tray_game(salvage: int) -> VaultGame:
	var game := _seal_base(true, true, true)
	var drop: Array[VaultBuilding] = []
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY:
			drop.append(building)
	for building: VaultBuilding in drop:
		game.buildings.erase(building)
		if building.get_parent() != null:
			building.get_parent().remove_child(building)
		building.free()
	game.power_grid.recalculate(game.buildings)
	game.food_system.salvage = salvage
	game.food_system.meals = 100
	return game


func _test_air() -> void:
	for warn: bool in [false, true]:
		var game := _air_game(warn, 20)
		_assert_true(game.breach_system.is_sealed() and game.reclaim_active, "pre: sealed with reclamation active")
		_assert_equal(_count_kind(game, VaultBuilding.Kind.AIR_RECYCLER), 0, "pre: no Air Recycler or blueprint")
		_assert_true(game.food_plan_spendable() >= 14, "pre: spendable covers Air (%d)" % game.food_plan_spendable())
		var text := _show(game)
		var step: Dictionary = game.player_orders._displayed_next_step
		var want := "Next: YOU spend 14: build Air Recycler · THEY craft it"
		if warn:
			_assert_true(game.player_orders.air_early_warning(), "pre: early warning is live")
			_assert_equal(text, game.player_orders._with_air_countdown(want), "warning Next keeps its clock (%s)" % text)
		else:
			_assert_false(game.player_orders.air_early_warning(), "pre: no air warning yet")
			_assert_equal(text, want, "Next names the Air spend (%s)" % text)
		_assert_equal(str(step.get("action", "")), "spend", "the Air step is a spend")
		_assert_equal(_spend_text(game), "Spend 14: build Air Recycler", "Spend offers the Air Recycler (%s)" % _spend_text(game))
		var before := _count_kind(game, VaultBuilding.Kind.AIR_RECYCLER)
		_press(game)
		_assert_equal(_count_kind(game, VaultBuilding.Kind.AIR_RECYCLER), before + 1, "one press queues exactly one Air Recycler")
		_dispose(game)


func _test_rec() -> void:
	var game := _rec_game(20)
	_show(game)
	_assert_equal(_target_kind(game), VaultBuilding.Kind.GENERATOR, "pre: a fittable Charge Node is the competing Mk II")
	_assert_equal(_low_mood_not_hiding(game), true, "pre: low-mood Rec suppression is not what hides the Charge Mk II")
	var text := game.player_orders.objective_label.text
	var step: Dictionary = game.player_orders._displayed_next_step
	_assert_equal(text, "Next: YOU spend 8: build Rec Console · THEY recover mood", "Next names the Rec spend (%s)" % text)
	_assert_equal(str(step.get("action", "")), "spend", "the Rec step is a spend")
	_assert_equal(_spend_text(game), "Spend 8: build Rec Console", "Spend offers the Rec, not Charge Mk II (%s)" % _spend_text(game))
	var also := game.player_orders.also_text()
	_assert_true(also.is_empty() or "fit Charge Mk II" in also, "Also may still name the Charge Mk II (%s)" % also)
	var before := _count_kind(game, VaultBuilding.Kind.RECREATION_CONSOLE)
	var selected := game.selected_building_id
	_press(game)
	_assert_equal(_count_kind(game, VaultBuilding.Kind.RECREATION_CONSOLE), before + 1, "one press queues one Rec Console")
	_assert_equal(game.selected_building_id, selected, "the press selects no fixture")
	_dispose(game)


func _low_mood_not_hiding(game: VaultGame) -> bool:
	# The competing target exists because planned power makes salvage_nudge_kind a Charge Node,
	# not because _low_mood_rec_wanted is false.
	return game.player_orders._low_mood_rec_wanted() and game.player_orders.salvage_nudge_kind() != VaultBuilding.Kind.RECREATION_CONSOLE


func _test_shed_rec() -> void:
	var game := _shed_game(20)
	_show(game)
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.RECREATION_CONSOLE), 0, "pre: Rec is complete but unpowered")
	_assert_equal(_target_kind(game), VaultBuilding.Kind.GROW_TRAY, "pre: a fittable Grow Tray is the competing Mk II")
	var text := game.player_orders.objective_label.text
	var step: Dictionary = game.player_orders._displayed_next_step
	_assert_equal(text, "Next: YOU spend 18: build Charge Node · THEY power the Rec Console", "Next names the Charge spend (%s)" % text)
	_assert_equal(str(step.get("action", "")), "spend", "the Charge step is a spend")
	_assert_equal(_spend_text(game), "Spend 18: build Charge Node", "Spend agrees with the Charge Node (%s)" % _spend_text(game))
	var before := _count_kind(game, VaultBuilding.Kind.GENERATOR)
	_press(game)
	_assert_equal(_count_kind(game, VaultBuilding.Kind.GENERATOR), before + 1, "one press queues one Charge Node")
	_dispose(game)


func _test_commit_build() -> void:
	var short := _air_game(false, 20)
	_queue_unpaid(short, VaultBuilding.Kind.GROW_TRAY, 2)
	_assert_equal(short.food_system.salvage, 20, "pre: stock covers Air only before commitments")
	_assert_true(short.food_plan_spendable() < 14, "pre: spendable is short of Air after the tray commitment (%d)" % short.food_plan_spendable())
	_assert_true(short.queued_build_commitment() != 12 - 0, "pre: in-transit means spendable is not salvage minus unfunded")
	var short_text := _show(short)
	_assert_false(short_text.begins_with("Next: YOU spend "), "short stock keeps the non-spend Air wording (%s)" % short_text)
	_assert_true("YOU place Air Recycler" in short_text, "short stock keeps the Air place wording (%s)" % short_text)
	_dispose(short)
	var enough := _air_game(false, 20)
	_queue_unpaid(enough, VaultBuilding.Kind.GROW_TRAY, 6)
	_assert_true(enough.food_plan_spendable() >= 14, "pre: in-transit leaves enough for Air (%d)" % enough.food_plan_spendable())
	_assert_true(enough.food_system.salvage - 12 < 14, "pre: salvage minus unfunded would still be short")
	var enough_text := _show(enough)
	_assert_equal(enough_text, "Next: YOU spend 14: build Air Recycler · THEY craft it", "stock that covers both uses the spend wording (%s)" % enough_text)
	_dispose(enough)


func _test_commit_mk2() -> void:
	var game := _seal_base(true, true, true)
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY:
			building.upgrade_tier = VaultBuilding.UPGRADE_TIER_BASE
	# Spare stays below a second tray's demand even after the unpaid Charge counts as +7.
	_add_lumens(game, 16)
	_queue_unpaid(game, VaultBuilding.Kind.GENERATOR, 0)
	game.food_system.salvage = 30
	_idle(game)
	_assert_equal(game.queued_build_commitment(), 18, "pre: the Charge Node still owes 18")
	_assert_equal(game.food_plan_spendable(), 12, "pre: spendable is 12 after the Charge commitment")
	_assert_equal(_target_kind(game), VaultBuilding.Kind.GROW_TRAY, "pre: a Grow Tray can take the Mk II fit")
	_assert_equal(game.player_orders.salvage_survival_sink(30), VaultBuilding.Kind.GENERATOR, "pre: the old budget would fall through to an 18-salvage Charge")
	_assert_equal(game.player_orders.salvage_survival_sink(12), -1, "pre: the commit-aware budget has no 18+ sink")
	var text := game.player_orders.objective_label.text
	_assert_false("YOU spend 18: fit" in text, "Next does not offer the Mk II fit on committed stock (%s)" % text)
	_assert_false(text.begins_with("Next: YOU spend 18:") or text.begins_with("Next: YOU spend 19:"), "Next does not fall through to an 18+ spend build (%s)" % text)
	game.food_system.salvage = 36
	_expire_hold(game)
	_assert_true(game.food_plan_spendable() >= 18, "36 salvage covers the fit after the Charge commitment")
	_assert_true("YOU spend 18: fit Grow Tray Mk II" in game.player_orders.objective_label.text, "with 36 salvage the Grow Tray fit returns (%s)" % game.player_orders.objective_label.text)
	_dispose(game)


# Codex #148 issuecomment-7014948183: Next withholding the fit is not enough; the purchase
# itself (inspector FIT, Spend's fallback, the Also line) must respect unpaid blueprints.
func _test_commit_mk2_purchase() -> void:
	var game := _seal_base(true, true, true)
	var tray: VaultBuilding = null
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY:
			building.upgrade_tier = VaultBuilding.UPGRADE_TIER_BASE
			if tray == null:
				tray = building
	_add_lumens(game, 16)
	var charge := _queue_unpaid(game, VaultBuilding.Kind.GENERATOR, 0)
	game.food_system.salvage = 30
	_idle(game)
	_assert_true(tray != null and charge != null, "a fittable Grow Tray and an unpaid Charge Node")
	_assert_equal(game.queued_build_commitment(), 18, "30: the Charge Node still owes 18")
	_assert_equal(_target_kind(game), VaultBuilding.Kind.GROW_TRAY, "30: the Grow Tray is still the Mk II candidate")
	_assert_false(game.can_upgrade_building(tray.building_id), "30: the fit is not available on committed stock")
	var po := game.player_orders
	_assert_false(po.upgrade_offer_button.visible and "Mk II" in po.upgrade_offer_button.text, "30: Spend does not offer the fit (%s)" % po.upgrade_offer_button.text)
	_assert_false(po.upgrade_offer_button.visible, "30: Spend hides rather than spend the Charge's stock on another build (%s)" % po.upgrade_offer_button.text)
	_assert_false(po.also_text().begins_with("Also: fit"), "30: no Also fit line (%s)" % po.also_text())
	var charges := _count_kind(game, VaultBuilding.Kind.GENERATOR)
	game.selected_building_id = -1
	po._on_upgrade_offer_pressed()
	_assert_true(game.selected_building_id != tray.building_id, "30: the Spend press does not open the tray's fit")
	_assert_equal(_count_kind(game, VaultBuilding.Kind.GENERATOR), charges, "30: the Spend press queues no second Charge Node")
	game.select_building(tray.building_id)
	po.refresh()
	_assert_true(po.fixture_upgrade_row.visible, "30: the inspector still shows the fit row")
	_assert_true(po.fixture_upgrade_button.disabled, "30: inspector FIT is disabled")
	_assert_equal(po.fixture_upgrade_button.tooltip_text, "Needs 18 salvage free · 18 held for queued builds (have 30).", "30: the tooltip names the held stock")
	po._on_fixture_upgrade_pressed()
	_assert_false(game.upgrade_building(tray.building_id), "30: the purchase is refused")
	_assert_equal(tray.upgrade_tier, VaultBuilding.UPGRADE_TIER_BASE, "30: the tray stays Mk I")
	_assert_equal(game.food_system.salvage, 30, "30: no salvage spent")
	_assert_equal(game.queued_build_commitment(), 18, "30: the Charge commitment of 18 is preserved")
	game.food_system.salvage = 36
	_expire_hold(game)
	_assert_true(game.can_upgrade_building(tray.building_id), "36: the fit is available")
	_assert_true(po.upgrade_offer_button.visible and "Mk II" in po.upgrade_offer_button.text or "fit Grow Tray Mk II" in po.objective_label.text, "36: the fit is offered again (%s / %s)" % [po.upgrade_offer_button.text, po.objective_label.text])
	game.select_building(tray.building_id)
	po.refresh()
	_assert_false(po.fixture_upgrade_button.disabled, "36: inspector FIT is enabled")
	po._on_fixture_upgrade_pressed()
	_assert_equal(tray.upgrade_tier, VaultBuilding.UPGRADE_TIER_MAX, "36: the inspector purchase fits the tray")
	_assert_equal(game.food_system.salvage, 18, "36: 18 salvage left")
	_assert_true(game.food_system.salvage >= game.queued_build_commitment(), "36: the 18 left still covers the Charge commitment")
	_dispose(game)


# Codex #148 issuecomment-7015041480: a held "YOU spend N: build X" must not keep
# Spend live, or place, after spendable salvage drops below N.
func _test_held_spend_afford() -> void:
	var game := _air_game(false, 14)
	game.user_paused = true
	var text := _show(game)
	_assert_equal(text, "Next: YOU spend 14: build Air Recycler · THEY craft it", "14: Next names the Air spend (%s)" % text)
	_assert_equal(_spend_text(game), "Spend 14: build Air Recycler", "14: Spend offers the Air Recycler (%s)" % _spend_text(game))
	_assert_equal(game.food_plan_spendable(), 14, "14: spendable covers Air")

	# Drop salvage while the spend step is still displayed. Refresh the button
	# only, so Next still names the spend: Spend must hide (button guard).
	game.food_system.salvage = 13
	_assert_equal(game.food_plan_spendable(), 13, "13: spendable is short of Air")
	game.player_orders._refresh_upgrade_offer()
	_assert_equal(_spend_text(game), "", "13: Spend hides once the named build is unaffordable")

	# Click must not place even if the button were still live (click guard).
	var before := _count_kind(game, VaultBuilding.Kind.AIR_RECYCLER)
	game.player_orders._on_upgrade_offer_pressed()
	_assert_equal(_count_kind(game, VaultBuilding.Kind.AIR_RECYCLER), before, "13: a Spend press queues no Air Recycler")
	_assert_true(game.food_plan_spendable() >= 0, "13: spendable stays non-negative (%d)" % game.food_plan_spendable())
	_assert_equal(game.food_system.salvage, 13, "13: stock is unchanged")
	_assert_true("Needs 14 salvage free" in game.status_message, "13: the press explains the shortfall (%s)" % game.status_message)
	_dispose(game)

	# Hold is invalid: a full refresh re-chooses immediately, with no 2s linger.
	var held := _air_game(false, 14)
	held.user_paused = true
	var held_text := _show(held)
	_assert_equal(held_text, "Next: YOU spend 14: build Air Recycler · THEY craft it", "hold pre: Next names the Air spend (%s)" % held_text)
	held.food_system.salvage = 13
	var after := _show(held)
	_assert_false(after.begins_with("Next: YOU spend "), "13: the held spend is dropped once it is unaffordable (%s)" % after)
	_assert_true("YOU place Air Recycler" in after, "13: Next returns to the place wording (%s)" % after)
	_dispose(held)

	# At 14, a press still queues one.
	var ok := _air_game(false, 14)
	ok.user_paused = true
	_show(ok)
	var start := _count_kind(ok, VaultBuilding.Kind.AIR_RECYCLER)
	_press(ok)
	_assert_equal(_count_kind(ok, VaultBuilding.Kind.AIR_RECYCLER), start + 1, "14: a Spend press still queues one Air Recycler")
	_dispose(ok)


# Codex #148 issuecomment-7019217243: the fallback Spend nudge (Air warning and
# salvage_nudge_kind) must not offer or queue a build on stock owed to a queued blueprint.
func _test_fallback_nudge_spendable() -> void:
	var air := _air_game(true, 14)
	air.user_paused = true
	_show(air)
	_queue_unpaid(air, VaultBuilding.Kind.LAMP, 0)
	var air_text := _show(air)
	_assert_equal(air.food_system.salvage, 14, "air raw 14")
	_assert_equal(air.food_plan_spendable(), 9, "air free 9 after the 5-salvage Lumen")
	_assert_false(air_text.begins_with("Next: YOU spend "), "air 9 free: Next is not a named spend (%s)" % air_text)
	_assert_equal(_spend_text(air), "", "air 9 free: Spend hides the Air nudge")
	var airs := _count_kind(air, VaultBuilding.Kind.AIR_RECYCLER)
	air.player_orders._on_upgrade_offer_pressed()
	_assert_equal(_count_kind(air, VaultBuilding.Kind.AIR_RECYCLER), airs, "air 9 free: a Spend press queues no Air Recycler")
	_dispose(air)
	var air_ok := _air_game(true, 19)
	air_ok.user_paused = true
	_show(air_ok)
	_queue_unpaid(air_ok, VaultBuilding.Kind.LAMP, 0)
	_show(air_ok)
	_assert_equal(air_ok.food_plan_spendable(), 14, "air free 14 covers Air after the Lumen")
	_assert_equal(_spend_text(air_ok), "Spend 14: build Air Recycler", "air 14 free: Spend offers Air (%s)" % _spend_text(air_ok))
	var airs_ok := _count_kind(air_ok, VaultBuilding.Kind.AIR_RECYCLER)
	_press(air_ok)
	_assert_equal(_count_kind(air_ok, VaultBuilding.Kind.AIR_RECYCLER), airs_ok + 1, "air 14 free: a press queues one Air Recycler")
	_dispose(air_ok)
	var rec := _seal_base(true, true, false)
	rec.food_system.salvage = 10
	rec.user_paused = true
	_show(rec)
	_queue_unpaid(rec, VaultBuilding.Kind.LAMP, 0)
	var rec_text := _show(rec)
	_assert_equal(rec.player_orders.salvage_nudge_kind(), VaultBuilding.Kind.RECREATION_CONSOLE, "pre: raw 10 still nudges a Rec")
	_assert_equal(rec.food_plan_spendable(), 5, "rec free 5 after the Lumen")
	_assert_false(rec_text.begins_with("Next: YOU spend "), "rec: Next is not a named spend (%s)" % rec_text)
	_assert_equal(_spend_text(rec), "", "rec 5 free: Spend hides the Rec nudge")
	var recs := _count_kind(rec, VaultBuilding.Kind.RECREATION_CONSOLE)
	rec.player_orders._on_upgrade_offer_pressed()
	_assert_equal(_count_kind(rec, VaultBuilding.Kind.RECREATION_CONSOLE), recs, "rec 5 free: a Spend press queues no Rec")
	rec.food_system.salvage = 13
	_show(rec)
	_assert_equal(_spend_text(rec), "Spend 8: build Rec Console", "rec 8 free: Spend offers the Rec (%s)" % _spend_text(rec))
	_press(rec)
	_assert_equal(_count_kind(rec, VaultBuilding.Kind.RECREATION_CONSOLE), recs + 1, "rec 8 free: a press queues one Rec")
	_dispose(rec)

func _test_threshold() -> void:
	var game := _air_game(false, 13)
	var first := _show(game)
	_assert_true("YOU place Air Recycler" in first, "13 salvage starts on the place wording (%s)" % first)
	game.food_system.salvage = 14
	var saw_place := 0.0
	var switches := 0
	var last := first
	var now := game.day_cycle.elapsed_seconds
	while game.day_cycle.elapsed_seconds - now <= PlayerOrders.NEXT_HOLD_S + 0.6:
		game.day_cycle.elapsed_seconds += 0.1
		var text := _show(game)
		if text != last:
			switches += 1
			last = text
		if "YOU place Air Recycler" in text:
			saw_place += 0.1
	_assert_true(switches <= 1, "affordability crosses at most once (%d switches, last %s)" % [switches, last])
	_assert_true(saw_place <= PlayerOrders.NEXT_HOLD_S + 0.1 + 0.000001, "place does not outlast one hold window after it is affordable (%.1f s, last %s)" % [saw_place, last])
	_assert_true("YOU spend 14: build Air Recycler" in last, "the line settles on the spend wording (%s)" % last)
	game.food_system.salvage = 13
	var down_place := 0.0
	var down_switches := 0
	var down_last := last
	var down_now := game.day_cycle.elapsed_seconds
	while game.day_cycle.elapsed_seconds - down_now <= PlayerOrders.NEXT_HOLD_S + 0.6:
		game.day_cycle.elapsed_seconds += 0.1
		var text := _show(game)
		if text != down_last:
			down_switches += 1
			down_last = text
		if "YOU place Air Recycler" in text:
			down_place += 0.1
	_assert_true(down_switches <= 1, "dropping below the cost switches at most once (%d)" % down_switches)
	_assert_true("YOU place Air Recycler" in down_last, "the line returns to place when it is no longer affordable (%s)" % down_last)
	_dispose(game)


func _test_all_five_kinds() -> void:
	var rows: Array = [
		[_station_game(20), "Next: YOU spend 10: build Nutrient Station · THEY cook/haul"],
		[_rec_game(20), "Next: YOU spend 8: build Rec Console · THEY recover mood"],
		[_tray_game(20), "Next: YOU spend 12: build Grow Tray · THEY haul output"],
		[_shed_game(20), "Next: YOU spend 18: build Charge Node · THEY power the Rec Console"],
		[_air_game(false, 20), "Next: YOU spend 14: build Air Recycler · THEY craft it"],
	]
	for row: Array in rows:
		var game: VaultGame = row[0]
		var want: String = row[1]
		var text := _show(game)
		_assert_equal(text, want, "rewrite text (%s)" % text)
		_assert_false(" a " in text.get_slice(" · ", 0) or " an " in text.get_slice(" · ", 0), "the first clause drops a/an (%s)" % text)
		_assert_equal(str(game.player_orders._displayed_next_step.get("action", "")), "spend", "each kind is a spend (%s)" % text)
		_dispose(game)


func _food_both_missing(salvage: int) -> VaultGame:
	var game := _tray_game(salvage)
	var drop: Array[VaultBuilding] = []
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.KITCHEN:
			drop.append(building)
	for building: VaultBuilding in drop:
		game.buildings.erase(building)
		if building.get_parent() != null:
			building.get_parent().remove_child(building)
		building.free()
	game.power_grid.recalculate(game.buildings)
	game.food_system.salvage = salvage
	return game


func _test_food_card() -> void:
	# No Station and no tray: Next names the tray spend, while the card's default
	# offer would be the Station. lead_kind must make the card follow Next.
	var game := _food_both_missing(20)
	var text := _show(game)
	_assert_equal(text, "Next: YOU spend 12: build Grow Tray · THEY haul output", "Next names the tray spend (%s)" % text)
	var button := _food_button(game)
	_assert_true(button != null and "Grow Tray" in button.text, "the food card follows Next's tray (%s)" % (button.text if button else "none"))
	_assert_false(button != null and "Nutrient Station" in button.text, "the card does not keep its default Station offer (%s)" % (button.text if button else "none"))
	_assert_equal(_spend_text(game), "Spend 12: build Grow Tray", "Spend names the same tray (%s)" % _spend_text(game))
	# Urgent food-recovery wording is unchanged: a named starving place step is not rewritten.
	var urgent := _station_game(20)
	urgent.food_system.meals = 0
	urgent.residents[1].needs.food = 0.0
	urgent.residents[1].needs.health = 20.0
	var urgent_text := _show(urgent)
	_assert_true(urgent_text.begins_with("Next: Bo starving · YOU place a Nutrient Station"), "urgent food recovery keeps its place wording (%s)" % urgent_text)
	_assert_true(bool(urgent.player_orders._displayed_next_step.get("urgent", false)), "the starving step stays urgent")
	_dispose(game)
	_dispose(urgent)


func _test_negatives() -> void:
	var unafford := _air_game(false, 5)
	var unafford_text := _show(unafford)
	_assert_true("YOU place Air Recycler" in unafford_text and not unafford_text.begins_with("Next: YOU spend "), "unaffordable Air stays a place or fund step (%s)" % unafford_text)
	_dispose(unafford)

	var pre := _spawn_game()
	pre.new_game(false, 4242, 5)
	pre.begin_shift()
	pre.user_paused = true
	pre.food_system.salvage = 20
	var pre_text := _show(pre)
	_assert_false(pre.breach_system.is_sealed(), "pre: hatch is not sealed")
	_assert_false(pre_text.begins_with("Next: YOU spend "), "pre-seal Next is unchanged by the spend rewrite (%s)" % pre_text)
	_dispose(pre)

	var urgent_air := _air_game(true, 20)
	urgent_air.oxygen_system.oxygen = 20.0
	urgent_air.oxygen_system.refresh_rates(urgent_air.residents, urgent_air.buildings, false)
	for resident: VaultResident in urgent_air.residents:
		resident.needs.health = 20.0
	var ari := _show(urgent_air)
	_assert_true(ari.begins_with("Next: Ari low on air · YOU place Air Recycler"), "urgent low-on-air place wording is unchanged (%s)" % ari)
	_assert_true(bool(urgent_air.player_orders._displayed_next_step.get("urgent", false)), "the low-on-air step stays urgent")
	_dispose(urgent_air)

	var kr := _spawn_game()
	kr.begin_shift()
	_add_completed_building(kr, VaultBuilding.Kind.BED, Vector2i(18, 12))
	_add_completed_building(kr, VaultBuilding.Kind.BED, Vector2i(19, 12))
	kr.day_cycle.deserialize({"elapsed_seconds": 70.0, "current_day": 2, "completed": false})
	kr.breach_system.advance(0.0, 70.0)
	kr.breach_system.patch_delivered = BreachSystem.PATCH_COST
	kr.breach_system.apply_patch_work(100.0)
	kr.job_system.rebuild_from_state()
	kr.day_cycle.deserialize({"elapsed_seconds": 279.5, "current_day": 7, "completed": false})
	kr.oxygen_system.oxygen = 100.0
	kr.step_simulation(1.0)
	_assert_true(kr.start_keep_running(), "KEEP RUNNING starts")
	for resident: VaultResident in kr.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
	kr.food_system.salvage = 20
	kr.player_orders.refresh()
	kr.keep_running_seconds += 3.0
	var kr_text := _show(kr)
	_assert_equal(kr_text, "Next: YOU spend 8: build Rec Console · THEY craft", "keep-running spend wording is unchanged (%s)" % kr_text)
	_dispose(kr)

	var bunks := _plateau(false, false)
	bunks.food_system.salvage = 20
	var bunk_text := _show(bunks)
	_assert_true(bunk_text.begins_with("Next: YOU place ") and "bunk" in bunk_text, "a bunk place step is unchanged (%s)" % bunk_text)
	_assert_true(_spend_text(bunks).begins_with("Spend ") and "bunk" in _spend_text(bunks), "Spend still places bunks (%s)" % _spend_text(bunks))
	_dispose(bunks)

	var finish := _plateau()
	var queued := 0
	for cell: Vector2i in finish.player_orders.spend_build_cells(VaultBuilding.Kind.BED):
		if queued >= 2:
			break
		if finish.place_blueprint(VaultBuilding.Kind.BED, cell):
			queued += 1
	finish.food_system.salvage = 40
	var finish_text := _show(finish)
	_assert_true("finish the bunks" in finish_text, "finish-the-bunks stays Next (%s)" % finish_text)
	_assert_equal(_spend_text(finish), "", "finish-the-bunks still hides Spend")
	_dispose(finish)

	var med := _seal_base(true, true, true)
	med.residents[1].needs.health = 20.0
	med.food_system.salvage = 20
	var med_text := _show(med)
	_assert_true("YOU place a Med Bed" in med_text and not med_text.begins_with("Next: YOU spend "), "a Medical Bed place step is unchanged (%s)" % med_text)
	_dispose(med)

	var hold := _air_game(false, 20)
	_queue_unpaid(hold, VaultBuilding.Kind.AIR_RECYCLER, 0)
	hold.food_system.meals = 0
	hold.residents[1].needs.food = 0.0
	hold.residents[1].needs.health = 5.0
	var hold_text := _show(hold)
	_assert_true(bool(hold.player_orders._displayed_next_step.get("hold_air_finish", false)), "pre: hold_air_finish is set")
	_assert_true("YOU leave Haul + Craft on · THEY finish the Air Recycler" in hold_text, "hold_air_finish keeps its finish wording (%s)" % hold_text)
	_assert_equal(_spend_text(hold), "", "hold_air_finish still hides Spend")
	_dispose(hold)


func _busy_crew(game: VaultGame) -> void:
	for resident: VaultResident in game.residents:
		resident.state = "Sleeping"
		resident.drafted = false


func _hold_day7_game() -> VaultGame:
	var game := _seal_base(true, true, true)
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
	game.food_system.meals = 100
	game.food_system.raw_food = 0
	game.oxygen_system.oxygen = 100.0
	_busy_crew(game)
	return game


func _tighten_power(game: VaultGame, below: int) -> void:
	var i := 0
	while game.player_orders._planned_power_spare() >= below and i < 40:
		_add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(16 + (i % 8), 11 - int(i / 8)))
		game.power_grid.recalculate(game.buildings)
		i += 1
	_assert_true(game.player_orders._planned_power_spare() < below, "grid spare is below %d (spare=%d after %d lumens)" % [below, game.player_orders._planned_power_spare(), i])


func _set_spare_to(game: VaultGame, target: int) -> void:
	var i := 0
	while game.player_orders._planned_power_spare() > target and i < 40:
		_add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(16 + (i % 8), 11 - int(i / 8)))
		game.power_grid.recalculate(game.buildings)
		i += 1
	_assert_equal(game.player_orders._planned_power_spare(), target, "grid spare is %d (got %d after %d lumens)" % [target, game.player_orders._planned_power_spare(), i])


func _test_hold_day7_mk2_busy() -> void:
	var game := _hold_day7_game()
	var tray: VaultBuilding = null
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY:
			building.upgrade_tier = VaultBuilding.UPGRADE_TIER_BASE
			tray = building
	game.food_system.salvage = 18
	_assert_false(game.player_orders._has_idle_crew(), "pre: crew is not idle")
	_assert_true(tray != null, "pre: a Grow Tray can take Mk II")
	_assert_equal(game.food_plan_spendable(), 18, "pre: spendable covers the fit")
	var text := _show(game)
	_assert_false(game.player_orders._has_idle_crew(), "after refresh the crew is still not idle")
	_assert_true("YOU spend 18: fit Grow Tray Mk II" in text, "busy hold Day 7 names the Grow Tray fit (%s)" % text)
	_assert_false("hold Day 7" in text, "busy hold Day 7 is rewritten (%s)" % text)
	_assert_true(_spend_text(game).find("Grow Tray Mk II") >= 0 or "Mk II" in _spend_text(game), "Spend offers the Grow Tray fit (%s)" % _spend_text(game))
	_assert_true(game.player_orders.also_text().begins_with("Also: fit Grow Tray Mk II"), "Also names the Grow Tray fit (%s)" % game.player_orders.also_text())
	game.select_building(tray.building_id)
	game.player_orders.refresh()
	game.player_orders._on_fixture_upgrade_pressed()
	_assert_equal(tray.upgrade_tier, VaultBuilding.UPGRADE_TIER_MAX, "a press fits the tray")
	_assert_equal(game.food_system.salvage, 0, "the fit spent 18")
	_dispose(game)


func _test_hold_day7_mk2_short() -> void:
	var game := _hold_day7_game()
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY:
			building.upgrade_tier = VaultBuilding.UPGRADE_TIER_BASE
	game.food_system.salvage = 17
	_assert_false(game.player_orders._has_idle_crew(), "pre: crew is not idle")
	var text := _show(game)
	_assert_equal(text, "Next: YOU designate needs · THEY hold Day 7", "17 salvage keeps the designate hold (%s)" % text)
	_assert_false(game.player_orders.also_text().begins_with("Also: fit"), "17: no Also fit line (%s)" % game.player_orders.also_text())
	var tier := VaultBuilding.UPGRADE_TIER_BASE
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY:
			tier = building.upgrade_tier
			game.select_building(building.building_id)
			game.player_orders.refresh()
			game.player_orders._on_fixture_upgrade_pressed()
	_assert_equal(tier, VaultBuilding.UPGRADE_TIER_BASE, "17: no tray is fitted")
	_assert_equal(game.food_system.salvage, 17, "17: no salvage spent")
	_dispose(game)


func _test_hold_day7_charge_busy() -> void:
	var game := _hold_day7_game()
	# A second Grow Tray, already Mk II, so no fit remains. Do not claim wing
	# orders, so Charge / Air Mk II stay locked.
	var tray2 := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(27, 11))
	tray2.upgrade_tier = VaultBuilding.UPGRADE_TIER_MAX
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY:
			building.upgrade_tier = VaultBuilding.UPGRADE_TIER_MAX
	game.power_grid.recalculate(game.buildings)
	_tighten_power(game, 2)
	game.food_system.salvage = 18
	game.food_system.raw_food = 0
	_assert_equal(game.player_orders._upgrade_offer_target(), null, "pre: no Mk II target remains")
	_assert_equal(game.player_orders.salvage_nudge_kind(), -1, "pre: raw 0 hides the regular salvage nudge")
	_assert_true(game.player_orders._planned_power_spare() < 2, "pre: power cannot cover a second kitchen")
	_assert_false(game.player_orders._has_idle_crew(), "pre: crew is not idle")
	var before := _count_kind(game, VaultBuilding.Kind.GENERATOR)
	var text := _show(game)
	_assert_false(game.player_orders._has_idle_crew(), "after refresh the crew is still not idle")
	_assert_true("YOU spend 18: build Charge Node" in text, "busy hold Day 7 names Charge (%s)" % text)
	_assert_equal(_spend_text(game), "Spend 18: build Charge Node", "Spend agrees with Charge (%s)" % _spend_text(game))
	# Raw crossing NUDGE_RAW_PILE must not drop or flicker the Charge spend.
	for raw in [0, 6, 0]:
		game.food_system.raw_food = raw
		game.day_cycle.elapsed_seconds += PlayerOrders.NEXT_HOLD_S + 0.1
		_busy_crew(game)
		game.player_orders.refresh()
		_assert_true("YOU spend 18: build Charge Node" in game.player_orders.objective_label.text, "raw %d keeps the Charge spend (%s)" % [raw, game.player_orders.objective_label.text])
		_assert_equal(_spend_text(game), "Spend 18: build Charge Node", "raw %d: Spend still agrees (%s)" % [raw, _spend_text(game)])
	_press(game)
	_assert_equal(_count_kind(game, VaultBuilding.Kind.GENERATOR), before + 1, "a Spend press queues a Charge Node")
	_assert_equal(game.queued_build_commitment(), 18, "the queued Charge still owes 18")
	_assert_equal(game.food_plan_spendable(), 0, "free stock is now held for the Charge")
	_dispose(game)


func _test_hold_day7_charge_short() -> void:
	var game := _hold_day7_game()
	var tray2 := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(27, 11))
	tray2.upgrade_tier = VaultBuilding.UPGRADE_TIER_MAX
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY:
			building.upgrade_tier = VaultBuilding.UPGRADE_TIER_MAX
	game.power_grid.recalculate(game.buildings)
	_tighten_power(game, 2)
	game.food_system.salvage = 17
	game.food_system.raw_food = 0
	var before := _count_kind(game, VaultBuilding.Kind.GENERATOR)
	var text := _show(game)
	_assert_equal(text, "Next: YOU designate needs · THEY hold Day 7", "17 salvage keeps the designate hold (%s)" % text)
	_press(game)
	_assert_equal(_count_kind(game, VaultBuilding.Kind.GENERATOR), before, "17: no Charge Node is queued")
	_assert_equal(game.food_system.salvage, 17, "17: no salvage spent")
	_dispose(game)


func _test_hold_day7_power_covers_kitchen() -> void:
	var game := _hold_day7_game()
	var tray2 := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, Vector2i(27, 11))
	tray2.upgrade_tier = VaultBuilding.UPGRADE_TIER_MAX
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY:
			building.upgrade_tier = VaultBuilding.UPGRADE_TIER_MAX
	game.power_grid.recalculate(game.buildings)
	_assert_true(game.player_orders._planned_power_spare() >= 2, "pre: spare covers a second kitchen (spare=%d)" % game.player_orders._planned_power_spare())
	game.food_system.salvage = 18
	game.food_system.raw_food = 0
	var before_charge := _count_kind(game, VaultBuilding.Kind.GENERATOR)
	var before_kitchen := _count_kind(game, VaultBuilding.Kind.KITCHEN)
	var text := _show(game)
	_assert_equal(text, "Next: YOU designate needs · THEY hold Day 7", "with spare power and no raw pile, hold Day 7 stays (%s)" % text)
	_assert_false("Charge Node" in text or "Nutrient Station" in text, "no invented kitchen or Charge spend (%s)" % text)
	_press(game)
	_assert_equal(_count_kind(game, VaultBuilding.Kind.GENERATOR), before_charge, "no Charge Node is queued")
	_assert_equal(_count_kind(game, VaultBuilding.Kind.KITCHEN), before_kitchen, "no Nutrient Station is queued")
	_dispose(game)


func _test_hold_day7_charge_tray_blocked() -> void:
	# Spare 2 covers a second kitchen (demand 2) but not a second tray (demand 3).
	var game := _hold_day7_game()
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY:
			building.upgrade_tier = VaultBuilding.UPGRADE_TIER_MAX
	game.power_grid.recalculate(game.buildings)
	_set_spare_to(game, 2)
	game.food_system.salvage = 18
	game.food_system.raw_food = 0
	_assert_equal(game.player_orders._upgrade_offer_target(), null, "pre: no Mk II target remains")
	_assert_equal(_count_kind(game, VaultBuilding.Kind.GROW_TRAY), 1, "pre: only one Grow Tray")
	_assert_true(game.player_orders._planned_power_spare() >= 2, "pre: spare covers a kitchen")
	_assert_true(game.player_orders._planned_power_spare() < 3, "pre: spare does not cover a second tray")
	var text := _show(game)
	_assert_true("YOU spend 18: build Charge Node" in text, "a tray-blocked grid names Charge (%s)" % text)
	_dispose(game)


func _test_hold_day7_rec_outranks_charge() -> void:
	var game := _seal_base(true, true, false)
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 39.0
		resident.needs.health = 100.0
	game.food_system.meals = 100
	game.food_system.raw_food = 0
	game.oxygen_system.oxygen = 100.0
	_busy_crew(game)
	_set_spare_to(game, 1)
	game.food_system.salvage = 18
	_assert_true(game.player_orders._planned_power_spare() >= 1, "pre: spare covers Rec")
	var text := _show(game)
	_assert_false("Charge Node" in text, "an affordable Rec is not displaced by Charge (%s)" % text)
	_assert_true("Rec Console" in text or "hold Day 7" in text, "Next stays with Rec or the designate hold (%s)" % text)
	_dispose(game)


func _test_hold_day7_commit_short() -> void:
	var game := _hold_day7_game()
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY:
			building.upgrade_tier = VaultBuilding.UPGRADE_TIER_BASE
	_queue_unpaid(game, VaultBuilding.Kind.LAMP, 0)
	game.food_system.salvage = 22
	_assert_equal(game.queued_build_commitment(), 5, "pre: the Lumen owes 5")
	_assert_equal(game.food_plan_spendable(), 17, "pre: spendable is 17 after the Lumen commitment")
	_assert_false(game.player_orders._has_idle_crew(), "pre: crew is not idle")
	var text := _show(game)
	_assert_equal(text, "Next: YOU designate needs · THEY hold Day 7", "raw 22 / spendable 17 keeps the designate hold (%s)" % text)
	_assert_false(game.player_orders.also_text().begins_with("Also: fit"), "17 free: no Also fit line (%s)" % game.player_orders.also_text())
	_dispose(game)


func _test_hold_day7_threshold() -> void:
	var game := _hold_day7_game()
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY:
			building.upgrade_tier = VaultBuilding.UPGRADE_TIER_BASE
	game.food_system.salvage = 17
	var text := _show(game)
	_assert_equal(text, "Next: YOU designate needs · THEY hold Day 7", "17: hold Day 7 stays (%s)" % text)
	game.food_system.salvage = 18
	_busy_crew(game)
	game.day_cycle.elapsed_seconds += PlayerOrders.NEXT_HOLD_S + 0.1
	_busy_crew(game)
	game.player_orders.refresh()
	_assert_false(game.player_orders._has_idle_crew(), "18: crew is still not idle")
	_assert_true("YOU spend 18: fit Grow Tray Mk II" in game.player_orders.objective_label.text, "18 after one hold window names the fit (%s)" % game.player_orders.objective_label.text)
	_dispose(game)

func _test_hold_day7_mk2_committed_stock() -> void:
	var game := _hold_day7_game()
	for building: VaultBuilding in game.buildings:
		if building.kind == VaultBuilding.Kind.GROW_TRAY:
			building.upgrade_tier = VaultBuilding.UPGRADE_TIER_BASE
	_queue_unpaid(game, VaultBuilding.Kind.GENERATOR, 0)
	game.food_system.salvage = 18
	_assert_equal(game.queued_build_commitment(), 18, "the queued Charge owes 18")
	_assert_equal(game.food_plan_spendable(), 0, "stock that covers the Charge is not free")
	_assert_false(game.player_orders._has_idle_crew(), "pre: crew is not idle")
	var text := _show(game)
	_assert_equal(text, "Next: YOU designate needs · THEY hold Day 7", "committed stock does not name a Mk II fit (%s)" % text)
	_dispose(game)

