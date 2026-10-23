extends SceneTree

# Breach alarm: a presentation-only beacon over the hatch pulses amber during
# WARNING and red during OPEN, quiets as the patch progresses, and goes dark
# once the hatch is sealed.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const EPS := 0.001

var _case_count := 0
var _assertion_count := 0
var _failure_count := 0
var _current_case := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_run_case("dormant and sealed hatches stay dark", _test_quiet_phases)
	_run_case("warning pulses amber at 1 Hz", _test_warning_wave)
	_run_case("open breach pulses harder at 2 Hz", _test_open_wave)
	_run_case("patch progress quiets the alarm", _test_patch_quiets)
	_run_case("live wing lights and clears the beacon", _test_live_beacon)
	print("BREACH ALARM TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
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


func _energy(phase: BreachSystem.Phase, patch_left: float, seconds: float) -> float:
	return MapView3D.breach_alarm_energy(phase, patch_left, seconds)


func _test_quiet_phases() -> void:
	for seconds: float in [0.0, 0.25, 0.6]:
		_near(_energy(BreachSystem.Phase.DORMANT, BreachSystem.PATCH_WORK_SECONDS, seconds), 0.0, "dormant @%.2f" % seconds)
		_near(_energy(BreachSystem.Phase.SEALED, 0.0, seconds), 0.0, "sealed @%.2f" % seconds)


func _test_warning_wave() -> void:
	var full := BreachSystem.PATCH_WORK_SECONDS
	_near(_energy(BreachSystem.Phase.WARNING, full, 0.25), 1.8, "warning peak")
	_near(_energy(BreachSystem.Phase.WARNING, full, 0.75), 0.63, "warning trough")
	_near(_energy(BreachSystem.Phase.WARNING, full, 1.25), 1.8, "warning peak one second later")


func _test_open_wave() -> void:
	var full := BreachSystem.PATCH_WORK_SECONDS
	_near(_energy(BreachSystem.Phase.OPEN, full, 0.125), 3.0, "open peak")
	_near(_energy(BreachSystem.Phase.OPEN, full, 0.375), 1.05, "open trough")
	_near(_energy(BreachSystem.Phase.OPEN, full, 0.625), 3.0, "open peak half a second later")


func _test_patch_quiets() -> void:
	var half := BreachSystem.PATCH_WORK_SECONDS * 0.5
	_near(_energy(BreachSystem.Phase.OPEN, half, 0.125), 2.25, "half-patched open peak")
	_near(_energy(BreachSystem.Phase.OPEN, 0.0, 0.125), 1.5, "fully worked open peak")
	_near(_energy(BreachSystem.Phase.WARNING, 0.0, 0.25), 0.9, "fully worked warning peak")


func _test_live_beacon() -> void:
	var game := MAIN_SCENE.instantiate() as VaultGame
	root.add_child(game)
	game.begin_shift()
	game.user_paused = true
	var view := game.map_view_3d
	game._sync_3d_play_view(false)
	_check(view.marker_root.get_node_or_null("BreachAlarm") == null, "no beacon before any breach")
	game.breach_system.phase = BreachSystem.Phase.WARNING
	game._sync_3d_play_view(false)
	var alarm := view.marker_root.get_node_or_null("BreachAlarm") as OmniLight3D
	_check(alarm != null, "warning creates the beacon")
	if alarm == null:
		root.remove_child(game)
		game.free()
		return
	_check(alarm.visible and alarm.light_energy > 0.0, "warning beacon is lit")
	_check(alarm.light_color.is_equal_approx(Color("EFC56B")), "warning beacon is amber")
	var hatch := MapGrid.offset_cell_to_world(BreachSystem.HATCH_CELL)
	_check(is_equal_approx(alarm.position.x, hatch.x) and is_equal_approx(alarm.position.z, hatch.y), "beacon sits over the hatch")
	game.breach_system.phase = BreachSystem.Phase.OPEN
	game._sync_3d_play_view(false)
	_check(alarm.visible and alarm.light_color.is_equal_approx(Color("EF6860")), "open beacon is red")
	view._sync_breach_alarm(BreachSystem.Phase.OPEN, BreachSystem.PATCH_WORK_SECONDS, 0.125)
	var high := alarm.light_energy
	view._sync_breach_alarm(BreachSystem.Phase.OPEN, BreachSystem.PATCH_WORK_SECONDS, 0.375)
	_check(high - alarm.light_energy > 1.0, "beacon pulses between frames")
	game.breach_system.phase = BreachSystem.Phase.SEALED
	game._sync_3d_play_view(false)
	_check(not alarm.visible and alarm.light_energy == 0.0, "sealed hatch turns the beacon off")
	_check(view.marker_root.get_children().filter(func(n: Node) -> bool: return n is OmniLight3D).size() == 1, "one beacon, reused")
	root.remove_child(game)
	game.free()
