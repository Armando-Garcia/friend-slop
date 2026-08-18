extends RefCounted

const MonsterComboTriggersScript := preload("res://scripts/monsters/monster_combo_triggers.gd")


func run() -> int:
	var failures := 0
	failures += _test_resolve_caster_on_node()
	return failures


func _test_resolve_caster_on_node() -> int:
	var projectile := Node3D.new()
	projectile.name = "Projectile"
	var player := Node3D.new()
	player.name = "Player"
	player.add_to_group("player")
	projectile.set("_caster", player)
	var resolved := MonsterComboTriggersScript.resolve_attacking_player(projectile, null)
	if resolved != player:
		push_error("Expected resolve_attacking_player to follow projectile _caster")
		return 1
	projectile.queue_free()
	player.queue_free()
	return 0
