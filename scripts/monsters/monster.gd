@tool
class_name Monster
extends Character

## Combat-ready AI character. Extends Character (not PlayableCharacter):
## no camera, wand, "player" group, or multiplayer authority.
##
## AI: senses append interest candidates → _prefer_interest → IDLE/PATROL/CHASE/ALERT.
## Override _prefer_interest / _append_default_interest_candidates on children;
## add MonsterSense nodes under Senses to customize perception without forking the FSM.
## Eyes (Head/Eyes) glow while chasing or alert — color from body_tint / eye_glow exports.
## Glow darkens and dims with missing health so hits read without an HP bar.
## Lookdev: set lookdev_override + lookdev_pose to preview chase/patrol in the editor.

enum ChaseStyle { CLOSE_IN, KEEP_AWAY }

const BroomLocomotionScript := preload("res://scripts/headmaster/broom_locomotion.gd")
const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")
const MonsterInterestScript := preload("res://scripts/monsters/monster_interest.gd")
const MonsterCorpseScript := preload("res://scripts/monsters/monster_corpse.gd")
const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")

const DEFAULT_TINT := Color(0.72, 0.28, 0.22, 1.0)
const DEFAULT_EYE_GLOW := Color(0.2, 0.55, 1.0, 1.0)
const PATROL_ARRIVE_DIST := 0.45
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
		body_tint = value
		if is_inside_tree():
			_refresh_appearance()

@export var eye_glow_color: Color = DEFAULT_EYE_GLOW:
	set(value):
		eye_glow_color = value
		if is_inside_tree():
			_refresh_appearance()

@export_group("Lookdev")
## When true, lookdev_pose drives eyes instead of live AI (workspace / editor preview).
@export var lookdev_override: bool = false:
	set(value):
		lookdev_override = value
		if is_inside_tree():
			_refresh_lookdev_eyes()

@export var lookdev_pose: MonsterAIScript.LookdevPose = MonsterAIScript.LookdevPose.PATROL:
	set(value):
		lookdev_pose = value
		if is_inside_tree():
			_refresh_lookdev_eyes()

@export var show_combat_ranges: bool = false:
	set(value):
		show_combat_ranges = value
		if is_inside_tree():
			_refresh_range_gizmos()

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
@export var patrol_radius: float = 4.0
## After chase loses all sight/hearing interest for this long → ALERT.
@export_range(0.5, 30.0, 0.25) var lost_chase_to_alert_sec: float = 4.0
## How long ALERT lasts with no detection before returning to PATROL.
@export_range(1.0, 60.0, 0.25) var alert_duration_sec: float = 12.0
@export var death_linger_sec: float = 30.0
@export var death_fade_sec: float = 3.0
## CLOSE_IN rushes melee. KEEP_AWAY holds at keep_away_range.
@export var chase_style: ChaseStyle = ChaseStyle.CLOSE_IN
@export_range(1.0, 40.0, 0.5) var keep_away_range: float = 20.0

var current_health: float = 60.0
var is_alive: bool = true

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
var _chase_range_mesh: MeshInstance3D = null
var _attack_range_mesh: MeshInstance3D = null
var _cast_windup_left: float = 0.0
var _casting_ability: Node = null
var _cast_prefer_index: int = 0


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group("monster")
		add_to_group("combat_target")
	current_health = max_health
	is_alive = true
	_rng.randomize()
	_senses_root = get_node_or_null("Senses")
	_cache_eyes()
	_refresh_appearance()
	if lookdev_override or Engine.is_editor_hint():
		_refresh_lookdev_eyes()
	else:
		_set_chase_eyes_active(false)
	_refresh_range_gizmos()
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	_enter_idle()
	set_physics_process(true)


func apply_summon_appearance(tint: Color, p_eye_glow_color: Color = DEFAULT_EYE_GLOW) -> void:
	## Used by the headmaster summon book after instantiate.
	body_tint = tint
	eye_glow_color = p_eye_glow_color
	_refresh_appearance()


func set_lookdev_pose(pose: MonsterAIScript.LookdevPose, enable_override: bool = true) -> void:
	lookdev_override = enable_override
	lookdev_pose = pose


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
	## Small hop so hits read even without an HP bar.
	velocity.y = maxf(velocity.y, HURT_UP_IMPULSE)
	_knockback_vel.y = maxf(_knockback_vel.y, HURT_UP_IMPULSE * 0.45)
	_knockback_timer = maxf(_knockback_timer, HURT_KNOCKBACK_TIMER_SEC)


func _health_ratio() -> float:
	if max_health <= 0.001:
		return 1.0
	return clampf(current_health / max_health, 0.0, 1.0)


func _apply_eye_glow_from_health() -> void:
	## Full HP = authored glow; near death = darker / dimmer (Wretch green dims hard).
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
	if mesh_inst == null:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = color
	mat.roughness = 0.62
	mat.metallic = 0.05
	mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	mesh_inst.material_override = mat
	mesh_inst.layers = WorldVisualLayersScript.PLAYER_SELF
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


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
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = EYE_EMISSION_ENERGY * energy_scale
	for mesh in _eye_meshes:
		if mesh == null:
			continue
		mesh.material_override = mat
		mesh.layers = PLAYER_SELF_VISUAL_LAYER
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _eye_light != null:
		_eye_light.light_color = color
		_eye_light.light_energy = EYE_LIGHT_ENERGY * energy_scale
		_eye_light.light_cull_mask = WorldVisualLayersScript.SCENE_LIGHT_MASK


func _refresh_lookdev_eyes() -> void:
	if not lookdev_override and not Engine.is_editor_hint():
		return
	var want := MonsterAIScript.lookdev_eyes_visible(lookdev_pose)
	_set_chase_eyes_active(want)


func _set_chase_eyes_active(active: bool) -> void:
	_eyes_chasing = active
	if _eyes_root == null:
		_cache_eyes()
	if _eyes_root != null:
		_eyes_root.visible = active


func _refresh_range_gizmos() -> void:
	if not show_combat_ranges:
		_free_range_gizmo(_chase_range_mesh)
		_chase_range_mesh = null
		_free_range_gizmo(_attack_range_mesh)
		_attack_range_mesh = null
		return
	_chase_range_mesh = _ensure_range_disc(
		_chase_range_mesh, "ChaseRangeGizmo", chase_range, Color(1.0, 0.35, 0.2, 0.22)
	)
	_attack_range_mesh = _ensure_range_disc(
		_attack_range_mesh, "AttackRangeGizmo", attack_range, Color(1.0, 0.85, 0.2, 0.28)
	)


func _ensure_range_disc(
	existing: MeshInstance3D, node_name: String, radius: float, color: Color
) -> MeshInstance3D:
	var mesh_inst := existing
	if mesh_inst == null or not is_instance_valid(mesh_inst):
		mesh_inst = MeshInstance3D.new()
		mesh_inst.name = node_name
		add_child(mesh_inst)
		if Engine.is_editor_hint() and get_tree() != null:
			var edited := get_tree().edited_scene_root
			if edited != null:
				mesh_inst.owner = edited
	var cyl := CylinderMesh.new()
	cyl.top_radius = maxf(0.05, radius)
	cyl.bottom_radius = cyl.top_radius
	cyl.height = RANGE_DISC_HEIGHT
	cyl.radial_segments = 48
	mesh_inst.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_inst.position = Vector3(0.0, RANGE_DISC_HEIGHT * 0.5, 0.0)
	return mesh_inst


func _free_range_gizmo(mesh_inst: MeshInstance3D) -> void:
	if mesh_inst != null and is_instance_valid(mesh_inst):
		mesh_inst.queue_free()


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

	_reparent_to_corpse(_body_collision, corpse)
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
		if child.has_method("append_interest_candidates"):
			child.call("append_interest_candidates", self, out)


## Default preferencing: highest urgency. Children override to weight sources.
func _prefer_interest(candidates: Array) -> RefCounted:
	return MonsterAIScript.prefer_highest_urgency(candidates)


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

	var chase_target: Node3D = null
	if _interest != null:
		chase_target = _interest.get("target") as Node3D

	if _casting_ability != null:
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
	move_and_slide()


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
	velocity.x = 0.0
	velocity.z = 0.0


func _enter_alert() -> void:
	_cancel_cast()
	_ai_state = MonsterAIScript.State.ALERT
	_undetected_sec = 0.0
	_alert_timer = 0.0
	velocity.x = 0.0
	velocity.z = 0.0


func _tick_idle(delta: float) -> void:
	_idle_timer += delta
	velocity.x = 0.0
	velocity.z = 0.0
	if _idle_timer >= idle_duration_sec:
		_begin_patrol()


func _begin_patrol() -> void:
	_ai_state = MonsterAIScript.State.PATROL
	_undetected_sec = 0.0
	_alert_timer = 0.0
	_patrol_goal = MonsterAIScript.random_patrol_point(
		global_position,
		patrol_radius,
		_rng.randf() * TAU,
		_rng.randf_range(0.35, 1.0)
	)


func _tick_patrol(_delta: float) -> void:
	var flat := Vector3(
		_patrol_goal.x - global_position.x,
		0.0,
		_patrol_goal.z - global_position.z
	)
	if flat.length() <= PATROL_ARRIVE_DIST:
		_enter_idle()
		return
	var desired: Vector3 = MonsterAIScript.horizontal_velocity_toward(
		global_position, _patrol_goal, move_speed, velocity.y
	)
	velocity.x = desired.x
	velocity.z = desired.z
	_face_horizontal(desired)


func _tick_alert(_delta: float) -> void:
	## Vigilant standstill while waiting to re-detect or drop to patrol.
	velocity.x = 0.0
	velocity.z = 0.0


func _tick_chase(_delta: float) -> void:
	if not _interest_is_actionable(_interest):
		## Grace window before ALERT: hold position, keep eyes on.
		_cancel_cast()
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var goal: Vector3 = _interest.call("resolved_goal_position", global_position)
	var target: Node3D = _interest.get("target") as Node3D

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


func _has_ranged_spacing_abilities() -> bool:
	for ability in get_combat_abilities():
		if "requires_target" in ability and not bool(ability.get("requires_target")):
			continue
		if "min_cast_range" in ability and float(ability.get("min_cast_range")) > 0.5:
			return true
	return false


func _move_keep_away(target: Node3D) -> void:
	var to_target := Vector3(
		target.global_position.x - global_position.x,
		0.0,
		target.global_position.z - global_position.z
	)
	var dist := to_target.length()
	var arrive_eps := 0.5
	_face_horizontal(to_target)
	if dist < 0.05:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var radial := to_target.normalized()
	if dist < keep_away_range - arrive_eps:
		var retreat_goal := target.global_position - radial * keep_away_range
		var desired_away: Vector3 = MonsterAIScript.horizontal_velocity_toward(
			global_position, retreat_goal, move_speed, velocity.y
		)
		velocity.x = desired_away.x
		velocity.z = desired_away.z
		return
	if dist > keep_away_range + arrive_eps:
		var approach_goal := target.global_position - radial * keep_away_range
		var desired_in: Vector3 = MonsterAIScript.horizontal_velocity_toward(
			global_position, approach_goal, move_speed, velocity.y
		)
		velocity.x = desired_in.x
		velocity.z = desired_in.z
		return
	velocity.x = 0.0
	velocity.z = 0.0


func _try_start_cast(target: Node3D) -> bool:
	var ready := _pick_ready_ability(target)
	if ready == null:
		return false
	_begin_ability_windup(ready)
	_tick_cast_windup(0.0, target)
	return true


## Keep cast spacing and fire when in band. Returns true when chase is handled.
func _tick_ranged_cast_chase(target: Node3D) -> bool:
	var ready := _pick_ready_ability(target)
	if ready != null:
		_begin_ability_windup(ready)
		_tick_cast_windup(0.0, target)
		return true

	var awaiting := _first_ranged_castable_ability()
	if awaiting != null:
		_move_toward_cast_range(target, awaiting)
		return true

	var spacer := _preferred_spacing_ability()
	if spacer != null:
		_move_toward_cast_range(target, spacer)
		return true
	return false


func _first_ranged_castable_ability() -> Node:
	var abilities := get_combat_abilities()
	for ability in abilities:
		if "requires_target" in ability and not bool(ability.get("requires_target")):
			continue
		if not bool(ability.call("can_cast")):
			continue
		return ability
	return null


func _first_castable_ability() -> Node:
	var abilities := get_combat_abilities()
	for ability in abilities:
		if bool(ability.call("can_cast")):
			return ability
	return null


func _preferred_spacing_ability() -> Node:
	var abilities := get_combat_abilities()
	for ability in abilities:
		if "requires_target" in ability and not bool(ability.get("requires_target")):
			continue
		return ability
	if abilities.is_empty():
		return null
	return abilities[0]


func _move_toward_cast_range(target: Node3D, ability: Node) -> void:
	var min_r := float(ability.get("min_cast_range")) if "min_cast_range" in ability else 3.0
	var max_r := float(ability.get("max_cast_range")) if "max_cast_range" in ability else 12.0
	var ideal := (min_r + max_r) * 0.5
	if ability.has_method("preferred_cast_range"):
		ideal = float(ability.call("preferred_cast_range"))
	var to_target := Vector3(
		target.global_position.x - global_position.x,
		0.0,
		target.global_position.z - global_position.z
	)
	var dist := to_target.length()
	var arrive_eps := 0.45
	_face_horizontal(to_target)

	## Too close: back off along the line away from the player.
	if dist < min_r or dist < ideal - arrive_eps:
		if dist < 0.05:
			velocity.x = 0.0
			velocity.z = 0.0
			return
		var radial := to_target.normalized()
		var retreat_goal := target.global_position - radial * ideal
		var desired_away: Vector3 = MonsterAIScript.horizontal_velocity_toward(
			global_position, retreat_goal, move_speed, velocity.y
		)
		velocity.x = desired_away.x
		velocity.z = desired_away.z
		return

	## Too far: close in toward preferred band (stop short of max).
	if dist > max_r or dist > ideal + arrive_eps:
		var radial_in := to_target.normalized()
		var approach_goal := target.global_position - radial_in * ideal
		var desired_in: Vector3 = MonsterAIScript.horizontal_velocity_toward(
			global_position, approach_goal, move_speed, velocity.y
		)
		velocity.x = desired_in.x
		velocity.z = desired_in.z
		return

	velocity.x = 0.0
	velocity.z = 0.0


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


func _cancel_cast() -> void:
	if _casting_ability != null and is_instance_valid(_casting_ability):
		if _casting_ability.has_method("stop_windup_fx"):
			_casting_ability.call("stop_windup_fx")
	_casting_ability = null
	_cast_windup_left = 0.0


func _try_touch_damage(target: Node3D) -> void:
	if target == null or not target.has_method("take_damage"):
		return
	target.call("take_damage", touch_damage * get_physics_process_delta_time(), self)


func _face_horizontal(desired_vel: Vector3) -> void:
	var flat := Vector3(desired_vel.x, 0.0, desired_vel.z)
	if flat.length_squared() < 0.0001:
		return
	look_at(global_position + flat.normalized(), Vector3.UP)


func _apply_knockback_bleed(delta: float) -> void:
	if _knockback_timer <= 0.0:
		return
	_knockback_timer -= delta
	velocity.x += _knockback_vel.x * 0.35
	velocity.z += _knockback_vel.z * 0.35
	_knockback_vel = _knockback_vel.move_toward(Vector3.ZERO, 28.0 * delta)
