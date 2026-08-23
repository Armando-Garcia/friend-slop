class_name TestWizardChallengeHeightState
extends RefCounted

const StateScript := preload("res://scripts/objectives/wizard_challenge_height_state.gd")


func run() -> int:
	var failures := 0
	failures += _test_win_in_range()
	failures += _test_win_out_of_range_fails()
	failures += _test_second_win_after_complete_fails()
	return failures


func _test_win_in_range() -> int:
	var state := StateScript.new()
	var player := Node.new()
	if not state.try_win(player, Vector3.ZERO, Vector3.ZERO, 4.0):
		push_error("Expected in-range win to succeed")
		return 1
	if state.phase != StateScript.Phase.COMPLETE:
		push_error("Expected complete phase after winning")
		return 1
	if state.winner != player:
		push_error("Expected winner to be recorded")
		return 1
	player.free()
	return 0


func _test_win_out_of_range_fails() -> int:
	var state := StateScript.new()
	var player := Node.new()
	if state.try_win(player, Vector3(10, 0, 0), Vector3.ZERO, 4.0):
		push_error("Expected out-of-range win attempt to fail")
		return 1
	if state.phase != StateScript.Phase.ACTIVE:
		push_error("Expected phase to remain active after a failed win attempt")
		return 1
	player.free()
	return 0


func _test_second_win_after_complete_fails() -> int:
	var state := StateScript.new()
	var first := Node.new()
	var second := Node.new()
	state.try_win(first, Vector3.ZERO, Vector3.ZERO, 4.0)
	if state.try_win(second, Vector3.ZERO, Vector3.ZERO, 4.0):
		push_error("Expected a second win attempt after completion to fail")
		return 1
	if state.winner != first:
		push_error("Expected the first winner to remain recorded")
		return 1
	first.free()
	second.free()
	return 0
