extends RefCounted

const MazeHoleTraversalScript := preload("res://scripts/maze/maze_hole_traversal.gd")
const MazeHoleScript := preload("res://scripts/maze/maze_hole.gd")
const MazeHoleTunnelScript := preload("res://scripts/maze/maze_hole_tunnel.gd")
const MazeWallHoleFrameScript := preload("res://scripts/maze/maze_wall_hole_frame.gd")


func run() -> int:
	var failures := 0
	failures += _test_burrow_reaches_exit()
	failures += _test_domed_opening_height()
	failures += _test_hole_burrow_waypoints()
	failures += _test_carve_tunnel_passage()
	return failures


func _test_burrow_reaches_exit() -> int:
	var gnome := CharacterBody3D.new()
	gnome.add_to_group("gnome")
	var start := Vector3(0.0, 0.0, 0.0)
	var center := Vector3(0.0, 0.0, 1.5)
	var exit_pos := Vector3(0.0, 0.0, 3.0)
	gnome.position = start
	MazeHoleTraversalScript.begin(gnome, [start, center, exit_pos])
	for _i in 120:
		if MazeHoleTraversalScript.tick(gnome, 1.0 / 60.0):
			break
	if MazeHoleTraversalScript.is_active(gnome):
		push_error("Burrow should finish within 2 seconds")
		gnome.free()
		return 1
	if gnome.position.distance_to(exit_pos) > 0.12:
		push_error("Burrow should end at the tunnel exit")
		gnome.free()
		return 1
	gnome.free()
	return 0


func _test_domed_opening_height() -> int:
	var expected := MazeHoleScript.HOLE_RECT_HEIGHT + MazeHoleScript.HOLE_ARCH_RADIUS
	if not is_equal_approx(MazeHoleScript.opening_total_height(), expected):
		push_error("Domed opening height should combine rect and arch radius")
		return 1
	var mesh := MazeHoleTunnelScript.build_interior_mesh(3.0)
	if mesh.get_surface_count() < 1:
		push_error("Tunnel mesh should have at least one surface")
		return 1
	return 0


func _test_hole_burrow_waypoints() -> int:
	var root := Node3D.new()
	var hole := MazeHoleScript.spawn(root, Vector3(6.0, 0.0, 6.0), Vector3.FORWARD, 3.0)
	var points: Array = hole.call("burrow_waypoints", 0.05)
	if points.size() != 3:
		push_error("Hole burrow path should include approach, center, and exit")
		root.free()
		return 1
	var center: Vector3 = points[1]
	if center.distance_to(Vector3(6.0, 0.05, 6.0)) > 0.05:
		push_error("Burrow center should stay on the wall cell")
		root.free()
		return 1
	root.free()
	return 0


func _test_carve_tunnel_passage() -> int:
	var walls := StaticBody3D.new()
	var cell := Vector2i(3, 5)
	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.set_meta(MazeWallHoleFrameScript.WALL_CELL_META, cell)
	walls.add_child(col)
	if not MazeWallHoleFrameScript.carve_tunnel_passage(
		walls, cell, Vector3.ZERO, Vector3.FORWARD, 3.0, 3.0
	):
		push_error("Expected to carve a tunnel passage in wall collision")
		walls.free()
		return 1
	var fragment_count := 0
	for child in walls.get_children():
		if child is CollisionShape3D and bool(child.get_meta(&"tunnel_fragment", false)):
			fragment_count += 1
	if fragment_count < 3:
		push_error("Expected tunnel collision fragments around the opening")
		walls.free()
		return 1
	walls.free()
	return 0
