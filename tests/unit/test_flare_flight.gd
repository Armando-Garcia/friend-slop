class_name TestFlareFlight
extends RefCounted

const FlareFlightScript := preload("res://scripts/spells/flare_flight.gd")


func run() -> int:
	var failures := 0
	failures += _test_launch_follows_aim()
	failures += _test_decelerates_over_time()
	failures += _test_gravity_pulls_down()
	failures += _test_upward_shot_stays_aloft()
	failures += _test_default_life_is_fifteen()
	return failures


func _test_launch_follows_aim() -> int:
	var aim := Vector3(1.0, 0.05, 0.2).normalized()
	var launched := FlareFlightScript.launch_direction(aim)
	if not launched.is_equal_approx(aim):
		push_error("Expected flare to follow crosshair aim, got %s" % launched)
		return 1
	var up := FlareFlightScript.launch_direction(Vector3.UP)
	if not up.is_equal_approx(Vector3.UP):
		push_error("Expected straight-up aim to stay up")
		return 1
	var empty := FlareFlightScript.launch_direction(Vector3.ZERO)
	if not empty.is_equal_approx(Vector3.FORWARD):
		push_error("Expected empty aim to fall back to forward")
		return 1
	var launch_vel := FlareFlightScript.initial_velocity(aim)
	if not is_equal_approx(launch_vel.length(), FlareFlightScript.LAUNCH_SPEED):
		push_error("Expected initial velocity at LAUNCH_SPEED")
		return 1
	return 0


func _test_decelerates_over_time() -> int:
	var velocity := FlareFlightScript.initial_velocity(Vector3.UP)
	var start_speed := velocity.length()
	## Two seconds — light drag still bleeds speed without a hard stop.
	var steps := 120
	var dt := 2.0 / float(steps)
	for _i in steps:
		velocity = FlareFlightScript.step_velocity(velocity, dt)
	if velocity.length() >= start_speed * 0.75:
		push_error(
			"Expected flare to decelerate within 2s, got %s from %s"
			% [velocity.length(), start_speed]
		)
		return 1
	return 0


func _test_gravity_pulls_down() -> int:
	var velocity := FlareFlightScript.initial_velocity(Vector3.FORWARD)
	if not is_zero_approx(velocity.y):
		push_error("Expected horizontal launch to start with zero vertical speed")
		return 1
	var after := FlareFlightScript.step_velocity(velocity, 0.25)
	if after.y >= 0.0:
		push_error("Expected gravity to pull flare velocity downward")
		return 1
	return 0


func _test_upward_shot_stays_aloft() -> int:
	var altitude := FlareFlightScript.simulate_altitude(2.0, Vector3.UP, 10.0)
	if altitude < 12.0:
		push_error(
			"Expected upward flare to stay sky-high for 10s, got altitude %s"
			% altitude
		)
		return 1
	return 0


func _test_default_life_is_fifteen() -> int:
	if not is_equal_approx(FlareFlightScript.DEFAULT_LIFE_SEC, 15.0):
		push_error("Expected flare default life to be 15 seconds")
		return 1
	return 0
