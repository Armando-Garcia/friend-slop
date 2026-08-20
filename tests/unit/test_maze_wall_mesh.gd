class_name TestMazeWallMesh
extends RefCounted

const MazeWallMeshScript := preload("res://scripts/maze_wall_mesh.gd")
const MazeGeometryScript := preload("res://scripts/maze_geometry.gd")


func run() -> int:
	var failures := 0
	failures += _test_straight_run_is_one_sausage()
	failures += _test_vertical_run_is_one_sausage()
	failures += _test_isolated_cell_is_one_run()
	failures += _test_t_junction_is_two_runs()
	failures += _test_straight_run_has_two_joints()
	failures += _test_t_has_four_joints()
	failures += _test_edge_stops_at_cell_centers()
	failures += _test_maze_offset_centers_odd_grid()
	failures += _test_keep_in_extents_cover_outer_walls()
	failures += _test_walls_are_slide_surfaces()
	return failures


func _test_straight_run_is_one_sausage() -> int:
	var grid := [
		[1],
		[1],
		[1],
		[1],
	]
	var runs: Array = MazeWallMeshScript.collect_runs(grid)
	if runs.size() != 1:
		push_error("A 4-cell corridor should be one run, got %s" % runs.size())
		return 1
	if int(runs[0]["length"]) != 4 or not bool(runs[0]["along_x"]):
		push_error("Expected a length-4 X run, got %s" % runs[0])
		return 1
	var radius := MazeWallMeshScript.cylinder_radius(3.0)
	if not is_equal_approx(radius, 1.5):
		push_error("Half-cylinder radius should be half the cell, got %s" % radius)
		return 1
	return 0


func _test_vertical_run_is_one_sausage() -> int:
	var grid := [[1, 1, 1, 1]]
	var runs: Array = MazeWallMeshScript.collect_runs(grid)
	if runs.size() != 1:
		push_error("A 4-cell vertical wall should be one run, got %s" % runs.size())
		return 1
	if int(runs[0]["length"]) != 4 or bool(runs[0]["along_x"]):
		push_error("Expected a length-4 Z run, got %s" % runs[0])
		return 1
	return 0


func _test_isolated_cell_is_one_run() -> int:
	var grid := [[1]]
	var runs: Array = MazeWallMeshScript.collect_runs(grid)
	if runs.size() != 1:
		push_error("An isolated wall cell should be one run, got %s" % runs.size())
		return 1
	return 0


func _test_t_junction_is_two_runs() -> int:
	var grid := [
		[0, 1, 0],
		[1, 1, 1],
		[0, 1, 0],
	]
	var runs: Array = MazeWallMeshScript.collect_runs(grid)
	if runs.size() != 2:
		push_error("A T junction should be two overlapping runs, got %s" % runs.size())
		return 1
	return 0


func _test_straight_run_has_two_joints() -> int:
	var grid := [
		[1],
		[1],
		[1],
		[1],
	]
	var runs: Array = MazeWallMeshScript.collect_runs(grid)
	var joints: Array = MazeWallMeshScript.collect_joints(runs)
	if joints.size() != 2:
		push_error("A straight run should have two end joints, got %s" % joints.size())
		return 1
	return 0


func _test_t_has_four_joints() -> int:
	var grid := [
		[1, 0, 0],
		[1, 1, 1],
		[1, 0, 0],
	]
	var runs: Array = MazeWallMeshScript.collect_runs(grid)
	var joints: Array = MazeWallMeshScript.collect_joints(runs)
	if joints.size() != 4:
		push_error("A T should have four joints, got %s" % joints.size())
		return 1
	return 0


func _test_edge_stops_at_cell_centers() -> int:
	var run := {"along_x": true, "gx": 0, "gy": 0, "length": 2}
	var pose: Dictionary = MazeWallMeshScript.run_pose(
		run,
		Vector3(3.0, 3.0, 3.0),
		func(gx: int, gy: int) -> Vector3:
			return Vector3(gx * 3.0, 0.0, gy * 3.0),
		1.5,
		1.5
	)
	var box_size: Vector3 = pose["box_size"]
	if not box_size.is_equal_approx(Vector3(3.0, 1.5, 3.0)):
		push_error("Edge should span cell centers, got %s" % box_size)
		return 1
	var box_y: float = pose["box_xform"].origin.y
	var cap_y: float = pose["cyl_xform"].origin.y
	if not is_equal_approx(box_y, 0.75) or not is_equal_approx(cap_y, 1.5):
		push_error("Cap axis should sit on the shaft top, box_y=%s cap_y=%s" % [box_y, cap_y])
		return 1
	if not is_equal_approx(float(pose["cyl_len"]), 3.0):
		push_error("Cap should stop at the joints, got %s" % pose["cyl_len"])
		return 1
	var joint: Dictionary = MazeWallMeshScript.joint_pose(
		Vector2i(0, 0),
		func(gx: int, gy: int) -> Vector3:
			return Vector3(gx * 3.0, 0.0, gy * 3.0),
		1.5,
		1.5
	)
	var ball_y: float = joint["ball_xform"].origin.y
	if not is_equal_approx(ball_y, 1.5):
		push_error("Joint sphere should sit on the shaft top, got %s" % ball_y)
		return 1
	return 0


func _test_maze_offset_centers_odd_grid() -> int:
	## 3 maze cells → 7 wall-grid cells. Center cell (3,3) should sit at origin.
	var origin: Vector3 = MazeGeometryScript.grid_to_world(3, 3, 3, 3, 2.0)
	if origin.distance_to(Vector3.ZERO) > 0.001:
		push_error("Expected maze grid center at origin, got %s" % origin)
		return 1
	return 0


func _test_keep_in_extents_cover_outer_walls() -> int:
	var box: Rect2 = MazeGeometryScript.xz_extents(3, 3, 2.0)
	var min_wall: Vector3 = MazeGeometryScript.grid_to_world(0, 0, 3, 3, 2.0)
	if box.position.x > min_wall.x - 1.0:
		push_error("Keep-in should sit outside the outer wall, got %s" % box)
		return 1
	if box.size.x < 4.0 or box.size.y < 4.0:
		push_error("Keep-in extents too small, got %s" % box.size)
		return 1
	return 0


func _test_walls_are_slide_surfaces() -> int:
	var parent := Node3D.new()
	MazeGeometryScript.add_walls(parent, [[1]], 1, 1, 3.0, 3.0)
	var walls := parent.get_node_or_null("Walls")
	var failed := 0
	if walls == null or not walls.is_in_group("slide_surface"):
		push_error("Maze Walls must be a slide surface")
		failed = 1
	parent.free()
	return failed
