extends "res://tests/test_runner.gd"

# Equal-count lighting reallocations must repaint the 3D floor without a forced rebuild.

const LUMEN_A := Vector2i(22, 14)  # starting Lumen
const LUMEN_B := Vector2i(17, 12)
const LUMEN_C := Vector2i(23, 19)
const REC_CELL := Vector2i(20, 17)  # plain floor, not a Lumen


func _run() -> void:
	_run_case("equal-count reallocation repaints plain floor on a normal sync", _test_plain_swap)
	_run_case("Light Map overlay repaints amber after an equal-count swap back", _test_overlay_swap_back)
	_run_case("unchanged lighting keeps the same terrain across syncs and ticks", _test_no_extra_rebuilds)
	_run_case("coverage revision is monotonic across refresh, force and new game", _test_revision_monotonic)
	_run_case("count-changing reallocation still repaints (control)", _test_count_change_control)
	_run_case("loading a swapped save repaints on a normal frame (control)", _test_load_control)
	_run_case("toggling a powered non-lamp consumer keeps revision, signature and terrain", _test_non_lamp_toggle)
	print("")
	print("LIT SIGNATURE TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	quit(1 if _failure_count else 0)


func _swap_game() -> Array:
	var game := _spawn_game()
	game.begin_shift()
	game.user_paused = true
	game.set_tool("select")
	var a := game.get_building_at(LUMEN_A)
	var b := _add_completed_building(game, VaultBuilding.Kind.LAMP, LUMEN_B)
	var c := _add_completed_building(game, VaultBuilding.Kind.LAMP, LUMEN_C)
	game.power_grid.recalculate(game.buildings)
	game._sync_3d_play_view()
	_assert_equal(game.power_grid.supply, 2, "fixture: emergency core supplies two power")
	_assert_true(a.powered and b.powered and not c.powered, "fixture: A and B powered, newest C shed")
	_assert_equal(game.lighting_system.get_lit_floor_count(), 99, "fixture: ninety-nine lit floors")
	_assert_equal(_stale(game).size(), 0, "fixture: terrain matches lighting before the swap")
	return [game, a, b, c]


func _test_plain_swap() -> void:
	var f := _swap_game()
	var game: VaultGame = f[0]
	var a: VaultBuilding = f[1]
	var b: VaultBuilding = f[2]
	var c: VaultBuilding = f[3]
	var before := _lit(game)
	var signature_before: String = game.map_view_3d._map_signature()
	var probe_before := _live_hex(game.map_view_3d, Vector2i(17, 19))
	var topology_before := game.map_grid.topology_revision
	_assert_true(game.toggle_building_enabled(a.building_id), "player disables the powered starting Lumen")
	_assert_true(not a.powered and b.powered and c.powered, "the shed Lumen C receives A's power")
	var after := _lit(game)
	_assert_equal(after.size(), before.size(), "lit floor count is unchanged (99)")
	var old_only := before.filter(func(cell: Vector2i) -> bool: return not after.has(cell))
	var new_only := after.filter(func(cell: Vector2i) -> bool: return not before.has(cell))
	_assert_equal(old_only.size() + new_only.size(), 34, "the lit set moved by 34 cells")
	_assert_equal(game.map_grid.topology_revision, topology_before, "topology is unchanged")
	_assert_equal(game.map_grid.preview_tool, "select", "tool is unchanged")
	_assert_true(game.map_view_3d._map_signature() != signature_before, "the map signature changes")
	game._process(0.0)
	_assert_equal(_stale(game), [] as Array[Vector2i], "one normal frame leaves no stale floor prism")
	_assert_true(_live_hex(game.map_view_3d, Vector2i(17, 19)) != probe_before, "the terrain was rebuilt")
	for cell: Vector2i in old_only:
		_assert_equal(_live_hex(game.map_view_3d, cell).material_override, game.map_view_3d._mat_floor_dark, "formerly lit %s is dark" % cell)
	for cell: Vector2i in new_only:
		_assert_equal(_live_hex(game.map_view_3d, cell).material_override, game.map_view_3d._mat_floor, "newly lit %s is plain floor" % cell)
	_dispose(game)


func _test_overlay_swap_back() -> void:
	var f := _swap_game()
	var game: VaultGame = f[0]
	var a: VaultBuilding = f[1]
	var c: VaultBuilding = f[3]
	_assert_true(game.toggle_building_enabled(a.building_id), "disable A")
	game._sync_3d_play_view()
	_assert_true(game.toggle_lighting_overlay(), "Light Map on")
	game._sync_3d_play_view()
	_assert_equal(_stale(game), [] as Array[Vector2i], "overlay shows B+C coverage")
	_assert_true(game.toggle_building_enabled(a.building_id), "re-enable A")
	_assert_true(a.powered and not c.powered, "A takes the power back; C is shed again")
	_assert_equal(game.lighting_system.get_lit_floor_count(), 99, "still ninety-nine lit floors")
	game._process(0.0)
	_assert_equal(_stale(game), [] as Array[Vector2i], "overlay repaints on a normal frame after the swap back")
	_assert_equal(_amber(game), _lit(game), "amber set equals simulated coverage")
	_dispose(game)


func _test_no_extra_rebuilds() -> void:
	var f := _swap_game()
	var game: VaultGame = f[0]
	var view: MapView3D = game.map_view_3d
	var revision: Variant = _revision(game)
	var terrain := view.hex_root.get_children()
	var queued_before := _queued(view)
	for i in 3:
		game.power_grid.recalculate(game.buildings)
		_assert_false(game.refresh_lighting(), "unchanged allocation is a lighting no-op")
		game._process(0.0)
	game.user_paused = false
	for i in 10:
		game._simulation_step(VaultGame.SIMULATION_TICK)
		game._sync_3d_play_view()
	game.user_paused = true
	_assert_equal(view.hex_root.get_children(), terrain, "terrain children are reused (no rebuild)")
	_assert_equal(_queued(view), queued_before, "no further terrain child is queued for deletion")
	_assert_equal(_revision(game), revision, "per-tick power recalculation does not bump the revision")
	_dispose(game)


func _test_revision_monotonic() -> void:
	var game := _spawn_game()
	game.begin_shift()
	var lighting := game.lighting_system
	_assert_true(lighting.has_method("get_coverage_revision"), "lighting exposes get_coverage_revision()")
	if not lighting.has_method("get_coverage_revision"):
		_dispose(game)
		return
	var start := int(_revision(game))
	_assert_false(game.refresh_lighting(), "unchanged refresh is a no-op")
	_assert_equal(int(_revision(game)), start, "no-op refresh keeps the revision")
	_assert_true(game.refresh_lighting(true), "forced refresh recomputes")
	_assert_equal(int(_revision(game)), start + 1, "forced refresh bumps once")
	lighting.reset()
	_assert_equal(int(_revision(game)), start + 2, "reset bumps instead of returning to zero")
	game.refresh_lighting()
	var before_new := int(_revision(game))
	game.new_game(false)
	_assert_true(int(_revision(game)) > before_new, "new game never reuses an older revision")
	_assert_equal(_stale(game).size(), 0, "new game terrain matches lighting")
	_dispose(game)


func _test_count_change_control() -> void:
	var f := _swap_game()
	var game: VaultGame = f[0]
	var a: VaultBuilding = f[1]
	var b: VaultBuilding = f[2]
	var c: VaultBuilding = f[3]
	_assert_true(game.toggle_building_enabled(b.building_id), "disable B")
	_assert_true(a.powered and not b.powered and c.powered, "C receives B's power")
	_assert_equal(game.lighting_system.get_lit_floor_count(), 116, "A+C light 116 floors")
	game._sync_3d_play_view()
	_assert_equal(_stale(game), [] as Array[Vector2i], "count change repaints")
	_dispose(game)


func _test_load_control() -> void:
	var f := _swap_game()
	var game: VaultGame = f[0]
	var a: VaultBuilding = f[1]
	_assert_true(game.toggle_building_enabled(a.building_id), "disable A")
	game._process(0.0)
	var swapped := _lit(game)
	var snapshot := game.create_snapshot()
	_assert_true(game.toggle_building_enabled(game.get_building_at(LUMEN_A).building_id), "re-enable A")
	game._process(0.0)
	_assert_true(game.apply_snapshot(snapshot), "swapped snapshot applies")
	game._process(0.0)
	_assert_equal(_lit(game), swapped, "loaded coverage is B+C")
	_assert_equal(_stale(game), [] as Array[Vector2i], "loaded terrain matches lighting")
	_dispose(game)


func _test_non_lamp_toggle() -> void:
	var game := _spawn_game()
	game.begin_shift()
	game.user_paused = true
	game.set_tool("select")
	var view: MapView3D = game.map_view_3d
	var a := game.get_building_at(LUMEN_A)
	var rec := _add_completed_building(game, VaultBuilding.Kind.RECREATION_CONSOLE, REC_CELL)
	game.power_grid.recalculate(game.buildings)
	game._sync_3d_play_view()
	_assert_true(a != null and a.powered, "fixture: starting Lumen A is powered")
	_assert_true(rec.powered, "fixture: Rec Console is powered (spare supply)")
	_assert_false(game.power_grid.brownout_active, "fixture: no brownout")
	_assert_equal(_stale(game).size(), 0, "fixture: terrain matches lighting")
	var revision: Variant = _revision(game)
	var lit := _lit(game)
	var signature: String = view._map_signature()
	var terrain := view.hex_root.get_children()
	var queued := _queued(view)
	var topology := game.map_grid.topology_revision
	for step in 2:
		var label := "disable" if step == 0 else "re-enable"
		_assert_true(game.toggle_building_enabled(rec.building_id), "player can %s the Rec Console" % label)
		_assert_equal(rec.powered, step == 1, "%s: Rec Console powered state flips" % label)
		_assert_true(a.powered, "%s: Lumen A stays powered" % label)
		_assert_equal(game.map_grid.topology_revision, topology, "%s: topology is unchanged" % label)
		_assert_equal(_revision(game), revision, "%s: coverage revision is unchanged" % label)
		_assert_equal(_lit(game), lit, "%s: lit set is unchanged" % label)
		_assert_equal(view._map_signature(), signature, "%s: map signature is unchanged" % label)
		game._process(0.0)
		_assert_true(view.hex_root.get_children() == terrain, "%s: terrain children are reused (no rebuild)" % label)
		_assert_equal(_queued(view), queued, "%s: no terrain child queued for deletion" % label)
		_assert_equal(_stale(game), [] as Array[Vector2i], "%s: no stale floor prism" % label)
	_dispose(game)


func _revision(game: VaultGame) -> Variant:
	if game.lighting_system.has_method("get_coverage_revision"):
		return game.lighting_system.call("get_coverage_revision")
	return null


func _queued(view: MapView3D) -> int:
	var count := 0
	for child: Node in view.hex_root.get_children():
		if child.is_queued_for_deletion():
			count += 1
	return count


func _lit(game: VaultGame) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in game.map_grid.get_floor_cells():
		if game.lighting_system.is_cell_lit(cell):
			cells.append(cell)
	return cells


func _amber(game: VaultGame) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in game.map_grid.get_floor_cells():
		var prism := _live_hex(game.map_view_3d, cell)
		if prism != null and prism.material_override == game.map_view_3d._mat_floor_lit:
			cells.append(cell)
	return cells


func _expected(game: VaultGame, cell: Vector2i) -> StandardMaterial3D:
	var view := game.map_view_3d
	var lighting := game.lighting_system
	if lighting.is_coverage_overlay_visible():
		return view._mat_floor_lit if lighting.is_cell_lit(cell) else view._mat_floor_dark
	if game.map_grid.stockpile_cells.has(cell):
		return view._mat_zone
	if lighting.is_floor_dark(cell):
		return view._mat_floor_dark
	return view._mat_floor


func _stale(game: VaultGame) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in game.map_grid.get_floor_cells():
		var prism := _live_hex(game.map_view_3d, cell)
		if prism == null or prism.material_override != _expected(game, cell):
			cells.append(cell)
	return cells


func _live_hex(view: MapView3D, cell: Vector2i) -> MeshInstance3D:
	var center := view.map_grid.cell_to_world(cell)
	for child in view.hex_root.get_children():
		if child is MeshInstance3D and not child.is_queued_for_deletion():
			if Vector2(child.position.x, child.position.z).distance_to(center) < 0.05:
				return child as MeshInstance3D
	return null
