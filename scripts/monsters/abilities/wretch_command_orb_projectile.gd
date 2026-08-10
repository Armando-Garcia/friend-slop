extends Area3D

## Fast green pack orb. Homing on a player, or flying to a heard world position.

signal hit_target(target: Node3D)

const GLOW := Color(0.35, 1.0, 0.4, 1.0)
const DEFAULT_SPEED := 28.0
const HIT_RADIUS := 0.45
const MAX_LIFE_SEC := 3.5
const ARRIVE_EPS := 0.35

var _caster: Node3D = null
var _target: Node3D = null
var _aim_position: Vector3 = Vector3.ZERO
var _has_aim_position: bool = false
var _summon_host: Node = null
var _speed: float = DEFAULT_SPEED
var _age: float = 0.0
var _finished: bool = false


static func spawn(
	parent: Node,
	origin: Vector3,
	target: Node3D,
	caster: Node3D,
	summon_host: Node,
	speed: float = DEFAULT_SPEED,
	scale_mult: float = 2.0
) -> Area3D:
	var proj = new()
	proj.name = "WretchCommandOrb"
	parent.add_child(proj)
	proj.global_position = origin
	proj._setup(target, Vector3.ZERO, false, caster, summon_host, speed, scale_mult)
	return proj


static func spawn_toward_point(
	parent: Node,
	origin: Vector3,
	aim_position: Vector3,
	caster: Node3D,
	summon_host: Node,
	speed: float = DEFAULT_SPEED,
	scale_mult: float = 2.0
) -> Area3D:
	var proj = new()
	proj.name = "WretchCommandOrb"
	parent.add_child(proj)
	proj.global_position = origin
	proj._setup(null, aim_position, true, caster, summon_host, speed, scale_mult)
	return proj


func _setup(
	target: Node3D,
	aim_position: Vector3,
	has_aim: bool,
	caster: Node3D,
	summon_host: Node,
	speed: float,
	scale_mult: float
) -> void:
	_target = target
	_aim_position = aim_position
	_has_aim_position = has_aim
	_caster = caster
	_summon_host = summon_host
	_speed = maxf(8.0, speed)
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1 | 2

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = HIT_RADIUS * scale_mult * 0.5
	shape.shape = sphere
	add_child(shape)
	body_entered.connect(_on_body_entered)

	var mesh := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.11 * scale_mult
	ball.height = 0.22 * scale_mult
	mesh.mesh = ball
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(GLOW.r, GLOW.g, GLOW.b, 0.9)
	mat.emission_enabled = true
	mat.emission = GLOW
	mat.emission_energy_multiplier = 5.0
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

	var light := OmniLight3D.new()
	light.light_color = GLOW
	light.light_energy = 4.5
	light.omni_range = 3.0 * scale_mult
	light.shadow_enabled = false
	add_child(light)

	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _finished:
		return
	_age += delta
	if _age >= MAX_LIFE_SEC:
		_finish_at_aim()
		return
	var aim := _resolve_aim()
	var to_aim := aim - global_position
	if to_aim.length_squared() < 0.0001 or to_aim.length() <= ARRIVE_EPS:
		if _target != null and is_instance_valid(_target):
			_finish(_target)
		else:
			_finish_at_aim()
		return
	var step := to_aim.normalized() * _speed * delta
	if step.length() >= to_aim.length():
		global_position = aim
		if _target != null and is_instance_valid(_target):
			_finish(_target)
		else:
			_finish_at_aim()
		return
	global_position += step


func _resolve_aim() -> Vector3:
	if _target != null and is_instance_valid(_target):
		return _target.global_position + Vector3(0.0, 0.5, 0.0)
	if _has_aim_position:
		return _aim_position
	return global_position + Vector3.FORWARD


func _on_body_entered(body: Node3D) -> void:
	if _finished or body == null or body == _caster:
		return
	if body.is_in_group("player") or body == _target:
		_finish(body)


func _finish_at_aim() -> void:
	if _finished:
		return
	_finished = true
	set_physics_process(false)
	if _summon_host != null and is_instance_valid(_summon_host):
		var pos := _aim_position if _has_aim_position else global_position
		if _summon_host.has_method("command_investigate"):
			_summon_host.call("command_investigate", pos)
	queue_free()


func _finish(hit: Node3D) -> void:
	if _finished:
		return
	_finished = true
	set_physics_process(false)
	if hit != null and is_instance_valid(hit):
		hit_target.emit(hit)
		var chase_target := hit
		if _target != null and is_instance_valid(_target):
			chase_target = _target
		_apply_hit_effects(hit, chase_target)
		if _summon_host != null and is_instance_valid(_summon_host):
			if _summon_host.has_method("command_attack"):
				_summon_host.call("command_attack", chase_target)
	queue_free()


func _apply_hit_effects(hit: Node3D, chase_target: Node3D) -> void:
	var dir := Vector3.FORWARD
	if _caster != null and is_instance_valid(_caster):
		dir = hit.global_position - _caster.global_position
	elif chase_target != null and is_instance_valid(chase_target):
		dir = chase_target.global_position - global_position
	var apply_local := true
	var tree := get_tree()
	if tree != null:
		var state := tree.root.get_node_or_null("GameState")
		var mp := state != null and bool(state.get("is_multiplayer"))
		if mp and hit is Node:
			apply_local = (hit as Node).is_multiplayer_authority()
	if not apply_local:
		return
	if hit.has_method("apply_wretch_command_hit"):
		hit.call("apply_wretch_command_hit", dir)
	else:
		if hit.has_method("apply_fireball_knockback"):
			hit.call("apply_fireball_knockback", dir * 1.75)
		if hit.has_method("apply_speed_boost"):
			hit.call("apply_speed_boost", 2.0, 0.1)
