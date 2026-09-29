class_name MapView3D
extends Node3D

## Placeholder 3D play surface. MapGrid remains logic authority (including hex BFS
## find_path). This node only mirrors tiles/actors for Camera3D viewing and
## screen→hex picking. Colonists use a single CapsuleMesh pill — nothing else.

const ROCK_HEIGHT := 6.0
const FLOOR_HEIGHT := 0.55
const DIG_HEIGHT := 5.2
const CAMERA_HEIGHT := 380.0
const CAMERA_BACK := 300.0
const CAMERA_SIDE := 40.0
const HEX_MESH_YAW_DEGREES := 0.0
const COLONIST_RADIUS := 3.2
const COLONIST_HEIGHT := 8.0

var map_grid: MapGrid
var lighting_system: LightingSystem

@onready var camera_3d: Camera3D = $Camera3D
@onready var hex_root: Node3D = $HexRoot
@onready var actor_root: Node3D = $ActorRoot
@onready var fixture_root: Node3D = $FixtureRoot
@onready var marker_root: Node3D = $MarkerRoot

var _last_map_signature := ""
var _resident_proxies: Dictionary = {}
var _building_proxies: Dictionary = {}
var _hatch_proxy: MeshInstance3D
var _shared_hex_mesh: CylinderMesh
var _mat_rock: StandardMaterial3D
var _mat_rock_border: StandardMaterial3D
var _mat_floor: StandardMaterial3D
var _mat_floor_dark: StandardMaterial3D
var _mat_dig: StandardMaterial3D
var _mat_zone: StandardMaterial3D
var _mat_hover_ok: StandardMaterial3D
var _mat_hover_bad: StandardMaterial3D
var _mat_colonist: StandardMaterial3D
var _mat_colonist_selected: StandardMaterial3D
var _mat_colonist_dead: StandardMaterial3D
var _mat_hatch: StandardMaterial3D


func _ready() -> void:
	_ensure_materials()
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
		_mat_rock = _make_mat(Color(0.16, 0.14, 0.13))
		_mat_rock_border = _make_mat(Color(0.125, 0.17, 0.20))
		_mat_floor = _make_mat(Color(0.18, 0.27, 0.31))
		_mat_floor_dark = _make_mat(Color(0.08, 0.11, 0.14))
		_mat_dig = _make_mat(Color(0.85, 0.55, 0.18))
		_mat_zone = _make_mat(Color(0.28, 0.62, 0.70))
		_mat_hover_ok = _make_mat(Color(0.35, 0.85, 0.65))
		_mat_hover_bad = _make_mat(Color(0.90, 0.30, 0.28))
		_mat_colonist = _make_mat(Color(0.44, 0.78, 0.71))
		_mat_colonist_selected = _make_mat(Color(0.96, 0.78, 0.30))
		_mat_colonist_dead = _make_mat(Color(0.38, 0.41, 0.42))
		_mat_hatch = _make_mat(Color(0.75, 0.35, 0.28))


func _make_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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
			hex_root.add_child(_make_hex_instance(Vector2i(x, y)))


func _map_signature() -> String:
	var hover := map_grid.hover_cell
	var dig_bits := map_grid.dig_marks.size()
	var zone_bits := map_grid.stockpile_cells.size()
	var lit_bits := 0
	if lighting_system != null and is_instance_valid(lighting_system):
		lit_bits = lighting_system.get_lit_floor_count()
		if lighting_system.is_coverage_overlay_visible():
			lit_bits += 100000
	return "%d:%d:%d:%d:%d:%s:%d" % [
		map_grid.topology_revision,
		dig_bits,
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
		height = DIG_HEIGHT if map_grid.dig_marks.has(cell) else ROCK_HEIGHT
		if map_grid.is_border(cell):
			mat = _mat_rock_border
		elif map_grid.dig_marks.has(cell):
			mat = _mat_dig
		else:
			mat = _mat_rock
	else:
		if map_grid.stockpile_cells.has(cell):
			mat = _mat_zone
		elif lighting_system != null and is_instance_valid(lighting_system) and lighting_system.is_floor_dark(cell):
			mat = _mat_floor_dark
		else:
			mat = _mat_floor
	if cell == map_grid.hover_cell and map_grid.preview_tool != "select":
		mat = _mat_hover_ok if map_grid.is_preview_valid(map_grid.preview_tool, cell) else _mat_hover_bad
		if is_rock:
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


func sync_actors(residents: Array[VaultResident], buildings: Array[VaultBuilding], show_hatch: bool) -> void:
	_ensure_materials()
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
		proxy.position = Vector3(pos.x, COLONIST_HEIGHT * 0.5, pos.y)
		if not resident.alive:
			proxy.material_override = _mat_colonist_dead
		elif resident.selected:
			proxy.material_override = _mat_colonist_selected
		else:
			proxy.material_override = _mat_colonist
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
		var proxy: MeshInstance3D = _building_proxies.get(building.building_id)
		if proxy == null or not is_instance_valid(proxy):
			proxy = _make_building_proxy(building.kind)
			fixture_root.add_child(proxy)
			_building_proxies[building.building_id] = proxy
		var center := MapGrid.offset_cell_to_world(building.cell)
		proxy.position = Vector3(center.x, 2.2 if building.complete else 1.4, center.y)
		proxy.scale = Vector3.ONE * (1.0 if building.complete else 0.75)
		var color := _building_color(building)
		if proxy.material_override is StandardMaterial3D:
			(proxy.material_override as StandardMaterial3D).albedo_color = color
	for id: Variant in _building_proxies.keys():
		if live_buildings.has(id):
			continue
		var stale_b: MeshInstance3D = _building_proxies[id]
		if is_instance_valid(stale_b):
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


func _make_building_proxy(kind: int) -> MeshInstance3D:
	var proxy := MeshInstance3D.new()
	if (
		kind == VaultBuilding.Kind.LAMP
		or kind == VaultBuilding.Kind.GENERATOR
		or kind == VaultBuilding.Kind.AIR_RECYCLER
	):
		var cyl := CylinderMesh.new()
		cyl.top_radius = 4.0
		cyl.bottom_radius = 4.0
		cyl.height = 5.0
		cyl.radial_segments = 10
		proxy.mesh = cyl
	else:
		var box := BoxMesh.new()
		box.size = Vector3(10.0, 4.5, 10.0)
		proxy.mesh = box
	proxy.material_override = _make_mat(_building_color_for_kind(kind))
	return proxy


func _building_color(building: VaultBuilding) -> Color:
	var color := _building_color_for_kind(building.kind)
	if not building.complete:
		color.a = 0.55
	elif building.get_power_demand() > 0 and not building.powered:
		color = color.darkened(0.35)
	return color


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
