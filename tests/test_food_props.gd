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
const FRONT := 9.0  # spec: pending food at an occupied source sits 9.0 toward the camera (+Z)


func _run() -> void:
	_run_case("Grow harvest waits in front of the Grow Tray", _test_grow_output_in_front)
	_run_case("cooked meals wait in front of the Nutrient Station", _test_kitchen_output_in_front)
	_run_case("every fixture kind ends before the food front offset", _test_all_fixture_fronts)
	_run_case("bare-floor and carried food keep their positions (control)", _test_floor_and_carried_control)
	_run_case("pending food follows whatever fixture occupies its source", _test_removed_producer)
	_run_case("save and load recolour reused food props", _test_load_recolours)
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
	_assert_equal(prop.position, Vector3(center.x, MapView3D.FLOOR_HEIGHT + 0.7, center.y + FRONT), "%s sits on the floor in front of its source" % label)
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
	var view := game.map_view_3d
	for kind: int in VaultBuilding.Kind.values():
		var assembly := view._make_building_proxy(kind)
		if not is_instance_valid(assembly):
			_assert_true(false, "%s fixture assembly exists" % VaultBuilding.Kind.keys()[kind])
			continue
		var front := -INF
		for part: MeshInstance3D in assembly.get_children():
			if not is_instance_valid(part) or part.mesh == null:
				front = INF
				break
			var bounds := part.mesh.get_aabb()
			front = maxf(front, part.position.z + bounds.end.z)
		assembly.free()
		_assert_true(front < FRONT - BOX_SIZE.z * 0.5, "%s front face (%.2f) ends before the food box" % [VaultBuilding.Kind.keys()[kind], front])
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
	_assert_equal(_position(_prop(game, job)), Vector3(center.x, MapView3D.FLOOR_HEIGHT + 0.7, center.y + FRONT), "an unfinished fixture on the source also moves the food in front")
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
