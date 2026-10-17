extends SceneTree

# Rec boost: a resident who finishes a Rec Console session leaves refreshed and
# digs, builds, crafts and cooks at 120% for one 40-second day. The boost stacks
# with the hunger/rest/mood penalties (floor 35%), shows in the inspector, and
# survives save/load. A powered console now pays back in work, not only mood.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const EPS := 0.0001

var _case_count := 0
var _assertion_count := 0
var _failure_count := 0
var _current_case := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_run_case("boost multiplies work speed, stacks with penalties and decays in a day", _test_multiplier)
	_run_case("a finished console session grants the boost; an interrupted one does not", _test_live_session)
	_run_case("inspector shows the boosted work speed and countdown", _test_inspector)
	_run_case("boost survives a snapshot and malformed values load safely", _test_save)
	print("REC BOOST TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(0 if _failure_count == 0 else 1)


func _run_case(label: String, test: Callable) -> void:
	_case_count += 1
	_current_case = label
	var before := _failure_count
	print("[TEST] %s" % label)
	test.call()
	print("[%s] %s" % ["PASS" if before == _failure_count else "FAIL", label])


func _check(condition: bool, message: String) -> void:
	_assertion_count += 1
	if not condition:
		_failure_count += 1
		print("  FAIL (%s): %s" % [_current_case, message])


func _near(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) <= EPS, "%s: expected %.4f, got %.4f" % [message, expected, actual])


func _healthy(resident: VaultResident) -> void:
	resident.needs.food = 100.0
	resident.needs.rest = 100.0
	resident.needs.mood = 80.0
	resident.needs.health = 100.0


func _test_multiplier() -> void:
	var resident := VaultResident.new()
	_healthy(resident)
	_near(resident.get_work_multiplier(), 1.0, "no boost by default")
	_near(VaultResident.REC_BOOST_MULTIPLIER, 1.2, "boost factor")
	_near(VaultResident.REC_BOOST_SECONDS, DayCycle.SECONDS_PER_DAY, "boost lasts one day")
	resident.rec_boost_left = VaultResident.REC_BOOST_SECONDS
	_near(resident.get_work_multiplier(), 1.2, "refreshed resident works at 120%")
	resident.needs.mood = 20.0
	_near(resident.get_work_multiplier(), 0.84, "boost stacks with the low-mood penalty")
	resident.needs.food = 10.0
	resident.needs.rest = 10.0
	_near(resident.get_work_multiplier(), 0.4095, "boost lifts fully stacked penalties above the floor")
	resident.rec_boost_left = 0.0
	_near(resident.get_work_multiplier(), 0.35, "without the boost the 35% floor still holds")
	_healthy(resident)
	resident.rec_boost_left = VaultResident.REC_BOOST_SECONDS
	resident.advance_needs(0.5, true, false)
	_near(resident.rec_boost_left, 20.0, "half a day burns half the boost")
	_near(resident.get_work_multiplier(), 1.2, "boost still active mid-day")
	resident.advance_needs(0.75, true, false)
	_near(resident.rec_boost_left, 0.0, "boost never goes negative")
	_healthy(resident)
	_near(resident.get_work_multiplier(), 1.0, "expired boost returns to full speed")
	resident.free()


func _spawn() -> VaultGame:
	var game := MAIN_SCENE.instantiate() as VaultGame
	root.add_child(game)
	for resident: VaultResident in game.residents:
		_healthy(resident)
		resident.needs.mood = 100.0
		resident.sleeping = false
		resident.bed_id = -1
		resident.stress_break_left = 0.0
		game.job_system.release_resident(resident)
	return game


func _dispose(game: VaultGame) -> void:
	root.remove_child(game)
	game.free()


func _console_at(game: VaultGame, resident: VaultResident) -> VaultBuilding:
	var building := VaultBuilding.new()
	game.building_root.add_child(building)
	building.configure(game.next_building_id, VaultBuilding.Kind.RECREATION_CONSOLE, resident.get_cell(game.map_grid), true)
	game.next_building_id += 1
	game.buildings.append(building)
	game.power_grid.recalculate(game.buildings)
	return building


func _finish_session(game: VaultGame, resident: VaultResident) -> void:
	resident.needs.mood = 35.0
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_check(resident.recreating, "resident claims the console at 35 mood")
	resident.needs.mood = 84.0
	game._simulation_step(VaultGame.SIMULATION_TICK)


func _test_live_session() -> void:
	var game := _spawn()
	var resident: VaultResident = game.residents[0]
	_console_at(game, resident)
	resident.needs.mood = 35.0
	game.job_system.advance(VaultGame.SIMULATION_TICK)
	_check(resident.recreating, "resident starts a session")
	resident.needs.mood = 60.0
	game.job_system.release_resident(resident)
	_check(not resident.recreating, "session interrupted before 85")
	_near(resident.rec_boost_left, 0.0, "interrupted session grants no boost")
	_finish_session(game, resident)
	_check(not resident.recreating, "session finished at 85")
	_check(resident.recreation_sessions == 1, "one completed session counted")
	_near(resident.rec_boost_left, VaultResident.REC_BOOST_SECONDS, "finished session grants a full day of boost")
	_near(resident.get_work_multiplier(), 1.2, "finished session works at 120%")
	_near(game.residents[1].rec_boost_left, 0.0, "other residents are not boosted")
	game.step_simulation(20.0)
	_near(resident.rec_boost_left, 20.0, "boost counts down with simulation time")
	game.step_simulation(20.1)
	_near(resident.rec_boost_left, 0.0, "boost expires after one day")
	_dispose(game)


func _inspector_text(game: VaultGame, resident: VaultResident) -> String:
	game.select_resident(resident.resident_id)
	game.player_orders.refresh()
	return game.player_orders.inspector_state.text


func _test_inspector() -> void:
	var game := _spawn()
	var resident: VaultResident = game.residents[0]
	var plain := _inspector_text(game, resident)
	_check("Work speed: 100%\n" in plain, "unboosted inspector line unchanged: " + plain.replace("\n", " | "))
	_check(not ("Rec boost" in plain), "no boost label without a boost")
	resident.rec_boost_left = 31.2
	var boosted := _inspector_text(game, resident)
	_check("Work speed: 120% · Rec boost 32s\n" in boosted, "boosted inspector line: " + boosted.replace("\n", " | "))
	_dispose(game)


func _test_save() -> void:
	var original := _spawn()
	var resident: VaultResident = original.residents[0]
	resident.rec_boost_left = 12.5
	var snapshot := original.create_snapshot()
	_near(float(snapshot.residents[0].rec_boost_left), 12.5, "snapshot stores the boost")
	_near(float(snapshot.residents[1].rec_boost_left), 0.0, "snapshot stores zero for unboosted residents")
	var loaded := _spawn()
	_check(loaded.apply_snapshot(snapshot), "boosted snapshot loads")
	var loaded_resident: VaultResident = loaded.get_resident_by_id(resident.resident_id)
	_near(loaded_resident.rec_boost_left, 12.5, "boost survives load")
	var cases := [["legacy", null, 0.0], ["text", "fast", 0.0], ["negative", -5.0, 0.0], ["huge", 999.0, 40.0], ["int", 7, 7.0]]
	for entry: Array in cases:
		var variant: Dictionary = snapshot.duplicate(true)
		if entry[1] == null:
			variant.residents[0].erase("rec_boost_left")
		else:
			variant.residents[0].rec_boost_left = entry[1]
		_check(loaded.apply_snapshot(variant), "%s boost value still loads" % entry[0])
		_near(loaded.get_resident_by_id(resident.resident_id).rec_boost_left, float(entry[2]), "%s boost value normalized" % entry[0])
	var dead: Dictionary = snapshot.duplicate(true)
	dead.residents[0].alive = false
	_check(loaded.apply_snapshot(dead), "deceased resident with a stale boost loads")
	_near(loaded.get_resident_by_id(resident.resident_id).rec_boost_left, 0.0, "deceased resident carries no boost")
	_dispose(original)
	_dispose(loaded)
