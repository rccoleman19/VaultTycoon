extends "res://tests/test_air_early_warning.gd"

# Light-touch playtest 2 (05 s1234, 120.4 s): "Spend 8: build Rec Console" only armed the Rec
# tool, nothing was built and Next asked for a Rec Console for 137 s. One Spend press for a
# named build now queues its blueprint on free floor, or says there is none.


func _run() -> void:
	_run_case("05 s1234: one Spend press queues the named build and Next moves on", _test_spend_queues)
	_run_case("with no free floor Spend says so and leaves no tool armed", _test_no_floor)
	print("")
	if _failure_count == 0:
		print("SPEND PLACES BUILD TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("SPEND PLACES BUILD TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [
			_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _idle(seed_value: int) -> VaultGame:
	var game := _spawn_game()
	game.new_game(false, seed_value, 5)
	game.begin_shift()
	return game


# Steps to the first "Spend N: build X" offer; returns X ("" if none by 240 s).
func _to_spend_build(game: VaultGame) -> String:
	var regex := RegEx.create_from_string("^Spend \\d+: build (.+)$")
	while game.day_cycle.elapsed_seconds < 240.0 and not game.ended:
		game.step_simulation(SAMPLE_S)
		game.player_orders.refresh()
		var found := regex.search(_spend_text(game))
		if found != null:
			return found.get_string(1)
	return ""


func _blueprints(game: VaultGame, build_name: String) -> Array[VaultBuilding]:
	var out: Array[VaultBuilding] = []
	for building: VaultBuilding in game.buildings:
		if not building.complete and building.get_display_name() == build_name:
			out.append(building)
	return out


func _test_spend_queues() -> void:
	var game := _idle(1234)
	var build_name := _to_spend_build(game)
	_assert_false(build_name.is_empty(), "the idle wing offers a Spend build (%s)" % build_name)
	print("SPEND OFFER %s at %.1f s" % [build_name, game.day_cycle.elapsed_seconds])
	var before := _blueprints(game, build_name).size()
	game.player_orders.upgrade_offer_button.pressed.emit()
	game.player_orders.refresh()
	var queued := _blueprints(game, build_name)
	_assert_equal(queued.size(), before + 1, "one press queues one %s blueprint" % build_name)
	_assert_equal(game.active_tool, "select", "no placement tool is left armed")
	var help: String = game.player_orders.tool_status.text
	_assert_true(help.contains("%s placed · THEY build it" % build_name), "the help line says it was placed (%s)" % help)
	if not queued.is_empty():
		var cell := queued[-1].cell
		_assert_true(cell != BreachSystem.HATCH_CELL and game.map_grid.is_walkable(cell), "it sits on carved floor off the hatch (%s)" % str(cell))
		game.set_tool("cancel")
		_assert_true(game.issue_order(cell), "the usual cancel removes it")
		game.set_tool("select")
		_assert_equal(_blueprints(game, build_name).size(), before, "and it is gone")
		game.player_orders.upgrade_offer_button.pressed.emit()
	game.status_message_left = 0.0
	for i in 4:
		game.step_simulation(SAMPLE_S)
	game.player_orders.refresh()
	var next: String = game.player_orders.objective_label.text
	_assert_false(next.contains("place a %s" % build_name) or next.contains("build %s" % build_name), "Next no longer asks for the %s (%s)" % [build_name, next])
	_assert_false(_spend_text(game).contains("build %s" % build_name), "and Spend no longer offers it (%s)" % _spend_text(game))
	_dispose(game)


func _test_no_floor() -> void:
	var game := _idle(1234)
	var build_name := _to_spend_build(game)
	# Cover every free floor tile, so nothing is left to build on.
	for y in MapGrid.HEIGHT:
		for x in MapGrid.WIDTH:
			var cell := Vector2i(x, y)
			if cell != BreachSystem.HATCH_CELL and game.map_grid.is_walkable(cell) and game.get_building_at(cell) == null:
				game.place_blueprint(VaultBuilding.Kind.LAMP, cell)
	var count := game.buildings.size()
	var kind: Variant = VaultBuilding.KIND_NAMES.find_key(build_name)
	_assert_true(kind != null, "the offer names a build kind (%s)" % build_name)
	game.set_tool("select")
	game.player_orders.refresh()
	if _spend_text(game).ends_with("build %s" % build_name):
		game.player_orders.upgrade_offer_button.pressed.emit()
	else:
		_assert_false(game.player_orders.place_spend_build(int(kind)), "Spend cannot place it")
	game.player_orders.refresh()
	_assert_equal(game.buildings.size(), count, "nothing new is queued")
	_assert_equal(game.active_tool, "select", "no placement tool is armed silently")
	var help: String = game.player_orders.tool_status.text
	_assert_true(help.contains("No free floor for %s · dig more" % build_name), "the help line says why (%s)" % help)
	_dispose(game)
