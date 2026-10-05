extends "res://tests/test_runner.gd"


func _run() -> void:
	_test_fixture_palettes()
	_test_remaining_fixture_palettes()
	_test_medical_capsule_pose()
	_test_sleeping_capsule_pose()
	await _test_build_ghost()
	await _test_build_ghost_validity()
	await _test_assembly_cleanup()
	print("Fixture props tests: %d assertions, %d failures" % [_assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _test_fixture_palettes() -> void:
	var game := _spawn_game()
	var view := game.get_node("MapView3D") as MapView3D
	var unfinished := _add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(18, 12))
	var active := _add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(19, 12))
	unfinished.complete = false
	unfinished.delivered = 0
	unfinished.construction_left = unfinished.get_build_time()
	unfinished.powered = false
	active.powered = true
	view.sync_actors([], game.buildings, false)
	var unfinished_root: Node3D = view._building_proxies[unfinished.building_id]
	var active_root: Node3D = view._building_proxies[active.building_id]
	for part: MeshInstance3D in active_root.get_children():
		var other := unfinished_root.get_node(NodePath(part.name)) as MeshInstance3D
		_assert_true(part.material_override != other.material_override, "same-kind fixtures own independent part materials")
	_assert_palette(unfinished_root, false, false, "unfinished Lumen")
	_assert_palette(active_root, true, true, "powered Lumen")
	for iteration in 5:
		view.sync_actors([], game.buildings, false)
	_assert_palette(unfinished_root, false, false, "repeated unfinished sync")
	_assert_palette(active_root, true, true, "neighbor stays powered")

	unfinished.complete = true
	view.sync_actors([], game.buildings, false)
	_assert_palette(unfinished_root, true, false, "completed unpowered Lumen")
	for iteration in 5:
		view.sync_actors([], game.buildings, false)
	_assert_palette(unfinished_root, true, false, "unpowered tint does not accumulate")
	unfinished.powered = true
	view.sync_actors([], game.buildings, false)
	_assert_palette(unfinished_root, true, true, "completion and power restore original palette")
	active.manually_disabled = true
	view.sync_actors([], game.buildings, false)
	_assert_palette(active_root, true, false, "manual disable overrides a stale powered flag")
	_assert_palette(unfinished_root, true, true, "manual disable stays independent")
	active.manually_disabled = false
	view.sync_actors([], game.buildings, false)
	_assert_palette(active_root, true, true, "enable restores emitter")

	for kind: int in [VaultBuilding.Kind.BED, VaultBuilding.Kind.KITCHEN, VaultBuilding.Kind.GENERATOR]:
		var building := _add_completed_building(game, kind, Vector2i(20, 12))
		building.powered = false
		view.sync_actors([], game.buildings, false)
		var assembly: Node3D = view._building_proxies[building.building_id]
		_assert_true(assembly.get_child_count() >= 4 and assembly.get_child_count() <= 8, "new design uses four to eight primitive parts")
		_assert_palette(assembly, true, building.get_power_demand() == 0, "completed fixture palette")
		building.powered = true
		view.sync_actors([], game.buildings, false)
		_assert_palette(assembly, true, true, "powered fixture restores palette")
		if kind == VaultBuilding.Kind.BED:
			var mattress := assembly.get_node("Mattress") as MeshInstance3D
			_assert_approximately(mattress.position.y + (mattress.mesh as BoxMesh).size.y / 2.0, MapView3D.BUNK_MATTRESS_TOP, 0.0001, "mattress top matches sleep contact constant")
	_dispose(game)


func _test_remaining_fixture_palettes() -> void:
	var game := _spawn_game()
	var view := game.get_node("MapView3D") as MapView3D
	for kind: int in [VaultBuilding.Kind.STOCKPILE, VaultBuilding.Kind.GROW_TRAY, VaultBuilding.Kind.AIR_RECYCLER, VaultBuilding.Kind.RECREATION_CONSOLE, VaultBuilding.Kind.MEDICAL_BED]:
		var unfinished := _add_completed_building(game, kind, Vector2i(18, 12))
		var neighbor := _add_completed_building(game, kind, Vector2i(19, 12))
		unfinished.complete = false
		unfinished.delivered = 0
		unfinished.construction_left = unfinished.get_build_time()
		unfinished.powered = false
		neighbor.powered = true
		view.sync_actors([], game.buildings, false)
		var assembly: Node3D = view._building_proxies[unfinished.building_id]
		var other: Node3D = view._building_proxies[neighbor.building_id]
		var label := "kind %d" % kind
		_assert_true(assembly.get_child_count() >= 4 and assembly.get_child_count() <= 8, "%s uses four to eight primitive parts" % label)
		_assert_false(assembly.has_node("Legacy"), "%s replaces legacy mesh" % label)
		for part: MeshInstance3D in assembly.get_children():
			var other_part := other.get_node(NodePath(part.name)) as MeshInstance3D
			_assert_true(part.material_override != other_part.material_override, "%s owns independent materials" % label)
			_assert_false(bool(part.get_meta("powered_emitter")), "%s has no emitters" % label)
		_assert_palette(assembly, false, false, "%s unfinished" % label)
		_assert_palette(other, true, true, "%s powered neighbor" % label)
		for iteration in 5:
			view.sync_actors([], game.buildings, false)
		_assert_palette(assembly, false, false, "%s repeated unfinished sync" % label)
		unfinished.complete = true
		var consumer := unfinished.is_power_consumer()
		view.sync_actors([], game.buildings, false)
		_assert_palette(assembly, true, not consumer, "%s completed without power" % label)
		for iteration in 5:
			view.sync_actors([], game.buildings, false)
		_assert_palette(assembly, true, not consumer, "%s repeated unpowered sync" % label)
		_assert_palette(other, true, true, "%s neighbor remains original" % label)
		unfinished.powered = true
		view.sync_actors([], game.buildings, false)
		_assert_palette(assembly, true, true, "%s completion and power restore palette" % label)
		if consumer:
			neighbor.manually_disabled = true
			view.sync_actors([], game.buildings, false)
			_assert_palette(other, true, false, "%s manual disable overrides stale powered flag" % label)
			_assert_palette(assembly, true, true, "%s manual disable stays independent" % label)
			neighbor.manually_disabled = false
			view.sync_actors([], game.buildings, false)
			_assert_palette(other, true, true, "%s enable restores palette" % label)
		_assert_remaining_design(assembly, kind)
	_dispose(game)


func _assert_remaining_design(assembly: Node3D, kind: int) -> void:
	match kind:
		VaultBuilding.Kind.STOCKPILE:
			var shelf := assembly.get_node("MiddleShelf") as MeshInstance3D
			var lower := assembly.get_node("CrateLower") as MeshInstance3D
			var upper := assembly.get_node("CrateUpper") as MeshInstance3D
			_assert_true(lower.position.y + (lower.mesh as BoxMesh).size.y / 2.0 < shelf.position.y - (shelf.mesh as BoxMesh).size.y / 2.0, "rack has visible gap above lower cargo")
			_assert_true(upper.position.y + (upper.mesh as BoxMesh).size.y / 2.0 < 9.3, "rack has visible gap above upper cargo")
		VaultBuilding.Kind.GROW_TRAY:
			_assert_true(assembly.has_node("Soil") and assembly.has_node("EndReservoir"), "grow trough has inset soil and end reservoir")
		VaultBuilding.Kind.AIR_RECYCLER:
			var vessels := 0
			for part: MeshInstance3D in assembly.get_children():
				if part.mesh is CylinderMesh:
					vessels += 1
			_assert_equal(vessels, 1, "air recycler has one vessel, distinct from paired Charge drums")
			_assert_true(assembly.get_node("Filter").position.x < 0 and assembly.get_node("Blower").position.x > 0, "air recycler has asymmetric filter and blower")
		VaultBuilding.Kind.RECREATION_CONSOLE:
			var screen := assembly.get_node("ScreenFace") as MeshInstance3D
			var housing := assembly.get_node("ScreenHousing") as MeshInstance3D
			_assert_true(screen.position.z > housing.position.z + (housing.mesh as BoxMesh).size.z / 2.0, "console screen faces +Z")
			_assert_approximately((screen.material_override as StandardMaterial3D).emission_energy_multiplier, 0.0, 0.0001, "console screen is non-emissive")
		VaultBuilding.Kind.MEDICAL_BED:
			_assert_true(assembly.has_node("RailLeft") and assembly.has_node("RailRight") and assembly.has_node("HeadEquipment"), "clinical couch has rails and head equipment")
			_assert_false(assembly.has_node("Headboard"), "clinical couch does not copy Bunk headboard")
			var mattress := assembly.get_node("Mattress") as MeshInstance3D
			_assert_approximately(MapView3D.MEDICAL_MATTRESS_TOP, 4.40, 0.0001, "medical mattress contact constant is 4.40")
			_assert_approximately(mattress.position.y + (mattress.mesh as BoxMesh).size.y / 2.0, MapView3D.MEDICAL_MATTRESS_TOP, 0.0001, "medical mattress geometry matches contact constant")


func _test_medical_capsule_pose() -> void:
	var game := _spawn_game()
	var view := game.get_node("MapView3D") as MapView3D
	var resident: VaultResident = game.residents[0]
	var bed := _add_completed_building(game, VaultBuilding.Kind.MEDICAL_BED, Vector2i(23, 15))
	var bed_center := MapGrid.offset_cell_to_world(bed.cell)
	resident.medical_bed_id = bed.building_id
	resident.bed_id = -1
	resident.sleeping = false
	resident.state = "Rest-Medical"
	resident.position = bed_center + Vector2(0.5, 0)
	view.sync_actors(game.residents, game.buildings, false)
	var original_proxy := view._resident_proxies.get(resident.resident_id) as MeshInstance3D
	_assert_true(original_proxy != null, "medical resident has a capsule proxy")
	if original_proxy == null:
		_dispose(game)
		return
	var original_mesh := original_proxy.mesh as CapsuleMesh
	var assert_pose := func(lying: bool, label: String) -> void:
		view.sync_actors(game.residents, game.buildings, false)
		var proxy := view._resident_proxies.get(resident.resident_id) as MeshInstance3D
		var expected_xz := bed_center if lying else resident.position
		var expected_y := 7.35 if lying else MapView3D.COLONIST_HEIGHT * 0.5
		_assert_true(proxy == original_proxy, "%s retains the same proxy" % label)
		_assert_true(proxy.position.is_equal_approx(Vector3(expected_xz.x, expected_y, expected_xz.y)), "%s center position" % label)
		_assert_true(proxy.rotation.is_equal_approx(Vector3(PI / 2, 0, 0) if lying else Vector3.ZERO), "%s rotation" % label)
		_assert_equal(proxy.scale, Vector3.ONE, "%s capsule scale" % label)
		_assert_true(proxy.mesh == original_mesh, "%s retains capsule mesh" % label)
		_assert_approximately(original_mesh.radius, 2.4, 0.0001, "%s capsule radius" % label)
		_assert_approximately(original_mesh.height, 13.0, 0.0001, "%s capsule height" % label)
	_assert_false(resident.sleeping, "medical rest does not require sleeping")
	assert_pose.call(true, "medical rest with sleeping false and bed_id cleared")

	resident.state = "Seeking Medical Bed"
	assert_pose.call(false, "seeking medical bed stays upright")
	resident.state = "Rest-Medical"
	resident.position = bed_center + Vector2(1.0, 0)
	assert_pose.call(true, "medical rest at distance gate boundary")
	resident.position = bed_center + Vector2(1.01, 0)
	assert_pose.call(false, "medical rest beyond distance gate")
	resident.position = bed_center
	assert_pose.call(true, "medical rest at bed center")

	bed.complete = false
	assert_pose.call(false, "incomplete medical bed")
	bed.complete = true
	assert_pose.call(true, "completed medical bed restored")
	bed.kind = VaultBuilding.Kind.BED
	assert_pose.call(false, "bunk id cannot supply medical pose")
	bed.kind = VaultBuilding.Kind.MEDICAL_BED
	resident.medical_bed_id = game.next_building_id + 100
	assert_pose.call(false, "missing medical building id")
	resident.medical_bed_id = bed.building_id
	assert_pose.call(true, "matching medical building restored")

	resident.alive = false
	assert_pose.call(false, "dead resident has no medical rest pose")
	_assert_true(original_proxy.material_override == view._mat_colonist_dead, "dead resident retains existing dead material")
	resident.alive = true
	assert_pose.call(true, "living medical resident restored")
	resident.medical_bed_id = -1
	assert_pose.call(false, "clearing medical assignment releases pose")
	resident.medical_bed_id = bed.building_id
	assert_pose.call(true, "medical assignment restored")
	resident.state = "Idle"
	assert_pose.call(false, "leaving Rest-Medical releases pose")
	_dispose(game)


func _assert_palette(assembly: Node3D, complete: bool, active: bool, label: String) -> void:
	_assert_approximately(assembly.position.y, MapView3D.FLOOR_HEIGHT, 0.0001, "%s root stays on floor" % label)
	for part: MeshInstance3D in assembly.get_children():
		var mat := part.material_override as StandardMaterial3D
		var expected: Color = part.get_meta("original_albedo")
		if not complete:
			expected.a = 0.55
		elif not active:
			expected = expected.darkened(0.35)
		_assert_true(mat.albedo_color.is_equal_approx(expected), "%s / %s derives original palette" % [label, part.name])
		_assert_equal(mat.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED if complete else BaseMaterial3D.TRANSPARENCY_ALPHA, "%s transparency" % label)
		var emitter := bool(part.get_meta("powered_emitter"))
		_assert_equal(mat.emission_enabled, emitter and complete and active, "%s / %s emitter state" % [label, part.name])
		if mat.emission_enabled:
			_assert_true(mat.emission.is_equal_approx(part.get_meta("original_emission")), "%s restores emission color" % label)
			_assert_approximately(mat.emission_energy_multiplier, 0.25, 0.0001, "%s has slight emission" % label)


func _test_assembly_cleanup() -> void:
	var game := _spawn_game()
	var view := game.get_node("MapView3D") as MapView3D
	for kind: int in [VaultBuilding.Kind.LAMP, VaultBuilding.Kind.STOCKPILE, VaultBuilding.Kind.GROW_TRAY, VaultBuilding.Kind.AIR_RECYCLER, VaultBuilding.Kind.RECREATION_CONSOLE, VaultBuilding.Kind.MEDICAL_BED]:
		var building := _add_completed_building(game, kind, Vector2i(18, 12))
		view.sync_actors([], game.buildings, false)
		var assembly: Node3D = view._building_proxies[building.building_id]
		var parts := assembly.get_children()
		var child_count := view.fixture_root.get_child_count()
		game.buildings.erase(building)
		view.sync_actors([], game.buildings, false)
		_assert_false(view._building_proxies.has(building.building_id), "teardown erases assembly id")
		_assert_equal(view.fixture_root.get_child_count(), child_count - 1, "teardown removes whole assembly from FixtureRoot")
		_assert_true(assembly.is_queued_for_deletion(), "teardown queues assembly for deletion")
		await process_frame
		_assert_false(is_instance_valid(assembly), "assembly is freed")
		for part: Node in parts:
			_assert_false(is_instance_valid(part), "all assembly parts are freed")
	_dispose(game)


func _test_build_ghost() -> void:
	var game := _spawn_game()
	var view := game.get_node("MapView3D") as MapView3D
	var grid := game.map_grid
	var ghost_root := view.get_node("BuildGhostRoot") as Node3D
	var snapshot := game.create_snapshot()
	var proxies := view._building_proxies.duplicate()
	var fixture_count := view.fixture_root.get_child_count()
	var previous: Node3D
	var expected_kinds := {
		"bed": VaultBuilding.Kind.BED, "lamp": VaultBuilding.Kind.LAMP,
		"generator": VaultBuilding.Kind.GENERATOR, "grow": VaultBuilding.Kind.GROW_TRAY,
		"kitchen": VaultBuilding.Kind.KITCHEN, "stockpile": VaultBuilding.Kind.STOCKPILE,
		"air": VaultBuilding.Kind.AIR_RECYCLER, "rec": VaultBuilding.Kind.RECREATION_CONSOLE,
		"medical": VaultBuilding.Kind.MEDICAL_BED,
	}
	for tool: String in expected_kinds:
		grid.preview_tool = tool
		grid.hover_cell = Vector2i(18, 12)
		view.rebuild_map()
		if previous != null:
			_assert_false(is_instance_valid(previous), "kind change frees the previous ghost")
		_assert_equal(ghost_root.get_child_count(), 1, "%s retains one assembly" % tool)
		var ghost := ghost_root.get_child(0) as Node3D
		_assert_true(ghost.visible, "%s ghost is visible on empty floor" % tool)
		var reference := view._make_building_proxy(expected_kinds[tool])
		_assert_equal(ghost.get_child_count(), reference.get_child_count(), "%s matches kind part count" % tool)
		for i in reference.get_child_count():
			var part := ghost.get_child(i) as MeshInstance3D
			var expected_part := reference.get_child(i) as MeshInstance3D
			_assert_equal(part.mesh.get_class(), expected_part.mesh.get_class(), "%s matches part mesh type" % tool)
			_assert_equal(part.mesh.get_aabb(), expected_part.mesh.get_aabb(), "%s matches part geometry" % tool)
			_assert_equal(part.position, expected_part.position, "%s matches part position" % tool)
			var mat := part.material_override as StandardMaterial3D
			var color: Color = expected_part.get_meta("original_albedo")
			color.a = 0.55
			_assert_true(mat.albedo_color.is_equal_approx(color), "%s uses translucent original palette" % tool)
			_assert_equal(mat.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "%s uses alpha transparency" % tool)
			_assert_false(mat.emission_enabled, "%s ghost has no emission" % tool)
			_assert_equal(mat.emission, Color.BLACK, "%s clears emission color" % tool)
			_assert_approximately(mat.emission_energy_multiplier, 0.0, 0.0001, "%s clears emission energy" % tool)
			_assert_true(mat != expected_part.material_override, "%s owns ghost material" % tool)
		reference.free()
		_assert_equal(ghost.scale, Vector3.ONE, "%s ghost uses completed scale" % tool)
		_assert_equal(ghost.rotation, Vector3.ZERO, "%s ghost uses completed orientation" % tool)
		grid.hover_cell = Vector2i(19, 12)
		# Exercise the signature early-return: ghost sync must still move it.
		view._last_map_signature = view._map_signature()
		var terrain := view.hex_root.get_children()
		view.rebuild_map()
		_assert_true(ghost_root.get_child(0) == ghost, "%s cell move reuses assembly" % tool)
		_assert_equal(view.hex_root.get_children(), terrain, "ghost sync runs before terrain early-return")
		var center := grid.cell_to_world(grid.hover_cell)
		_assert_equal(ghost.position, Vector3(center.x, MapView3D.FLOOR_HEIGHT, center.y), "%s ghost follows floor center" % tool)
		previous = ghost
		await process_frame
	_assert_equal(game.create_snapshot(), snapshot, "hover sync leaves simulation snapshot and building ID unchanged")
	_assert_equal(view._building_proxies, proxies, "ghost never registers a live fixture proxy")
	_assert_equal(view.fixture_root.get_child_count(), fixture_count, "ghost leaves FixtureRoot untouched")
	_dispose(game)
	_assert_false(is_instance_valid(previous), "view teardown frees ghost independently")


func _test_build_ghost_validity() -> void:
	var game := _spawn_game()
	var view := game.get_node("MapView3D") as MapView3D
	var grid := game.map_grid
	var cell := Vector2i(18, 12)
	grid.preview_tool = "lamp"
	grid.hover_cell = cell
	view.rebuild_map()
	await process_frame
	var ghost_root := view.get_node("BuildGhostRoot") as Node3D
	var ghost := ghost_root.get_child(0) as Node3D
	_assert_hover_material(view, cell, view._mat_hover_ok, "empty build cell is green")
	var neighbor := Vector2i(19, 12)
	var footprint := view._make_hex_instance(neighbor)
	_assert_true(footprint.material_override == view._mat_hover_ok, "valid Lumen preview retains range footprint")
	footprint.free()
	var valid_signature := view._map_signature()
	_assert_true(game.place_blueprint(VaultBuilding.Kind.BED, cell), "place stationary-hover blueprint")
	var building := game.get_building_at(cell)
	_assert_true(grid.is_preview_valid("lamp", cell), "grid placement preview remains unchanged on occupied floor")
	_assert_true(view._map_signature() != valid_signature, "occupancy changes signature without hover movement")
	view.rebuild_map()
	await process_frame
	_assert_false(ghost.visible, "occupied blueprint hides ghost")
	_assert_hover_material(view, cell, view._mat_hover_bad, "occupied hover turns red")
	footprint = view._make_hex_instance(neighbor)
	_assert_true(footprint.material_override != view._mat_hover_ok, "occupied Lumen preview removes range footprint")
	footprint.free()
	building.complete = true
	view.sync_actors([], game.buildings, false)
	var live_proxy: Node3D = view._building_proxies[game.buildings[0].building_id]
	view.rebuild_map()
	_assert_false(ghost.visible, "completed occupied fixture hides ghost")
	for invalid_cell: Vector2i in [Vector2i(1, 1), BreachSystem.HATCH_CELL, Vector2i(-1, -1), Vector2i(MapGrid.WIDTH, MapGrid.HEIGHT)]:
		grid.hover_cell = invalid_cell
		view.rebuild_map()
		_assert_false(ghost.visible, "rock, hatch and OOB hide retained ghost")
		_assert_equal(ghost_root.get_child_count(), 1, "invalid hover retains one assembly")
		await process_frame
	grid.hover_cell = cell
	for tool: String in ["select", "dig", "cancel", "zone"]:
		grid.preview_tool = tool
		view.rebuild_map()
		_assert_false(ghost.visible, "%s has no fixture ghost" % tool)
		_assert_equal(view._is_view_preview_valid(tool, cell), grid.is_preview_valid(tool, cell), "%s keeps grid tint validity" % tool)
		await process_frame
	grid.preview_tool = "lamp"
	view.rebuild_map()
	await process_frame
	var occupied_signature := view._map_signature()
	game.buildings.erase(building)
	_assert_true(view._map_signature() != occupied_signature, "removal changes signature with stationary hover and tool")
	var removed_snapshot := game.create_snapshot()
	view.rebuild_map()
	await process_frame
	_assert_equal(view._map_signature(), valid_signature, "removal restores signature without moving hover")
	_assert_true(ghost_root.get_child(0) == ghost and ghost.visible, "removal reveals retained same-kind ghost")
	_assert_hover_material(view, cell, view._mat_hover_ok, "removal restores green hover")
	var proxies := view._building_proxies.duplicate()
	grid.preview_tool = "medical"
	view.rebuild_map()
	_assert_false(is_instance_valid(ghost), "valid kind change frees hidden retained assembly")
	_assert_equal(view._building_proxies, proxies, "ghost replacement leaves live proxy registry untouched")
	_assert_true(is_instance_valid(live_proxy) and live_proxy.get_parent() == view.fixture_root, "ghost teardown leaves live fixture attached")
	_assert_equal(game.create_snapshot(), removed_snapshot, "ghost visibility and replacement leave simulation untouched")
	building.free()
	_dispose(game)


func _assert_hover_material(view: MapView3D, cell: Vector2i, expected: StandardMaterial3D, label: String) -> void:
	var center := view.map_grid.cell_to_world(cell)
	for child in view.hex_root.get_children():
		if child is MeshInstance3D and is_equal_approx(child.position.x, center.x) and is_equal_approx(child.position.z, center.y):
			_assert_true(child.material_override == expected, label)
			return
	_assert_true(false, "%s: hover prism missing" % label)
