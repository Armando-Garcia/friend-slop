class_name MonsterSightSense
extends MonsterSense

## Proximity + optional LOS player detection under Monster/Senses.

const MonsterInterestScript := preload("res://scripts/monsters/monster_interest.gd")

@export var sight_range: float = 10.0
@export var require_line_of_sight: bool = true
@export var eye_height: float = 0.55
@export var sight_urgency: float = 1.4


func append_interest_candidates(monster: CharacterBody3D, out: Array) -> void:
	if not enabled or monster == null:
		return
	var tree := monster.get_tree()
	if tree == null:
		return
	var origin := monster.global_position
	for node in tree.get_nodes_in_group("player"):
		if not (node is Node3D):
			continue
		var player := node as Node3D
		var alive_value = player.get("is_alive")
		if alive_value != null and not bool(alive_value):
			continue
		var flat := Vector3(
			player.global_position.x - origin.x,
			0.0,
			player.global_position.z - origin.z
		)
		var dist := flat.length()
		if dist > sight_range:
			continue
		if require_line_of_sight and not _has_line_of_sight(monster, player):
			continue
		var urgency := sight_urgency * (1.0 - (dist / maxf(sight_range, 0.01)) * 0.35)
		out.append(MonsterInterestScript.from_target(player, urgency, &"sight"))


func _has_line_of_sight(monster: CharacterBody3D, target: Node3D) -> bool:
	var world := monster.get_world_3d()
	if world == null or world.direct_space_state == null:
		return true
	var from := monster.global_position + Vector3(0.0, eye_height, 0.0)
	var to := target.global_position + Vector3(0.0, eye_height, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [monster.get_rid()]
	if target is CollisionObject3D:
		query.exclude.append((target as CollisionObject3D).get_rid())
	var hit := world.direct_space_state.intersect_ray(query)
	return hit.is_empty()
