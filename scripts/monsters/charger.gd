@tool
class_name Charger
extends Monster

## Sight-cone rammer: faces the player, winds up green→red, then charges
## with a held ward until it hits a wall. Player hits launch into the maze.

enum ChargePhase { NONE, TURNING, WINDUP, CHARGING, STUNNED }

const ChargerLaunchScript := preload("res://scripts/monsters/charger_launch.gd")
const GameWorldScript := preload("res://scripts/game_world.gd")
const WorldGroundScript := preload("res://scripts/world_ground.gd")
const SIGHT_SOURCE := &"sight"
const FACE_ALIGN_RAD := 0.12
const WALL_GRACE_SEC := 0.1
const EYE_REST := Color(0.96, 0.96, 0.94, 1.0)
const EYE_REST_ENERGY := 0.32
const _SNOUT_CAPSULE_BASIS := Basis(Vector3.RIGHT, PI * 0.5)
const _SPHERE_COLLIDER_PARTS: PackedStringArray = [
	"%CollisionShape3D|%Body",
	"MidBodyCollision|%MidBody",
	"NeckCollision|%Neck",
	"HeadCollision|%Head",
	"LeftHindlegCollision|%LeftHindleg",
	"RightHindlegCollision|%RightHindleg",
	"LeftForelegCollision|%LeftForeleg",
	"RightForelegCollision|%RightForeleg",
]
const _FLESH_PARTS: PackedStringArray = [
	"%Snout",
	"%Neck",
	"%LeftForeleg",
	"%RightForeleg",
	"%LeftHindleg",
	"%RightHindleg",
]

@export_range(0.4, 3.0, 0.05) var windup_sec: float = 1.2
@export_range(1.0, 8.0, 0.1) var self_stun_sec: float = 3.0
@export var rest_tint: Color = Color(0.22, 0.72, 0.28, 1.0)
@export var charge_tint: Color = Color(0.88, 0.12, 0.1, 1.0)

var _phase: ChargePhase = ChargePhase.NONE
var _phase_age: float = 0.0
var _charge_dir: Vector3 = Vector3.FORWARD
var _charge_target: Node3D = null
var _held_ward: Node = null
var _hit_bodies: Dictionary = {}
var _used_landings: Dictionary = {}
var _stun_stars: Node = null
var _los_eye: Color = Color(0.95, 0.08, 0.05, 1.0)
var _body_lean: Node3D = null
var _head_lean: Node3D = null
var _head_rest_pitch: float = 0.0


func _ready() -> void:
	super._ready()
	_los_eye = eye_glow_color
	rest_tint = body_tint
	_body_lean = get_node_or_null("%Body") as Node3D
	_head_lean = get_node_or_null("%Head") as Node3D
	if _head_lean != null:
		_head_rest_pitch = _head_lean.rotation.x
	_stun_stars = get_node_or_null("Head/StunStars")
	_set_stun_stars(false)
	_set_chase_eyes_active(true)
	_sync_los_eyes()
	_sync_part_colliders()


func apply_summon_appearance(tint: Color, p_eye_glow_color: Color = DEFAULT_EYE_GLOW) -> void:
	super.apply_summon_appearance(tint, p_eye_glow_color)
	rest_tint = tint
	_los_eye = p_eye_glow_color
	_sync_los_eyes()


func die() -> void:
	_shatter_ward()
	_set_stun_stars(false)
	super.die()


func apply_fireball_knockback(fireball_dir: Vector3) -> void:
	if _phase == ChargePhase.WINDUP or _phase == ChargePhase.CHARGING:
		return
	super.apply_fireball_knockback(fireball_dir)


func _append_default_interest_candidates(_out: Array) -> void:
	## Vision cone (and weak hearing) own aggro — no wide proximity detect.
	pass


func _try_start_cast(_target: Node3D) -> bool:
	return false


func _uses_continuous_chase_move_timer() -> bool:
	return false


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_alive:
		return
	if _phase != ChargePhase.NONE:
		_tick_locked_phase(delta)
		_sync_los_eyes()
		return
	super._physics_process(delta)
	_sync_los_eyes()


func _tick_chase(delta: float) -> void:
	if not _interest_is_actionable(_interest):
		super._tick_chase(delta)
		return
	if _interest_source() == SIGHT_SOURCE:
		_begin_turning(_interest.get("target") as Node3D)
		return
	super._tick_chase(delta)


func _tick_locked_phase(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	match _phase:
		ChargePhase.TURNING:
			_tick_turning(delta)
		ChargePhase.WINDUP:
			_tick_windup(delta)
		ChargePhase.CHARGING:
			_tick_charging(delta)
		ChargePhase.STUNNED:
			_tick_self_stun(delta)
	move_and_slide()
	if _phase == ChargePhase.CHARGING:
		_resolve_charge_collisions()


func _begin_turning(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_phase = ChargePhase.TURNING
	_phase_age = 0.0
	_charge_target = target
	_cancel_cast()
	_clear_chase_move()
	velocity.x = 0.0
	velocity.z = 0.0
	_set_chase_eyes_active(true)


func _tick_turning(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if not _target_is_valid():
		_reset_to_idle()
		return
	var toward := _flat_to_target()
	_face_horizontal_at_speed(toward, delta, face_turn_speed_rad)
	if _is_facing(toward):
		_begin_windup()


func _begin_windup() -> void:
	_phase = ChargePhase.WINDUP
	_phase_age = 0.0
	_charge_dir = _locked_forward()
	velocity.x = 0.0
	velocity.z = 0.0
	_shatter_ward()
	_held_ward = _spawn_held_ward()


func _tick_windup(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_phase_age += delta
	var t := clampf(_phase_age / maxf(windup_sec, 0.05), 0.0, 1.0)
	_apply_charge_tint(t)
	_set_body_lean(t * 0.28)
	if t >= 1.0:
		_begin_charging()


func _begin_charging() -> void:
	_phase = ChargePhase.CHARGING
	_phase_age = 0.0
	_hit_bodies.clear()
	_used_landings.clear()
	_charge_dir = _locked_forward()
	_apply_charge_tint(1.0)
	_set_body_lean(0.32)


func _tick_charging(delta: float) -> void:
	_phase_age += delta
	var speed := ChargerLaunchScript.charge_speed(PlayableCharacter.SPRINT_SPEED)
	velocity.x = _charge_dir.x * speed
	velocity.z = _charge_dir.z * speed
	_face_horizontal_at_speed(_charge_dir, delta, face_turn_speed_rad * 4.0)


func _begin_self_stun() -> void:
	_shatter_ward()
	_phase = ChargePhase.STUNNED
	_phase_age = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_charge_tint(0.0)
	_set_body_lean(0.0)
	_set_stun_stars(true)


func _tick_self_stun(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_phase_age += delta
	if _phase_age >= self_stun_sec:
		_reset_to_idle()


func _reset_to_idle() -> void:
	_shatter_ward()
	_set_stun_stars(false)
	_apply_charge_tint(0.0)
	_set_body_lean(0.0)
	_phase = ChargePhase.NONE
	_phase_age = 0.0
	_charge_target = null
	_hit_bodies.clear()
	_enter_idle()


func _spawn_held_ward() -> Node:
	var ability := _charge_ward_ability()
	if ability != null and ability.has_method("spawn_held_ward"):
		return ability.call("spawn_held_ward", self)
	return null


func _charge_ward_ability() -> Node:
	for ability in get_combat_abilities():
		if str(ability.get("ability_id")) == "charger_ward":
			return ability
	var abilities := get_combat_abilities()
	if abilities.is_empty():
		return null
	return abilities[0]


func _shatter_ward() -> void:
	if _held_ward != null and is_instance_valid(_held_ward):
		if _held_ward.has_method("shatter"):
			_held_ward.call("shatter")
		else:
			_held_ward.queue_free()
	_held_ward = null


func _resolve_charge_collisions() -> void:
	var hit_wall := false
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var collider := col.get_collider()
		if collider is Node:
			_try_hit_player(collider as Node)
		if _phase_age >= WALL_GRACE_SEC and _is_charge_wall(collider, col.get_normal()):
			hit_wall = true
	if hit_wall:
		_begin_self_stun()


func _try_hit_player(body: Node) -> void:
	if body == null or body == self:
		return
	if not (body is Node3D) or not body.is_in_group("player"):
		return
	var id := body.get_instance_id()
	if _hit_bodies.has(id):
		return
	_hit_bodies[id] = true
	_launch_player(body as Node3D)


func _launch_player(player: Node3D) -> void:
	var maze := _find_maze()
	var away := _charge_dir
	var landing := ChargerLaunchScript.resolve_landing_world(
		maze, player.global_position, away, _rng, _used_landings
	)
	if maze != null and player.is_inside_tree():
		var world_3d := player.get_world_3d()
		landing = WorldGroundScript.with_height_above_ground(
			world_3d, landing, 0.0, player.global_position.y
		)
	_apply_player_hit(player, landing)


func _apply_player_hit(player: Node, landing: Vector3) -> void:
	var stun := player.get_node_or_null("Stun")
	if stun == null:
		return
	var g := gravity
	if "gravity" in player:
		g = float(player.get("gravity"))
	if not GameState.is_multiplayer or player.is_multiplayer_authority():
		if stun.has_method("begin_charger_hit"):
			stun.call("begin_charger_hit", landing, g)
		return
	var peer := int(player.get_multiplayer_authority())
	if peer > 0 and stun.has_method("rpc_begin_charger_hit"):
		stun.rpc_id(peer, "rpc_begin_charger_hit", landing)


func _is_charge_wall(collider: Object, normal: Vector3) -> bool:
	if collider == null or collider == self:
		return false
	if not (collider is Node):
		return normal.y < 0.45
	var node := collider as Node
	if node.is_in_group("player") or node.is_in_group("monster"):
		return false
	if node is CharacterBody3D:
		return false
	var name_s := str(node.name).to_lower()
	if name_s == "floor" or name_s.begins_with("floor"):
		return false
	return normal.y < 0.45


func _find_maze() -> Node:
	if not is_inside_tree():
		return null
	var match_root := GameWorldScript.find_match_root(get_tree())
	if match_root != null:
		return match_root.get_node_or_null("MazeGenerator")
	return null


func _interest_source() -> StringName:
	if _interest == null:
		return &""
	return _interest.get("source") as StringName


func _target_is_valid() -> bool:
	return _charge_target != null and is_instance_valid(_charge_target)


func _flat_to_target() -> Vector3:
	if not _target_is_valid():
		return _charge_dir
	return Vector3(
		_charge_target.global_position.x - global_position.x,
		0.0,
		_charge_target.global_position.z - global_position.z
	)


func _locked_forward() -> Vector3:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3.FORWARD
	return forward.normalized()


func _is_facing(desired: Vector3) -> bool:
	if desired.length_squared() < 0.0001:
		return true
	var forward := _locked_forward()
	return forward.angle_to(desired.normalized()) <= FACE_ALIGN_RAD


func _tint_optional_body_parts() -> void:
	super._tint_optional_body_parts()
	for path in _FLESH_PARTS:
		_tint_mesh_instance(get_node_or_null(path) as MeshInstance3D, body_tint)


func _apply_charge_tint(t: float) -> void:
	body_tint = rest_tint.lerp(charge_tint, clampf(t, 0.0, 1.0))


func _set_chase_eyes_active(_active: bool) -> void:
	## White eyes stay visible; red glow is LOS, not the generic chase hide/show.
	super._set_chase_eyes_active(true)


func _apply_eye_glow_from_health() -> void:
	if eye_glow_color.is_equal_approx(EYE_REST):
		_apply_eye_glow_color(EYE_REST, EYE_REST_ENERGY)
		return
	super._apply_eye_glow_from_health()


func _sync_los_eyes() -> void:
	var want := _los_eye if _has_los_lock() else EYE_REST
	if not eye_glow_color.is_equal_approx(want):
		eye_glow_color = want


func _has_los_lock() -> bool:
	if _phase == ChargePhase.TURNING or _phase == ChargePhase.WINDUP or _phase == ChargePhase.CHARGING:
		return true
	if _phase == ChargePhase.STUNNED:
		return false
	return _interest_source() == SIGHT_SOURCE


func _set_body_lean(pitch: float) -> void:
	if _body_lean != null:
		_body_lean.rotation.x = pitch * 0.4
	if _head_lean != null:
		_head_lean.rotation.x = _head_rest_pitch + pitch
	_sync_part_colliders()


func _sync_part_colliders() -> void:
	# CollisionShape3D must stay direct children of Charger. Snap them to meshes.
	for spec in _SPHERE_COLLIDER_PARTS:
		var bits := spec.split("|")
		if bits.size() != 2:
			continue
		var col := get_node_or_null(bits[0]) as CollisionShape3D
		var part := get_node_or_null(bits[1]) as Node3D
		if col == null or part == null:
			continue
		col.global_position = part.global_position
		col.global_basis = part.global_transform.basis.orthonormalized()
	var snout_col := get_node_or_null("SnoutCollision") as CollisionShape3D
	var snout := get_node_or_null("%Snout") as Node3D
	if snout_col == null or snout == null or _head_lean == null:
		return
	snout_col.global_position = snout.global_position
	snout_col.global_basis = _head_lean.global_transform.basis * _SNOUT_CAPSULE_BASIS


func _set_stun_stars(on: bool) -> void:
	if _stun_stars != null and _stun_stars.has_method("set_active"):
		_stun_stars.call("set_active", on)
