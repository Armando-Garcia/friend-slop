class_name WardSlotChannel
extends RefCounted

## Player-slot ward: dome rides the camera; a cylinder runs from the wand tip.

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
	var host := _follow_host(player)
	var parent: Node = host
	if parent == null:
		parent = SpellEphemeralFxScript.resolve_parent(player)
	if parent == null:
		return
	var packed: PackedScene = load(SpellDefinition.world_scene_path("ward")) as PackedScene
	if packed == null:
		return
	var ward: Node = packed.instantiate()
	parent.add_child(ward)
	if ward.has_method("set_caster"):
		ward.call("set_caster", player)
	var origin := Vector3.ZERO
	var direction := Vector3(0.0, 0.0, -1.0)
	if player.has_method("get_view_origin"):
		origin = player.call("get_view_origin") as Vector3
	if player.has_method("get_view_direction"):
		direction = player.call("get_view_direction") as Vector3
	if ward.has_method("start_wand_follow"):
		ward.call("start_wand_follow", origin, direction, 1, host)
	_ward = ward


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


func _follow_host(player: Node3D) -> Node3D:
	if player.has_method("get_view_camera"):
		var cam: Camera3D = player.call("get_view_camera") as Camera3D
		if cam != null:
			return cam
	if "camera_pivot" in player:
		return player.get("camera_pivot") as Node3D
	return null
