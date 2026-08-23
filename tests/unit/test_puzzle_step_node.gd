class_name TestPuzzleStepNode
extends RefCounted

const PuzzleStepEntryScript := preload("res://scripts/objectives/puzzle_step_entry.gd")
const PuzzleStepNodeScript := preload("res://scripts/objectives/puzzle_step_node.gd")


## Duck-typed stand-in for PlayableCharacter — _trigger_launch only needs
## a body with an apply_ember_halo_jump_pad(strength_mult) method.
class FakeLaunchTarget:
	extends RefCounted
	var received_strength: float = -1.0

	func apply_ember_halo_jump_pad(strength_mult: float = 1.0) -> void:
		received_strength = strength_mult


func run() -> int:
	var failures := 0
	failures += _test_entry_round_trip()
	failures += _test_staircase_shape_round_trips()
	failures += _test_launch_trap_passes_trap_param_as_strength()
	failures += _test_launch_trap_clamps_negative_trap_param()
	return failures


func _test_entry_round_trip() -> int:
	var entry := PuzzleStepEntryScript.new()
	entry.position = Vector3(1.5, 2.25, -3.0)
	entry.rotation_y_degrees = 135.0
	entry.shape = PuzzleStepEntryScript.Shape.RAMP
	entry.size = Vector3(1.6, 0.6, 1.4)
	entry.is_summit = true
	entry.trap_type = PuzzleStepEntryScript.Trap.CRUMBLE
	entry.trap_param = 0.9

	var node := PuzzleStepNodeScript.from_entry(entry)
	var round_tripped := node.to_entry()

	var failures := 0
	if not round_tripped.position.is_equal_approx(entry.position):
		push_error("Expected position to round-trip through PuzzleStepNode")
		failures += 1
	if not is_equal_approx(round_tripped.rotation_y_degrees, entry.rotation_y_degrees):
		push_error("Expected rotation_y_degrees to round-trip through PuzzleStepNode")
		failures += 1
	if round_tripped.shape != entry.shape:
		push_error("Expected shape to round-trip through PuzzleStepNode")
		failures += 1
	if not round_tripped.size.is_equal_approx(entry.size):
		push_error("Expected size to round-trip through PuzzleStepNode")
		failures += 1
	if round_tripped.is_summit != entry.is_summit:
		push_error("Expected is_summit to round-trip through PuzzleStepNode")
		failures += 1
	if round_tripped.trap_type != entry.trap_type:
		push_error("Expected trap_type to round-trip through PuzzleStepNode")
		failures += 1
	if not is_equal_approx(round_tripped.trap_param, entry.trap_param):
		push_error("Expected trap_param to round-trip through PuzzleStepNode")
		failures += 1

	node.free()
	return failures


func _test_staircase_shape_round_trips() -> int:
	var entry := PuzzleStepEntryScript.new()
	entry.shape = PuzzleStepEntryScript.Shape.STAIRCASE
	entry.size = Vector3(1.6, 0.8, 1.8)

	var node := PuzzleStepNodeScript.from_entry(entry)
	var failures := 0
	if node.shape != PuzzleStepEntryScript.Shape.STAIRCASE:
		push_error("Expected the live node to pick up the STAIRCASE shape")
		failures += 1
	var round_tripped := node.to_entry()
	if round_tripped.shape != PuzzleStepEntryScript.Shape.STAIRCASE:
		push_error("Expected STAIRCASE shape to round-trip through PuzzleStepNode")
		failures += 1
	node.free()
	return failures


func _test_launch_trap_passes_trap_param_as_strength() -> int:
	var entry := PuzzleStepEntryScript.new()
	entry.trap_type = PuzzleStepEntryScript.Trap.LAUNCH
	entry.trap_param = 2.5
	var node := PuzzleStepNodeScript.from_entry(entry)
	var target := FakeLaunchTarget.new()
	node.call("_trigger_launch", target)
	node.free()

	if not is_equal_approx(target.received_strength, 2.5):
		push_error(
			"Expected the launch trap to pass trap_param (2.5) through as the strength"
			+ " multiplier, got %s" % target.received_strength
		)
		return 1
	return 0


func _test_launch_trap_clamps_negative_trap_param() -> int:
	var entry := PuzzleStepEntryScript.new()
	entry.trap_type = PuzzleStepEntryScript.Trap.LAUNCH
	entry.trap_param = -1.0
	var node := PuzzleStepNodeScript.from_entry(entry)
	var target := FakeLaunchTarget.new()
	node.call("_trigger_launch", target)
	node.free()

	if not is_zero_approx(target.received_strength):
		push_error(
			"Expected a negative trap_param to clamp to a 0 strength multiplier, got %s"
			% target.received_strength
		)
		return 1
	return 0
