extends SceneTree

# Air haze: a presentation-only cue. The chamber fill light stays warm while air
# is fine, cools and dims between LOW (35%) and CRITICAL (15%) O2, and warms back
# up as recyclers refill the wing.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const EPS := 0.001
const WARM := Color(1.0, 0.82, 0.62)
const COLD := Color("7F9BB8")

var _case_count := 0
var _assertion_count := 0
var _failure_count := 0
var _current_case := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_run_case("breathable air keeps the warm fill", _test_breathable)
	_run_case("haze ramps linearly from LOW to CRITICAL", _test_ramp)
	_run_case("live wing cools the fill and recovers", _test_live_fill)
	print("AIR HAZE TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
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
	_check(absf(actual - expected) <= EPS, "%s: expected %.3f, got %.3f" % [message, expected, actual])


func _test_breathable() -> void:
	for o2: float in [100.0, 60.0, 35.0]:
		_near(MapView3D.air_haze_strength(o2), 0.0, "haze @%.0f%%" % o2)


func _test_ramp() -> void:
	_near(MapView3D.air_haze_strength(30.0), 0.25, "haze @30%")
	_near(MapView3D.air_haze_strength(25.0), 0.5, "haze @25%")
	_near(MapView3D.air_haze_strength(15.0), 1.0, "haze @15% (critical)")
	_near(MapView3D.air_haze_strength(0.0), 1.0, "haze clamps below critical")


func _test_live_fill() -> void:
	var game := MAIN_SCENE.instantiate() as VaultGame
	root.add_child(game)
	game.begin_shift()
	game.user_paused = true
	var fill := game.map_view_3d.get_node_or_null("ChamberFill") as OmniLight3D
	_check(fill != null, "chamber fill exists")
	if fill == null:
		root.remove_child(game)
		game.free()
		return
	game._sync_3d_play_view(false)
	_near(fill.light_energy, 0.65, "fresh wing fill energy")
	_check(fill.light_color.is_equal_approx(WARM), "fresh wing fill is warm")
	game.oxygen_system.oxygen = 25.0
	game._sync_3d_play_view(false)
	_near(fill.light_energy, 0.475, "half-haze fill energy")
	_check(fill.light_color.is_equal_approx(WARM.lerp(COLD, 0.5)), "half-haze fill is half cooled")
	game.oxygen_system.oxygen = 10.0
	game._sync_3d_play_view(false)
	_near(fill.light_energy, 0.3, "critical fill energy")
	_check(fill.light_color.is_equal_approx(COLD), "critical fill is cold")
	game.oxygen_system.oxygen = 80.0
	game._sync_3d_play_view(false)
	_near(fill.light_energy, 0.65, "refilled air restores energy")
	_check(fill.light_color.is_equal_approx(WARM), "refilled air restores warmth")
	root.remove_child(game)
	game.free()
