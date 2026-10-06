extends SceneTree

## Terrain and drawn-resident picking regressions.
## Every click goes through the real input path: Input.parse_input_event ->
## VaultGame._unhandled_input -> issue_order_at_screen / issue_order.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const FOCUS := Vector2i(23, 16)
const EDGE_ZOOMS := [0.75, 1.0, 1.8]
const WHEEL_ZOOMS := [0.75, 0.88, 1.0, 1.12, 1.24, 1.36, 1.48, 1.6, 1.72, 1.8]
const ROCK_TARGETS := [Vector2i(23, 10), Vector2i(16, 15), Vector2i(29, 16), Vector2i(20, 21)]
const SIDE_TARGETS := [Vector2i(23, 10), Vector2i(16, 15), Vector2i(29, 16)]
const FLOOR_EDGE_TARGETS := [Vector2i(23, 16), Vector2i(22, 15), Vector2i(18, 12), Vector2i(27, 19)]
const AXIS_HEIGHTS := [3.0, 6.5, 9.0, 11.0, 12.5]

var _case_count := 0
var _assertion_count := 0
var _failure_count := 0
var _current_case := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for zoom: float in EDGE_ZOOMS:
		_run_case("rock tops near hex edges pick the rock at zoom %s" % zoom, _test_rock_tops.bind(zoom))
	for zoom: float in EDGE_ZOOMS:
		_run_case("visible rock sides near hex edges pick the rock at zoom %s" % zoom, _test_rock_sides.bind(zoom))
	_run_case("partly dug rock top picks at its rendered height", _test_partly_dug)
	_run_case("dig click on a rock top marks that rock", _test_dig_click)
	_run_case("drag-dig across rock tops marks the rocks under the cursor", _test_drag_dig)
	_run_case("off-map click falls back to the floor plane", _test_floor_fallback)
	for zoom: float in EDGE_ZOOMS:
		_run_case("ordinary floor centers unchanged at zoom %s" % zoom, _test_floor_centers.bind(zoom))
	for zoom: float in EDGE_ZOOMS:
		_run_case("floor near hex edges picks that floor at zoom %s" % zoom, _test_floor_edges.bind(zoom))
	_run_case("mid-step resident selected where drawn (18 of 24)", _test_mid_step.bind(true))
	_run_case("mid-step resident selected where drawn (real drafted step)", _test_mid_step.bind(false))
	for zoom: float in WHEEL_ZOOMS:
		_run_case("upper capsule selects that resident while paused at zoom %s" % zoom, _test_upper_capsule.bind(zoom))
	_run_case("re-click on a selected co-located resident cycles on the drawn hex", _test_cycle)
	_run_case("capsule clicks cycle three co-located residents in hex order", _test_cycle_three)
	_run_case("capsule clicks cycle two residents and the Emergency Core", _test_cycle_with_fixture)
	_run_case("clicking another resident's capsule switches directly", _test_direct_switch)
	_run_case("lying resident picked by its rotated capsule", _test_lying)
	_run_case("dead resident occludes but is not selectable", _test_dead)
	_run_case("terrain in front of a capsule wins", _test_terrain_occludes)
	_run_case("dig and build tools ignore residents", _test_tools_ignore_residents)
	_run_case("drafted right-click uses the terrain-aware hex", _test_right_click)
	print("TERRAIN AWARE PICKING TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(0 if _failure_count == 0 else 1)


func _run_case(label: String, test: Callable) -> void:
	_case_count += 1
	_current_case = label
	var before := _failure_count
	print("[TEST] %s" % label)
	test.call()
	print("[%s] %s" % ["PASS" if before == _failure_count else "FAIL", label])


func _spawn_game(zoom := 1.0) -> VaultGame:
	var game := MAIN_SCENE.instantiate() as VaultGame
	root.add_child(game)
	game.begin_shift()
	game.user_paused = true
	_focus(game, zoom)
	return game


func _focus(game: VaultGame, zoom: float, cell := FOCUS) -> void:
	game.world_camera.position = game.map_grid.cell_to_world(cell)
	game.world_camera.zoom = Vector2.ONE * zoom
	game._sync_3d_play_view(true)


func _screen(game: VaultGame, point: Vector3) -> Vector2:
	return game.map_view_3d.camera_3d.unproject_position(point)


# On screen, left of the right panel, and not under any HUD control that stops
# the mouse (the 52 px top bar, tip cards, ...), so the click reaches the world.
func _clickable(game: VaultGame, screen: Vector2) -> bool:
	var size := root.get_visible_rect().size
	if screen.x < 0.0 or screen.y < 0.0 or screen.x >= minf(size.x, 1280.0 - VaultGame.RIGHT_PANEL_WIDTH) or screen.y >= size.y:
		return false
	var stack: Array[Node] = [game.player_orders]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var control := node as Control
		if control != null and control.is_visible_in_tree() and control.mouse_filter == Control.MOUSE_FILTER_STOP and control.get_global_rect().has_point(screen):
			return false
	return true


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# Headless windows are not 1280x720: events carry window coordinates and the root
# viewport maps them back through its stretch transform.
func _window(viewport_pos: Vector2) -> Vector2:
	return root.get_screen_transform() * viewport_pos


func _move(viewport_pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = _window(viewport_pos)
	motion.global_position = motion.position
	_send(motion)


func _button(viewport_pos: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = _window(viewport_pos)
	event.global_position = event.position
	_send(event)


func _click(game: VaultGame, viewport_pos: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	_assert_true(_clickable(game, viewport_pos), "click %s is inside the play area" % viewport_pos)
	_move(viewport_pos)
	_button(viewport_pos, true, button)
	_button(viewport_pos, false, button)


func _clear_selection(game: VaultGame) -> void:
	game.selected_resident_id = -1
	game.selected_building_id = -1
	game.selected_breach = false
	for resident: VaultResident in game.residents:
		resident.selected = false


func _hex_samples(center: Vector2, inset: float) -> Array:
	var samples := [["center", center]]
	for index: int in 6:
		var angle := index * PI / 3.0
		samples.append(["vertex%d" % index, center + Vector2(sin(angle), cos(angle)) * (MapGrid.HEX_SIZE - inset)])
	for index: int in 6:
		var angle := index * PI / 3.0 + PI / 6.0
		samples.append(["edge%d" % index, center + Vector2(sin(angle), cos(angle)) * (MapGrid.HEX_SIZE * sqrt(3.0) * 0.5 - inset)])
	return samples


func _test_rock_tops(zoom: float) -> void:
	var game := _spawn_game(zoom)
	for target: Vector2i in ROCK_TARGETS:
		# The player pans to the rock; every sample is then on screen and clickable.
		_focus(game, zoom, target)
		_assert_equal(game.map_grid.get_tile(target), MapGrid.Tile.ROCK, "%s is rock" % target)
		var center := game.map_grid.cell_to_world(target)
		for sample: Array in _hex_samples(center, 1.5):
			var point: Vector2 = sample[1]
			var screen := _screen(game, Vector3(point.x, MapView3D.ROCK_HEIGHT, point.y))
			_assert_true(_clickable(game, screen), "%s top %s on screen" % [target, sample[0]])
			_assert_equal(game.map_view_3d.pick_cell(screen), target, "%s top %s" % [target, sample[0]])
	game.free()


func _test_rock_sides(zoom: float) -> void:
	var game := _spawn_game(zoom)
	var camera := game.map_view_3d.camera_3d
	for target: Vector2i in SIDE_TARGETS:
		_focus(game, zoom, target)
		var center := game.map_grid.cell_to_world(target)
		var faces := 0
		for face: int in 6:
			var angle := face * PI / 3.0 + PI / 6.0
			var normal := Vector2(sin(angle), cos(angle))
			var neighbor := game.map_grid.world_to_cell(center + normal * MapGrid.HEX_SIZE * sqrt(3.0))
			var to_camera := Vector2(camera.global_position.x, camera.global_position.z) - center
			# Only faces that border carved floor and face the camera are visible.
			if not game.map_grid.is_walkable(neighbor) or normal.dot(to_camera) <= 0.0:
				continue
			faces += 1
			var a := Vector2(sin(face * PI / 3.0), cos(face * PI / 3.0)) * MapGrid.HEX_SIZE
			var b := Vector2(sin((face + 1) * PI / 3.0), cos((face + 1) * PI / 3.0)) * MapGrid.HEX_SIZE
			for along: float in [0.2, 0.5, 0.8]:
				var point := center + a.lerp(b, along) - normal * 0.3
				for height: float in [1.5, 3.0, 4.5]:
					var screen := _screen(game, Vector3(point.x, height, point.y))
					_assert_true(_clickable(game, screen), "%s face %d sample on screen" % [target, face])
					_assert_equal(game.map_view_3d.pick_cell(screen), target, "%s face %d along %.2f y %.1f" % [target, face, along, height])
		_assert_true(faces >= 1, "%s has a visible floor-facing side" % target)
	game.free()


func _test_partly_dug() -> void:
	var game := _spawn_game(1.0)
	var target := Vector2i(23, 10)
	_assert_true(game.map_grid.queue_dig(target), "dig mark queued on %s" % target)
	game.map_grid.dig_progress[target] = 4.0
	game._sync_3d_play_view(true)
	var expected := lerpf(MapView3D.DIG_HEIGHT, MapView3D.FLOOR_HEIGHT, 0.5)
	var center := game.map_grid.cell_to_world(target)
	var prism: MeshInstance3D = null
	for child: Node in game.map_view_3d.hex_root.get_children():
		var instance := child as MeshInstance3D
		if instance != null and not instance.is_queued_for_deletion() and instance.mesh is CylinderMesh or (instance != null and not instance.is_queued_for_deletion() and instance.mesh is ArrayMesh):
			if Vector2(instance.position.x, instance.position.z).distance_to(center) < 0.01:
				prism = instance
	_assert_true(prism != null, "rendered prism found for %s" % target)
	if prism != null:
		_assert_true(absf(prism.scale.y - expected) < 0.0001, "rendered prism height is the half-dug height")
	for sample: Array in _hex_samples(center, 1.5):
		var point: Vector2 = sample[1]
		var screen := _screen(game, Vector3(point.x, expected, point.y))
		_assert_equal(game.map_view_3d.pick_cell(screen), target, "half-dug top %s" % sample[0])
	game.free()


func _vertex_point(cell_center: Vector2, index: int, inset: float) -> Vector2:
	var angle := index * PI / 3.0
	return cell_center + Vector2(sin(angle), cos(angle)) * (MapGrid.HEX_SIZE - inset)


func _test_dig_click() -> void:
	var game := _spawn_game(1.0)
	game.set_tool("dig")
	var target := Vector2i(23, 10)
	var point := _vertex_point(game.map_grid.cell_to_world(target), 5, 1.5)
	var screen := _screen(game, Vector3(point.x, MapView3D.ROCK_HEIGHT, point.y))
	_move(screen)
	_assert_equal(game.map_grid.hover_cell, target, "hover shows the rock under the cursor")
	_click(game, screen)
	_assert_equal(game.map_grid.dig_marks.keys(), [target], "zoom 1.0 dig lands on the clicked rock only")
	game.free()
	game = _spawn_game(1.8)
	_focus(game, 1.8, target)
	game.set_tool("dig")
	var center := game.map_grid.cell_to_world(target)
	_click(game, _screen(game, Vector3(center.x, MapView3D.ROCK_HEIGHT, center.y)))
	_assert_equal(game.map_grid.dig_marks.keys(), [target], "zoom 1.8 top-center dig lands on the clicked rock")
	game.free()


func _test_drag_dig() -> void:
	var game := _spawn_game(1.0)
	game.set_tool("dig")
	var first := Vector2i(23, 10)
	var second := Vector2i(24, 10)
	# 1.5u inside each rock's north-west vertex: the y=0 plane lands a row north.
	var a := _vertex_point(game.map_grid.cell_to_world(first), 4, 1.5)
	var b := _vertex_point(game.map_grid.cell_to_world(second), 4, 1.5)
	var sa := _screen(game, Vector3(a.x, MapView3D.ROCK_HEIGHT, a.y))
	var sb := _screen(game, Vector3(b.x, MapView3D.ROCK_HEIGHT, b.y))
	_assert_true(_clickable(game, sa), "drag start is inside the play area")
	_assert_true(_clickable(game, sb), "drag end is inside the play area")
	_move(sa)
	_button(sa, true)
	_move(sb)
	_button(sb, false)
	var marks := game.map_grid.dig_marks.keys()
	marks.sort()
	_assert_equal(marks, [first, second], "drag marks exactly the two rocks under the cursor")
	game.free()


func _test_floor_fallback() -> void:
	var game := _spawn_game(0.75)
	_focus(game, 0.75, Vector2i(1, 1))
	game.set_tool("dig")
	var view := game.map_view_3d
	var checked := 0
	for screen: Vector2 in [Vector2(40, 80), Vector2(160, 70), Vector2(30, 200), Vector2(30, 400)]:
		var plane := game.map_grid.world_to_cell(view.screen_to_world_xz(screen))
		# Off the map even where the ray is at rock height: no prism can be hit.
		var from := view.camera_3d.project_ray_origin(screen)
		var dir := view.camera_3d.project_ray_normal(screen)
		var high := from + dir * ((MapView3D.ROCK_HEIGHT - from.y) / dir.y)
		var high_cell := game.map_grid.world_to_cell(Vector2(high.x, high.z))
		if game.map_grid.is_inside(plane) or game.map_grid.is_inside(high_cell) or not _clickable(game, screen):
			continue
		checked += 1
		_assert_equal(view.pick_cell(screen), plane, "off-map %s uses the y=0 plane cell" % screen)
		_click(game, screen)
		_assert_true(game.map_grid.dig_marks.is_empty(), "off-map dig click changes nothing")
	_assert_true(checked >= 2, "at least two probe points are off the map (got %d)" % checked)
	game.free()


func _test_floor_centers(zoom: float) -> void:
	var game := _spawn_game(zoom)
	var checked := 0
	for cell: Vector2i in game.map_grid.get_floor_cells():
		var center := game.map_grid.cell_to_world(cell)
		for height: float in [0.0, MapView3D.FLOOR_HEIGHT]:
			var screen := _screen(game, Vector3(center.x, height, center.y))
			if not _clickable(game, screen):
				continue
			checked += 1
			_assert_equal(game.map_view_3d.pick_cell(screen), cell, "floor %s center y %.2f" % [cell, height])
	_assert_true(checked >= 100, "at least 100 floor centers on screen (got %d)" % checked)
	game.set_tool("bed")
	game.food_system.salvage = 99
	var target := Vector2i(25, 14)
	var c := game.map_grid.cell_to_world(target)
	var before := game.buildings.size()
	_click(game, _screen(game, Vector3(c.x, MapView3D.FLOOR_HEIGHT, c.y)))
	_assert_equal(game.buildings.size(), before + 1, "bed click places one blueprint")
	if game.buildings.size() == before + 1:
		_assert_equal(game.buildings[before].cell, target, "bed blueprint on the clicked floor")
	game.set_tool("select")
	_clear_selection(game)
	var core := game.map_grid.cell_to_world(Vector2i(24, 15))
	_click(game, _screen(game, Vector3(core.x, MapView3D.FLOOR_HEIGHT, core.y)))
	_assert_equal(game.selected_building_id, 1, "select click on the Emergency Core floor selects it")
	game.free()


func _test_floor_edges(zoom: float) -> void:
	var game := _spawn_game(zoom)
	for target: Vector2i in FLOOR_EDGE_TARGETS:
		var center := game.map_grid.cell_to_world(target)
		for sample: Array in _hex_samples(center, 0.4):
			var point: Vector2 = sample[1]
			var screen := _screen(game, Vector3(point.x, MapView3D.FLOOR_HEIGHT, point.y))
			_assert_equal(game.map_view_3d.pick_cell(screen), target, "floor %s %s inset 0.4" % [target, sample[0]])
	game.free()


func _test_mid_step(direct: bool) -> void:
	var game := _spawn_game(1.0)
	for resident: VaultResident in game.residents:
		for key: String in ["dig", "haul", "craft", "cook"]:
			resident.work_allowed[key] = false
		game.job_system.release_resident(resident)
	var ari: VaultResident = game.get_resident_by_id(1)
	var start := game.map_grid.cell_to_world(Vector2i(20, 15))
	if direct:
		ari.position = start + Vector2(18.0, 0.0)
	else:
		game.toggle_resident_draft(1)
		_assert_true(game._issue_drafted_move(ari, Vector2i(21, 15)), "drafted move to (21,15) accepted")
		game.step_simulation(0.2)
	_assert_true(ari.position.x - start.x > 12.0 and ari.position.x - start.x < 24.0, "Ari is past the midpoint, not arrived")
	_assert_equal(game.map_grid.world_to_cell(ari.position), Vector2i(21, 15), "Ari is drawn in (21,15)")
	_assert_equal(ari._occupancy_cell, Vector2i(20, 15), "sim occupancy still (20,15)")
	var position_before := ari.position
	var path_before: Array = ari._path.duplicate()
	var index_before := ari._path_index
	var elapsed_before := game.day_cycle.elapsed_seconds
	for zoom: float in EDGE_ZOOMS:
		_focus(game, zoom)
		var proxy: MeshInstance3D = game.map_view_3d._resident_proxies[1]
		var drawn := game.map_grid.cell_to_world(Vector2i(21, 15))
		var targets := {
			"drawn hex center": Vector3(drawn.x, MapView3D.FLOOR_HEIGHT, drawn.y),
			"capsule center": proxy.global_position,
			"upper capsule": proxy.global_position + Vector3(0.0, 4.5, 0.0),
		}
		for label: String in targets:
			_clear_selection(game)
			_click(game, _screen(game, targets[label]))
			_assert_equal(game.selected_resident_id, 1, "%s at zoom %s selects Ari" % [label, zoom])
		_clear_selection(game)
		var old_center := game.map_grid.cell_to_world(Vector2i(20, 15))
		_click(game, _screen(game, Vector3(old_center.x, MapView3D.FLOOR_HEIGHT, old_center.y)))
		_assert_equal(game.selected_resident_id, -1, "old occupancy hex (20,15) at zoom %s selects nobody" % zoom)
	_assert_equal(ari._occupancy_cell, Vector2i(20, 15), "clicks leave occupancy untouched")
	_assert_equal(ari.position, position_before, "clicks leave position untouched")
	_assert_equal(ari._path, path_before, "clicks leave the path untouched")
	_assert_equal(ari._path_index, index_before, "clicks leave the path index untouched")
	_assert_equal(game.day_cycle.elapsed_seconds, elapsed_before, "no simulation time passed")
	game.free()


func _test_upper_capsule(zoom: float) -> void:
	var game := _spawn_game(zoom)
	_assert_true(game.user_paused, "starting layout is paused")
	var elapsed_before := game.day_cycle.elapsed_seconds
	for resident: VaultResident in game.residents:
		var proxy: MeshInstance3D = game.map_view_3d._resident_proxies[resident.resident_id]
		for height: float in AXIS_HEIGHTS:
			_clear_selection(game)
			_click(game, _screen(game, Vector3(proxy.global_position.x, height, proxy.global_position.z)))
			_assert_equal(game.selected_resident_id, resident.resident_id, "%s y %.1f selects %s" % [resident.resident_name, height, resident.resident_name])
		# Re-clicking the selected resident keeps them selected (no co-located cycle target).
		_click(game, _screen(game, Vector3(proxy.global_position.x, 11.0, proxy.global_position.z)))
		_assert_equal(game.selected_resident_id, resident.resident_id, "re-click keeps %s selected" % resident.resident_name)
	_assert_true(game.user_paused, "still paused after clicks")
	_assert_equal(game.day_cycle.elapsed_seconds, elapsed_before, "no simulation time passed")
	game.free()


func _test_cycle() -> void:
	var game := _spawn_game(1.0)
	var ari: VaultResident = game.get_resident_by_id(1)
	var bo: VaultResident = game.get_resident_by_id(2)
	bo.position = ari.position
	game._sync_3d_play_view(true)
	var proxy: MeshInstance3D = game.map_view_3d._resident_proxies[1]
	var screen := _screen(game, proxy.global_position + Vector3(0.0, 4.0, 0.0))
	_clear_selection(game)
	_click(game, screen)
	var first := game.selected_resident_id
	_assert_true(first == 1 or first == 2, "first click selects one of the stacked residents")
	_click(game, screen)
	_assert_equal(game.selected_resident_id, 3 - first, "re-click cycles to the other stacked resident")
	_click(game, screen)
	_assert_equal(game.selected_resident_id, first, "third click cycles back")
	game.free()


# Records each selection as R<resident id> or B<building id>.
func _selection_label(game: VaultGame) -> String:
	if game.selected_resident_id != -1:
		return "R%d" % game.selected_resident_id
	if game.selected_building_id != -1:
		return "B%d" % game.selected_building_id
	return "none"


func _click_sequence(game: VaultGame, screen: Vector2, clicks: int) -> Array[String]:
	var sequence: Array[String] = []
	for _i: int in clicks:
		_click(game, screen)
		sequence.append(_selection_label(game))
	return sequence


func _test_cycle_three() -> void:
	var game := _spawn_game(1.0)
	var hex := Vector2i(22, 17)
	_assert_equal(game.map_grid.get_tile(hex), MapGrid.Tile.FLOOR, "(22,17) is a floor hex")
	var center := game.map_grid.cell_to_world(hex)
	for resident_id: int in [1, 2, 3]:
		game.get_resident_by_id(resident_id).position = center
	game._sync_3d_play_view(true)
	var proxy: MeshInstance3D = game.map_view_3d._resident_proxies[1]
	var screen := _screen(game, Vector3(proxy.global_position.x, 4.0, proxy.global_position.z))
	_clear_selection(game)
	_assert_equal(_click_sequence(game, screen, 4), ["R1", "R2", "R3", "R1"], "four capsule clicks walk the hex order and wrap")
	game.free()


func _test_cycle_with_fixture() -> void:
	var game := _spawn_game(1.0)
	var hex := Vector2i(24, 15)
	var core := game.get_building_at(hex)
	_assert_true(core != null and core.is_emergency_core, "the Emergency Core stands on (24,15)")
	if core == null:
		game.free()
		return
	var spot := game.map_grid.cell_to_world(hex) + Vector2(0.0, 7.0)
	_assert_equal(game.map_grid.world_to_cell(spot), hex, "centre + (0,7) is still drawn in (24,15)")
	for resident_id: int in [1, 2]:
		game.get_resident_by_id(resident_id).position = spot
	game._sync_3d_play_view(true)
	var proxy: MeshInstance3D = game.map_view_3d._resident_proxies[1]
	var screen := _screen(game, Vector3(proxy.global_position.x, 9.0, proxy.global_position.z))
	_clear_selection(game)
	var core_label := "B%d" % core.building_id
	_assert_equal(_click_sequence(game, screen, 4), ["R1", "R2", core_label, "R1"], "capsule clicks reach the fixture, then wrap")
	game.free()


func _test_direct_switch() -> void:
	var game := _spawn_game(1.0)
	var view := game.map_view_3d
	if not view.has_method("pick_resident_id"):
		_fail("pick_resident_id", "MapView3D.pick_resident_id is missing")
		_assertion_count += 1
		game.free()
		return
	var ari: VaultResident = game.get_resident_by_id(1)
	var bo_proxy: MeshInstance3D = view._resident_proxies[2]
	var screen := _screen(game, Vector3(bo_proxy.global_position.x, 6.5, bo_proxy.global_position.z))
	var only_ari: Array[VaultResident] = [ari]
	_assert_equal(view.call("pick_resident_id", screen, only_ari), -1, "Ari's capsule is not under the cursor")
	_assert_equal(view.call("pick_resident_id", screen, game.residents), 2, "Bo's capsule is under the cursor")
	game.select_resident(1)
	_click(game, screen)
	_assert_equal(game.selected_resident_id, 2, "clicking Bo with Ari selected selects Bo")
	game.free()


func _test_lying() -> void:
	var game := _spawn_game(1.0)
	var ari: VaultResident = game.get_resident_by_id(1)
	ari.sleeping = true
	ari.bed_id = -1
	game._sync_3d_play_view(true)
	var proxy: MeshInstance3D = game.map_view_3d._resident_proxies[1]
	_assert_true(absf(proxy.rotation.x - PI / 2.0) < 0.0001, "Ari's proxy lies down")
	for offset: float in [-3.5, 0.0, 3.5]:
		_clear_selection(game)
		var point := proxy.global_position + proxy.global_transform.basis.y.normalized() * offset
		_click(game, _screen(game, point))
		_assert_equal(game.selected_resident_id, 1, "lying capsule offset %.1f selects Ari" % offset)
	var view := game.map_view_3d
	if not view.has_method("pick_resident_id"):
		_fail("pick_resident_id", "MapView3D.pick_resident_id is missing")
		_assertion_count += 1
		game.free()
		return
	var axis := proxy.global_transform.basis.y.normalized()
	for offset: float in [-5.5, 0.0, 5.5]:
		var screen := _screen(game, proxy.global_position + axis * offset)
		_assert_equal(view.call("pick_resident_id", screen, game.residents), 1, "rotated capsule offset %.1f picks Ari" % offset)
	for rise: float in [6.0, 9.0]:
		var air := _screen(game, proxy.global_position + Vector3(0.0, rise, 0.0))
		_assert_equal(view.call("pick_resident_id", air, game.residents), -1, "air %.1f above the lying capsule (upright pill space) picks nobody" % rise)
	game.free()


func _test_dead() -> void:
	var game := _spawn_game(1.0)
	var bo: VaultResident = game.get_resident_by_id(2)
	bo.alive = false
	game._sync_3d_play_view(true)
	var proxy: MeshInstance3D = game.map_view_3d._resident_proxies[2]
	for height: float in [9.0, 11.0, 12.5]:
		_clear_selection(game)
		_click(game, _screen(game, Vector3(proxy.global_position.x, height, proxy.global_position.z)))
		_assert_equal(game.selected_resident_id, -1, "dead Bo y %.1f selects nobody (not Ari behind)" % height)
	game.free()


func _test_terrain_occludes() -> void:
	var game := _spawn_game(1.0)
	var view := game.map_view_3d
	if not view.has_method("pick_resident_id"):
		_fail("pick_resident_id", "MapView3D.pick_resident_id is missing")
		_assertion_count += 1
		game.free()
		return
	var ari: VaultResident = game.get_resident_by_id(1)
	var rock := Vector2i(23, 9)
	ari.position = game.map_grid.cell_to_world(rock)
	game._sync_3d_play_view(true)
	var screen := _screen(game, Vector3(ari.position.x, 2.0, ari.position.y))
	_assert_equal(view.call("pick_resident_id", screen, game.residents), -1, "rock in front of Ari's buried legs wins")
	_assert_equal(view.pick_cell(screen), rock, "terrain pick is the rock")
	var head := _screen(game, Vector3(ari.position.x, 11.0, ari.position.y))
	_assert_equal(view.call("pick_resident_id", head, game.residents), 1, "Ari's head above the rock is still pickable")
	game.free()


func _test_tools_ignore_residents() -> void:
	var game := _spawn_game(1.0)
	var bo_proxy: MeshInstance3D = game.map_view_3d._resident_proxies[2]
	var screen := _screen(game, Vector3(bo_proxy.global_position.x, 11.0, bo_proxy.global_position.z))
	game.set_tool("dig")
	_click(game, screen)
	_assert_true(game.map_grid.dig_marks.is_empty(), "dig click on Bo's head marks nothing")
	_assert_equal(game.selected_resident_id, -1, "dig click selects nobody")
	game.set_tool("bed")
	game.food_system.salvage = 99
	var before := game.buildings.size()
	_move(screen)
	var hover := game.map_grid.hover_cell
	_assert_equal(hover, game.map_view_3d.pick_cell(screen), "hover equals the terrain pick")
	_click(game, screen)
	_assert_equal(game.buildings.size(), before + 1, "bed click places one blueprint")
	if game.buildings.size() == before + 1:
		_assert_equal(game.buildings[before].cell, hover, "blueprint lands on the hovered terrain hex")
	_assert_equal(game.selected_resident_id, -1, "build click selects nobody")
	game.free()


func _test_right_click() -> void:
	var game := _spawn_game(1.0)
	game.toggle_resident_draft(1)
	game.select_resident(1)
	var target := Vector2i(23, 16)
	var point := game.map_grid.cell_to_world(target) + Vector2(sin(PI + PI / 6.0), cos(PI + PI / 6.0)) * (MapGrid.HEX_SIZE * sqrt(3.0) * 0.5 - 0.4)
	_click(game, _screen(game, Vector3(point.x, MapView3D.FLOOR_HEIGHT, point.y)), MOUSE_BUTTON_RIGHT)
	var ari: VaultResident = game.get_resident_by_id(1)
	_assert_equal(ari.manual_destination, target, "drafted move goes to the floor hex under the cursor")
	game.free()


func _assert_true(condition: bool, message: String) -> void:
	_assert_equal(condition, true, message)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	_assertion_count += 1
	if actual != expected:
		_fail(message, "expected %s, got %s" % [str(expected), str(actual)])


func _fail(message: String, detail: String) -> void:
	_failure_count += 1
	printerr("[FAIL] %s :: %s — %s" % [_current_case, message, detail])
