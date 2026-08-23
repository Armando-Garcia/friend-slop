@tool
class_name PuzzleStepNode
extends StaticBody3D

## One physical step in a WizardChallengeHeight tower. Doubles as:
## - the live, draggable node you place/shape/trap in puzzle_workshop.tscn
## - the node WizardChallengeHeight instantiates at match runtime from a
##   saved PuzzleDefinition
##
## Position/rotation ARE the node's own transform (drag it in the 3D
## viewport). Shape/trap are exported fields with setters that live-rebuild
## the mesh + collider, same idiom as MazeGenerator's exported knobs.

const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")
const RoundedBoxMeshScript := preload("res://scripts/objectives/rounded_box_mesh.gd")
const StaircaseMeshScript := preload("res://scripts/objectives/staircase_mesh.gd")

## Seconds a CRUMBLE step stays gone before it reappears.
const CRUMBLE_RESPAWN_SEC := 4.0
## Bottom-rim fillet radius for the BOX shape.
const BOTTOM_ROUND_RADIUS := 0.1
const NORMAL_COLOR := Color(0.42, 0.34, 0.58)
const SUMMIT_COLOR := Color(0.55, 0.42, 0.85)
const CRUMBLE_COLOR := Color(0.75, 0.35, 0.25)
const LAUNCH_COLOR := Color(0.3, 0.72, 0.95)

@export var shape: PuzzleStepEntry.Shape = PuzzleStepEntry.Shape.BOX:
	set(value):
		shape = value
		_rebuild_visual()
## Box: full extents (x, y, z). Cylinder: (diameter, height, diameter).
## Ramp: (width, max height, run length).
@export var size: Vector3 = Vector3(1.6, 0.3, 1.15):
	set(value):
		size = value
		_rebuild_visual()
@export var is_summit: bool = false:
	set(value):
		is_summit = value
		_rebuild_visual()
@export var trap_type: PuzzleStepEntry.Trap = PuzzleStepEntry.Trap.NONE:
	set(value):
		trap_type = value
		_rebuild_visual()
		_sync_trap_behavior()
## CRUMBLE: seconds standing on it before it drops. LAUNCH: launch strength
## multiplier — 1.0 is a normal jump pad pop, higher launches you higher.
@export var trap_param: float = 0.6

var _mesh_instance: MeshInstance3D
var _collision: CollisionShape3D
var _trap_area: Area3D
var _crumble_triggered: bool = false


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	if _mesh_instance == null:
		_rebuild_visual()
	if not Engine.is_editor_hint():
		_sync_trap_behavior()


## --- Saved-puzzle <-> live-node conversion --------------------------------

static func from_entry(entry: PuzzleStepEntry) -> PuzzleStepNode:
	var node := PuzzleStepNode.new()
	node.apply_entry(entry)
	return node


func apply_entry(entry: PuzzleStepEntry) -> void:
	position = entry.position
	rotation = Vector3(0.0, deg_to_rad(entry.rotation_y_degrees), 0.0)
	shape = entry.shape
	size = entry.size
	is_summit = entry.is_summit
	trap_type = entry.trap_type
	trap_param = entry.trap_param
	_rebuild_visual()


func to_entry() -> PuzzleStepEntry:
	var entry := PuzzleStepEntry.new()
	entry.position = position
	entry.rotation_y_degrees = rad_to_deg(rotation.y)
	entry.shape = shape
	entry.size = size
	entry.is_summit = is_summit
	entry.trap_type = trap_type
	entry.trap_param = trap_param
	return entry


## --- Visual / collider -----------------------------------------------------

func _rebuild_visual() -> void:
	if not is_inside_tree() and _mesh_instance == null:
		## Called from a setter before _ready(); defer to _ready().
		return
	_clear_visual()

	var color := _step_color()
	match shape:
		PuzzleStepEntry.Shape.CYLINDER:
			_build_cylinder(color)
		PuzzleStepEntry.Shape.RAMP:
			_build_ramp(color)
		PuzzleStepEntry.Shape.STAIRCASE:
			_build_staircase(color)
		_:
			_build_box(color)


func _step_color() -> Color:
	match trap_type:
		PuzzleStepEntry.Trap.CRUMBLE:
			return CRUMBLE_COLOR
		PuzzleStepEntry.Trap.LAUNCH:
			return LAUNCH_COLOR
		_:
			return SUMMIT_COLOR if is_summit else NORMAL_COLOR


func _clear_visual() -> void:
	if _mesh_instance != null and is_instance_valid(_mesh_instance):
		_mesh_instance.free()
	if _collision != null and is_instance_valid(_collision):
		_collision.free()
	_mesh_instance = null
	_collision = null


func _build_box(color: Color) -> void:
	var mesh := RoundedBoxMeshScript.build_mesh(size, BOTTOM_ROUND_RADIUS)
	_finish_mesh(mesh, color)
	var shape_res := ConvexPolygonShape3D.new()
	shape_res.points = RoundedBoxMeshScript.build_collision_points(size, BOTTOM_ROUND_RADIUS)
	_finish_collision(shape_res)


func _build_staircase(color: Color) -> void:
	var mesh := StaircaseMeshScript.build_mesh(size)
	_finish_mesh(mesh, color)
	var shape_res := ConvexPolygonShape3D.new()
	shape_res.points = StaircaseMeshScript.ramp_collision_points(size)
	_finish_collision(shape_res)


func _build_cylinder(color: Color) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = size.x * 0.5
	cyl.bottom_radius = size.x * 0.5
	cyl.height = size.y
	_finish_mesh(cyl, color)
	var shape_res := CylinderShape3D.new()
	shape_res.radius = size.x * 0.5
	shape_res.height = size.y
	_finish_collision(shape_res)


func _build_ramp(color: Color) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var a := Vector3(-hx, -hy, -hz)
	var b := Vector3(hx, -hy, -hz)
	var c := Vector3(-hx, -hy, hz)
	var d := Vector3(hx, -hy, hz)
	var e := Vector3(-hx, hy, hz)
	var f := Vector3(hx, hy, hz)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := [
		[a, b, d], [a, d, c],  ## bottom
		[c, d, f], [c, f, e],  ## back wall
		[a, b, f], [a, f, e],  ## ramp surface
		[a, c, e],  ## left wall
		[b, f, d],  ## right wall
	]
	for tri in tris:
		for v in tri:
			st.add_vertex(v)
	st.generate_normals()
	_finish_mesh(st.commit(), color)

	var shape_res := ConvexPolygonShape3D.new()
	shape_res.points = PackedVector3Array([a, b, c, d, e, f])
	_finish_collision(shape_res)


func _finish_mesh(mesh: Mesh, color: Color) -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Mesh"
	_mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.35
	material.emission_energy_multiplier = 1.2
	material.roughness = 0.6
	## Hand-built meshes (rounded box, staircase, ramp) are easy to get a
	## winding edge case wrong on; double-siding is cheap insurance against
	## any face looking hollow/culled from a given angle.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_instance.material_override = material
	_mesh_instance.layers = WorldVisualLayersScript.WORLD
	_mesh_instance.set_meta("_edit_lock_", true)
	add_child(_mesh_instance)


func _finish_collision(shape_res: Shape3D) -> void:
	_collision = CollisionShape3D.new()
	_collision.name = "Collision"
	_collision.shape = shape_res
	add_child(_collision)


## --- Trap behavior (runtime only) -------------------------------------
## Each client detects its own local overlap and animates the trap purely
## cosmetically (mesh hide / collision disable) — not network-synced. Good
## enough for a solo-first race objective; a host-authoritative broadcast
## (like WizardChallengeHeightSync) would be needed for strict parity.

func _sync_trap_behavior() -> void:
	if Engine.is_editor_hint():
		return
	if _trap_area != null and is_instance_valid(_trap_area):
		_trap_area.free()
		_trap_area = null
	_crumble_triggered = false
	if trap_type == PuzzleStepEntry.Trap.NONE:
		return

	_trap_area = Area3D.new()
	_trap_area.name = "TrapArea"
	_trap_area.collision_layer = 0
	_trap_area.collision_mask = 1
	_trap_area.monitoring = true
	_trap_area.monitorable = false
	add_child(_trap_area)

	var trigger_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	## A thin volume hugging the top surface so the trap fires on footfall.
	box.size = Vector3(size.x * 0.9, 0.5, size.z * 0.9)
	trigger_shape.shape = box
	trigger_shape.position = Vector3(0.0, size.y * 0.5 + 0.25, 0.0)
	_trap_area.add_child(trigger_shape)

	_trap_area.body_entered.connect(_on_trap_body_entered)


func _on_trap_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	match trap_type:
		PuzzleStepEntry.Trap.CRUMBLE:
			_trigger_crumble()
		PuzzleStepEntry.Trap.LAUNCH:
			_trigger_launch(body)


func _trigger_crumble() -> void:
	if _crumble_triggered:
		return
	_crumble_triggered = true
	await get_tree().create_timer(maxf(trap_param, 0.05)).timeout
	if not is_instance_valid(self):
		return
	_set_step_solid(false)
	await get_tree().create_timer(CRUMBLE_RESPAWN_SEC).timeout
	if not is_instance_valid(self):
		return
	_set_step_solid(true)
	_crumble_triggered = false


func _set_step_solid(solid: bool) -> void:
	if _mesh_instance != null and is_instance_valid(_mesh_instance):
		_mesh_instance.visible = solid
	if _collision != null and is_instance_valid(_collision):
		_collision.disabled = not solid


func _trigger_launch(body: Node3D) -> void:
	if body.has_method("apply_ember_halo_jump_pad"):
		body.call("apply_ember_halo_jump_pad", maxf(trap_param, 0.0))
