@tool
class_name Monster
extends Character

## Combat-ready AI. Senses → IDLE/PATROL/CHASE/ALERT. Eyes glow while chasing.

enum ChaseStyle { CLOSE_IN, KEEP_AWAY }

const BroomLocomotionScript := preload("res://scripts/headmaster/broom_locomotion.gd")
const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")
const MonsterInterestScript := preload("res://scripts/monsters/monster_interest.gd")
const MonsterCorpseScript := preload("res://scripts/monsters/monster_corpse.gd")
const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")
const MonsterChaseMoveScript := preload("res://scripts/monsters/monster_chase_move.gd")
const MonsterCombatSpacingScript := preload("res://scripts/monsters/monster_combat_spacing.gd")
const MonsterCasterCombatScript := preload("res://scripts/monsters/monster_caster_combat.gd")
const MonsterRangeGizmosScript := preload("res://scripts/monsters/monster_range_gizmos.gd")
const MonsterPatrolScript := preload("res://scripts/monsters/monster_patrol.gd")

const DEFAULT_TINT := Color(0.72, 0.28, 0.22, 1.0)
const DEFAULT_EYE_GLOW := Color(0.2, 0.55, 1.0, 1.0)
const KNOCKBACK_TIMER_SEC := 0.35
const DEFAULT_PLAYER_SOURCE := &"player"
const DEATH_IMPULSE_SCALE := 1.35
const EYE_EMISSION_ENERGY := 5.5
const EYE_LIGHT_ENERGY := 2.6
const RANGE_DISC_HEIGHT := 0.02
const HURT_UP_IMPULSE := 5.0
const HURT_KNOCKBACK_TIMER_SEC := 0.15
## Eye glow at 0 HP: near-black, slightly tinted from authored color.
const EYE_DEAD_RGB_SCALE := Vector3(0.04, 0.06, 0.04)
const EYE_DEAD_ENERGY_SCALE := 0.28

@export_group("Appearance")
@export var body_tint: Color = DEFAULT_TINT:
	set(value):
		if body_tint.is_equal_approx(value):
			return
		body_tint = value
		if is_inside_tree():
			_refresh_appearance()

@export var eye_glow_color: Color = DEFAULT_EYE_GLOW:
	set(value):
		if eye_glow_color.is_equal_approx(value):
			return
		eye_glow_color = value
		if is_inside_tree():
			_apply_eye_glow_from_health()

@export_group("Lookdev")
## When true, lookdev_pose drives eyes instead of live AI (workspace / editor preview).
@export var lookdev_override: bool = false:
	set(value):
		lookdev_override = value
		if is_inside_tree():
			_refresh_lookdev_eyes()

## Patrol hides chase eyes; Chase shows them. Workspace pose buttons set this.
@export var lookdev_pose: MonsterAIScript.LookdevPose = MonsterAIScript.LookdevPose.PATROL:
	set(value):
		lookdev_pose = value
		if is_inside_tree():
			_refresh_lookdev_eyes()

@export_group("Gizmos")
## Orange chase disc and yellow attack disc (meters = Combat chase/attack range).
@export var show_combat_ranges: bool = false:
	set(value):
		show_combat_ranges = value
		if is_inside_tree():
			_refresh_range_gizmos()

## Cyan hearing, green sight, yellow light, LOS ray — reads live Senses/ children.
@export var show_sense_ranges: bool = false:
	set(value):
		show_sense_ranges = value
		if is_inside_tree():
			var giz := get_node_or_null("SenseGizmos") as MonsterSenseGizmos
			if giz != null:
				giz.sync_enabled(value)

@export_group("Combat")
@export var max_health: float = 60.0
@export var move_speed: float = 3.2
@export var chase_range: float = 12.0:
	set(value):
		chase_range = value
		if is_inside_tree() and show_combat_ranges:
			_refresh_range_gizmos()

@export var attack_range: float = 1.4:
	set(value):
		attack_range = value
		if is_inside_tree() and show_combat_ranges:
			_refresh_range_gizmos()

@export var touch_damage: float = 8.0
@export var gravity: float = 18.0
@export var idle_duration_sec: float = 1.2
@export var patrol_speed: float = 2.4
@export var patrol_radius: float = 8.0
## After chase loses all sight/hearing interest for this long → ALERT.
@export_range(0.5, 30.0, 0.25) var lost_chase_to_alert_sec: float = 4.0
## How long ALERT lasts with no detection before returning to PATROL.
@export_range(1.0, 60.0, 0.25) var alert_duration_sec: float = 12.0
@export var death_linger_sec: float = 30.0
@export var death_fade_sec: float = 3.0
## CLOSE_IN rushes melee. KEEP_AWAY holds at keep_away_range.
@export var chase_style: ChaseStyle = ChaseStyle.CLOSE_IN
@export_range(1.0, 40.0, 0.5) var keep_away_range: float = 20.0
## Yaw turn rate (rad/s). Fast default so retreat/re-face reads as fluid.
@export_range(1.0, 24.0, 0.1) var face_turn_speed_rad: float = 10.0

@export_group("Chase move")
@export_range(0.25, 10.0, 0.05) var chase_wait_min_sec: float = 1.0
@export_range(0.25, 12.0, 0.05) var chase_wait_max_sec: float = 3.0
@export_range(0.25, 6.0, 0.05) var chase_strafe_min_sec: float = 1.2
@export_range(0.25, 6.0, 0.05) var chase_strafe_max_sec: float = 2.0
@export_range(0.25, 8.0, 0.05) var chase_retreat_min_sec: float = 1.2
@export_range(0.25, 8.0, 0.05) var chase_retreat_max_sec: float = 3.2
@export_range(0.1, 3.0, 0.05) var chase_optimal_eps: float = 0.55

var current_health: float = 60.0
var is_alive: bool = true

var _body_collision: CollisionShape3D
var _ai_state: int = MonsterAIScript.State.IDLE
var _idle_timer: float = 0.0
var _undetected_sec: float = 0.0
var _alert_timer: float = 0.0
var _patrol: RefCounted = null
var _interest: RefCounted = null
var _knockback_vel: Vector3 = Vector3.ZERO
var _knockback_timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _senses_root: Node = null
var _last_hit_dir: Vector3 = Vector3.FORWARD
var _dying: bool = false
var _eyes_root: Node3D = null
var _eye_meshes: Array[MeshInstance3D] = []
var _eye_light: OmniLight3D = null
var _eyes_chasing: bool = false
var _chase_range_mesh: MeshInstance3D = null
var _attack_range_mesh: MeshInstance3D = null
var _cast_windup_left: float = 0.0
var _casting_ability: Node = null
var _cast_prefer_index: int = 0
var _chase_move: MonsterChaseMove = null
var _lookdev_aggro: Node3D = null

func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group("monster")
		add_to_group("combat_target")
	current_health = max_health
	is_alive = true
	_rng.randomize()
	_chase_move = MonsterChaseMoveScript.new() as MonsterChaseMove
	_sync_chase_move_config()
	_senses_root = get_node_or_null("Senses")
	_cache_eyes()
	_refresh_appearance()
	var live_ai := bool(get_meta("lookdev_live_ai", false))
	if lookdev_override or (Engine.is_editor_hint() and not live_ai):
		_refresh_lookdev_eyes()
	else:
		_set_chase_eyes_active(false)
	_refresh_range_gizmos()
	if Engine.is_editor_hint() and not live_ai:
		set_physics_process(false)
		return
	if Engine.is_editor_hint() and live_ai:
		set_physics_process(false)
		set_process(true)
		call_deferred("_begin_patrol")
		return
	_enter_idle()
	set_physics_process(true)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() and bool(get_meta("lookdev_live_ai", false)):
		_physics_process(delta)


func _sync_chase_move_config() -> void:
	if _chase_move == null:
		return
	_chase_move.configure(
		_rng, chase_wait_min_sec, chase_wait_max_sec,
		chase_strafe_min_sec, chase_strafe_max_sec,
		chase_retreat_min_sec, chase_retreat_max_sec, chase_optimal_eps
	)


func apply_summon_appearance(tint: Color, p_eye_glow_color: Color = DEFAULT_EYE_GLOW) -> void:
	body_tint = tint
	eye_glow_color = p_eye_glow_color
	_refresh_appearance()


func set_lookdev_pose(pose: MonsterAIScript.LookdevPose, enable_override: bool = true) -> void:
	lookdev_override = enable_override
	lookdev_pose = pose

func set_lookdev_aggro(target: Node3D) -> void:
	_lookdev_aggro = target
	lookdev_override = lookdev_override and not is_instance_valid(target)
	set_physics_process(not Engine.is_editor_hint() or is_instance_valid(target))


func get_ability_placeholders() -> Array[Node]:
	var out: Array[Node] = []
	var root := get_node_or_null("Abilities")
	if root == null:
		return out
	for child in root.get_children():
		if child.has_method("preview_cast"):
			out.append(child)
	return out


func get_combat_abilities() -> Array[Node]:
	## Abilities that support chase casting (can_cast / begin_cast / range check).
	var out: Array[Node] = []
	var root := get_node_or_null("Abilities")
	if root == null:
		return out
	for child in root.get_children():
		if "participates_in_cast_rotation" in child:
			if not bool(child.get("participates_in_cast_rotation")):
				continue
		if (
			child.has_method("can_cast")
			and child.has_method("begin_cast")
			and child.has_method("is_target_in_range")
		):
			out.append(child)
	return out


func is_ai_chasing() -> bool:
	return _ai_state == MonsterAIScript.State.CHASE


func is_ai_alert() -> bool:
	return _ai_state == MonsterAIScript.State.ALERT


func take_damage(amount: float, from: Node3D = null) -> void:
	if not is_alive:
		return
	_remember_hit_dir(from)
	current_health = MonsterAIScript.apply_damage(current_health, amount)
	if MonsterAIScript.is_dead(current_health):
		die()
		return
	_apply_hurt_knockback()
	_apply_eye_glow_from_health()


func heal(amount: float) -> void:
	if not is_alive:
		return
	current_health = MonsterAIScript.apply_heal(current_health, amount, max_health)
	_apply_eye_glow_from_health()


func die() -> void:
	if _dying or not is_alive:
		return
	_dying = true
	is_alive = false
	current_health = 0.0
	_ai_state = MonsterAIScript.State.IDLE
	_interest = null
	_undetected_sec = 0.0
	_alert_timer = 0.0
	_cancel_cast()
	_kill_owned_summons()
	_set_chase_eyes_active(false)
	velocity = Vector3.ZERO
	set_physics_process(false)
	if is_in_group("monster"):
		remove_from_group("monster")
	if is_in_group("combat_target"):
		remove_from_group("combat_target")
	_spawn_ragdoll_corpse()
	queue_free()


func get_summon_host() -> Node:
	return get_node_or_null("SummonHost")


func _kill_owned_summons() -> void:
	var host := get_summon_host()
	if host != null and host.has_method("kill_all"):
		host.call("kill_all")


func apply_fireball_knockback(fireball_dir: Vector3) -> void:
	if not is_alive:
		return
	if fireball_dir.length_squared() > 0.0001:
		_last_hit_dir = fireball_dir.normalized()
	var impulse: Vector3 = BroomLocomotionScript.knockback_impulse(fireball_dir)
	_knockback_vel = impulse
	_knockback_timer = KNOCKBACK_TIMER_SEC
	velocity += impulse


func _apply_hurt_knockback() -> void:
	velocity.y = maxf(velocity.y, HURT_UP_IMPULSE)
	_knockback_vel.y = maxf(_knockback_vel.y, HURT_UP_IMPULSE * 0.45)
	_knockback_timer = maxf(_knockback_timer, HURT_KNOCKBACK_TIMER_SEC)


func get_health_ratio() -> float:
	if max_health <= 0.001:
		return 1.0
	return clampf(current_health / max_health, 0.0, 1.0)


func _apply_eye_glow_from_health() -> void:
	## Full HP = authored glow; near death = darker / dimmer (Rat Queen green dims hard).
	var t := 1.0 if Engine.is_editor_hint() else get_health_ratio()
	var dead := Color(
		eye_glow_color.r * EYE_DEAD_RGB_SCALE.x,
		eye_glow_color.g * EYE_DEAD_RGB_SCALE.y,
		eye_glow_color.b * EYE_DEAD_RGB_SCALE.z,
		1.0
	)
	var color := eye_glow_color.lerp(dead, 1.0 - t)
	var energy := lerpf(EYE_DEAD_ENERGY_SCALE, 1.0, t)
	_apply_eye_glow_color(color, energy)


func _refresh_appearance() -> void:
	_ensure_mesh_refs()
	if _body_mesh != null and _head_mesh != null:
		_character_color = body_tint
		_apply_character_color(body_tint)
	_tint_optional_body_parts()
	_apply_eye_glow_from_health()


func _tint_optional_body_parts() -> void:
	## Type scenes may author MidBody / hand spheres that should match body_tint.
	_tint_mesh_instance(get_node_or_null("%MidBody") as MeshInstance3D, body_tint)
	_tint_optional_hands()


func _tint_optional_hands() -> void:
	for path in ["%RightHand", "%LeftHand"]:
		_tint_mesh_instance(get_node_or_null(path) as MeshInstance3D, body_tint)


func _tint_mesh_instance(mesh_inst: MeshInstance3D, color: Color) -> void:
	var mat := _authored_material(mesh_inst)
	if mat == null:
		return
	mat.albedo_color = color


func _ensure_mesh_refs() -> void:
	if head == null:
		head = get_node_or_null("%Head") as Node3D
	if _body_mesh == null:
		_body_mesh = get_node_or_null("%Body") as MeshInstance3D
	if _head_mesh == null:
		_head_mesh = get_node_or_null("%HeadMesh") as MeshInstance3D
	if _body_collision == null:
		_body_collision = get_node_or_null("%CollisionShape3D") as CollisionShape3D


func _cache_eyes() -> void:
	_eyes_root = get_node_or_null("%Eyes") as Node3D
	if _eyes_root == null:
		_eyes_root = get_node_or_null("Head/Eyes") as Node3D
	_eye_meshes.clear()
	_eye_light = null
	if _eyes_root == null:
		return
	for child in _eyes_root.get_children():
		if child is MeshInstance3D:
			_eye_meshes.append(child as MeshInstance3D)
		elif child is OmniLight3D:
			_eye_light = child as OmniLight3D


func _apply_eye_glow_color(color: Color, energy_scale: float = 1.0) -> void:
	if _eyes_root == null:
		_cache_eyes()
	var mat: StandardMaterial3D = null
	if not _eye_meshes.is_empty():
		mat = _authored_material(_eye_meshes[0])
	if mat != null:
		mat.albedo_color = color
		mat.emission = color
		mat.emission_energy_multiplier = EYE_EMISSION_ENERGY * energy_scale
	if _eye_light != null:
		_eye_light.light_color = color
		_eye_light.light_energy = EYE_LIGHT_ENERGY * energy_scale
		_eye_light.light_cull_mask = WorldVisualLayersScript.SCENE_LIGHT_MASK


func _refresh_lookdev_eyes() -> void:
	if not lookdev_override and not Engine.is_editor_hint():
		return
	_set_chase_eyes_active(MonsterAIScript.lookdev_eyes_visible(lookdev_pose))


func _set_chase_eyes_active(active: bool) -> void:
	_eyes_chasing = active
	if _eyes_root == null:
		_cache_eyes()
	if _eyes_root != null:
		_eyes_root.visible = active


func _refresh_range_gizmos() -> void:
	var result: Dictionary = MonsterRangeGizmosScript.refresh(
		self, show_combat_ranges, _chase_range_mesh, _attack_range_mesh,
		chase_range, attack_range, RANGE_DISC_HEIGHT
	)
	_chase_range_mesh = result.get("chase") as MeshInstance3D
	_attack_range_mesh = result.get("attack") as MeshInstance3D


func _remember_hit_dir(from: Node3D) -> void:
	if from == null:
		return
	var away := global_position - from.global_position
	away.y = 0.0
	if away.length_squared() > 0.0001:
		_last_hit_dir = away.normalized()


func _spawn_ragdoll_corpse() -> void:
	## No skeleton on the character shell — tumble as one RigidBody with body/head meshes.
	var parent_node := get_parent()
	if parent_node == null or not is_inside_tree():
		return
	var corpse := RigidBody3D.new()
	corpse.name = "%sCorpse" % name
	corpse.set_script(MonsterCorpseScript)
	parent_node.add_child(corpse)
	corpse.global_transform = global_transform

	var body_colliders: Array[CollisionShape3D] = []
	for child in get_children():
		if child is CollisionShape3D:
			body_colliders.append(child as CollisionShape3D)
	for collider in body_colliders:
		_reparent_to_corpse(collider, corpse)
	_reparent_to_corpse(_body_mesh, corpse)
	_reparent_to_corpse(get_node_or_null("%MidBody"), corpse)
	_reparent_to_corpse(head, corpse)

	var impulse: Vector3 = BroomLocomotionScript.knockback_impulse(_last_hit_dir)
	impulse *= DEATH_IMPULSE_SCALE
	if corpse.has_method("begin_death_sequence"):
		corpse.call(
			"begin_death_sequence",
			impulse,
			death_linger_sec,
			death_fade_sec
		)


func _reparent_to_corpse(node: Node, corpse: Node) -> void:
	if node == null or corpse == null:
		return
	var xf: Transform3D
	var is_spatial := node is Node3D
	if is_spatial:
		xf = (node as Node3D).global_transform
	var old_parent := node.get_parent()
	if old_parent != null:
		old_parent.remove_child(node)
	corpse.add_child(node)
	if is_spatial:
		(node as Node3D).global_transform = xf


## Collects candidates (default players + senses) and prefers one. Override to replace.
func _gather_interest() -> RefCounted:
	if _lookdev_aggro != null and is_instance_valid(_lookdev_aggro):
		return MonsterInterestScript.from_target(_lookdev_aggro, 2.0, &"lookdev")
	var candidates: Array = []
	_append_default_interest_candidates(candidates)
	_append_sense_interest_candidates(candidates)
	return _prefer_interest(candidates)


## Default: nearest living player in chase_range as a proximity-scored interest.
func _append_default_interest_candidates(out: Array) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var players := tree.get_nodes_in_group("player")
	var positions: Array = []
	var alive_flags: Array = []
	var nodes: Array = []
	for node in players:
		if node is Node3D:
			var n3 := node as Node3D
			positions.append(n3.global_position)
			var alive_value = n3.get("is_alive")
			alive_flags.append(true if alive_value == null else bool(alive_value))
			nodes.append(n3)
	var idx: int = MonsterAIScript.pick_nearest_target_index(
		global_position, positions, alive_flags, chase_range
	)
	if idx < 0:
		return
	var target: Node3D = nodes[idx] as Node3D
	var urgency: float = MonsterAIScript.proximity_urgency(
		global_position, target.global_position, chase_range
	)
	out.append(
		MonsterInterestScript.from_target(target, urgency, DEFAULT_PLAYER_SOURCE)
	)


## Reads MonsterSense children under Senses/.
func _append_sense_interest_candidates(out: Array) -> void:
	if _senses_root == null:
		_senses_root = get_node_or_null("Senses")
	if _senses_root == null:
		return
	for child in _senses_root.get_children():
		if MonsterSense.can_append_from(child):
			child.call("append_interest_candidates", self, out)


## Default preferencing: highest urgency. Children override to weight sources.
func _prefer_interest(candidates: Array) -> RefCounted:
	return MonsterAIScript.prefer_highest_urgency(candidates)

func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	if Engine.is_editor_hint() and not bool(get_meta("lookdev_live_ai", false)):
		return
	MonsterAIScript.apply_gravity(self, delta, gravity)

	_interest = _gather_interest()
	var has_interest := _interest_is_actionable(_interest)
	_ai_state = MonsterAIScript.resolve_state(_ai_state, has_interest)
	_update_alert_timers(delta, has_interest)

	var chase_target: Node3D = null
	if _interest != null:
		chase_target = _interest.get("target") as Node3D

	var caster_chase := MonsterCasterCombatScript.tick_monster_if_present(
		self, delta, _ai_state, chase_target
	)
	if caster_chase:
		pass
	elif _casting_ability != null:
		_tick_cast_windup(delta, chase_target)
	elif _try_start_cast(chase_target):
		pass
	else:
		match _ai_state:
			MonsterAIScript.State.IDLE:
				_tick_idle(delta)
			MonsterAIScript.State.PATROL:
				_tick_patrol(delta)
			MonsterAIScript.State.CHASE:
				_tick_chase(delta)
			MonsterAIScript.State.ALERT:
				_tick_alert(delta)

	if lookdev_override:
		_refresh_lookdev_eyes()
	else:
		var want_eyes := MonsterAIScript.chase_eyes_visible(_ai_state)
		if want_eyes != _eyes_chasing:
			_set_chase_eyes_active(want_eyes)

	_apply_knockback_bleed(delta)
	MonsterAIScript.apply_move(self, delta)


func _update_alert_timers(delta: float, has_interest: bool) -> void:
	## 4s fully undetected after chase → ALERT; 12s more undetected → PATROL.
	if has_interest:
		_undetected_sec = 0.0
		_alert_timer = 0.0
		return
	if _ai_state == MonsterAIScript.State.CHASE:
		_undetected_sec += delta
		if _undetected_sec >= lost_chase_to_alert_sec:
			_enter_alert()
	elif _ai_state == MonsterAIScript.State.ALERT:
		_alert_timer += delta
		if _alert_timer >= alert_duration_sec:
			_undetected_sec = 0.0
			_alert_timer = 0.0
			_begin_patrol()
	else:
		_undetected_sec = 0.0
		_alert_timer = 0.0


func _interest_is_actionable(interest: RefCounted) -> bool:
	if interest == null:
		return false
	if interest.has_method("is_actionable"):
		return bool(interest.call("is_actionable"))
	return false


func _enter_idle() -> void:
	_ai_state = MonsterAIScript.State.IDLE
	_idle_timer = 0.0
	_undetected_sec = 0.0
	_alert_timer = 0.0
	_clear_chase_move()
	velocity.x = 0.0
	velocity.z = 0.0


func _enter_alert() -> void:
	_cancel_cast()
	_ai_state = MonsterAIScript.State.ALERT
	_undetected_sec = 0.0
	_alert_timer = 0.0
	_clear_chase_move()
	velocity.x = 0.0
	velocity.z = 0.0


func _tick_idle(delta: float) -> void:
	_idle_timer += delta
	velocity.x = 0.0
	velocity.z = 0.0
	if _idle_timer >= idle_duration_sec:
		_begin_patrol()


func _ensure_patrol() -> RefCounted:
	if _patrol == null:
		_patrol = MonsterPatrolScript.new()
	return _patrol


func _begin_patrol() -> void:
	_ai_state = MonsterAIScript.State.PATROL
	_undetected_sec = 0.0
	_alert_timer = 0.0
	_clear_chase_move()
	_ensure_patrol().call("begin", self, _rng, patrol_radius)


func _tick_patrol(_delta: float) -> void:
	var patrol := _ensure_patrol()
	patrol.call("tick", self, _rng)
	var desired: Vector3 = patrol.call("follow_velocity", self, patrol_speed)
	velocity.x = desired.x
	velocity.z = desired.z
	_face_horizontal(desired)


func _tick_alert(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _tick_chase(delta: float) -> void:
	if not _interest_is_actionable(_interest):
		## Grace window before ALERT: hold position, keep eyes on.
		_cancel_cast()
		_clear_chase_move()
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var goal: Vector3 = _interest.call("resolved_goal_position", global_position)
	var target: Node3D = _interest.get("target") as Node3D

	if _try_tick_chase_reposition(delta, target):
		return

	if _tick_chase_reposition_wait(delta, target):
		return

	_tick_chase_approach(goal, target)


func _tick_chase_reposition_wait(delta: float, target: Node3D) -> bool:
	## Continuous kite loop while near optimal range. Returns true if handled.
	if not _uses_continuous_chase_move_timer():
		return false
	if target == null or not is_instance_valid(target):
		return false
	_ensure_chase_wait_armed()
	var dist := MonsterAIScript.horizontal_distance(
		global_position, target.global_position
	)
	var optimal := _optimal_combat_range()
	if dist > optimal + chase_optimal_eps:
		return false
	if _tick_chase_wait_and_decide(delta, target, dist, optimal):
		if _try_tick_chase_reposition(delta, target):
			return true
	_hold_chase_while_waiting(target)
	return true


func _tick_chase_approach(goal: Vector3, target: Node3D) -> void:
	if (
		chase_style == ChaseStyle.CLOSE_IN
		and target != null
		and is_instance_valid(target)
		and _has_ranged_spacing_abilities()
	):
		if _tick_ranged_cast_chase(target):
			return

	if chase_style == ChaseStyle.KEEP_AWAY and target != null and is_instance_valid(target):
		_move_keep_away(target)
		return

	var to_goal := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
	if to_goal.length() <= attack_range:
		velocity.x = 0.0
		velocity.z = 0.0
		if target != null and is_instance_valid(target):
			_try_touch_damage(target)
		return
	var desired: Vector3 = MonsterAIScript.horizontal_velocity_toward(
		global_position, goal, move_speed, velocity.y
	)
	velocity.x = desired.x
	velocity.z = desired.z
	_face_horizontal(desired)


func _uses_continuous_chase_move_timer() -> bool:
	## Children (e.g. Rat Queen) can disable the free 1–3s kite loop.
	return true


func is_chase_retreating() -> bool:
	return _chase_move != null and _chase_move.is_retreating()


func is_chase_moving() -> bool:
	return _chase_move != null and _chase_move.is_moving()


func _clear_chase_move() -> void:
	if _chase_move != null:
		_chase_move.clear()


func _ensure_chase_wait_armed() -> void:
	_sync_chase_move_config()
	if _chase_move != null:
		_chase_move.ensure_wait_armed()


func _arm_chase_wait() -> void:
	_sync_chase_move_config()
	if _chase_move != null:
		_chase_move.arm_wait()


func _optimal_combat_range() -> float:
	if chase_style == ChaseStyle.KEEP_AWAY:
		return keep_away_range
	if _has_ranged_spacing_abilities():
		var ability := MonsterCombatSpacingScript.preferred_spacing(get_combat_abilities())
		if ability != null:
			return MonsterCombatSpacingScript.preferred_cast_ideal(ability)
	return attack_range


func _max_chase_reposition_distance() -> float:
	return MonsterAIScript.max_aggro_move_distance(chase_range)


func _tick_chase_wait_and_decide(
	delta: float, target: Node3D, dist: float, optimal: float
) -> bool:
	_sync_chase_move_config()
	if _chase_move == null:
		return false
	return _chase_move.tick_wait_and_decide(
		delta, self, target, dist, optimal, _max_chase_reposition_distance()
	)


func start_chase_strafe(target: Node3D, side_sign: float, duration_sec: float) -> void:
	_sync_chase_move_config()
	if _chase_move != null:
		_chase_move.start_strafe(self, target, side_sign, duration_sec)


func start_chase_retreat(target: Node3D, side_sign: float, duration_sec: float) -> void:
	if MonsterCasterCombatScript.try_combo_instead_of_retreat_on(self, target):
		return
	_begin_chase_retreat_move(target, side_sign, duration_sec)


func _begin_chase_retreat_move(
	target: Node3D, side_sign: float, duration_sec: float
) -> void:
	_sync_chase_move_config()
	if _chase_move != null:
		_chase_move.start_retreat(
			self, target, side_sign, duration_sec, _max_chase_reposition_distance()
		)


func _try_tick_chase_reposition(delta: float, target: Node3D) -> bool:
	_sync_chase_move_config()
	if _chase_move == null:
		return false
	return _chase_move.tick_move(
		delta,
		self,
		target,
		move_speed,
		attack_range,
		_max_chase_reposition_distance(),
		Callable(self, "_face_horizontal"),
		Callable(self, "_try_touch_damage")
	)


func _hold_chase_while_waiting(target: Node3D) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if target == null or not is_instance_valid(target):
		return
	var toward := Vector3(
		target.global_position.x - global_position.x,
		0.0,
		target.global_position.z - global_position.z
	)
	_face_horizontal(toward)
	if toward.length() <= attack_range:
		_try_touch_damage(target)


func _has_ranged_spacing_abilities() -> bool:
	for ability in get_combat_abilities():
		if "requires_target" in ability and not bool(ability.get("requires_target")):
			continue
		if "min_cast_range" in ability and float(ability.get("min_cast_range")) > 0.5:
			return true
	return false


func _move_keep_away(target: Node3D) -> void:
	MonsterCombatSpacingScript.apply_keep_away(
		self, target, keep_away_range, move_speed, Callable(self, "_face_horizontal")
	)


func _try_start_cast(target: Node3D) -> bool:
	if is_chase_retreating():
		return false
	var ready_ability := _pick_ready_ability(target)
	if ready_ability == null:
		return false
	_begin_ability_windup(ready_ability)
	_tick_cast_windup(0.0, target)
	return true


## Keep cast spacing and fire when in band. Returns true when chase is handled.
func _tick_ranged_cast_chase(target: Node3D) -> bool:
	var ready_ability := _pick_ready_ability(target)
	if ready_ability != null:
		_begin_ability_windup(ready_ability)
		_tick_cast_windup(0.0, target)
		return true

	var awaiting := MonsterCombatSpacingScript.first_ranged_castable(get_combat_abilities())
	if awaiting != null:
		_move_toward_cast_range(target, awaiting)
		return true

	var spacer := MonsterCombatSpacingScript.preferred_spacing(get_combat_abilities())
	if spacer != null:
		_move_toward_cast_range(target, spacer)
		return true
	return false


func _move_toward_cast_range(target: Node3D, ability: Node) -> void:
	MonsterCombatSpacingScript.apply_cast_band(
		self, target, ability, move_speed, Callable(self, "_face_horizontal")
	)


func _pick_ready_ability(target: Node3D) -> Node:
	var abilities := get_combat_abilities()
	if abilities.is_empty():
		return null
	var count := abilities.size()
	for i in count:
		var idx := (_cast_prefer_index + i) % count
		var ability: Node = abilities[idx]
		if ability.has_method("is_ready_to_cast"):
			if not bool(ability.call("is_ready_to_cast", self, target)):
				continue
		else:
			if not bool(ability.call("can_cast")):
				continue
			if not bool(ability.call("is_target_in_range", self, target)):
				continue
		_cast_prefer_index = (idx + 1) % count
		return ability
	return null


func _begin_ability_windup(ability: Node) -> void:
	_casting_ability = ability
	_cast_windup_left = 0.55
	if "windup_sec" in ability:
		_cast_windup_left = float(ability.get("windup_sec"))
	velocity.x = 0.0
	velocity.z = 0.0
	if ability.has_method("start_windup_fx"):
		ability.call("start_windup_fx", self)


func _tick_cast_windup(delta: float, target: Node3D) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if target != null and is_instance_valid(target):
		var toward := Vector3(
			target.global_position.x - global_position.x,
			0.0,
			target.global_position.z - global_position.z
		)
		_face_horizontal(toward)
	_cast_windup_left -= delta
	if _cast_windup_left > 0.0:
		return
	var ability := _casting_ability
	_casting_ability = null
	_cast_windup_left = 0.0
	if ability == null or not is_instance_valid(ability):
		return
	var needs_target := true
	if "requires_target" in ability:
		needs_target = bool(ability.get("requires_target"))
	if needs_target and (target == null or not is_instance_valid(target)):
		if ability.has_method("stop_windup_fx"):
			ability.call("stop_windup_fx")
		return
	if ability.has_method("begin_cast"):
		ability.call("begin_cast", self, target)
		_on_ability_cast_fired(ability)


func _on_ability_cast_fired(_ability: Node) -> void:
	## Override in children (e.g. Rat Queen post-Command-Pack retreat).
	pass


func _cancel_cast() -> void:
	if _casting_ability != null and is_instance_valid(_casting_ability):
		if _casting_ability.has_method("stop_windup_fx"):
			_casting_ability.call("stop_windup_fx")
	_casting_ability = null
	_cast_windup_left = 0.0


func _try_touch_damage(target: Node3D) -> void:
	if is_chase_retreating() or target == null or not target.has_method("take_damage"):
		return
	target.call("take_damage", touch_damage * get_physics_process_delta_time(), self)


func _face_horizontal(desired_vel: Vector3) -> void:
	## Strafe keeps facing the player; retreat/approach turn at face_turn_speed_rad.
	_face_horizontal_at_speed(
		desired_vel, get_physics_process_delta_time(), face_turn_speed_rad
	)


func _face_horizontal_at_speed(desired: Vector3, delta: float, speed_rad: float) -> void:
	rotation.y = MonsterAIScript.rotate_yaw_toward(rotation.y, desired, speed_rad, delta)


func _apply_knockback_bleed(delta: float) -> void:
	if _knockback_timer <= 0.0:
		return
	_knockback_timer -= delta
	velocity.x += _knockback_vel.x * 0.35
	velocity.z += _knockback_vel.z * 0.35
	_knockback_vel = _knockback_vel.move_toward(Vector3.ZERO, 28.0 * delta)
