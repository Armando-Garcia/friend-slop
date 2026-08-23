class_name TestPuzzlePlatformMotion
extends RefCounted

const MotionScript := preload("res://scripts/objectives/puzzle_platform_motion.gd")


func run() -> int:
	var failures := 0
	failures += _test_waypoint_moves_forward_along_open_path()
	failures += _test_waypoint_ping_pongs_at_open_end()
	failures += _test_waypoint_loops_at_closed_end()
	failures += _test_waypoint_pauses_at_stop_then_resumes()
	failures += _test_waypoint_position_interpolates_mid_segment()
	failures += _test_waypoint_noop_with_fewer_than_two_points()
	failures += _test_circle_position_at_known_angles()
	failures += _test_circle_advances_without_stops()
	failures += _test_circle_pauses_at_stop_then_resumes()
	failures += _test_circle_single_stop_requires_full_lap_to_retrigger()
	return failures


## --- Waypoint (LINE / POLYGON) ---------------------------------------------

func _test_waypoint_moves_forward_along_open_path() -> int:
	var points := [Vector3(0, 0, 0), Vector3(10, 0, 0)]
	var stops := [0.0, 0.0]
	var state := MotionScript.default_waypoint_state()
	state = MotionScript.advance_waypoint_state(state, points, stops, 2.0, 1.0, false)
	var pos: Vector3 = MotionScript.waypoint_state_position(state, points)
	if not pos.is_equal_approx(Vector3(2.0, 0, 0)):
		push_error("Expected 2 m/s for 1s to travel 2m along the line, got %s" % pos)
		return 1
	return 0


func _test_waypoint_ping_pongs_at_open_end() -> int:
	var points := [Vector3(0, 0, 0), Vector3(4, 0, 0)]
	var stops := [0.0, 0.0]
	var state := MotionScript.default_waypoint_state()
	## 10m of travel on a 4m line: 0->4 (reverse), 4->0 (reverse again),
	## then 2m back out toward 4 — ends at x=2, heading forward again.
	state = MotionScript.advance_waypoint_state(state, points, stops, 2.0, 5.0, false)
	var pos: Vector3 = MotionScript.waypoint_state_position(state, points)
	if not pos.is_equal_approx(Vector3(2.0, 0, 0)):
		push_error("Expected the double bounce to land at x=2, got %s" % pos)
		return 1
	if int(state.direction) != 1:
		push_error("Expected direction to be forward (1) after bouncing off both ends")
		return 1
	return 0


func _test_waypoint_loops_at_closed_end() -> int:
	var points := [Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(0, 0, 4)]
	var stops := [0.0, 0.0, 0.0, 0.0]
	var state := MotionScript.default_waypoint_state()
	## Perimeter is 16m; 18m of travel should wrap 2m into the first leg again.
	state = MotionScript.advance_waypoint_state(state, points, stops, 2.0, 9.0, true)
	var pos: Vector3 = MotionScript.waypoint_state_position(state, points)
	if not pos.is_equal_approx(Vector3(2.0, 0, 0)):
		push_error("Expected the closed loop to wrap back to x=2 on the first leg, got %s" % pos)
		return 1
	return 0


func _test_waypoint_pauses_at_stop_then_resumes() -> int:
	var points := [Vector3(0, 0, 0), Vector3(2, 0, 0)]
	var stops := [0.0, 1.5]
	var state := MotionScript.default_waypoint_state()
	## 2m at 2 m/s takes exactly 1s to arrive at the stop.
	state = MotionScript.advance_waypoint_state(state, points, stops, 2.0, 1.0, false)
	if not bool(state.paused):
		push_error("Expected the platform to be paused after arriving at a 1.5s stop")
		return 1
	var pos_while_paused: Vector3 = MotionScript.waypoint_state_position(state, points)
	if not pos_while_paused.is_equal_approx(Vector3(2, 0, 0)):
		push_error("Expected the platform to sit exactly at the stop while paused")
		return 1
	## Half the dwell time elapses — still paused.
	state = MotionScript.advance_waypoint_state(state, points, stops, 2.0, 0.75, false)
	if not bool(state.paused):
		push_error("Expected the platform to still be paused mid-dwell")
		return 1
	## The rest of the dwell time elapses — should resume and start moving back.
	state = MotionScript.advance_waypoint_state(state, points, stops, 2.0, 1.0, false)
	if bool(state.paused):
		push_error("Expected the platform to resume once the dwell time fully elapses")
		return 1
	return 0


func _test_waypoint_position_interpolates_mid_segment() -> int:
	var points := [Vector3(0, 0, 0), Vector3(10, 0, 0)]
	var state := MotionScript.default_waypoint_state()
	state.progress = 5.0
	var pos: Vector3 = MotionScript.waypoint_state_position(state, points)
	if not pos.is_equal_approx(Vector3(5, 0, 0)):
		push_error("Expected the midpoint of the segment, got %s" % pos)
		return 1
	return 0


func _test_waypoint_noop_with_fewer_than_two_points() -> int:
	var state := MotionScript.default_waypoint_state()
	var out := MotionScript.advance_waypoint_state(state, [Vector3.ZERO], [0.0], 2.0, 1.0, false)
	if not is_equal_approx(float(out.progress), float(state.progress)):
		push_error("Expected advance_waypoint_state to no-op with fewer than 2 points")
		return 1
	return 0


## --- Circle -----------------------------------------------------------------

func _test_circle_position_at_known_angles() -> int:
	var state := MotionScript.default_circle_state()
	state.angle = 0.0
	if not MotionScript.circle_position(state, 5.0).is_equal_approx(Vector3(5, 0, 0)):
		push_error("Expected angle 0 to sit at (radius, 0, 0)")
		return 1
	state.angle = PI * 0.5
	if not MotionScript.circle_position(state, 5.0).is_equal_approx(Vector3(0, 0, 5)):
		push_error("Expected angle pi/2 to sit at (0, 0, radius)")
		return 1
	return 0


func _test_circle_advances_without_stops() -> int:
	var state := MotionScript.default_circle_state()
	## angular speed = speed / radius = 2/4 = 0.5 rad/s; over 2s -> 1.0 rad.
	state = MotionScript.advance_circle_state(state, [], 4.0, 2.0, 2.0)
	if not is_equal_approx(float(state.angle), 1.0):
		push_error("Expected the circle angle to advance by 1.0 rad, got %s" % state.angle)
		return 1
	return 0


func _test_circle_pauses_at_stop_then_resumes() -> int:
	var stops := [{"angle": 1.0, "seconds": 2.0}]
	var state := MotionScript.default_circle_state()
	## Reaches angle 1.0 rad after exactly 2s at 0.5 rad/s.
	state = MotionScript.advance_circle_state(state, stops, 4.0, 2.0, 2.0)
	if not bool(state.paused):
		push_error("Expected the platform to be paused at the circle stop")
		return 1
	if not is_equal_approx(float(state.angle), 1.0):
		push_error("Expected the angle to sit exactly at the stop while paused, got %s" % state.angle)
		return 1
	state = MotionScript.advance_circle_state(state, stops, 4.0, 2.0, 2.0)
	if bool(state.paused):
		push_error("Expected the platform to resume once the 2s dwell elapses")
		return 1
	return 0


func _test_circle_single_stop_requires_full_lap_to_retrigger() -> int:
	var stops := [{"angle": 0.0, "seconds": 1.0}]
	var state := MotionScript.default_circle_state()
	state.angle = 0.0
	## Standing exactly on the only stop: advancing should NOT re-pause
	## immediately — it needs a full lap (TAU rad) before the stop triggers
	## again, otherwise the platform would freeze forever.
	state = MotionScript.advance_circle_state(state, stops, 1.0, 1.0, 0.5)
	if bool(state.paused):
		push_error("Expected the platform to travel away from its own stop, not re-pause instantly")
		return 1
	if not is_equal_approx(float(state.angle), 0.5):
		push_error("Expected the angle to have advanced by 0.5 rad, got %s" % state.angle)
		return 1
	return 0
