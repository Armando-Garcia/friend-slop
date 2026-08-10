class_name SummonMonster
extends Monster

## Host-linked monster. Restricted by leash; dies when the host dies.
## While leashed (not chasing / not commanded free), patrols the outer ring and
## never crosses the leash edge.

const FORCED_HUNT_SOURCE := &"forced_hunt"
const FORCED_INVESTIGATE_SOURCE := &"forced_investigate"
const FORCED_HUNT_URGENCY := 2.0
## High enough that a rat that sees the player pulls the host into chase.
const RELAY_SIGHT_URGENCY := 2.25
## Prefer the outer band of the leash disk for idle patrol goals.
const PATROL_EDGE_MIN := 0.72
const PATROL_EDGE_MAX := 0.96

@export var leash_radius: float = 10.0
@export var leash_enabled: bool = true

var host: Node = null
var forced_hunt_target: Node3D = null
var forced_hunt_goal: Vector3 = Vector3.ZERO
var has_forced_hunt_goal: bool = false


func bind_to_host(p_host: Node, p_leash_radius: float = 10.0) -> void:
	host = p_host
	leash_radius = maxf(p_leash_radius, 0.5)
	leash_enabled = true
	chase_style = ChaseStyle.CLOSE_IN
	## Keep default patrol small; leash ring owns wander while bound.
	patrol_radius = mini(patrol_radius, leash_radius * 0.35)
	if host != null and not host.tree_exiting.is_connected(_on_host_exiting):
		host.tree_exiting.connect(_on_host_exiting)


func set_forced_hunt(target: Node3D, free_leash: bool = true) -> void:
	forced_hunt_target = target
	has_forced_hunt_goal = false
	if free_leash:
		leash_enabled = false


func set_forced_investigate(world_position: Vector3, free_leash: bool = true) -> void:
	forced_hunt_target = null
	forced_hunt_goal = world_position
	has_forced_hunt_goal = true
	if free_leash:
		leash_enabled = false


func clear_forced_hunt() -> void:
	forced_hunt_target = null
	has_forced_hunt_goal = false
	leash_enabled = true


func get_relayed_player_interest() -> RefCounted:
	if _interest == null:
		return null
	var target: Node3D = _interest.get("target") as Node3D
	if target == null or not is_instance_valid(target):
		return null
	if not target.is_in_group("player"):
		return null
	return MonsterInterestScript.from_target(
		target, RELAY_SIGHT_URGENCY, &"summon_sight"
	)


func _gather_interest() -> RefCounted:
	## Forced hunt ignores hearing/LOS and distance — chase the assigned target.
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
	return super._gather_interest()


func _begin_patrol() -> void:
	_ai_state = MonsterAIScript.State.PATROL
	if _should_enforce_leash():
		_patrol_goal = _random_leash_edge_point()
		return
	super._begin_patrol()


func _tick_idle(delta: float) -> void:
	if _should_enforce_leash() and _try_pull_to_leash():
		return
	super._tick_idle(delta)


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
	super._tick_patrol(_delta)


func _tick_chase(_delta: float) -> void:
	## Chase mode and commanded free hunts may leave the leash radius.
	super._tick_chase(_delta)


func _should_enforce_leash() -> bool:
	## Bound radius applies while leashed and not actively chasing.
	## Commanded hunts set leash_enabled=false so they stay free.
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
	## Kill outward velocity so they don't keep pushing the edge.
	var radial := clamped.normalized()
	var outward := velocity.x * radial.x + velocity.z * radial.z
	if outward > 0.0:
		velocity.x -= radial.x * outward
		velocity.z -= radial.z * outward


func _on_host_exiting() -> void:
	host = null
	if is_alive and not _dying:
		die()
