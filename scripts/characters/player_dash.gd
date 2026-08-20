class_name PlayerDash
extends RefCounted

## Foot dash for PlayableCharacter (Headmaster + Apprentice).
## Tunables live on PlayableCharacter; defaults below are fallbacks for tests.

const SlideSurfaceScript := preload("res://scripts/slide_surface.gd")
const PlayerCrouchScript := preload("res://scripts/characters/player_crouch.gd")

const DEFAULT_DISTANCE := 3.0
const DEFAULT_DURATION := 0.15
const DEFAULT_COOLDOWN_SEC := 3.0
const DEFAULT_SPEED := 20.0
const META_ACTIVE_UNTIL := "_dash_active_until_msec"
const META_COOLDOWN := "_dash_cooldown_sec"


static func dash_speed(config: Dictionary = {}) -> float:
	return maxf(float(config.get("speed", DEFAULT_SPEED)), 0.0)


static func dash_duration(config: Dictionary = {}) -> float:
	return maxf(float(config.get("duration", DEFAULT_DURATION)), 0.05)


static func dash_cooldown(config: Dictionary = {}) -> float:
	return maxf(float(config.get("cooldown_sec", DEFAULT_COOLDOWN_SEC)), 0.0)


static func config_from(player: CharacterBody3D) -> Dictionary:
	return {
		"distance": _export_float(player, "dash_distance", DEFAULT_DISTANCE),
		"duration": _export_float(player, "dash_duration", DEFAULT_DURATION),
		"cooldown_sec": _export_float(player, "dash_cooldown_sec", DEFAULT_COOLDOWN_SEC),
		"speed": _export_float(player, "dash_speed", DEFAULT_SPEED),
	}


static func _export_float(player: Object, property: StringName, default: float) -> float:
	if player is PlayableCharacter:
		return float(player.get(property))
	var value: Variant = player.get(property)
	if value == null:
		return default
	return float(value)


static func is_active(player: CharacterBody3D) -> bool:
	return Time.get_ticks_msec() < int(player.get_meta(META_ACTIVE_UNTIL, 0))


static func tick_and_try(
	player: CharacterBody3D, head: Node3D, delta: float, config: Dictionary = {}
) -> void:
	if config.is_empty():
		config = config_from(player)
	_tick_cooldown(player, delta)
	if is_active(player):
		return
	_try_dash(player, head, config)


static func _tick_cooldown(player: CharacterBody3D, delta: float) -> void:
	var cooldown := float(player.get_meta(META_COOLDOWN, 0.0))
	if cooldown <= 0.0:
		return
	player.set_meta(META_COOLDOWN, maxf(0.0, cooldown - delta))


static func _try_dash(player: CharacterBody3D, head: Node3D, config: Dictionary) -> void:
	if float(player.get_meta(META_COOLDOWN, 0.0)) > 0.0:
		return
	if not Input.is_action_just_pressed("dash"):
		return
	var direction := SlideSurfaceScript.camera_relative_move_direction(head)
	if direction == Vector3.ZERO:
		return
	var speed := dash_speed(config)
	var duration := dash_duration(config)
	player.velocity.x = direction.x * speed
	player.velocity.z = direction.z * speed
	player.set_meta(
		META_ACTIVE_UNTIL, Time.get_ticks_msec() + int(round(duration * 1000.0))
	)
	player.set_meta(META_COOLDOWN, dash_cooldown(config))
	var grace := _export_float(player, "crouch_slide_dash_grace_sec", 0.6)
	PlayerCrouchScript.mark_dash_slide_grace(player, duration, grace)
