extends RefCounted

const WorldGroundScript := preload("res://scripts/world_ground.gd")


func run() -> int:
	var failures := 0
	failures += _test_with_height_above_ground_fallback()
	return failures


func _test_with_height_above_ground_fallback() -> int:
	var pos := WorldGroundScript.with_height_above_ground(
		null, Vector3(3.0, 9.0, -2.0), 1.15, 0.0
	)
	if not is_equal_approx(pos.x, 3.0) or not is_equal_approx(pos.z, -2.0):
		push_error("Expected XZ to be preserved when snapping height")
		return 1
	if not is_equal_approx(pos.y, 1.15):
		push_error("Expected fallback ground 0 + height 1.15, got %s" % pos.y)
		return 1
	return 0
