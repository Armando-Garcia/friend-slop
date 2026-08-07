class_name TestEmberLobFlight
extends RefCounted

const EmberLobFlightScript := preload("res://scripts/monsters/abilities/ember_lob_flight.gd")


func run() -> int:
	var failures := 0
	failures += _test_initial_lob_has_upward()
	failures += _test_apex_cross_detection()
	failures += _test_dive_aims_at_point()
	return failures


func _test_initial_lob_has_upward() -> int:
	var from := Vector3.ZERO
	var toward := Vector3(5.0, 0.0, 0.0)
	var vel := EmberLobFlightScript.initial_lob_velocity(from, toward)
	if vel.y <= 0.0:
		push_error("Expected lob launch to include upward velocity")
		return 1
	if vel.x <= 0.0:
		push_error("Expected lob to aim toward target on X")
		return 1
	return 0


func _test_apex_cross_detection() -> int:
	if not EmberLobFlightScript.crossed_apex(1.0, -0.1):
		push_error("Expected + to - vertical velocity to count as apex")
		return 1
	if EmberLobFlightScript.crossed_apex(1.0, 0.5):
		push_error("Expected still-rising velocity not to count as apex")
		return 1
	if EmberLobFlightScript.crossed_apex(-0.2, -1.0):
		push_error("Expected already-falling velocity not to count as apex")
		return 1
	var vel := EmberLobFlightScript.initial_lob_velocity(Vector3.ZERO, Vector3(4.0, 0.0, 0.0))
	var prev_y := vel.y
	var found := false
	for _i in 120:
		vel = EmberLobFlightScript.step_lob_velocity(vel, 1.0 / 60.0)
		if EmberLobFlightScript.crossed_apex(prev_y, vel.y):
			found = true
			break
		prev_y = vel.y
	if not found:
		push_error("Expected stepped lob velocity to cross apex")
		return 1
	return 0


func _test_dive_aims_at_point() -> int:
	var from := Vector3(0.0, 4.0, 0.0)
	var dive_to := Vector3(3.0, 0.0, 1.0)
	var dive := EmberLobFlightScript.dive_velocity(from, dive_to)
	if not is_equal_approx(dive.length(), EmberLobFlightScript.DIVE_SPEED):
		push_error("Expected dive at DIVE_SPEED, got %s" % dive.length())
		return 1
	var expected_dir := (dive_to - from).normalized()
	if not dive.normalized().is_equal_approx(expected_dir):
		push_error("Expected dive direction toward snap point")
		return 1
	return 0
