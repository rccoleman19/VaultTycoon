extends "res://tests/test_runner.gd"


func _run() -> void:
	_test_fixture_palettes()
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
	var lamp := _add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(18, 12))
	view.sync_actors([], game.buildings, false)
	var assembly: Node3D = view._building_proxies[lamp.building_id]
	var parts := assembly.get_children()
	var child_count := view.fixture_root.get_child_count()
	game.buildings.erase(lamp)
	view.sync_actors([], game.buildings, false)
	_assert_false(view._building_proxies.has(lamp.building_id), "teardown erases assembly id")
	_assert_equal(view.fixture_root.get_child_count(), child_count - 1, "teardown removes whole assembly from FixtureRoot")
	_assert_true(assembly.is_queued_for_deletion(), "teardown queues assembly for deletion")
	await process_frame
	_assert_false(is_instance_valid(assembly), "assembly is freed")
	for part: Node in parts:
		_assert_false(is_instance_valid(part), "all assembly parts are freed")
	_dispose(game)
