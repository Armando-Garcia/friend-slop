class_name TestPuzzlePendulum
extends RefCounted

const PuzzlePendulumEntryScript := preload("res://scripts/objectives/puzzle_pendulum_entry.gd")
const PuzzlePendulumNodeScript := preload("res://scripts/objectives/puzzle_pendulum_node.gd")
const EXAMPLE_PUZZLE_PATH := "res://resources/objectives/puzzles/example_spiral.tres"


func run() -> int:
	var failures := 0
	failures += _test_entry_round_trip()
	failures += _test_current_angle_zero_at_rest()
	failures += _test_current_angle_scales_with_amplitude()
	failures += _test_example_puzzle_has_pendulum()
	return failures


func _test_entry_round_trip() -> int:
	var entry := PuzzlePendulumEntryScript.new()
	entry.position = Vector3(1.0, 2.5, -1.5)
	entry.radius = 3.1
	entry.speed = 1.4
	entry.swing_amplitude_degrees = 60.0
	entry.bob_size = 1.1
	entry.swing_plane_rotation_degrees = 90.0
	entry.bounce_pad_left = true
	entry.bounce_pad_right = false

	var node := PuzzlePendulumNodeScript.from_entry(entry)
	var round_tripped := node.to_entry()

	var failures := 0
	if not round_tripped.position.is_equal_approx(entry.position):
		push_error("Expected position to round-trip through PuzzlePendulumNode")
		failures += 1
	if not is_equal_approx(round_tripped.radius, entry.radius):
		push_error("Expected radius to round-trip through PuzzlePendulumNode")
		failures += 1
	if not is_equal_approx(round_tripped.speed, entry.speed):
		push_error("Expected speed to round-trip through PuzzlePendulumNode")
		failures += 1
	if not is_equal_approx(round_tripped.swing_amplitude_degrees, entry.swing_amplitude_degrees):
		push_error("Expected swing_amplitude_degrees to round-trip through PuzzlePendulumNode")
		failures += 1
	if not is_equal_approx(round_tripped.bob_size, entry.bob_size):
		push_error("Expected bob_size to round-trip through PuzzlePendulumNode")
		failures += 1
	if not is_equal_approx(
		round_tripped.swing_plane_rotation_degrees, entry.swing_plane_rotation_degrees
	):
		push_error("Expected swing_plane_rotation_degrees to round-trip through PuzzlePendulumNode")
		failures += 1
	if round_tripped.bounce_pad_left != entry.bounce_pad_left:
		push_error("Expected bounce_pad_left to round-trip through PuzzlePendulumNode")
		failures += 1
	if round_tripped.bounce_pad_right != entry.bounce_pad_right:
		push_error("Expected bounce_pad_right to round-trip through PuzzlePendulumNode")
		failures += 1

	node.free()
	return failures


func _test_current_angle_zero_at_rest() -> int:
	var node := PuzzlePendulumNodeScript.new()
	node.swing_amplitude_degrees = 45.0
	## _phase starts at 0.0, so sin(0) = 0 — the bob hangs straight down.
	if not is_equal_approx(node.current_angle(), 0.0):
		push_error("Expected a fresh pendulum's angle to be 0 (hanging straight down)")
		node.free()
		return 1
	node.free()
	return 0


func _test_current_angle_scales_with_amplitude() -> int:
	var node := PuzzlePendulumNodeScript.new()
	node.swing_amplitude_degrees = 90.0
	node._phase = PI * 0.5
	## sin(pi/2) = 1, so the angle should hit the full amplitude.
	if not is_equal_approx(node.current_angle(), deg_to_rad(90.0)):
		push_error("Expected the swing angle to reach full amplitude at phase pi/2")
		node.free()
		return 1
	node.free()
	return 0


func _test_example_puzzle_has_pendulum() -> int:
	if not ResourceLoader.exists(EXAMPLE_PUZZLE_PATH):
		push_error("Expected the example puzzle resource to exist at %s" % EXAMPLE_PUZZLE_PATH)
		return 1
	var puzzle := ResourceLoader.load(EXAMPLE_PUZZLE_PATH) as PuzzleDefinition
	if puzzle == null:
		push_error("Expected the example puzzle to load as a PuzzleDefinition")
		return 1
	if puzzle.pendulums.is_empty():
		push_error("Expected the example puzzle to include a pendulum trap")
		return 1
	var pendulum: PuzzlePendulumEntry = puzzle.pendulums[0]
	if not (pendulum.bounce_pad_left and pendulum.bounce_pad_right):
		push_error("Expected the example pendulum to demonstrate both bounce pads")
		return 1
	return 0
