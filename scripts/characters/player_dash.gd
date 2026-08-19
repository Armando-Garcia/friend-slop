class_name PlayerDash
extends RefCounted

## Foot dash on the sprint action: burst velocity along held move input.

const SlideSurfaceScript := preload("res://scripts/slide_surface.gd")

const DASH_SPEED := 10.0
const DASH_COOLDOWN_SEC := 0.55
const META_COOLDOWN := "_dash_cooldown_sec"


static func tick_and_try(player: CharacterBody3D, head: Node3D, delta: float) -> void:
	_tick_cooldown(player, delta)
	_try_dash(player, head)


static func _tick_cooldown(player: CharacterBody3D, delta: float) -> void:
	var cooldown := float(player.get_meta(META_COOLDOWN, 0.0))
	if cooldown <= 0.0:
		return
	player.set_meta(META_COOLDOWN, maxf(0.0, cooldown - delta))


static func _try_dash(player: CharacterBody3D, head: Node3D) -> void:
	if float(player.get_meta(META_COOLDOWN, 0.0)) > 0.0:
		return
	if not Input.is_action_just_pressed("sprint"):
		return
	var direction := SlideSurfaceScript.camera_relative_move_direction(head)
	if direction == Vector3.ZERO:
		return
	player.velocity.x = direction.x * DASH_SPEED
	player.velocity.z = direction.z * DASH_SPEED
	player.set_meta(META_COOLDOWN, DASH_COOLDOWN_SEC)
