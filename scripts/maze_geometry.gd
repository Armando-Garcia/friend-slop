class_name MazeGeometry
extends RefCounted

## Shared maze floor + wall construction (mesh, materials, box colliders).

const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")
const MazeWallMeshScript := preload("res://scripts/maze_wall_mesh.gd")

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
	var mesh: ArrayMesh = MazeWallMeshScript.build(wall_grid, wall_size, cell_to_world_fn)

	var body := StaticBody3D.new()
	body.name = "Walls"
	body.collision_layer = 1
	body.collision_mask = 0

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = WALL_COLOR
	material.roughness = 0.7
	mesh_instance.material_override = material
	mesh_instance.layers = WorldVisualLayersScript.WORLD
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(mesh_instance)

	var shared_shape := BoxShape3D.new()
	shared_shape.size = wall_size
	var half_height := wall_height * 0.5
	for gx in wall_grid.size():
		for gy in wall_grid[gx].size():
			if wall_grid[gx][gy] != 1:
				continue
			var collision := CollisionShape3D.new()
			collision.shape = shared_shape
			collision.debug_color = WALL_COLLISION_DEBUG
			var center: Vector3 = grid_to_world(
				gx, gy, maze_width, maze_height, cell_size
			)
			center.y = half_height
			collision.position = center
			body.add_child(collision)

	parent.add_child(body)
	return body
