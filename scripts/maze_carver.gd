class_name MazeCarver
extends RefCounted

## Pure maze-carving logic (no scene nodes). Safe for large grids - uses an explicit stack.
##
## Tuning:
## - mean_corridor_length: center of typical corridor run lengths (maze cells).
## - corridor_length_variance: half-range around the mean most corridors fall into.
## - clearing_count: how many clearings to place in each maze quadrant.
## - clearing_size: average clearing radius in maze cells.
## - clearing_separation: preferred min distance between clearing centers (maze cells).
## - spire_clearing_size: radius of a fixed square clearing at maze center (0 = none).

const DIRS := [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]


static func generate(
	maze_width: int,
	maze_height: int,
	rng_seed: int = -1,
	options: Variant = null
) -> Array:
	if maze_width < 1 or maze_height < 1:
		push_error("MazeCarver.generate: width and height must be >= 1")
		return []

	if rng_seed >= 0:
		seed(rng_seed)

	var opts: Dictionary = options if options is Dictionary else {}
	var mean_corridor_length: float = float(opts.get("mean_corridor_length", 3.0))
	var corridor_length_variance: int = int(opts.get("corridor_length_variance", 0))
	var clearing_count: int = int(opts.get("clearing_count", 0))
	var clearing_size: float = float(opts.get("clearing_size", 0.0))
	var clearing_separation: float = float(opts.get("clearing_separation", 0.0))
	var spire_clearing_size: float = float(opts.get("spire_clearing_size", 0.0))

	var grid := _create_wall_grid(maze_width, maze_height)
	carve_iterative(grid, 1, 1, mean_corridor_length, corridor_length_variance)
	var placed: Array[Dictionary] = []
	add_spire_clearing(grid, maze_width, maze_height, spire_clearing_size, placed)
	add_clearings(
		grid, maze_width, maze_height, clearing_count, clearing_size, clearing_separation, placed
	)
	return grid


static func generate_open_box(
	maze_width: int, maze_height: int, with_cover: bool = false
) -> Array:
	## Perimeter walls, fully open interior. Optional center cover for LOS tests.
	if maze_width < 1 or maze_height < 1:
		push_error("MazeCarver.generate_open_box: width and height must be >= 1")
		return []
	var grid := _create_wall_grid(maze_width, maze_height)
	var size := grid_size_for(maze_width, maze_height)
	for x in range(1, size.x - 1):
		for y in range(1, size.y - 1):
			grid[x][y] = 0
	if with_cover:
		_add_center_cover(grid, size)
	return grid


static func _add_center_cover(grid: Array, size: Vector2i) -> void:
	var cx := int(size.x / 2.0)
	var half := mini(2, maxi(int(size.y / 2.0) - 2, 1))
	var cy := int(size.y / 2.0)
	for dy in range(-half, half + 1):
		var gy := cy + dy
		if gy > 0 and gy < size.y - 1:
			grid[cx][gy] = 1


static func carve_iterative(
	wall_grid: Array,
	start_x: int,
	start_y: int,
	mean_corridor_length: float = 3.0,
	corridor_length_variance: int = 0
) -> void:
	var stack: Array = [{
		"pos": Vector2i(start_x, start_y),
		"incoming": Vector2i.ZERO,
		"run_length": 0,
		"target_run": 0,
	}]
	wall_grid[start_x][start_y] = 0

	while not stack.is_empty():
		var frame: Dictionary = stack[-1]
		var current: Vector2i = frame["pos"]
		var incoming: Vector2i = frame["incoming"]
		var run_length: int = int(frame["run_length"])
		var target_run: int = int(frame["target_run"])
		var gx := current.x
		var gy := current.y

		var directions := _ordered_directions(incoming, run_length, target_run)

		var carved := false
		for dir in directions:
			var nx := gx + dir.x * 2
			var ny := gy + dir.y * 2
			if nx <= 0 or nx >= wall_grid.size() - 1:
				continue
			if ny <= 0 or ny >= wall_grid[0].size() - 1:
				continue
			if wall_grid[nx][ny] == 1:
				wall_grid[gx + dir.x][gy + dir.y] = 0
				wall_grid[nx][ny] = 0
				var next_run := 1
				var next_target := target_run
				if dir == incoming and incoming != Vector2i.ZERO:
					next_run = run_length + 1
				else:
					next_target = _sample_corridor_target(
						mean_corridor_length, corridor_length_variance
					)
				stack.append({
					"pos": Vector2i(nx, ny),
					"incoming": dir,
					"run_length": next_run,
					"target_run": next_target,
				})
				carved = true
				break

		if not carved:
			stack.pop_back()


static func _sample_corridor_target(mean_corridor_length: float, variance: int) -> int:
	var center := maxi(1, int(round(mean_corridor_length)))
	var spread := maxi(0, variance)
	var lo := maxi(1, center - spread)
	var hi := maxi(lo, center + spread)
	return randi_range(lo, hi)

static func add_spire_clearing(
	wall_grid: Array,
	maze_width: int,
	maze_height: int,
	size: float,
	placed: Array[Dictionary] = []
) -> void:
	## Fixed square clearing at maze center. Size is radius in maze cells; 0 skips.
	var radius := spire_radius_cells(size)
	if radius <= 0:
		return
	if wall_grid.is_empty() or maze_width < 1 or maze_height < 1:
		return

	var grid_w: int = wall_grid.size()
	var grid_h: int = wall_grid[0].size()
	var center_cell := spire_center_maze_cell(maze_width, maze_height)
	var center := Vector2i(center_cell.x * 2 + 1, center_cell.y * 2 + 1)
	var extent := radius * 2
	_open_clearing_square(wall_grid, grid_w, grid_h, center, extent)
	placed.append({"center": center, "extent": extent})


static func spire_radius_cells(size: float) -> int:
	if size <= 0.0:
		return 0
	return maxi(1, int(round(size)))


static func spire_center_maze_cell(maze_width: int, maze_height: int) -> Vector2i:
	return Vector2i(int(maze_width / 2.0), int(maze_height / 2.0))


static func is_maze_cell_in_spire_clearing(
	cell: Vector2i,
	maze_width: int,
	maze_height: int,
	spire_size: float
) -> bool:
	var radius := spire_radius_cells(spire_size)
	if radius <= 0:
		return false
	var center := spire_center_maze_cell(maze_width, maze_height)
	return maxi(absi(cell.x - center.x), absi(cell.y - center.y)) <= radius


static func add_clearings(
	wall_grid: Array,
	maze_width: int,
	maze_height: int,
	count: int,
	size: float,
	separation: float = 0.0,
	placed: Array[Dictionary] = []
) -> void:
	## Places up to `count` clearings in each maze quadrant (centers stay in-quadrant).
	## Prefers centers at least `separation` maze cells from other clearings (incl. spire).
	if count <= 0 or size <= 0.0:
		return
	if wall_grid.is_empty() or maze_width < 1 or maze_height < 1:
		return

	var grid_w: int = wall_grid.size()
	var grid_h: int = wall_grid[0].size()
	var mid_x := int(maze_width / 2.0)
	var mid_y := int(maze_height / 2.0)
	var quadrants: Array[Dictionary] = [
		{"x0": 0, "x1": mid_x, "y0": 0, "y1": mid_y},
		{"x0": mid_x, "x1": maze_width, "y0": 0, "y1": mid_y},
		{"x0": 0, "x1": mid_x, "y0": mid_y, "y1": maze_height},
		{"x0": mid_x, "x1": maze_width, "y0": mid_y, "y1": maze_height},
	]
	var max_attempts := maxi(count * 32, 64)

	for quadrant in quadrants:
		var x0: int = int(quadrant["x0"])
		var x1: int = int(quadrant["x1"])
		var y0: int = int(quadrant["y0"])
		var y1: int = int(quadrant["y1"])
		if x1 <= x0 or y1 <= y0:
			continue
		for _i in count:
			var best_center := Vector2i.ZERO
			var best_extent := 0
			var best_score := -1.0
			var found := false
			for _attempt in max_attempts:
				var cell_x := randi_range(x0, x1 - 1)
				var cell_y := randi_range(y0, y1 - 1)
				var center := Vector2i(cell_x * 2 + 1, cell_y * 2 + 1)
				var radius_cells := maxi(1, int(round(size * randf_range(0.6, 1.4))))
				var extent := radius_cells * 2
				if _clearing_overlaps_any(placed, center, extent):
					continue
				## Soft target around the average separation; hard floor at half.
				var target_sep := 0.0
				if separation > 0.0:
					target_sep = separation * randf_range(0.75, 1.25)
				var min_dist := _min_clearing_center_distance(placed, center)
				if separation > 0.0 and min_dist < separation * 0.5:
					continue
				var score := min_dist
				if min_dist >= target_sep:
					score += 1000.0
				if not found or score > best_score:
					best_center = center
					best_extent = extent
					best_score = score
					found = true
					if min_dist >= target_sep and target_sep > 0.0:
						break
					if separation <= 0.0:
						break
			if not found:
				## This quadrant is too packed for another spaced clearing.
				break
			_open_clearing_square(wall_grid, grid_w, grid_h, best_center, best_extent)
			placed.append({"center": best_center, "extent": best_extent})


static func _min_clearing_center_distance(placed: Array[Dictionary], center: Vector2i) -> float:
	if placed.is_empty():
		return INF
	var best := INF
	for entry in placed:
		var other_center: Vector2i = entry["center"]
		best = minf(best, _clearing_center_maze_distance(center, other_center))
	return best


static func _clearing_center_maze_distance(a: Vector2i, b: Vector2i) -> float:
	## Wall-grid centers are two steps per maze cell; Chebyshev distance in maze cells.
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return float(maxi(dx, dy)) / 2.0


static func _clearing_overlaps_any(
	placed: Array[Dictionary],
	center: Vector2i,
	extent: int
) -> bool:
	for entry in placed:
		var other_center: Vector2i = entry["center"]
		var other_extent: int = int(entry["extent"])
		if _clearing_squares_overlap(center, extent, other_center, other_extent):
			return true
	return false


static func _clearing_squares_overlap(
	a_center: Vector2i,
	a_extent: int,
	b_center: Vector2i,
	b_extent: int
) -> bool:
	## Chebyshev squares share a cell when center distance <= sum of extents.
	var dx := absi(a_center.x - b_center.x)
	var dy := absi(a_center.y - b_center.y)
	return maxi(dx, dy) <= a_extent + b_extent


static func _open_clearing_square(
	wall_grid: Array,
	grid_w: int,
	grid_h: int,
	center: Vector2i,
	extent: int
) -> void:
	for dx in range(-extent, extent + 1):
		for dy in range(-extent, extent + 1):
			if maxi(absi(dx), absi(dy)) > extent:
				continue
			var gx := center.x + dx
			var gy := center.y + dy
			if gx <= 0 or gx >= grid_w - 1:
				continue
			if gy <= 0 or gy >= grid_h - 1:
				continue
			wall_grid[gx][gy] = 0


static func count_open_neighbors(wall_grid: Array, gx: int, gy: int) -> int:
	## Counts reachable neighboring maze cells from a passage cell at (gx, gy).
	if wall_grid.is_empty():
		return 0

	var open := 0
	var grid_w: int = wall_grid.size()
	var grid_h: int = wall_grid[0].size()

	for dir in DIRS:
		var passage_x: int = gx + dir.x
		var passage_y: int = gy + dir.y
		var cell_x: int = gx + dir.x * 2
		var cell_y: int = gy + dir.y * 2
		if passage_x <= 0 or passage_x >= grid_w - 1:
			continue
		if passage_y <= 0 or passage_y >= grid_h - 1:
			continue
		if cell_x <= 0 or cell_x >= grid_w - 1:
			continue
		if cell_y <= 0 or cell_y >= grid_h - 1:
			continue
		if wall_grid[passage_x][passage_y] != 0:
			continue
		if wall_grid[cell_x][cell_y] != 0:
			continue
		open += 1
	return open


static func grid_size_for(maze_width: int, maze_height: int) -> Vector2i:
	return Vector2i(maze_width * 2 + 1, maze_height * 2 + 1)


static func count_carved_cells(wall_grid: Array, maze_width: int, maze_height: int) -> int:
	var carved := 0
	for cell_y in maze_height:
		for cell_x in maze_width:
			var gx := cell_x * 2 + 1
			var gy := cell_y * 2 + 1
			if wall_grid[gx][gy] == 0:
				carved += 1
	return carved


static func count_open_wall_cells(wall_grid: Array) -> int:
	var open := 0
	for x in wall_grid.size():
		for y in wall_grid[x].size():
			if wall_grid[x][y] == 0:
				open += 1
	return open


static func mean_straight_run_length(wall_grid: Array, maze_width: int, maze_height: int) -> float:
	## Average consecutive steps in one direction across maze-cell corridors.
	var total_run := 0
	var run_count := 0
	for cell_y in maze_height:
		for cell_x in maze_width:
			var gx := cell_x * 2 + 1
			var gy := cell_y * 2 + 1
			if wall_grid[gx][gy] != 0:
				continue
			## Horizontal runs: measure eastward from cells with no west open neighbor.
			if not _has_open_neighbor(wall_grid, gx, gy, Vector2i(-1, 0)):
				var run := 1
				var cx := gx
				var cy := gy
				while _has_open_neighbor(wall_grid, cx, cy, Vector2i(1, 0)):
					cx += 2
					run += 1
				if run > 1:
					total_run += run
					run_count += 1
			## Vertical runs: measure southward from cells with no north open neighbor.
			if not _has_open_neighbor(wall_grid, gx, gy, Vector2i(0, -1)):
				var run_v := 1
				var vx := gx
				var vy := gy
				while _has_open_neighbor(wall_grid, vx, vy, Vector2i(0, 1)):
					vy += 2
					run_v += 1
				if run_v > 1:
					total_run += run_v
					run_count += 1
	if run_count == 0:
		return 0.0
	return float(total_run) / float(run_count)


static func outer_boundary_is_solid(wall_grid: Array) -> bool:
	if wall_grid.is_empty():
		return false

	var grid_w: int = wall_grid.size()
	var grid_h: int = wall_grid[0].size()

	for x in grid_w:
		if wall_grid[x][0] != 1 or wall_grid[x][grid_h - 1] != 1:
			return false

	for y in grid_h:
		if wall_grid[0][y] != 1 or wall_grid[grid_w - 1][y] != 1:
			return false

	return true


static func all_cells_reachable(wall_grid: Array, maze_width: int, maze_height: int) -> bool:
	var start := Vector2i(1, 1)
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	visited[_cell_key(start.x, start.y)] = true
	var reachable := 0

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		reachable += 1

		for dir in DIRS:
			var passage := Vector2i(current.x + dir.x, current.y + dir.y)
			var next_cell := Vector2i(current.x + dir.x * 2, current.y + dir.y * 2)
			if not _is_cell_in_maze(next_cell.x, next_cell.y, maze_width, maze_height):
				continue
			if wall_grid[passage.x][passage.y] != 0:
				continue
			if wall_grid[next_cell.x][next_cell.y] != 0:
				continue

			var key := _cell_key(next_cell.x, next_cell.y)
			if visited.has(key):
				continue
			visited[key] = true
			queue.append(next_cell)

	return reachable == maze_width * maze_height


static func grids_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false

	for x in a.size():
		if a[x].size() != b[x].size():
			return false
		for y in a[x].size():
			if a[x][y] != b[x][y]:
				return false

	return true


static func _ordered_directions(
	incoming: Vector2i,
	run_length: int,
	target_run: int
) -> Array[Vector2i]:
	var directions: Array[Vector2i] = []
	for dir in DIRS:
		directions.append(dir)
	directions.shuffle()

	if incoming == Vector2i.ZERO:
		return directions

	var goal := maxi(target_run, 1)
	var prefer_straight := run_length < goal
	for i in directions.size():
		if directions[i] != incoming:
			continue
		var chosen: Vector2i = directions[i]
		directions.remove_at(i)
		if prefer_straight:
			directions.insert(0, chosen)
		else:
			directions.append(chosen)
		break

	return directions


static func _has_open_neighbor(
	wall_grid: Array,
	gx: int,
	gy: int,
	dir: Vector2i
) -> bool:
	var passage := Vector2i(gx + dir.x, gy + dir.y)
	var next_cell := Vector2i(gx + dir.x * 2, gy + dir.y * 2)
	var grid_w: int = wall_grid.size()
	var grid_h: int = wall_grid[0].size()
	if passage.x <= 0 or passage.x >= grid_w - 1:
		return false
	if passage.y <= 0 or passage.y >= grid_h - 1:
		return false
	if next_cell.x <= 0 or next_cell.x >= grid_w - 1:
		return false
	if next_cell.y <= 0 or next_cell.y >= grid_h - 1:
		return false
	return wall_grid[passage.x][passage.y] == 0 and wall_grid[next_cell.x][next_cell.y] == 0


static func _create_wall_grid(maze_width: int, maze_height: int) -> Array:
	var size := grid_size_for(maze_width, maze_height)
	var grid_w: int = size.x
	var grid_h: int = size.y

	var grid: Array = []
	grid.resize(grid_w)
	for x in grid_w:
		grid[x] = []
		grid[x].resize(grid_h)
		for y in grid_h:
			grid[x][y] = 1

	return grid


static func _is_cell_in_maze(gx: int, gy: int, maze_width: int, maze_height: int) -> bool:
	var cell_x: int = (gx - 1) >> 1
	var cell_y: int = (gy - 1) >> 1
	return cell_x >= 0 and cell_y >= 0 and cell_x < maze_width and cell_y < maze_height


static func _cell_key(gx: int, gy: int) -> String:
	return "%d,%d" % [gx, gy]
