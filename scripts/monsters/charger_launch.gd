class_name ChargerLaunch
extends RefCounted

## Pure helpers for Charger ram speed, maze-safe landings, and launch arcs.

const CHARGE_SPEED_MULT := 2.0
const MIN_CELL_DISTANCE := 2
const DEFAULT_CELL_SIZE_M := 3.0
const MIN_FLIGHT_SEC := 0.7
const MAX_FLIGHT_SEC := 1.35
const FLIGHT_DIST_REF_M := 12.0


static func charge_speed(sprint_speed: float) -> float:
	return maxf(0.0, sprint_speed) * CHARGE_SPEED_MULT


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func is_open_cell(wall_grid: Array, cell: Vector2i) -> bool:
	if wall_grid.is_empty():
		return false
	if cell.x < 0 or cell.x >= wall_grid.size():
		return false
	var row: Array = wall_grid[cell.x]
	if cell.y < 0 or cell.y >= row.size():
		return false
	return int(row[cell.y]) == 0


static func collect_landing_cells(
	wall_grid: Array, from_cell: Vector2i, min_dist: int = MIN_CELL_DISTANCE
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var need := maxi(min_dist, 1)
	for gx in wall_grid.size():
		var row: Array = wall_grid[gx]
		for gy in row.size():
			var cell := Vector2i(gx, gy)
			if not is_open_cell(wall_grid, cell):
				continue
			if chebyshev(from_cell, cell) < need:
				continue
			out.append(cell)
	return out


static func pick_landing_cell(
	cells: Array[Vector2i], rng: RandomNumberGenerator, used: Dictionary = {}
) -> Vector2i:
	if cells.is_empty():
		return Vector2i.ZERO
	var unused: Array[Vector2i] = []
	for cell in cells:
		if not used.has(cell):
			unused.append(cell)
	var pool: Array[Vector2i] = unused if not unused.is_empty() else cells
	var idx := 0
	if rng != null:
		idx = rng.randi_range(0, pool.size() - 1)
	return pool[idx]


static func flight_time_for_distance(horiz_m: float) -> float:
	var t := clampf(horiz_m / FLIGHT_DIST_REF_M, 0.0, 1.0)
	return lerpf(MIN_FLIGHT_SEC, MAX_FLIGHT_SEC, t)


static func launch_velocity(
	from_pos: Vector3, to_pos: Vector3, gravity: float, flight_sec: float
) -> Vector3:
	var t := maxf(flight_sec, 0.05)
	var vx := (to_pos.x - from_pos.x) / t
	var vz := (to_pos.z - from_pos.z) / t
	var vy := (to_pos.y - from_pos.y + 0.5 * gravity * t * t) / t
	return Vector3(vx, vy, vz)


static func integrate_launch(
	from_pos: Vector3, velocity: Vector3, gravity: float, flight_sec: float
) -> Vector3:
	var t := maxf(flight_sec, 0.0)
	return Vector3(
		from_pos.x + velocity.x * t,
		from_pos.y + velocity.y * t - 0.5 * gravity * t * t,
		from_pos.z + velocity.z * t
	)


static func fallback_landing(
	from_pos: Vector3, away_dir: Vector3, cell_size: float = DEFAULT_CELL_SIZE_M
) -> Vector3:
	var flat := Vector3(away_dir.x, 0.0, away_dir.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	else:
		flat = flat.normalized()
	var dist := maxf(cell_size, 0.1) * float(MIN_CELL_DISTANCE)
	return from_pos + flat * dist


static func resolve_landing_world(
	maze: Node,
	from_world: Vector3,
	away_dir: Vector3,
	rng: RandomNumberGenerator,
	used_cells: Dictionary = {}
) -> Vector3:
	if maze == null or not maze.has_method("get_wall_grid"):
		return fallback_landing(from_world, away_dir)
	var wall_grid: Array = maze.call("get_wall_grid")
	if wall_grid.is_empty():
		return fallback_landing(from_world, away_dir)
	var from_cell: Vector2i = maze.call("world_to_cell", from_world)
	if not is_open_cell(wall_grid, from_cell) and maze.has_method("world_to_cell"):
		from_cell = _nearest_open_cell(wall_grid, from_cell)
	var cells := collect_landing_cells(wall_grid, from_cell)
	if cells.is_empty():
		return fallback_landing(from_world, away_dir)
	var cell := pick_landing_cell(cells, rng, used_cells)
	used_cells[cell] = true
	var world: Vector3 = maze.call("grid_to_world", cell.x, cell.y)
	world.y = from_world.y
	return world


static func _nearest_open_cell(wall_grid: Array, start: Vector2i) -> Vector2i:
	if is_open_cell(wall_grid, start):
		return start
	for radius in range(1, 24):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var cell := Vector2i(start.x + dx, start.y + dy)
				if is_open_cell(wall_grid, cell):
					return cell
	return start
