class_name PlayerFrostBreath
extends RefCounted

## Frost breath knockback, slow, and mana drain on armed spell.

const AshFrostBreathFlightScript := preload(
	"res://scripts/monsters/abilities/ash_frost_breath_flight.gd"
)


static func apply(player: Node, hit_dir: Vector3) -> void:
	if player == null:
		return
	if player.has_method("is_multiplayer_authority"):
		var tree := player.get_tree()
		var state := tree.root.get_node_or_null("GameState") if tree != null else null
		var mp := state != null and bool(state.get("is_multiplayer"))
		if mp and not player.is_multiplayer_authority():
			return
	var flat := Vector3(hit_dir.x, 0.0, hit_dir.z)
	if flat.length_squared() < 0.0001 and player is Node3D:
		flat = -(player as Node3D).global_transform.basis.z
		flat.y = 0.0
	if flat.length_squared() > 0.0001:
		flat = flat.normalized()
		var impulse := (
			flat * AshFrostBreathFlightScript.KNOCKBACK_SPEED
			+ Vector3.UP * AshFrostBreathFlightScript.KNOCKBACK_LIFT
		)
		if "velocity" in player:
			player.velocity += impulse
		if "_knockback_vel" in player:
			player.set("_knockback_vel", impulse)
		if "_knockback_timer" in player:
			player.set("_knockback_timer", 0.35)
	if player.has_method("apply_speed_boost"):
		player.call(
			"apply_speed_boost",
			AshFrostBreathFlightScript.SLOW_DURATION_SEC,
			AshFrostBreathFlightScript.SLOW_MULTIPLIER
		)
	_drain_mana_if_armed(player, AshFrostBreathFlightScript.MANA_DRAIN)


static func _drain_mana_if_armed(player: Node, amount: float) -> void:
	if amount <= 0.0 or "_armed_spell" not in player:
		return
	var armed = player.get("_armed_spell")
	if armed == null:
		return
	if player.has_method("_spend_mana"):
		player.call("_spend_mana", amount)
