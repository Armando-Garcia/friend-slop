class_name TestPlayerSpawnLayout
extends RefCounted

const PlayerSpawnLayoutScript := preload("res://scripts/player_spawn_layout.gd")


func run() -> int:
	var failures := 0
	failures += _test_single_player_uses_spawn_center()
	failures += _test_two_players_are_separated()
	failures += _test_three_players_use_distinct_positions()
	failures += _test_open_spawn_cells_skip_walled_centers()
	failures += _test_headmaster_spawns_near_center()
	failures += _test_apprentices_use_distinct_corners()
	failures += _test_teammate_offsets_cluster_with_spacing()
	return failures


func _test_single_player_uses_spawn_center() -> int:
	var wall_grid := _fully_open_corridors(5, 5)
	var positions := PlayerSpawnLayoutScript.compute_positions(
		Vector2i(0, 0),
		wall_grid,
		5,
		5,
		Callable(self, "_cell_to_world"),
		1
	)
	if positions.size() != 1:
		push_error("Expected one spawn position for solo player")
		return 1
	# First roster cell is headmaster center for compute_positions index 0.
	var center_cell := PlayerSpawnLayoutScript.resolve_headmaster_cell(wall_grid, 5, 5)
	var expected := Vector3(
		float(center_cell.x) * 3.0,
		PlayerSpawnLayoutScript.PLAYER_Y,
		float(center_cell.y) * 3.0
	)
	if positions[0] != expected:
		push_error("Expected solo compute_positions[0] at headmaster center cell")
		return 1
	return 0


func _test_two_players_are_separated() -> int:
	var wall_grid := _fully_open_corridors(5, 5)
	var positions := PlayerSpawnLayoutScript.compute_positions(
		Vector2i(0, 0),
		wall_grid,
		5,
		5,
		Callable(self, "_cell_to_world"),
		2
	)
	if positions.size() != 2:
		push_error("Expected two spawn positions")
		return 1
	if positions[0].distance_to(positions[1]) < 1.0:
		push_error("Expected two-player spawns to be separated")
		return 1
	return 0


func _test_three_players_use_distinct_positions() -> int:
	var wall_grid := _fully_open_corridors(5, 5)
	var positions := PlayerSpawnLayoutScript.compute_positions(
		Vector2i(0, 0),
		wall_grid,
		5,
		5,
		Callable(self, "_cell_to_world"),
		3
	)
	if positions.size() != 3:
		push_error("Expected three spawn positions")
		return 1

	var seen: Dictionary = {}
	for pos in positions:
		var key := "%.2f,%.2f,%.2f" % [pos.x, pos.y, pos.z]
		if seen.has(key):
			push_error("Expected three-player spawns to be unique")
			return 1
		seen[key] = true
	return 0


func _test_open_spawn_cells_skip_walled_centers() -> int:
	var wall_grid := _open_grid(3, 3)
	wall_grid[3][3] = 1
	var open_cells: Array[Vector2i] = PlayerSpawnLayoutScript.collect_open_spawn_cells(
		wall_grid,
		3,
		3
	)
	if open_cells.size() != 8:
		push_error("Expected 8 open spawn cells after walling one center")
		return 1
	if open_cells.has(Vector2i(1, 1)):
		push_error("Walled cell should not be an open spawn zone")
		return 1
	return 0


func _test_headmaster_spawns_near_center() -> int:
	var wall_grid := _fully_open_corridors(9, 9)
	var cell := PlayerSpawnLayoutScript.resolve_headmaster_cell(wall_grid, 9, 9)
	if cell != Vector2i(4, 4):
		push_error("Headmaster should resolve to maze center cell on an open grid")
		return 1
	return 0


func _test_apprentices_use_distinct_corners() -> int:
	var wall_grid := _fully_open_corridors(9, 9)
	var a0 := PlayerSpawnLayoutScript.resolve_apprentice_cell(wall_grid, 9, 9, 0)
	var a1 := PlayerSpawnLayoutScript.resolve_apprentice_cell(wall_grid, 9, 9, 1)
	var a2 := PlayerSpawnLayoutScript.resolve_apprentice_cell(wall_grid, 9, 9, 2)
	if a0 != Vector2i(0, 0) or a1 != Vector2i(8, 0) or a2 != Vector2i(0, 8):
		push_error("Apprentices should map to NW, NE, SW corners")
		return 1
	if a0 == a1 or a0 == a2 or a1 == a2:
		push_error("Apprentice corner cells must be distinct")
		return 1
	var roster: Array[Vector2i] = PlayerSpawnLayoutScript.collect_roster_spawn_cells(
		wall_grid,
		9,
		9
	)
	if roster.size() != 4:
		push_error("Roster should include headmaster + 3 apprentices")
		return 1
	if roster[0] != Vector2i(4, 4):
		push_error("Roster[0] should be headmaster center")
		return 1
	return 0


func _test_teammate_offsets_cluster_with_spacing() -> int:
	## Apprentice CapsuleShape3D radius ≈ 0.24; centers must clear 2×radius.
	const MIN_CLEARANCE := 0.48
	var solo: Array[Vector3] = PlayerSpawnLayoutScript.teammate_offsets(1)
	var spacing := PlayerSpawnLayoutScript.TEAMMATE_SPAWN_SPACING
	var trio: Array[Vector3] = PlayerSpawnLayoutScript.teammate_offsets(3)
	var ok := (
		solo.size() == 1
		and solo[0] == Vector3.ZERO
		and spacing >= MIN_CLEARANCE
		and trio.size() == 3
		and is_equal_approx(trio[1].x, 0.0)
		and absf(trio[0].distance_to(trio[1]) - spacing) <= 0.001
		and spacing + 0.24 <= 1.5
	)
	if not ok:
		push_error("Teammate offsets must clear capsules and fit three in a maze cell")
		return 1
	return 0


func _cell_to_world(cell_x: int, cell_y: int) -> Vector3:
	return Vector3(float(cell_x) * 3.0, 0.0, float(cell_y) * 3.0)


func _open_grid(maze_width: int, maze_height: int) -> Array:
	var grid_w := maze_width * 2 + 1
	var grid_h := maze_height * 2 + 1
	var grid: Array = []
	for gx in grid_w:
		var column: Array = []
		for gy in grid_h:
			var is_passage_x := gx % 2 == 1
			var is_passage_y := gy % 2 == 1
			column.append(0 if is_passage_x and is_passage_y else 1)
		grid.append(column)
	return grid


func _fully_open_corridors(maze_width: int, maze_height: int) -> Array:
	var grid := _open_grid(maze_width, maze_height)
	var grid_w := maze_width * 2 + 1
	var grid_h := maze_height * 2 + 1
	for gx in range(1, grid_w - 1):
		for gy in range(1, grid_h - 1):
			grid[gx][gy] = 0
	return grid
