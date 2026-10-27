extends "res://tests/test_sidebar_reach.gd"

# Playtest finding 5 (2026-10-27, clip 03 at sim 99-104 s):
# (a) a 0.1 HP scratch raised "INJURED 1 · NO MED BED" while the Next chain (rightly)
#     asked for bunks: the alert must use the same Med Bed need as the chain.
# (b) a long build-mode help line widened the bottom rail under the right panel and
#     hid the resident card's FOOD/REST bars: the rail must stay left of the panel.

const LONG_HELP := "Designate AIR $14 and keep it powered (3). Craft auto-builds the blueprint.\nReclamation: +18 salvage now, +18 every 30 s, 6 times Select a living resident, then [R] to draft/undraft. Right-click: drafted = move; undrafted = force-context job."


func _run() -> void:
	await _run_frame_case("F5a a scratch above the seek threshold is not INJURED · NO MED BED", _test_scratch_not_injured)
	await _run_frame_case("F5a a resident who wants care still raises INJURED · NO MED BED", _test_real_injury)
	await _run_frame_case("F5b a long tool help line keeps the bottom rail left of the right panel", _test_rail_clear_of_panel)
	print("")
	if _failure_count == 0:
		print("MEDBED BUNK CARD TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("MEDBED BUNK CARD TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _alerts(game: VaultGame) -> String:
	game.player_orders.refresh()
	return str(game.player_orders.alert_label.text) + " " + str(game.player_orders.alert_label.tooltip_text)


func _test_scratch_not_injured() -> void:
	var game := _sealed_game()
	var fen: VaultResident = game.residents[0]
	fen.needs.health = 99.9
	fen.needs.food = 70.0
	_assert_false(fen.needs.wants_medical_care(), "fixture: 99.9 HP does not seek a Med Bed")
	_assert_false(game.player_orders._counts_as_injured(fen), "F5a 99.9 HP without a Med Bed reservation is not counted injured")
	fen.needs.health = ResidentNeeds.MEDICAL_SEEK_THRESHOLD + 0.5
	_assert_false(game.player_orders._counts_as_injured(fen), "F5a just above the seek threshold is not counted injured")
	_assert_true("NO MED BED" not in _alerts(game), "F5a no NO MED BED alert for a scratch")
	game.queue_free()
	await _layout()


func _test_real_injury() -> void:
	var game := _sealed_game()
	var fen: VaultResident = game.residents[0]
	fen.needs.health = ResidentNeeds.MEDICAL_SEEK_THRESHOLD
	fen.needs.food = 70.0
	_assert_true(game.player_orders._counts_as_injured(fen), "F5a at the seek threshold the resident is injured")
	fen.needs.health = 60.0
	_assert_true(game.player_orders._counts_as_injured(fen), "F5a 60 HP is injured")
	fen.needs.health = 99.0
	fen.medical_bed_id = 3
	_assert_true(game.player_orders._counts_as_injured(fen), "F5a a resident already reserving a Med Bed still counts while healing")
	fen.medical_bed_id = -1
	game.queue_free()
	await _layout()


func _test_rail_clear_of_panel() -> void:
	var game := _sealed_game()
	await _layout()
	var po = game.player_orders
	var right: Control = po.objective_label
	while right != null and not (right is PanelContainer and right.get_parent() == po.bottom_panel.get_parent()):
		right = right.get_parent() as Control
	_assert_true(right != null, "fixture: found the right panel")
	game.status_message = LONG_HELP + " " + LONG_HELP.replace("\n", " ")
	game.status_message_left = 60.0
	po.refresh()
	await _layout()
	var rail: Rect2 = po.bottom_panel.get_global_rect()
	_assert_true(po.tool_status.text.contains("force-context job. Designate"), "fixture: the long help is live")
	var view := Rect2(Vector2.ZERO, Vector2(1280, 720))
	_assert_true(rail.end.x <= right.get_global_rect().position.x + 0.5, "F5b rail right edge %.0f stays left of the right panel %.0f" % [rail.end.x, right.get_global_rect().position.x])
	_assert_true(view.encloses(rail), "F5b the rail stays inside the 1280x720 viewport (%s)" % str(rail))
	_assert_true(view.encloses(right.get_global_rect()), "F5b the right panel stays inside the viewport")
	_assert_true(po.tool_status.tooltip_text.contains("Reclamation"), "F5b the full help stays readable as a tooltip")
	game.queue_free()
	await _layout()
