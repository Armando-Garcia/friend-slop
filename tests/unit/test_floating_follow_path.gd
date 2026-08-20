extends RefCounted

const FloatingFollowPathScript := preload("res://scripts/spells/floating_follow_path.gd")


func run() -> int:
	var failures := 0
	failures += _test_grid_path_goes_around_wall()
	failures += _test_grid_path_direct_when_open()
	failures += _test_advance_path_drops_reached_waypoints()
	failures += _test_world_height_path_keeps_goal_y()
	return failures


func _open_corridor_with_blocker() -> Array:
	## 5x5 open cells with a wall blocking the middle of the direct route.
	var grid: Array = []
	grid.resize(5)
	for x in 5:
		grid[x] = []
		grid[x].resize(5)
		for y in 5:
			grid[x][y] = 0
	grid[2][1] = 1
	grid[2][2] = 1
	grid[2][3] = 1
	return grid


func _test_grid_path_goes_around_wall() -> int:
	var grid := _open_corridor_with_blocker()
	var path := FloatingFollowPathScript.find_grid_path(
		grid, Vector2i(1, 2), Vector2i(3, 2)
	)
	if path.is_empty():
		push_error("Expected a path around the blocking wall")
		return 1
	if path[0] != Vector2i(1, 2) or path[path.size() - 1] != Vector2i(3, 2):
		push_error("Expected path to start and end on the requested cells")
		return 1
	for cell in path:
		if int(grid[cell.x][cell.y]) != 0:
			push_error("Path stepped onto a wall cell")
			return 1
	if path.size() < 4:
		push_error("Expected detour path longer than the blocked direct line")
		return 1
	return 0


func _test_grid_path_direct_when_open() -> int:
	var grid: Array = [
		[1, 1, 1, 1, 1],
		[1, 0, 0, 0, 1],
		[1, 0, 0, 0, 1],
		[1, 0, 0, 0, 1],
		[1, 1, 1, 1, 1],
	]
	var path := FloatingFollowPathScript.find_grid_path(
		grid, Vector2i(1, 1), Vector2i(3, 1)
	)
	if path.is_empty():
		push_error("Expected open-grid path")
		return 1
	if path.size() != 3:
		push_error("Expected shortest open path of length 3, got %d" % path.size())
		return 1
	return 0


func _test_advance_path_drops_reached_waypoints() -> int:
	var path: Array[Vector3] = [
		Vector3(0.0, 1.0, 0.0),
		Vector3(2.0, 1.0, 0.0),
		Vector3(4.0, 1.0, 0.0),
	]
	var remaining := FloatingFollowPathScript.advance_path(path, Vector3(0.1, 1.0, 0.0))
	if remaining.size() != 2:
		push_error("Expected first waypoint to be dropped when reached")
		return 1
	if remaining[0] != Vector3(2.0, 1.0, 0.0):
		push_error("Expected next waypoint after advancing")
		return 1
	return 0


func _test_world_height_path_keeps_goal_y() -> int:
	## No maze / no space → direct path should preserve elevated goal Y.
	var path := FloatingFollowPathScript.build_path(
		Vector3(0.0, 1.15, 0.0),
		Vector3(4.0, 7.5, 0.0),
		null,
		1.15,
		null,
		true
	)
	if path.is_empty():
		push_error("Expected a direct world-height path")
		return 1
	if not is_equal_approx(path[path.size() - 1].y, 7.5):
		push_error("Expected air follow path to keep elevated goal Y")
		return 1
	return 0
