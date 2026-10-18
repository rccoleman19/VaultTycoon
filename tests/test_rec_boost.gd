extends SceneTree

# Rec boost: a resident who finishes a Rec Console session leaves refreshed and
# digs, builds, crafts and cooks at 120% for one 40-second day. The boost stacks
# with the hunger/rest/mood penalties (floor 35%), shows in the inspector, and
# survives save/load. A powered console now pays back in work, not only mood.
# A resident who dies mid-boost loses it at once, so a corpse never shows a frozen
# Rec boost and its inspector reads the same before a save and after the load.

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
	_run_case("death clears the boost before died fires; corpses show no Rec boost", _test_death)
	_run_case("the boost pauses while asleep, resumes on waking and keeps its time across a load", _test_sleep)
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


func _work_line(text: String) -> String:
	for line: String in text.split("\n"):
		if line.begins_with("Work speed:"):
			return line
	return ""


func _test_death() -> void:
	var game := _spawn()
	var damaged: VaultResident = game.residents[0]
	var starved: VaultResident = game.residents[1]
	var boost_at_death := {}
	for resident: VaultResident in [damaged, starved]:
		resident.rec_boost_left = 30.0
		resident.died.connect(func(who: VaultResident) -> void: boost_at_death[who.resident_id] = who.rec_boost_left)
	_check("Rec boost 30s" in _inspector_text(game, damaged), "living boosted resident shows the countdown")
	damaged.apply_damage(500.0)
	_check(not damaged.alive, "suffocation-style damage kills the resident")
	_near(float(boost_at_death.get(damaged.resident_id, -1.0)), 0.0, "boost already cleared when died fires (damage path)")
	_near(damaged.rec_boost_left, 0.0, "damage death clears the boost")
	starved.needs.health = 0.0
	starved.advance_needs(0.01, true, false)
	_check(not starved.alive, "zero health kills the resident in advance_needs")
	_near(float(boost_at_death.get(starved.resident_id, -1.0)), 0.0, "boost already cleared when died fires (needs path)")
	_near(starved.rec_boost_left, 0.0, "needs death clears the boost")
	game.step_simulation(5.0)
	_near(damaged.rec_boost_left, 0.0, "a corpse never regains a boost")
	var corpse := _inspector_text(game, damaged)
	_check(not ("Rec boost" in corpse), "corpse inspector has no Rec boost: " + corpse.replace("\n", " | "))
	_check(_work_line(corpse) == "Work speed: 100%", "corpse work line drops the 120%%: %s" % _work_line(corpse))
	var snapshot := game.create_snapshot()
	_near(float(snapshot.residents[0].rec_boost_left), 0.0, "snapshot stores no boost for the dead")
	var loaded := _spawn()
	_check(loaded.apply_snapshot(snapshot), "snapshot with a mid-boost death loads")
	var reloaded := _inspector_text(loaded, loaded.get_resident_by_id(damaged.resident_id))
	_check(_work_line(reloaded) == _work_line(corpse), "corpse work line identical after load: %s vs %s" % [_work_line(reloaded), _work_line(corpse)])
	_dispose(game)
	_dispose(loaded)


func _test_sleep() -> void:
	var resident := VaultResident.new()
	_healthy(resident)
	resident.rec_boost_left = 30.0
	resident.sleeping = true
	resident.advance_needs(0.5, true, true)
	_near(resident.rec_boost_left, 30.0, "half a day asleep burns none of the boost")
	resident.sleeping = false
	resident.advance_needs(0.25, true, false)
	_near(resident.rec_boost_left, 20.0, "awake again, the boost counts down")
	resident.free()
	var game := _spawn()
	var sleeper: VaultResident = game.residents[0]
	var awake: VaultResident = game.residents[1]
	sleeper.needs.rest = 10.0
	sleeper.sleeping = true
	sleeper.state = "Collapsed on floor"
	sleeper.rec_boost_left = 30.0
	awake.rec_boost_left = 30.0
	game.step_simulation(5.0)
	_check(sleeper.sleeping, "sleeper is still asleep after 5s")
	_near(sleeper.rec_boost_left, 30.0, "a sleeping resident keeps the full boost")
	_near(awake.rec_boost_left, 25.0, "an awake resident's boost still counts down")
	var asleep_text := _inspector_text(game, sleeper)
	_check("· Rec boost 30s paused\n" in asleep_text, "asleep inspector says the boost is paused: " + asleep_text.replace("\n", " | "))
	var awake_text := _inspector_text(game, awake)
	_check("Work speed: 120% · Rec boost 25s\n" in awake_text, "awake inspector line unchanged: " + awake_text.replace("\n", " | "))
	var snapshot := game.create_snapshot()
	var loaded := _spawn()
	_check(loaded.apply_snapshot(snapshot), "snapshot with a sleeping boosted resident loads")
	var restored: VaultResident = loaded.get_resident_by_id(sleeper.resident_id)
	_check(restored.sleeping, "load keeps the resident asleep")
	_near(restored.rec_boost_left, 30.0, "load keeps the paused boost time")
	_check(_work_line(_inspector_text(loaded, restored)) == _work_line(asleep_text), "asleep work line identical after load")
	loaded.step_simulation(2.0)
	_near(restored.rec_boost_left, 30.0, "still paused after the load")
	restored.sleeping = false
	restored.state = "Idle"
	restored.needs.rest = 100.0
	loaded.step_simulation(2.0)
	_near(restored.rec_boost_left, 28.0, "waking resumes the countdown from the saved time")
	_dispose(game)
	_dispose(loaded)
