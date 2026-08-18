class_name SpellWardBlock
extends RefCounted

## Shared ward hit resolution for player and monster projectiles.


static func live_node(node: Variant) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	if not (node is Node):
		return null
	return node as Node


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
	body: Node, blocked_damage: float = 0.0, ignore_caster: Variant = null
) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	var caster := live_node(ignore_caster)
	var ward := ward_from_node(body)
	if ward == null:
		return false
	if caster != null and ward.has_method("is_owned_by"):
		if bool(ward.call("is_owned_by", caster)):
			return false
	ward.call("notify_spell_blocked", blocked_damage, caster)
	notify_caster_warded(caster, ward)
	return true


## Tell the attacking caster a live ward ate their spell.
static func notify_caster_warded(caster: Variant = null, blocked_by: Node = null) -> void:
	var live := live_node(caster)
	if live == null:
		return
	if live.has_method("on_spell_ward_blocked"):
		live.call("on_spell_ward_blocked", blocked_by)
