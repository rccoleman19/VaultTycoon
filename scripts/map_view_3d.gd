class_name MapView3D
extends Node3D

## Placeholder 3D play surface. MapGrid remains logic authority (including hex BFS
## find_path). This node only mirrors tiles/actors for Camera3D viewing and
## screen→hex picking. Colonists use a single CapsuleMesh pill — nothing else.

const ROCK_HEIGHT := 6.0
const FLOOR_HEIGHT := 0.55
const DIG_HEIGHT := 5.2
const CAMERA_HEIGHT := 170.0
const CAMERA_BACK := 200.0
const CAMERA_SIDE := 30.0
const HEX_MESH_YAW_DEGREES := 0.0
const COLONIST_RADIUS := 2.4
const COLONIST_HEIGHT := 13.0
const BUNK_MATTRESS_TOP := 3.90
const MEDICAL_MATTRESS_TOP := 4.40

var map_grid: MapGrid
var lighting_system: LightingSystem

@onready var camera_3d: Camera3D = $Camera3D
@onready var hex_root: Node3D = $HexRoot
@onready var actor_root: Node3D = $ActorRoot
@onready var fixture_root: Node3D = $FixtureRoot
@onready var marker_root: Node3D = $MarkerRoot

var _last_map_signature := ""
var _resident_proxies: Dictionary = {}
var _building_proxies: Dictionary[int, Node3D] = {}
var _rubble_props: Dictionary = {}
var _food_props: Dictionary = {}
var _hatch_proxy: MeshInstance3D
var _shared_hex_mesh: CylinderMesh
var _mat_rock: StandardMaterial3D
var _mat_rock_border: StandardMaterial3D
var _mat_wall: StandardMaterial3D
var _wall_rock_meshes: Dictionary = {}
var _chamber_fill: OmniLight3D
var _mat_floor: StandardMaterial3D
var _mat_floor_dark: StandardMaterial3D
var _mat_floor_lit: StandardMaterial3D
var _mat_dig: StandardMaterial3D
var _mat_zone: StandardMaterial3D
var _mat_hover_ok: StandardMaterial3D
var _mat_hover_bad: StandardMaterial3D
var _mat_colonist: StandardMaterial3D
var _mat_colonist_uneasy: StandardMaterial3D
var _mat_colonist_break: StandardMaterial3D
var _mat_colonist_selected: StandardMaterial3D
var _mat_colonist_dead: StandardMaterial3D
var _mat_hatch: StandardMaterial3D


func _ready() -> void:
	_ensure_materials()
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_energy = 0.32
	_chamber_fill = OmniLight3D.new()
	_chamber_fill.name = "ChamberFill"
	_chamber_fill.light_color = Color(1.0, 0.82, 0.62)
	_chamber_fill.light_energy = 0.65
	_chamber_fill.omni_range = 210.0
	_chamber_fill.omni_attenuation = 0.8
	# Presentation only: this light never participates in Lumen coverage.
	var chamber_center := MapGrid.offset_cell_to_world(MapGrid.CHAMBER.get_center())
	_chamber_fill.position = Vector3(chamber_center.x, 42.0, chamber_center.y)
	add_child(_chamber_fill)
	if camera_3d:
		camera_3d.current = true


func get_hex_prism_radius() -> float:
	_ensure_materials()
	return _shared_hex_mesh.top_radius


func get_hex_mesh_yaw_degrees() -> float:
	return HEX_MESH_YAW_DEGREES


func setup(grid: MapGrid, lighting: LightingSystem = null) -> void:
	map_grid = grid
	lighting_system = lighting
	_ensure_materials()
	rebuild_map(true)


func _ensure_materials() -> void:
	if _shared_hex_mesh == null:
		_shared_hex_mesh = CylinderMesh.new()
		_shared_hex_mesh.top_radius = MapGrid.HEX_SIZE
		_shared_hex_mesh.bottom_radius = MapGrid.HEX_SIZE
		_shared_hex_mesh.height = 1.0
		_shared_hex_mesh.radial_segments = 6
		_shared_hex_mesh.rings = 1
	if _mat_rock == null:
		_mat_rock = _make_terrain_mat(Color(0.16, 0.14, 0.13))
		_mat_rock_border = _make_terrain_mat(Color(0.125, 0.12, 0.11))
		_mat_floor = _make_terrain_mat(Color(0.43, 0.42, 0.39))
		_mat_floor_dark = _make_terrain_mat(Color(0.27, 0.26, 0.24))
		_mat_floor_lit = _make_terrain_mat(_mat_floor.albedo_color.lerp(Color(1.0, 0.78, 0.28), 0.12))
		_mat_wall = _make_terrain_mat(Color(0.36, 0.35, 0.32))
		_mat_dig = _make_mat(Color(0.85, 0.55, 0.18))
		_mat_zone = _make_mat(Color(0.28, 0.62, 0.70))
		_mat_hover_ok = _make_mat(Color(0.35, 0.85, 0.65))
		_mat_hover_bad = _make_mat(Color(0.90, 0.30, 0.28))
		_mat_colonist = _make_mat(Color(0.44, 0.78, 0.71))
		_mat_colonist_uneasy = _make_mat(Color("a68462"))
		_mat_colonist_break = _make_mat(Color("ef5a54"))
		_mat_colonist_selected = _make_mat(Color(0.96, 0.78, 0.30))
		_mat_colonist_dead = _make_mat(Color(0.38, 0.41, 0.42))
		_mat_hatch = _make_mat(Color(0.75, 0.35, 0.28))


func _make_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _make_terrain_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.metallic = 0.0
	mat.roughness = 0.95
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func rebuild_map(force := false) -> void:
	if map_grid == null:
		return
	_ensure_materials()
	var signature := _map_signature()
	if not force and signature == _last_map_signature:
		return
	_last_map_signature = signature
	for child in hex_root.get_children():
		child.queue_free()
	for y in MapGrid.HEIGHT:
		for x in MapGrid.WIDTH:
			var cell := Vector2i(x, y)
			var prism := _make_hex_instance(cell)
			hex_root.add_child(prism)
			if map_grid.get_tile(cell) == MapGrid.Tile.ROCK:
				_add_perimeter_walls(cell, prism)


# The same yaw-0, pointy-top vertices as CylinderMesh, at full HEX_SIZE.
func _hex_vertex(index: int) -> Vector2:
	var angle := index * PI / 3.0
	return Vector2(sin(angle), cos(angle)) * MapGrid.HEX_SIZE


func _add_perimeter_walls(cell: Vector2i, prism: MeshInstance3D) -> void:
	var wall_height := prism.scale.y - FLOOR_HEIGHT
	if wall_height <= 0.0001:
		return
	var center := map_grid.cell_to_world(cell)
	var edge_mask := 0
	for edge in 6:
		var a := _hex_vertex(edge)
		var b := _hex_vertex(edge + 1)
		var midpoint := (a + b) * 0.5
		# Twice the edge midpoint is the neighboring cell's center offset.
		var neighbor := map_grid.world_to_cell(center + midpoint * 2.0)
		if not map_grid.is_walkable(neighbor):
			continue
		edge_mask |= 1 << edge
		var wall := MeshInstance3D.new()
		wall.name = "ConcreteWall_%d_%d_%d" % [cell.x, cell.y, edge]
		var box := BoxMesh.new()
		const THICKNESS := 0.18
		box.size = Vector3(a.distance_to(b), wall_height, THICKNESS)
		wall.mesh = box
		wall.material_override = _mat_wall
		var wall_center := center + midpoint - midpoint.normalized() * THICKNESS * 0.5
		wall.position = Vector3(wall_center.x, FLOOR_HEIGHT + wall_height * 0.5, wall_center.y)
		var tangent := b - a
		wall.rotation.y = atan2(-tangent.y, tangent.x)
		hex_root.add_child(wall)
	if edge_mask != 0:
		# Keep the prism's top (including orange dig feedback) and all exterior
		# faces. Omit only sides behind concrete to avoid coplanar z-fighting.
		prism.mesh = _rock_mesh_with_walls(edge_mask)


func _rock_mesh_with_walls(edge_mask: int) -> ArrayMesh:
	if _wall_rock_meshes.has(edge_mask):
		return _wall_rock_meshes[edge_mask]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for edge in 6:
		var a := _hex_vertex(edge)
		var b := _hex_vertex(edge + 1)
		var bottom_a := Vector3(a.x, -0.5, a.y)
		var bottom_b := Vector3(b.x, -0.5, b.y)
		var top_a := Vector3(a.x, 0.5, a.y)
		var top_b := Vector3(b.x, 0.5, b.y)
		_add_terrain_triangle(surface, Vector3(0.0, 0.5, 0.0), top_a, top_b, Vector3.UP)
		_add_terrain_triangle(surface, Vector3(0.0, -0.5, 0.0), bottom_b, bottom_a, Vector3.DOWN)
		if edge_mask & (1 << edge) == 0:
			var normal := Vector3(a.x + b.x, 0.0, a.y + b.y).normalized()
			_add_terrain_triangle(surface, bottom_a, top_a, top_b, normal)
			_add_terrain_triangle(surface, bottom_a, top_b, bottom_b, normal)
	var mesh := surface.commit()
	_wall_rock_meshes[edge_mask] = mesh
	return mesh


func _add_terrain_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	surface.set_normal(normal)
	surface.add_vertex(a)
	# Godot uses clockwise front faces; keep the supplied outward normal.
	surface.add_vertex(c)
	surface.add_vertex(b)


func _dig_bucket(cell: Vector2i) -> int:
	var progress := float(map_grid.dig_progress.get(cell, 0.0))
	return floori(clampf(progress / 8.0, 0.0, 1.0) * 8.0)


func _map_signature() -> String:
	var hover := map_grid.hover_cell
	var dig_cells := map_grid.dig_marks.keys()
	dig_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y * MapGrid.WIDTH + a.x < b.y * MapGrid.WIDTH + b.x)
	var dig_bits := PackedStringArray()
	for cell: Vector2i in dig_cells:
		dig_bits.append("%d,%d,%d" % [cell.x, cell.y, _dig_bucket(cell)])
	var zone_bits := map_grid.stockpile_cells.size()
	var lit_bits := 0
	if lighting_system != null and is_instance_valid(lighting_system):
		lit_bits = lighting_system.get_lit_floor_count()
		if lighting_system.is_coverage_overlay_visible():
			lit_bits += 100000
	return "%d:%s:%d:%d:%d:%s:%d" % [
		map_grid.topology_revision,
		";".join(dig_bits),
		zone_bits,
		hover.x,
		hover.y,
		map_grid.preview_tool,
		lit_bits,
	]


func _make_hex_instance(cell: Vector2i) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = _shared_hex_mesh
	var center := map_grid.cell_to_world(cell)
	var height := FLOOR_HEIGHT
	var mat := _mat_floor
	var is_rock := map_grid.get_tile(cell) == MapGrid.Tile.ROCK
	if is_rock:
		height = lerpf(DIG_HEIGHT, FLOOR_HEIGHT, _dig_bucket(cell) / 8.0) if map_grid.dig_marks.has(cell) else ROCK_HEIGHT
		if map_grid.is_border(cell):
			mat = _mat_rock_border
		elif map_grid.dig_marks.has(cell):
			mat = _mat_dig
		else:
			mat = _mat_rock
	else:
		if lighting_system != null and is_instance_valid(lighting_system) and lighting_system.is_coverage_overlay_visible():
			mat = _mat_floor_lit if lighting_system.is_cell_lit(cell) else _mat_floor_dark
		elif map_grid.stockpile_cells.has(cell):
			mat = _mat_zone
		elif lighting_system != null and is_instance_valid(lighting_system) and lighting_system.is_floor_dark(cell):
			mat = _mat_floor_dark
		else:
			mat = _mat_floor
	if (
		map_grid.preview_tool == "lamp"
		and map_grid.is_preview_valid("lamp", map_grid.hover_cell)
		and map_grid.is_walkable(cell)
		and LightingSystem.is_cell_in_lumen_range(cell, map_grid.hover_cell)
	):
		mat = _mat_hover_ok
	if cell == map_grid.hover_cell and map_grid.preview_tool != "select":
		mat = _mat_hover_ok if map_grid.is_preview_valid(map_grid.preview_tool, cell) else _mat_hover_bad
		if is_rock and not map_grid.dig_marks.has(cell):
			height = maxf(height, DIG_HEIGHT)
	instance.scale = Vector3(1.0, height, 1.0)
	instance.position = Vector3(center.x, height * 0.5, center.y)
	# CylinderMesh vertices sit on ±Z at yaw 0. World Z is the row axis, so yaw 0 is pointy-top and matches odd-r centers. +30° would turn the mesh flat-top and open interior seams.
	instance.rotation_degrees.y = HEX_MESH_YAW_DEGREES
	instance.material_override = mat
	return instance


func apply_camera_focus(focus: Vector2, zoom: float) -> void:
	if camera_3d == null:
		return
	var z := clampf(zoom, 0.75, 1.8)
	var inv := 1.0 / z
	var focus3 := Vector3(focus.x, 0.0, focus.y)
	camera_3d.position = focus3 + Vector3(CAMERA_SIDE * inv, CAMERA_HEIGHT * inv, CAMERA_BACK * inv)
	camera_3d.look_at(focus3, Vector3.UP)
	camera_3d.fov = 42.0


func screen_to_world_xz(screen_pos: Vector2) -> Vector2:
	if camera_3d == null:
		return Vector2.ZERO
	var from := camera_3d.project_ray_origin(screen_pos)
	var dir := camera_3d.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.00001:
		return Vector2(from.x, from.z)
	var t := -from.y / dir.y
	if t < 0.0:
		return Vector2(from.x, from.z)
	var hit := from + dir * t
	return Vector2(hit.x, hit.z)


func pick_cell(screen_pos: Vector2) -> Vector2i:
	if map_grid == null:
		return Vector2i(-1, -1)
	return map_grid.world_to_cell(screen_to_world_xz(screen_pos))


func sync_actors(residents: Array[VaultResident], buildings: Array[VaultBuilding], show_hatch: bool, jobs: Array = [], breach_phase: BreachSystem.Phase = BreachSystem.Phase.DORMANT, patch_work_left: float = BreachSystem.PATCH_WORK_SECONDS) -> void:
	_ensure_materials()
	match breach_phase:
		BreachSystem.Phase.DORMANT:
			_mat_hatch.albedo_color = Color(0.75, 0.35, 0.28)
		BreachSystem.Phase.SEALED:
			_mat_hatch.albedo_color = Color("75D4B4")
		BreachSystem.Phase.WARNING, BreachSystem.Phase.OPEN:
			var progress := clampf(1.0 - patch_work_left / BreachSystem.PATCH_WORK_SECONDS, 0.0, 1.0)
			var phase_color := Color("EFC56B") if breach_phase == BreachSystem.Phase.WARNING else Color("EF6860")
			_mat_hatch.albedo_color = phase_color.lerp(Color("75D4B4"), progress)
	var prop_root := get_node_or_null("PropRoot") as Node3D
	if prop_root == null:
		prop_root = Node3D.new()
		prop_root.name = "PropRoot"
		add_child(prop_root)
	var live_rubble: Dictionary = {}
	for job: Dictionary in jobs:
		if int(job.type) != JobSystem.JobType.HAUL_RUBBLE or bool(job.done):
			continue
		live_rubble[job.id] = true
		var prop: MeshInstance3D = _rubble_props.get(job.id)
		if prop == null or not is_instance_valid(prop):
			prop = MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(3.2, 2.0, 3.2)
			prop.mesh = box
			prop.material_override = _make_mat(Color("bd8f52"))
			prop_root.add_child(prop)
			_rubble_props[job.id] = prop
		var center := MapGrid.offset_cell_to_world(job.target)
		prop.position = Vector3(center.x, 1.0, center.y)
		for resident: VaultResident in residents:
			if (
				is_instance_valid(resident) and resident.alive
				and resident.current_job_id == int(job.id)
				and resident.job_phase == "deposit" and resident.carrying > 0
			):
				prop.position = Vector3(resident.position.x + 4.6, 1.0, resident.position.y)
				break
	for id: Variant in _rubble_props.keys():
		if live_rubble.has(id):
			continue
		var stale_prop: MeshInstance3D = _rubble_props[id]
		if is_instance_valid(stale_prop):
			stale_prop.get_parent().remove_child(stale_prop)
			stale_prop.queue_free()
		_rubble_props.erase(id)
	var live_food: Dictionary = {}
	for job: Dictionary in jobs:
		if int(job.type) not in [JobSystem.JobType.HAUL_MEAL, JobSystem.JobType.HAUL_RAW_FOOD] or bool(job.done):
			continue
		live_food[job.id] = true
		var prop: MeshInstance3D = _food_props.get(job.id)
		if prop == null or not is_instance_valid(prop):
			prop = MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(2.4, 1.4, 2.4)
			prop.mesh = box
			prop.material_override = _make_mat(Color("c46a3a") if int(job.type) == JobSystem.JobType.HAUL_MEAL else Color("74b76c"))
			prop_root.add_child(prop)
			_food_props[job.id] = prop
		var center := MapGrid.offset_cell_to_world(job.target)
		prop.position = Vector3(center.x, 0.7, center.y)
		for resident: VaultResident in residents:
			if (
				is_instance_valid(resident) and resident.alive
				and resident.current_job_id == int(job.id)
				and resident.job_phase == "deposit" and resident.carrying > 0
			):
				prop.position = Vector3(resident.position.x + 4.6, 0.7, resident.position.y)
				break
	for id: Variant in _food_props.keys():
		if live_food.has(id):
			continue
		var stale_prop: MeshInstance3D = _food_props[id]
		if is_instance_valid(stale_prop):
			stale_prop.get_parent().remove_child(stale_prop)
			stale_prop.queue_free()
		_food_props.erase(id)
	var live_residents: Dictionary = {}
	for resident: VaultResident in residents:
		if not is_instance_valid(resident):
			continue
		live_residents[resident.resident_id] = true
		var proxy: MeshInstance3D = _resident_proxies.get(resident.resident_id)
		if proxy == null or not is_instance_valid(proxy):
			proxy = _make_colonist_proxy()
			actor_root.add_child(proxy)
			_resident_proxies[resident.resident_id] = proxy
		proxy.visible = true
		var pos := resident.position
		proxy.rotation = Vector3.ZERO
		proxy.position = Vector3(pos.x, COLONIST_HEIGHT * 0.5, pos.y)
		if resident.sleeping and resident.bed_id < 0:
			proxy.rotation = Vector3(PI / 2, 0, 0)
			proxy.position.y = COLONIST_RADIUS
		elif resident.sleeping and resident.state == "Sleeping":
			for building: VaultBuilding in buildings:
				if building.building_id != resident.bed_id or not building.complete or building.kind != VaultBuilding.Kind.BED:
					continue
				var bed_center := MapGrid.offset_cell_to_world(building.cell)
				if pos.distance_to(bed_center) <= 1.0:
					proxy.rotation = Vector3(PI / 2, 0, 0)
					proxy.position = Vector3(bed_center.x, FLOOR_HEIGHT + BUNK_MATTRESS_TOP + COLONIST_RADIUS, bed_center.y)
				break
		elif resident.alive and resident.medical_bed_id >= 0 and resident.state == "Rest-Medical":
			for building: VaultBuilding in buildings:
				if building.building_id != resident.medical_bed_id or not building.complete or building.kind != VaultBuilding.Kind.MEDICAL_BED:
					continue
				var bed_center := MapGrid.offset_cell_to_world(building.cell)
				if pos.distance_to(bed_center) <= 1.0:
					proxy.rotation = Vector3(PI / 2, 0, 0)
					proxy.position = Vector3(bed_center.x, FLOOR_HEIGHT + MEDICAL_MATTRESS_TOP + COLONIST_RADIUS, bed_center.y)
				break
		if not resident.alive:
			proxy.material_override = _mat_colonist_dead
		elif resident.selected:
			proxy.material_override = _mat_colonist_selected
		elif resident.needs.mood >= 70.0:
			proxy.material_override = _mat_colonist
		elif resident.needs.mood > ResidentNeeds.BREAK_MOOD_THRESHOLD:
			proxy.material_override = _mat_colonist_uneasy
		else:
			proxy.material_override = _mat_colonist_break
	for id: Variant in _resident_proxies.keys():
		if live_residents.has(id):
			continue
		var stale: MeshInstance3D = _resident_proxies[id]
		if is_instance_valid(stale):
			stale.queue_free()
		_resident_proxies.erase(id)

	var live_buildings: Dictionary = {}
	for building: VaultBuilding in buildings:
		if not is_instance_valid(building):
			continue
		live_buildings[building.building_id] = true
		var proxy: Node3D = _building_proxies.get(building.building_id)
		if proxy == null or not is_instance_valid(proxy):
			proxy = _make_building_proxy(building.kind)
			fixture_root.add_child(proxy)
			_building_proxies[building.building_id] = proxy
		var center := MapGrid.offset_cell_to_world(building.cell)
		var s := 1.0
		if not building.complete:
			if building.delivered < building.get_cost():
				s = lerpf(0.50, 0.75, float(building.delivered) / float(building.get_cost()))
			else:
				s = lerpf(0.75, 1.00, 1.0 - building.construction_left / building.get_build_time())
		proxy.position = Vector3(center.x, FLOOR_HEIGHT, center.y)
		proxy.scale = Vector3.ONE * s
		_sync_fixture_appearance(proxy, building)
	for id: Variant in _building_proxies.keys():
		if live_buildings.has(id):
			continue
		var stale_b: Node3D = _building_proxies[id]
		if is_instance_valid(stale_b):
			fixture_root.remove_child(stale_b)
			stale_b.queue_free()
		_building_proxies.erase(id)

	if show_hatch:
		if _hatch_proxy == null or not is_instance_valid(_hatch_proxy):
			_hatch_proxy = MeshInstance3D.new()
			var hatch_mesh := CylinderMesh.new()
			hatch_mesh.top_radius = 5.0
			hatch_mesh.bottom_radius = 5.0
			hatch_mesh.height = 3.0
			hatch_mesh.radial_segments = 8
			_hatch_proxy.mesh = hatch_mesh
			_hatch_proxy.material_override = _mat_hatch
			marker_root.add_child(_hatch_proxy)
		var hatch_center := MapGrid.offset_cell_to_world(BreachSystem.HATCH_CELL)
		_hatch_proxy.position = Vector3(hatch_center.x, 2.0, hatch_center.y)
		_hatch_proxy.visible = true
	elif _hatch_proxy != null and is_instance_valid(_hatch_proxy):
		_hatch_proxy.visible = false


## Colonists/NPCs: one CapsuleMesh pill only — no body art, no multi-mesh humanoids.
func _make_colonist_proxy() -> MeshInstance3D:
	var proxy := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = COLONIST_RADIUS
	capsule.height = COLONIST_HEIGHT
	proxy.mesh = capsule
	proxy.material_override = _mat_colonist
	return proxy


## Fixture geometry is authored upward from the foot; each instance owns its materials.
func _make_building_proxy(kind: int) -> Node3D:
	var root := Node3D.new()
	var steel := Color("505b60")
	var dark_steel := Color("303a40")
	match kind:
		VaultBuilding.Kind.BED:
			_fixture_box(root, "Foot", Vector3(7.8, 1.8, 13.8), Vector3(0, 0.9, 0), dark_steel)
			_fixture_box(root, "Frame", Vector3(8.8, 1.0, 15.0), Vector3(0, 2.3, 0), steel)
			_fixture_box(root, "Mattress", Vector3(7.6, 1.1, 13.4), Vector3(0, BUNK_MATTRESS_TOP - 0.55, 0), Color("aebbb8"))
			_fixture_box(root, "Pillow", Vector3(5.6, 0.7, 2.6), Vector3(0, BUNK_MATTRESS_TOP + 0.35, -4.8), Color("ddd8c6"))
			_fixture_box(root, "Headboard", Vector3(8.8, 4.8, 0.7), Vector3(0, 2.4, -7.15), steel)
		VaultBuilding.Kind.KITCHEN:
			_fixture_box(root, "Foot", Vector3(10.4, 0.7, 7.8), Vector3(0, 0.35, 0), dark_steel)
			_fixture_box(root, "Cabinet", Vector3(10.8, 4.4, 8.2), Vector3(0, 2.9, 0), Color("89938d"))
			_fixture_box(root, "Worktop", Vector3(11.6, 0.6, 8.8), Vector3(0, 5.4, 0), Color("d1c5a6"))
			_fixture_box(root, "Appliance", Vector3(10.8, 2.7, 2.2), Vector3(0, 7.05, -3.0), steel)
			_fixture_box(root, "CookSurface", Vector3(4.8, 0.12, 4.0), Vector3(-2.0, 5.71, 0.6), dark_steel)
		VaultBuilding.Kind.GENERATOR:
			# Emergency Core and Charge Node deliberately share this assembly.
			_fixture_box(root, "Foot", Vector3(10.8, 0.9, 9.4), Vector3(0, 0.45, 0), dark_steel)
			_fixture_box(root, "Housing", Vector3(10.0, 2.6, 8.6), Vector3(0, 2.2, 0), steel)
			for x: float in [-2.6, 2.6]:
				var drum := CylinderMesh.new()
				drum.top_radius = 2.1
				drum.bottom_radius = 2.1
				drum.height = 3.4
				drum.radial_segments = 12
				_fixture_part(root, "Drum", drum, Vector3(x, 4.8, 0), Color("7f8b87"))
			_fixture_box(root, "TealInset", Vector3(2.8, 1.0, 0.15), Vector3(0, 2.6, 4.31), Color("65ada5"))
		VaultBuilding.Kind.LAMP:
			_fixture_box(root, "Foot", Vector3(5.8, 1.0, 5.4), Vector3(0, 0.5, 0), dark_steel)
			_fixture_box(root, "Pedestal", Vector3(1.8, 5.8, 1.8), Vector3(0, 3.9, 0), steel)
			_fixture_box(root, "EmitterBacking", Vector3(4.0, 4.4, 1.8), Vector3(0, 8.1, 0), dark_steel)
			_fixture_box(root, "Emitter", Vector3(2.8, 3.4, 0.3), Vector3(0, 8.1, 0.95), Color("efbe63"), true)
			_fixture_box(root, "GuardLeft", Vector3(0.5, 4.4, 2.2), Vector3(-1.75, 8.1, 0.2), steel)
			_fixture_box(root, "GuardRight", Vector3(0.5, 4.4, 2.2), Vector3(1.75, 8.1, 0.2), steel)
			_fixture_box(root, "GuardCap", Vector3(4.0, 0.5, 2.2), Vector3(0, 10.05, 0.2), steel)
		VaultBuilding.Kind.STOCKPILE:
			# Fixed decorative cargo: open rack and shelf gaps lead the silhouette.
			_fixture_box(root, "BaseShelf", Vector3(12.0, 0.7, 8.0), Vector3(0, 0.35, 0), Color("97804f"))
			_fixture_box(root, "PostLeft", Vector3(0.8, 10.0, 0.9), Vector3(-5.6, 5.0, 0), steel)
			_fixture_box(root, "PostRight", Vector3(0.8, 10.0, 0.9), Vector3(5.6, 5.0, 0), steel)
			_fixture_box(root, "MiddleShelf", Vector3(10.4, 0.6, 8.0), Vector3(0, 5.0, 0), Color("97804f"))
			_fixture_box(root, "TopCrossbar", Vector3(12.0, 0.7, 0.8), Vector3(0, 9.65, 0), steel)
			_fixture_box(root, "CrateLower", Vector3(3.6, 2.4, 4.0), Vector3(-2.7, 1.9, 0.5), Color("747b68"))
			_fixture_box(root, "CrateUpper", Vector3(3.4, 2.2, 3.6), Vector3(2.8, 6.4, 0.4), Color("89918c"))
			var drum := CylinderMesh.new()
			drum.top_radius = 1.4
			drum.bottom_radius = 1.4
			drum.height = 2.8
			drum.radial_segments = 12
			_fixture_part(root, "CargoDrum", drum, Vector3(2.7, 2.1, 0.5), Color("626e70"))
		VaultBuilding.Kind.GROW_TRAY:
			_fixture_box(root, "Plinth", Vector3(8.8, 1.8, 6.8), Vector3(0, 0.9, 0), dark_steel)
			_fixture_box(root, "Trough", Vector3(11.0, 2.4, 9.0), Vector3(0, 3.0, 0), Color("89938d"))
			_fixture_box(root, "Soil", Vector3(8.8, 0.25, 7.2), Vector3(-0.5, 4.12, 0), Color("51483a"))
			_fixture_box(root, "CropLeft", Vector3(2.0, 1.4, 5.2), Vector3(-3.5, 4.9, 0), Color("638153"))
			_fixture_box(root, "CropMiddle", Vector3(2.0, 1.8, 5.0), Vector3(-0.7, 5.1, 0), Color("78955c"))
			_fixture_box(root, "CropRight", Vector3(2.0, 1.3, 5.2), Vector3(2.1, 4.85, 0), Color("58794e"))
			_fixture_box(root, "EndReservoir", Vector3(1.4, 3.0, 8.0), Vector3(4.7, 3.3, 0), Color("657f83"))
		VaultBuilding.Kind.AIR_RECYCLER:
			_fixture_box(root, "Skid", Vector3(10.0, 0.8, 9.0), Vector3(0, 0.4, 0), dark_steel)
			var filter := CylinderMesh.new()
			filter.top_radius = 2.5
			filter.bottom_radius = 2.5
			filter.height = 8.0
			filter.radial_segments = 12
			_fixture_part(root, "Filter", filter, Vector3(-2.0, 4.8, -0.7), Color("8a9c99"))
			_fixture_box(root, "FilterCap", Vector3(5.8, 1.0, 5.8), Vector3(-2.0, 9.3, -0.7), steel)
			_fixture_box(root, "Blower", Vector3(3.6, 4.2, 6.0), Vector3(3.0, 2.9, 0.8), Color("697b80"))
			_fixture_box(root, "Duct", Vector3(3.0, 1.8, 2.4), Vector3(1.2, 5.5, -0.7), steel)
			_fixture_box(root, "Intake", Vector3(2.8, 2.8, 0.2), Vector3(3.0, 3.0, 3.9), dark_steel)
		VaultBuilding.Kind.RECREATION_CONSOLE:
			_fixture_box(root, "Foot", Vector3(8.0, 0.8, 6.4), Vector3(0, 0.4, 0), dark_steel)
			_fixture_box(root, "Pedestal", Vector3(5.8, 4.0, 4.8), Vector3(0, 2.8, -0.5), steel)
			_fixture_box(root, "ControlDeck", Vector3(10.0, 0.8, 8.0), Vector3(0, 5.2, 0), Color("89938d"))
			_fixture_box(root, "ScreenHousing", Vector3(8.0, 3.4, 0.8), Vector3(0, 7.3, -2.8), dark_steel)
			# The inset face looks toward +Z; muted albedo only, no emission.
			_fixture_box(root, "ScreenFace", Vector3(6.8, 2.4, 0.12), Vector3(0, 7.3, -2.34), Color("54768d"))
			_fixture_box(root, "ControlStrip", Vector3(6.8, 0.15, 1.0), Vector3(0, 5.675, 2.0), Color("505e68"))
		VaultBuilding.Kind.MEDICAL_BED:
			_fixture_box(root, "Pedestal", Vector3(4.8, 2.6, 8.0), Vector3(0, 1.3, 0), steel)
			_fixture_box(root, "Deck", Vector3(8.6, 0.8, 14.0), Vector3(0, 3.0, 0), Color("a4b5b5"))
			_fixture_box(root, "Mattress", Vector3(7.2, 1.0, 12.6), Vector3(0, MEDICAL_MATTRESS_TOP - 0.5, 0), Color("dce5e1"))
			_fixture_box(root, "Pillow", Vector3(5.4, 0.6, 2.4), Vector3(0, 4.7, -4.7), Color("eef0e7"))
			_fixture_box(root, "RailLeft", Vector3(0.55, 1.8, 6.0), Vector3(-4.05, 4.3, 0.8), Color("bbc9ca"))
			_fixture_box(root, "RailRight", Vector3(0.55, 1.8, 6.0), Vector3(4.05, 4.3, 0.8), Color("bbc9ca"))
			_fixture_box(root, "HeadEquipment", Vector3(3.2, 2.6, 1.6), Vector3(2.6, 4.7, -6.7), Color("8aabaa"))
	return root


func _fixture_box(root: Node3D, part_name: String, size: Vector3, center: Vector3, color: Color, emitter := false) -> void:
	var box := BoxMesh.new()
	box.size = size
	_fixture_part(root, part_name, box, center, color, emitter)


func _fixture_part(root: Node3D, part_name: String, mesh: PrimitiveMesh, center: Vector3, color: Color, emitter := false) -> void:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.position = center
	var mat := _make_mat(color)
	mat.emission = color if emitter else Color.BLACK
	mat.emission_energy_multiplier = 0.25 if emitter else 0.0
	part.material_override = mat
	# Immutable palette data, independent of the live material altered by sync.
	part.set_meta("original_albedo", color)
	part.set_meta("original_emission", mat.emission)
	part.set_meta("original_emission_energy", mat.emission_energy_multiplier)
	part.set_meta("powered_emitter", emitter)
	root.add_child(part)


func _sync_fixture_appearance(root: Node3D, building: VaultBuilding) -> void:
	var inactive := building.is_power_consumer() and (not building.powered or building.manually_disabled)
	for part: MeshInstance3D in root.get_children():
		var mat := part.material_override as StandardMaterial3D
		var color: Color = part.get_meta("original_albedo")
		if not building.complete:
			color.a = 0.55
		elif inactive:
			color = color.darkened(0.35)
		mat.albedo_color = color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if building.complete else BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission = part.get_meta("original_emission")
		mat.emission_energy_multiplier = part.get_meta("original_emission_energy")
		mat.emission_enabled = bool(part.get_meta("powered_emitter")) and building.complete and building.powered and not building.manually_disabled


func _building_color_for_kind(kind: int) -> Color:
	match kind:
		VaultBuilding.Kind.BED:
			return Color(0.47, 0.64, 0.72)
		VaultBuilding.Kind.LAMP:
			return Color(0.94, 0.79, 0.41)
		VaultBuilding.Kind.GENERATOR:
			return Color(0.38, 0.80, 0.72)
		VaultBuilding.Kind.GROW_TRAY:
			return Color(0.45, 0.72, 0.42)
		VaultBuilding.Kind.KITCHEN:
			return Color(0.84, 0.85, 0.84)
		VaultBuilding.Kind.STOCKPILE:
			return Color(0.72, 0.55, 0.32)
		VaultBuilding.Kind.AIR_RECYCLER:
			return Color(0.56, 0.80, 0.83)
		VaultBuilding.Kind.RECREATION_CONSOLE:
			return Color(0.71, 0.54, 0.77)
		VaultBuilding.Kind.MEDICAL_BED:
			return Color(0.85, 0.87, 0.88)
	return Color.WHITE
