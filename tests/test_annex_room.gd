extends "res://tests/test_runner.gd"

# Codex P2 on #111 (issuecomment-6268064046): the Annex payoff is all or nothing. With fewer free
# floor cells than its four fixtures it waits (quotas kept, nobody moves in, a clear "free N floor
# cells" message), re-checks every tick and after a load, then grants all four plus Eko at once.

const ROOM_SAVE := "user://test_annex_room.json"
const ROOM_STATUS := "ANNEX READY: free %s for its bunk, Grow Tray, Nutrient Station and Charge Node."
const ROOM_HEADER := "ANNEX READY · free %s"
const ROOM_NEXT := "Next: YOU free %s · THEY open the Annex"
const FIXTURES := [VaultBuilding.Kind.BED, VaultBuilding.Kind.GROW_TRAY, VaultBuilding.Kind.KITCHEN, VaultBuilding.Kind.GENERATOR]


func _run() -> void:
	_run_case("with 0 to 3 free floor cells the Annex waits and grants nothing", _test_waits)
	_run_case("clearing a zone opens the Annex on the next tick with all four fixtures", _test_unzone_opens)
	_run_case("digging new floor opens the Annex with all four fixtures", _test_dig_opens)
	_run_case("a waiting Annex survives save and load, then opens once there is room", _test_reload_waiting)
	_run_case("room freed before a save opens the Annex as the save loads", _test_reload_opens)
	_run_case("a done Annex missing its resident waits for room instead of a partial payoff", _test_done_missing_resident)
	_run_case("with room the payoff is unchanged and the save shape is the same", _test_happy_path)
	_run_case("room texts fit with 12 px to spare", _test_fit)
	_run_case("while the Annex waits on room, Spend offers no floor build", _test_spend_waits)
	_run_case("while the Annex waits on room, the comfort card hides", _test_comfort_waits)
	print("")
	if _failure_count == 0:
		print("ANNEX ROOM TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("ANNEX ROOM TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _cells(short: int) -> String:
	return "%d floor cell%s" % [short, "" if short == 1 else "s"]


func _running() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	game.day_cycle.deserialize({"elapsed_seconds": 70.0, "current_day": 2, "completed": false})
	game.breach_system.advance(0.0, 70.0)
	game.breach_system.patch_delivered = BreachSystem.PATCH_COST
	game.breach_system.apply_patch_work(100.0)
	game.job_system.rebuild_from_state()
	game.day_cycle.deserialize({"elapsed_seconds": 279.5, "current_day": 7, "completed": false})
	game.oxygen_system.oxygen = 100.0
	game.step_simulation(1.0)
	game.start_keep_running()
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 100.0
		resident.needs.health = 100.0
	return game


func _finish(game: VaultGame) -> void:
	game.annex_meals = VaultGame.ANNEX_MEALS - 1
	game.annex_salvage = VaultGame.ANNEX_SALVAGE - 1
	game.food_system.meals = 20
	game.food_system.salvage = 20
	for i in 60:
		game._advance_annex(0.1)


func _free_count(game: VaultGame) -> int:
	return game._annex_free_cells(9999).size()


# Zone every free floor cell but `cap` (the cells farthest from the chamber center stay free).
func _zone_all_but(game: VaultGame, cap: int) -> void:
	var free := game._annex_free_cells(9999)
	for index in range(0, free.size() - cap):
		game.map_grid.paint_stockpile(free[index])


func _unzone(game: VaultGame, count: int) -> void:
	var cells: Array = game.map_grid.stockpile_cells.keys()
	for index in mini(count, cells.size()):
		game.map_grid.clear_stockpile(cells[index])


func _counts(game: VaultGame) -> Array[int]:
	var counts: Array[int] = []
	for kind: int in FIXTURES:
		var n := 0
		for b: VaultBuilding in game.buildings:
			if b.kind == kind and b.complete:
				n += 1
		counts.append(n)
	return counts


func _plus_one(counts: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for n in counts:
		out.append(n + 1)
	return out


func _assert_waiting(game: VaultGame, short: int, buildings: int, what: String) -> void:
	_assert_false(game.annex_done, "%s: the Annex is not finalized" % what)
	_assert_true(game.keep_running and not game.ended, "%s: still keeping running" % what)
	_assert_equal(game.residents.size(), 4, "%s: nobody moves in yet" % what)
	_assert_true(game.annex_resident() == null, "%s: no Eko" % what)
	_assert_equal(game.buildings.size(), buildings, "%s: no fixture is granted early" % what)
	_assert_equal([game.annex_meals, game.annex_salvage], [VaultGame.ANNEX_MEALS, VaultGame.ANNEX_SALVAGE], "%s: both quotas stay paid" % what)
	game.player_orders.refresh()
	_assert_true(game.player_orders.annex_box.visible, "%s: the card stays" % what)
	_assert_equal(game.player_orders.annex_header.text, ROOM_HEADER % _cells(short), "%s: header names the room" % what)
	_assert_false(game.player_orders.annex_minus_button.get_parent().visible, "%s: no reserve stepper while it waits on room" % what)
	_assert_true(game.comfort_pending(), "%s: comfort is still pending (no Rec Console or Med Bed)" % what)
	_assert_equal(game.player_orders.objective_label.text, ROOM_NEXT % _cells(short), "%s: Next asks for room, over the comfort card" % what)


func _assert_opened(game: VaultGame, counts: Array[int], buildings: int, what: String) -> void:
	_assert_true(game.annex_done, "%s: the Annex is done" % what)
	_assert_equal(game.residents.size(), 5, "%s: five crew" % what)
	var eko := game.annex_resident()
	_assert_true(eko != null and eko.resident_name == "Eko", "%s: Eko moves in" % what)
	_assert_equal(_counts(game), _plus_one(counts), "%s: +1 bunk, Grow Tray, Nutrient Station, Charge Node" % what)
	_assert_equal(game.buildings.size(), buildings + 4, "%s: exactly four fixtures" % what)
	for b: VaultBuilding in game.buildings:
		_assert_false(game.map_grid.stockpile_cells.has(b.cell) and b.kind in FIXTURES and b.building_id >= game.next_building_id - 4, "%s: no payoff fixture on a zone" % what)
	game.player_orders.refresh()
	_assert_false(game.player_orders.annex_header.text.begins_with("ANNEX READY"), "%s: the room header is gone" % what)


func _test_waits() -> void:
	for cap in 4:
		var game := _running()
		_zone_all_but(game, cap)
		_assert_equal(_free_count(game), cap, "fixture has %d free cells" % cap)
		var buildings := game.buildings.size()
		_finish(game)
		var what := "%d free" % cap
		_assert_waiting(game, 4 - cap, buildings, what)
		_assert_equal(game.status_message, ROOM_STATUS % _cells(4 - cap), "%s: status says how much room" % what)
		game.step_simulation(10.0)
		_assert_waiting(game, 4 - cap, buildings, "%s, 10 s later" % what)
		_dispose(game)


func _test_unzone_opens() -> void:
	var game := _running()
	_zone_all_but(game, 2)
	var buildings := game.buildings.size()
	var counts := _counts(game)
	_finish(game)
	_assert_waiting(game, 2, buildings, "2 free")
	_unzone(game, 1)
	game.step_simulation(VaultGame.SIMULATION_TICK)
	_assert_waiting(game, 1, buildings, "3 free")
	_unzone(game, 1)
	game.step_simulation(VaultGame.SIMULATION_TICK)
	_assert_opened(game, counts, buildings, "4 free after one tick")
	_assert_true(game.status_message.begins_with("ANNEX OPEN: Eko moves in"), "the arrival status: %s" % game.status_message)
	_dispose(game)


func _test_dig_opens() -> void:
	var game := _running()
	_zone_all_but(game, 0)
	var buildings := game.buildings.size()
	var counts := _counts(game)
	_finish(game)
	_assert_waiting(game, 4, buildings, "0 free")
	var dug := 0
	for cell: Vector2i in game.map_grid.get_floor_cells():
		for n: Vector2i in game.map_grid.get_neighbors(cell):
			if dug < 4 and n != BreachSystem.HATCH_CELL and game.map_grid.can_queue_dig(n) and game.map_grid.queue_dig(n):
				game.map_grid.apply_dig_work(n, 100.0)
				dug += 1
	_assert_equal(dug, 4, "dug four rock tiles")
	game.step_simulation(VaultGame.SIMULATION_TICK)
	_assert_opened(game, counts, buildings, "after digging")
	_dispose(game)


func _test_reload_waiting() -> void:
	var game := _running()
	_zone_all_but(game, 1)
	var buildings := game.buildings.size()
	var counts := _counts(game)
	_finish(game)
	_assert_waiting(game, 3, buildings, "1 free")
	_remove_test_save(ROOM_SAVE)
	_assert_true(game.save_game(false, ROOM_SAVE), "saved")
	var snapshot := game.create_snapshot()
	_assert_true(game._is_snapshot_shape_valid(snapshot), "a waiting save is valid")
	_assert_false(bool(snapshot[VaultGame.ANNEX_KEY].done), "saved as not done")
	game.new_game(false)
	_assert_true(game.load_game(ROOM_SAVE), "loaded")
	_assert_waiting(game, 3, buildings, "1 free, reloaded")
	_unzone(game, 3)
	game.step_simulation(VaultGame.SIMULATION_TICK)
	_assert_opened(game, counts, buildings, "room freed after reload")
	_assert_true(game.save_game(false, ROOM_SAVE), "saved open")
	game.new_game(false)
	_assert_true(game.load_game(ROOM_SAVE), "loaded open")
	_assert_opened(game, counts, buildings, "reloaded open, nothing doubled")
	_remove_test_save(ROOM_SAVE)
	_dispose(game)


func _test_reload_opens() -> void:
	var game := _running()
	_zone_all_but(game, 0)
	var buildings := game.buildings.size()
	var counts := _counts(game)
	_finish(game)
	_assert_waiting(game, 4, buildings, "0 free")
	game.user_paused = true
	_unzone(game, 4)
	var snapshot := game.create_snapshot()
	_assert_false(bool(snapshot[VaultGame.ANNEX_KEY].done), "saved before any tick re-checked")
	_assert_true(game.apply_snapshot(snapshot), "reload")
	_assert_opened(game, counts, buildings, "opened on load")
	_dispose(game)


func _test_done_missing_resident() -> void:
	var game := _running()
	_finish(game)
	_assert_true(game.annex_done and game.residents.size() == 5, "opened with room")
	_zone_all_but(game, 0)
	var snapshot := game.create_snapshot()
	var crew: Array = snapshot.residents
	crew.resize(4)
	var buildings := (snapshot.buildings as Array).size()
	var counts := _counts(game)
	_assert_true(game.apply_snapshot(snapshot), "a done save without resident 5 loads")
	_assert_equal(game.residents.size(), 4, "no resident without room for the payoff")
	_assert_equal(game.buildings.size(), buildings, "no partial fixtures")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.annex_header.text, ROOM_HEADER % _cells(4), "the card asks for room")
	game.step_simulation(1.0)
	_assert_equal(game.residents.size(), 4, "still waiting a second later")
	_unzone(game, 4)
	game.step_simulation(VaultGame.SIMULATION_TICK)
	_assert_opened(game, counts, buildings, "room freed")
	_dispose(game)


func _test_happy_path() -> void:
	var game := _running()
	var buildings := game.buildings.size()
	var counts := _counts(game)
	_assert_true(_free_count(game) >= 5, "plenty of room")
	_finish(game)
	_assert_opened(game, counts, buildings, "full room")
	_assert_true(game.status_message.begins_with("ANNEX OPEN: Eko moves in"), "arrival status")
	_assert_true(game.map_grid.is_walkable(game.annex_resident().get_cell(game.map_grid)), "Eko on floor")
	var annex: Dictionary = game.create_snapshot()[VaultGame.ANNEX_KEY]
	var keys: Array = annex.keys()
	keys.sort()
	_assert_equal(keys, ["done", "meals", "reserve", "salvage", "version"], "annex save key unchanged")
	_assert_equal(int(annex.version), 1, "annex version 1")
	_assert_equal(SaveLoad.SAVE_VERSION, 1, "SAVE_VERSION unchanged")
	_dispose(game)


func _text_width(control: Control, text: String) -> float:
	return control.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, control.get_theme_font_size("font_size")).x


func _test_fit() -> void:
	var game := _running()
	var orders := game.player_orders
	var width := VaultGame.RIGHT_PANEL_WIDTH
	var node: Node = orders.annex_box.get_parent()
	while node is Control:
		if node is PanelContainer:
			width -= (node as PanelContainer).get_theme_stylebox("panel").get_minimum_size().x
			break
		if node is MarginContainer:
			width -= (node as Control).get_theme_constant("margin_left") + (node as Control).get_theme_constant("margin_right")
		node = node.get_parent()
	var header_room := width - _text_width(orders.annex_header, ROOM_HEADER % _cells(4))
	_assert_true(header_room >= 12.0, "room header fits one line with %.0f px to spare" % header_room)
	var next_room := 2.0 * width - _text_width(orders.objective_label, ROOM_NEXT % _cells(4))
	_assert_true(next_room >= 12.0, "room Next fits two lines with %.0f px to spare" % next_room)
	var select_line := "SELECT // Select a living resident, then [R] to draft/undraft. Right-click: drafted = move; undrafted = force context job."
	var status_room := _text_width(orders.tool_status, select_line) - _text_width(orders.tool_status, "SELECT // " + ROOM_STATUS % _cells(4))
	_assert_true(status_room >= 12.0, "room status is %.0f px shorter than the select help the bar fits" % status_room)
	_dispose(game)


func _test_spend_waits() -> void:
	var game := _running()
	_zone_all_but(game, 2)
	# A built Grow Tray on an already-zoned cell: a Mk II fit candidate that takes no free floor.
	var zoned: Vector2i = game.map_grid.stockpile_cells.keys()[0]
	game.map_grid.stockpile_cells.erase(zoned)
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, zoned)
	# Mk II fits wait on a finished, powered Air Recycler (NX37); it and its Charge Node sit on zoned cells.
	for kind: int in [VaultBuilding.Kind.GENERATOR, VaultBuilding.Kind.AIR_RECYCLER]:
		var cell: Vector2i = game.map_grid.stockpile_cells.keys()[0]
		game.map_grid.stockpile_cells.erase(cell)
		_add_completed_building(game, kind, cell)
	game.power_grid.recalculate(game.buildings)
	_assert_equal(game.get_powered_building_count(VaultBuilding.Kind.AIR_RECYCLER), 1, "the Air Recycler is powered")
	_finish(game)
	game.food_system.salvage = 40
	_assert_true(game.annex_waiting_for_room(), "the paid Annex waits on room")
	_assert_equal(game.annex_room_short(), 2, "two cells short")
	_assert_equal(game.player_orders.salvage_nudge_kind(), -1, "no Spend build while it waits")
	game.player_orders.refresh()
	var button: Button = game.player_orders.upgrade_offer_button
	_assert_false(button.visible and button.text.begins_with("Spend "), "the Spend button offers no build: %s" % button.text)
	var fit: VaultBuilding = game.player_orders._upgrade_offer_target()
	_assert_true(fit != null, "a Mk II fit is affordable in this state")
	if fit != null:
		_assert_true(button.visible and button.text == game.player_orders.upgrade_offer_text(fit), "an in-place Mk II fit stays on offer: %s" % button.text)
	var fits_before := game.buildings.size()
	game.food_system.salvage = 15
	game.player_orders.refresh()
	_assert_false(button.visible and button.text.begins_with("Spend "), "with too little for a fit, still no Spend build: %s" % button.text)
	game.food_system.salvage = 40
	game.player_orders._on_upgrade_offer_pressed()
	_assert_equal(game.buildings.size(), fits_before, "pressing the offer places nothing")
	_assert_true(str(game.active_tool) not in ["kitchen", "rec", "grow", "generator"], "and arms no build tool")
	_unzone(game, 2)
	for i in 3:
		game._advance_annex(0.1)
	_assert_true(game.annex_resident() != null, "with room the Annex opens")
	game.food_system.salvage = 40
	_assert_true(game.player_orders.salvage_nudge_kind() >= 0, "after it opens Spend offers a build again")
	_dispose(game)


func _test_comfort_waits() -> void:
	var game := _running()
	_assert_true(game.has_method("comfort_pending") and "comfort_box" in game.player_orders, "the comfort card exists")
	game.player_orders.refresh()
	_assert_true(game.comfort_pending() and game.player_orders.comfort_box.visible, "before the Annex waits, the comfort card shows")
	_zone_all_but(game, 2)
	_finish(game)
	_assert_true(game.annex_waiting_for_room(), "the paid Annex waits on room")
	game.player_orders.refresh()
	_assert_true(game.comfort_pending(), "comfort is still pending")
	_assert_false(game.player_orders.comfort_box.visible, "but the card hides while the Annex waits")
	_unzone(game, 2)
	for i in 3:
		game._advance_annex(0.1)
	_assert_true(game.annex_resident() != null, "with room the Annex opens")
	game.player_orders.refresh()
	_assert_equal(game.player_orders.comfort_box.visible, game.comfort_pending(), "after it opens the card follows comfort_pending again")
	game.ended = true
	game.player_orders.refresh()
	_assert_false(game.comfort_pending() or game.player_orders.comfort_box.visible, "with nothing pending the card stays hidden")
	game.ended = false
	_dispose(game)
