class_name SpellWardBlock
extends RefCounted

## Shared ward hit resolution for player and monster projectiles.


static func ward_from_node(node: Node) -> Node:
	var walk: Node = node
	while walk != null:
		if walk.is_in_group("spell_ward") and walk.has_method("notify_spell_blocked"):
			return walk
		walk = walk.get_parent()
	return null


## If `body` belongs to a live ward, spend it and return true.
## Pass `ignore_caster` so a monster/player cannot pop their own shield.
static func try_block(
	body: Node, blocked_damage: float = 0.0, ignore_caster: Node = null
) -> bool:
	var ward := ward_from_node(body)
	if ward == null:
		return false
	if ignore_caster != null and ward.has_method("is_owned_by"):
		if bool(ward.call("is_owned_by", ignore_caster)):
			return false
	ward.call("notify_spell_blocked", blocked_damage)
	return true
