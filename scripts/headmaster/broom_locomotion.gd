class_name BroomLocomotion
extends RefCounted

## Pure broom flight math — unit-testable without a scene tree.
## Planar momentum is stored in world XZ so camera turns do not redirect coasting.

const MAX_SPEED := 4.5 ## WALK_SPEED * 1.5
const BOOST_MULTIPLIER := 3.0 ## Shift while flying
const ACCEL := 5.0
const FRICTION := 8.0 ## Coast bleed when no move input
const CLIMB_SPEED := 4.0
const KNOCKBACK_HORIZONTAL := 9.0
const KNOCKBACK_UP := 3.5


static func max_speed_with_boost(boosting: bool, base_speed: float = MAX_SPEED) -> float:
	return base_speed * (BOOST_MULTIPLIER if boosting else 1.0)


static func flat_forward(forward: Vector3) -> Vector3:
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length_squared() < 0.0001:
		return Vector3.ZERO
	return flat.normalized()


static func flat_right(forward: Vector3) -> Vector3:
	var flat := flat_forward(forward)
	if flat.length_squared() < 0.0001:
		return Vector3.ZERO
	return Vector3(-flat.z, 0.0, flat.x)


static func wish_direction(forward: Vector3, throttle: float, strafe: float) -> Vector3:
	## Look-relative wish on the ground plane. Zero if no WASD.
	var wish := (
		flat_forward(forward) * clampf(throttle, -1.0, 1.0)
		+ flat_right(forward) * clampf(strafe, -1.0, 1.0)
	)
	if wish.length_squared() < 0.0001:
		return Vector3.ZERO
	return wish.normalized()


static func step_planar_velocity(
	current: Vector3,
	wish_dir: Vector3,
	delta: float,
	max_speed: float = MAX_SPEED,
	accel: float = ACCEL,
	friction: float = FRICTION
) -> Vector3:
	## World-space XZ momentum.
	## Friction only when there is no WASD wish — never while thrusting.
	## Max speed is an accel cap only; releasing sprint does not hard-brake.
	var vel := Vector3(current.x, 0.0, current.z)
	var limit := maxf(max_speed, 0.0)
	if wish_dir.length_squared() > 0.0001:
		var wish_n := wish_dir.normalized()
		var along := vel.dot(wish_n)
		var add_speed := limit - along
		if add_speed > 0.0:
			vel += wish_n * minf(accel * delta, add_speed)
	else:
		vel = vel.move_toward(Vector3.ZERO, friction * delta)
	return vel


static func vertical_velocity(
	ascend: bool,
	descend: bool,
	climb_speed: float = CLIMB_SPEED
) -> float:
	if ascend and not descend:
		return climb_speed
	if descend and not ascend:
		return -climb_speed
	return 0.0


static func knockback_impulse(fireball_dir: Vector3) -> Vector3:
	var dir := fireball_dir
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	else:
		dir = dir.normalized()
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	else:
		flat = flat.normalized()
	return flat * KNOCKBACK_HORIZONTAL + Vector3.UP * KNOCKBACK_UP
