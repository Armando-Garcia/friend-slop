class_name TestPuzzleBasePieceNode
extends RefCounted

const PuzzleBasePieceEntryScript := preload("res://scripts/objectives/puzzle_base_piece_entry.gd")
const PuzzleBasePieceNodeScript := preload("res://scripts/objectives/puzzle_base_piece_node.gd")


func run() -> int:
	var failures := 0
	failures += _test_entry_round_trip()
	failures += _test_rect_base_builds_one_body()
	failures += _test_rect_hole_builds_floor_and_four_walls()
	failures += _test_cylinder_hole_builds_floor_and_wall_ring()
	return failures


func _test_entry_round_trip() -> int:
	var entry := PuzzleBasePieceEntryScript.new()
	entry.position = Vector3(1.5, 0.0, -2.25)
	entry.rotation_y_degrees = 90.0
	entry.shape = PuzzleBasePieceEntryScript.Shape.CYLINDER_HOLE
	entry.size = Vector3(1.8, 1.2, 0.0)

	var node := PuzzleBasePieceNodeScript.from_entry(entry)
	var round_tripped := node.to_entry()

	var failures := 0
	if not round_tripped.position.is_equal_approx(entry.position):
		push_error("Expected position to round-trip through PuzzleBasePieceNode")
		failures += 1
	if not is_equal_approx(round_tripped.rotation_y_degrees, entry.rotation_y_degrees):
		push_error("Expected rotation_y_degrees to round-trip through PuzzleBasePieceNode")
		failures += 1
	if round_tripped.shape != entry.shape:
		push_error("Expected shape to round-trip through PuzzleBasePieceNode")
		failures += 1
	if not round_tripped.size.is_equal_approx(entry.size):
		push_error("Expected size to round-trip through PuzzleBasePieceNode")
		failures += 1

	node.free()
	return failures


func _test_rect_base_builds_one_body() -> int:
	var entry := PuzzleBasePieceEntryScript.new()
	entry.shape = PuzzleBasePieceEntryScript.Shape.RECT_BASE
	entry.size = Vector3(5.4, 0.2, 5.4)
	var node := PuzzleBasePieceNodeScript.from_entry(entry)

	var built := node.get_node_or_null("Built")
	var failures := 0
	if built == null or built.get_child_count() != 1:
		push_error("Expected RECT_BASE to build exactly one StaticBody3D")
		failures += 1

	node.free()
	return failures


func _test_rect_hole_builds_floor_and_four_walls() -> int:
	var entry := PuzzleBasePieceEntryScript.new()
	entry.shape = PuzzleBasePieceEntryScript.Shape.RECT_HOLE
	entry.size = Vector3(2.0, 1.5, 2.0)
	var node := PuzzleBasePieceNodeScript.from_entry(entry)

	var built := node.get_node_or_null("Built")
	var failures := 0
	if built == null or built.get_child_count() != 5:
		push_error(
			"Expected RECT_HOLE to build a floor plus 4 walls (5 bodies), got %s"
			% (built.get_child_count() if built != null else -1)
		)
		failures += 1
	if built != null and built.get_node_or_null("Floor") == null:
		push_error("Expected RECT_HOLE to build a Floor body")
		failures += 1

	node.free()
	return failures


func _test_cylinder_hole_builds_floor_and_wall_ring() -> int:
	var entry := PuzzleBasePieceEntryScript.new()
	entry.shape = PuzzleBasePieceEntryScript.Shape.CYLINDER_HOLE
	entry.size = Vector3(1.5, 1.5, 0.0)
	var node := PuzzleBasePieceNodeScript.from_entry(entry)

	var built := node.get_node_or_null("Built")
	var failures := 0
	## 1 floor + CYLINDER_WALL_SEGMENTS (16) wall segments.
	if built == null or built.get_child_count() != 17:
		push_error(
			"Expected CYLINDER_HOLE to build a floor plus 16 wall segments (17 bodies), got %s"
			% (built.get_child_count() if built != null else -1)
		)
		failures += 1
	if built != null and built.get_node_or_null("Floor") == null:
		push_error("Expected CYLINDER_HOLE to build a Floor body")
		failures += 1

	node.free()
	return failures
