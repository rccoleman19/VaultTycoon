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
	_run_case("a selected resident behind on another hex does not hijack the click", _test_cross_hex_behind)
	_run_case("lying resident picked by its rotated capsule", _test_lying)
	_run_case("dead resident occludes but is not selectable", _test_dead)
	_run_case("terrain in front of a capsule wins", _test_terrain_occludes)
	_run_case("dig and build tools ignore residents", _test_tools_ignore_residents)
	_run_case("drafted right-click uses the terrain-aware hex", _test_right_click)
	for zoom: float in EDGE_ZOOMS:
		_run_case("starting fixture tops and fronts pick their own hex at zoom %s" % zoom, _test_fixture_parts.bind(zoom))
	_run_case("every fixture kind's tops and fronts pick its own hex", _test_fixture_kinds)
	_run_case("a build click on a fixture top does not build behind it", _test_fixture_build_click)
	_run_case("a fixture in front of a capsule hides it", _test_fixture_occludes_capsule)
	_run_case("terrain in front of a fixture wins", _test_terrain_occludes_fixture)
	_run_case("a blueprint picks at its drawn scale", _test_blueprint_scale)
	_run_case("cylinder parts pick as drawn cylinders, not their boxes", _test_cylinder_not_box)
	for phase: int in [BreachSystem.Phase.DORMANT, BreachSystem.Phase.WARNING, BreachSystem.Phase.OPEN]:
		_run_case("hatch hex click order: capsule first, then the hatch (%s)" % BreachSystem.Phase.keys()[phase], _test_hatch_click_order.bind(phase))
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


# Proves a click lands on the capsule branch (a resident is under the cursor).
func _assert_capsule_hit(game: VaultGame, screen: Vector2, label: String) -> void:
	var view := game.map_view_3d
	if not view.has_method("pick_resident_id"):
		_fail("pick_resident_id", "MapView3D.pick_resident_id is missing")
		_assertion_count += 1
		return
	_assert_true(int(view.call("pick_resident_id", screen, game.residents)) != -1, "%s: a capsule is under the cursor" % label)


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
	_assert_capsule_hit(game, screen, "three co-located")
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
	_assert_capsule_hit(game, screen, "residents on the core")
	_clear_selection(game)
	var core_label := "B%d" % core.building_id
	_assert_equal(_click_sequence(game, screen, 4), ["R1", "R2", core_label, "R1"], "capsule clicks reach the fixture, then wrap")
	game.free()


# Cyra is selected and stands on (22,17) too (her default spawn), off the ray.
# Ari (first in hex order) and Bo also share (22,17), with Ari off the ray, so
# only a direct switch selects Bo. Treating "selected resident shares the hex"
# alone as a re-click would cycle the hex and select Ari.
func _test_direct_switch() -> void:
	var game := _spawn_game(1.0)
	var view := game.map_view_3d
	if not view.has_method("pick_resident_id"):
		_fail("pick_resident_id", "MapView3D.pick_resident_id is missing")
		_assertion_count += 1
		game.free()
		return
	var hex := Vector2i(22, 17)
	var center := game.map_grid.cell_to_world(hex)
	var ari: VaultResident = game.get_resident_by_id(1)
	var bo: VaultResident = game.get_resident_by_id(2)
	var cyra: VaultResident = game.get_resident_by_id(3)
	ari.position = center + Vector2(4.0, 0.0)
	bo.position = center + Vector2(-4.0, 0.0)
	_assert_equal(game.map_grid.world_to_cell(ari.position), hex, "Ari is drawn in (22,17)")
	_assert_equal(game.map_grid.world_to_cell(bo.position), hex, "Bo is drawn in (22,17)")
	_assert_equal(game.map_grid.world_to_cell(cyra.position), hex, "selected Cyra also stands on (22,17), off the ray")
	game._sync_3d_play_view(true)
	var bo_proxy: MeshInstance3D = view._resident_proxies[2]
	var screen := _screen(game, Vector3(bo_proxy.global_position.x, 6.5, bo_proxy.global_position.z))
	var only_cyra: Array[VaultResident] = [cyra]
	var only_ari: Array[VaultResident] = [ari]
	_assert_equal(view.call("pick_resident_id", screen, game.residents), 2, "Bo's capsule is the hit")
	_assert_equal(view.call("pick_resident_id", screen, only_cyra), -1, "selected Cyra's capsule is not under the cursor")
	_assert_equal(view.call("pick_resident_id", screen, only_ari), -1, "Ari's capsule is not under the cursor")
	game.select_resident(3)
	_click(game, screen)
	_assert_equal(game.selected_resident_id, 2, "clicking Bo selects Bo directly (not Ari, first on the hex)")
	game.free()


# Offsets from the (22,17) centre: Cyra (-5,-6.4) and Bo (0,0) on (22,17); selected
# Ari (-7,-14.4) on another hex, behind Cyra's capsule along the ray. The click on
# Cyra must select Cyra; it is not a re-click of Ari.
func _test_cross_hex_behind() -> void:
	var game := _spawn_game(1.0)
	var view := game.map_view_3d
	if not view.has_method("pick_resident_id"):
		_fail("pick_resident_id", "MapView3D.pick_resident_id is missing")
		_assertion_count += 1
		game.free()
		return
	var hex := Vector2i(22, 17)
	var center := game.map_grid.cell_to_world(hex)
	var ari: VaultResident = game.get_resident_by_id(1)
	var bo: VaultResident = game.get_resident_by_id(2)
	var cyra: VaultResident = game.get_resident_by_id(3)
	cyra.position = center + Vector2(-5.0, -6.4)
	ari.position = center + Vector2(-7.0, -14.4)
	bo.position = center
	_assert_equal(game.map_grid.world_to_cell(cyra.position), hex, "Cyra is drawn in (22,17)")
	_assert_equal(game.map_grid.world_to_cell(bo.position), hex, "Bo is drawn in (22,17)")
	_assert_true(game.map_grid.world_to_cell(ari.position) != hex, "selected Ari is drawn on another hex")
	game._sync_3d_play_view(true)
	var cyra_proxy: MeshInstance3D = view._resident_proxies[3]
	var screen := _screen(game, Vector3(cyra_proxy.global_position.x, 9.0, cyra_proxy.global_position.z))
	var only_ari: Array[VaultResident] = [ari]
	_assert_equal(view.call("pick_resident_id", screen, game.residents), 3, "Cyra's capsule is the hit")
	_assert_equal(view.call("pick_resident_id", screen, only_ari), 1, "selected Ari's capsule is behind it on the ray")
	game.select_resident(1)
	_click(game, screen)
	_assert_equal(game.selected_resident_id, 3, "clicking Cyra selects Cyra, not Bo via a cross-hex re-click")
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


# Residents wait on (18,12), behind every starting fixture and off their rays.
func _park_residents(game: VaultGame) -> void:
	for resident: VaultResident in game.residents:
		resident.position = game.map_grid.cell_to_world(Vector2i(18, 12))
	game._sync_3d_play_view(true)


# The top-face and camera-facing (+Z) face centres of every drawn part.
func _part_samples(proxy: Node3D) -> Array:
	var samples := []
	for part: MeshInstance3D in proxy.get_children():
		var box := part.mesh.get_aabb()
		samples.append(["%s top" % part.name, part.global_transform * (box.get_center() + Vector3(0.0, box.size.y * 0.5, 0.0))])
		samples.append(["%s front" % part.name, part.global_transform * (box.get_center() + Vector3(0.0, 0.0, box.size.z * 0.5))])
	return samples


func _highest_top(proxy: Node3D) -> Vector3:
	var best := Vector3(0.0, -INF, 0.0)
	for sample: Array in _part_samples(proxy):
		if String(sample[0]).ends_with(" top") and sample[1].y > best.y:
			best = sample[1]
	return best


func _capsule_on_ray(game: VaultGame, screen: Vector2, resident: VaultResident) -> bool:
	var view := game.map_view_3d
	var proxy: MeshInstance3D = view._resident_proxies[resident.resident_id]
	var to_local := proxy.global_transform.affine_inverse()
	return view._ray_capsule(to_local * view.camera_3d.project_ray_origin(screen), to_local.basis * view.camera_3d.project_ray_normal(screen)) < INF


func _test_fixture_parts(zoom: float) -> void:
	var game := _spawn_game(zoom)
	_park_residents(game)
	_assert_equal(game.buildings.size(), 3, "starting layout has the Core, the Lumen and the Salvage Bay")
	for building: VaultBuilding in game.buildings:
		_focus(game, zoom, building.cell)
		var proxy: Node3D = game.map_view_3d._building_proxies[building.building_id]
		for sample: Array in _part_samples(proxy):
			var screen := _screen(game, sample[1])
			var label := "%s %s y %.2f" % [building.get_display_name(), sample[0], sample[1].y]
			_assert_equal(game.map_view_3d.pick_cell(screen), building.cell, label)
			_clear_selection(game)
			_click(game, screen)
			_assert_equal(_selection_label(game), "B%d" % building.building_id, "select click on %s" % label)
	game.free()


func _test_fixture_kinds() -> void:
	var cell := Vector2i(25, 14)
	for kind: int in VaultBuilding.Kind.values():
		var game := _spawn_game(1.0)
		_focus(game, 1.0, cell)
		_park_residents(game)
		game._spawn_starting_fixture(kind, cell, false)
		game._sync_3d_play_view(true)
		var building: VaultBuilding = game.get_building_at(cell)
		var proxy: Node3D = game.map_view_3d._building_proxies[building.building_id]
		var kind_name: String = VaultBuilding.Kind.keys()[kind]
		# Picking skips hexes the ray never nears, so every part must stay in its hex.
		var reach := 0.0
		for part: MeshInstance3D in proxy.get_children():
			var box := part.mesh.get_aabb()
			for corner: int in 8:
				var point: Vector3 = part.global_transform * box.get_endpoint(corner)
				reach = maxf(reach, Vector2(point.x, point.z).distance_to(game.map_grid.cell_to_world(cell)))
		_assert_true(reach <= MapGrid.HEX_SIZE, "%s is drawn inside its hex (reach %.2f)" % [kind_name, reach])
		for sample: Array in _part_samples(proxy):
			_assert_equal(game.map_view_3d.pick_cell(_screen(game, sample[1])), cell, "%s %s y %.2f" % [kind_name, sample[0], sample[1].y])
		_clear_selection(game)
		_click(game, _screen(game, _highest_top(proxy)))
		_assert_equal(_selection_label(game), "B%d" % building.building_id, "select click on the %s's highest top" % kind_name)
		game.free()


func _test_fixture_build_click() -> void:
	var game := _spawn_game(1.0)
	_park_residents(game)
	var lumen := game.get_building_at(Vector2i(22, 14))
	_assert_true(lumen != null and lumen.kind == VaultBuilding.Kind.LAMP, "the Lumen stands on (22,14)")
	if lumen == null:
		game.free()
		return
	var screen := _screen(game, _highest_top(game.map_view_3d._building_proxies[lumen.building_id]))
	game.set_tool("bed")
	var before := game.buildings.size()
	_move(screen)
	_assert_equal(game.map_grid.hover_cell, lumen.cell, "hovering the Lumen's top shows the Lumen's hex")
	_click(game, screen)
	_assert_equal(game.buildings.size(), before, "a bed click on the Lumen's top places nothing behind it")
	game.free()


# Ari stands behind the Lumen on its hex; Bo, selected, shares the hex off the ray.
# A click on the Lumen's face is a click on the Lumen: no capsule hit, so the hex
# cycle moves on from Bo to the Lumen instead of jumping to hidden Ari.
func _test_fixture_occludes_capsule() -> void:
	var game := _spawn_game(1.0)
	var view := game.map_view_3d
	var hex := Vector2i(22, 14)
	var lumen := game.get_building_at(hex)
	var center := game.map_grid.cell_to_world(hex)
	var ari: VaultResident = game.get_resident_by_id(1)
	var bo: VaultResident = game.get_resident_by_id(2)
	_park_residents(game)
	ari.position = center + Vector2(0.0, -6.0)
	bo.position = center + Vector2(9.0, 0.0)
	_focus(game, 1.0, hex)
	_assert_equal(game.map_grid.world_to_cell(ari.position), hex, "Ari is drawn on the Lumen's hex")
	_assert_equal(game.map_grid.world_to_cell(bo.position), hex, "Bo is drawn on the Lumen's hex")
	var proxy: Node3D = view._building_proxies[lumen.building_id]
	var hidden := 0
	for sample: Array in _part_samples(proxy):
		var screen := _screen(game, sample[1])
		if not _capsule_on_ray(game, screen, ari) or _capsule_on_ray(game, screen, bo):
			continue
		hidden += 1
		_assert_equal(view.call("pick_resident_id", screen, game.residents), -1, "Lumen %s hides Ari behind it" % sample[0])
		_assert_equal(view.pick_cell(screen), hex, "Lumen %s picks the Lumen's hex" % sample[0])
		game.select_resident(2)
		_click(game, screen)
		_assert_equal(_selection_label(game), "B%d" % lumen.building_id, "Lumen %s with Bo selected selects the Lumen, not hidden Ari" % sample[0])
	_assert_true(hidden >= 3, "at least three Lumen faces lie in front of Ari (got %d)" % hidden)
	var head := _screen(game, Vector3(ari.position.x, 12.0, ari.position.y))
	_assert_equal(view.call("pick_resident_id", head, game.residents), 1, "Ari's head above the Lumen is still pickable")
	game.free()


# A bed on a floor hex whose camera-side neighbours are rock: low points on its
# front face that the rock hides pick the rock.
func _test_terrain_occludes_fixture() -> void:
	var game := _spawn_game(1.0)
	var view := game.map_view_3d
	var cell := Vector2i(-1, -1)
	for candidate: Vector2i in game.map_grid.get_floor_cells():
		if candidate == BreachSystem.HATCH_CELL or game.get_building_at(candidate) != null:
			continue
		var front := 0
		var rock := 0
		for neighbor: Vector2i in game.map_grid.get_neighbors(candidate):
			if game.map_grid.cell_to_world(neighbor).y > game.map_grid.cell_to_world(candidate).y:
				front += 1
				if game.map_grid.get_tile(neighbor) == MapGrid.Tile.ROCK:
					rock += 1
		if front == 2 and rock == 2:
			cell = candidate
			break
	_assert_true(cell != Vector2i(-1, -1), "a floor hex with rock on both camera-side neighbours exists")
	if cell == Vector2i(-1, -1):
		game.free()
		return
	_park_residents(game)
	game._spawn_starting_fixture(VaultBuilding.Kind.BED, cell, false)
	_focus(game, 1.0, cell)
	var proxy: Node3D = view._building_proxies[game.get_building_at(cell).building_id]
	var foot: MeshInstance3D = proxy.get_node("Foot")
	var box := foot.mesh.get_aabb()
	var hidden := 0
	for x: float in [-3.5, 0.0, 3.5]:
		for y: float in [-0.6, 0.0]:
			var point: Vector3 = foot.global_transform * Vector3(x, y, box.end.z)
			var screen := _screen(game, point)
			var from := view.camera_3d.project_ray_origin(screen)
			var terrain: Dictionary = view._pick_terrain(from, view.camera_3d.project_ray_normal(screen))
			if terrain.get("t", INF) >= from.distance_to(point) - 0.01:
				continue
			hidden += 1
			_assert_equal(game.map_grid.get_tile(terrain.cell), MapGrid.Tile.ROCK, "bed foot (%.1f, %.1f) is behind a rock" % [x, y])
			_assert_equal(view.pick_cell(screen), terrain.cell, "bed foot (%.1f, %.1f) behind the rock picks the rock" % [x, y])
	_assert_true(hidden >= 2, "at least two bed-foot points are hidden by rock (got %d)" % hidden)
	game.free()


# Blueprints are drawn at 0.5..1.0 scale; the air where the finished Lumen would be
# is not the blueprint.
func _test_blueprint_scale() -> void:
	var game := _spawn_game(1.0)
	var cell := Vector2i(25, 14)
	_focus(game, 1.0, cell)
	_park_residents(game)
	_assert_true(game.place_blueprint(VaultBuilding.Kind.LAMP, cell), "Lumen blueprint placed on (25,14)")
	game._sync_3d_play_view(true)
	var view := game.map_view_3d
	var proxy: Node3D = view._building_proxies[game.get_building_at(cell).building_id]
	_assert_true(absf(proxy.scale.x - 0.5) < 0.0001, "an undelivered blueprint is drawn at half scale")
	var cap: MeshInstance3D = proxy.get_node("GuardCap")
	var drawn_top := cap.global_transform * Vector3(0.0, 0.25, 0.0)
	_assert_equal(view.pick_cell(_screen(game, drawn_top)), cell, "the drawn half-scale cap top picks the blueprint")
	var full_top := Vector3(drawn_top.x, MapView3D.FLOOR_HEIGHT + 10.3, cap.global_position.z)
	var screen := _screen(game, full_top)
	var from := view.camera_3d.project_ray_origin(screen)
	var terrain: Dictionary = view._pick_terrain(from, view.camera_3d.project_ray_normal(screen))
	_assert_true(terrain.get("cell", cell) != cell, "the full-size cap top is over another hex's terrain")
	_assert_equal(view.pick_cell(screen), terrain.get("cell", cell), "air where a finished Lumen's cap would be picks the terrain behind")
	game.free()


# The hatch disc (CylinderMesh r 5) is alone near its back-right box corner: a ray
# through that corner, outside the drawn disc, hits no fixture or hatch.
func _test_cylinder_not_box() -> void:
	var game := _spawn_game(1.0)
	var view := game.map_view_3d
	if not view.has_method("_pick_fixture"):
		_fail("_pick_fixture", "MapView3D._pick_fixture is missing")
		_assertion_count += 1
		game.free()
		return
	_park_residents(game)
	_focus(game, 1.0, BreachSystem.HATCH_CELL)
	var disc: MeshInstance3D = view._hatch_proxy
	var corner: Vector3 = disc.global_transform * Vector3(4.6, 1.5, -4.6)
	_assert_true(disc.mesh.get_aabb().grow(0.001).has_point(disc.global_transform.affine_inverse() * corner), "the probe point is inside the disc's box")
	var screen := _screen(game, corner)
	var hit: Dictionary = view.call("_pick_fixture", view.camera_3d.project_ray_origin(screen), view.camera_3d.project_ray_normal(screen))
	_assert_true(hit.is_empty(), "a ray through the disc's box corner misses the drawn disc (got %s)" % hit)
	var rim: Vector3 = disc.global_transform * Vector3(3.2, 1.5, -3.2)
	var rim_screen := _screen(game, rim)
	var rim_hit: Dictionary = view.call("_pick_fixture", view.camera_3d.project_ray_origin(rim_screen), view.camera_3d.project_ray_normal(rim_screen))
	_assert_equal(rim_hit.get("cell", Vector2i(-1, -1)), BreachSystem.HATCH_CELL, "a ray through the disc top inside its rim hits the hatch")
	game.free()


# Pinned at #84: a capsule under the cursor wins on the hatch hex; during a breach,
# re-clicking that selected capsule moves on to the hatch, and a click on the hatch
# hex off every capsule opens the hatch. Dormant, it is an ordinary hex (Bo).
# New: the drawn hatch disc hides a standing resident's feet like any fixture.
func _test_hatch_click_order(phase: int) -> void:
	var game := _spawn_game(1.0)
	var view := game.map_view_3d
	var hatch := BreachSystem.HATCH_CELL
	var center := game.map_grid.cell_to_world(hatch)
	_park_residents(game)
	var bo: VaultResident = game.get_resident_by_id(2)
	bo.position = center
	game.breach_system.phase = phase
	_focus(game, 1.0, hatch)
	var breach := phase != BreachSystem.Phase.DORMANT
	var proxy: MeshInstance3D = view._resident_proxies[2]
	var capsule := _screen(game, proxy.global_position + Vector3(0.0, 6.5, 0.0))
	_assert_capsule_hit(game, capsule, "Bo on the hatch")
	_clear_selection(game)
	var got: Array[String] = []
	for _i: int in 3:
		_click(game, capsule)
		got.append("HATCH" if game.selected_breach else _selection_label(game))
	_assert_equal(got, ["R2", "HATCH" if breach else "R2", "R2"], "three capsule clicks on the hatch hex")
	var floor_screen := _screen(game, Vector3(center.x - 7.0, MapView3D.FLOOR_HEIGHT, center.y - 5.0))
	_assert_true(not _capsule_on_ray(game, floor_screen, bo), "the hatch-hex floor point is off Bo's capsule")
	_assert_equal(view.pick_cell(floor_screen), hatch, "the floor point is on the hatch hex")
	_clear_selection(game)
	_click(game, floor_screen)
	_assert_equal("HATCH" if game.selected_breach else _selection_label(game), "HATCH" if breach else "R2", "a hatch-hex floor click off every capsule")
	var disc := _screen(game, Vector3(center.x, 3.5, center.y + 4.5))
	_assert_true(_capsule_on_ray(game, disc, bo), "Bo's feet lie behind the hatch disc front on the ray")
	_assert_equal(view.call("pick_resident_id", disc, game.residents), -1, "the hatch disc hides Bo's feet")
	_assert_equal(view.pick_cell(disc), hatch, "the hatch disc picks the hatch hex")
	_clear_selection(game)
	_click(game, disc)
	_assert_equal("HATCH" if game.selected_breach else _selection_label(game), "HATCH" if breach else "R2", "a click on the hatch disc in front of Bo's feet")
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
