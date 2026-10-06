extends "res://tests/test_runner.gd"

# Pending food sits visibly in front of its source, and keeps its type colour across a load.

const SAVE_PATH := "user://headless_food_props.json"
const MEAL_COLOR := Color("c46a3a")
const RAW_COLOR := Color("74b76c")
const BOX_SIZE := Vector3(2.4, 1.4, 2.4)
const GROW_CELL := Vector2i(20, 12)
const KITCHEN_CELL := Vector2i(23, 12)
const CHARGE_CELL := Vector2i(26, 12)
const BARE_CELL := Vector2i(22, 17)
const SOUTH_GROW_CELL := Vector2i(20, 20)
const SOUTH_KITCHEN_CELL := Vector2i(23, 20)
const EAST_KITCHEN_CELL := Vector2i(28, 19)  # odd row of x=28: rock at (29,20) toward the camera
# Spec (food-props-edge): pending food at an occupied source sits toward the camera
# (+Z) 1.5 past that kind's scale-1 front face, capped at 9.0. A kind without
# parts only clears a resident: 2.4 + 1.5. Do not reference production consts here.
const FRONT_MARGIN := 1.5
const MAX_FRONT := 9.0
const PARTLESS_FRONT := 3.9
const FRONT_BY_KIND := {
	VaultBuilding.Kind.BED: 9.0,
	VaultBuilding.Kind.LAMP: 4.2,
	VaultBuilding.Kind.GENERATOR: 6.2,
	VaultBuilding.Kind.GROW_TRAY: 6.0,
	VaultBuilding.Kind.KITCHEN: 5.9,
	VaultBuilding.Kind.STOCKPILE: 5.5,
	VaultBuilding.Kind.AIR_RECYCLER: 6.0,
	VaultBuilding.Kind.RECREATION_CONSOLE: 5.5,
	VaultBuilding.Kind.MEDICAL_BED: 8.5,
}
# One chamber floor cell per kind for the placed-fixture pin (no two adjacent).
const KIND_CELLS := [Vector2i(18, 12), Vector2i(20, 12), Vector2i(22, 12), Vector2i(24, 12), Vector2i(26, 12), Vector2i(18, 15), Vector2i(20, 15), Vector2i(22, 15), Vector2i(26, 15)]
const POSITION_TOLERANCE := 0.001
const MIN_SOUTH_VISIBLE := 0.8


func _run() -> void:
	_run_case("Grow harvest waits in front of the Grow Tray", _test_grow_output_in_front)
	_run_case("cooked meals wait in front of the Nutrient Station", _test_kitchen_output_in_front)
	_run_case("every fixture kind puts its food 1.5 past its own front face", _test_all_fixture_fronts)
	_run_case("bare-floor and carried food keep their positions (control)", _test_floor_and_carried_control)
	_run_case("pending food follows whatever fixture occupies its source", _test_removed_producer)
	_run_case("save and load recolour reused food props", _test_load_recolours)
	_run_case("south-row and east-column food stays in sight past camera-side rock", _test_south_row_in_sight)
	print("")
	print("FOOD PROPS TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	_remove_test_save(SAVE_PATH)
	quit(1 if _failure_count else 0)


func _producer_game() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	game.user_paused = true
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, CHARGE_CELL)
	_add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, GROW_CELL)
	_add_completed_building(game, VaultBuilding.Kind.KITCHEN, KITCHEN_CELL)
	game.power_grid.recalculate(game.buildings)
	var grow := game.get_building_at(GROW_CELL)
	var kitchen := game.get_building_at(KITCHEN_CELL)
	_assert_true(is_instance_valid(grow) and is_instance_valid(kitchen) and grow.powered and kitchen.powered, "fixture: producers powered")
	return game


func _food_job(game: VaultGame, type: int, cell: Vector2i) -> Dictionary:
	for job: Dictionary in game.job_system.jobs:
		if int(job.type) == type and job.target == cell and not bool(job.done):
			return job
	return {}


func _prop(game: VaultGame, job: Dictionary) -> MeshInstance3D:
	var prop: MeshInstance3D = game.map_view_3d._food_props.get(job.get("id", -1)) as MeshInstance3D
	return prop if is_instance_valid(prop) else null


func _color(prop: MeshInstance3D) -> Color:
	if not is_instance_valid(prop):
		return Color.TRANSPARENT
	var material := prop.material_override as StandardMaterial3D
	return material.albedo_color if material != null else Color.TRANSPARENT


func _position(prop: MeshInstance3D) -> Vector3:
	return prop.position if is_instance_valid(prop) else Vector3(INF, INF, INF)


func _front(kind: int) -> float:
	return float(FRONT_BY_KIND.get(kind, INF))


func _front_position(cell: Vector2i, kind: int) -> Vector3:
	var center := MapGrid.offset_cell_to_world(cell)
	return Vector3(center.x, MapView3D.FLOOR_HEIGHT + 0.7, center.y + _front(kind))


func _assert_position(actual: Vector3, expected: Vector3, message: String) -> void:
	_assertion_count += 1
	if not (actual.distance_to(expected) <= POSITION_TOLERANCE):
		_fail(message, "expected %s, got %s" % [str(expected), str(actual)])


# The prop must sit on the floor in front of the live fixture proxy, clear of all
# its parts and of a resident standing on the cell, inside the source hex, and
# in sight of the game camera.
func _assert_in_front(game: VaultGame, prop: MeshInstance3D, building: VaultBuilding, label: String) -> void:
	_assert_true(prop != null and is_instance_valid(prop), "%s prop exists" % label)
	if not is_instance_valid(prop):
		return
	var view := game.map_view_3d
	var proxy: Node3D = view._building_proxies.get(building.building_id) if is_instance_valid(building) else null
	_assert_true(is_instance_valid(proxy), "%s fixture proxy exists" % label)
	if not is_instance_valid(proxy):
		return
	var center := MapGrid.offset_cell_to_world(building.cell)
	_assert_position(prop.position, _front_position(building.cell, building.kind), "%s sits on the floor 1.5 in front of its source" % label)
	var box := prop.mesh as BoxMesh
	_assert_equal(box.size if box != null else Vector3.ZERO, BOX_SIZE, "%s box size unchanged" % label)
	var prop_box := AABB(prop.position - BOX_SIZE * 0.5, BOX_SIZE)
	var parts: Array[AABB] = []
	for part: MeshInstance3D in proxy.get_children():
		if not is_instance_valid(part) or part.mesh == null:
			_assert_true(false, "%s fixture part has a mesh" % label)
			continue
		var bounds := part.mesh.get_aabb()
		bounds = AABB(proxy.position + (part.position + bounds.position) * proxy.scale, bounds.size * proxy.scale)
		parts.append(bounds)
		_assert_false(bounds.grow(-0.001).intersects(prop_box), "%s clears fixture part %s" % [label, part.name])
		_assert_true(prop_box.position.z > bounds.end.z, "%s is in front of fixture part %s" % [label, part.name])
	for corner: Vector2 in [Vector2(prop_box.position.x, prop_box.position.z), Vector2(prop_box.end.x, prop_box.position.z), Vector2(prop_box.position.x, prop_box.end.z), Vector2(prop_box.end.x, prop_box.end.z)]:
		_assert_equal(game.map_grid.world_to_cell(corner), building.cell, "%s footprint corner stays in the source hex" % label)
	_assert_true(prop_box.position.z - center.y > MapView3D.COLONIST_RADIUS, "%s clears a resident standing on the source cell" % label)
	for zoom: float in [0.75, 1.0, 1.8]:
		if not is_instance_valid(view.camera_3d):
			_assert_true(false, "%s game camera exists" % label)
			continue
		view.apply_camera_focus(center, zoom)
		var eye := view.camera_3d.position
		var target := prop.position + Vector3(0.0, 0.7, 0.0)
		var blocked := false
		for bounds: AABB in parts:
			if bounds.intersects_segment(eye, target):
				blocked = true
		_assert_false(blocked, "%s top is in sight of the camera at zoom %.2f" % [label, zoom])


func _test_grow_output_in_front() -> void:
	var game := _producer_game()
	var grow := game.get_building_at(GROW_CELL)
	game.food_system.advance(FoodSystem.GROW_SECONDS, game.buildings)
	var job := _food_job(game, JobSystem.JobType.HAUL_RAW_FOOD, GROW_CELL)
	_assert_false(job.is_empty(), "real harvest queues raw food at the Grow Tray cell")
	game._sync_3d_play_view()
	var prop := _prop(game, job)
	_assert_in_front(game, prop, grow, "pending raw food")
	_assert_equal(_color(prop), RAW_COLOR, "raw food stays green")
	_dispose(game)


func _test_kitchen_output_in_front() -> void:
	var game := _producer_game()
	var kitchen := game.get_building_at(KITCHEN_CELL)
	# job_system.gd cook completion calls exactly this.
	game.job_system.queue_meals(KITCHEN_CELL, FoodSystem.COOK_OUTPUT)
	var job := _food_job(game, JobSystem.JobType.HAUL_MEAL, KITCHEN_CELL)
	_assert_false(job.is_empty(), "cook output queues meals at the Nutrient Station cell")
	game._sync_3d_play_view()
	var prop := _prop(game, job)
	_assert_in_front(game, prop, kitchen, "pending meal")
	_assert_equal(_color(prop), MEAL_COLOR, "meal stays orange")
	_dispose(game)


func _test_all_fixture_fronts() -> void:
	var game := _spawn_game()
	game.begin_shift()
	game.user_paused = true
	var view := game.map_view_3d
	var kinds: Array = VaultBuilding.Kind.values()
	_assert_equal(kinds.size(), KIND_CELLS.size(), "fixture: one test cell per fixture kind")
	for i: int in kinds.size():
		var kind: int = kinds[i]
		var kind_name: String = VaultBuilding.Kind.keys()[kind]
		var assembly := view._make_building_proxy(kind)
		if not is_instance_valid(assembly):
			_assert_true(false, "%s fixture assembly exists" % kind_name)
			continue
		var front := -INF
		for part: MeshInstance3D in assembly.get_children():
			if not is_instance_valid(part) or part.mesh == null:
				front = INF
				break
			var bounds := part.mesh.get_aabb()
			front = maxf(front, part.position.z + bounds.end.z)
		assembly.free()
		# Uncapped on purpose: a fixture that grows past the 9.0 cap must fail here, not lose its gap.
		_assert_approximately(front + FRONT_MARGIN, _front(kind), POSITION_TOLERANCE, "%s food front is its front face (%.2f) + 1.5" % [kind_name, front])
		_assert_true(front < _front(kind) - BOX_SIZE.z * 0.5, "%s front face (%.2f) ends before the food box" % [kind_name, front])
		_assert_true(_front(kind) - BOX_SIZE.z * 0.5 > MapView3D.COLONIST_RADIUS and _front(kind) <= MAX_FRONT, "%s food box clears a standing resident and stays within the 9.0 cap" % kind_name)
		# Real path: a placed fixture of this kind with pending food on its cell.
		var cell: Vector2i = KIND_CELLS[i]
		_assert_true(game.map_grid.is_walkable(cell) and game.get_building_at(cell) == null, "fixture: %s test cell is empty floor" % kind_name)
		_add_completed_building(game, kind, cell)
		game.job_system.queue_raw_food(cell, 1)
	game._sync_3d_play_view()
	for i: int in kinds.size():
		var kind: int = kinds[i]
		var cell: Vector2i = KIND_CELLS[i]
		var job := _food_job(game, JobSystem.JobType.HAUL_RAW_FOOD, cell)
		_assert_position(_position(_prop(game, job)), _front_position(cell, kind), "%s source puts its pending food 1.5 past its front face" % VaultBuilding.Kind.keys()[kind])
	if view.has_method("_food_source_front_offset"):
		var partless := float(view.call("_food_source_front_offset", kinds.size()))
		_assert_true(is_finite(partless) and absf(partless - PARTLESS_FRONT) <= POSITION_TOLERANCE, "a kind without fixture parts only clears a resident (expected %.2f, got %s)" % [PARTLESS_FRONT, str(partless)])
	else:
		_assert_true(false, "map view measures the food front per fixture kind (_food_source_front_offset missing)")
	_dispose(game)


func _test_floor_and_carried_control() -> void:
	var game := _producer_game()
	_assert_true(game.get_building_at(BARE_CELL) == null, "fixture: bare floor cell has no fixture")
	game.job_system.queue_raw_food(BARE_CELL, 1)
	game.food_system.advance(FoodSystem.GROW_SECONDS, game.buildings)
	game._sync_3d_play_view()
	var bare := _food_job(game, JobSystem.JobType.HAUL_RAW_FOOD, BARE_CELL)
	var center := MapGrid.offset_cell_to_world(BARE_CELL)
	_assert_equal(_position(_prop(game, bare)), Vector3(center.x, 0.7, center.y), "bare-floor food keeps y 0.7")
	var grow_job := _food_job(game, JobSystem.JobType.HAUL_RAW_FOOD, GROW_CELL)
	var carrier: VaultResident = game.residents[0] if not game.residents.is_empty() else null
	if not is_instance_valid(carrier):
		_assert_true(false, "fixture: carrier exists")
		_dispose(game)
		return
	carrier.current_job_id = int(grow_job.get("id", -1))
	carrier.current_job_type = int(grow_job.get("type", -1))
	carrier.carrying_kind = "raw_food"
	carrier.job_phase = "deposit"
	carrier.carrying = 2
	game._sync_3d_play_view()
	_assert_equal(_position(_prop(game, grow_job)), Vector3(carrier.position.x + 4.6, 0.7, carrier.position.y), "carried food stays beside the pill")
	_dispose(game)


func _test_removed_producer() -> void:
	var game := _producer_game()
	var grow := game.get_building_at(GROW_CELL)
	game.food_system.advance(FoodSystem.GROW_SECONDS, game.buildings)
	game._sync_3d_play_view()
	_assert_true(is_instance_valid(grow) and game.deconstruct_building(grow.building_id), "Grow Tray deconstructed")
	var job := _food_job(game, JobSystem.JobType.HAUL_RAW_FOOD, GROW_CELL)
	_assert_false(job.is_empty(), "pending raw food outlives its producer")
	game._sync_3d_play_view()
	var center := MapGrid.offset_cell_to_world(GROW_CELL)
	_assert_equal(_position(_prop(game, job)), Vector3(center.x, 0.7, center.y), "orphaned food returns to the bare-floor centre")
	_assert_true(game.place_blueprint(VaultBuilding.Kind.LAMP, GROW_CELL), "a Lumen blueprint is placed on the source cell")
	game._sync_3d_play_view()
	_assert_position(_position(_prop(game, job)), _front_position(GROW_CELL, VaultBuilding.Kind.LAMP), "an unfinished fixture on the source also moves the food in front (Lumen front)")
	_dispose(game)


func _test_load_recolours() -> void:
	_remove_test_save(SAVE_PATH)
	var game := _producer_game()
	game.job_system.queue_meals(KITCHEN_CELL, FoodSystem.COOK_OUTPUT)
	game.food_system.advance(FoodSystem.GROW_SECONDS, game.buildings)
	game._sync_3d_play_view()
	var meal := _food_job(game, JobSystem.JobType.HAUL_MEAL, KITCHEN_CELL)
	var raw := _food_job(game, JobSystem.JobType.HAUL_RAW_FOOD, GROW_CELL)
	var meal_id := int(meal.get("id", -1))
	var raw_id := int(raw.get("id", -1))
	_assert_true(not meal.is_empty() and not raw.is_empty() and meal_id < raw_id, "fixture: meal queued before raw food")
	var meal_node := _prop(game, meal)
	_assert_true(game.save_game(false, SAVE_PATH), "save succeeds")
	_assert_true(game.load_game(SAVE_PATH), "load succeeds")
	game._sync_3d_play_view()
	var loaded_meal := _food_job(game, JobSystem.JobType.HAUL_MEAL, KITCHEN_CELL)
	var loaded_raw := _food_job(game, JobSystem.JobType.HAUL_RAW_FOOD, GROW_CELL)
	_assert_equal(int(loaded_raw.get("id", -2)), meal_id, "fixture: load rebuilds raw food first, taking the meal's old id")
	_assert_equal(int(loaded_meal.get("id", -2)), raw_id, "fixture: the meal takes the raw food's old id")
	_assert_true(is_instance_valid(meal_node) and _prop(game, loaded_raw) == meal_node, "the cached box is reused for the new owner of its id")
	_assert_equal(_color(_prop(game, loaded_raw)), RAW_COLOR, "reloaded raw food is green")
	_assert_equal(_color(_prop(game, loaded_meal)), MEAL_COLOR, "reloaded meal is orange")
	_assert_in_front(game, _prop(game, loaded_raw), game.get_building_at(GROW_CELL), "reloaded raw food")
	_assert_in_front(game, _prop(game, loaded_meal), game.get_building_at(KITCHEN_CELL), "reloaded meal")
	_assert_equal(game.map_view_3d._food_props.size(), 2, "one box per pending food job after load")
	_remove_test_save(SAVE_PATH)
	_dispose(game)


func _test_south_row_in_sight() -> void:
	var game := _spawn_game()
	game.begin_shift()
	game.user_paused = true
	_add_completed_building(game, VaultBuilding.Kind.GENERATOR, CHARGE_CELL)
	var grow := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, SOUTH_GROW_CELL)
	var kitchen := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, SOUTH_KITCHEN_CELL)
	var east := _add_completed_building(game, VaultBuilding.Kind.KITCHEN, EAST_KITCHEN_CELL)
	game.power_grid.recalculate(game.buildings)
	_assert_true(grow.powered and kitchen.powered, "fixture: south-row producers powered")
	game.food_system.advance(FoodSystem.GROW_SECONDS, game.buildings)
	game.job_system.queue_meals(SOUTH_KITCHEN_CELL, FoodSystem.COOK_OUTPUT)
	game.job_system.queue_meals(EAST_KITCHEN_CELL, FoodSystem.COOK_OUTPUT)
	game._sync_3d_play_view()
	var sources := [
		[grow, JobSystem.JobType.HAUL_RAW_FOOD, SOUTH_GROW_CELL + Vector2i(0, 1), RAW_COLOR, "south-row raw food"],
		[kitchen, JobSystem.JobType.HAUL_MEAL, SOUTH_KITCHEN_CELL + Vector2i(0, 1), MEAL_COLOR, "south-row meal"],
		[east, JobSystem.JobType.HAUL_MEAL, EAST_KITCHEN_CELL + Vector2i(1, 1), MEAL_COLOR, "east-column meal"],
	]
	for entry: Array in sources:
		var source: VaultBuilding = entry[0]
		var label: String = entry[4]
		var job := _food_job(game, int(entry[1]), source.cell)
		_assert_false(job.is_empty(), "%s is queued at its source" % label)
		_assert_equal(game.map_grid.get_tile(entry[2]), MapGrid.Tile.ROCK, "fixture: rock lies toward the camera from %s" % label)
		var prop := _prop(game, job)
		_assert_in_front(game, prop, source, label)
		_assert_equal(_color(prop), entry[3], "%s keeps its colour" % label)
		_assert_rock_sight(game, prop, source.cell, label)
	_dispose(game)


# Camera-side rock and walls (6.0 tall) must not hide the box: its top centre is in
# sight at every zoom, and at the worst zoom most of its top/front/+X faces are.
func _assert_rock_sight(game: VaultGame, prop: MeshInstance3D, cell: Vector2i, label: String) -> void:
	var view := game.map_view_3d
	var center := MapGrid.offset_cell_to_world(cell)
	var position := _position(prop)
	var worst := 1.0
	for zoom: float in [0.75, 1.0, 1.8]:
		view.apply_camera_focus(center, zoom)
		var eye := view.camera_3d.position
		_assert_true(is_instance_valid(prop) and _clear_of_rock(game.map_grid, position + Vector3(0.0, BOX_SIZE.y * 0.5, 0.0), eye), "%s top is not hidden by camera-side rock at zoom %.2f" % [label, zoom])
		var seen := 0
		var samples := 0
		var h := BOX_SIZE * 0.5
		for i: int in 5:
			for j: int in 5:
				var u := -1.0 + 0.5 * i
				var v := -1.0 + 0.5 * j
				for p: Vector3 in [position + Vector3(u * h.x, h.y, v * h.z), position + Vector3(u * h.x, v * h.y, h.z), position + Vector3(h.x, v * h.y, u * h.z)]:
					samples += 1
					if is_instance_valid(prop) and _clear_of_rock(game.map_grid, p, eye):
						seen += 1
		worst = minf(worst, float(seen) / float(samples))
	_assert_true(worst >= MIN_SOUTH_VISIBLE, "%s is mostly in sight past camera-side rock (worst zoom %.2f >= %.2f)" % [label, worst, MIN_SOUTH_VISIBLE])


func _clear_of_rock(grid: MapGrid, point: Vector3, eye: Vector3) -> bool:
	var d := eye - point
	var steps := int(d.length() / 0.1)
	for i: int in range(1, steps):
		var q := point + d * (float(i) / float(steps))
		if q.y >= MapView3D.ROCK_HEIGHT:
			return true
		if grid.get_tile(grid.world_to_cell(Vector2(q.x, q.z))) == MapGrid.Tile.ROCK:
			return false
	return true
