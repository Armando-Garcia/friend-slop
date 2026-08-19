class_name MazeGeometry
extends RefCounted

## Shared maze floor + wall construction (mesh, materials, colliders).

const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")
const MazeWallMeshScript := preload("res://scripts/maze_wall_mesh.gd")
const SlideSurfaceScript := preload("res://scripts/slide_surface.gd")

const FLOOR_COLOR := Color(0.18, 0.15, 0.22)
const WALL_COLOR := Color(0.52, 0.46, 0.58)
const WALL_COLLISION_DEBUG := Color(0.1, 0.95, 1.0, 0.32)
const FLOOR_THICKNESS := 0.2


static func maze_offset(maze_width: int, maze_height: int, cell_size: float) -> Vector3:
	var grid_w := maze_width * 2 + 1
	var grid_h := maze_height * 2 + 1
	return Vector3(grid_w * cell_size * 0.5, 0.0, grid_h * cell_size * 0.5)


static func grid_to_world(
	gx: int, gy: int, maze_width: int, maze_height: int, cell_size: float
) -> Vector3:
	var offset := maze_offset(maze_width, maze_height, cell_size)
	return Vector3(gx * cell_size - offset.x, 0.0, gy * cell_size - offset.z)


static func add_floor(
	parent: Node3D, maze_width: int, maze_height: int, cell_size: float
) -> StaticBody3D:
	var grid_w := maze_width * 2 + 1
	var grid_h := maze_height * 2 + 1
	var floor_size := Vector3(grid_w * cell_size, FLOOR_THICKNESS, grid_h * cell_size)

	var body := StaticBody3D.new()
	body.name = "Floor"
	body.collision_layer = 1
	body.collision_mask = 0

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = floor_size
	mesh_instance.mesh = box
	mesh_instance.position.y = -FLOOR_THICKNESS * 0.5

	var material := StandardMaterial3D.new()
	material.albedo_color = FLOOR_COLOR
	material.roughness = 0.85
	mesh_instance.material_override = material
	mesh_instance.layers = WorldVisualLayersScript.WORLD
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = floor_size
	collision.shape = shape
	collision.position.y = -FLOOR_THICKNESS * 0.5

	body.add_child(mesh_instance)
	body.add_child(collision)
	parent.add_child(body)
	return body


static func add_walls(
	parent: Node3D,
	wall_grid: Array,
	maze_width: int,
	maze_height: int,
	cell_size: float,
	wall_height: float
) -> StaticBody3D:
	var wall_size := Vector3(cell_size, wall_height, cell_size)
	var cell_to_world_fn := func(gx: int, gy: int) -> Vector3:
		return grid_to_world(gx, gy, maze_width, maze_height, cell_size)
	var runs: Array = MazeWallMeshScript.collect_runs(wall_grid)
	var joints: Array = MazeWallMeshScript.collect_joints(runs)
	var radius := MazeWallMeshScript.cylinder_radius(cell_size)
	var box_h := maxf(wall_height - radius, 0.2)

	var body := StaticBody3D.new()
	body.name = "Walls"
	body.collision_layer = 1
	body.collision_mask = 0
	body.editor_description = "Maze walls. Players slide; walk input does not apply."
	SlideSurfaceScript.tag(body)

	var material := StandardMaterial3D.new()
	material.albedo_color = WALL_COLOR
	material.roughness = 0.7

	var shaft_xfs: Array[Transform3D] = []
	var cap_xfs: Array[Transform3D] = []
	for run in runs:
		if int(run["length"]) < 2:
			continue
		var pose: Dictionary = MazeWallMeshScript.run_pose(
			run, wall_size, cell_to_world_fn, box_h, radius
		)
		shaft_xfs.append(MazeWallMeshScript.shaft_transform(pose))
		cap_xfs.append(MazeWallMeshScript.cap_transform(pose))
		_add_box_collision(body, pose["box_size"], pose["box_xform"])
		_add_cyl_collision(body, radius, float(pose["cyl_len"]), pose["cyl_xform"])

	var post_xfs: Array[Transform3D] = []
	var ball_xfs: Array[Transform3D] = []
	for cell in joints:
		var joint: Dictionary = MazeWallMeshScript.joint_pose(
			cell, cell_to_world_fn, box_h, radius
		)
		post_xfs.append(MazeWallMeshScript.post_transform(joint))
		ball_xfs.append(MazeWallMeshScript.ball_transform(joint))
		_add_cyl_collision(
			body, radius, float(joint["post_h"]), joint["post_xform"]
		)
		_add_sphere_collision(body, radius, joint["ball_xform"])

	_add_multimesh(
		body, "WallShafts", MazeWallMeshScript.make_shaft_mesh(), shaft_xfs, material
	)
	_add_multimesh(
		body, "WallCaps", MazeWallMeshScript.make_cap_mesh(), cap_xfs, material
	)
	_add_multimesh(
		body, "WallPosts", MazeWallMeshScript.make_post_mesh(), post_xfs, material
	)
	_add_multimesh(
		body, "WallJoints", MazeWallMeshScript.make_ball_mesh(), ball_xfs, material
	)

	parent.add_child(body)
	return body


static func _add_multimesh(
	body: Node3D,
	node_name: String,
	mesh: PrimitiveMesh,
	xforms: Array[Transform3D],
	material: Material
) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = node_name
	inst.multimesh = mm
	inst.material_override = material
	inst.layers = WorldVisualLayersScript.WORLD
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(inst)


static func _add_box_collision(body: Node3D, size: Vector3, xf: Transform3D) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.debug_color = WALL_COLLISION_DEBUG
	col.transform = xf
	body.add_child(col)


static func _add_cyl_collision(
	body: Node3D, radius: float, height: float, xf: Transform3D
) -> void:
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	col.shape = shape
	col.debug_color = WALL_COLLISION_DEBUG
	col.transform = xf
	body.add_child(col)


static func _add_sphere_collision(
	body: Node3D, radius: float, xf: Transform3D
) -> void:
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	col.shape = shape
	col.debug_color = WALL_COLLISION_DEBUG
	col.transform = xf
	body.add_child(col)


static func xz_extents(
	maze_width: int, maze_height: int, cell_size: float
) -> Rect2:
	var cs := maxf(cell_size, 0.1)
	var min_c := grid_to_world(0, 0, maze_width, maze_height, cs)
	var gw := maze_width * 2 + 1
	var gh := maze_height * 2 + 1
	var max_c := grid_to_world(gw - 1, gh - 1, maze_width, maze_height, cs)
	var half := cs * 0.5
	var pos := Vector2(min_c.x - half, min_c.z - half)
	var size := Vector2((max_c.x + half) - pos.x, (max_c.z + half) - pos.y)
	return Rect2(pos, size)


static func add_keep_in(
	parent: Node3D, maze_width: int, maze_height: int, cell_size: float
) -> Node3D:
	## Loaded (not preloaded) to avoid a cycle with MazeKeepIn.
	var script: GDScript = load("res://scripts/maze_keep_in.gd")
	var keep: Node3D = script.new()
	keep.name = "KeepIn"
	parent.add_child(keep)
	keep.call("build", maze_width, maze_height, cell_size)
	return keep
