class_name TestStaircaseMesh
extends RefCounted

const StaircaseMeshScript := preload("res://scripts/objectives/staircase_mesh.gd")


func run() -> int:
	var failures := 0
	failures += _test_build_mesh_produces_geometry()
	failures += _test_ramp_collision_points_match_ramp_wedge()
	return failures


func _test_build_mesh_produces_geometry() -> int:
	var mesh := StaircaseMeshScript.build_mesh(Vector3(1.6, 0.8, 1.8))
	if mesh == null or mesh.get_surface_count() == 0:
		push_error("Expected build_mesh to produce at least one surface")
		return 1
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	## 10 independent boxes x 6 faces x 2 tris x 3 verts.
	var expected := StaircaseMeshScript.STEP_COUNT * 6 * 2 * 3
	if verts.size() != expected:
		push_error("Expected %d vertices from 10 stacked boxes, got %d" % [expected, verts.size()])
		return 1
	return 0


## A staircase should collide exactly like PuzzleStepNode's RAMP wedge.
func _test_ramp_collision_points_match_ramp_wedge() -> int:
	var size := Vector3(1.6, 0.8, 1.8)
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var expected := PackedVector3Array([
		Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz),
		Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz),
		Vector3(-hx, hy, hz), Vector3(hx, hy, hz),
	])
	var points := StaircaseMeshScript.ramp_collision_points(size)
	if points.size() != expected.size():
		push_error("Expected %d ramp collision points, got %d" % [expected.size(), points.size()])
		return 1
	for i in points.size():
		if not points[i].is_equal_approx(expected[i]):
			push_error("Expected ramp collision point %d to be %s, got %s" % [i, expected[i], points[i]])
			return 1
	return 0
