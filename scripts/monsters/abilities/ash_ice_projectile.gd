class_name AshIceProjectile
extends Area3D

## Curved ice bolt that travels up and aside, then into the target.

const AshIceFlightScript := preload("res://scripts/monsters/abilities/ash_ice_flight.gd")
const SpellWardBlockScript := preload("res://scripts/spells/spell_ward_block.gd")

const HIT_DAMAGE := 14.0
const MAX_LIFE_SEC := 3.5

var _caster: Node3D = null
var _target: Node3D = null
var _from: Vector3 = Vector3.ZERO
var _control: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _arc_dist: float = 0.0
var _age: float = 0.0
var _finished: bool = false
var _last_dir: Vector3 = Vector3.FORWARD


static func spawn_toward_point(
	parent: Node,
	origin: Vector3,
	aim_position: Vector3,
	caster: Node3D = null,
	side_sign: float = 1.0
) -> AshIceProjectile:
	var packed: PackedScene = load(
		"res://scenes/monsters/abilities/ash_ice_projectile.tscn"
	) as PackedScene
	var proj: AshIceProjectile = packed.instantiate() as AshIceProjectile
	parent.add_child(proj)
	proj.global_position = origin
	proj.setup_toward_point(aim_position, caster, side_sign)
	return proj


static func spawn(
	parent: Node,
	origin: Vector3,
	target: Node3D,
	caster: Node3D = null,
	side_sign: float = 1.0
) -> AshIceProjectile:
	var aim := origin + Vector3.FORWARD * 8.0
	if target != null and is_instance_valid(target):
		aim = target.global_position
	return spawn_toward_point(parent, origin, aim, caster, side_sign)


func setup_toward_point(
	aim_position: Vector3, caster: Node3D = null, side_sign: float = 1.0
) -> void:
	_target = null
	_caster = caster
	_build_projectile_body()
	_from = global_position
	_to = aim_position
	_to.y = maxf(_to.y, 0.4)
	_control = AshIceFlightScript.make_control(_from, _to, side_sign)
	_arc_dist = 0.0
	_last_dir = AshIceFlightScript.tangent(_from, _control, _to, 0.0)
	set_physics_process(true)


func setup(target: Node3D, caster: Node3D = null, side_sign: float = 1.0) -> void:
	var aim := global_position + Vector3.FORWARD * 8.0
	if target != null and is_instance_valid(target):
		aim = target.global_position
	setup_toward_point(aim, caster, side_sign)


func _build_projectile_body() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1 | 2
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.16
	shape.shape = sphere
	add_child(shape)
	body_entered.connect(_on_body_entered)

	var mesh := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.13
	ball.height = 0.26
	mesh.mesh = ball
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.55, 0.85, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.75, 1.0)
	mat.emission_energy_multiplier = 4.2
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

	var light := OmniLight3D.new()
	light.light_color = Color(0.45, 0.8, 1.0)
	light.light_energy = 2.8
	light.omni_range = 2.8
	light.shadow_enabled = false
	add_child(light)

	var flakes := GPUParticles3D.new()
	flakes.amount = 14
	flakes.lifetime = 0.4
	flakes.emitting = true
	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = 55.0
	pmat.initial_velocity_min = 0.2
	pmat.initial_velocity_max = 0.7
	pmat.gravity = Vector3(0, -1.5, 0)
	pmat.scale_min = 0.04
	pmat.scale_max = 0.09
	pmat.color = Color(0.7, 0.9, 1.0, 0.75)
	flakes.process_material = pmat
	var smesh := SphereMesh.new()
	smesh.radius = 0.035
	smesh.height = 0.07
	flakes.draw_pass_1 = smesh
	add_child(flakes)


func _physics_process(delta: float) -> void:
	if _finished:
		return
	if _caster != null and not is_instance_valid(_caster):
		_caster = null
	_age += delta
	if _age >= MAX_LIFE_SEC:
		_finish()
		return

	var step := AshIceFlightScript.advance_arc_distance(
		_from, _control, _to, _arc_dist, delta
	)
	var next_pos: Vector3 = step["position"]
	var next_t: float = float(step["t"])
	_last_dir = AshIceFlightScript.tangent(_from, _control, _to, next_t)
	global_position = next_pos
	_arc_dist = float(step["distance"])
	if _try_block_ward_overlap():
		return
	var total_len := float(step["total_length"])
	if _arc_dist >= total_len - 0.05 or next_t >= 0.999:
		_finish()


func _on_body_entered(body: Node3D) -> void:
	if _finished:
		return
	if body == _caster:
		return
	if _is_own_ward(body):
		return
	if _block_if_ward(body):
		return
	if _try_hit(body):
		return
	_finish()


func _try_block_ward_overlap() -> bool:
	if not monitoring or not is_inside_tree():
		return false
	for body in get_overlapping_bodies():
		if body == _caster:
			continue
		if _is_own_ward(body):
			continue
		if _block_if_ward(body):
			return true
	return false


func _is_own_ward(body: Node) -> bool:
	var ward := SpellWardBlockScript.ward_from_node(body)
	if ward == null or _caster == null:
		return false
	if not ward.has_method("is_owned_by"):
		return false
	return bool(ward.call("is_owned_by", _caster))


func _block_if_ward(body: Node) -> bool:
	if not SpellWardBlockScript.try_block(body, HIT_DAMAGE, _caster):
		return false
	_finish()
	return true


func _try_hit(body: Node3D) -> bool:
	if body == null or body == _caster:
		return false
	if not (
		body.is_in_group("player")
		or body.is_in_group("monster")
		or body.is_in_group("combat_target")
	):
		return false
	var dir := _last_dir
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	_finish()
	var apply_local := true
	if body is Node:
		var state := get_tree().root.get_node_or_null("GameState") if get_tree() != null else null
		var mp := state != null and bool(state.get("is_multiplayer"))
		apply_local = (not mp) or (body as Node).is_multiplayer_authority()
	if apply_local and body.has_method("apply_fireball_knockback"):
		body.call("apply_fireball_knockback", dir)
	if body.has_method("take_damage") and HIT_DAMAGE > 0.0:
		body.call("take_damage", HIT_DAMAGE, self)
	return true


func _finish() -> void:
	if _finished:
		return
	_finished = true
	set_physics_process(false)
	queue_free()
