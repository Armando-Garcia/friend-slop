@tool
class_name CloudSystem
extends Node3D

## Deterministic cloud layer: picks from a fixed mesh pool and drifts across the sky.

const CloudStateScript := preload("res://scripts/environment/cloud_state.gd")
const CloudMeshBuilderScript := preload("res://scripts/environment/cloud_mesh_builder.gd")
const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")
const CloudMaterial := preload("res://materials/environment/cloud.tres")
const CloudScene := preload("res://scenes/environment/cloud.tscn")

const DEFAULT_CLOUD_MESHES: Array[Mesh] = [
	preload("res://assets/environment/clouds/cloud_01.res"),
	preload("res://assets/environment/clouds/cloud_02.res"),
	preload("res://assets/environment/clouds/cloud_03.res"),
	preload("res://assets/environment/clouds/cloud_04.res"),
	preload("res://assets/environment/clouds/cloud_05.res"),
	preload("res://assets/environment/clouds/cloud_06.res"),
	preload("res://assets/environment/clouds/cloud_07.res"),
	preload("res://assets/environment/clouds/cloud_08.res"),
]

const CLOUD_SALT := "clouds"
const BASE_CLOUD_RADIUS := CloudMeshBuilderScript.REFERENCE_RADIUS
const MIN_CLOUD_RADIUS := 16.0
const MAX_CLOUD_RADIUS := 48.0
const WIND_GIZMO_NAME := "WindDirectionGizmo"
const EDITOR_PREVIEW_SEED := 4242
## Safety cap so huge spawn areas cannot spawn unbounded instances.
const COUNT_HARD_MAX := 600
## Random placement overlaps, so we over-cover the plane to make coverage 1.0 look full.
const COVERAGE_OVERFILL := 2.0
## Typical instance scale used when estimating each cloud's XZ footprint.
const COVERAGE_RADIUS_SCALE := 1.15

## Fixed cloud spawn box size (X = width, Y = band thickness, Z = depth).
@export var spawn_size: Vector3 = Vector3(680.0, 40.0, 680.0):
	set(value):
		spawn_size = Vector3(
			maxf(value.x, 1.0),
			maxf(value.y, 1.0),
			maxf(value.z, 1.0)
		)
		_request_editor_cloud_rebuild()
## World Y of the spawn box center.
@export var spawn_center_y: float = 120.0:
	set(value):
		spawn_center_y = value
		_request_editor_cloud_rebuild()
## Fraction of the spawn XZ plane covered by clouds (1 = sky packed full).
@export_range(0.0, 1.0, 0.01) var sky_coverage: float = 0.25:
	set(value):
		sky_coverage = value
		_request_editor_cloud_rebuild()
## Constant wind speed on XZ (world units per second).
@export var wind_speed: float = 4.5:
	set(value):
		wind_speed = maxf(value, 0.0)
		if not _configured:
			return
		_apply_wind_velocity()
		if Engine.is_editor_hint():
			# Restart drift clock so the new speed is obvious immediately.
			_match_start_time_msec = Time.get_ticks_msec()
			_update_wind_gizmo()
## Compass heading for wind on the XZ plane (0° = +X, 90° = +Z).
@export_range(0.0, 360.0, 1.0, "degrees") var wind_direction: float = 35.0:
	set(value):
		wind_direction = value
		if not _configured:
			_update_wind_gizmo()
			return
		_apply_wind_velocity()
		if Engine.is_editor_hint():
			_update_wind_gizmo()
## Override pool in the inspector; empty uses the baked default set.
@export var meshes: Array[Mesh] = []:
	set(value):
		meshes = value
		_request_editor_cloud_rebuild()

var _clouds: Array[CloudState] = []
var _bounds_min: Vector3 = Vector3.ZERO
var _bounds_max: Vector3 = Vector3.ZERO
var _travel_span: float = 0.0
var _match_start_time_msec: int = 0
var _last_run_seed: int = -1
var _last_moon_height: float = -1.0
var _configured: bool = false
var _editor_rebuild_queued: bool = false
var _shared_drift_velocity: Vector3 = Vector3.ZERO
var _cloud_holder: Node3D = null
var _shadow_material: StandardMaterial3D = null
var _wind_gizmo: MeshInstance3D = null


func _create_cloud_holder() -> Node3D:
	var holder := Node3D.new()
	holder.name = "Clouds"
	return holder


func _ready() -> void:
	_ensure_holder_in_tree()
	if Engine.is_editor_hint():
		call_deferred("_editor_ensure_preview_clouds")
	else:
		_free_wind_gizmo()


func _editor_ensure_preview_clouds() -> void:
	## Standalone / post-reload safety: show clouds even if Main hasn't configured yet.
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _configured and get_cloud_count() > 0:
		_update_wind_gizmo()
		return
	configure_from_spawn_area(EDITOR_PREVIEW_SEED, 0, _last_moon_height)


func _request_editor_cloud_rebuild() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _editor_rebuild_queued:
		return
	_editor_rebuild_queued = true
	call_deferred("_editor_rebuild_clouds")


func _editor_rebuild_clouds() -> void:
	_editor_rebuild_queued = false
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	configure_from_spawn_area(_last_run_seed, 0, _last_moon_height)


func _wind_direction_vector() -> Vector3:
	var radians := deg_to_rad(wind_direction)
	return Vector3(cos(radians), 0.0, sin(radians))


func _apply_wind_velocity() -> void:
	_shared_drift_velocity = _wind_direction_vector() * wind_speed
	for state in _clouds:
		state.velocity = _shared_drift_velocity


func _free_wind_gizmo() -> void:
	if _wind_gizmo != null and is_instance_valid(_wind_gizmo):
		if _wind_gizmo.get_parent() != null:
			_wind_gizmo.get_parent().remove_child(_wind_gizmo)
		_wind_gizmo.free()
	_wind_gizmo = null
	var existing := get_node_or_null(WIND_GIZMO_NAME)
	if existing != null:
		existing.get_parent().remove_child(existing)
		existing.free()


func _update_wind_gizmo() -> void:
	## Editor-only ray. Never created (and freed if present) at runtime.
	if not Engine.is_editor_hint():
		_free_wind_gizmo()
		return
	if not is_inside_tree():
		return

	if _wind_gizmo == null or not is_instance_valid(_wind_gizmo):
		_wind_gizmo = get_node_or_null(WIND_GIZMO_NAME) as MeshInstance3D
	if _wind_gizmo == null:
		_wind_gizmo = MeshInstance3D.new()
		_wind_gizmo.name = WIND_GIZMO_NAME
		var cyl := CylinderMesh.new()
		cyl.top_radius = 2.5
		cyl.bottom_radius = 2.5
		cyl.height = 1.0
		_wind_gizmo.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.85, 0.2, 0.95)
		mat.disable_fog = true
		_wind_gizmo.material_override = mat
		_wind_gizmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_wind_gizmo)

	var dir := _wind_direction_vector()
	# Length scales with speed so inspector tweaks are visible on the gizmo.
	var arrow_length := maxf(wind_speed * 25.0, 8.0)
	var cyl_mesh := _wind_gizmo.mesh as CylinderMesh
	if cyl_mesh != null:
		cyl_mesh.height = arrow_length

	var mid := Vector3.ZERO
	if _configured:
		mid = (_bounds_min + _bounds_max) * 0.5
	else:
		mid = Vector3(0.0, 100.0, 0.0)

	_wind_gizmo.visible = true
	_wind_gizmo.position = mid
	# CylinderMesh extends along +Y; looking_at aims -Z, then tip it onto wind.
	_wind_gizmo.basis = Basis.looking_at(dir, Vector3.UP)
	_wind_gizmo.rotate_object_local(Vector3.RIGHT, -PI * 0.5)


func _ensure_holder_in_tree() -> void:
	if _cloud_holder != null and is_instance_valid(_cloud_holder):
		if _cloud_holder.get_parent() == null:
			add_child(_cloud_holder)
		return
	# Reclaim a leftover holder after @tool script reload.
	var existing := get_node_or_null("Clouds") as Node3D
	if existing != null:
		_cloud_holder = existing
		return
	_cloud_holder = _create_cloud_holder()
	add_child(_cloud_holder)


func configure_for_maze(
	_maze_width: int,
	_maze_height: int,
	_cell_size: float,
	moon_height: float,
	run_seed: int = -1,
	start_time_msec: int = 0
) -> void:
	## Maze size is ignored — spawn box is a fixed CloudSystem setting.
	## Moon height only keeps the band from sitting above the moon.
	configure_from_spawn_area(run_seed, start_time_msec, moon_height)


func configure_from_spawn_area(
	run_seed: int = -1,
	start_time_msec: int = 0,
	moon_height: float = -1.0
) -> void:
	if moon_height > 0.0:
		_last_moon_height = moon_height
	var half := spawn_size * 0.5
	var center_y := spawn_center_y
	var height_cap := moon_height if moon_height > 0.0 else _last_moon_height
	if height_cap > 0.0:
		center_y = minf(center_y, maxf(height_cap * 0.5, half.y + 1.0))
	var center := Vector3(0.0, center_y, 0.0)
	var bounds_min := center - half
	var bounds_max := center + half
	var travel_span := maxf(spawn_size.x, spawn_size.z)
	configure(bounds_min, bounds_max, run_seed, start_time_msec, travel_span)


func configure(
	bounds_min: Vector3,
	bounds_max: Vector3,
	run_seed: int = -1,
	start_time_msec: int = 0,
	travel_span: float = -1.0
) -> void:
	_ensure_holder_in_tree()
	_clear_clouds()
	_bounds_min = bounds_min
	_bounds_max = bounds_max
	_travel_span = travel_span if travel_span > 0.0 else maxf(
		_bounds_max.x - _bounds_min.x,
		_bounds_max.z - _bounds_min.z
	)
	_last_run_seed = run_seed
	# Keep editor preview time advancing from "now" so clouds drift live.
	if Engine.is_editor_hint():
		_match_start_time_msec = Time.get_ticks_msec()
	else:
		_match_start_time_msec = (
			start_time_msec if start_time_msec > 0 else Time.get_ticks_msec()
		)
	_configured = true

	var cloud_seed := _derive_seed(run_seed)
	seed(cloud_seed)

	var cloud_count := _cloud_count_for_sky_area()
	_clouds = _generate_cloud_states(cloud_count)
	for state in _clouds:
		var instance := _create_cloud_instance(state)
		instance.name = "Cloud_%d" % state.index
		_cloud_holder.add_child(instance)

	set_process(true)
	_update_cloud_transforms(_elapsed_seconds())
	_update_wind_gizmo()


func get_travel_span() -> float:
	return _travel_span


func get_bounds_min() -> Vector3:
	return _bounds_min


func get_bounds_max() -> Vector3:
	return _bounds_max


func get_shared_drift_velocity() -> Vector3:
	return _shared_drift_velocity


func is_configured() -> bool:
	return _configured


func _derive_seed(run_seed: int) -> int:
	return hash("%d:%s" % [run_seed, CLOUD_SALT])


func _spawnable_sky_area() -> float:
	## Horizontal footprint of the spawn box (from fixed spawn_size in normal use).
	var size := _bounds_max - _bounds_min
	return maxf(size.x, 1.0) * maxf(size.z, 1.0)


func _cloud_footprint_area() -> float:
	## Top-down disk for a typical-sized cloud instance.
	var radius := BASE_CLOUD_RADIUS * COVERAGE_RADIUS_SCALE
	return PI * radius * radius


func _cloud_count_for_sky_area() -> int:
	## coverage 1.0 → total cloud disk area ≈ sky area * overfill (looks packed on XZ).
	var raw := (
		_spawnable_sky_area() * sky_coverage * COVERAGE_OVERFILL
		/ maxf(_cloud_footprint_area(), 1.0)
	)
	if raw < 0.5:
		return 0
	return clampi(int(round(raw)), 1, COUNT_HARD_MAX)


func _mesh_pool() -> Array[Mesh]:
	if meshes.size() > 0:
		return meshes
	return DEFAULT_CLOUD_MESHES


func _generate_cloud_states(count_value: int) -> Array[CloudState]:
	var states: Array[CloudState] = []
	var size := _bounds_max - _bounds_min
	var wind_radians := deg_to_rad(wind_direction)
	_shared_drift_velocity = Vector3(
		cos(wind_radians) * wind_speed,
		0.0,
		sin(wind_radians) * wind_speed
	)
	var pool := _mesh_pool()
	var pool_size := maxi(pool.size(), 1)

	for i in count_value:
		var state := CloudStateScript.new()
		state.index = i
		state.base_position = Vector3(
			_bounds_min.x + randf() * size.x,
			_bounds_min.y + randf() * size.y,
			_bounds_min.z + randf() * size.z
		)
		state.velocity = _shared_drift_velocity

		var radius_scale := 0.75 + randf() * 0.85
		state.radius = clampf(BASE_CLOUD_RADIUS * radius_scale, MIN_CLOUD_RADIUS, MAX_CLOUD_RADIUS)
		state.mesh_index = posmod(hash("%d:%s" % [i, CLOUD_SALT]), pool_size)
		state.arc_amplitude = state.radius * (0.12 + randf() * 0.18)
		state.arc_wavelength = _travel_span * (0.35 + randf() * 0.25)
		state.arc_phase = randf() * TAU
		states.append(state)

	return states


func _create_cloud_instance(state: CloudState) -> Node3D:
	var pool := _mesh_pool()
	var mesh: Mesh = null
	if pool.size() > 0:
		mesh = pool[state.mesh_index % pool.size()]
	var root: Node3D = CloudScene.instantiate()
	var mesh_instance := root.get_node_or_null("Mesh") as MeshInstance3D
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "Mesh"
		root.add_child(mesh_instance)
	mesh_instance.mesh = mesh
	mesh_instance.material_override = CloudMaterial
	# Visual mesh stays translucent; opaque proxy handles moonlight shadows.
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.layers = WorldVisualLayersScript.WORLD
	mesh_instance.extra_cull_margin = MAX_CLOUD_RADIUS * 2.0

	var shadow_caster := MeshInstance3D.new()
	shadow_caster.name = "ShadowCaster"
	# AABB box proxy — same rough footprint as the cloud, far fewer shadow-map tris.
	# Full voxel meshes swimming through CSM cascades are a major flicker source.
	shadow_caster.mesh = _shadow_proxy_mesh(mesh)
	if mesh != null:
		shadow_caster.position = mesh.get_aabb().get_center()
	shadow_caster.material_override = _opaque_shadow_material()
	shadow_caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	shadow_caster.layers = WorldVisualLayersScript.WORLD
	shadow_caster.extra_cull_margin = MAX_CLOUD_RADIUS * 2.0
	root.add_child(shadow_caster)

	var scale_factor := state.radius / CloudMeshBuilderScript.REFERENCE_RADIUS
	root.scale = Vector3.ONE * scale_factor
	return root


func _shadow_proxy_mesh(source_mesh: Mesh) -> Mesh:
	if source_mesh == null:
		var fallback := SphereMesh.new()
		fallback.radius = 1.0
		fallback.height = 2.0
		return fallback
	var aabb := source_mesh.get_aabb()
	var box := BoxMesh.new()
	# Slightly inflate so soft filter still covers the visual silhouette.
	box.size = aabb.size * 1.05
	return box


func _opaque_shadow_material() -> StandardMaterial3D:
	## Opaque material so DirectionalLight shadow maps include cloud silhouettes.
	if _shadow_material != null:
		return _shadow_material
	_shadow_material = StandardMaterial3D.new()
	_shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_material.albedo_color = Color(1, 1, 1, 1)
	_shadow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _shadow_material


func _process(_delta: float) -> void:
	if not _configured:
		return
	_update_cloud_transforms(_elapsed_seconds())


func _elapsed_seconds() -> float:
	if _match_start_time_msec == 0:
		return 0.0
	return (Time.get_ticks_msec() - _match_start_time_msec) / 1000.0


func _update_cloud_transforms(elapsed_sec: float) -> void:
	var children := _cloud_holder.get_children()
	for i in _clouds.size():
		if i >= children.size():
			break
		var state: CloudState = _clouds[i]
		var instance: Node3D = children[i] as Node3D
		if instance == null:
			continue
		instance.position = state.position_at(elapsed_sec, _bounds_min, _bounds_max)


func _clear_clouds() -> void:
	_clouds.clear()
	_shared_drift_velocity = Vector3.ZERO
	if _cloud_holder == null:
		return
	# Free immediately — queue_free is deferred and would leave new clouds at
	# the origin while transforms get applied to the dying nodes.
	while _cloud_holder.get_child_count() > 0:
		var child := _cloud_holder.get_child(0)
		_cloud_holder.remove_child(child)
		child.free()


func get_cloud_count() -> int:
	return _clouds.size()


func get_cloud_state(index: int) -> CloudState:
	if index < 0 or index >= _clouds.size():
		return null
	return _clouds[index]
