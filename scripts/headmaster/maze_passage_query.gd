class_name MazePassageQuery
extends RefCounted

## Find open room-to-room passage edge cells in the maze wall grid.


static func is_open_passage_edge(wall_grid: Array, gx: int, gy: int) -> bool:
	if not _in_bounds(wall_grid, gx, gy):
		return false
	if int(wall_grid[gx][gy]) != 0:
		return false
	var even_x := (gx % 2) == 0
	var even_y := (gy % 2) == 0
	# Horizontal corridor between room centers left/right (odd, odd).
	if even_x and not even_y:
		return _is_open(wall_grid, gx - 1, gy) and _is_open(wall_grid, gx + 1, gy)
	# Vertical corridor between room centers above/below.
	if not even_x and even_y:
		return _is_open(wall_grid, gx, gy - 1) and _is_open(wall_grid, gx, gy + 1)
	return false


static func nearest_open_passage_cell(
	wall_grid: Array,
	origin_cell: Vector2i,
	max_radius: int = 8
) -> Vector2i:
	## Returns Vector2i(-1, -1) when no open passage edge is found.
	if is_open_passage_edge(wall_grid, origin_cell.x, origin_cell.y):
		return origin_cell
	var best := Vector2i(-1, -1)
	var best_dist_sq := 1 << 30
	for radius in range(1, maxi(max_radius, 1) + 1):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var cell := Vector2i(origin_cell.x + dx, origin_cell.y + dy)
				if not is_open_passage_edge(wall_grid, cell.x, cell.y):
					continue
				var dist_sq := dx * dx + dy * dy
				if dist_sq < best_dist_sq:
					best_dist_sq = dist_sq
					best = cell
		if best.x >= 0:
			return best
	return best


static func _in_bounds(wall_grid: Array, gx: int, gy: int) -> bool:
	if gx < 0 or gy < 0 or gx >= wall_grid.size():
		return false
	return gy < wall_grid[gx].size()


static func _is_open(wall_grid: Array, gx: int, gy: int) -> bool:
	if not _in_bounds(wall_grid, gx, gy):
		return false
	return int(wall_grid[gx][gy]) == 0
