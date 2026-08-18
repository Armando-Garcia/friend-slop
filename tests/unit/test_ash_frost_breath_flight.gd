extends RefCounted

const AshFrostBreathFlightScript := preload(
	"res://scripts/monsters/abilities/ash_frost_breath_flight.gd"
)


func run() -> int:
	var failures := 0
	failures += _test_radius_reaches_max()
	failures += _test_launch_offset_toward_target()
	failures += _test_combo_ward_delay()
	return failures


func _test_radius_reaches_max() -> int:
	var at_start := AshFrostBreathFlightScript.radius_at_age(0.0)
	if not is_zero_approx(at_start):
		push_error("Expected frost cloud radius 0 at age 0")
		return 1
	var at_end := AshFrostBreathFlightScript.radius_at_age(
		AshFrostBreathFlightScript.GROW_SEC
	)
	if not is_equal_approx(at_end, AshFrostBreathFlightScript.MAX_RADIUS):
		push_error("Expected frost cloud max radius at GROW_SEC, got %s" % at_end)
		return 1
	return 0


func _test_launch_offset_toward_target() -> int:
	var from := Vector3(0.0, 0.5, 0.0)
	var toward := Vector3(0.0, 0.5, 5.0)
	var pos := AshFrostBreathFlightScript.launch_position(from, toward)
	if pos.z <= from.z:
		push_error("Expected frost launch offset toward +Z target")
		return 1
	var dist := Vector2(pos.x - from.x, pos.z - from.z).length()
	if not is_equal_approx(dist, AshFrostBreathFlightScript.LAUNCH_OFFSET):
		push_error("Expected launch offset distance LAUNCH_OFFSET, got %s" % dist)
		return 1
	return 0


func _test_combo_ward_delay() -> int:
	if not is_equal_approx(AshFrostBreathFlightScript.COMBO_WARD_DELAY_SEC, 0.6):
		push_error("Expected COMBO_WARD_DELAY_SEC 0.6")
		return 1
	return 0
