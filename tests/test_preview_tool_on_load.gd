extends "res://tests/test_runner.gd"

# LOAD and NEW WING put the player back on SELECT. The 3D build ghost, the
# hover tint and the Lumen range tint read MapGrid.preview_tool, so it has to
# return to SELECT with them; otherwise a Bunk ghost follows the cursor while
# clicks select. Uses production button callbacks, dispatched mouse/key input
# and process updates (VaultGame._process).

const FOCUS := Vector2i(23, 16)
const FLOOR_CELL := Vector2i(18, 12)
const OTHER_FLOOR_CELL := Vector2i(20, 12)
const ROCK_CELL := Vector2i(16, 15)
const RESIDENT_CELL := Vector2i(20, 15)
const LAMP_CELL := Vector2i(22, 14)
const PREVIEW_TOOLS := ["dig", "cancel", "zone", "bed", "lamp", "generator", "grow", "kitchen", "stockpile", "air", "rec", "medical"]
const SAVE_SUFFIXES := ["", ".tmp", ".bak"]

var _saved_slot: Dictionary = {}


func _run() -> void:
	_backup_slot()
	_run_case("LOAD clears the Bunk ghost and its hover tint", _test_load_clears_bunk_ghost)
	_run_case("LOAD clears the hover preview of every tool", _test_load_clears_every_tool)
	_run_case("a click after LOAD selects and places nothing", _test_click_after_load_selects)
	_run_case("NEW WING after a loss clears the Bunk ghost in the same frame", _test_new_wing_clears_preview.bind("bed", FLOOR_CELL))
	_run_case("NEW WING after a loss clears the DIG hover tint in the same frame", _test_new_wing_clears_preview.bind("dig", ROCK_CELL))
	_run_case("LOAD LAST CHECKPOINT after a loss clears the Lumen preview", _test_checkpoint_clears_lumen)
	_run_case("briefing LOAD from HELP clears the Bunk ghost", _test_briefing_load_clears_ghost)
	_run_case("picking a tool again after LOAD shows its preview (control)", _test_tool_again_after_load)
	_run_case("selection, inspector and a held dig drag reset on LOAD", _test_selection_and_drag_reset)
	print("")
	print("PREVIEW TOOL ON LOAD TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	_restore_slot()
	quit(1 if _failure_count else 0)


# The real LOAD buttons use the one local slot; keep a developer's slot intact.
func _backup_slot() -> void:
	for suffix: String in SAVE_SUFFIXES:
		var path := SaveLoad.DEFAULT_PATH + suffix
		if FileAccess.file_exists(path):
			_saved_slot[suffix] = FileAccess.get_file_as_bytes(path)


func _restore_slot() -> void:
	_remove_test_save(SaveLoad.DEFAULT_PATH)
	for suffix: String in _saved_slot:
		var file := FileAccess.open(SaveLoad.DEFAULT_PATH + suffix, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_saved_slot[suffix])
			file.close()


func _paused_game() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	game.user_paused = true
	game.world_camera.position = game.map_grid.cell_to_world(FOCUS)
	game.world_camera.zoom = Vector2.ONE
	game._sync_3d_play_view(true)
	return game


func _frames(game: VaultGame, count := 1) -> void:
	for _index in count:
		game._process(0.0)


func _screen(game: VaultGame, cell: Vector2i) -> Vector2:
	var center := game.map_grid.cell_to_world(cell)
	var height := MapView3D.FLOOR_HEIGHT if game.map_grid.is_walkable(cell) else MapView3D.ROCK_HEIGHT
	return game.map_view_3d.camera_3d.unproject_position(Vector3(center.x, height, center.y))


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# Headless windows are not 1280x720: events carry window coordinates.
func _move(game: VaultGame, cell: Vector2i) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = root.get_screen_transform() * _screen(game, cell)
	motion.global_position = motion.position
	_send(motion)


func _mouse_button(game: VaultGame, cell: Vector2i, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = root.get_screen_transform() * _screen(game, cell)
	event.global_position = event.position
	_send(event)


func _click(game: VaultGame, cell: Vector2i) -> void:
	_move(game, cell)
	_mouse_button(game, cell, true)
	_mouse_button(game, cell, false)


func _press_tool(game: VaultGame, tool: String) -> void:
	game.player_orders.command_buttons[tool].pressed.emit()


func _find_button(parent: Node, text: String) -> Button:
	var stack: Array[Node] = [parent]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Button and (node as Button).text == text:
			return node
	return null


func _press(parent: Node, text: String) -> void:
	var button := _find_button(parent, text)
	_assert_true(button != null, "%s button exists" % text)
	if button != null:
		button.pressed.emit()


func _press_menu(game: VaultGame, text: String) -> void:
	_press(game.player_orders.architect_category_rows["menu"], text)


func _save_slot(game: VaultGame) -> void:
	_press_menu(game, "SAVE")
	_assert_true(FileAccess.file_exists(SaveLoad.DEFAULT_PATH), "fixture: SAVE wrote the local slot")


func _ghost_visible(game: VaultGame) -> bool:
	var ghost: Node3D = game.map_view_3d._build_ghost
	return ghost != null and is_instance_valid(ghost) and ghost.visible


# Live hex prisms (rebuilds queue_free the old ones) wearing a preview material.
func _tinted_count(game: VaultGame) -> int:
	var view := game.map_view_3d
	var count := 0
	for child: Node in view.hex_root.get_children():
		var prism := child as MeshInstance3D
		if prism == null or prism.is_queued_for_deletion():
			continue
		if prism.material_override == view._mat_hover_ok or prism.material_override == view._mat_hover_bad:
			count += 1
	return count


# 3 assertions: SELECT preview, no ghost, no tinted hex.
func _assert_no_preview(game: VaultGame, label: String) -> void:
	_assert_equal(game.map_grid.preview_tool, "select", "%s: preview tool is SELECT" % label)
	_assert_false(_ghost_visible(game), "%s: no build ghost" % label)
	_assert_equal(_tinted_count(game), 0, "%s: no hex wears a hover/range tint" % label)


func _hover(game: VaultGame, tool: String, cell: Vector2i) -> void:
	_press_tool(game, tool)
	_move(game, cell)
	_frames(game)


func _test_load_clears_bunk_ghost() -> void:
	var game := _paused_game()
	_save_slot(game)
	_hover(game, "bed", FLOOR_CELL)
	_assert_true(_ghost_visible(game), "fixture: the Bunk ghost shows at the cursor")
	_assert_equal(game.map_view_3d._build_ghost_kind, VaultBuilding.Kind.BED, "fixture: the ghost is a Bunk")
	_assert_equal(_tinted_count(game), 1, "fixture: the hovered hex is tinted")
	_press_menu(game, "LOAD")
	_assert_equal(game.active_tool, "select", "LOAD returns the tool to SELECT")
	_frames(game)
	_assert_no_preview(game, "after LOAD")
	_assert_true(game.player_orders.tool_status.text.begins_with("SELECT // Wing loaded."), "the HUD keeps the load message (got %s)" % game.player_orders.tool_status.text)
	_move(game, OTHER_FLOOR_CELL)
	_frames(game)
	_assert_equal(game.map_grid.hover_cell, OTHER_FLOOR_CELL, "fixture: the hover follows the cursor after LOAD")
	_assert_no_preview(game, "cursor moved after LOAD")
	_dispose(game)


func _test_load_clears_every_tool() -> void:
	var game := _paused_game()
	_save_slot(game)
	for tool: String in PREVIEW_TOOLS:
		_hover(game, tool, ROCK_CELL if tool == "dig" else FLOOR_CELL)
		_assert_true(_tinted_count(game) >= 1, "fixture: %s tints the hovered hex" % tool)
		_assert_equal(_ghost_visible(game), VaultGame.BUILD_KIND_BY_TOOL.has(tool), "fixture: %s shows a ghost only for a build tool" % tool)
		_press_menu(game, "LOAD")
		_frames(game)
		_assert_no_preview(game, "LOAD after %s" % tool)
	_dispose(game)


func _test_click_after_load_selects() -> void:
	var game := _paused_game()
	_save_slot(game)
	_hover(game, "bed", RESIDENT_CELL)
	_assert_true(_ghost_visible(game), "fixture: the Bunk ghost shows over Ari's floor")
	_press_menu(game, "LOAD")
	_frames(game)
	var building_count := game.buildings.size()
	_click(game, RESIDENT_CELL)
	_frames(game)
	_assert_equal(game.selected_resident_id, 1, "the click selects Ari")
	_assert_equal(game.buildings.size(), building_count, "the click places no blueprint")
	_assert_true(game.get_building_at(RESIDENT_CELL) == null, "nothing stands on the clicked floor")
	_assert_no_preview(game, "after the click")
	_dispose(game)


func _test_new_wing_clears_preview(tool: String, cell: Vector2i) -> void:
	var game := _paused_game()
	_hover(game, tool, cell)
	game._finish_loss()
	_frames(game)
	_assert_true(game.player_orders.outcome_panel.visible, "fixture: the loss shows the outcome panel")
	_assert_equal(_ghost_visible(game), VaultGame.BUILD_KIND_BY_TOOL.has(tool), "fixture: a ghost is up behind the outcome panel only for a build tool")
	_assert_equal(_tinted_count(game), 1, "fixture: the %s hover tint is up behind the outcome panel" % tool)
	_press(game.player_orders.outcome_panel, "NEW WING")
	# new_game() rebuilds the view itself; the reset must land before that sync.
	_assert_no_preview(game, "NEW WING, same frame")
	_frames(game)
	_assert_no_preview(game, "NEW WING, next frame")
	game.player_orders.briefing_begin_button.pressed.emit()
	game.user_paused = true
	_move(game, OTHER_FLOOR_CELL)
	_frames(game)
	_assert_equal(game.active_tool, "select", "the new wing starts on SELECT")
	_assert_no_preview(game, "new wing, cursor moved")
	_dispose(game)


func _test_checkpoint_clears_lumen() -> void:
	var game := _paused_game()
	_save_slot(game)
	_hover(game, "lamp", FLOOR_CELL)
	_assert_true(_tinted_count(game) > 1, "fixture: the Lumen preview tints its whole range")
	game._finish_loss()
	_frames(game)
	_press(game.player_orders.outcome_panel, "LOAD LAST CHECKPOINT")
	_frames(game)
	_assert_false(game.player_orders.outcome_panel.visible, "fixture: the checkpoint closes the outcome panel")
	_assert_no_preview(game, "LOAD LAST CHECKPOINT")
	_dispose(game)


func _test_briefing_load_clears_ghost() -> void:
	var game := _paused_game()
	_save_slot(game)
	_hover(game, "bed", FLOOR_CELL)
	game.player_orders.help_button.pressed.emit()
	_assert_true(game.player_orders.is_help_open(), "fixture: HELP opens the briefing")
	_assert_true(_ghost_visible(game), "fixture: the Bunk ghost is still up behind HELP")
	game.player_orders.briefing_load_button.pressed.emit()
	_frames(game)
	_assert_false(game.player_orders.is_briefing_open(), "fixture: briefing LOAD closes the briefing")
	_assert_no_preview(game, "briefing LOAD")
	_dispose(game)


func _press_escape() -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.physical_keycode = KEY_ESCAPE
		key.pressed = pressed
		_send(key)


func _test_tool_again_after_load() -> void:
	var game := _paused_game()
	_save_slot(game)
	_hover(game, "bed", FLOOR_CELL)
	_press_menu(game, "LOAD")
	_frames(game)
	_hover(game, "bed", FLOOR_CELL)
	_assert_equal(game.map_grid.preview_tool, "bed", "BUNK after LOAD previews the Bunk")
	_assert_true(_ghost_visible(game), "BUNK after LOAD shows the ghost")
	_assert_equal(_tinted_count(game), 1, "BUNK after LOAD tints the hovered hex")
	_hover(game, "lamp", FLOOR_CELL)
	_assert_true(_tinted_count(game) > 1, "LUMEN after LOAD tints its range")
	_press_escape()
	_frames(game)
	_assert_equal(game.active_tool, "select", "Esc returns to SELECT")
	_assert_no_preview(game, "Esc to SELECT")
	_dispose(game)


func _test_selection_and_drag_reset() -> void:
	var game := _paused_game()
	_save_slot(game)
	_press_tool(game, "select")
	_click(game, RESIDENT_CELL)
	_frames(game)
	_assert_equal(game.selected_resident_id, 1, "fixture: Ari is selected")
	_press_menu(game, "LOAD")
	_frames(game)
	_assert_equal(game.selected_resident_id, -1, "LOAD clears the selected resident")
	_assert_equal(game.player_orders.inspector_title.text, "INSPECTOR", "the inspector drops the resident")
	_click(game, LAMP_CELL)
	_frames(game)
	_assert_true(game.selected_building_id > 0, "fixture: the Lumen is selected")
	_press_menu(game, "LOAD")
	_frames(game)
	_assert_equal(game.selected_building_id, -1, "LOAD clears the selected fixture")
	_assert_equal(game.player_orders.inspector_title.text, "INSPECTOR", "the inspector drops the fixture")
	game.focus_breach()
	_assert_true(game.selected_breach, "fixture: hatch focus selects the hatch")
	_press_menu(game, "LOAD")
	_frames(game)
	_assert_false(game.selected_breach, "LOAD clears the hatch selection")
	_assert_equal(game.player_orders.inspector_title.text, "INSPECTOR", "the inspector drops the hatch")
	_press_tool(game, "dig")
	_move(game, ROCK_CELL)
	_mouse_button(game, ROCK_CELL, true)
	_assert_true(game.map_grid.dig_marks.has(ROCK_CELL), "fixture: the drag starts with a dig mark")
	_press_menu(game, "LOAD")
	_frames(game)
	_move(game, ROCK_CELL + Vector2i(0, 1))
	_move(game, ROCK_CELL + Vector2i(0, 2))
	_mouse_button(game, ROCK_CELL + Vector2i(0, 2), false)
	_assert_true(game.map_grid.dig_marks.is_empty(), "a drag held across LOAD marks nothing")
	_assert_no_preview(game, "drag held across LOAD")
	_dispose(game)
