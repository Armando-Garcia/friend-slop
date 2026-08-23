class_name TestEmberHaloFlight
extends RefCounted

const EmberHaloFlightScript := preload("res://scripts/monsters/abilities/ember_halo_flight.gd")


func run() -> int:
	var failures := 0
	failures += _test_radius_grows_then_clamps()
	failures += _test_flat_direction()
	failures += _test_slow_defaults()
	failures += _test_ring_and_center_zones()
	failures += _test_jump_pad_velocity()
	failures += _test_jump_pad_velocity_scales_with_strength()
	failures += _test_travel_and_knockback()
	return failures


func _test_radius_grows_then_clamps() -> int:
	var start := EmberHaloFlightScript.radius_at_distance(0.0)
	if not is_equal_approx(start, EmberHaloFlightScript.START_RADIUS):
		push_error("Expected start radius at distance 0")
		return 1
	var mid := EmberHaloFlightScript.radius_at_distance(1.0)
	var expected_mid := (
		EmberHaloFlightScript.START_RADIUS + EmberHaloFlightScript.EXPAND_PER_METER
	)
	if not is_equal_approx(mid, expected_mid):
		push_error("Expected linear radius growth, got %s vs %s" % [mid, expected_mid])
		return 1
	var far := EmberHaloFlightScript.radius_at_distance(100.0)
	if not is_equal_approx(far, EmberHaloFlightScript.MAX_RADIUS):
		push_error("Expected radius clamp at MAX_RADIUS, got %s" % far)
		return 1
	return 0


func _test_flat_direction() -> int:
	var dir := EmberHaloFlightScript.flat_direction(Vector3.ZERO, Vector3(2.0, 5.0, 0.0))
	if not is_zero_approx(dir.y):
		push_error("Expected flat direction to ignore height")
		return 1
	if not dir.is_equal_approx(Vector3.RIGHT):
		push_error("Expected flat direction along +X, got %s" % dir)
		return 1
	return 0


func _test_slow_defaults() -> int:
	if not is_equal_approx(EmberHaloFlightScript.SLOW_DURATION_SEC, 0.5):
		push_error("Expected halo slow duration 0.5s")
		return 1
	if not is_equal_approx(EmberHaloFlightScript.SLOW_MULTIPLIER, 0.6):
		push_error("Expected halo slow multiplier 0.6")
		return 1
	return 0


func _test_ring_and_center_zones() -> int:
	var outer := 2.0
	var inner := EmberHaloFlightScript.inner_radius(outer)
	if not EmberHaloFlightScript.is_in_center(inner * 0.5, outer):
		push_error("Expected center zone inside inner radius")
		return 1
	if EmberHaloFlightScript.is_in_ring(inner * 0.5, outer):
		push_error("Expected center zone to exclude ring hit")
		return 1
	var mid := (inner + outer) * 0.5
	if not EmberHaloFlightScript.is_in_ring(mid, outer):
		push_error("Expected ring zone between inner and outer radius")
		return 1
	if EmberHaloFlightScript.is_in_center(mid, outer):
		push_error("Expected ring zone to exclude center")
		return 1
	return 0


func _test_jump_pad_velocity() -> int:
	var gravity := 9.8
	var vel := EmberHaloFlightScript.jump_pad_velocity(gravity)
	var expected := sqrt(2.0 * gravity * EmberHaloFlightScript.JUMP_PAD_HEIGHT_M)
	if not is_equal_approx(vel, expected):
		push_error("Expected jump pad velocity for 2m apex, got %s vs %s" % [vel, expected])
		return 1
	return 0


func _test_jump_pad_velocity_scales_with_strength() -> int:
	var gravity := 9.8
	var baseline := EmberHaloFlightScript.jump_pad_velocity(gravity)
	var doubled := EmberHaloFlightScript.jump_pad_velocity(gravity, 2.0)
	var expected_doubled := sqrt(
		2.0 * gravity * EmberHaloFlightScript.JUMP_PAD_HEIGHT_M * 2.0
	)
	if not is_equal_approx(doubled, expected_doubled):
		push_error(
			"Expected 2x strength to double the apex height, got %s vs %s"
			% [doubled, expected_doubled]
		)
		return 1
	if doubled <= baseline:
		push_error("Expected a higher strength multiplier to launch faster than baseline")
		return 1
	var negative_clamped := EmberHaloFlightScript.jump_pad_velocity(gravity, -1.0)
	if not is_zero_approx(negative_clamped):
		push_error("Expected a negative strength multiplier to clamp to zero velocity")
		return 1
	return 0


func _test_travel_and_knockback() -> int:
	if not is_equal_approx(EmberHaloFlightScript.TRAVEL_SPEED, 14.0):
		push_error("Expected halo travel speed 14 m/s (2× prior)")
		return 1
	if not is_equal_approx(EmberHaloFlightScript.HIT_KNOCKBACK_SPEED, 3.8):
		push_error("Expected light-moderate halo knockback speed 3.8")
		return 1
	return 0
