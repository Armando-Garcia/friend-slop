class_name Headmaster
extends PlayableCharacter

## Maze Headmaster — larger silhouette with shared playable wand / broom.
## Starts with broom in slot 1 and summoning book in slot 2.

const HEADMASTER_BODY_SCALE := 1.18


func _ready() -> void:
	scale = Vector3.ONE * HEADMASTER_BODY_SCALE
	super._ready()


func _apply_character_color(color: Color) -> void:
	var headmaster_tint := Color(
		color.r * 0.35 + 0.08,
		color.g * 0.2 + 0.04,
		color.b * 0.45 + 0.12
	)
	super._apply_character_color(headmaster_tint)
	var body_mat := _authored_material(_body_mesh)
	if body_mat != null:
		body_mat.roughness = 0.85
		body_mat.metallic = 0.12
