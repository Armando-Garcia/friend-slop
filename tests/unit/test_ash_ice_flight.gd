extends RefCounted

const AshIceFlightScript := preload("res://scripts/monsters/abilities/ash_ice_flight.gd")


func run() -> int:
	var failures := 0
	failures += _test_control_has_up_and_side()
	failures += _test_curve_ends_at_target()
	failures += _test_advance_reaches_one()
	return failures


func _test_control_has_up_and_side() -> int:
	var from := Vector3.ZERO
	var to := Vector3(0.0, 0.0, -10.0)
	var control := AshIceFlightScript.make_control(from, to, 1.0)
	if control.y <= from.y:
		push_error("Expected ice control point above the launch")
		return 1
	## Facing -Z, +side should push toward +X.
	if control.x <= 0.0:
		push_error("Expected +side_sign control to offset to +X, got %s" % control)
		return 1
	var other := AshIceFlightScript.make_control(from, to, -1.0)
	if other.x >= 0.0:
		push_error("Expected -side_sign control to offset to -X, got %s" % other)
		return 1
	return 0


func _test_curve_ends_at_target() -> int:
	var from := Vector3(1.0, 0.5, 1.0)
	var to := Vector3(8.0, 0.4, -4.0)
	var control := AshIceFlightScript.make_control(from, to, 1.0)
	var start := AshIceFlightScript.point_on_curve(from, control, to, 0.0)
	var end := AshIceFlightScript.point_on_curve(from, control, to, 1.0)
	if not start.is_equal_approx(from):
		push_error("Expected t=0 on ice curve at launch")
		return 1
	if not end.is_equal_approx(to):
		push_error("Expected t=1 on ice curve at target")
		return 1
	var mid := AshIceFlightScript.point_on_curve(from, control, to, 0.5)
	if mid.y <= maxf(from.y, to.y):
		push_error("Expected mid-curve point to rise above endpoints")
		return 1
	return 0


func _test_advance_reaches_one() -> int:
	var from := Vector3.ZERO
	var to := Vector3(6.0, 0.0, 0.0)
	var control := AshIceFlightScript.make_control(from, to, 1.0)
	var t := 0.0
	for _i in 240:
		t = AshIceFlightScript.advance_t(from, control, to, t, 1.0 / 60.0)
		if t >= 1.0:
			return 0
	push_error("Expected ice flight advance_t to reach 1.0")
	return 1
