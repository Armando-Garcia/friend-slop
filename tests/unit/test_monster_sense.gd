extends RefCounted

const MonsterSenseScript := preload("res://scripts/monsters/monster_sense.gd")
const MonsterSightSenseScript := preload("res://scripts/monsters/monster_sight_sense.gd")
const MonsterHearingSenseScript := preload("res://scripts/monsters/monster_hearing_sense.gd")
const MonsterLightSenseScript := preload("res://scripts/monsters/monster_light_awareness_sense.gd")


func run() -> int:
	var failures := 0
	failures += _test_sense_scripts_are_tool()
	failures += _test_can_append_from()
	failures += _test_sight_appends_in_range_player()
	return failures


func _test_sense_scripts_are_tool() -> int:
	## Lookdev live AI calls append_interest_candidates in the editor.
	var scripts: Array[Script] = [
		MonsterSenseScript,
		MonsterSightSenseScript,
		MonsterHearingSenseScript,
		MonsterLightSenseScript,
	]
	for scr in scripts:
		if not scr.is_tool():
			push_error("%s must be @tool for lookdev live AI" % scr.resource_path)
			return 1
	return 0


func _test_can_append_from() -> int:
	var dummy := Node.new()
	if MonsterSenseScript.can_append_from(dummy):
		push_error("Bare Node must not count as a sense")
		dummy.free()
		return 1
	dummy.free()
	var sight: Node = MonsterSightSenseScript.new()
	if not MonsterSenseScript.can_append_from(sight):
		push_error("MonsterSightSense should be callable")
		sight.free()
		return 1
	sight.free()
	if MonsterSenseScript.can_append_from(null):
		push_error("null must not count as a sense")
		return 1
	return 0


func _test_sight_appends_in_range_player() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		push_error("Expected SceneTree for sight sense test")
		return 1
	var holder := Node3D.new()
	tree.root.add_child(holder)
	var monster := CharacterBody3D.new()
	holder.add_child(monster)
	monster.global_position = Vector3.ZERO
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	holder.add_child(player)
	player.global_position = Vector3(0.0, 0.0, -2.0)
	var sight: Node = MonsterSightSenseScript.new()
	sight.set("require_line_of_sight", false)
	sight.set("use_vision_cone", false)
	sight.set("sight_range", 10.0)
	monster.add_child(sight)
	var out: Array = []
	sight.call("append_interest_candidates", monster, out)
	holder.free()
	if out.is_empty():
		push_error("Expected sight to append an in-range player")
		return 1
	return 0
