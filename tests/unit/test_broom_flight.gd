class_name TestBroomFlight
extends RefCounted

const BroomLocomotionScript := preload("res://scripts/headmaster/broom_locomotion.gd")


func run() -> int:
	var failures := 0
	failures += _test_accelerate_and_coast_friction()
	failures += _test_vertical_controls()
	failures += _test_boost_triples_max_speed()
	failures += _test_coast_ignores_camera_turn()
	failures += _test_knockback_uses_fireball_direction()
	failures += _test_no_friction_while_thrusting()
	failures += _test_release_sprint_keeps_momentum_while_thrusting()
	return failures


func _test_accelerate_and_coast_friction() -> int:
	var forward := Vector3(0.0, 0.0, -1.0)
	var wish := BroomLocomotionScript.wish_direction(forward, 1.0, 0.0)
	var vel := Vector3.ZERO
	vel = BroomLocomotionScript.step_planar_velocity(vel, wish, 0.5)
	if vel.length() <= 0.0 or vel.length() > BroomLocomotionScript.MAX_SPEED:
		push_error("Expected forward wish to raise broom planar speed")
		return 1
	var after_coast := BroomLocomotionScript.step_planar_velocity(vel, Vector3.ZERO, 0.25)
	if after_coast.length() >= vel.length() - 0.001:
		push_error("Expected friction to bleed broom momentum when not accelerating")
		return 1
	if after_coast.length() <= 0.0:
		push_error("Expected coasting to retain some momentum briefly")
		return 1
	return 0


func _test_vertical_controls() -> int:
	if not is_equal_approx(
		BroomLocomotionScript.vertical_velocity(true, false),
		BroomLocomotionScript.CLIMB_SPEED
	):
		push_error("Expected ascend vertical velocity")
		return 1
	if not is_equal_approx(
		BroomLocomotionScript.vertical_velocity(false, true),
		-BroomLocomotionScript.CLIMB_SPEED
	):
		push_error("Expected descend vertical velocity")
		return 1
	if not is_equal_approx(BroomLocomotionScript.vertical_velocity(false, false), 0.0):
		push_error("Expected hover vertical velocity when neither key held")
		return 1
	return 0


func _test_boost_triples_max_speed() -> int:
	var boosted := BroomLocomotionScript.max_speed_with_boost(true)
	var normal := BroomLocomotionScript.max_speed_with_boost(false)
	if not is_equal_approx(normal, BroomLocomotionScript.MAX_SPEED):
		push_error("Expected unboosted broom max speed")
		return 1
	if not is_equal_approx(boosted, BroomLocomotionScript.MAX_SPEED * 3.0):
		push_error("Expected Shift boost to triple broom max speed")
		return 1
	return 0


func _test_coast_ignores_camera_turn() -> int:
	## Build momentum looking -Z, then coast while "facing" +X — vector must hold.
	var vel := Vector3(0.0, 0.0, -3.0)
	var facing_right := Vector3(1.0, 0.0, 0.0)
	var wish_none := BroomLocomotionScript.wish_direction(facing_right, 0.0, 0.0)
	var after := BroomLocomotionScript.step_planar_velocity(vel, wish_none, 0.1)
	if absf(after.x) > 0.001:
		push_error("Expected coasting momentum to stay on world Z when camera turns")
		return 1
	if after.z >= -0.01:
		push_error("Expected coasting to keep traveling the original world direction")
		return 1
	return 0


func _test_knockback_uses_fireball_direction() -> int:
	var impulse := BroomLocomotionScript.knockback_impulse(Vector3(1.0, 0.2, 0.0))
	if impulse.x <= 0.0:
		push_error("Expected knockback to push along fireball X")
		return 1
	if impulse.y <= 0.0:
		push_error("Expected knockback to include upward component")
		return 1
	return 0


func _test_no_friction_while_thrusting() -> int:
	var forward := Vector3(0.0, 0.0, -1.0)
	var wish := BroomLocomotionScript.wish_direction(forward, 1.0, 0.0)
	var vel := forward * 3.0
	var after := BroomLocomotionScript.step_planar_velocity(
		vel, wish, 0.25, BroomLocomotionScript.MAX_SPEED, 8.0, 40.0
	)
	if after.length() < vel.length() - 0.001:
		push_error("Expected no friction bleed while forward thrust is held")
		return 1
	return 0


func _test_release_sprint_keeps_momentum_while_thrusting() -> int:
	## After sprinting, dropping the speed cap must not hard-brake while W is held.
	var forward := Vector3(0.0, 0.0, -1.0)
	var wish := BroomLocomotionScript.wish_direction(forward, 1.0, 0.0)
	var sprint_speed := BroomLocomotionScript.MAX_SPEED * 3.0
	var vel := forward * sprint_speed
	var after := BroomLocomotionScript.step_planar_velocity(
		vel, wish, 0.1, BroomLocomotionScript.MAX_SPEED, 8.0, 4.0
	)
	if after.length() < sprint_speed - 0.05:
		push_error("Expected releasing sprint to keep momentum while still thrusting")
		return 1
	return 0
