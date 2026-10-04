extends "res://tests/test_runner.gd"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_build_highlights_and_player_choice()
	_test_help_deferral()
	_test_priorities_deferral()
	_test_other_blockers_and_pause()
	_test_returning_bed("dig")
	_test_returning_bed("select")
	_test_non_build_suggestions()
	_test_same_tool_different_sentence()
	print("Open suggested tab tests: %d assertions, %d failures" % [_assertion_count, _failure_count])
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
	game.food_system.meals = game.get_alive_count()
	return game


func _refresh_and_assert(game: VaultGame, tool: String, tab: String) -> void:
	var active_tool := game.active_tool
	var building_count := game.buildings.size()
	_assert_equal(game.player_orders._primary_next_step()["tool"], tool, "real Next step suggests %s" % tool)
	game.player_orders.refresh()
	_assert_equal(game.player_orders._architect_open_tab, tab, "%s suggestion leaves expected tab %s" % [tool, tab])
	_assert_equal(game.active_tool, active_tool, "refresh preserves active tool")
	_assert_equal(game.buildings.size(), building_count, "refresh does not place a building")


func _test_build_highlights_and_player_choice() -> void:
	var game := _healthy_game()
	var orders := game.player_orders
	game.residents[0].needs.rest = 28.0
	_assert_equal(game.active_tool, "select", "Select starts active")
	_refresh_and_assert(game, "bed", "build")
	_assert_true(orders.command_buttons["bed"].is_visible_in_tree(), "suggested bed button is visible in BUILD")
	_assert_equal(orders.command_buttons["bed"].modulate, Color("75d4b4"), "inactive suggested bed is teal")
	_assert_equal(orders.command_buttons["select"].modulate, Color("efc56b"), "active Select stays gold")
	game.residents[0].needs.food = 19.0
	game.food_system.meals = 0
	_assert_equal(game.get_completed_building_count(VaultBuilding.Kind.KITCHEN), 0, "kitchen suggestion has no completed kitchen")
	_refresh_and_assert(game, "kitchen", "build")
	_assert_equal(orders.command_buttons["kitchen"].modulate, Color("75d4b4"), "inactive suggested kitchen is teal")
	_assert_true(orders.command_buttons["bed"].modulate != Color("75d4b4"), "previous bed suggestion loses teal")
	orders._on_architect_tab_pressed("dig")
	for iteration in 3:
		_refresh_and_assert(game, "kitchen", "dig")
	orders._on_architect_tab_pressed("build")
	orders._on_architect_tab_pressed("build")
	for iteration in 3:
		_refresh_and_assert(game, "kitchen", "")
	game.active_tool = "kitchen"
	_refresh_and_assert(game, "kitchen", "")
	_assert_equal(orders.command_buttons["kitchen"].modulate, Color("efc56b"), "active suggested kitchen stays gold")
	_dispose(game)


func _test_help_deferral() -> void:
	var game := _healthy_game()
	var orders := game.player_orders
	_refresh_and_assert(game, "dig", "")
	orders.open_help()
	_assert_true(not game.tutorial_open and orders.is_help_open(), "ordinary help is open without tutorial")
	game.residents[0].needs.rest = 28.0
	for iteration in 2:
		_refresh_and_assert(game, "bed", "")
	orders.show_briefing(false)
	_refresh_and_assert(game, "bed", "build")
	orders._set_architect_tab("")
	orders.show_briefing(true, false)
	_refresh_and_assert(game, "bed", "")
	orders.show_briefing(false)
	for iteration in 3:
		_refresh_and_assert(game, "bed", "")
	# A different suggestion seen only behind help must not replace handled bed.
	orders.open_help()
	game.residents[0].needs.rest = 100.0
	_refresh_and_assert(game, "dig", "")
	game.residents[0].needs.rest = 28.0
	orders.show_briefing(false)
	_refresh_and_assert(game, "bed", "")
	_dispose(game)


func _test_priorities_deferral() -> void:
	var game := _healthy_game()
	var orders := game.player_orders
	orders.show_work_priorities(true)
	_assert_true(orders.is_work_priorities_open(), "work priorities overlay is open")
	game.residents[0].needs.rest = 28.0
	for iteration in 2:
		_refresh_and_assert(game, "bed", "")
	orders.show_work_priorities(false)
	_refresh_and_assert(game, "bed", "build")
	orders._set_architect_tab("")
	orders.show_work_priorities(true)
	_refresh_and_assert(game, "bed", "")
	orders.show_work_priorities(false)
	_refresh_and_assert(game, "bed", "")
	_dispose(game)


func _test_other_blockers_and_pause() -> void:
	for blocker in ["tutorial", "ended", "breach"]:
		var game := _healthy_game()
		game.residents[0].needs.rest = 28.0
		match blocker:
			"tutorial":
				game.tutorial_open = true
			"ended":
				game.ended = true
			"breach":
				game.breach_system.phase = BreachSystem.Phase.WARNING
				game.breach_system.warning_acknowledged = false
		_refresh_and_assert(game, "bed", "")
		game.tutorial_open = false
		game.ended = false
		game.breach_system.warning_acknowledged = true
		game.user_paused = true
		_refresh_and_assert(game, "bed", "build")
		game.player_orders._set_architect_tab("")
		_refresh_and_assert(game, "bed", "")
		_dispose(game)


func _test_returning_bed(middle_tool: String) -> void:
	var game := _healthy_game()
	var orders := game.player_orders
	game.residents[0].needs.rest = 28.0
	_refresh_and_assert(game, "bed", "build")
	orders._on_architect_tab_pressed("dig")
	game.residents[0].needs.rest = 100.0
	if middle_tool == "select":
		var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
		kitchen.manually_disabled = true
		game.residents[0].needs.food = 19.0
		game.food_system.meals = 0
		_assert_equal(orders._primary_next_step()["text"], "Next: YOU power the Nutrient Station · THEY cook", "Select comes from the real power-kitchen step")
	_refresh_and_assert(game, middle_tool, "dig")
	game.residents[0].needs.food = 100.0
	game.food_system.meals = game.get_alive_count()
	game.residents[0].needs.rest = 28.0
	_refresh_and_assert(game, "bed", "build")
	_dispose(game)


func _test_non_build_suggestions() -> void:
	var game := _healthy_game()
	_refresh_and_assert(game, "dig", "")
	game.player_orders._set_architect_tab("build")
	_refresh_and_assert(game, "dig", "build")
	_dispose(game)
	game = _healthy_game()
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, Vector2i(20, 12))
	kitchen.manually_disabled = true
	game.residents[0].needs.food = 19.0
	game.food_system.meals = 0
	_assert_equal(game.player_orders._primary_next_step()["text"], "Next: YOU power the Nutrient Station · THEY cook", "disabled kitchen suggests Select")
	_refresh_and_assert(game, "select", "")
	game.player_orders._set_architect_tab("dig")
	_refresh_and_assert(game, "select", "dig")
	_dispose(game)


func _test_same_tool_different_sentence() -> void:
	var game := _healthy_game()
	game.residents[0].needs.rest = 28.0
	_refresh_and_assert(game, "bed", "build")
	var first_text: String = game.player_orders._primary_next_step()["text"]
	game.player_orders._set_architect_tab("")
	game.residents[0].needs.rest = 100.0
	# Expand by twelve floors to reach the planned two-bunk step.
	for x in range(17, 29):
		var cell := Vector2i(x, 10)
		_assert_true(game.map_grid.queue_dig(cell), "queue connected expansion dig")
		_assert_true(game.map_grid.apply_dig_work(cell, 8.0), "complete expansion dig")
	_assert_true(game.player_orders._primary_next_step()["text"] != first_text, "real Next sentence changes while still suggesting bed")
	_refresh_and_assert(game, "bed", "")
	_dispose(game)
