class_name CombatHealth
extends Node

## Authored HP pool. Parent characters call take_damage; this node owns current/max.

signal damaged(amount: float, from: Variant)
signal died(from: Variant)

const DEFAULT_MAX_HEALTH := 100.0

@export_range(1.0, 1000.0, 1.0) var max_health: float = DEFAULT_MAX_HEALTH:
	set(value):
		max_health = maxf(value, 1.0)
		if current_health > max_health:
			current_health = max_health

var current_health: float = DEFAULT_MAX_HEALTH


func _ready() -> void:
	current_health = max_health


func is_dead() -> bool:
	return current_health <= 0.0


func ratio() -> float:
	if max_health <= 0.001:
		return 0.0
	return clampf(current_health / max_health, 0.0, 1.0)


func take_damage(amount: float, from: Variant = null) -> void:
	if is_dead():
		return
	var hit := maxf(amount, 0.0)
	if hit <= 0.0:
		return
	current_health = maxf(0.0, current_health - hit)
	damaged.emit(hit, from)
	if is_dead():
		died.emit(from)


static func apply_hit(body: Node, amount: float, from: Variant = null) -> void:
	if body == null or not is_instance_valid(body):
		return
	if body.has_method("is_multiplayer_authority"):
		var tree := body.get_tree()
		var state := tree.root.get_node_or_null("GameState") if tree != null else null
		var mp := state != null and bool(state.get("is_multiplayer"))
		if mp and not body.is_multiplayer_authority():
			return
	var health := body.get_node_or_null("Health") as CombatHealth
	if health != null:
		health.take_damage(amount, from)
		if health.is_dead() and "is_alive" in body:
			body.set("is_alive", false)
		return
	if body.has_method("take_damage"):
		body.call("take_damage", amount, from)


func heal(amount: float) -> void:
	if is_dead():
		return
	current_health = clampf(current_health + maxf(amount, 0.0), 0.0, max_health)
