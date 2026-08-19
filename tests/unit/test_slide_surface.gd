extends RefCounted

const SlideSurfaceScript := preload("res://scripts/slide_surface.gd")


func run() -> int:
	var failures := 0
	failures += _test_tagged_up_normal_is_slide_floor()
	failures += _test_tagged_vertical_is_not_slide_floor()
	failures += _test_untagged_up_normal_is_walkable()
	failures += _test_peak_push_keeps_moving_bodies()
	failures += _test_peak_push_amplifies_leftover()
	failures += _test_peak_push_picks_a_direction_when_still()
	return failures


func _test_tagged_up_normal_is_slide_floor() -> int:
	var body := StaticBody3D.new()
	SlideSurfaceScript.tag(body)
	if not SlideSurfaceScript.is_slide_floor(body, Vector3.UP):
		push_error("Tagged wall top should be a slide floor")
		body.free()
		return 1
	body.free()
	return 0


func _test_tagged_vertical_is_not_slide_floor() -> int:
	var body := StaticBody3D.new()
	SlideSurfaceScript.tag(body)
	if SlideSurfaceScript.is_slide_floor(body, Vector3.FORWARD):
		push_error("Vertical wall faces should stay walls, not slide floors")
		body.free()
		return 1
	body.free()
	return 0


func _test_untagged_up_normal_is_walkable() -> int:
	var body := StaticBody3D.new()
	if not SlideSurfaceScript.is_walkable_floor(body, Vector3.UP):
		push_error("Maze floor should stay walkable")
		body.free()
		return 1
	if SlideSurfaceScript.is_slide_floor(body, Vector3.UP):
		push_error("Untagged floor should not be a slide surface")
		body.free()
		return 1
	body.free()
	return 0


func _test_peak_push_keeps_moving_bodies() -> int:
	var vel := Vector3(1.2, -3.0, 0.4)
	var out: Vector3 = SlideSurfaceScript.peak_push(vel, Vector3.UP)
	if not out.is_equal_approx(vel):
		push_error("Already-moving bodies should keep their slide, got %s" % out)
		return 1
	var slope: Vector3 = SlideSurfaceScript.peak_push(
		Vector3.ZERO, Vector3(0.4, 0.9, 0.0).normalized()
	)
	if not slope.is_equal_approx(Vector3.ZERO):
		push_error("Off-crest slopes should not get a peak nudge, got %s" % slope)
		return 1
	return 0


func _test_peak_push_amplifies_leftover() -> int:
	var out: Vector3 = SlideSurfaceScript.peak_push(Vector3(0.1, -2.0, 0.0), Vector3.UP)
	if out.x <= 0.0 or absf(out.z) > 0.001:
		push_error("Leftover XZ should be amplified off the crest, got %s" % out)
		return 1
	if absf(out.y + 2.0) > 0.001:
		push_error("Peak nudge must keep vertical speed, got %s" % out.y)
		return 1
	return 0


func _test_peak_push_picks_a_direction_when_still() -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var out: Vector3 = SlideSurfaceScript.peak_push(Vector3.ZERO, Vector3.UP, rng)
	var horiz := Vector2(out.x, out.z).length()
	if absf(horiz - SlideSurfaceScript.PEAK_NUDGE) > 0.001:
		push_error("Still peak landings need a full nudge, got %s" % horiz)
		return 1
	return 0
