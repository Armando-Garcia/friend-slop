class_name MazeHole
extends Node3D

## Gnome tunnel spliced into one wall cell — wall frame + open bore through both sides.

const MazeHoleWallPieceScript := preload("res://scripts/maze/maze_hole_wall_piece.gd")
const MazeHoleGateScript := preload("res://scripts/maze/maze_hole_gate.gd")

const HOLE_WIDTH := 0.68
const HOLE_RECT_HEIGHT := 0.52
const HOLE_ARCH_RADIUS := HOLE_WIDTH * 0.5
const HOLE_ARCH_SEGMENTS := 10

const TUNNEL_COLOR := Color(0.12, 0.1, 0.14)


static func opening_total_height() -> float:
	return HOLE_RECT_HEIGHT + HOLE_ARCH_RADIUS


static func spawn(
	parent: Node,
	world_pos: Vector3,
	facing: Vector3 = Vector3.FORWARD,
	cell_size: float = 3.0,
	wall_height: float = 3.0,
	wall_cell: Vector2i = Vector2i(-999, -999)
) -> Node:
	var hole := Node3D.new()
	hole.set_script(load("res://scripts/maze/maze_hole.gd"))
	if parent != null:
		parent.add_child(hole)
	if hole is Node3D:
		var node := hole as Node3D
		if node.is_inside_tree():
			node.global_position = world_pos
		else:
			node.position = world_pos
		var flat := Vector3(facing.x, 0.0, facing.z)
		if flat.length_squared() > 0.0001:
			var look_from := node.global_position if node.is_inside_tree() else node.position
			var look_at_pos := look_from - flat.normalized()
			if node.is_inside_tree():
				node.look_at(look_at_pos, Vector3.UP)
			else:
				node.look_at_from_position(look_from, look_at_pos, Vector3.UP)
	hole.set_meta("_cell_size", cell_size)
	hole.set_meta("_wall_height", wall_height)
	hole.set_meta("_wall_cell", wall_cell)
	if hole.has_method("_build_geometry"):
		hole.call("_build_geometry")
	hole.add_to_group("maze_hole")
	return hole


func burrow_waypoints(body_y: float) -> Array:
	var cell_size := float(get_meta("_cell_size", 3.0))
	var inset := maxf(cell_size * 0.5 - 0.25, 0.75)
	var xform := global_transform if is_inside_tree() else transform
	var corridor := -xform.basis.z
	var center := xform.origin
	var approach := center - corridor * inset
	var exit_pos := center + corridor * inset
	approach.y = body_y
	exit_pos.y = body_y
	center.y = body_y
	return [approach, center, exit_pos]


func _build_geometry() -> void:
	var cell_size := float(get_meta("_cell_size", 3.0))
	var wall_height := float(get_meta("_wall_height", 3.0))
	var total_h := opening_total_height()

	var splice := Node3D.new()
	splice.name = "WallSplice"
	add_child(splice)
	MazeHoleWallPieceScript.build_tunnel(splice, cell_size)

	var gate := Area3D.new()
	gate.name = "Gate"
	gate.set_script(MazeHoleGateScript)
	var gate_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(HOLE_WIDTH, total_h, cell_size * 0.45)
	gate_shape.shape = box
	gate_shape.position = Vector3(0.0, total_h * 0.5, 0.0)
	gate.add_child(gate_shape)
	add_child(gate)
