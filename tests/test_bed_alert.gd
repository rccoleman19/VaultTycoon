extends "res://tests/test_runner.gd"

# QA-e #3 C: a bunk shortage nobody is collapsing from reads "BED SHORTAGE · crew rotate".


func _run() -> void:
	_run_case("BED SHORTAGE gains the crew-rotate suffix only while nobody is under rest 15", _test_suffix)
	print("")
	if _failure_count == 0:
		print("BED ALERT TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("BED ALERT TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _alert(game: VaultGame) -> String:
	game.player_orders.refresh()
	return game.player_orders.alert_label.text


func _test_suffix() -> void:
	var game := _spawn_game()
	game.begin_shift()
	for resident: VaultResident in game.residents:
		resident.needs.rest = 60.0
		resident.drafted = false
		resident.sleeping = false
		resident.bed_id = -1
	_assert_false("BED SHORTAGE" in _alert(game), "no tired crew, no shortage")
	game.residents[0].needs.rest = 28.0
	_assert_true("BED SHORTAGE · crew rotate" in _alert(game), "rest 28 with no bunk: shortage with the rotate suffix")
	game.residents[0].needs.rest = 15.0
	_assert_true("BED SHORTAGE · crew rotate" in _alert(game), "rest exactly 15 still rotates")
	game.residents[0].needs.rest = 14.9
	var text := _alert(game)
	_assert_true("BED SHORTAGE" in text, "rest under 15 keeps BED SHORTAGE")
	_assert_false("crew rotate" in text, "and drops the suffix")
	game.residents[0].needs.rest = 28.0
	game.residents[1].needs.rest = 10.0
	game.residents[1].drafted = true
	text = _alert(game)
	_assert_true("BED SHORTAGE" in text and not "crew rotate" in text, "any living crew member under 15 makes it plain, even one not counted for bunks")
	game.residents[1].alive = false
	_assert_true("BED SHORTAGE · crew rotate" in _alert(game), "the dead do not count")
	_assert_equal(game.player_orders.alert_label.get_theme_color("font_color"), Color("ef6860"), "colour unchanged (red)")
	_dispose(game)
