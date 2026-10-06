extends "res://tests/test_runner.gd"

# Building ids restart with every save, so after a load (or a new game) the
# same id can belong to another fixture kind. The 3D view must then draw the
# loaded kind, not the cached proxy of the old one.

const SAVE_GROW := "user://headless_proxy_kind_grow.json"
const SAVE_BED := "user://headless_proxy_kind_bed.json"
const SAVE_KINDS := "user://headless_proxy_kind_all.json"
const SWAP_CELL := Vector2i(20, 12)
const RUBBLE_CELL := Vector2i(21, 17)
const OTHER_RUBBLE_CELL := Vector2i(24, 17)
const KIND_CELLS := [Vector2i(18, 12), Vector2i(20, 12), Vector2i(22, 12), Vector2i(24, 12), Vector2i(26, 12), Vector2i(18, 15), Vector2i(20, 15), Vector2i(22, 16), Vector2i(26, 15)]
const STARTING_KINDS := [VaultBuilding.Kind.GENERATOR, VaultBuilding.Kind.LAMP, VaultBuilding.Kind.STOCKPILE]
const STARTING_CELLS := [Vector2i(24, 15), Vector2i(22, 14), Vector2i(19, 17)]


func _run() -> void:
	_run_case("load draws the saved Grow Tray where a Bunk reused its id", _test_load_bunk_to_grow)
	_run_case("loading the Bunk save back swaps the proxy again", _test_load_grow_to_bunk)
	_run_case("every fixture kind is redrawn when a load reuses its id", _test_all_kinds_swap)
	_run_case("same-kind reload keeps every cached proxy (control)", _test_same_kind_reload_keeps_proxies)
	_run_case("New Game redraws starting fixtures where the old game drew other kinds", _test_new_game_over_other_kinds)
	_run_case("after a load the view matches a fresh load (buildings, residents, rubble)", _test_matches_fresh_load)
	print("")
	print("PROXY KIND ON LOAD TESTS: %d cases, %d assertions, %d failures" % [_case_count, _assertion_count, _failure_count])
	for path: String in [SAVE_GROW, SAVE_BED, SAVE_KINDS]:
		_remove_test_save(path)
	quit(1 if _failure_count else 0)


func _paused_game() -> VaultGame:
	var game := _spawn_game()
	game.begin_shift()
	game.user_paused = true
	return game


func _restart(game: VaultGame) -> void:
	game.new_game()
	game.begin_shift()
	game.user_paused = true


func _building(game: VaultGame, building_id: int) -> VaultBuilding:
	for building: VaultBuilding in game.buildings:
		if is_instance_valid(building) and building.building_id == building_id:
			return building
	return null


func _proxy(game: VaultGame, building_id: int) -> Node3D:
	var proxy: Node3D = game.map_view_3d._building_proxies.get(building_id)
	return proxy if is_instance_valid(proxy) else null


func _kind_name(kind: int) -> String:
	return str(VaultBuilding.Kind.keys()[kind]) if kind >= 0 and kind < VaultBuilding.Kind.size() else "kind %d" % kind


# One line per part: name, primitive, local bounds and offset.
func _geometry(assembly: Node3D) -> PackedStringArray:
	var lines := PackedStringArray()
	if not is_instance_valid(assembly):
		return lines
	for part: Node in assembly.get_children():
		var mesh_part := part as MeshInstance3D
		var part_name := "@auto" if str(part.name).begins_with("@") else str(part.name)
		if mesh_part == null or mesh_part.mesh == null:
			lines.append("%s:<no mesh>" % part_name)
			continue
		lines.append("%s:%s:%s:%s" % [part_name, mesh_part.mesh.get_class(), str(mesh_part.mesh.get_aabb()), str(mesh_part.position)])
	return lines


func _names(assembly: Node3D) -> PackedStringArray:
	var names := PackedStringArray()
	if is_instance_valid(assembly):
		for part: Node in assembly.get_children():
			names.append("@auto" if str(part.name).begins_with("@") else str(part.name))
	return names


func _palette(assembly: Node3D) -> Array:
	var colors: Array = []
	if is_instance_valid(assembly):
		for part: Node in assembly.get_children():
			colors.append(part.get_meta("original_albedo", Color.TRANSPARENT))
	return colors


# 4 assertions: part names, part geometry, part palette, placement on the cell.
func _assert_draws_kind(game: VaultGame, building: VaultBuilding, kind: int, label: String) -> void:
	var proxy := _proxy(game, building.building_id if is_instance_valid(building) else -1)
	var reference := game.map_view_3d._make_building_proxy(kind)
	_assert_equal(_names(proxy), _names(reference), "%s draws %s parts" % [label, _kind_name(kind)])
	_assert_equal(_geometry(proxy), _geometry(reference), "%s has %s geometry" % [label, _kind_name(kind)])
	_assert_equal(_palette(proxy), _palette(reference), "%s has the %s palette" % [label, _kind_name(kind)])
	reference.free()
	var center := MapGrid.offset_cell_to_world(building.cell) if is_instance_valid(building) else Vector2(INF, INF)
	var placed := is_instance_valid(proxy) and proxy.position.is_equal_approx(Vector3(center.x, MapView3D.FLOOR_HEIGHT, center.y)) and proxy.scale.is_equal_approx(Vector3.ONE)
	_assert_true(placed, "%s sits full size on its cell" % label)


# 2 assertions: one proxy per building, and nothing orphaned under FixtureRoot.
func _assert_one_proxy_per_building(game: VaultGame, label: String) -> void:
	_assert_equal(game.map_view_3d._building_proxies.size(), game.buildings.size(), "%s: one cached proxy per building" % label)
	_assert_equal(game.map_view_3d.fixture_root.get_child_count(), game.buildings.size(), "%s: no orphaned fixture under FixtureRoot" % label)


func _test_load_bunk_to_grow() -> void:
	_remove_test_save(SAVE_GROW)
	var game := _paused_game()
	var grow := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, SWAP_CELL)
	var saved_id := grow.building_id
	game._sync_3d_play_view()
	_assert_true(game.save_game(false, SAVE_GROW), "fixture: Grow Tray save succeeds")
	_restart(game)
	var bunk := _add_completed_building(game, VaultBuilding.Kind.BED, SWAP_CELL)
	_assert_equal(bunk.building_id, saved_id, "fixture: the new game's Bunk reuses the saved Grow Tray's id")
	game._sync_3d_play_view()
	_assert_draws_kind(game, bunk, VaultBuilding.Kind.BED, "Bunk before the load")
	var bunk_proxy := _proxy(game, saved_id)
	_assert_true(game.load_game(SAVE_GROW), "fixture: load succeeds")
	game._sync_3d_play_view()
	var loaded := _building(game, saved_id)
	_assert_true(is_instance_valid(loaded) and loaded.kind == VaultBuilding.Kind.GROW_TRAY and loaded.cell == SWAP_CELL, "fixture: the loaded id is a Grow Tray on the same cell")
	_assert_draws_kind(game, loaded, VaultBuilding.Kind.GROW_TRAY, "loaded Grow Tray")
	_assert_false(is_instance_valid(bunk_proxy), "the stale Bunk proxy is freed at once")
	_assert_one_proxy_per_building(game, "after load")
	var replaced := _proxy(game, saved_id)
	for i in 3:
		game._sync_3d_play_view()
	_assert_true(replaced != null and _proxy(game, saved_id) == replaced, "later syncs keep the replacement proxy")
	_remove_test_save(SAVE_GROW)
	_dispose(game)


func _test_load_grow_to_bunk() -> void:
	_remove_test_save(SAVE_GROW)
	_remove_test_save(SAVE_BED)
	var game := _paused_game()
	var bunk := _add_completed_building(game, VaultBuilding.Kind.BED, SWAP_CELL)
	var saved_id := bunk.building_id
	game._sync_3d_play_view()
	_assert_true(game.save_game(false, SAVE_BED), "fixture: Bunk save succeeds")
	_restart(game)
	var grow := _add_completed_building(game, VaultBuilding.Kind.GROW_TRAY, SWAP_CELL)
	_assert_equal(grow.building_id, saved_id, "fixture: the Grow Tray reuses the saved Bunk's id")
	game._sync_3d_play_view()
	_assert_true(game.save_game(false, SAVE_GROW), "fixture: Grow Tray save succeeds")
	_assert_true(game.load_game(SAVE_BED), "fixture: Bunk load succeeds")
	game._sync_3d_play_view()
	_assert_draws_kind(game, _building(game, saved_id), VaultBuilding.Kind.BED, "loaded Bunk")
	_assert_true(game.load_game(SAVE_GROW), "fixture: Grow Tray load succeeds")
	game._sync_3d_play_view()
	_assert_draws_kind(game, _building(game, saved_id), VaultBuilding.Kind.GROW_TRAY, "reloaded Grow Tray")
	_assert_one_proxy_per_building(game, "after two loads")
	_remove_test_save(SAVE_GROW)
	_remove_test_save(SAVE_BED)
	_dispose(game)


func _test_all_kinds_swap() -> void:
	_remove_test_save(SAVE_KINDS)
	var kinds: Array = VaultBuilding.Kind.values()
	_assert_equal(kinds.size(), KIND_CELLS.size(), "fixture: one cell per fixture kind")
	var game := _paused_game()
	var saved_ids: Array[int] = []
	for i in kinds.size():
		saved_ids.append(_add_completed_building(game, kinds[i], KIND_CELLS[i]).building_id)
	game._sync_3d_play_view()
	_assert_true(game.save_game(false, SAVE_KINDS), "fixture: all-kinds save succeeds")
	_restart(game)
	var reused := true
	for i in kinds.size():
		var other := _add_completed_building(game, kinds[(i + 1) % kinds.size()], KIND_CELLS[i])
		reused = reused and other.building_id == saved_ids[i]
	_assert_true(reused, "fixture: every saved id now holds the next kind")
	game._sync_3d_play_view()
	_assert_true(game.load_game(SAVE_KINDS), "fixture: all-kinds load succeeds")
	game._sync_3d_play_view()
	for i in kinds.size():
		_assert_draws_kind(game, _building(game, saved_ids[i]), kinds[i], "loaded %s" % _kind_name(kinds[i]))
	_assert_one_proxy_per_building(game, "after the all-kinds load")
	_remove_test_save(SAVE_KINDS)
	_dispose(game)


func _test_same_kind_reload_keeps_proxies() -> void:
	_remove_test_save(SAVE_BED)
	var game := _paused_game()
	var bunk := _add_completed_building(game, VaultBuilding.Kind.BED, SWAP_CELL)
	_add_completed_building(game, VaultBuilding.Kind.LAMP, Vector2i(26, 12))
	game._sync_3d_play_view()
	var before := {}
	for building: VaultBuilding in game.buildings:
		before[building.building_id] = _proxy(game, building.building_id)
	_assert_true(game.save_game(false, SAVE_BED), "fixture: save succeeds")
	# Leave the live Bunk as a fresh blueprint so the reload must refresh the kept proxy.
	bunk.complete = false
	bunk.delivered = 0
	bunk.construction_left = bunk.get_build_time()
	game._sync_3d_play_view()
	var blueprint := _proxy(game, bunk.building_id)
	_assert_true(blueprint != null and blueprint.scale.is_equal_approx(Vector3.ONE * 0.5), "fixture: the live Bunk is drawn as a half-size blueprint")
	_assert_true(game.load_game(SAVE_BED), "fixture: load succeeds")
	game._sync_3d_play_view()
	var kept := game.buildings.size() == before.size()
	for building: VaultBuilding in game.buildings:
		kept = kept and before.get(building.building_id) != null and _proxy(game, building.building_id) == before[building.building_id]
	_assert_true(kept, "every same-kind proxy survives the reload unchanged")
	var loaded := game.get_building_at(SWAP_CELL)
	_assert_draws_kind(game, loaded, VaultBuilding.Kind.BED, "reloaded Bunk")
	var solid := is_instance_valid(blueprint)
	if solid:
		for part: MeshInstance3D in blueprint.get_children():
			var material := part.material_override as StandardMaterial3D
			solid = solid and material != null and material.albedo_color == part.get_meta("original_albedo") and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
	_assert_true(solid, "the kept proxy is repainted solid in its saved palette")
	_assert_one_proxy_per_building(game, "after same-kind reload")
	_remove_test_save(SAVE_BED)
	_dispose(game)


func _test_new_game_over_other_kinds() -> void:
	# Shipped saves always keep ids 1-3 for the starting fixtures, so this only
	# guards older or hand-edited wings (and any future change to the starting
	# set): the old game drew other kinds on ids 1-3 when New Game respawns them.
	var game := _paused_game()
	for building: VaultBuilding in game.buildings:
		building.free()
	game.buildings.clear()
	game._sync_3d_play_view()
	game.next_building_id = 1
	var legacy_kinds := [VaultBuilding.Kind.BED, VaultBuilding.Kind.GROW_TRAY, VaultBuilding.Kind.KITCHEN]
	for i in legacy_kinds.size():
		_add_completed_building(game, legacy_kinds[i], STARTING_CELLS[i])
	game.power_grid.recalculate(game.buildings)
	game._sync_3d_play_view()
	_assert_draws_kind(game, _building(game, 1), VaultBuilding.Kind.BED, "old game's id 1 before New Game")
	game.new_game()
	var starting_ok := true
	for i in STARTING_KINDS.size():
		var building := _building(game, i + 1)
		starting_ok = starting_ok and is_instance_valid(building) and building.kind == STARTING_KINDS[i] and building.cell == STARTING_CELLS[i]
	_assert_true(starting_ok, "fixture: New Game puts the starting fixtures on ids 1-3")
	for i in STARTING_KINDS.size():
		_assert_draws_kind(game, _building(game, i + 1), STARTING_KINDS[i], "New Game %s" % _kind_name(STARTING_KINDS[i]))
	_assert_one_proxy_per_building(game, "after New Game")
	_dispose(game)


# Differential audit of every id-keyed cache except food boxes (#88 owns their
# colour after a load): the live view after A -> load B must equal a view whose
# fixtures were all built from B.
func _test_matches_fresh_load() -> void:
	_remove_test_save(SAVE_KINDS)
	var source := _paused_game()
	_add_completed_building(source, VaultBuilding.Kind.GROW_TRAY, Vector2i(20, 12))
	_add_completed_building(source, VaultBuilding.Kind.KITCHEN, Vector2i(23, 12))
	_add_completed_building(source, VaultBuilding.Kind.BED, Vector2i(26, 12))
	_add_completed_building(source, VaultBuilding.Kind.LAMP, Vector2i(18, 15))
	source.power_grid.recalculate(source.buildings)
	source.job_system.queue_rubble(RUBBLE_CELL, 1)
	source.residents[1].needs.mood = 20.0
	source.residents[2].sleeping = true
	source.residents[2].bed_id = -1
	source.residents[3].alive = false
	source._sync_3d_play_view()
	_assert_true(source.save_game(false, SAVE_KINDS), "fixture: source save succeeds")
	var live := _paused_game()
	_add_completed_building(live, VaultBuilding.Kind.BED, Vector2i(20, 12))
	_add_completed_building(live, VaultBuilding.Kind.GROW_TRAY, Vector2i(23, 12))
	_add_completed_building(live, VaultBuilding.Kind.LAMP, Vector2i(26, 12))
	_add_completed_building(live, VaultBuilding.Kind.KITCHEN, Vector2i(18, 15))
	live.power_grid.recalculate(live.buildings)
	live.job_system.queue_rubble(OTHER_RUBBLE_CELL, 1)
	live.residents[0].selected = true
	live.residents[2].needs.mood = 10.0
	live.residents[3].sleeping = true
	live.residents[3].bed_id = -1
	live._sync_3d_play_view()
	_assert_true(live.load_game(SAVE_KINDS), "fixture: live load succeeds")
	live._sync_3d_play_view()
	# Reference view: drop the boot fixtures first so every cached proxy comes from B.
	var fresh := _spawn_game()
	for building: VaultBuilding in fresh.buildings:
		building.free()
	fresh.buildings.clear()
	fresh._sync_3d_play_view()
	_assert_true(fresh.map_view_3d._building_proxies.is_empty(), "fixture: the reference view starts with no cached fixtures")
	_assert_true(fresh.load_game(SAVE_KINDS), "fixture: fresh load succeeds")
	fresh._sync_3d_play_view()
	for cache_name: String in ["_building_proxies", "_resident_proxies", "_rubble_props"]:
		var live_cache: Dictionary = live.map_view_3d.get(cache_name)
		var fresh_cache: Dictionary = fresh.map_view_3d.get(cache_name)
		var keys := live_cache.keys()
		keys.sort()
		var fresh_keys := fresh_cache.keys()
		fresh_keys.sort()
		_assert_equal(keys, fresh_keys, "%s holds the same ids as a fresh load" % cache_name)
		for key: Variant in fresh_keys:
			_assert_equal(_describe(live_cache.get(key)), _describe(fresh_cache[key]), "%s[%s] matches a fresh load" % [cache_name, str(key)])
	_remove_test_save(SAVE_KINDS)
	_dispose(source)
	_dispose(live)
	_dispose(fresh)


func _describe(node: Variant) -> String:
	if not is_instance_valid(node) or not node is Node3D:
		return "<missing>"
	var node3d := node as Node3D
	var text := "%s pos=%s rot=%s scale=%s visible=%s" % [node3d.get_class(), str(node3d.position.snapped(Vector3.ONE * 0.001)), str(node3d.rotation.snapped(Vector3.ONE * 0.001)), str(node3d.scale.snapped(Vector3.ONE * 0.001)), node3d.visible]
	var mesh_node := node3d as MeshInstance3D
	if mesh_node != null:
		text += " mesh=%s %s" % [mesh_node.mesh.get_class() if mesh_node.mesh != null else "null", str(mesh_node.mesh.get_aabb()) if mesh_node.mesh != null else ""]
		var material := mesh_node.material_override as StandardMaterial3D
		if material != null:
			text += " albedo=%s emission=%s transparency=%d" % [material.albedo_color.to_html(), material.emission_enabled, material.transparency]
	var parts := PackedStringArray()
	for child: Node in node3d.get_children():
		parts.append("%s{%s}" % ["@auto" if str(child.name).begins_with("@") else str(child.name), _describe(child)])
	if not parts.is_empty():
		text += " [" + "; ".join(parts) + "]"
	return text
