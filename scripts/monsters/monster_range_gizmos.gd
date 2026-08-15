class_name MonsterRangeGizmos
extends RefCounted

## Editor combat-range disc helpers for Monster.


static func refresh(
	host: Node3D,
	show: bool,
	chase_mesh: MeshInstance3D,
	attack_mesh: MeshInstance3D,
	chase_range: float,
	attack_range: float,
	disc_height: float
) -> Dictionary:
	## Returns {chase, attack} mesh refs after refresh.
	if not show:
		free_gizmo(chase_mesh)
		free_gizmo(attack_mesh)
		return {"chase": null, "attack": null}
	return {
		"chase": ensure_disc(
			host, chase_mesh, "ChaseRangeGizmo", chase_range, Color(1.0, 0.35, 0.2, 0.22), disc_height
		),
		"attack": ensure_disc(
			host,
			attack_mesh,
			"AttackRangeGizmo",
			attack_range,
			Color(1.0, 0.85, 0.2, 0.28),
			disc_height
		),
	}


static func ensure_disc(
	host: Node3D,
	existing: MeshInstance3D,
	node_name: String,
	radius: float,
	color: Color,
	disc_height: float
) -> MeshInstance3D:
	var mesh_inst := existing
	if mesh_inst == null or not is_instance_valid(mesh_inst):
		mesh_inst = MeshInstance3D.new()
		mesh_inst.name = node_name
		host.add_child(mesh_inst)
		if Engine.is_editor_hint() and host.get_tree() != null:
			var edited := host.get_tree().edited_scene_root
			if edited != null:
				mesh_inst.owner = edited
	var cyl := CylinderMesh.new()
	cyl.top_radius = maxf(0.05, radius)
	cyl.bottom_radius = cyl.top_radius
	cyl.height = disc_height
	cyl.radial_segments = 48
	mesh_inst.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_inst.position = Vector3(0.0, disc_height * 0.5, 0.0)
	return mesh_inst


static func free_gizmo(mesh_inst: MeshInstance3D) -> void:
	if mesh_inst != null and is_instance_valid(mesh_inst):
		mesh_inst.queue_free()
