@tool
class_name WorkspacePlayerDummy
extends CharacterBody3D

## Stationary lookdev punching bag. In the player group so monster AI can aggro.

const BroomLocomotionScript := preload("res://scripts/headmaster/broom_locomotion.gd")
const EmberHaloFlightScript := preload(
	"res://scripts/monsters/abilities/ember_halo_flight.gd"
)

const DUMMY_HP := 9999.0
const JUMP_VELOCITY := 4.5
const KNOCKBACK_TIMER_SEC := 0.35
const HURT_UP_IMPULSE := 2.4
const HOME_RETURN_RATE := 14.0

var is_alive: bool = true
var max_health: float = DUMMY_HP
var current_health: float = DUMMY_HP
var gravity: float = 18.0
var _knockback_vel: Vector3 = Vector3.ZERO
var _knockback_timer: float = 0.0
var _speed_boost_timer: float = 0.0
var _home: Vector3 = Vector3.ZERO
var _home_set: bool = false


func _ready() -> void:
	add_to_group("player")
	collision_layer = 1
	## Floor/monster both live on layer 1 — mask 0 so dashes do not shove the dummy.
	collision_mask = 0
	is_alive = true
	current_health = max_health
	_build_visuals()
	if Engine.is_editor_hint():
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _knockback_timer > 0.0:
		_knockback_timer -= delta
		velocity.x += _knockback_vel.x * 0.35
		velocity.z += _knockback_vel.z * 0.35
		_knockback_vel = _knockback_vel.move_toward(Vector3.ZERO, 28.0 * delta)
	velocity.y -= gravity * delta
	if _speed_boost_timer > 0.0:
		_speed_boost_timer = maxf(0.0, _speed_boost_timer - delta)
	move_and_slide()
	_return_home(delta)


func pin_home() -> void:
	_home = global_position
	_home_set = true


func take_damage(amount: float, _from: Node3D = null) -> void:
	if amount <= 0.0:
		return
	current_health = maxf(1.0, current_health - amount)
	velocity.y = maxf(velocity.y, HURT_UP_IMPULSE)


func apply_speed_boost(duration: float, _multiplier: float) -> void:
	_speed_boost_timer = duration


func apply_fireball_knockback(fireball_dir: Vector3) -> void:
	var impulse: Vector3 = BroomLocomotionScript.knockback_impulse(fireball_dir)
	_knockback_vel = impulse
	_knockback_timer = KNOCKBACK_TIMER_SEC
	velocity += impulse


func apply_ember_halo_jump_pad() -> void:
	velocity.y = EmberHaloFlightScript.jump_pad_velocity(gravity)


func apply_ember_halo_hit(hit_dir: Vector3) -> void:
	velocity.y = maxf(velocity.y, JUMP_VELOCITY)
	var flat := Vector3(hit_dir.x, 0.0, hit_dir.z)
	if flat.length_squared() > 0.0001:
		flat = flat.normalized()
		var impulse := flat * EmberHaloFlightScript.HIT_KNOCKBACK_SPEED
		_knockback_vel = impulse
		_knockback_timer = 0.25
		velocity.x += impulse.x
		velocity.z += impulse.z
	apply_speed_boost(
		EmberHaloFlightScript.SLOW_DURATION_SEC,
		EmberHaloFlightScript.SLOW_MULTIPLIER
	)


func apply_wretch_command_hit(hit_dir: Vector3) -> void:
	var dir := hit_dir
	if dir.length_squared() < 0.0001:
		dir = -global_transform.basis.z
	else:
		dir = dir.normalized()
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	else:
		flat = flat.normalized()
	var impulse := flat * 6.0 + Vector3.UP * 1.5
	_knockback_vel = impulse
	_knockback_timer = 0.28
	velocity += impulse


func apply_ember_trail_burn(
	_dps: float, slow_multiplier: float, refresh_sec: float
) -> void:
	apply_speed_boost(refresh_sec, slow_multiplier)


func _return_home(delta: float) -> void:
	if not _home_set:
		return
	var t := clampf(HOME_RETURN_RATE * delta, 0.0, 1.0)
	var pos := global_position
	pos.x = lerpf(pos.x, _home.x, t)
	pos.z = lerpf(pos.z, _home.z, t)
	if pos.y < _home.y:
		pos.y = _home.y
		velocity.y = maxf(velocity.y, 0.0)
	global_position = pos
	if _knockback_timer <= 0.0:
		velocity.x = 0.0
		velocity.z = 0.0


func _build_visuals() -> void:
	if get_node_or_null("Collision") != null:
		return
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.15
	collision.shape = capsule
	collision.position = Vector3(0.0, 0.58, 0.0)
	add_child(collision)
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.28
	mesh.height = 1.15
	mesh_inst.mesh = mesh
	mesh_inst.position = Vector3(0.0, 0.58, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.62, 0.95, 1.0)
	mat.roughness = 0.55
	mesh_inst.material_override = mat
	add_child(mesh_inst)
