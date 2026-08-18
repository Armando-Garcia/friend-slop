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


## Rotate current yaw toward a flat desired facing vector at speed_rad.
static func rotate_yaw_toward(
	current_yaw: float, desired_flat: Vector3, speed_rad: float, delta: float
) -> float:
	var flat := Vector3(desired_flat.x, 0.0, desired_flat.z)
	if flat.length_squared() < 0.0001:
		return current_yaw
	var target_yaw := Basis.looking_at(flat.normalized(), Vector3.UP).get_euler().y
	return rotate_toward(current_yaw, target_yaw, maxf(speed_rad, 0.01) * delta)


## Max distance from the player for chase reposition (80% of aggro / chase_range).
static func max_aggro_move_distance(chase_range: float) -> float:
	return maxf(0.0, chase_range) * 0.8


static func pick_chase_wait_sec(
	rng: RandomNumberGenerator, min_sec: float = 1.0, max_sec: float = 3.0
) -> float:
	return rng.randf_range(minf(min_sec, max_sec), maxf(min_sec, max_sec))


static func pick_chase_strafe_sec(
	rng: RandomNumberGenerator, min_sec: float = 1.2, max_sec: float = 2.0
) -> float:
	return rng.randf_range(minf(min_sec, max_sec), maxf(min_sec, max_sec))


static func pick_chase_retreat_sec(
	rng: RandomNumberGenerator, min_sec: float = 1.2, max_sec: float = 3.2
) -> float:
	return rng.randf_range(minf(min_sec, max_sec), maxf(min_sec, max_sec))


static func pick_wretch_post_cast_move_sec(
	rng: RandomNumberGenerator, min_sec: float = 0.5, max_sec: float = 1.5
) -> float:
	return rng.randf_range(minf(min_sec, max_sec), maxf(min_sec, max_sec))


static func horizontal_distance(from: Vector3, to: Vector3) -> float:
	return Vector3(to.x - from.x, 0.0, to.z - from.z).length()


## Flat unit vector from monster toward player. Zero if coincident.
static func toward_player_flat(from: Vector3, player: Vector3) -> Vector3:
	var flat := Vector3(player.x - from.x, 0.0, player.z - from.z)
	if flat.length_squared() < 0.0001:
		return Vector3.ZERO
	return flat.normalized()


## Angled strafe: mostly sideways with a small radial blend (positive = toward player).
static func angled_strafe_dir(
	from: Vector3,
	player: Vector3,
	side_sign: float,
	radial_blend: float = 0.28
) -> Vector3:
	var toward := toward_player_flat(from, player)
	if toward.length_squared() < 0.0001:
		return Vector3.ZERO
	var side := Vector3(-toward.z, 0.0, toward.x) * signf(side_sign)
	if side.length_squared() < 0.0001:
		return toward
	var blend := clampf(radial_blend, 0.0, 0.85)
	var dir := (side * (1.0 - blend) + toward * blend).normalized()
	return dir


## Angled retreat: mostly away from player with a lateral bias.
static func angled_retreat_dir(
	from: Vector3,
	player: Vector3,
	side_sign: float,
	lateral_blend: float = 0.38
) -> Vector3:
	var toward := toward_player_flat(from, player)
	if toward.length_squared() < 0.0001:
		return Vector3.ZERO
	var away := -toward
	var side := Vector3(-toward.z, 0.0, toward.x) * signf(side_sign)
	var blend := clampf(lateral_blend, 0.0, 0.85)
	var dir := (away * (1.0 - blend) + side * blend).normalized()
	return dir


static func can_retreat_farther(from: Vector3, player: Vector3, max_dist: float) -> bool:
	return horizontal_distance(from, player) < max_dist - 0.05


## Zero horizontal retreat when already at/over the aggro move cap.
static func retreat_velocity_clamped(
	from: Vector3,
	player: Vector3,
	move_dir: Vector3,
	speed: float,
	y_velocity: float,
	max_dist: float
) -> Vector3:
	if not can_retreat_farther(from, player, max_dist):
		return Vector3(0.0, y_velocity, 0.0)
	var flat_dir := Vector3(move_dir.x, 0.0, move_dir.z)
	if flat_dir.length_squared() < 0.0001:
		return Vector3(0.0, y_velocity, 0.0)
	flat_dir = flat_dir.normalized()
	var step := maxf(speed, 0.0) * 0.05
	var next := from + flat_dir * step
	if horizontal_distance(next, player) > max_dist:
		return Vector3(0.0, y_velocity, 0.0)
	return Vector3(flat_dir.x * speed, y_velocity, flat_dir.z * speed)


## Flat unit vector of where the player is looking (XZ only).
static func player_facing_flat(player: Node3D) -> Vector3:
	if player == null:
		return Vector3(0.0, 0.0, -1.0)
	var head := player.get_node_or_null("Head") as Node3D
	var basis: Basis = head.global_transform.basis if head != null else player.global_transform.basis
	var forward := Vector3(-basis.z.x, 0.0, -basis.z.z)
	if forward.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, -1.0)
	return forward.normalized()


## Landing spot behind the player's view at preferred range, biased to the monster's side.
static func pick_dash_landing_behind(
	monster_pos: Vector3,
	player: Node3D,
	preferred_range: float,
	max_dist_from_player: float
) -> Vector3:
	if player == null:
		return monster_pos
	var player_pos := player.global_position
	var forward := player_facing_flat(player)
	var behind := -forward
	var lateral := Vector3(-forward.z, 0.0, forward.x)
	var to_monster := Vector3(
		monster_pos.x - player_pos.x, 0.0, monster_pos.z - player_pos.z
	)
	var side_sign := signf(lateral.dot(to_monster))
	if absf(side_sign) < 0.01:
		side_sign = 1.0
	var dist := clampf(preferred_range * 0.95, 1.0, max_dist_from_player)
	var landing := player_pos + behind * dist + lateral * side_sign * 0.5
	landing.y = monster_pos.y
	var to_landing := Vector3(landing.x - player_pos.x, 0.0, landing.z - player_pos.z)
	if to_landing.dot(forward) > 0.0:
		landing = player_pos + behind * dist + lateral * side_sign * 0.5
		to_landing = Vector3(landing.x - player_pos.x, 0.0, landing.z - player_pos.z)
	if to_landing.length_squared() > 0.0001 and to_landing.length() > max_dist_from_player:
		landing = player_pos + to_landing.normalized() * max_dist_from_player
		landing.y = monster_pos.y
	return landing
