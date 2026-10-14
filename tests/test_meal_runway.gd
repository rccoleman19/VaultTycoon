extends SceneTree

# Meal runway: the resource HUD shows how many days the stored and pending
# meals feed the living crew (one meal per resident per day).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var _case_count := 0
var _assertion_count := 0
var _failure_count := 0
var _current_case := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_run_case("opening wing shows three days of meals", _test_opening)
	_run_case("pending meals count toward the runway", _test_pending)
	_run_case("runway floors to a tenth", _test_floor)
	_run_case("fewer living residents stretch the runway", _test_deaths)
	_run_case("empty larder shows zero days", _test_empty)
	_run_case("no living crew hides the runway", _test_no_crew)
	_run_case("ended wing hides the runway", _test_ended)
	_run_case("eating a meal shortens the runway", _test_live_eat)
	print("MEAL RUNWAY TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(0 if _failure_count == 0 else 1)


func _run_case(label: String, test: Callable) -> void:
	_case_count += 1
	_current_case = label
	var before := _failure_count
	print("[TEST] %s" % label)
	test.call()
	print("[%s] %s" % ["PASS" if before == _failure_count else "FAIL", label])


func _spawn_game() -> VaultGame:
	var game := MAIN_SCENE.instantiate() as VaultGame
	root.add_child(game)
	game.begin_shift()
	game.user_paused = true
	return game


func _free(game: VaultGame) -> void:
	game.queue_free()
	await process_frame


func _text(game: VaultGame) -> String:
	game.player_orders.refresh()
	return game.player_orders.resource_label.text


func _test_opening() -> void:
	var game := _spawn_game()
	# 12 meals / 4 residents = 3.0 days.
	_assert_equal(_text(game), "MEALS 12 (+0) · 3.0 DAYS  RAW 4 (+0)  SALVAGE 48", "opening resource line")
	_assert_true("one meal a day" in game.player_orders.resource_label.tooltip_text, "tooltip explains DAYS")
	_free(game)


func _test_pending() -> void:
	var game := _spawn_game()
	game.food_system.meals = 5
	game.job_system.queue_meals(Vector2i(21, 12), 3)
	# (5 stored + 3 pending) / 4 = 2.0 days.
	_assert_true("MEALS 5 (+3) · 2.0 DAYS  RAW" in _text(game), "runway includes pending meals")
	_free(game)


func _test_floor() -> void:
	var game := _spawn_game()
	game.food_system.meals = 7
	# 7 / 4 = 1.75 -> 1.7, never rounded up to 1.8.
	_assert_true("MEALS 7 (+0) · 1.7 DAYS  RAW" in _text(game), "floored runway")
	_free(game)


func _test_deaths() -> void:
	var game := _spawn_game()
	game.food_system.meals = 5
	game.residents[0].alive = false
	game.residents[1].alive = false
	# 5 / 2 = 2.5 days.
	_assert_true("· 2.5 DAYS" in _text(game), "runway per living resident")
	_free(game)


func _test_empty() -> void:
	var game := _spawn_game()
	game.food_system.meals = 0
	_assert_true("MEALS 0 (+0) · 0.0 DAYS  RAW" in _text(game), "zero runway still shown")
	_free(game)


func _test_no_crew() -> void:
	var game := _spawn_game()
	for resident: VaultResident in game.residents:
		resident.alive = false
	_assert_equal(_text(game), "MEALS 12 (+0)  RAW 4 (+0)  SALVAGE 48", "no runway with no crew")
	_free(game)


func _test_ended() -> void:
	var game := _spawn_game()
	game.ended = true
	game.outcome = "win"
	_assert_false("DAYS" in _text(game), "no runway after the shift ends")
	_free(game)


func _test_live_eat() -> void:
	var game := _spawn_game()
	_assert_true("· 3.0 DAYS" in _text(game), "before eating")
	game.food_system.consume_meal()
	# 11 / 4 = 2.75 -> 2.7.
	_assert_true("MEALS 11 (+0) · 2.7 DAYS" in _text(game), "after one meal is eaten")
	_free(game)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	_assertion_count += 1
	if actual != expected:
		_failure_count += 1
		print("  FAIL %s: expected %s, got %s" % [message, var_to_str(expected), var_to_str(actual)])


func _assert_true(value: bool, message: String) -> void:
	_assert_equal(value, true, message)


func _assert_false(value: bool, message: String) -> void:
	_assert_equal(value, false, message)
