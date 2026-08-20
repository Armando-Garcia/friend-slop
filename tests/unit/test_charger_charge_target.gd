extends RefCounted

const ChargerScript := preload("res://scripts/monsters/charger.gd")
const PlayableScene := preload("res://scenes/characters/playable_character.tscn")
const PlayableScript := preload("res://scripts/characters/playable_character.gd")
const ApprenticeScript := preload("res://scripts/characters/apprentice.gd")
const StunScript := preload("res://scripts/characters/player_stun.gd")


func run() -> int:
	var failures := 0
	failures += _test_dummy_group_player_is_not_charge_target()
	failures += _test_playable_character_is_charge_target()
	failures += _test_dead_playable_is_not_charge_target()
	failures += _test_script_extends_playable()
	failures += _test_resolve_walks_to_playable_parent()
	failures += _test_stun_begins_without_ready()
	failures += _test_stun_hop_applies_gravity_without_moving()
	return failures


func _test_dummy_group_player_is_not_charge_target() -> int:
	var dummy := CharacterBody3D.new()
	dummy.add_to_group("player")
	if ChargerScript.is_playable_charge_target(dummy):
		push_error("Lookdev dummy in player group must not be a charge target")
		dummy.free()
		return 1
	dummy.free()
	return 0


func _test_playable_character_is_charge_target() -> int:
	var player: Node = PlayableScene.instantiate()
	player.add_to_group("player")
	if "is_alive" in player:
		player.set("is_alive", true)
	if not ChargerScript.is_playable_charge_target(player):
		push_error("PlayableCharacter in player group should be a charge target")
		player.free()
		return 1
	player.free()
	return 0


func _test_dead_playable_is_not_charge_target() -> int:
	var player: Node = PlayableScene.instantiate()
	player.add_to_group("player")
	player.set("is_alive", false)
	if ChargerScript.is_playable_charge_target(player):
		push_error("Dead PlayableCharacter must not be a charge target")
		player.free()
		return 1
	player.free()
	return 0


func _test_script_extends_playable() -> int:
	if not ChargerScript.script_extends_playable(PlayableScript):
		push_error("Expected playable_character.gd to count as playable")
		return 1
	if not ChargerScript.script_extends_playable(ApprenticeScript):
		push_error("Expected apprentice.gd to count as playable")
		return 1
	if ChargerScript.script_extends_playable(ChargerScript):
		push_error("Charger script must not count as playable")
		return 1
	return 0


func _test_resolve_walks_to_playable_parent() -> int:
	var player: Node = PlayableScene.instantiate()
	player.add_to_group("player")
	if "is_alive" in player:
		player.set("is_alive", true)
	var prop := Node.new()
	player.add_child(prop)
	var resolved := ChargerScript.resolve_playable_hit_body(prop)
	if resolved != player:
		push_error("Expected ram collider child to resolve to PlayableCharacter")
		player.free()
		return 1
	player.free()
	return 0


func _test_stun_begins_without_ready() -> int:
	var body := CharacterBody3D.new()
	var stun: Node = StunScript.new()
	body.add_child(stun)
	stun.call("begin_charger_hit", Vector3(6.0, 8.0, 0.0), 18.0)
	if not bool(stun.call("is_stunned")):
		push_error("Expected charger hit to stun even before Stun._ready")
		body.free()
		return 1
	if body.velocity.length() < 0.1:
		push_error("Expected launch velocity on the player body")
		body.free()
		return 1
	body.free()
	return 0


func _test_stun_hop_applies_gravity_without_moving() -> int:
	var body := CharacterBody3D.new()
	var stun: Node = StunScript.new()
	body.add_child(stun)
	stun.call("begin_charger_hit", Vector3(6.0, 8.0, 0.0), 18.0)
	var start := body.global_position
	var vy0 := body.velocity.y
	stun.call("tick_physics", body, 1.0 / 60.0, 18.0)
	if body.global_position.distance_to(start) > 0.0001:
		push_error("Stun tick should not move the body; move_and_slide owns that")
		body.free()
		return 1
	if body.velocity.y >= vy0:
		push_error("Expected gravity to reduce launch vy, got %s" % body.velocity.y)
		body.free()
		return 1
	if not bool(stun.call("is_launching")):
		push_error("Expected to still be launching after takeoff")
		body.free()
		return 1
	stun.call("after_slide", body)
	if not bool(stun.call("is_launching")):
		push_error("Min airtime should keep the hop going on the first frame")
		body.free()
		return 1
	body.free()
	return 0
