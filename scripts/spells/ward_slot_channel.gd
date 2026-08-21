class_name WardSlotChannel
extends RefCounted

## Player-slot ward: follow the wand while held, plant on release.

const SpellEphemeralFxScript := preload("res://scripts/spells/spell_ephemeral_fx.gd")

var _ward: Node


func consume() -> Node:
	var ward := _ward
	_ward = null
	if ward != null and is_instance_valid(ward):
		return ward
	return null


func begin(player: Node3D) -> void:
	drop()
	if player == null:
		return
	var parent := SpellEphemeralFxScript.resolve_parent(player)
	if parent == null:
		return
	var origin := Vector3.ZERO
	var direction := Vector3.FORWARD
	if player.has_method("get_wand_cast_origin"):
		origin = player.call("get_wand_cast_origin") as Vector3
	if player.has_method("get_wand_cast_direction"):
		direction = player.call("get_wand_cast_direction") as Vector3
	var packed: PackedScene = load(SpellDefinition.world_scene_path("ward")) as PackedScene
	if packed == null:
		return
	var ward: Node = packed.instantiate()
	if ward is Node3D:
		SpellEphemeralFxScript.add_child_at(parent, ward as Node3D, origin)
	else:
		parent.add_child(ward)
	if ward.has_method("set_caster"):
		ward.call("set_caster", player)
	if ward.has_method("start_wand_follow"):
		ward.call("start_wand_follow", origin, direction, 1)
	_ward = ward


func tick(player: Node3D) -> void:
	if _ward == null or not is_instance_valid(_ward):
		_ward = null
		return
	if player == null or not _ward.has_method("follow_wand"):
		return
	var origin := player.call("get_wand_cast_origin") as Vector3
	var direction := player.call("get_wand_cast_direction") as Vector3
	_ward.call("follow_wand", origin, direction)


func plant() -> void:
	if _ward == null or not is_instance_valid(_ward):
		_ward = null
		return
	if _ward.has_method("plant"):
		_ward.call("plant")


func drop() -> void:
	if _ward == null:
		return
	var ward := _ward
	_ward = null
	if not is_instance_valid(ward):
		return
	var following := (
		bool(ward.call("is_channel_following"))
		if ward.has_method("is_channel_following")
		else true
	)
	if not following:
		return
	if ward.has_method("shatter"):
		ward.call("shatter")
	else:
		ward.queue_free()
