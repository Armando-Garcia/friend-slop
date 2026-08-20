class_name TestMazePassageQuery
extends RefCounted

const MazePassageQueryScript := preload("res://scripts/headmaster/maze_passage_query.gd")


func run() -> int:
	var failures := 0
	failures += _test_open_passage_edge_detection()
	failures += _test_nearest_open_passage()
	failures += _test_rejects_room_centers_and_solid_walls()
	return failures


func _make_grid() -> Array:
	## 5x5 wall grid: rooms at (1,1) and (3,1) connected by open edge (2,1).
	var grid: Array = []
	for x in range(5):
		var col: Array = []
		for y in range(5):
			col.append(1)
		grid.append(col)
	grid[1][1] = 0
	grid[2][1] = 0
	grid[3][1] = 0
	grid[1][3] = 0
	return grid


func _test_open_passage_edge_detection() -> int:
	var grid := _make_grid()
	if not MazePassageQueryScript.is_open_passage_edge(grid, 2, 1):
		push_error("Expected (2,1) to be an open passage edge")
		return 1
	return 0


func _test_nearest_open_passage() -> int:
	var grid := _make_grid()
	var found: Vector2i = MazePassageQueryScript.nearest_open_passage_cell(
		grid, Vector2i(1, 1), 4
	)
	if found != Vector2i(2, 1):
		push_error("Expected nearest open passage from room (1,1) to be (2,1)")
		return 1
	return 0


func _test_rejects_room_centers_and_solid_walls() -> int:
	var grid := _make_grid()
	if MazePassageQueryScript.is_open_passage_edge(grid, 1, 1):
		push_error("Room center should not count as a passage edge")
		return 1
	if MazePassageQueryScript.is_open_passage_edge(grid, 0, 0):
		push_error("Solid wall cell should not count as a passage edge")
		return 1
	return 0
