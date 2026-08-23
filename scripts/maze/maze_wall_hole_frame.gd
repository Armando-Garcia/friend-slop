class_name MazeWallHoleFrame
extends RefCounted

## Per-cell wall collision; carve only the square+dome tunnel cross-section.

const MazeHoleScript := preload("res://scripts/maze/maze_hole.gd")
const MazeGeometryScript := preload("res://scripts/maze_geometry.gd")

const WALL_CELL_META := &"wall_cell"
const TUNNEL_FRAGMENT_META := &"tunnel_fragment"


static func add_per_cell_collision(
	body: Node3D,
	wall_grid: Array,
	maze_width: int,
	maze_height: int,
	cell_size: float,
	wall_height: float
) -> void:
	if wall_grid.is_empty():
		return
	for gx in wall_grid.size():
		var row: Array = wall_grid[gx]
		for gy in row.size():
			if int(row[gy]) != 1:
				continue
			var cell := Vector2i(gx, gy)
			var center := MazeGeometryScript.grid_to_world(
				gx, gy, maze_width, maze_height, cell_size
			)
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(cell_size, wall_height, cell_size)
			col.shape = shape
			col.position = Vector3(center.x, wall_height * 0.5, center.z)
			col.set_meta(WALL_CELL_META, cell)
			body.add_child(col)


## Replace the solid cell collider with slabs outside the tunnel profile only.
static func carve_tunnel_passage(
	walls: Node,
	cell: Vector2i,
	center: Vector3,
	facing: Vector3,
	cell_size: float,
	wall_height: float
) -> bool:
	if walls == null or cell.x < -900:
		return false
	if not _remove_cell_collision(walls, cell):
		return false

	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	else:
		flat = flat.normalized()
	var through := -flat
	var side := Vector3(-through.z, 0.0, through.x)

	var half_cell := cell_size * 0.5
	var half_w := MazeHoleScript.HOLE_WIDTH * 0.5
	var side_w := half_cell - half_w
	var total_h := MazeHoleScript.opening_total_height()
	var lintel_h := maxf(wall_height - total_h, 0.05)
	if side_w < 0.02:
		return false

	_add_tunnel_fragment(
		walls,
		cell,
		center,
		side,
		through,
		Vector3(side_w, wall_height, cell_size),
		side * (-half_w - side_w * 0.5) + Vector3(0.0, wall_height * 0.5, 0.0)
	)
	_add_tunnel_fragment(
		walls,
		cell,
		center,
		side,
		through,
		Vector3(side_w, wall_height, cell_size),
		side * (half_w + side_w * 0.5) + Vector3(0.0, wall_height * 0.5, 0.0)
	)
	_add_tunnel_fragment(
		walls,
		cell,
		center,
		side,
		through,
		Vector3(cell_size, lintel_h, cell_size),
		Vector3(0.0, total_h + lintel_h * 0.5, 0.0)
	)
	return true


static func _remove_cell_collision(walls: Node, cell: Vector2i) -> bool:
	var found := false
	for child in walls.get_children():
		if not (child is CollisionShape3D):
			continue
		if bool(child.get_meta(TUNNEL_FRAGMENT_META, false)):
			continue
		if child.get_meta(WALL_CELL_META, Vector2i(-999, -999)) != cell:
			continue
		child.queue_free()
		found = true
	return found


static func _add_tunnel_fragment(
	walls: Node,
	cell: Vector2i,
	center: Vector3,
	side: Vector3,
	through: Vector3,
	size: Vector3,
	local_offset: Vector3
) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	var basis := Basis(side, Vector3.UP, through)
	col.transform = Transform3D(basis, center + basis * local_offset)
	col.set_meta(WALL_CELL_META, cell)
	col.set_meta(TUNNEL_FRAGMENT_META, true)
	walls.add_child(col)
