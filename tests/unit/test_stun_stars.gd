extends RefCounted

const StunStarMeshScript := preload("res://scripts/fx/stun_star_mesh.gd")


func run() -> int:
	var failures := 0
	failures += _test_star_mesh_has_five_points()
	failures += _test_baked_star_mesh()
	return failures


func _test_star_mesh_has_five_points() -> int:
	var mesh := StunStarMeshScript.build(0.07)
	if mesh == null or mesh.get_surface_count() < 1:
		push_error("Expected stun star mesh to have a surface")
		return 1
	var faces := mesh.get_faces()
	## 10 triangles (5 tips × 2) × 3 verts. Inner radius is below 0.06.
	if faces.size() < 30:
		push_error("Expected a 5-point star (10 triangles), got %s face verts" % faces.size())
		return 1
	var outer_hits := 0
	for v in faces:
		if v.length() > 0.06:
			outer_hits += 1
	if outer_hits < 10:
		push_error("Expected outer star tips, got %s far vertices" % outer_hits)
		return 1
	return 0


func _test_baked_star_mesh() -> int:
	var mesh := load("res://assets/fx/stun_star.res") as ArrayMesh
	if mesh == null or mesh.get_surface_count() < 1:
		push_error("Expected baked stun_star.res")
		return 1
	var faces := mesh.get_faces()
	if faces.size() < 30:
		push_error("Expected baked 5-point star, got %s face verts" % faces.size())
		return 1
	var outer_hits := 0
	for v in faces:
		if v.length() > 0.9:
			outer_hits += 1
	if outer_hits < 10:
		push_error("Expected unit-radius baked tips, got %s far vertices" % outer_hits)
		return 1
	return 0
