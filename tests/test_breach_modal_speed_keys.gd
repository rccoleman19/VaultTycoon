extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := MAIN_SCENE.instantiate() as VaultGame
	root.add_child(game)
	game.begin_shift()
	game.set_speed(3)
	game.step_simulation(BreachSystem.WARNING_AT_SECONDS)
	game.player_orders.refresh()

	_assert_equal(game.breach_system.phase, BreachSystem.Phase.WARNING, "breach warning opens")
	_assert_true(game.user_paused, "breach warning pauses the shift")
	_assert_equal(game.simulation_speed, 1, "breach warning resets speed")
	_assert_true(game.player_orders.breach_warning_panel.visible, "breach warning modal is visible")
	_assert_false(game.breach_system.warning_acknowledged, "breach warning starts unacknowledged")

	for key: int in [KEY_1, KEY_2, KEY_3]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.pressed = true
		game._unhandled_input(event)
		_assert_false(game.breach_system.warning_acknowledged, "speed key %d does not acknowledge warning" % key)
		_assert_true(game.player_orders.breach_warning_panel.visible, "speed key %d leaves modal visible" % key)
		_assert_true(game.user_paused, "speed key %d leaves response paused" % key)
		_assert_equal(game.simulation_speed, 1, "speed key %d leaves warning speed unchanged" % key)

	game.acknowledge_breach_warning(true)
	_assert_true(game.breach_system.warning_acknowledged, "resume action still acknowledges warning")
	_assert_false(game.player_orders.breach_warning_panel.visible, "resume action still closes modal")
	_assert_false(game.user_paused, "resume action still unpauses the shift")

	game.queue_free()
	if failures == 0:
		print("BREACH MODAL SPEED KEY REGRESSION PASSED")
		quit(0)
	else:
		push_error("BREACH MODAL SPEED KEY REGRESSION FAILED: %d failures" % failures)
		quit(1)


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)


func _assert_false(value: bool, message: String) -> void:
	if value:
		_fail(message)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _fail(message: String) -> void:
	failures += 1
	push_error(message)
