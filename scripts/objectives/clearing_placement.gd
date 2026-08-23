class_name ClearingPlacement
extends RefCounted

## Finds procedurally-carved clearings (open squares placed per maze quadrant —
## distinct from the fixed spire clearing at maze center) so objectives can
## spawn into them.

const MazePathGraphScript := preload("res://scripts/maze_path_graph.gd")


## Returns {} if the maze has no clearings, otherwise:
## {
##   "origin": Vector3,  ## world-space min corner (Y = 0)
##   "size": Vector3,    ## world-space footprint (Y = 0)
##   "center": Vector3,  ## world-space footprint center (Y = 0)
## }
static func largest_clearing(
	wall_grid: Array,
	maze_width: int,
	maze_height: int,
	cell_size: float
) -> Dictionary:
	var graph := MazePathGraphScript.build(wall_grid, maze_width, maze_height, cell_size)
	return largest_clearing_from_graph(graph)


static func largest_clearing_from_graph(graph: Dictionary) -> Dictionary:
	var best_area := 0.0
	var best: Dictionary = {}
	for rect in graph.get("clearing_rects", []):
		var size: Vector3 = rect["size"]
		var area := size.x * size.z
		if area <= best_area:
			continue
		best_area = area
		var origin: Vector3 = rect["origin"]
		best = {
			"origin": origin,
			"size": size,
			"center": origin + Vector3(size.x * 0.5, 0.0, size.z * 0.5),
		}
	return best
