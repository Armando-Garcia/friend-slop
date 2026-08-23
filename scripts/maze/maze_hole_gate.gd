class_name MazeHoleGate
extends Area3D

## Low tunnel mouth — standing players are pushed back; crouching players and gnomes pass.

const PlayerCrouchScript := preload("res://scripts/characters/player_crouch.gd")

const PUSH_BACK := 2.5


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	collision_layer = 0
	collision_mask = 1


func _on_body_entered(body: Node3D) -> void:
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("gnome"):
		return
	if body is CharacterBody3D and PlayerCrouchScript.is_crouching(body as CharacterBody3D):
		return
	if not (body.is_in_group("player") or body is CharacterBody3D):
		return
	_push_back(body as CharacterBody3D)


func _push_back(body: CharacterBody3D) -> void:
	if body == null:
		return
	var away := body.global_position - global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3.FORWARD
	away = away.normalized()
	body.velocity.x = away.x * PUSH_BACK
	body.velocity.z = away.z * PUSH_BACK
