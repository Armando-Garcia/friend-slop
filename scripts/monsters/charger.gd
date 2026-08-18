@tool
class_name Charger
extends Monster

## Sight-cone rammer: lock-on telegraph, then a locked ram, then wall stun.

enum ChargePhase { NONE, TELEGRAPH, CHARGE, WALL_STUN }

const ChargerChargeScript := preload("res://scripts/monsters/charger_charge.gd")
const ChargerLaunchScript := preload("res://scripts/monsters/charger_launch.gd")
const GameWorldScript := preload("res://scripts/game_world.gd")
const WorldGroundScript := preload("res://scripts/world_ground.gd")
const SIGHT_SOURCE := &"sight"
const RAM_HIT_RANGE := 1.7
const RAM_WALL_RAY := 1.15
const GORE_TOSS_SPEED_RAD := 10.0
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

@export_group("Charge")
## Pose only: lock, ward, bow, turn red. Holds when the telegraph is finished.
@export_tool_button("Preview Telegraph", "Callable")
var preview_telegraph_action := preview_telegraph
## Pose only: locked red ram in place. Does not wall-stun. Does not steer.
@export_tool_button("Preview Charge", "Callable")
var preview_charge_action := preview_charge_pose
## Pose only: wall stars, then recover to idle.
@export_tool_button("Preview Wall Stun", "Callable")
var preview_wall_stun_action := preview_wall_stun
## Seconds locked on the player, bowing and turning red, before the ram.
@export_range(0.4, 3.0, 0.05) var telegraph_sec: float = 1.2
## Seconds stunned with orbiting stars after the ram hits a wall.
@export_range(1.0, 8.0, 0.1) var self_stun_sec: float = 3.0
## Head tuck before the ram. 360 = level, 330 = 30° down. Finishes as running starts.
@export_range(330.0, 360.0, 0.5) var charge_head_plunge_deg: float = 338.0
## Head toss (degrees up) when a player is gored during the ram.
@export_range(30.0, 90.0, 1.0) var charge_head_toss_deg: float = 60.0
## How fast the head eases back to rest after a wall (rad/s). Does not snap.
@export_range(0.4, 8.0, 0.1) var head_return_speed_rad: float = 2.8
## Body color while idle / patrol / after stun.
@export var rest_tint: Color = Color(0.22, 0.72, 0.28, 1.0)
## Body color at full telegraph and during the ram.
@export var charge_tint: Color = Color(0.88, 0.12, 0.1, 1.0)

var _phase: ChargePhase = ChargePhase.NONE
var _charge := ChargerChargeScript.new()
var _charge_target: Node3D = null
var _held_ward: Node = null
var _hit_bodies: Dictionary = {}
var _used_landings: Dictionary = {}
var _stun_stars: Node = null
var _los_eye: Color = Color(0.95, 0.08, 0.05, 1.0)
var _body_lean: Node3D = null
var _head_lean: Node3D = null
var _head_rest_pitch: float = 0.0
var _head_pitch: float = 0.0
var _head_pitch_goal: float = 0.0
var _head_pitch_speed: float = 3.0
var _lookdev_launch_stuns: Array[Node] = []


func _ready() -> void:
	super._ready()
	patrol_speed = ChargerLaunchScript.patrol_speed(PlayableCharacter.WALK_SPEED)
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
	if bool(get_meta("lookdev_live_ai", false)):
		set_process(true)


func _sandbox_charge_tick() -> bool:
	return Engine.is_editor_hint() and bool(get_meta("lookdev_live_ai", false))


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
	if _phase == ChargePhase.TELEGRAPH or _phase == ChargePhase.CHARGE:
		return
	super.apply_fireball_knockback(fireball_dir)


func _append_default_interest_candidates(_out: Array) -> void:
	## Vision cone (and weak hearing) own aggro — no wide proximity detect.
	pass


func _try_start_cast(_target: Node3D) -> bool:
	return false


func preview_telegraph() -> void:
	## Inspector pose: lock, ward, bow, turn red. Holds when finished.
	begin_lock_on(null, true)


func preview_charge_pose() -> void:
	## Inspector pose: locked red ram in place. No wall stun. No steering.
	begin_charge_now(true, null)


func preview_wall_stun() -> void:
	## Inspector pose: wall stars, then recover to idle.
	if not is_inside_tree() or not is_alive:
		return
	_charge.pose_only = true
	set_process(true)
	_begin_wall_stun()


func preview_charge(target: Node3D) -> void:
	## Live lock-on toward `target` (workspace / match helpers).
	begin_lock_on(target, false)


func begin_lock_on(target: Node3D, pose_only: bool = false) -> void:
	if not is_inside_tree() or not is_alive:
		return
	if target != null and not pose_only and not is_playable_charge_target(target):
		return
	lookdev_override = false
	_charge.pose_only = pose_only
	_charge.begin_telegraph()
	_phase = ChargePhase.TELEGRAPH
	_charge_target = target
	_cancel_cast()
	_clear_chase_move()
	velocity.x = 0.0
	velocity.z = 0.0
	_set_chase_eyes_active(true)
	_shatter_ward()
	_held_ward = _spawn_held_ward()
	var down := ChargerLaunchScript.plunge_pitch_rad(charge_head_plunge_deg)
	var tuck_speed := absf(down) / maxf(telegraph_sec, 0.05)
	_set_head_pitch_goal(down, maxf(tuck_speed, 0.4))
	_arm_charge_ticks(pose_only)


func begin_charge_now(pose_only: bool = false, target: Node3D = null) -> void:
	if not is_inside_tree() or not is_alive:
		return
	lookdev_override = false
	_charge.pose_only = pose_only
	if is_playable_charge_target(target):
		_charge_target = target
		_snap_yaw(_flat_to_target())
	_cancel_cast()
	_clear_chase_move()
	if _held_ward == null or not is_instance_valid(_held_ward):
		_held_ward = _spawn_held_ward()
	_begin_charging()
	_arm_charge_ticks(pose_only)


func begin_wall_stun_now() -> void:
	if not is_inside_tree() or not is_alive:
		return
	lookdev_override = false
	_charge.pose_only = false
	_arm_charge_ticks(false)
	_begin_wall_stun()


func _arm_charge_ticks(pose_only: bool) -> void:
	if pose_only or _sandbox_charge_tick():
		set_process(true)
		if pose_only:
			set_physics_process(false)
	else:
		set_physics_process(true)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_tick_lookdev_launches(delta)
	if _phase == ChargePhase.NONE:
		super._process(delta)
		return
	if _charge.pose_only or _sandbox_charge_tick():
		_tick_locked_phase(delta)
		_sync_los_eyes()


func _validate_property(property: Dictionary) -> void:
	## Charger ignores kite/KEEP_AWAY timers — hide them so Combat stays readable.
	var hidden := PackedStringArray([
		"chase_style",
		"keep_away_range",
		"chase_wait_min_sec",
		"chase_wait_max_sec",
		"chase_strafe_min_sec",
		"chase_strafe_max_sec",
		"chase_retreat_min_sec",
		"chase_retreat_max_sec",
		"chase_optimal_eps",
	])
	if hidden.has(property.name):
		property.usage = (
			PROPERTY_USAGE_STORAGE
			| PROPERTY_USAGE_SCRIPT_VARIABLE
			| PROPERTY_USAGE_NO_EDITOR
		)


func _uses_continuous_chase_move_timer() -> bool:
	return false


func _physics_process(delta: float) -> void:
	if not is_alive or _charge.pose_only:
		return
	if _phase != ChargePhase.NONE:
		if _sandbox_charge_tick():
			return
		_tick_locked_phase(delta)
		_sync_los_eyes()
		return
	if Engine.is_editor_hint() and not bool(get_meta("lookdev_live_ai", false)):
		return
	super._physics_process(delta)
	_sync_los_eyes()


func _tick_chase(delta: float) -> void:
	if not _interest_is_actionable(_interest):
		super._tick_chase(delta)
		return
	if _interest_source() == SIGHT_SOURCE:
		var target := _interest.get("target") as Node3D
		if is_playable_charge_target(target):
			begin_lock_on(target, false)
			return
	super._tick_chase(delta)


func _tick_locked_phase(delta: float) -> void:
	if not _charge.pose_only:
		if _sandbox_charge_tick():
			velocity.y = 0.0
		elif not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = 0.0
	match _phase:
		ChargePhase.TELEGRAPH:
			_tick_telegraph(delta)
		ChargePhase.CHARGE:
			_tick_charging(delta)
		ChargePhase.WALL_STUN:
			_tick_wall_stun(delta)
	_tick_head_pitch(delta)
	if _charge.pose_only:
		return
	if _sandbox_charge_tick():
		if _phase == ChargePhase.CHARGE:
			velocity.y = 0.0
			global_position += Vector3(velocity.x, 0.0, velocity.z) * delta
			_try_ram_contacts()
		else:
			MonsterAIScript.apply_move(self, delta)
		return
	move_and_slide()
	if _phase == ChargePhase.CHARGE:
		_try_ram_contacts()


func _tick_telegraph(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_charge.tick(delta)
	if not _charge.pose_only:
		if not _target_is_valid():
			_reset_to_idle()
			return
		_face_horizontal_at_speed(_flat_to_target(), delta, face_turn_speed_rad)
	var t := _charge.telegraph_progress(telegraph_sec)
	_apply_charge_tint(t)
	_set_body_lean(t * 0.28)
	var plunge := ChargerLaunchScript.plunge_pitch_rad(charge_head_plunge_deg)
	if (
		not _charge.pose_only
		and _charge.telegraph_ready(telegraph_sec, _head_pitch, plunge)
	):
		_begin_charging()


func _begin_charging() -> void:
	_phase = ChargePhase.CHARGE
	_charge.begin_charge(_locked_forward())
	_hit_bodies.clear()
	_used_landings.clear()
	_apply_charge_tint(1.0)
	_set_body_lean(0.32)
	var plunge := ChargerLaunchScript.plunge_pitch_rad(charge_head_plunge_deg)
	_head_pitch = plunge
	_set_head_pitch_goal(plunge, 8.0)
	_apply_head_pitch()
	if _charge.pose_only:
		velocity.x = 0.0
		velocity.z = 0.0


func _tick_charging(delta: float) -> void:
	_charge.tick(delta)
	_apply_charge_tint(1.0)
	_set_body_lean(0.32)
	if _charge.pose_only:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var speed := ChargerChargeScript.charge_speed(PlayableCharacter.SPRINT_SPEED)
	var ram := _charge.charge_velocity(speed)
	velocity.x = ram.x
	velocity.z = ram.z
	_face_horizontal_at_speed(_charge.locked_dir, delta, face_turn_speed_rad * 4.0)


func _begin_wall_stun() -> void:
	_shatter_ward()
	_phase = ChargePhase.WALL_STUN
	_charge.begin_wall_stun()
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_charge_tint(0.0)
	_set_body_lean(0.0)
	_set_head_pitch_goal(0.0, head_return_speed_rad)
	_set_stun_stars(true)


func _tick_wall_stun(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_charge.tick(delta)
	if _charge.wall_stun_ready(self_stun_sec):
		_reset_to_idle()


func _reset_to_idle() -> void:
	_shatter_ward()
	_set_stun_stars(false)
	_apply_charge_tint(0.0)
	_set_body_lean(0.0)
	_head_pitch = 0.0
	_head_pitch_goal = 0.0
	_apply_head_pitch()
	_phase = ChargePhase.NONE
	_charge.reset()
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


func _try_ram_contacts() -> void:
	var hit_wall := false
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var collider := col.get_collider()
		if collider is Node:
			_try_hit_player(collider as Node)
		if (
			_charge.can_read_walls()
			and ChargerChargeScript.is_wall_collider(collider, col.get_normal())
		):
			hit_wall = true
	_try_ram_proximity_hit()
	if hit_wall:
		_begin_wall_stun()
		return
	if _sandbox_charge_tick():
		_try_editor_wall_stun()


func _try_ram_proximity_hit() -> void:
	if _target_is_valid() and _flat_to_target().length() <= RAM_HIT_RANGE:
		_try_hit_player(_charge_target)
		return
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("player"):
		if not (node is Node3D):
			continue
		var body := node as Node3D
		if not is_playable_charge_target(body):
			continue
		var flat := Vector3(
			body.global_position.x - global_position.x,
			0.0,
			body.global_position.z - global_position.z
		)
		if flat.length() <= RAM_HIT_RANGE:
			_try_hit_player(body)


func _try_editor_wall_stun() -> void:
	if not _charge.can_read_walls():
		return
	var world := get_world_3d()
	if world == null:
		return
	var from := global_position + Vector3(0.0, 0.45, 0.0)
	var ahead := from + _charge.locked_dir * RAM_WALL_RAY
	var exclude: Array = ChargerChargeScript.collect_wall_excludes(self, _held_ward)
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group("player"):
			if node is CollisionObject3D:
				exclude.append((node as CollisionObject3D).get_rid())
	var hit_dist := MonsterSightSense.occlude_distance(world, from, ahead, exclude)
	if hit_dist + 0.02 < from.distance_to(ahead):
		_begin_wall_stun()


func _try_hit_player(body: Node) -> void:
	var victim := resolve_playable_hit_body(body)
	if victim == null or victim == self:
		return
	var id := victim.get_instance_id()
	if _hit_bodies.has(id):
		return
	_hit_bodies[id] = true
	_begin_player_gore_pose()
	_launch_player(victim as Node3D)


func _begin_player_gore_pose() -> void:
	_set_head_pitch_goal(
		ChargerLaunchScript.toss_pitch_rad(charge_head_toss_deg), GORE_TOSS_SPEED_RAD
	)


func _launch_player(player: Node3D) -> void:
	var maze := _find_maze()
	var away := _charge.locked_dir
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
	var g := ChargerLaunchScript.gravity_of(player, gravity)
	if not GameState.is_multiplayer or player.is_multiplayer_authority():
		if stun.has_method("begin_charger_hit"):
			stun.call("begin_charger_hit", landing, g)
		if Engine.is_editor_hint() and not _lookdev_launch_stuns.has(stun):
			_lookdev_launch_stuns.append(stun)
		return
	var peer := int(player.get_multiplayer_authority())
	if peer > 0 and stun.has_method("rpc_begin_charger_hit"):
		stun.rpc_id(peer, "rpc_begin_charger_hit", landing)


func _tick_lookdev_launches(delta: float) -> void:
	var i := _lookdev_launch_stuns.size() - 1
	while i >= 0:
		var stun := _lookdev_launch_stuns[i]
		if stun == null or not is_instance_valid(stun):
			_lookdev_launch_stuns.remove_at(i)
		elif stun.has_method("is_stunned") and not bool(stun.call("is_stunned")):
			_lookdev_launch_stuns.remove_at(i)
		elif stun.has_method("tick_lookdev"):
			var host := stun.get_parent()
			stun.call("tick_lookdev", delta, ChargerLaunchScript.gravity_of(host, gravity))
		i -= 1


func _find_maze() -> Node:
	if not is_inside_tree():
		return null
	var match_root := GameWorldScript.find_match_root(get_tree())
	if match_root != null:
		var maze := match_root.get_node_or_null("MazeGenerator")
		if maze != null:
			return maze
	var node: Node = self
	while node != null:
		var maze := node.get_node_or_null("MazeGenerator")
		if maze != null:
			return maze
		node = node.get_parent()
	return get_tree().root.find_child("MazeGenerator", true, false)


func _interest_source() -> StringName:
	if _interest == null:
		return &""
	return _interest.get("source") as StringName


func _target_is_valid() -> bool:
	return is_playable_charge_target(_charge_target)


static func is_playable_charge_target(node: Node) -> bool:
	## Charge only at living PlayableCharacter (Apprentice / Headmaster / sandbox spawn).
	if node == null or not is_instance_valid(node):
		return false
	if not node.is_in_group("player"):
		return false
	var alive_value = node.get("is_alive")
	if alive_value != null and not bool(alive_value):
		return false
	if node is PlayableCharacter:
		return true
	return script_extends_playable(node.get_script() as Script)


static func resolve_playable_hit_body(node: Node) -> Node:
	var n := node
	while n != null:
		if is_playable_charge_target(n):
			return n
		n = n.get_parent()
	return null


static func script_extends_playable(scr: Script) -> bool:
	while scr != null:
		if scr.resource_path.ends_with("playable_character.gd"):
			return true
		scr = scr.get_base_script()
	return false


func _flat_to_target() -> Vector3:
	if not _target_is_valid():
		return _charge.locked_dir
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


func _snap_yaw(desired: Vector3) -> void:
	var flat := Vector3(desired.x, 0.0, desired.z)
	if flat.length_squared() < 0.0001:
		return
	var at := global_position + flat
	if global_position.distance_squared_to(at) > 0.0001:
		look_at(at, Vector3.UP)


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
	if _phase == ChargePhase.TELEGRAPH or _phase == ChargePhase.CHARGE:
		return true
	if _phase == ChargePhase.WALL_STUN:
		return false
	return _interest_source() == SIGHT_SOURCE


func _set_body_lean(pitch: float) -> void:
	if _body_lean != null:
		_body_lean.rotation.x = pitch * 0.4
	_sync_part_colliders()


func _set_head_pitch_goal(offset_rad: float, speed_rad: float) -> void:
	_head_pitch_goal = offset_rad
	_head_pitch_speed = maxf(speed_rad, 0.05)


func _tick_head_pitch(delta: float) -> void:
	_head_pitch = move_toward(_head_pitch, _head_pitch_goal, _head_pitch_speed * delta)
	_apply_head_pitch()


func _apply_head_pitch() -> void:
	if _head_lean != null:
		_head_lean.rotation.x = _head_rest_pitch + _head_pitch
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
