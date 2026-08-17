class_name TestEmberHaloFlight
extends RefCounted

const EmberHaloFlightScript := preload("res://scripts/monsters/abilities/ember_halo_flight.gd")


func run() -> int:
	var failures := 0
	failures += _test_radius_grows_then_clamps()
	failures += _test_flat_direction()
	failures += _test_slow_defaults()
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
