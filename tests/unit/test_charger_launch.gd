extends RefCounted

const ChargerLaunchScript := preload("res://scripts/monsters/charger_launch.gd")


class _GravityHost extends RefCounted:
	var gravity: Variant = null


func run() -> int:
	var failures := 0
	failures += _test_charge_speed_is_double_sprint()
	failures += _test_patrol_speed_is_80_percent_walk()
	failures += _test_head_plunge_is_down_in_330_360()
	failures += _test_head_toss_is_up()
	failures += _test_gravity_of_skips_null_and_non_floats()
	failures += _test_knockup_follows_charge_dir()
	failures += _test_knockup_rng_spreads_team()
	failures += _test_knockup_clears_wall_height()
	failures += _test_arc_points_follow_velocity()
	return failures


func _test_charge_speed_is_double_sprint() -> int:
	var speed := ChargerLaunchScript.charge_speed(5.0)
	if not is_equal_approx(speed, 11.5):
		push_error("Expected charger ram at 230%% of sprint 5, got %s" % speed)
		return 1
	if not is_equal_approx(ChargerLaunchScript.charge_speed(0.0), 0.0):
		push_error("Expected zero sprint to yield zero charge speed")
		return 1
	return 0


func _test_patrol_speed_is_80_percent_walk() -> int:
	var speed := ChargerLaunchScript.patrol_speed(3.0)
	if not is_equal_approx(speed, 2.4):
		push_error("Expected charger patrol at 80%% of walk 3, got %s" % speed)
		return 1
	return 0


func _test_head_plunge_is_down_in_330_360() -> int:
	if not is_equal_approx(ChargerLaunchScript.plunge_pitch_rad(360.0), 0.0):
		push_error("Expected 360° plunge to be level (0 rad)")
		return 1
	var down := ChargerLaunchScript.plunge_pitch_rad(330.0)
	if down >= 0.0 or not is_equal_approx(down, deg_to_rad(-30.0)):
		push_error("Expected 330° plunge to be 30° snout-down, got %s" % down)
		return 1
	var mid := ChargerLaunchScript.plunge_pitch_rad(338.0)
	if mid >= 0.0 or mid <= down:
		push_error("Expected default 338° between level and 330° down")
		return 1
	return 0


func _test_head_toss_is_up() -> int:
	var toss := ChargerLaunchScript.toss_pitch_rad(60.0)
	if toss <= 0.0 or not is_equal_approx(toss, deg_to_rad(60.0)):
		push_error("Expected 60° toss to lift the snout, got %s" % toss)
		return 1
	return 0


func _test_gravity_of_skips_null_and_non_floats() -> int:
	if not is_equal_approx(ChargerLaunchScript.gravity_of(null, 18.0), 18.0):
		push_error("Expected null node to keep fallback gravity")
		return 1
	var host := _GravityHost.new()
	if not is_equal_approx(ChargerLaunchScript.gravity_of(host, 18.0), 18.0):
		push_error("Expected null gravity property to keep fallback")
		return 1
	host.gravity = 9.8
	var got := ChargerLaunchScript.gravity_of(host, 18.0)
	if not is_equal_approx(got, 9.8):
		push_error("Expected float gravity from the node, got %s" % got)
		return 1
	host.gravity = 12
	if not is_equal_approx(ChargerLaunchScript.gravity_of(host, 18.0), 12.0):
		push_error("Expected int gravity to coerce to float")
		return 1
	host.gravity = Vector3.DOWN
	if not is_equal_approx(ChargerLaunchScript.gravity_of(host, 18.0), 18.0):
		push_error("Expected non-numeric gravity to keep fallback")
		return 1
	return 0


func _test_knockup_follows_charge_dir() -> int:
	var vel := ChargerLaunchScript.knockup_velocity(
		Vector3(1.0, 0.0, 0.0), 18.0, 3.0, 1.25, 15.0, null
	)
	if vel.x <= 0.0 or absf(vel.z) > 0.001:
		push_error("Expected knockup along +X, got %s" % vel)
		return 1
	if vel.y <= 0.0:
		push_error("Expected an upward knockup")
		return 1
	return 0


func _test_knockup_rng_spreads_team() -> int:
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 3
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 99
	var a := ChargerLaunchScript.knockup_velocity(
		Vector3(0.0, 0.0, 1.0), 18.0, 3.0, 1.25, 12.0, rng_a
	)
	var b := ChargerLaunchScript.knockup_velocity(
		Vector3(0.0, 0.0, 1.0), 18.0, 3.0, 1.25, 12.0, rng_b
	)
	var flat_a := Vector2(a.x, a.z)
	var flat_b := Vector2(b.x, b.z)
	if flat_a.dot(Vector2(0.0, 1.0)) <= 0.0 or flat_b.dot(Vector2(0.0, 1.0)) <= 0.0:
		push_error("Spread knockups should still go generally forward")
		return 1
	if flat_a.distance_to(flat_b) < 0.05:
		push_error("Expected RNG to split two knockups, got %s and %s" % [a, b])
		return 1
	return 0


func _test_knockup_clears_wall_height() -> int:
	var from := Vector3.ZERO
	var vel := ChargerLaunchScript.knockup_velocity(
		Vector3(1.0, 0.0, 0.0), 18.0, 3.0, 1.25, 14.0, null
	)
	var apex := ChargerLaunchScript.apex_height(from, vel, 18.0)
	if apex + 0.001 < 4.25:
		push_error("Expected apex above 3m walls + 1.25m, got %s" % apex)
		return 1
	return 0


func _test_arc_points_follow_velocity() -> int:
	var from := Vector3.ZERO
	var vel := ChargerLaunchScript.knockup_velocity(
		Vector3(1.0, 0.0, 0.0), 18.0, 3.0, 1.25, 14.0, null
	)
	var pts: PackedVector3Array = ChargerLaunchScript.arc_points(from, vel, 18.0, 12)
	if pts.size() < 2:
		push_error("Expected knockup arc samples")
		return 1
	if pts[pts.size() - 1].x <= from.x:
		push_error("Arc should travel along +X, got %s" % pts[pts.size() - 1])
		return 1
	return 0
