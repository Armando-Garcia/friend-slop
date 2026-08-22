extends RefCounted

const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")
const MonsterInterestScript := preload("res://scripts/monsters/monster_interest.gd")


func run() -> int:
	var failures := 0
	failures += _test_live_node3d_on_freed()
	failures += _test_live_target_clears_freed()
	return failures


func _test_live_node3d_on_freed() -> int:
	var player := Node3D.new()
	if MonsterAIScript.live_node3d(player) != player:
		push_error("Expected live_node3d to return the live node")
		player.free()
		return 1
	player.free()
	if MonsterAIScript.live_node3d(player) != null:
		push_error("Expected live_node3d(freed) to return null")
		return 1
	if MonsterAIScript.live_node3d(null) != null:
		push_error("Expected live_node3d(null) to return null")
		return 1
	return 0


func _test_live_target_clears_freed() -> int:
	## get_chase_target() is the supported monster-facing API; interests clear stale refs.
	var player := Node3D.new()
	player.add_to_group("player")
	var interest := MonsterInterestScript.from_target(player, 2.0, &"sight")
	if interest.get_live_target() != player:
		push_error("Expected live target before free")
		player.free()
		return 1
	player.free()
	## Must not hard-error on a freed interest target.
	if interest.get_live_target() != null:
		push_error("Expected freed target to resolve as null")
		return 1
	if interest.target != null:
		push_error("Expected get_live_target to clear stale target field")
		return 1
	if interest.is_actionable():
		push_error("Expected interest with only a freed target to be inactive")
		return 1
	return 0
