class_name EmberDashTrailSegment
extends Area3D

## Flat ground burn segment left by Ember Wretch dash. Slow + DPS stub on overlap.

const SegmentScript := preload("res://scripts/monsters/abilities/ember_dash_trail_segment.gd")

const GROUND_Y := 0.045

var _lifetime_sec: float = 4.0
var _burn_dps: float = 6.0
var _burn_slow_multiplier: float = 0.75
var _burn_refresh_sec: float = 0.5
var _age: float = 0.0


static func spawn(
	parent: Node,
	position: Vector3,
	direction: Vector3,
	width: float,
	length: float,
	lifetime_sec: float,
	burn_dps: float,
	burn_slow_multiplier: float,
	burn_refresh_sec: float
) -> Area3D:
	var seg: Area3D = SegmentScript.new()
	seg._lifetime_sec = lifetime_sec
	seg._burn_dps = burn_dps
	seg._burn_slow_multiplier = burn_slow_multiplier
	seg._burn_refresh_sec = burn_refresh_sec
	parent.add_child(seg)
	seg._build_visual(width, length)
	seg.global_position = Vector3(position.x, GROUND_Y, position.z)
	if direction.length_squared() > 0.0001:
		var flat := Vector3(direction.x, 0.0, direction.z).normalized()
		seg.rotation.y = atan2(flat.x, flat.z)
	seg.monitoring = true
	seg.monitorable = false
	seg.collision_layer = 0
	seg.collision_mask = 1 | 2
	seg.set_physics_process(true)
	return seg


func _build_visual(width: float, length: float) -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, 0.02, maxf(length, 0.2))
	mesh_inst.mesh = box
	mesh_inst.position = Vector3(0.0, 0.01, box.size.z * 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.95, 0.12, 0.06, 0.82)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.15, 0.05)
	mat.emission_energy_multiplier = 2.2
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_inst)

	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 0.35, maxf(length, 0.2))
	shape_node.shape = shape
	shape_node.position = Vector3(0.0, 0.12, box.size.z * 0.5)
	add_child(shape_node)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= _lifetime_sec:
		queue_free()
		return
	for body in get_overlapping_bodies():
		_apply_burn(body)


func _on_body_entered(body: Node3D) -> void:
	_apply_burn(body)


func _apply_burn(body: Node3D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	var apply_local := true
	var state := get_tree().root.get_node_or_null("GameState") if get_tree() != null else null
	var mp := state != null and bool(state.get("is_multiplayer"))
	if mp and body is Node:
		apply_local = (body as Node).is_multiplayer_authority()
	if apply_local and body.has_method("apply_ember_trail_burn"):
		body.call(
			"apply_ember_trail_burn",
			_burn_dps,
			_burn_slow_multiplier,
			_burn_refresh_sec
		)
