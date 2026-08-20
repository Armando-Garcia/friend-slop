extends RefCounted

const AshFrostBreathFlightScript := preload(
	"res://scripts/monsters/abilities/ash_frost_breath_flight.gd"
)


func run() -> int:
	var failures := 0
	failures += _test_radius_reaches_max()
	failures += _test_launch_offset_toward_target()
	failures += _test_travel_pitch_down()
	failures += _test_combo_ward_delay()
	failures += _test_no_hit_damage()
	failures += _test_range_mult()
	failures += _test_log_deceleration()
	failures += _test_knockback_impulse_up_and_away()
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


func _test_travel_pitch_down() -> int:
	var from := Vector3(0.0, 0.5, 0.0)
	var toward := Vector3(0.0, 0.5, 5.0)
	var dir := AshFrostBreathFlightScript.travel_direction(from, toward)
	var flat := AshFrostBreathFlightScript.flat_direction(from, toward)
	var arced := (flat + Vector3.UP * AshFrostBreathFlightScript.TRAVEL_ARC_UP).normalized()
	var expected := (
		asin(clampf(arced.y, -1.0, 1.0))
		- deg_to_rad(AshFrostBreathFlightScript.TRAVEL_PITCH_DOWN_DEG)
	)
	if not is_equal_approx(AshFrostBreathFlightScript.TRAVEL_PITCH_DOWN_DEG, 10.0):
		push_error("Expected TRAVEL_PITCH_DOWN_DEG 10")
		return 1
	if absf(asin(clampf(dir.y, -1.0, 1.0)) - expected) > 0.01:
		push_error("Expected frost travel pitch to match TRAVEL_PITCH_DOWN_DEG, got %s" % asin(dir.y))
		return 1
	if dir.z <= 0.0:
		push_error("Expected frost travel to keep aiming toward the target")
		return 1
	return 0


func _test_combo_ward_delay() -> int:
	if not is_equal_approx(AshFrostBreathFlightScript.COMBO_WARD_DELAY_SEC, 0.6):
		push_error("Expected COMBO_WARD_DELAY_SEC 0.6")
		return 1
	if not is_equal_approx(AshFrostBreathFlightScript.COMBO_AFTER_CLOUD_DELAY_SEC, 0.3):
		push_error("Expected COMBO_AFTER_CLOUD_DELAY_SEC 0.3")
		return 1
	return 0


func _test_no_hit_damage() -> int:
	if not is_zero_approx(AshFrostBreathFlightScript.HIT_DAMAGE):
		push_error("Expected frost cloud HIT_DAMAGE 0")
		return 1
	return 0


func _test_range_mult() -> int:
	var expected := (
		AshFrostBreathFlightScript.BASE_TRAVEL_RANGE * AshFrostBreathFlightScript.RANGE_MULT
		+ AshFrostBreathFlightScript.RANGE_EXTRA_M
	)
	if not is_equal_approx(AshFrostBreathFlightScript.MAX_TRAVEL_RANGE, expected):
		push_error("Expected frost MAX_TRAVEL_RANGE scaled range plus 2m, got %s" % expected)
		return 1
	if not is_equal_approx(AshFrostBreathFlightScript.RANGE_MULT, 2.125):
		push_error("Expected frost RANGE_MULT 2.125 (1.7x then +25%)")
		return 1
	return 0


func _test_log_deceleration() -> int:
	var v0 := AshFrostBreathFlightScript.travel_speed_at_distance(0.0)
	if not is_equal_approx(v0, AshFrostBreathFlightScript.LAUNCH_SPEED):
		push_error("Expected launch speed at distance 0, got %s" % v0)
		return 1
	var range_m := AshFrostBreathFlightScript.MAX_TRAVEL_RANGE
	var v_end := AshFrostBreathFlightScript.travel_speed_at_distance(range_m)
	if v_end > 0.05:
		push_error("Expected near-zero speed at max frost range, got %s" % v_end)
		return 1
	var v_mid := AshFrostBreathFlightScript.travel_speed_at_distance(range_m * 0.5)
	var linear_mid := v0 * 0.5
	if v_mid >= linear_mid:
		push_error("Expected log curve slower than linear at mid range, got %s" % v_mid)
		return 1
	var step := AshFrostBreathFlightScript.travel_step(0.0, 0.05)
	if step <= 0.0:
		push_error("Expected a positive first travel step")
		return 1
	if AshFrostBreathFlightScript.travel_step(range_m, 0.05) > 0.0:
		push_error("Expected no travel step at max range")
		return 1
	return 0


func _test_knockback_impulse_up_and_away() -> int:
	var impulse := AshFrostBreathFlightScript.knockback_impulse(Vector3(0.0, 0.0, 1.0))
	if impulse.z <= 0.0:
		push_error("Expected frost knockback away along +Z, got %s" % impulse)
		return 1
	if impulse.y < AshFrostBreathFlightScript.KNOCKBACK_LIFT - 0.01:
		push_error("Expected frost knockback to include upward lift, got %s" % impulse.y)
		return 1
	return 0
