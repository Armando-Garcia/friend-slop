extends RefCounted

const SpellWardBlockScript := preload("res://scripts/spells/spell_ward_block.gd")


func run() -> int:
	var failures := 0
	failures += _test_live_node_null()
	failures += _test_try_block_with_freed_caster()
	return failures


func _test_live_node_null() -> int:
	if SpellWardBlockScript.live_node(null) != null:
		push_error("Expected live_node(null) to be null")
		return 1
	return 0


func _test_try_block_with_freed_caster() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("Expected a SceneTree for freed-caster ward block")
		return 1
	var body := Node3D.new()
	var caster := Node3D.new()
	tree.root.add_child(body)
	tree.root.add_child(caster)
	caster.free()
	var blocked := SpellWardBlockScript.try_block(body, 0.0, caster)
	body.queue_free()
	if blocked:
		push_error("Expected try_block on a non-ward body to return false")
		return 1
	return 0
