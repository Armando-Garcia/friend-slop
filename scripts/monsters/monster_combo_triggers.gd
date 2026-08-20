class_name MonsterComboTriggers
extends RefCounted

## Shared combo trigger helpers for Ice Caster and Ember Caster.

const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")


static func resolve_attacking_player(from: Node, monster: Node) -> Node3D:
	if from != null and is_instance_valid(from):
		if from.is_in_group("player") and from is Node3D:
			return from as Node3D
		if "_caster" in from:
			var caster: Variant = from.get("_caster")
			if caster is Node3D and is_instance_valid(caster as Node3D):
				var caster_n3 := caster as Node3D
				if caster_n3.is_in_group("player"):
					return caster_n3
		var node: Node = from
		while node != null:
			if node.is_in_group("player") and node is Node3D:
				return node as Node3D
			node = node.get_parent()
	if monster != null and monster.has_method("get_aggro_player_target"):
		var live: Variant = monster.call("get_aggro_player_target")
		if live is Node3D and is_instance_valid(live as Node3D):
			return live as Node3D
	return nearest_player(monster)


static func nearest_player(monster: Node) -> Node3D:
	if monster == null:
		return null
	var tree := monster.get_tree()
	if tree == null:
		return null
	var best: Node3D = null
	var best_dist := INF
	for node in tree.get_nodes_in_group("player"):
		if not node is Node3D or not is_instance_valid(node as Node3D):
			continue
		var n3 := node as Node3D
		var dist := MonsterAIScript.horizontal_distance(
			monster.global_position, n3.global_position
		)
		if dist < best_dist:
			best_dist = dist
			best = n3
	return best


static func is_player_within_range(
	monster: Node, player: Node3D, range_m: float
) -> bool:
	if monster == null or player == null or not is_instance_valid(player):
		return false
	return (
		MonsterAIScript.horizontal_distance(monster.global_position, player.global_position)
		<= range_m
	)
