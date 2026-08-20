class_name ObjectivePlacement
extends RefCounted

const MazeCarverScript := preload("res://scripts/maze_carver.gd")

const PLACEMENT_SALT := "delivery_objective"
const MIN_ITEM_DISTANCE_CELLS := 6
const MIN_TURN_IN_DISTANCE_CELLS := 10


static func derive_seed(run_seed: int) -> int:
	return hash("%d:%s" % [run_seed, PLACEMENT_SALT])


static func plan(
	wall_grid: Array,
	maze_width: int,
	maze_height: int,
	spawn_cell: Vector2i,
	run_seed: int,
	spawn_relic_near_spawn: bool = false,
	spire_clearing_size: float = 0.0
) -> Dictionary:
	var reachable := DiscoverableSpawnPlan.collect_reachable_cells(
		wall_grid,
		maze_width,
		maze_height,
		spawn_cell
	)
	if reachable.size() < 2:
		return {}

	var outside_spire := _cells_outside_spire(
		reachable, maze_width, maze_height, spire_clearing_size
	)
	## Prefer the whole maze only if the spire somehow covers every reachable cell.
	var pool: Array[Vector2i] = outside_spire if outside_spire.size() >= 2 else reachable

	if spawn_relic_near_spawn:
		return _plan_near_spawn(
			pool, spawn_cell, run_seed, maze_width, maze_height, spire_clearing_size
		)

	var rng := RandomNumberGenerator.new()
	rng.seed = derive_seed(run_seed)

	var item_candidates: Array[Vector2i] = []
	for cell in pool:
		if cell.distance_to(spawn_cell) >= MIN_ITEM_DISTANCE_CELLS:
			item_candidates.append(cell)
	if item_candidates.is_empty():
		item_candidates = pool.duplicate()

	var item_cell: Vector2i = item_candidates[rng.randi_range(0, item_candidates.size() - 1)]

	var turn_in_candidates: Array[Vector2i] = []
	for cell in pool:
		if cell == item_cell:
			continue
		if cell.distance_to(spawn_cell) >= MIN_TURN_IN_DISTANCE_CELLS:
			turn_in_candidates.append(cell)
	if turn_in_candidates.is_empty():
		for cell in pool:
			if cell != item_cell:
				turn_in_candidates.append(cell)
	if turn_in_candidates.is_empty():
		return {}

	var turn_in_cell: Vector2i = turn_in_candidates[
		rng.randi_range(0, turn_in_candidates.size() - 1)
	]
	return {
		"item_cell": item_cell,
		"turn_in_cell": turn_in_cell,
	}


static func _plan_near_spawn(
	pool: Array[Vector2i],
	spawn_cell: Vector2i,
	run_seed: int,
	maze_width: int,
	maze_height: int,
	spire_clearing_size: float
) -> Dictionary:
	## Dev shortcut: relic near spawn (spawn is never the spire on normal maps).
	var item_cell := _nearest_reachable_cell(pool, spawn_cell)

	var turn_in_candidates: Array[Vector2i] = []
	for cell in pool:
		if cell == item_cell:
			continue
		if MazeCarverScript.is_maze_cell_in_spire_clearing(
			cell, maze_width, maze_height, spire_clearing_size
		):
			continue
		if cell.distance_to(spawn_cell) >= MIN_TURN_IN_DISTANCE_CELLS:
			turn_in_candidates.append(cell)
	if turn_in_candidates.is_empty():
		for cell in pool:
			if cell == item_cell:
				continue
			if MazeCarverScript.is_maze_cell_in_spire_clearing(
				cell, maze_width, maze_height, spire_clearing_size
			):
				continue
			turn_in_candidates.append(cell)
	if turn_in_candidates.is_empty():
		for cell in pool:
			if cell != item_cell:
				turn_in_candidates.append(cell)
	if turn_in_candidates.is_empty():
		return {}

	var rng := RandomNumberGenerator.new()
	rng.seed = derive_seed(run_seed)
	var turn_in_cell: Vector2i = turn_in_candidates[
		rng.randi_range(0, turn_in_candidates.size() - 1)
	]
	return {
		"item_cell": item_cell,
		"turn_in_cell": turn_in_cell,
	}


static func _cells_outside_spire(
	cells: Array[Vector2i],
	maze_width: int,
	maze_height: int,
	spire_clearing_size: float
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in cells:
		if MazeCarverScript.is_maze_cell_in_spire_clearing(
			cell, maze_width, maze_height, spire_clearing_size
		):
			continue
		result.append(cell)
	return result


static func _nearest_reachable_cell(
	reachable: Array[Vector2i],
	target_cell: Vector2i
) -> Vector2i:
	for cell in reachable:
		if cell == target_cell:
			return target_cell

	var nearest: Vector2i = reachable[0]
	var nearest_score := nearest.distance_to(target_cell)
	for cell in reachable:
		var score := cell.distance_to(target_cell)
		if score < nearest_score:
			nearest_score = score
			nearest = cell
	return nearest
