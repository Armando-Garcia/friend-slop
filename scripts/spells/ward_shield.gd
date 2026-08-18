@tool
class_name WardShield
extends Node3D

## Forward-facing spherical-cap blue shield. Player wards spend spell hits;
## HP wards (Charger) absorb spell damage and tint red as they weaken.
## Open scenes/spells/ward.tscn (or ward_workspace.tscn) — select Ward root to edit Dome shape.
## Cast: tip beam (instant on detect) → rim bloom → dome form (see setup_cast).

const WardMeshBuilderScript := preload("res://scripts/spells/ward_mesh_builder.gd")
const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")
const SpellEphemeralFxScript := preload("res://scripts/spells/spell_ephemeral_fx.gd")

const GROUP := "spell_ward"
const DURATION_SEC := 1.0
## Kept for tests / callers that expect a class-level default size.
const RADIUS := 1.35
## Beam must read as immediate once the voice match resolves.
const CAST_TRAVEL_SEC := 0.05
const FORM_SEC := 0.08
const SHIELD_BLUE := Color(0.35, 0.65, 1.0, 0.38)
const SHIELD_EDGE := Color(0.55, 0.85, 1.0, 0.72)
const SHIELD_STRESS := Color(0.92, 0.12, 0.08, 0.42)
const SHIELD_STRESS_EDGE := Color(1.0, 0.25, 0.1, 1.0)

@export_group("Dome shape")
@export_range(0.25, 4.0, 0.05, "or_greater") var radius: float = 1.35:
	set(value):
		radius = maxf(value, 0.05)
		_rebuild_geometry()

@export_range(0.1, 0.9, 0.01) var surface_fraction: float = 0.333:
	set(value):
		surface_fraction = clampf(value, 0.05, 0.95)
		_rebuild_geometry()

@export_range(2, 32, 1) var ring_count: int = 10:
	set(value):
		ring_count = maxi(value, 2)
		_rebuild_geometry()

@export_range(3, 64, 1) var segment_count: int = 28:
	set(value):
		segment_count = maxi(value, 3)
		_rebuild_geometry()

var _body: StaticBody3D
var _mesh_instance: MeshInstance3D
var _collision_shape: CollisionShape3D
var _material: StandardMaterial3D
var _hits_remaining := 1
var _max_hp := 0.0
var _hp := 0.0
var _lifetime := 0.0
var _lifetime_active := false
## Instance duration; defaults to DURATION_SEC (player ward). Monster casts may extend.
var _duration_sec: float = DURATION_SEC
var _wand_origin := Vector3.ZERO
var _body_collision_layer := 1
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _rim: MeshInstance3D
var _rim_mat: StandardMaterial3D
var _cast_tween: Tween
var _held := false


static func spawn(
	parent: Node,
	origin: Vector3,
	direction: Vector3,
	hit_capacity: int = 1
) -> Node:
	## Lazy-load avoids circular preload with ward.tscn (which attaches this script).
	var packed: PackedScene = load("res://scenes/spells/ward.tscn") as PackedScene
	var ward: Node = packed.instantiate()
	if parent != null and ward is Node3D:
		SpellEphemeralFxScript.add_child_at(parent, ward as Node3D, origin)
	elif parent != null:
		parent.add_child(ward)
	if ward.has_method("setup_cast"):
		ward.call("setup_cast", origin, direction, hit_capacity)
	return ward


func set_duration_sec(seconds: float) -> void:
	_duration_sec = maxf(seconds, 0.05)


func hold_until_broken() -> void:
	## Keep the shield up until shatter() — used by the Charger ram.
	_held = true
	_lifetime_active = false


func set_hit_points(hp: float) -> void:
	## Damage-absorb mode. Survives until HP is spent; ignores hit-count.
	_max_hp = maxf(hp, 0.01)
	_hp = _max_hp
	_apply_integrity_color()


func shatter() -> void:
	_held = false
	_dissolve()


func _ready() -> void:
	_cache_nodes()
	_rebuild_geometry()
	add_to_group(GROUP)
	if _body != null:
		_body.add_to_group(GROUP)
		_body_collision_layer = _body.collision_layer
	if Engine.is_editor_hint() and not _lifetime_active:
		## Look-dev instance: stay static until setup_cast runs (workspace preview).
		set_process(false)
		return
	_ensure_runtime_material()


func _cache_nodes() -> void:
	_mesh_instance = get_node_or_null("Dome") as MeshInstance3D
	_body = get_node_or_null("Body") as StaticBody3D
	if _body != null:
		_collision_shape = _body.get_node_or_null("CollisionShape3D") as CollisionShape3D


func _rebuild_geometry() -> void:
	if not is_inside_tree() and not Engine.is_editor_hint():
		return
	if _mesh_instance == null or _collision_shape == null:
		_cache_nodes()
	if _mesh_instance == null:
		return
	_mesh_instance.mesh = WardMeshBuilderScript.build_mesh(
		radius, surface_fraction, ring_count, segment_count
	)
	if _collision_shape != null:
		_collision_shape.shape = WardMeshBuilderScript.build_collision_shape(
			radius, surface_fraction, ring_count, segment_count
		)


func setup_cast(origin: Vector3, direction: Vector3, hit_capacity: int = 1) -> void:
	var dir := direction
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	else:
		dir = dir.normalized()
	_wand_origin = origin
	## Sit the dome just ahead of the cast point, bulging toward the aim (-Z).
	var pos := origin + dir * (radius * 0.2)
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.95:
		up = Vector3.RIGHT
	global_transform = Transform3D(Basis.looking_at(dir, up), pos)
	_lifetime = 0.0
	_hits_remaining = maxi(hit_capacity, 1)
	_lifetime_active = false
	## Editor look-dev trees are often paused; keep cast FX + lifetime ticking.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_ensure_runtime_material()
	_prepare_for_cast_fx()
	_play_cast_sequence()


func _make_cast_tween() -> Tween:
	var tween := create_tween()
	## Bound tweens freeze while the editor scene tree is paused.
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return tween


func _ensure_runtime_material() -> void:
	if _mesh_instance == null:
		_cache_nodes()
	if _mesh_instance == null:
		return
	if _mesh_instance.material_override is StandardMaterial3D:
		## Duplicate so fade/dissolve does not mutate the shared scene material.
		_material = (_mesh_instance.material_override as StandardMaterial3D).duplicate()
		_mesh_instance.material_override = _material


func _prepare_for_cast_fx() -> void:
	if _body != null:
		_body_collision_layer = maxi(_body.collision_layer, 1)
		_body.collision_layer = 0
	if _mesh_instance != null:
		_mesh_instance.visible = true
		_mesh_instance.scale = Vector3.ONE * 0.05
	if _material != null:
		_material.albedo_color.a = 0.0
		_material.emission_energy_multiplier = 0.0


func _play_cast_sequence() -> void:
	_kill_cast_tween()
	_clear_cast_fx()
	_build_beam()
	## Collision goes live with the cast — beam is FX only; ward must protect on detect.
	_enable_collision()
	var skip_travel := _wand_origin.distance_squared_to(global_position) < 0.01
	_cast_tween = _make_cast_tween()
	if skip_travel:
		_set_beam_progress(1.0)
		_cast_tween.tween_callback(_form_shield)
		return
	_set_beam_progress(0.0)
	_cast_tween.tween_method(
		_set_beam_progress,
		0.0,
		1.0,
		CAST_TRAVEL_SEC
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_cast_tween.tween_callback(_form_shield)


func _build_beam() -> void:
	var world := get_parent()
	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.008
	cyl.bottom_radius = 0.018
	cyl.height = 1.0
	_beam.mesh = cyl
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_color = Color(0.45, 0.75, 1.0, 0.45)
	_beam_mat.emission_enabled = true
	_beam_mat.emission = Color(0.5, 0.82, 1.0)
	_beam_mat.emission_energy_multiplier = 2.0
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.layers = WorldVisualLayersScript.WORLD
	_beam.process_mode = Node.PROCESS_MODE_ALWAYS
	if world != null:
		world.add_child(_beam)
	else:
		add_child(_beam)
	_update_beam(_wand_origin, _wand_origin)


func _set_beam_progress(t: float) -> void:
	var pos := _wand_origin.lerp(global_position, clampf(t, 0.0, 1.0))
	_update_beam(_wand_origin, pos)
	if _beam_mat != null:
		_beam_mat.albedo_color.a = lerpf(0.5, 0.06, t)
		_beam_mat.emission_energy_multiplier = lerpf(2.4, 0.6, t)


func _update_beam(from_pos: Vector3, to_pos: Vector3) -> void:
	if _beam == null or not is_instance_valid(_beam):
		return
	var delta := to_pos - from_pos
	var length := delta.length()
	if length < 0.001:
		_beam.visible = false
		return
	_beam.visible = true
	_beam.global_position = from_pos.lerp(to_pos, 0.5)
	_beam.scale = Vector3(1.0, length, 1.0)
	_beam.basis = Basis.looking_at(delta.normalized(), Vector3.UP)
	_beam.rotate_object_local(Vector3.RIGHT, -PI * 0.5)


func _form_shield() -> void:
	_clear_cast_fx()
	_spawn_rim_bloom()
	_enable_collision()
	_lifetime = 0.0
	_lifetime_active = not _held
	set_process(true)
	if _mesh_instance != null:
		_mesh_instance.visible = true
		_mesh_instance.scale = Vector3.ONE * 0.2
	_cast_tween = _make_cast_tween()
	_cast_tween.set_parallel(true)
	if _mesh_instance != null:
		_cast_tween.tween_property(_mesh_instance, "scale", Vector3.ONE, FORM_SEC).set_trans(
			Tween.TRANS_QUAD
		).set_ease(Tween.EASE_OUT)
	if _material != null:
		_cast_tween.tween_method(_set_form_material, 0.0, 1.0, FORM_SEC).set_trans(
			Tween.TRANS_SINE
		).set_ease(Tween.EASE_OUT)
	if _rim != null and is_instance_valid(_rim):
		_cast_tween.tween_property(_rim, "scale", Vector3.ONE * 1.08, FORM_SEC).set_trans(
			Tween.TRANS_CUBIC
		).set_ease(Tween.EASE_OUT)
		if _rim_mat != null:
			_cast_tween.tween_property(_rim_mat, "albedo_color:a", 0.0, FORM_SEC)
			_cast_tween.tween_property(_rim_mat, "emission_energy_multiplier", 0.2, FORM_SEC)
	_cast_tween.chain().tween_callback(_finish_form)


func _set_form_material(t: float) -> void:
	if _material == null:
		return
	_material.albedo_color.a = SHIELD_BLUE.a * clampf(t, 0.0, 1.0)
	_material.emission = SHIELD_EDGE
	_material.emission_energy_multiplier = lerpf(0.0, 0.75, t)


func _spawn_rim_bloom() -> void:
	if _mesh_instance == null or _mesh_instance.mesh == null:
		return
	_rim = MeshInstance3D.new()
	_rim.name = "RimBloom"
	_rim.mesh = _mesh_instance.mesh
	_rim.scale = Vector3.ONE * 0.08
	_rim_mat = StandardMaterial3D.new()
	_rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rim_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rim_mat.albedo_color = Color(0.65, 0.9, 1.0, 0.55)
	_rim_mat.emission_enabled = true
	_rim_mat.emission = Color(0.7, 0.95, 1.0)
	_rim_mat.emission_energy_multiplier = 3.2
	_rim.material_override = _rim_mat
	_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rim.layers = WorldVisualLayersScript.WORLD
	add_child(_rim)


func _finish_form() -> void:
	if _rim != null and is_instance_valid(_rim):
		_free_node(_rim)
		_rim = null
	_rim_mat = null
	if _mesh_instance != null:
		_mesh_instance.scale = Vector3.ONE
	if _material != null:
		_material.albedo_color.a = SHIELD_BLUE.a
		_material.emission = SHIELD_EDGE
		_material.emission_energy_multiplier = 0.75
	_apply_integrity_color()
	_enable_collision()


func _enable_collision() -> void:
	if _body != null:
		_body.collision_layer = _body_collision_layer


func _process(delta: float) -> void:
	if _held or not _lifetime_active or _is_broken():
		return
	_lifetime += delta
	var duration := maxf(_duration_sec, 0.05)
	if _material != null:
		var fade := clampf(1.0 - (_lifetime / duration), 0.0, 1.0)
		_material.albedo_color.a = SHIELD_BLUE.a * fade
		_material.emission = SHIELD_EDGE * (0.35 + 0.4 * fade)
	if _lifetime >= duration and not _is_broken():
		_dissolve()


func notify_spell_blocked(damage: float = 0.0) -> void:
	## Hit-count wards spend one cast. HP wards subtract spell damage and tint red.
	if _is_broken():
		return
	if _max_hp > 0.0:
		if damage > 0.0:
			_hp -= damage
			_apply_integrity_color()
		if _hp <= 0.0:
			_dissolve()
		return
	_hits_remaining -= 1
	if _hits_remaining <= 0:
		_dissolve()


func _is_broken() -> bool:
	if _max_hp > 0.0:
		return _hp <= 0.0
	return _hits_remaining <= 0


func integrity_ratio() -> float:
	if _max_hp <= 0.001:
		return 1.0
	return clampf(_hp / _max_hp, 0.0, 1.0)


static func integrity_tint(integrity: float) -> Color:
	var t := 1.0 - clampf(integrity, 0.0, 1.0)
	return SHIELD_BLUE.lerp(SHIELD_STRESS, t)


static func integrity_edge(integrity: float) -> Color:
	var t := 1.0 - clampf(integrity, 0.0, 1.0)
	return SHIELD_EDGE.lerp(SHIELD_STRESS_EDGE, t)


func _apply_integrity_color() -> void:
	if _material == null or _max_hp <= 0.0:
		return
	var integrity := integrity_ratio()
	var fill := integrity_tint(integrity)
	var alpha := _material.albedo_color.a
	_material.albedo_color = Color(fill.r, fill.g, fill.b, alpha)
	_material.emission = integrity_edge(integrity)
	_material.emission_energy_multiplier = lerpf(0.75, 1.8, 1.0 - integrity)


func _dissolve() -> void:
	_hits_remaining = 0
	_hp = 0.0
	_lifetime_active = false
	set_process(false)
	_kill_cast_tween()
	_clear_cast_fx()
	if _rim != null and is_instance_valid(_rim):
		_free_node(_rim)
		_rim = null
	if _body != null:
		_body.collision_layer = 0
	var tween := _make_cast_tween()
	if _material != null:
		tween.tween_property(_material, "albedo_color:a", 0.0, 0.12)
	tween.tween_callback(_free_self)


func _kill_cast_tween() -> void:
	if _cast_tween != null and _cast_tween.is_valid():
		_cast_tween.kill()
	_cast_tween = null


func _clear_cast_fx() -> void:
	if _beam != null and is_instance_valid(_beam):
		_free_node(_beam)
		_beam = null
	_beam_mat = null


func _free_node(node: Node) -> void:
	if Engine.is_editor_hint():
		node.free()
	else:
		node.queue_free()


func _free_self() -> void:
	if Engine.is_editor_hint():
		free()
	else:
		queue_free()


func _exit_tree() -> void:
	_kill_cast_tween()
	_clear_cast_fx()
