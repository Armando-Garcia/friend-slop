class_name TestPuzzleMovingPlatform
extends RefCounted

const PuzzleMovingPlatformEntryScript := preload(
	"res://scripts/objectives/puzzle_moving_platform_entry.gd"
)
const PuzzlePlatformPathPointEntryScript := preload(
	"res://scripts/objectives/puzzle_platform_path_point_entry.gd"
)
const PuzzleMovingPlatformNodeScript := preload(
	"res://scripts/objectives/puzzle_moving_platform_node.gd"
)
const EXAMPLE_PUZZLE_PATH := "res://resources/objectives/puzzles/example_spiral.tres"


func run() -> int:
	var failures := 0
	failures += _test_entry_round_trip_with_path_points()
	failures += _test_new_path_point_defaults()
	failures += _test_path_point_children_ignores_the_tile_body()
	failures += _test_example_puzzle_has_platform()
	return failures


func _test_entry_round_trip_with_path_points() -> int:
	var entry := PuzzleMovingPlatformEntryScript.new()
	entry.position = Vector3(1.0, 2.0, -1.0)
	entry.path_type = PuzzleMovingPlatformEntryScript.PathType.POLYGON
	entry.speed = 3.5
	entry.is_jump_tile = true
	entry.tile_shape = PuzzleMovingPlatformEntryScript.TileShape.STAIRCASE
	entry.tile_size = Vector3(2.0, 0.4, 2.0)
	entry.circle_radius = 4.5
	entry.circle_rotation_degrees = Vector3(0.0, 90.0, 0.0)
	entry.closed_loop = false

	var point_a := PuzzlePlatformPathPointEntryScript.new()
	point_a.position = Vector3(1.0, 0.0, 0.0)
	point_a.stop_seconds = 0.0
	var point_b := PuzzlePlatformPathPointEntryScript.new()
	point_b.position = Vector3(3.0, 0.0, 2.0)
	point_b.stop_seconds = 1.25
	entry.path_points = [point_a, point_b]

	var node := PuzzleMovingPlatformNodeScript.from_entry(entry)
	var round_tripped := node.to_entry()

	var failures := 0
	if not round_tripped.position.is_equal_approx(entry.position):
		push_error("Expected position to round-trip through PuzzleMovingPlatformNode")
		failures += 1
	if round_tripped.path_type != entry.path_type:
		push_error("Expected path_type to round-trip through PuzzleMovingPlatformNode")
		failures += 1
	if not is_equal_approx(round_tripped.speed, entry.speed):
		push_error("Expected speed to round-trip through PuzzleMovingPlatformNode")
		failures += 1
	if round_tripped.is_jump_tile != entry.is_jump_tile:
		push_error("Expected is_jump_tile to round-trip through PuzzleMovingPlatformNode")
		failures += 1
	if round_tripped.tile_shape != entry.tile_shape:
		push_error("Expected tile_shape to round-trip through PuzzleMovingPlatformNode")
		failures += 1
	if not round_tripped.tile_size.is_equal_approx(entry.tile_size):
		push_error("Expected tile_size to round-trip through PuzzleMovingPlatformNode")
		failures += 1
	if not is_equal_approx(round_tripped.circle_radius, entry.circle_radius):
		push_error("Expected circle_radius to round-trip through PuzzleMovingPlatformNode")
		failures += 1
	if not round_tripped.circle_rotation_degrees.is_equal_approx(entry.circle_rotation_degrees):
		push_error("Expected circle_rotation_degrees to round-trip through PuzzleMovingPlatformNode")
		failures += 1
	if round_tripped.closed_loop != entry.closed_loop:
		push_error("Expected closed_loop to round-trip through PuzzleMovingPlatformNode")
		failures += 1
	if round_tripped.path_points.size() != 2:
		push_error(
			"Expected 2 path points to round-trip, got %d" % round_tripped.path_points.size()
		)
		failures += 1
	else:
		if not round_tripped.path_points[0].position.is_equal_approx(point_a.position):
			push_error("Expected path point 0's position to round-trip")
			failures += 1
		if not is_equal_approx(round_tripped.path_points[1].stop_seconds, point_b.stop_seconds):
			push_error("Expected path point 1's stop_seconds to round-trip")
			failures += 1

	node.free()
	return failures


func _test_new_path_point_defaults() -> int:
	var node := PuzzleMovingPlatformNodeScript.new()
	var point := node.new_path_point(Vector3(2.0, 0.0, 0.0))
	if not point.position.is_equal_approx(Vector3(2.0, 0.0, 0.0)):
		push_error("Expected new_path_point to set the requested local position")
		node.free()
		point.free()
		return 1
	if not is_equal_approx(point.stop_seconds, 0.0):
		push_error("Expected a fresh path point to default to no stop")
		node.free()
		point.free()
		return 1
	node.free()
	point.free()
	return 0


func _test_path_point_children_ignores_the_tile_body() -> int:
	## The platform's own tile body lives as a sibling child alongside path
	## points — path_point_children() must not pick it up, only real
	## PuzzlePlatformPathPointNode children.
	var node := PuzzleMovingPlatformNodeScript.new()
	var fake_tile := AnimatableBody3D.new()
	fake_tile.name = "Tile"
	node.add_child(fake_tile)
	node.add_child(node.new_path_point(Vector3(1.0, 0.0, 0.0)))
	var count := node.path_point_children().size()
	node.free()
	if count != 1:
		push_error("Expected path_point_children() to report only the real path point, got %d" % count)
		return 1
	return 0


func _test_example_puzzle_has_platform() -> int:
	if not ResourceLoader.exists(EXAMPLE_PUZZLE_PATH):
		push_error("Expected the example puzzle resource to exist at %s" % EXAMPLE_PUZZLE_PATH)
		return 1
	var puzzle := ResourceLoader.load(EXAMPLE_PUZZLE_PATH) as PuzzleDefinition
	if puzzle == null:
		push_error("Expected the example puzzle to load as a PuzzleDefinition")
		return 1
	if puzzle.platforms.is_empty():
		push_error("Expected the example puzzle to include a moving platform")
		return 1
	var platform: PuzzleMovingPlatformEntry = puzzle.platforms[0]
	if platform.path_points.size() < 2:
		push_error("Expected the example platform to define at least 2 path points")
		return 1
	return 0
