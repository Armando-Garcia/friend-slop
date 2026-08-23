class_name TestClearingPlacement
extends RefCounted

const MazeCarverScript := preload("res://scripts/maze_carver.gd")
const ClearingPlacementScript := preload("res://scripts/objectives/clearing_placement.gd")


func run() -> int:
	var failures := 0
	failures += _test_finds_largest_clearing()
	failures += _test_empty_without_wall_grid()
	return failures


func _test_finds_largest_clearing() -> int:
	var grid: Array = MazeCarverScript.generate(20, 20, 4242, {
		"mean_corridor_length": 3.0,
		"clearing_count": 3,
		"clearing_size": 2.0,
		"clearing_separation": 6.0,
	})
	var clearing := ClearingPlacementScript.largest_clearing(grid, 20, 20, 4.0)
	if clearing.is_empty():
		push_error("Expected a clearing on a maze configured with clearing_count > 0")
		return 1
	var size: Vector3 = clearing["size"]
	if size.x <= 0.0 or size.z <= 0.0:
		push_error("Expected the largest clearing to have a positive footprint")
		return 1
	var origin: Vector3 = clearing["origin"]
	var center: Vector3 = clearing["center"]
	var expected_center := origin + Vector3(size.x * 0.5, 0.0, size.z * 0.5)
	if not center.is_equal_approx(expected_center):
		push_error("Expected clearing center to be the footprint midpoint")
		return 1
	return 0


func _test_empty_without_wall_grid() -> int:
	var clearing := ClearingPlacementScript.largest_clearing([], 10, 10, 4.0)
	if not clearing.is_empty():
		push_error("Expected no clearing result from an empty wall grid")
		return 1
	return 0
