@tool
class_name PuzzleBasePieceNode
extends Node3D

## One piece of a WizardChallengeHeight tower's ground-level footprint.
## Doubles as:
## - the live, draggable node you place/shape in puzzle_workshop.tscn
## - the node WizardChallengeHeight instantiates at match runtime from a
##   saved PuzzleDefinition
##
## Built entirely from ordinary StaticBody3D children carrying BoxShape3D /
## CylinderShape3D collision (no hand-built SurfaceTool meshes) — a pit is
## non-convex, so a single ConvexPolygonShape3D built from its rim would
## wrongly fill in as a solid disc/box. Position/rotation ARE the node's own
## transform (drag it in the 3D viewport).

const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")

const WALL_THICKNESS := 0.3
const RECT_BASE_THICKNESS := 0.2
const HOLE_FLOOR_THICKNESS := 0.2
const CYLINDER_WALL_SEGMENTS := 16

const BASE_COLOR := Color(0.28, 0.22, 0.4)
const HOLE_COLOR := Color(0.16, 0.13, 0.22)

@export var shape: PuzzleBasePieceEntry.Shape = PuzzleBasePieceEntry.Shape.RECT_BASE:
	set(value):
		shape = value
		_rebuild()
## RECT_BASE: (length, unused, width). RECT_HOLE: (length, depth, width).
## CYLINDER_HOLE: (radius, depth, unused).
@export var size: Vector3 = Vector3(5.4, 0.2, 5.4):
	set(value):
		size = value
		_rebuild()

var _built: Node3D


func _ready() -> void:
	if _built == null:
		_rebuild()


## --- Saved-puzzle <-> live-node conversion --------------------------------

static func from_entry(entry: PuzzleBasePieceEntry) -> PuzzleBasePieceNode:
	var node := PuzzleBasePieceNode.new()
	node.apply_entry(entry)
	return node


func apply_entry(entry: PuzzleBasePieceEntry) -> void:
	position = entry.position
	rotation = Vector3(0.0, deg_to_rad(entry.rotation_y_degrees), 0.0)
	shape = entry.shape
	size = entry.size
	_rebuild()


func to_entry() -> PuzzleBasePieceEntry:
	var entry := PuzzleBasePieceEntry.new()
	entry.position = position
	entry.rotation_y_degrees = rad_to_deg(rotation.y)
	entry.shape = shape
	entry.size = size
	return entry


## --- Visual / collider -----------------------------------------------------

func _rebuild() -> void:
	if not is_inside_tree() and _built == null:
		## Called from a setter before _ready(); defer to _ready().
		return
	_clear_built()
	_built = Node3D.new()
	_built.name = "Built"
	add_child(_built)

	match shape:
		PuzzleBasePieceEntry.Shape.RECT_HOLE:
			_build_rect_hole()
		PuzzleBasePieceEntry.Shape.CYLINDER_HOLE:
			_build_cylinder_hole()
		_:
			_build_rect_base()


func _clear_built() -> void:
	if _built != null and is_instance_valid(_built):
		_built.free()
	_built = null


func _build_rect_base() -> void:
	var length := maxf(size.x, 0.2)
	var width := maxf(size.z, 0.2)
	_add_box_body(
		"Base",
		Vector3(length, RECT_BASE_THICKNESS, width),
		## Top face sits a hair above the ground plane to avoid z-fighting.
		Vector3(0.0, -0.08, 0.0),
		BASE_COLOR
	)


func _build_rect_hole() -> void:
	var length := maxf(size.x, 0.4)
	var depth := maxf(size.y, 0.2)
	var width := maxf(size.z, 0.4)
	var half_length := length * 0.5
	var half_width := width * 0.5

	_add_box_body(
		"Floor",
		Vector3(length, HOLE_FLOOR_THICKNESS, width),
		Vector3(0.0, -depth - HOLE_FLOOR_THICKNESS * 0.5, 0.0),
		HOLE_COLOR
	)
	_add_box_body(
		"WallNorth",
		Vector3(length + WALL_THICKNESS, depth, WALL_THICKNESS),
		Vector3(0.0, -depth * 0.5, -half_width - WALL_THICKNESS * 0.5),
		HOLE_COLOR
	)
	_add_box_body(
		"WallSouth",
		Vector3(length + WALL_THICKNESS, depth, WALL_THICKNESS),
		Vector3(0.0, -depth * 0.5, half_width + WALL_THICKNESS * 0.5),
		HOLE_COLOR
	)
	_add_box_body(
		"WallEast",
		Vector3(WALL_THICKNESS, depth, width + WALL_THICKNESS),
		Vector3(half_length + WALL_THICKNESS * 0.5, -depth * 0.5, 0.0),
		HOLE_COLOR
	)
	_add_box_body(
		"WallWest",
		Vector3(WALL_THICKNESS, depth, width + WALL_THICKNESS),
		Vector3(-half_length - WALL_THICKNESS * 0.5, -depth * 0.5, 0.0),
		HOLE_COLOR
	)


func _build_cylinder_hole() -> void:
	var radius := maxf(size.x, 0.4)
	var depth := maxf(size.y, 0.2)

	_add_cylinder_body(
		"Floor",
		radius,
		HOLE_FLOOR_THICKNESS,
		Vector3(0.0, -depth - HOLE_FLOOR_THICKNESS * 0.5, 0.0),
		HOLE_COLOR
	)

	## Straight box segments approximating the round wall — a ConvexPolygonShape3D
	## ring would wrongly fill in as a solid disc, since the hole is non-convex.
	var segment_angle := TAU / float(CYLINDER_WALL_SEGMENTS)
	var chord := 2.0 * radius * sin(segment_angle * 0.5) + 0.05
	for i in CYLINDER_WALL_SEGMENTS:
		var theta := (float(i) + 0.5) * segment_angle
		var tangent := Vector3(-sin(theta), 0.0, cos(theta))
		var radial := Vector3(cos(theta), 0.0, sin(theta))
		## z_axis = -radial (not radial) keeps this a proper right-handed
		## rotation (x_axis cross y_axis = z_axis); using radial directly
		## would mirror the segment and invert its mesh winding/normals.
		var wall_basis := Basis(tangent, Vector3.UP, -radial)
		var wall_position := radial * radius + Vector3(0.0, -depth * 0.5, 0.0)
		_add_box_body(
			"Wall_%d" % i,
			Vector3(chord, depth, WALL_THICKNESS),
			wall_position,
			HOLE_COLOR,
			wall_basis
		)


func _add_box_body(
	node_name: String,
	box_size: Vector3,
	local_position: Vector3,
	color: Color,
	local_basis: Basis = Basis.IDENTITY
) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = Transform3D(local_basis, local_position)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var box := BoxMesh.new()
	box.size = box_size
	mesh_instance.mesh = box
	mesh_instance.material_override = _make_material(color)
	mesh_instance.layers = WorldVisualLayersScript.WORLD
	mesh_instance.set_meta("_edit_lock_", true)
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var shape_res := BoxShape3D.new()
	shape_res.size = box_size
	collision.shape = shape_res
	body.add_child(collision)

	_built.add_child(body)


func _add_cylinder_body(
	node_name: String, radius: float, height: float, local_position: Vector3, color: Color
) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = local_position

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	mesh_instance.mesh = cyl
	mesh_instance.material_override = _make_material(color)
	mesh_instance.layers = WorldVisualLayersScript.WORLD
	mesh_instance.set_meta("_edit_lock_", true)
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var shape_res := CylinderShape3D.new()
	shape_res.radius = radius
	shape_res.height = height
	collision.shape = shape_res
	body.add_child(collision)

	_built.add_child(body)


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6
	## Double-siding is cheap insurance against any face looking hollow/
	## culled from a given angle.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
