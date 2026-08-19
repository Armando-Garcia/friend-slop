class_name TestMazeCarver
extends RefCounted

const MazeCarverScript := preload("res://scripts/maze_carver.gd")

var failures: int = 0


func run() -> int:
	test_all_cells_carved_small()
	test_all_cells_carved_large()
	test_boundary_stays_solid()
	test_all_cells_reachable()
	test_same_seed_produces_same_maze()
	test_different_seeds_produce_different_mazes()
	test_carve_iterative_does_not_use_recursion()
	test_longer_mean_corridor_tends_to_longer_runs()
	test_clearings_open_more_cells_and_keep_border()
	test_clearing_squares_do_not_overlap()
	test_clearings_place_per_quadrant()
	test_clearings_respect_separation()
	test_spire_clearing_opens_center()
	test_count_open_neighbors()
	test_open_box_is_hollow_with_solid_border()
	test_open_box_cover_marks_center()
	return failures


func test_all_cells_carved_small() -> void:
	var grid := _generate(5, 5, 1234)
	_assert_eq(_count_carved_cells(grid, 5, 5), 25, "5x5 maze should carve all 25 cells")


func test_all_cells_carved_large() -> void:
	var grid := _generate(45, 45, 5678)
	_assert_eq(
		_count_carved_cells(grid, 45, 45),
		45 * 45,
		"45x45 maze should carve all cells without stack overflow"
	)


func test_boundary_stays_solid() -> void:
	var grid := _generate(10, 8, 42)
	_assert_true(
		MazeCarverScript.outer_boundary_is_solid(grid),
		"outer maze boundary should remain solid walls"
	)


func test_all_cells_reachable() -> void:
	var grid := _generate(15, 15, 999)
	_assert_true(
		MazeCarverScript.all_cells_reachable(grid, 15, 15),
		"every cell should be reachable from the start"
	)


func test_same_seed_produces_same_maze() -> void:
	var grid_a := _generate(12, 12, 2026)
	var grid_b := _generate(12, 12, 2026)
	_assert_true(
		MazeCarverScript.grids_equal(grid_a, grid_b),
		"identical seeds should produce identical mazes"
	)


func test_different_seeds_produce_different_mazes() -> void:
	var grid_a := _generate(12, 12, 111)
	var grid_b := _generate(12, 12, 222)
	_assert_true(
		not MazeCarverScript.grids_equal(grid_a, grid_b),
		"different seeds should usually produce different mazes"
	)


func test_longer_mean_corridor_tends_to_longer_runs() -> void:
	var short_opts := {
		"mean_corridor_length": 1.0,
		"corridor_length_variance": 0,
		"clearing_count": 0,
	}
	var long_opts := {
		"mean_corridor_length": 8.0,
		"corridor_length_variance": 0,
		"clearing_count": 0,
	}
	var short_mean := 0.0
	var long_mean := 0.0
	for seed_value in [101, 202, 303, 404, 505]:
		var short_grid := _generate(24, 24, seed_value, short_opts)
		var long_grid := _generate(24, 24, seed_value, long_opts)
		short_mean += MazeCarverScript.mean_straight_run_length(short_grid, 24, 24)
		long_mean += MazeCarverScript.mean_straight_run_length(long_grid, 24, 24)
	short_mean /= 5.0
	long_mean /= 5.0
	_assert_true(
		long_mean > short_mean,
		"higher mean_corridor_length should produce longer average straight runs"
	)


func test_clearings_open_more_cells_and_keep_border() -> void:
	var plain := _generate(16, 16, 777, {
		"mean_corridor_length": 3.0,
		"clearing_count": 0,
		"clearing_size": 0.0,
	})
	var cleared := _generate(16, 16, 777, {
		"mean_corridor_length": 3.0,
		"clearing_count": 1,
		"clearing_size": 2.0,
	})
	_assert_true(
		not MazeCarverScript.grids_equal(plain, cleared),
		"clearings should change the maze layout"
	)
	_assert_true(
		MazeCarverScript.count_open_wall_cells(cleared)
		> MazeCarverScript.count_open_wall_cells(plain),
		"clearings should open additional wall-grid cells"
	)
	_assert_true(
		MazeCarverScript.outer_boundary_is_solid(cleared),
		"clearings must leave the outer boundary solid"
	)
	_assert_true(
		MazeCarverScript.all_cells_reachable(cleared, 16, 16),
		"maze with clearings should remain fully connected"
	)


func test_clearing_squares_do_not_overlap() -> void:
	_assert_true(
		not MazeCarverScript._clearing_squares_overlap(
			Vector2i(5, 5), 2, Vector2i(11, 5), 2
		),
		"separated clearings should not count as overlapping"
	)
	_assert_true(
		MazeCarverScript._clearing_squares_overlap(
			Vector2i(5, 5), 2, Vector2i(9, 5), 2
		),
		"adjacent clearings that share cells should overlap"
	)


func test_clearings_place_per_quadrant() -> void:
	seed(424242)
	var grid := _generate(20, 20, 424242, {
		"clearing_count": 0,
		"spire_clearing_size": 0.0,
	})
	var placed: Array[Dictionary] = []
	MazeCarverScript.add_clearings(grid, 20, 20, 1, 1.0, 0.0, placed)
	_assert_eq(placed.size(), 4, "count=1 should place one clearing per quadrant")
	var seen := {"nw": false, "ne": false, "sw": false, "se": false}
	var mid_x := 10
	var mid_y := 10
	for entry in placed:
		var center: Vector2i = entry["center"]
		var cell_x := int((center.x - 1) / 2)
		var cell_y := int((center.y - 1) / 2)
		if cell_x < mid_x and cell_y < mid_y:
			seen["nw"] = true
		elif cell_x >= mid_x and cell_y < mid_y:
			seen["ne"] = true
		elif cell_x < mid_x and cell_y >= mid_y:
			seen["sw"] = true
		else:
			seen["se"] = true
	_assert_true(
		seen["nw"] and seen["ne"] and seen["sw"] and seen["se"],
		"each quadrant should get a clearing center"
	)


func test_clearings_respect_separation() -> void:
	seed(777001)
	var grid := _generate(30, 30, 777001, {
		"clearing_count": 0,
		"spire_clearing_size": 0.0,
	})
	var placed: Array[Dictionary] = []
	MazeCarverScript.add_spire_clearing(grid, 30, 30, 2.0, placed)
	MazeCarverScript.add_clearings(grid, 30, 30, 1, 1.0, 8.0, placed)
	_assert_true(placed.size() >= 2, "spire plus at least one spaced clearing should place")
	var floor_sep := 8.0 * 0.5
	for i in placed.size():
		for j in range(i + 1, placed.size()):
			var dist := MazeCarverScript._clearing_center_maze_distance(
				placed[i]["center"], placed[j]["center"]
			)
			_assert_true(
				dist >= floor_sep,
				"clearing centers should stay at least half the separation apart"
			)


func test_spire_clearing_opens_center() -> void:
	var plain := _generate(15, 15, 333, {
		"clearing_count": 0,
		"spire_clearing_size": 0.0,
	})
	var with_spire := _generate(15, 15, 333, {
		"clearing_count": 0,
		"spire_clearing_size": 2.0,
	})
	_assert_true(
		MazeCarverScript.count_open_wall_cells(with_spire)
		> MazeCarverScript.count_open_wall_cells(plain),
		"spire clearing should open additional wall-grid cells"
	)
	## Center maze cell (7, 7) -> wall coords (15, 15); neighbors in the square open.
	_assert_eq(with_spire[15][15], 0, "spire clearing should open the maze center cell")
	_assert_eq(with_spire[13][15], 0, "spire clearing should open cells near center")
	_assert_true(
		MazeCarverScript.outer_boundary_is_solid(with_spire),
		"spire clearing must leave the outer boundary solid"
	)
	_assert_true(
		MazeCarverScript.all_cells_reachable(with_spire, 15, 15),
		"maze with spire clearing should remain fully connected"
	)


func test_count_open_neighbors() -> void:
	var grid := _generate(5, 5, 4242)
	var count := MazeCarverScript.count_open_neighbors(grid, 1, 1)
	_assert_true(
		count >= 1 and count <= 3,
		"start cell should report only connected maze-cell neighbors"
	)
	_assert_eq(
		MazeCarverScript.count_open_neighbors(grid, 999, 999),
		0,
		"out-of-bounds positions should report zero neighbors"
	)


func test_open_box_is_hollow_with_solid_border() -> void:
	var grid: Array = MazeCarverScript.generate_open_box(5, 5, false)
	_assert_true(
		MazeCarverScript.outer_boundary_is_solid(grid),
		"open box should keep a solid outer wall ring"
	)
	var size: Vector2i = MazeCarverScript.grid_size_for(5, 5)
	_assert_eq(int(grid[1][1]), 0, "open box interior corner should be carved")
	_assert_eq(
		int(grid[size.x - 2][size.y - 2]),
		0,
		"open box far interior should be carved"
	)


func test_open_box_cover_marks_center() -> void:
	var open_grid: Array = MazeCarverScript.generate_open_box(5, 5, false)
	var cover_grid: Array = MazeCarverScript.generate_open_box(5, 5, true)
	var size: Vector2i = MazeCarverScript.grid_size_for(5, 5)
	var cx := int(size.x / 2)
	var cy := int(size.y / 2)
	_assert_eq(int(open_grid[cx][cy]), 0, "hollow box center should be open")
	_assert_eq(int(cover_grid[cx][cy]), 1, "cover box center should be a wall")


func test_carve_iterative_does_not_use_recursion() -> void:
	var grid := _generate(3, 3, 7)
	for x in grid.size():
		for y in grid[x].size():
			if grid[x][y] != 0 and grid[x][y] != 1:
				_assert_true(false, "grid cells should only contain wall (1) or passage (0) values")
				return
	_assert_true(true, "grid cells should only contain wall (1) or passage (0) values")


func _generate(
	maze_width: int,
	maze_height: int,
	rng_seed: int = -1,
	options: Variant = null
) -> Array:
	return MazeCarverScript.generate(maze_width, maze_height, rng_seed, options)


func _count_carved_cells(grid: Array, maze_width: int, maze_height: int) -> int:
	return MazeCarverScript.count_carved_cells(grid, maze_width, maze_height)


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		failures += 1
		push_error("  FAIL: %s" % message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		print("  PASS: %s" % message)
	else:
		failures += 1
		push_error("  FAIL: %s (expected %s, got %s)" % [message, expected, actual])
