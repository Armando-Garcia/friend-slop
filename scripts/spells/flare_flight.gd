class_name FlareFlight
extends RefCounted

## Pure flare rocket rules — unit-testable without a scene tree.

const LAUNCH_SPEED := 38.0
## Light drag so the rocket coasts far before gravity owns the arc.
const DRAG := 0.35
## Soft gravity while coasting.
const GRAVITY := 2.0
const DEFAULT_LIFE_SEC := 15.0
const HIT_RADIUS := 0.22


static func launch_direction(aim: Vector3) -> Vector3:
	## Follow the crosshair / cast aim exactly — no forced skyward bias.
	if aim.length_squared() < 0.0001:
		return Vector3.FORWARD
	return aim.normalized()


static func initial_velocity(aim: Vector3, launch_speed: float = LAUNCH_SPEED) -> Vector3:
	return launch_direction(aim) * maxf(launch_speed, 0.0)


static func step_velocity(
	velocity: Vector3,
	delta: float,
	drag: float = DRAG,
	gravity: float = GRAVITY
) -> Vector3:
	## Exponential drag, then gravity.
	var dt := maxf(delta, 0.0)
	var next := velocity * exp(-maxf(drag, 0.0) * dt)
	next.y -= maxf(gravity, 0.0) * dt
	return next


static func simulate_altitude(
	origin_y: float,
	aim: Vector3,
	elapsed_sec: float,
	step_sec: float = 1.0 / 60.0,
	launch_speed: float = LAUNCH_SPEED,
	drag: float = DRAG,
	gravity: float = GRAVITY
) -> float:
	## Integrate flight for hang-time checks (no collision).
	var y := origin_y
	var velocity := initial_velocity(aim, launch_speed)
	var t := 0.0
	var life := maxf(elapsed_sec, 0.0)
	var dt_step := maxf(step_sec, 0.0001)
	while t < life:
		var dt := minf(dt_step, life - t)
		velocity = step_velocity(velocity, dt, drag, gravity)
		y += velocity.y * dt
		t += dt
	return y
