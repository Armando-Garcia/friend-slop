extends RefCounted

const MazeHoleScript := preload("res://scripts/maze/maze_hole.gd")
const MazeHoleGateScript := preload("res://scripts/maze/maze_hole_gate.gd")
const PlayerCrouchScript := preload("res://scripts/characters/player_crouch.gd")


func run() -> int:
	var failures := 0
	failures += _test_spawn_builds_tunnel_and_gate()
	failures += _test_gate_allows_crouch_and_gnome()
	failures += _test_gate_pushes_standing_player()
	return failures


func _test_spawn_builds_tunnel_and_gate() -> int:
	var root := Node3D.new()
	var hole := MazeHoleScript.spawn(root, Vector3.ZERO)
	if hole.get_node_or_null("WallSplice") == null:
		push_error("MazeHole spawn must create WallSplice root")
		root.free()
		return 1
	if hole.get_node_or_null("WallSplice/Tunnel") == null:
		push_error("MazeHole splice must include tunnel interior")
		root.free()
		return 1
	if hole.get_node_or_null("Gate") == null:
		push_error("MazeHole spawn must create Gate Area3D")
		root.free()
		return 1
	root.free()
	return 0


func _test_gate_allows_crouch_and_gnome() -> int:
	var gate := Area3D.new()
	gate.set_script(MazeHoleGateScript)
	var crouch := CharacterBody3D.new()
	crouch.add_to_group("player")
	crouch.set_meta(PlayerCrouchScript.META_CROUCHING, true)
	gate.call("_on_body_entered", crouch)
	if crouch.velocity.length_squared() > 0.0001:
		push_error("Gate should not push crouching players")
		crouch.free()
		gate.free()
		return 1
	var gnome := CharacterBody3D.new()
	gnome.add_to_group("gnome")
	gnome.velocity = Vector3(1.0, 0.0, 0.0)
	gate.call("_on_body_entered", gnome)
	if gnome.velocity.length_squared() < 0.0001:
		push_error("Gate should not alter gnome velocity")
		gnome.free()
		crouch.free()
		gate.free()
		return 1
	gnome.free()
	crouch.free()
	gate.free()
	return 0


func _test_gate_pushes_standing_player() -> int:
	var gate := Area3D.new()
	gate.global_position = Vector3(0.0, 0.0, 0.0)
	gate.set_script(MazeHoleGateScript)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.global_position = Vector3(0.0, 0.0, 0.5)
	gate.call("_on_body_entered", player)
	if player.velocity.length_squared() < 0.01:
		push_error("Gate should push standing players away from the opening")
		player.free()
		gate.free()
		return 1
	player.free()
	gate.free()
	return 0
