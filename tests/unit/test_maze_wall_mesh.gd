class_name TestMazeWallMesh
extends RefCounted

const MazeWallMeshScript := preload("res://scripts/maze_wall_mesh.gd")
const MazeGeometryScript := preload("res://scripts/maze_geometry.gd")


func run() -> int:
	var failures := 0
	failures += _test_solid_wall_normals_point_outward()
	failures += _test_single_wall_mesh_builds()
	failures += _test_maze_offset_centers_odd_grid()
	return failures


func _test_solid_wall_normals_point_outward() -> int:
	var grid := [
		[1, 1, 1],
		[1, 0, 1],
		[1, 1, 1],
	]
	var mesh := MazeWallMeshScript.build(
		grid,
		Vector3(3.0, 3.0, 3.0),
		func(gx: int, gy: int) -> Vector3:
			return Vector3(gx * 3.0, 0.0, gy * 3.0)
	)
	var failures := 0
	if mesh.get_surface_count() == 0:
		push_error("Expected wall mesh to contain at least one surface")
		return 1

	var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	if normals.is_empty():
		push_error("Expected wall mesh vertex normals")
		failures += 1
	else:
		if not _has_normal(normals, Vector3(0.0, 0.0, -1.0)):
			push_error("Expected outward -Z wall normals")
			failures += 1
		if not _has_normal(normals, Vector3(0.0, 1.0, 0.0)):
			push_error("Expected outward +Y wall normals")
			failures += 1
	return failures


func _test_single_wall_mesh_builds() -> int:
	var grid := [[1]]
	var mesh := MazeWallMeshScript.build(
		grid,
		Vector3(3.0, 3.0, 3.0),
		func(_gx: int, _gy: int) -> Vector3:
			return Vector3.ZERO
	)
	if mesh.get_surface_count() == 0:
		push_error("Expected solid wall mesh to contain a surface")
		return 1
	return 0


func _has_normal(normals: PackedVector3Array, target: Vector3) -> bool:
	for i in normals.size():
		if normals[i].dot(target) > 0.99:
			return true
	return false


func _test_maze_offset_centers_odd_grid() -> int:
	## 3 maze cells → 7 wall-grid cells. Center cell (3,3) should sit at origin.
	var origin: Vector3 = MazeGeometryScript.grid_to_world(3, 3, 3, 3, 2.0)
	if origin.distance_to(Vector3.ZERO) > 0.001:
		push_error("Expected maze grid center at origin, got %s" % origin)
		return 1
	return 0
