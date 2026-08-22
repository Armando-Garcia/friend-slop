extends RefCounted

const MonsterSpellHitScript := preload("res://scripts/combat/monster_spell_hit.gd")
const SlideSurfaceScript := preload("res://scripts/slide_surface.gd")


func run() -> int:
	var failures := 0
	failures += _test_combat_and_wall_kinds()
	failures += _test_freed_caster_is_ignored()
	failures += _test_mask_value()
	return failures


func _test_combat_and_wall_kinds() -> int:
	var player := Node3D.new()
	player.add_to_group("player")
	var monster := Node3D.new()
	monster.add_to_group("monster")
	var wall := StaticBody3D.new()
	wall.name = "NorthWall"
	SlideSurfaceScript.tag(wall)
	var floor := StaticBody3D.new()
	floor.name = "Floor"
	var caster := Node3D.new()
	if MonsterSpellHitScript.kind(player, caster) != MonsterSpellHitScript.Kind.COMBAT:
		push_error("Expected player overlap to count as combat")
		return 1
	if MonsterSpellHitScript.kind(monster, caster) != MonsterSpellHitScript.Kind.COMBAT:
		push_error("Expected NPC overlap to count as combat")
		return 1
	if MonsterSpellHitScript.kind(wall, caster) != MonsterSpellHitScript.Kind.WALL:
		push_error("Expected maze wall overlap to count as a wall")
		return 1
	if MonsterSpellHitScript.kind(floor, caster) != MonsterSpellHitScript.Kind.IGNORE:
		push_error("Expected floor overlap not to stop a projectile")
		return 1
	if MonsterSpellHitScript.kind(caster, caster) != MonsterSpellHitScript.Kind.IGNORE:
		push_error("Expected caster overlap to be ignored")
		return 1
	player.free()
	monster.free()
	wall.free()
	floor.free()
	caster.free()
	return 0


func _test_freed_caster_is_ignored() -> int:
	## Projectiles often outlive the casting monster; kind() must not hard-error.
	var player := Node3D.new()
	player.add_to_group("player")
	var caster := Node3D.new()
	caster.free()
	if MonsterSpellHitScript.kind(player, caster) != MonsterSpellHitScript.Kind.COMBAT:
		push_error("Expected freed caster to be treated as null")
		player.free()
		return 1
	player.free()
	return 0


func _test_mask_value() -> int:
	if MonsterSpellHitScript.COLLISION_MASK != (1 | 2):
		push_error("Expected monster spells to scan world + combat layers")
		return 1
	return 0
