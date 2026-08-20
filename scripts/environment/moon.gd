@tool
class_name Moon
extends Node3D

## Physical moon above the maze; moonlight is a child DirectionalLight3D.
##
## Place the moon with its transform. The light always casts from the moon
## toward the maze origin (same in editor and gameplay).

const LIGHT_ARROW_NAME := "LightDirectionArrow"
const LIGHT_ARROW_LENGTH := 80.0

## Editor-only arrow showing which way moonlight is cast.
@export var show_light_arrow: bool = true:
	set(value):
		show_light_arrow = value
		_update_light_arrow()

var _light_arrow: MeshInstance3D = null

@onready var moon_light: DirectionalLight3D = $MoonLight


func _get_moon_light() -> DirectionalLight3D:
	if moon_light != null:
		return moon_light
	return get_node_or_null("MoonLight") as DirectionalLight3D


func _ready() -> void:
	set_notify_transform(true)
	if Engine.is_editor_hint():
		_sync_light_from_moon_position()
		return
	_free_light_arrow()
	_sync_light_from_moon_position()
	_configure_moon_light()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_sync_light_from_moon_position()


func light_cast_direction() -> Vector3:
	## Unit vector along moonlight rays (moon → maze origin).
	var to_origin := -global_position if is_inside_tree() else -position
	if to_origin.length_squared() < 0.0001:
		return Vector3.DOWN
	return to_origin.normalized()


func _sync_light_from_moon_position() -> void:
	if not is_inside_tree():
		return
	var light := _get_moon_light()
	if light == null or not light.is_inside_tree():
		return
	var cast_dir := light_cast_direction()
	## Avoid look_at colinear warnings when the moon sits nearly straight up.
	var up := Vector3.UP
	if absf(cast_dir.dot(up)) > 0.95:
		up = Vector3.RIGHT
	light.look_at(light.global_position + cast_dir, up)
	_update_light_arrow()


func _free_light_arrow() -> void:
	if _light_arrow != null and is_instance_valid(_light_arrow):
		if _light_arrow.get_parent() != null:
			_light_arrow.get_parent().remove_child(_light_arrow)
		_light_arrow.free()
	_light_arrow = null
	var existing := get_node_or_null(LIGHT_ARROW_NAME)
	if existing != null:
		existing.get_parent().remove_child(existing)
		existing.free()


func _update_light_arrow() -> void:
	## Editor-only cast-direction gizmo. Never kept at runtime.
	if not Engine.is_editor_hint():
		_free_light_arrow()
		return
	if not show_light_arrow:
		_free_light_arrow()
		return
	if not is_inside_tree():
		return

	if _light_arrow == null or not is_instance_valid(_light_arrow):
		_light_arrow = get_node_or_null(LIGHT_ARROW_NAME) as MeshInstance3D
	if _light_arrow == null:
		_light_arrow = MeshInstance3D.new()
		_light_arrow.name = LIGHT_ARROW_NAME
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.8
		cyl.bottom_radius = 3.2
		cyl.height = 1.0
		_light_arrow.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.92, 0.35, 0.95)
		mat.disable_fog = true
		_light_arrow.material_override = mat
		_light_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_light_arrow.set_meta("_edit_lock_", true)
		add_child(_light_arrow)

	var cast_dir := light_cast_direction()
	# Arrow is a child of Moon, so convert world cast dir into moon local space.
	var local_cast := cast_dir
	if not global_transform.basis.is_equal_approx(Basis.IDENTITY):
		local_cast = global_transform.basis.inverse() * cast_dir
	if local_cast.length_squared() < 0.0001:
		local_cast = Vector3.DOWN
	else:
		local_cast = local_cast.normalized()

	var cyl_mesh := _light_arrow.mesh as CylinderMesh
	if cyl_mesh != null:
		cyl_mesh.height = LIGHT_ARROW_LENGTH

	_light_arrow.visible = true
	_light_arrow.position = local_cast * (LIGHT_ARROW_LENGTH * 0.5)
	var arrow_up := Vector3.UP
	if absf(local_cast.dot(arrow_up)) > 0.95:
		arrow_up = Vector3.RIGHT
	_light_arrow.basis = Basis.looking_at(local_cast, arrow_up)
	_light_arrow.rotate_object_local(Vector3.RIGHT, -PI * 0.5)


func _configure_moon_light() -> void:
	var light := _get_moon_light()
	if light == null:
		return
	# Light + shadow both WORLD and PLAYER_SELF so characters receive moonlight shading.
	light.light_cull_mask = WorldVisualLayers.SCENE_LIGHT_MASK
	light.shadow_caster_mask = WorldVisualLayers.SCENE_LIGHT_MASK
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.directional_shadow_blend_splits = true
	# Near-biased splits: player-in-maze POV needs stable floor coverage first.
	light.directional_shadow_split_1 = 0.18
	light.directional_shadow_split_2 = 0.42
	light.directional_shadow_split_3 = 0.72
	# Pancake restores depth precision for high cloud → floor rays (0 caused swim/flicker).
	light.directional_shadow_pancake_size = 28.0
	light.directional_shadow_fade_start = 0.85
	light.light_angular_distance = 0.0
	light.shadow_blur = 0.6
	# Hard enough for moonlight, soft enough to hide cascade micro-jitter.
	light.shadow_bias = 0.12
	light.shadow_normal_bias = 2.2
	## Let moonlight scatter into volumetric fog (match WorldEnvironment).
	light.light_volumetric_fog_energy = 3.0
	_sync_light_from_moon_position()


func configure_for_maze(
	maze_width: int,
	maze_height: int,
	cell_size: float,
	cloud_field_size: Vector3 = Vector3.ZERO
) -> void:
	## Keeps the moon where you placed it; only syncs light + shadow distance.
	_configure_moon_light()
	var light := _get_moon_light()
	if light == null:
		return
	light.shadow_enabled = true
	var span_x := float(maze_width * 2 + 1) * cell_size
	var span_z := float(maze_height * 2 + 1) * cell_size
	var span := maxf(span_x, span_z)
	# Reach overhead clouds above the playable maze — not the full 1500-unit field edge.
	# Oversized max_distance is a common cause of DirectionalLight shadow flicker.
	var cloud_ceiling := maxf(cell_size * 52.0, 140.0)
	if cloud_field_size.y > 0.0:
		cloud_ceiling = maxf(cloud_ceiling, cloud_field_size.y + 40.0)
	var shadow_distance := maxf(span * 1.25, cloud_ceiling + span * 0.55)
	light.directional_shadow_max_distance = clampf(shadow_distance, 280.0, 400.0)
	light.directional_shadow_split_1 = 0.18
	light.directional_shadow_split_2 = 0.42
	light.directional_shadow_split_3 = 0.72
