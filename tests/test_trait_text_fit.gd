extends "res://tests/test_runner.gd"

# Every trait's inspector line ("Trait: X · effect") fits on one line of the right panel with
# room to spare. Tests run without frames, so the label width is derived from the right panel's
# default width minus each ancestor's padding, assuming the details scroll bar is showing.

const ROOM := 12.0
const EXPECTED := {
	"DIGGER": "Dig +25%",
	"CHEF": "Cook +25%",
	"FRUGAL": "Hunger -15%",
	"CALM": "Mood loss -25%",
	"PATCHER": "Patch +15%",
}


func _run() -> void:
	_run_case("trait effect texts are short and still name the number", _test_texts)
	_run_case("every trait's inspector line fits on one line with room", _test_fit)
	_finish()


func _finish() -> void:
	print("")
	if _failure_count == 0:
		print("TRAIT TEXT FIT TESTS PASSED: %d cases, %d assertions" % [_case_count, _assertion_count])
		quit(0)
	else:
		printerr("TRAIT TEXT FIT TESTS FAILED: %d/%d cases, %d failed assertions of %d" % [_failed_case_count, _case_count, _failure_count, _assertion_count])
		quit(1)


func _label_width(label: Control) -> float:
	var width := VaultGame.RIGHT_PANEL_WIDTH
	var node: Node = label.get_parent()
	while node is Control:
		if node is PanelContainer:
			width -= (node as PanelContainer).get_theme_stylebox("panel").get_minimum_size().x
			break
		if node is MarginContainer:
			width -= (node as Control).get_theme_constant("margin_left") + (node as Control).get_theme_constant("margin_right")
		if node is ScrollContainer:
			width -= (node as ScrollContainer).get_v_scroll_bar().get_combined_minimum_size().x
		node = node.get_parent()
	return width


func _test_texts() -> void:
	_assert_equal(VaultResident.TRAIT_EFFECTS.size(), VaultResident.TRAIT_POOL.size(), "one text per trait")
	for t: String in VaultResident.TRAIT_POOL:
		_assert_equal(VaultResident.TRAIT_EFFECTS[t], EXPECTED[t], "%s effect text" % t)


func _test_fit() -> void:
	var game := _spawn_game()
	_assert_true(game != null and game.player_orders != null, "the game and its panels load")
	if game == null or game.player_orders == null:
		return
	game.new_game(false, 4242)
	var orders := game.player_orders
	var label: Label = orders.inspector_state
	var font := label.get_theme_font("font")
	var size := label.get_theme_font_size("font_size")
	var width := _label_width(label)
	print("INSPECTOR WIDTH %.0f" % width)
	var resident: VaultResident = game.residents[0]
	game.selected_resident_id = resident.resident_id
	for t: String in VaultResident.TRAIT_POOL:
		resident.set_trait(t)
		orders._refresh_inspector()
		var lines := orders.inspector_state.text.split("\n")
		var line := lines[lines.size() - 1]
		_assert_equal(line, "Trait: %s · %s" % [t, EXPECTED[t]], "%s line is last" % t)
		var room := width - font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		print("ROOM %s %.0f" % [t, room])
		_assert_true(room >= ROOM, "%s: '%s' fits with %.0f px to spare" % [t, line, room])
	_dispose(game)
