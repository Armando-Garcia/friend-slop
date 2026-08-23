class_name TestPuzzleDefinition
extends RefCounted

const PuzzleDefinitionScript := preload("res://scripts/objectives/puzzle_definition.gd")
const PuzzleStepEntryScript := preload("res://scripts/objectives/puzzle_step_entry.gd")
const EXAMPLE_PUZZLE_PATH := "res://resources/objectives/puzzles/example_spiral.tres"


func run() -> int:
	var failures := 0
	failures += _test_find_summit_step_prefers_marked_entry()
	failures += _test_find_summit_step_falls_back_to_last()
	failures += _test_find_summit_step_empty_returns_null()
	failures += _test_example_puzzle_loads()
	return failures


func _test_find_summit_step_prefers_marked_entry() -> int:
	var puzzle := PuzzleDefinitionScript.new()
	var a := PuzzleStepEntryScript.new()
	var b := PuzzleStepEntryScript.new()
	b.is_summit = true
	var c := PuzzleStepEntryScript.new()
	puzzle.steps = [a, b, c]
	if puzzle.find_summit_step() != b:
		push_error("Expected find_summit_step to return the marked entry")
		return 1
	return 0


func _test_find_summit_step_falls_back_to_last() -> int:
	var puzzle := PuzzleDefinitionScript.new()
	var a := PuzzleStepEntryScript.new()
	var b := PuzzleStepEntryScript.new()
	puzzle.steps = [a, b]
	if puzzle.find_summit_step() != b:
		push_error("Expected find_summit_step to fall back to the last step")
		return 1
	return 0


func _test_find_summit_step_empty_returns_null() -> int:
	var puzzle := PuzzleDefinitionScript.new()
	if puzzle.find_summit_step() != null:
		push_error("Expected find_summit_step to return null for an empty puzzle")
		return 1
	return 0


func _test_example_puzzle_loads() -> int:
	if not ResourceLoader.exists(EXAMPLE_PUZZLE_PATH):
		push_error("Expected the example puzzle resource to exist at %s" % EXAMPLE_PUZZLE_PATH)
		return 1
	var puzzle := ResourceLoader.load(EXAMPLE_PUZZLE_PATH) as PuzzleDefinition
	if puzzle == null:
		push_error("Expected the example puzzle to load as a PuzzleDefinition")
		return 1
	if puzzle.steps.is_empty():
		push_error("Expected the example puzzle to have steps")
		return 1
	var summit := puzzle.find_summit_step()
	if summit == null or not summit.is_summit:
		push_error("Expected the example puzzle to have an explicit summit step")
		return 1
	return 0
