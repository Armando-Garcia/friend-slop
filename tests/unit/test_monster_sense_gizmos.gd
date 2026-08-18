extends RefCounted

const MonsterSenseGizmosScript := preload("res://scripts/monsters/monster_sense_gizmos.gd")
const MonsterSightSenseScript := preload("res://scripts/monsters/monster_sight_sense.gd")
const MonsterRangeGizmosScript := preload("res://scripts/monsters/monster_range_gizmos.gd")


func run() -> int:
	var failures := 0
	failures += _test_cone_half_angle()
	failures += _test_cone_rim_faces_forward()
	failures += _test_cone_mesh_has_fan()
	failures += _test_segment_aligns_with_delta()
	failures += _test_los_colors()
	failures += _test_debug_aabb_is_small()
	failures += _test_cone_outline_keeps_full_range()
	failures += _test_clipped_fill_is_shorter_than_range()
	return failures


func _test_cone_half_angle() -> int:
	var half := MonsterSightSenseScript.cone_half_angle(1.0, 2.0)
	if not is_equal_approx(half, PI * 0.25):
		push_error("Expected half-angle atan(1) = PI/4, got %s" % half)
		return 1
	var charger := MonsterSightSenseScript.cone_half_angle(24.0, 22.0)
	if charger <= 0.0 or charger >= PI * 0.5:
		push_error("Expected charger cone half-angle in (0, 90deg), got %s" % charger)
		return 1
	return 0


func _test_cone_rim_faces_forward() -> int:
	var half := PI * 0.25
	var mid: Vector3 = MonsterSenseGizmosScript.cone_rim_point(4.0, half, 0.5)
	if mid.distance_to(Vector3(0.0, 0.0, -4.0)) > 0.02:
		push_error("Expected cone midline on -Z, got %s" % mid)
		return 1
	var left: Vector3 = MonsterSenseGizmosScript.cone_rim_point(4.0, half, 0.0)
	if left.x >= 0.0 or left.z >= 0.0:
		push_error("Expected left rim in -X / -Z, got %s" % left)
		return 1
	var right: Vector3 = MonsterSenseGizmosScript.cone_rim_point(4.0, half, 1.0)
	if right.x <= 0.0 or right.z >= 0.0:
		push_error("Expected right rim in +X / -Z, got %s" % right)
		return 1
	return 0


func _test_cone_mesh_has_fan() -> int:
	var mesh: ArrayMesh = MonsterSenseGizmosScript.build_vision_cone_mesh(8.0, PI * 0.2)
	if mesh == null or mesh.get_surface_count() < 1:
		push_error("Expected vision cone mesh surface")
		return 1
	var faces: PackedVector3Array = mesh.get_faces()
	## 24 segments × 1 triangle × 3 verts.
	if faces.size() < 72:
		push_error("Expected cone fan triangles, got %s face verts" % faces.size())
		return 1
	var far_hits := 0
	for vertex in faces:
		if vertex.z > 0.05:
			push_error("Cone vertex leaked behind the monster: %s" % vertex)
			return 1
		if vertex.length() > 7.5:
			far_hits += 1
	if far_hits < 24:
		push_error("Expected rim verts near sight_range, got %s" % far_hits)
		return 1
	return 0


func _test_segment_aligns_with_delta() -> int:
	var xf: Transform3D = MonsterSenseGizmosScript.segment_transform(
		Vector3(0.0, 0.5, 0.0), Vector3(0.0, 0.5, -6.0)
	)
	if xf.basis.y.dot(Vector3(0.0, 0.0, -1.0)) < 0.99:
		push_error("Expected LOS cylinder Y along -Z, got %s" % xf.basis.y)
		return 1
	if xf.origin.distance_to(Vector3(0.0, 0.5, -3.0)) > 0.01:
		push_error("Expected segment midpoint, got %s" % xf.origin)
		return 1
	return 0


func _test_los_colors() -> int:
	var clear_c: Color = MonsterSenseGizmosScript.los_line_color(
		MonsterSenseGizmosScript.LosKind.CLEAR
	)
	var blocked_c: Color = MonsterSenseGizmosScript.los_line_color(
		MonsterSenseGizmosScript.LosKind.BLOCKED
	)
	if clear_c.g <= clear_c.r:
		push_error("Expected clear LOS to read green")
		return 1
	if blocked_c.r <= blocked_c.g:
		push_error("Expected blocked LOS to read red")
		return 1
	return 0


func _test_debug_aabb_is_small() -> int:
	var host := Node3D.new()
	var disc: MeshInstance3D = MonsterRangeGizmosScript.ensure_disc(
		host, null, "Disc", 24.0, Color(1, 1, 1, 0.2), 0.02, false
	)
	var aabb_len := 0.0
	if disc != null:
		aabb_len = disc.custom_aabb.size.length()
	host.free()
	if aabb_len > 2.0:
		push_error("Expected a small editor AABB, got %s" % aabb_len)
		return 1
	return 0


func _test_cone_outline_keeps_full_range() -> int:
	var mesh: ArrayMesh = MonsterSenseGizmosScript.build_cone_outline_mesh(10.0, PI * 0.25)
	if mesh == null or mesh.get_surface_count() < 1:
		push_error("Expected cone outline surface")
		return 1
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var far_hits := 0
	for vertex in verts:
		if vertex.length() > 9.5:
			far_hits += 1
	if far_hits < 2:
		push_error("Expected outline to keep the full sight range, got %s far verts" % far_hits)
		return 1
	return 0


func _test_clipped_fill_is_shorter_than_range() -> int:
	var dirs := PackedVector3Array()
	var radii := PackedFloat32Array()
	dirs.append(Vector3(0.0, 0.0, -1.0))
	dirs.append(Vector3(0.2, 0.0, -1.0).normalized())
	dirs.append(Vector3(-0.2, 0.0, -1.0).normalized())
	radii.append(3.0)
	radii.append(3.0)
	radii.append(3.0)
	var mesh: ArrayMesh = MonsterSenseGizmosScript.build_clipped_fan_mesh(dirs, radii)
	if mesh == null or mesh.get_surface_count() < 1:
		push_error("Expected clipped sight fill surface")
		return 1
	var faces: PackedVector3Array = mesh.get_faces()
	for vertex in faces:
		if vertex.length() > 3.2:
			push_error("Expected clipped fill to stay inside occlude radii, got %s" % vertex)
			return 1
	return 0
