class_name Summon
extends Character

## Host-linked minion base. Character → Summon (not Monster).
## Leash + bind/death + command aggro + sense relay. No cast windup, KEEP_AWAY,
## Abilities, or chase-move kite timers.

enum AggroMode { BOUND, HOST_MIRROR, COMMAND_HUNT, COMMAND_INVESTIGATE, RECALL }

const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")
const MonsterInterestScript := preload("res://scripts/monsters/monster_interest.gd")
const MonsterCorpseScript := preload("res://scripts/monsters/monster_corpse.gd")
const BroomLocomotionScript := preload("res://scripts/headmaster/broom_locomotion.gd")
const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")

const FORCED_HUNT_SOURCE := &"forced_hunt"
const FORCED_INVESTIGATE_SOURCE := &"forced_investigate"
const FORCED_HUNT_URGENCY := 2.0
const RELAY_SIGHT_URGENCY := 2.25
const RELAY_HEARING_URGENCY := 1.85
const PATROL_EDGE_MIN := 0.72
const PATROL_EDGE_MAX := 0.96
const PATROL_ARRIVE_DIST := 0.45
const RECALL_ARRIVE_DIST := 1.15
const RECALL_SOURCE := &"recall"
const KNOCKBACK_TIMER_SEC := 0.35
const HURT_UP_IMPULSE := 5.0
const HURT_KNOCKBACK_TIMER_SEC := 0.15
const DEATH_IMPULSE_SCALE := 1.35
const EYE_EMISSION_ENERGY := 5.5
const EYE_LIGHT_ENERGY := 2.6
const EYE_DEAD_RGB_SCALE := Vector3(0.04, 0.06, 0.04)
const EYE_DEAD_ENERGY_SCALE := 0.28
const DEFAULT_TINT := Color(0.55, 0.45, 0.35, 1.0)
const DEFAULT_EYE_GLOW := Color(0.25, 1.0, 0.35, 1.0)

@export_group("Appearance")
@export var body_tint: Color = DEFAULT_TINT:
	set(value):
		if body_tint.is_equal_approx(value):
			return
		body_tint = value
		if is_node_ready():
			_refresh_appearance()

@export var eye_glow_color: Color = DEFAULT_EYE_GLOW:
	set(value):
		if eye_glow_color.is_equal_approx(value):
			return
		eye_glow_color = value
		if is_node_ready():
			_apply_eye_glow_from_health()

@export_group("Gizmos")
## Cyan hearing, green sight, yellow light, LOS ray — reads live Senses/ children.
@export var show_sense_ranges: bool = false:
	set(value):
		show_sense_ranges = value
		if is_inside_tree():
			var giz := get_node_or_null("SenseGizmos") as MonsterSenseGizmos
			if giz != null:
				giz.sync_enabled(value)

@export_group("Combat")
@export var max_health: float = 10.0
@export var move_speed: float = 4.0
@export var chase_range: float = 10.0
@export var attack_range: float = 0.85
@export var touch_damage: float = 0.0
@export var gravity: float = 18.0
@export var idle_duration_sec: float = 1.2
@export var patrol_radius: float = 4.0
@export_range(0.5, 30.0, 0.25) var lost_chase_to_alert_sec: float = 4.0
@export_range(1.0, 60.0, 0.25) var alert_duration_sec: float = 12.0
@export var death_linger_sec: float = 30.0
@export var death_fade_sec: float = 3.0
@export_range(1.0, 24.0, 0.1) var face_turn_speed_rad: float = 10.0

@export_group("Leash")
@export var leash_radius: float = 10.0
@export var leash_enabled: bool = true

var current_health: float = 10.0
var is_alive: bool = true
var host: Node = null
var forced_hunt_target: Node3D = null
var forced_hunt_goal: Vector3 = Vector3.ZERO
var has_forced_hunt_goal: bool = false
var aggro_mode: int = AggroMode.BOUND

var _body_collision: CollisionShape3D
var _ai_state: int = MonsterAIScript.State.IDLE
var _idle_timer: float = 0.0
var _undetected_sec: float = 0.0
var _alert_timer: float = 0.0
var _patrol_goal: Vector3 = Vector3.ZERO
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


func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh_appearance()
		return
	add_to_group("summon")
	add_to_group("monster")
	add_to_group("combat_target")
	current_health = max_health
	is_alive = true
	_rng.randomize()
	_ensure_mesh_refs()
	_cache_eyes()
	_senses_root = get_node_or_null("Senses")
	_refresh_appearance()
	_enter_idle()


func bind_to_host(p_host: Node, p_leash_radius: float = 10.0) -> void:
	host = p_host
	leash_radius = maxf(p_leash_radius, 0.5)
	leash_enabled = true
	aggro_mode = AggroMode.BOUND
	patrol_radius = minf(patrol_radius, leash_radius * 0.35)
	if host != null and not host.tree_exiting.is_connected(_on_host_exiting):
		host.tree_exiting.connect(_on_host_exiting)


func set_forced_hunt(target: Node3D, free_leash: bool = true) -> void:
	forced_hunt_target = target
	has_forced_hunt_goal = false
	aggro_mode = AggroMode.COMMAND_HUNT
	if free_leash:
		leash_enabled = false


func set_forced_investigate(world_position: Vector3, free_leash: bool = true) -> void:
	forced_hunt_target = null
	forced_hunt_goal = world_position
	has_forced_hunt_goal = true
	aggro_mode = AggroMode.COMMAND_INVESTIGATE
	if free_leash:
		leash_enabled = false


func clear_forced_hunt() -> void:
	forced_hunt_target = null
	has_forced_hunt_goal = false
	leash_enabled = true
	if aggro_mode != AggroMode.RECALL:
		aggro_mode = AggroMode.BOUND


func begin_recall() -> void:
	## Host calmed — run home, then resume leashed search (eyes off).
	forced_hunt_target = null
	has_forced_hunt_goal = false
	leash_enabled = true
	aggro_mode = AggroMode.RECALL
	_interest = null
	_set_chase_eyes_active(false)
	_ai_state = MonsterAIScript.State.CHASE


func finish_recall() -> void:
	if aggro_mode != AggroMode.RECALL:
		return
	aggro_mode = AggroMode.BOUND
	_set_chase_eyes_active(false)
	_on_recall_finished()


func _on_recall_finished() -> void:
	## Default: spread into leashed patrol. Subclasses may override.
	_begin_patrol()


func sync_from_host_state(state: int) -> void:
	## Host AI posture. Commands override while host is hot; calm host recalls pack.
	if (
		state == MonsterAIScript.State.CHASE
		or state == MonsterAIScript.State.ALERT
	):
		if (
			aggro_mode == AggroMode.COMMAND_HUNT
			or aggro_mode == AggroMode.COMMAND_INVESTIGATE
		):
			return
		## Interrupts RECALL / BOUND into host-mirror vigilance.
		aggro_mode = AggroMode.HOST_MIRROR
		if (
			_ai_state == MonsterAIScript.State.IDLE
			or _ai_state == MonsterAIScript.State.PATROL
		):
			_enter_alert()
		return
	## Host returned to idle/patrol — recall to his side.
	begin_recall()


func get_relayed_player_interest() -> RefCounted:
	if _interest == null:
		return null
	var target: Node3D = _interest.get("target") as Node3D
	if target == null or not is_instance_valid(target):
		return null
	if not target.is_in_group("player"):
		return null
	var source := str(_interest.get("source"))
	if source == "hearing" or source == "summon_hearing":
		return null
	return MonsterInterestScript.from_target(
		target, RELAY_SIGHT_URGENCY, &"summon_sight"
	)


func get_relayed_hearing_interest() -> RefCounted:
	## Prefer current hearing interest; otherwise sample Hearing senses.
	if _interest != null:
		var source := str(_interest.get("source"))
		if source == "hearing" or source == "summon_hearing":
			if bool(_interest.call("is_actionable")):
				var goal: Vector3 = _interest.call(
					"resolved_goal_position", global_position
				)
				return MonsterInterestScript.from_position(
					goal, RELAY_HEARING_URGENCY, &"summon_hearing"
				)
	var candidates: Array = []
	_append_hearing_sense_candidates(candidates)
	var best: RefCounted = MonsterAIScript.prefer_highest_urgency(candidates)
	if best == null or not bool(best.call("is_actionable")):
		return null
	var goal_pos: Vector3 = best.call("resolved_goal_position", global_position)
	return MonsterInterestScript.from_position(
		goal_pos, RELAY_HEARING_URGENCY, &"summon_hearing"
	)


func append_relayed_interests(out: Array) -> void:
	var sight := get_relayed_player_interest()
	if sight != null:
		out.append(sight)
	var hearing := get_relayed_hearing_interest()
	if hearing != null:
		out.append(hearing)


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
	_set_chase_eyes_active(false)
	velocity = Vector3.ZERO
	set_physics_process(false)
	if is_in_group("summon"):
		remove_from_group("summon")
	if is_in_group("monster"):
		remove_from_group("monster")
	if is_in_group("combat_target"):
		remove_from_group("combat_target")
	_spawn_ragdoll_corpse()
	queue_free()


func apply_fireball_knockback(fireball_dir: Vector3) -> void:
	if not is_alive:
		return
	if fireball_dir.length_squared() > 0.0001:
		_last_hit_dir = fireball_dir.normalized()
	var impulse: Vector3 = BroomLocomotionScript.knockback_impulse(fireball_dir)
	_knockback_vel = impulse
	_knockback_timer = KNOCKBACK_TIMER_SEC
	velocity += impulse


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_alive:
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	_interest = _gather_interest()
	var has_interest := _interest_is_actionable(_interest)
	_ai_state = MonsterAIScript.resolve_state(_ai_state, has_interest)
	_update_alert_timers(delta, has_interest)

	match _ai_state:
		MonsterAIScript.State.IDLE:
			_tick_idle(delta)
		MonsterAIScript.State.PATROL:
			_tick_patrol(delta)
		MonsterAIScript.State.CHASE:
			_tick_chase(delta)
		MonsterAIScript.State.ALERT:
			_tick_alert(delta)

	var want_eyes := MonsterAIScript.chase_eyes_visible(_ai_state)
	if aggro_mode == AggroMode.RECALL or aggro_mode == AggroMode.BOUND:
		## Passive / leashed search: keep glow eyes off.
		if _ai_state != MonsterAIScript.State.CHASE:
			want_eyes = false
		if aggro_mode == AggroMode.RECALL:
			want_eyes = false
	if want_eyes != _eyes_chasing:
		_set_chase_eyes_active(want_eyes)

	_apply_knockback_bleed(delta)
	move_and_slide()


func _gather_interest() -> RefCounted:
	if aggro_mode == AggroMode.RECALL:
		## Live player can interrupt the trip home.
		var live: Array = []
		_append_sense_interest_candidates(live)
		var preferred_live := _prefer_interest(live)
		if preferred_live != null and bool(preferred_live.call("is_actionable")):
			var live_target: Node3D = preferred_live.get("target") as Node3D
			if live_target != null and live_target.is_in_group("player"):
				aggro_mode = AggroMode.BOUND
				return preferred_live
		if host != null and is_instance_valid(host) and host is Node3D:
			return MonsterInterestScript.from_position(
				(host as Node3D).global_position, FORCED_HUNT_URGENCY, RECALL_SOURCE
			)
		return null
	if forced_hunt_target != null and is_instance_valid(forced_hunt_target):
		return MonsterInterestScript.from_target(
			forced_hunt_target, FORCED_HUNT_URGENCY, FORCED_HUNT_SOURCE
		)
	if forced_hunt_target != null:
		forced_hunt_target = null
	if has_forced_hunt_goal:
		return MonsterInterestScript.from_position(
			forced_hunt_goal, FORCED_HUNT_URGENCY, FORCED_INVESTIGATE_SOURCE
		)
	var candidates: Array = []
	_append_default_interest_candidates(candidates)
	_append_sense_interest_candidates(candidates)
	return _prefer_interest(candidates)


func _append_default_interest_candidates(_out: Array) -> void:
	## Default: no wide proximity. Subclasses / senses own aggro.
	pass


func _append_sense_interest_candidates(out: Array) -> void:
	if _senses_root == null:
		_senses_root = get_node_or_null("Senses")
	if _senses_root == null:
		return
	for child in _senses_root.get_children():
		if MonsterSense.can_append_from(child):
			child.call("append_interest_candidates", self, out)


func _append_hearing_sense_candidates(out: Array) -> void:
	if _senses_root == null:
		_senses_root = get_node_or_null("Senses")
	if _senses_root == null:
		return
	for child in _senses_root.get_children():
		## Duck-type Hearing sense nodes (hear_range export).
		if MonsterSense.can_append_from(child) and "hear_range" in child:
			child.call("append_interest_candidates", self, out)


func _prefer_interest(candidates: Array) -> RefCounted:
	return MonsterAIScript.prefer_highest_urgency(candidates)


func _interest_is_actionable(interest: RefCounted) -> bool:
	if interest == null:
		return false
	if interest.has_method("is_actionable"):
		return bool(interest.call("is_actionable"))
	return false


func _update_alert_timers(delta: float, has_interest: bool) -> void:
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


func _enter_idle() -> void:
	_ai_state = MonsterAIScript.State.IDLE
	_idle_timer = 0.0
	_undetected_sec = 0.0
	_alert_timer = 0.0
	velocity.x = 0.0
	velocity.z = 0.0


func _enter_alert() -> void:
	_ai_state = MonsterAIScript.State.ALERT
	_undetected_sec = 0.0
	_alert_timer = 0.0
	velocity.x = 0.0
	velocity.z = 0.0


func _tick_idle(delta: float) -> void:
	if _should_enforce_leash() and _try_pull_to_leash():
		return
	_idle_timer += delta
	velocity.x = 0.0
	velocity.z = 0.0
	if _idle_timer >= idle_duration_sec:
		_begin_patrol()


func _begin_patrol() -> void:
	_ai_state = MonsterAIScript.State.PATROL
	_undetected_sec = 0.0
	_alert_timer = 0.0
	if _should_enforce_leash():
		_patrol_goal = _random_leash_edge_point()
		return
	_patrol_goal = MonsterAIScript.random_patrol_point(
		global_position,
		patrol_radius,
		_rng.randf() * TAU,
		_rng.randf_range(0.35, 1.0)
	)


func _tick_patrol(_delta: float) -> void:
	if _should_enforce_leash():
		if _try_pull_to_leash():
			return
		if not _point_inside_leash(_patrol_goal):
			_patrol_goal = _random_leash_edge_point()
		var flat := Vector3(
			_patrol_goal.x - global_position.x,
			0.0,
			_patrol_goal.z - global_position.z
		)
		if flat.length() <= PATROL_ARRIVE_DIST:
			_enter_idle()
			_soft_clamp_inside_leash()
			return
		var desired: Vector3 = MonsterAIScript.horizontal_velocity_toward(
			global_position, _patrol_goal, move_speed, velocity.y
		)
		velocity.x = desired.x
		velocity.z = desired.z
		_face_horizontal(desired)
		_soft_clamp_inside_leash()
		return
	var flat2 := Vector3(
		_patrol_goal.x - global_position.x,
		0.0,
		_patrol_goal.z - global_position.z
	)
	if flat2.length() <= PATROL_ARRIVE_DIST:
		_enter_idle()
		return
	var desired2: Vector3 = MonsterAIScript.horizontal_velocity_toward(
		global_position, _patrol_goal, move_speed, velocity.y
	)
	velocity.x = desired2.x
	velocity.z = desired2.z
	_face_horizontal(desired2)


func _tick_alert(_delta: float) -> void:
	if _should_enforce_leash() and _try_pull_to_leash():
		return
	velocity.x = 0.0
	velocity.z = 0.0
	_soft_clamp_inside_leash()


func _tick_chase(_delta: float) -> void:
	if aggro_mode == AggroMode.RECALL:
		_tick_recall(_delta)
		return
	## Chase and commanded free hunts may leave the leash radius.
	if not _interest_is_actionable(_interest):
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var goal: Vector3 = _interest.call("resolved_goal_position", global_position)
	var target: Node3D = _interest.get("target") as Node3D
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


func _tick_recall(_delta: float) -> void:
	_set_chase_eyes_active(false)
	if host == null or not is_instance_valid(host) or not (host is Node3D):
		finish_recall()
		return
	var host_pos := (host as Node3D).global_position
	var to_host := Vector3(
		host_pos.x - global_position.x,
		0.0,
		host_pos.z - global_position.z
	)
	if to_host.length() <= RECALL_ARRIVE_DIST:
		velocity.x = 0.0
		velocity.z = 0.0
		finish_recall()
		return
	var desired: Vector3 = MonsterAIScript.horizontal_velocity_toward(
		global_position, host_pos, move_speed, velocity.y
	)
	velocity.x = desired.x
	velocity.z = desired.z
	_face_horizontal(desired)


func _should_enforce_leash() -> bool:
	if not leash_enabled:
		return false
	if host == null or not is_instance_valid(host) or not (host is Node3D):
		return false
	if _ai_state == MonsterAIScript.State.CHASE:
		return false
	return true


func _host_position() -> Vector3:
	return (host as Node3D).global_position


func _point_inside_leash(world_pos: Vector3) -> bool:
	var host_pos := _host_position()
	var flat := Vector3(world_pos.x - host_pos.x, 0.0, world_pos.z - host_pos.z)
	return flat.length() <= leash_radius + 0.05


func _random_leash_edge_point() -> Vector3:
	var host_pos := _host_position()
	var angle := _rng.randf() * TAU
	var dist := leash_radius * _rng.randf_range(PATROL_EDGE_MIN, PATROL_EDGE_MAX)
	return Vector3(
		host_pos.x + cos(angle) * dist,
		global_position.y,
		host_pos.z + sin(angle) * dist
	)


func _try_pull_to_leash() -> bool:
	if not leash_enabled or host == null or not is_instance_valid(host):
		return false
	if not (host is Node3D):
		return false
	var host_pos := _host_position()
	var to_host := Vector3(
		host_pos.x - global_position.x,
		0.0,
		host_pos.z - global_position.z
	)
	var dist := to_host.length()
	if dist <= leash_radius:
		return false
	var desired: Vector3 = MonsterAIScript.horizontal_velocity_toward(
		global_position, host_pos, move_speed, velocity.y
	)
	velocity.x = desired.x
	velocity.z = desired.z
	_face_horizontal(desired)
	return true


func _soft_clamp_inside_leash() -> void:
	if not leash_enabled or host == null or not is_instance_valid(host):
		return
	if not (host is Node3D):
		return
	if _ai_state == MonsterAIScript.State.CHASE:
		return
	var host_pos := _host_position()
	var offset := Vector3(
		global_position.x - host_pos.x,
		0.0,
		global_position.z - host_pos.z
	)
	var dist := offset.length()
	if dist <= leash_radius:
		return
	var clamped := offset.normalized() * leash_radius
	global_position.x = host_pos.x + clamped.x
	global_position.z = host_pos.z + clamped.z
	var radial := clamped.normalized()
	var outward := velocity.x * radial.x + velocity.z * radial.z
	if outward > 0.0:
		velocity.x -= radial.x * outward
		velocity.z -= radial.z * outward


func _on_host_exiting() -> void:
	host = null
	if is_alive and not _dying:
		die()


func _cancel_cast() -> void:
	## Summons do not cast; stub for subclasses that previously called Monster API.
	pass


func _try_touch_damage(target: Node3D) -> void:
	if target == null or not target.has_method("take_damage"):
		return
	if touch_damage <= 0.0:
		return
	target.call("take_damage", touch_damage * get_physics_process_delta_time(), self)


func _face_horizontal(desired_vel: Vector3) -> void:
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


func _apply_hurt_knockback() -> void:
	velocity.y = maxf(velocity.y, HURT_UP_IMPULSE)
	_knockback_vel.y = maxf(_knockback_vel.y, HURT_UP_IMPULSE * 0.45)
	_knockback_timer = maxf(_knockback_timer, HURT_KNOCKBACK_TIMER_SEC)


func _health_ratio() -> float:
	if max_health <= 0.001:
		return 1.0
	return clampf(current_health / max_health, 0.0, 1.0)


func _apply_eye_glow_from_health() -> void:
	var t := 1.0 if Engine.is_editor_hint() else _health_ratio()
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
	_apply_eye_glow_from_health()


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


func _set_chase_eyes_active(active: bool) -> void:
	_eyes_chasing = active
	if _eyes_root == null:
		_cache_eyes()
	if _eyes_root != null:
		_eyes_root.visible = active


func _remember_hit_dir(from: Node3D) -> void:
	if from == null:
		return
	var away := global_position - from.global_position
	away.y = 0.0
	if away.length_squared() > 0.0001:
		_last_hit_dir = away.normalized()


func _spawn_ragdoll_corpse() -> void:
	var parent_node := get_parent()
	if parent_node == null or not is_inside_tree():
		return
	var corpse := RigidBody3D.new()
	corpse.name = "%sCorpse" % name
	corpse.set_script(MonsterCorpseScript)
	parent_node.add_child(corpse)
	corpse.global_transform = global_transform
	_reparent_to_corpse(_body_collision, corpse)
	_reparent_to_corpse(_body_mesh, corpse)
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
