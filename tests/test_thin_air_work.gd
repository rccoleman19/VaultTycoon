extends SceneTree

# Thin-air work: while wing O2 is at or below LOW (35%), awake residents dig,
# build and craft at 80% speed (stacking with hunger/rest/mood, floored at 35%).
# Letting the air crash now slows the very repairs that fix it.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const EPS := 0.0001
const THIN_AIR_SAVE_TEST_PATH := "user://headless_thin_air_work.json"

var _case_count := 0
var _assertion_count := 0
var _failure_count := 0
var _current_case := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_run_case("thin air multiplies work speed and keeps the floor", _test_multiplier)
	_run_case("live wing O2 sets and clears the thin-air penalty", _test_live_wing)
	_run_case("LOW threshold is inclusive for work speed", _test_dig_progress)
	_run_case("paused load at LOW O2 keeps the thin-air work speed", _test_paused_load)
	print("THIN AIR WORK TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
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


func _test_multiplier() -> void:
	var resident := VaultResident.new()
	resident.needs.food = 100.0
	resident.needs.rest = 100.0
	resident.needs.mood = 80.0
	_near(resident.get_work_multiplier(), 1.0, "good air, healthy resident")
	resident.advance_needs(0.0, true, false, false, true)
	_check(resident.short_of_air, "low O2 tick marks the resident short of air")
	_near(resident.get_work_multiplier(), 0.8, "thin air alone")
	resident.needs.mood = 20.0
	_near(resident.get_work_multiplier(), 0.56, "thin air stacks with low mood")
	resident.needs.food = 10.0
	resident.needs.rest = 10.0
	_near(resident.get_work_multiplier(), 0.35, "stacked penalties keep the 35% floor")
	resident.needs.food = 100.0
	resident.needs.rest = 100.0
	resident.needs.mood = 80.0
	resident.advance_needs(0.0, true, false, false, false)
	_check(not resident.short_of_air, "breathable tick clears the flag")
	_near(resident.get_work_multiplier(), 1.0, "recovered air restores full speed")
	resident.free()


func _spawn() -> VaultGame:
	var game := MAIN_SCENE.instantiate() as VaultGame
	root.add_child(game)
	game.begin_shift()
	game.user_paused = true
	for resident: VaultResident in game.residents:
		resident.needs.food = 100.0
		resident.needs.rest = 100.0
		resident.needs.mood = 80.0
	return game


func _dispose(game: VaultGame) -> void:
	root.remove_child(game)
	game.free()


func _test_live_wing() -> void:
	var game := _spawn()
	var resident: VaultResident = game.residents[0]
	game.oxygen_system.oxygen = 90.0
	game.step_simulation(0.1)
	_check(not resident.short_of_air, "fresh air: not short of air")
	_near(resident.get_work_multiplier(), 1.0, "fresh air work speed")
	game.oxygen_system.oxygen = 30.0
	game.step_simulation(0.1)
	_check(game.oxygen_system.is_low(), "wing O2 is LOW")
	_check(resident.short_of_air, "LOW wing O2 marks residents short of air")
	_near(resident.get_work_multiplier(), 0.8, "LOW wing O2 work speed")
	game.oxygen_system.oxygen = 90.0
	game.step_simulation(0.1)
	_check(not resident.short_of_air, "refilled air clears the penalty")
	_dispose(game)


func _dig_progress(oxygen: float) -> float:
	var resident := VaultResident.new()
	resident.needs.food = 100.0
	resident.needs.rest = 100.0
	resident.needs.mood = 80.0
	resident.advance_needs(0.0, true, false, false, oxygen <= OxygenSystem.LOW_OXYGEN_THRESHOLD)
	var work := 1.0 * resident.get_work_multiplier()
	resident.free()
	return work


func _test_dig_progress() -> void:
	_near(_dig_progress(100.0), 1.0, "1s of work in good air")
	_near(_dig_progress(35.0), 0.8, "1s of work at exactly LOW")
	_near(_dig_progress(36.0), 1.0, "1s of work just above LOW")


func _remove_test_save() -> void:
	if FileAccess.file_exists(THIN_AIR_SAVE_TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(THIN_AIR_SAVE_TEST_PATH))


func _inspector_work_line(game: VaultGame, resident: VaultResident) -> String:
	game.select_resident(resident.resident_id)
	game.player_orders.refresh()
	return game.player_orders.inspector_state.text


func _test_paused_load() -> void:
	_remove_test_save()
	var original := _spawn()
	original.oxygen_system.oxygen = 30.0
	original.step_simulation(0.1)
	var saved_resident: VaultResident = original.residents[0]
	_check(saved_resident.short_of_air, "LOW wing O2 marks the saved resident short of air")
	_check("Work speed: 80%" in _inspector_work_line(original, saved_resident), "inspector shows 80% before saving")
	_check(original.save_game(false, THIN_AIR_SAVE_TEST_PATH), "LOW-O2 wing saves to an isolated file")
	_dispose(original)
	var loaded := _spawn()
	loaded.user_paused = false
	_check(loaded.load_game(THIN_AIR_SAVE_TEST_PATH), "LOW-O2 save loads through the public file path")
	_check(loaded.user_paused, "load leaves the wing paused")
	_check(loaded.oxygen_system.is_low(), "loaded wing O2 is still LOW")
	var resident: VaultResident = loaded.residents[0]
	resident.needs.food = 100.0
	resident.needs.rest = 100.0
	resident.needs.mood = 80.0
	_check(resident.short_of_air, "load rebuilds the thin-air flag from wing O2")
	_near(resident.get_work_multiplier(), 0.8, "paused load keeps the thin-air work speed")
	var text := _inspector_work_line(loaded, resident)
	_check("Work speed: 80%" in text, "paused inspector still shows 80% after load: " + text.replace("\n", " | "))
	loaded.oxygen_system.oxygen = 90.0
	_check(loaded.save_game(false, THIN_AIR_SAVE_TEST_PATH), "breathable wing saves over the isolated file")
	_dispose(loaded)
	var fresh := _spawn()
	_check(fresh.load_game(THIN_AIR_SAVE_TEST_PATH), "breathable save loads")
	_check(not fresh.residents[0].short_of_air, "breathable load leaves residents at full air")
	_dispose(fresh)
	_remove_test_save()
