@tool
class_name MazeKeepIn
extends Node3D

## Tall keep-in collision around the maze. Visuals are reusable ForceField panes.

const ForceFieldScene := preload("res://scenes/fx/force_field.tscn")
const MazeGeometryScript := preload("res://scripts/maze_geometry.gd")
const SlideSurfaceScript := preload("res://scripts/slide_surface.gd")

const HEIGHT_M := 24.0
const THICKNESS_M := 0.9


func build(maze_width: int, maze_height: int, cell_size: float) -> void:
	for child in get_children():
		child.free()
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	SlideSurfaceScript.tag(body)
	add_child(body)
	var extents := MazeGeometryScript.xz_extents(maze_width, maze_height, cell_size)
	var min_x := extents.position.x
	var max_x := extents.position.x + extents.size.x
	var min_z := extents.position.y
	var max_z := extents.position.y + extents.size.y
	var mid_x := (min_x + max_x) * 0.5
	var mid_z := (min_z + max_z) * 0.5
	var span_x := max_x - min_x
	var span_z := max_z - min_z
	_add_wall(
		body,
		Vector3(mid_x, HEIGHT_M * 0.5, min_z - THICKNESS_M * 0.5),
		Vector3(span_x + THICKNESS_M * 2.0, HEIGHT_M, THICKNESS_M),
		Vector3(0.0, 0.0, 1.0)
	)
	_add_wall(
		body,
		Vector3(mid_x, HEIGHT_M * 0.5, max_z + THICKNESS_M * 0.5),
		Vector3(span_x + THICKNESS_M * 2.0, HEIGHT_M, THICKNESS_M),
		Vector3(0.0, 0.0, -1.0)
	)
	_add_wall(
		body,
		Vector3(min_x - THICKNESS_M * 0.5, HEIGHT_M * 0.5, mid_z),
		Vector3(THICKNESS_M, HEIGHT_M, span_z),
		Vector3(1.0, 0.0, 0.0)
	)
	_add_wall(
		body,
		Vector3(max_x + THICKNESS_M * 0.5, HEIGHT_M * 0.5, mid_z),
		Vector3(THICKNESS_M, HEIGHT_M, span_z),
		Vector3(-1.0, 0.0, 0.0)
	)


func _add_wall(
	body: StaticBody3D, center: Vector3, size: Vector3, inward: Vector3
) -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position = center
	body.add_child(col)
	var field := ForceFieldScene.instantiate() as ForceField
	add_child(field)
	field.fit_wall(center, size, inward)
