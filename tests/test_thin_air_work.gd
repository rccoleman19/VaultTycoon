extends SceneTree

# Thin-air work: while wing O2 is at or below LOW (35%), awake residents dig,
# build and craft at 80% speed (stacking with hunger/rest/mood, floored at 35%).
# Letting the air crash now slows the very repairs that fix it.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const EPS := 0.0001

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
