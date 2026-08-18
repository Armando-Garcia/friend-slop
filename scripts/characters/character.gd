@tool
class_name Character
extends CharacterBody3D

## 3D character shell: body/head meshes, collision, and tint.
## Inherited by PlayableCharacter (Apprentice / Headmaster) and Monster.
## CollisionShape3D is authored per character scene (Apprentice / Headmaster) — not rebuilt here.

## Body/head render layer — wand lights use a world-only mask and skip this layer.
const PLAYER_SELF_VISUAL_LAYER := WorldVisualLayers.PLAYER_SELF

var _character_color: Color = Color.WHITE

@onready var head: Node3D = %Head
@onready var _body_mesh: MeshInstance3D = %Body
@onready var _head_mesh: MeshInstance3D = %HeadMesh
@onready var _body_collision: CollisionShape3D = %CollisionShape3D


func _apply_character_color(color: Color) -> void:
	# Lit materials (no constant emission) so moonlight / world lights shade the mesh.
	# Layer PLAYER_SELF: moon uses SCENE_LIGHT_MASK; wand flashlight stays WORLD-only.
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.albedo_color = color
	material.roughness = 0.62
	material.metallic = 0.05
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	_body_mesh.material_override = material
	_body_mesh.layers = PLAYER_SELF_VISUAL_LAYER
	_body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var head_material := material.duplicate() as StandardMaterial3D
	head_material.albedo_color = color.lightened(0.08)
	_head_mesh.material_override = head_material
	_head_mesh.layers = PLAYER_SELF_VISUAL_LAYER
	_head_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func get_snail_color() -> Color:
	return _character_color
