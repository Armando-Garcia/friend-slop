class_name MonsterAI
extends RefCounted

## Pure helpers for Monster FSM / targeting / interest preferencing.

enum State { IDLE, PATROL, CHASE, ALERT }
## Lookdev pose → eyes. Chase shows eyes; Patrol hides them.
enum LookdevPose { PATROL, CHASE }


static func apply_damage(current_health: float, amount: float) -> float:
	return maxf(0.0, current_health - maxf(0.0, amount))


static func apply_heal(current_health: float, amount: float, max_health: float) -> float:
	return clampf(current_health + maxf(0.0, amount), 0.0, max_health)


static func is_dead(health: float) -> bool:
	return health <= 0.0


## Returns index of nearest living target within chase_range, or -1.
static func pick_nearest_target_index(
	origin: Vector3,
	target_positions: Array,
	target_alive: Array,
	chase_range: float
) -> int:
	var best_i := -1
	var best_d2 := chase_range * chase_range
	var n := mini(target_positions.size(), target_alive.size())
	for i in range(n):
		if not bool(target_alive[i]):
			continue
		var pos: Vector3 = target_positions[i]
		var d2 := Vector3(pos.x - origin.x, 0.0, pos.z - origin.z).length_squared()
		if d2 <= best_d2:
			best_d2 = d2
			best_i = i
	return best_i


## Distance-based urgency in (0, 1], nearer = higher. 0 if out of range.
static func proximity_urgency(origin: Vector3, target: Vector3, range_m: float) -> float:
	if range_m <= 0.0:
		return 0.0
	var flat := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	var dist := flat.length()
	if dist > range_m:
		return 0.0
	return 1.0 - (dist / range_m) * 0.5


## Default preferencing: highest urgency among actionable candidates.
static func prefer_highest_urgency(candidates: Array) -> RefCounted:
	var best: RefCounted = null
	var best_u := 0.0
	for item in candidates:
		if item == null or not item.has_method("is_actionable"):
			continue
		if not bool(item.call("is_actionable")):
			continue
		var urgency := float(item.get("urgency"))
		if best == null or urgency > best_u:
			best = item
			best_u = urgency
	return best


## Interest always forces CHASE. Without interest, CHASE/ALERT persist so the
## monster can time CHASE→ALERT (lost target) and ALERT→PATROL. IDLE→PATROL is
## owned by the monster idle tick.
static func resolve_state(current: State, has_chase_target: bool) -> State:
	if has_chase_target:
		return State.CHASE
	return current


## Eyes stay on while chasing or alert (lost-player vigilance).
static func chase_eyes_visible(state: State) -> bool:
	return state == State.CHASE or state == State.ALERT


static func lookdev_eyes_visible(pose: LookdevPose) -> bool:
	return pose == LookdevPose.CHASE


static func random_patrol_point(
	origin: Vector3, radius: float, angle_rad: float, dist_factor: float
) -> Vector3:
	var dist := clampf(dist_factor, 0.0, 1.0) * maxf(0.0, radius)
	return Vector3(
		origin.x + cos(angle_rad) * dist,
		origin.y,
		origin.z + sin(angle_rad) * dist
	)


static func horizontal_velocity_toward(
	from: Vector3, to: Vector3, speed: float, y_velocity: float = 0.0
) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if flat.length_squared() < 0.0001:
		return Vector3(0.0, y_velocity, 0.0)
	var dir := flat.normalized()
	return Vector3(dir.x * speed, y_velocity, dir.z * speed)
