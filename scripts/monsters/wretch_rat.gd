class_name WretchRat
extends "res://scripts/monsters/summon_monster.gd"

## Small sphere minion for the Wretch. Sight-only aggro; dies with host / fireball.


func _append_default_interest_candidates(_out: Array) -> void:
	## Rats use authored Sight sense only (no wide proximity aggro).
	pass


func apply_fireball_knockback(fireball_dir: Vector3) -> void:
	## Any fireball contact kills the rat.
	if not is_alive or _dying:
		return
	if fireball_dir.length_squared() > 0.0001:
		_last_hit_dir = fireball_dir.normalized()
	die()
