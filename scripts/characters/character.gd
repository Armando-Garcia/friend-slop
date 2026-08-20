class_name Character
extends CharacterBody3D

## 3D character shell: body/head meshes, collision, and tint.
## Inherited by PlayableCharacter (Apprentice / Headmaster) and Monster.
## CollisionShape3D is authored per character scene (Apprentice / Headmaster) — not rebuilt here.
## Appearance: mutate authored scene materials. Never allocate meshes or materials.

var _character_color: Color = Color.WHITE

@onready var head: Node3D = %Head
@onready var _body_mesh: MeshInstance3D = %Body
@onready var _head_mesh: MeshInstance3D = %HeadMesh


func _apply_character_color(color: Color) -> void:
	# Lit materials (no constant emission) so moonlight / world lights shade the mesh.
	if _body_mesh == null or _head_mesh == null:
		return
	var body_mat := _authored_material(_body_mesh)
	if body_mat != null:
		body_mat.albedo_color = color
	var head_mat := _authored_material(_head_mesh)
	if head_mat != null:
		head_mat.albedo_color = color.lightened(0.08)


func _authored_material(mesh_inst: MeshInstance3D) -> StandardMaterial3D:
	if mesh_inst == null:
		return null
	if mesh_inst.material_override is StandardMaterial3D:
		return mesh_inst.material_override as StandardMaterial3D
	var override_mat := mesh_inst.get_surface_override_material(0)
	if override_mat is StandardMaterial3D:
		return override_mat as StandardMaterial3D
	if mesh_inst.mesh != null and mesh_inst.mesh.get_surface_count() > 0:
		var surf := mesh_inst.mesh.surface_get_material(0)
		if surf is StandardMaterial3D:
			return surf as StandardMaterial3D
	return null


func get_snail_color() -> Color:
	return _character_color
