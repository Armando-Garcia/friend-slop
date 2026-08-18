class_name AshFrostBreathFlight
extends RefCounted

## Frost breath projectile travel, growth, and hit tuning.

const MONSTER_BODY_RADIUS := 0.2
const MAX_RADIUS := MONSTER_BODY_RADIUS * 2.5 * 1.5
const GROW_SEC := 0.4
const LINGER_SEC := 0.15
const LAUNCH_OFFSET := 0.35
const LAUNCH_HEIGHT_OFFSET := 0.22
const TRAVEL_ARC_UP := 0.21
const TRAVEL_SPEED := 7.0
const MAX_TRAVEL_SEC := 2.5

const KNOCKBACK_SPEED := 9.0
const KNOCKBACK_LIFT := 2.4
const SLOW_DURATION_SEC := 2.2
const SLOW_MULTIPLIER := 0.5
const MANA_DRAIN := 40.0
const HIT_DAMAGE := 10.0

const COMBO_WARD_DELAY_SEC := 0.6


static func radius_at_age(
	age: float, grow_sec: float = GROW_SEC, max_radius: float = MAX_RADIUS
) -> float:
	var t := clampf(age / maxf(grow_sec, 0.01), 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - t, 2.0)
	return max_radius * eased


static func flat_direction(from: Vector3, toward: Vector3) -> Vector3:
	var flat := Vector3(toward.x - from.x, 0.0, toward.z - from.z)
	if flat.length_squared() < 0.0001:
		return Vector3.FORWARD
	return flat.normalized()


static func travel_direction(from: Vector3, toward: Vector3) -> Vector3:
	var flat := flat_direction(from, toward)
	return (flat + Vector3.UP * TRAVEL_ARC_UP).normalized()


static func launch_position(
	from: Vector3,
	toward: Vector3,
	offset: float = LAUNCH_OFFSET
) -> Vector3:
	var flat := flat_direction(from, toward)
	return from + flat * maxf(offset, 0.0) + Vector3.UP * LAUNCH_HEIGHT_OFFSET


static func total_life_sec(
	grow_sec: float = GROW_SEC, linger_sec: float = LINGER_SEC
) -> float:
	return maxf(grow_sec, 0.01) + maxf(linger_sec, 0.0)
