extends "res://tests/test_runner.gd"
# Next stays steady under pressure (QA light-touch playtest 2, 2026-10-30):
# (2) "<name> starving" leads only a food action, and a name that drops or
#     changes on the same action holds briefly instead of flickering;
# (3) while the PRESSURE SURGE modal is up, Next holds the hatch response.

const TICK := VaultGame.SIMULATION_TICK


func _run() -> void:
	_run_case("a starving resident does not prefix a hatch step", _test_prefix_food_only)
	_run_case("the starving name holds briefly on the same food action", _test_name_hold)
	_run_case("PRESSURE SURGE modal holds Next on the hatch response", _test_surge_hold)
	print("NEXT STEADY TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(0 if _failure_count == 0 else 1)


func _next(game: VaultGame) -> String:
	game.player_orders.refresh()
	return game.player_orders.objective_label.text


func _action(text: String) -> String:
	return text.substr(text.find("YOU"))


func _starve(game: VaultGame, index: int) -> void:
	game.food_system.meals = 0
	game.food_system.raw_food = 0
	for i: int in game.residents.size():
		game.residents[i].needs.food = 19.0 if i == index else 100.0


func _at(game: VaultGame, seconds: float) -> String:
	game.day_cycle.elapsed_seconds = seconds
	return _next(game)


func _test_prefix_food_only() -> void:
	var game := _healthy()
	_warn(game)
	_open(game)
	_set_all(game, "haul", VaultResident.PRIORITY_DISABLED)
	_starve(game, 0)
	var text := _next(game)
	print("PREFIX ", text)
	_assert_true(text.begins_with("Next: YOU enable Haul [P]"), "the hatch step leads, unnamed (%s)" % text)
	_assert_false("starving" in text, "no starving name on a hatch action (%s)" % text)
	_dispose(game)


func _test_name_hold() -> void:
	var game := _healthy()
	var t := 20.0
	var calm := _at(game, t)
	print("HOLD calm ", calm)
	_starve(game, 0)
	var ari := _at(game, t + 0.5)
	print("HOLD ari ", ari)
	_assert_true(ari.begins_with("Next: Ari starving · "), "a new starving name shows at once (%s)" % ari)
	_starve(game, 1)
	var swapped := _at(game, t + 1.5)
	print("HOLD swap ", swapped)
	_assert_equal(swapped, ari, "a name change on the same action holds (no flicker)")
	var later := _at(game, t + 5.0)
	print("HOLD later ", later)
	_assert_true(later.begins_with("Next: Bo starving · "), "after the hold the current name shows (%s)" % later)
	_assert_equal(_action(later), _action(ari), "same food action throughout")
	_dispose(game)


func _test_surge_hold() -> void:
	var game := _healthy()
	game.day_cycle.elapsed_seconds = BreachSystem.WARNING_AT_SECONDS - TICK
	game.step_simulation(TICK)
	_assert_true(game.player_orders.breach_warning_panel.visible, "the surge modal is up")
	var hatch := _next(game)
	print("SURGE first ", hatch)
	_starve(game, 0)
	var under := _next(game)
	print("SURGE under ", under)
	_assert_equal(under, hatch, "a food swap does not happen under the modal")
	_set_all(game, "haul", VaultResident.PRIORITY_DISABLED)
	_assert_equal(_next(game), hatch, "nor any other swap until the modal is answered")
	_set_all(game, "haul", VaultResident.DEFAULT_WORK_PRIORITY)
	game.acknowledge_breach_warning(false)
	var after := _next(game)
	print("SURGE after ", after)
	_assert_true(after != hatch, "answering the modal lets Next move on (%s)" % after)
	# A later surge latches afresh: it names what blocks the hatch now.
	_set_all(game, "haul", VaultResident.PRIORITY_DISABLED)
	game.breach_system.warning_acknowledged = false
	var again := _next(game)
	_assert_true(again.begins_with("Next: YOU acknowledge warning · then enable Haul [P]"), "a new surge shows its own hatch step (%s)" % again)
	_dispose(game)


func _healthy() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	# These fixtures isolate hatch phases and response blockers. Give their
	# four crew a bounded 240-second food runway, including when work is OFF;
	# the explicit food-crisis test below replaces this reserve with zero meals.
	game.food_system.meals = 24
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


func _warn(game: VaultGame) -> void:
	# Real path: one simulation tick across 60 s raises the warning modal.
	game.day_cycle.elapsed_seconds = BreachSystem.WARNING_AT_SECONDS - TICK
	game.step_simulation(TICK)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.WARNING, "real hatch WARNING")
	game.acknowledge_breach_warning(false)


func _open(game: VaultGame) -> void:
	game.day_cycle.elapsed_seconds = BreachSystem.WARNING_AT_SECONDS + BreachSystem.GRACE_SECONDS + 1.0
	game.breach_system.advance(0.0, game.day_cycle.elapsed_seconds)
	_assert_equal(game.breach_system.phase, BreachSystem.Phase.OPEN, "real hatch OPEN")


func _set_all(game: VaultGame, work: String, priority: int) -> void:
	for resident: VaultResident in game.residents:
		resident.set_work_priority(work, priority)
