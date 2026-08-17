class_name EmberHaloFlight
extends RefCounted

## Expanding ring radius vs distance traveled.

const TRAVEL_SPEED := 7.0
const START_RADIUS := 0.35
const MAX_RADIUS := 2.4
## Radius gain per meter traveled.
const EXPAND_PER_METER := 0.55
## Player hit: 60% move speed for 0.5s (via apply_speed_boost).
const SLOW_DURATION_SEC := 0.5
const SLOW_MULTIPLIER := 0.6
const HIT_KNOCKBACK_SPEED := 2.2


static func radius_at_distance(
	distance_traveled: float,
	start_radius: float = START_RADIUS,
	max_radius: float = MAX_RADIUS,
	expand_per_meter: float = EXPAND_PER_METER
) -> float:
	var grown := start_radius + maxf(distance_traveled, 0.0) * maxf(expand_per_meter, 0.0)
	return minf(grown, maxf(max_radius, start_radius))


static func flat_direction(from: Vector3, toward: Vector3) -> Vector3:
	var flat := Vector3(toward.x - from.x, 0.0, toward.z - from.z)
	if flat.length_squared() < 0.0001:
		return Vector3.FORWARD
	return flat.normalized()
