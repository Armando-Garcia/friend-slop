class_name TestRoundedBoxMesh
extends RefCounted

const RoundedBoxMeshScript := preload("res://scripts/objectives/rounded_box_mesh.gd")


func run() -> int:
	var failures := 0
	failures += _test_build_mesh_produces_geometry()
	failures += _test_build_mesh_handles_zero_radius()
	failures += _test_build_mesh_handles_oversized_radius()
	failures += _test_collision_points_match_box_corners()
	return failures


func _test_build_mesh_produces_geometry() -> int:
	var mesh := RoundedBoxMeshScript.build_mesh(Vector3(1.6, 0.3, 1.15), 0.1)
	if mesh == null or mesh.get_surface_count() == 0:
		push_error("Expected build_mesh to produce at least one surface")
		return 1
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.size() == 0:
		push_error("Expected build_mesh to produce vertices")
		return 1
	return 0


## At radius 0 every fillet/octant collapses away — the walls and bottom
## should degrade to a plain box's bounds.
func _test_build_mesh_handles_zero_radius() -> int:
	var size := Vector3(1.6, 0.3, 1.15)
	var mesh := RoundedBoxMeshScript.build_mesh(size, 0.0)
	if mesh == null or mesh.get_surface_count() == 0:
		push_error("Expected build_mesh(radius=0) to still produce geometry")
		return 1
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	for v in verts:
		if absf(v.x) > hx + 0.001 or absf(v.y) > hy + 0.001 or absf(v.z) > hz + 0.001:
			push_error("Expected a zero-radius box to stay within its plain-box bounds, got %s" % v)
			return 1
	return 0


## A radius bigger than the box should get clamped rather than producing
## garbage/inverted geometry.
func _test_build_mesh_handles_oversized_radius() -> int:
	var mesh := RoundedBoxMeshScript.build_mesh(Vector3(1.0, 1.0, 1.0), 50.0)
	if mesh == null or mesh.get_surface_count() == 0:
		push_error("Expected an oversized radius to still clamp to valid geometry")
		return 1
	return 0


func _test_collision_points_match_box_corners() -> int:
	var size := Vector3(1.6, 0.3, 1.15)
	var points := RoundedBoxMeshScript.build_collision_points(size, 0.1)
	if points.size() != 8:
		push_error("Expected 8 collision hull points, got %d" % points.size())
		return 1
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	for p in points:
		if not (
			is_equal_approx(absf(p.x), hx)
			and is_equal_approx(absf(p.y), hy)
			and is_equal_approx(absf(p.z), hz)
		):
			push_error("Expected each collision point to sit at a box corner, got %s" % p)
			return 1
	return 0
