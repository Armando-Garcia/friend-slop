@tool
class_name PuzzleMovingPlatformNode
extends Node3D

## A moving platform: rides a line, circle, or polygon path at a tunable
## speed, optionally pausing at stops placed along the way, and is either a
## regular ride-along tile or a jump tile that launches the player on
## footfall. Doubles as:
## - the live, draggable node you place/tune in puzzle_workshop.tscn
## - the node WizardChallengeHeight instantiates at match runtime from a
##   saved PuzzleDefinition
##
## Position is this node's own transform — the path anchor (the LINE/POLYGON
## start, or the CIRCLE's center). Path points are child
## PuzzlePlatformPathPointNode markers, added via the workshop's "Path
## Point" object type while this platform is selected, then dragged into
## place: for LINE/POLYGON they ARE the route (visited in child order); for
## CIRCLE they only mark stop angles (projected onto the circle) + dwell.
##
## Movement runs in _physics_process and only at actual runtime (F6 or a
## match) — an @tool script doesn't get physics ticks while just editing,
## so drag the path points to author the route and run the scene to see it
## move, same as everything else in this workshop.

const PuzzlePlatformMotionScript := preload("res://scripts/objectives/puzzle_platform_motion.gd")
const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")
const StaircaseMeshScript := preload("res://scripts/objectives/staircase_mesh.gd")

## Reuses PuzzleMovingPlatformEntry's enums directly (rather than declaring
## matching local ones) so entry <-> node assignments type-check — GDScript
## treats two identically-named-but-separately-declared enums as distinct
## types, even with the same members.
const TILE_COLOR := Color(0.35, 0.45, 0.55)
const JUMP_TILE_COLOR := Color(0.3, 0.72, 0.95)

@export var path_type: PuzzleMovingPlatformEntry.PathType = PuzzleMovingPlatformEntry.PathType.LINE:
	set(value):
		path_type = value
		_reset_motion_state()
		_rebuild()
## Meters per second traveled along the path.
@export_range(0.2, 10.0, 0.1) var speed: float = 2.0
## Regular ride-along tile, or a jump tile that launches the player on footfall.
@export var is_jump_tile: bool = false:
	set(value):
		is_jump_tile = value
		_rebuild()
## STAIRCASE looks like 10 stair steps but collides like a plain ramp — a
## "moving version" of the stationary Staircase step.
@export var tile_shape: PuzzleMovingPlatformEntry.TileShape = (
	PuzzleMovingPlatformEntry.TileShape.BOX
):
	set(value):
		tile_shape = value
		_rebuild()
@export var tile_size: Vector3 = Vector3(1.6, 0.3, 1.6):
	set(value):
		tile_size = value
		_rebuild()
## CIRCLE only: radius of the loop.
@export_range(0.5, 10.0, 0.1) var circle_radius: float = 3.0:
	set(value):
		circle_radius = value
		_reset_motion_state()
## CIRCLE only: orientation of the circle's plane.
@export var circle_rotation_degrees: Vector3 = Vector3.ZERO:
	set(value):
		circle_rotation_degrees = value
		_reset_motion_state()
## POLYGON only: loop back to the first point instead of ping-ponging.
@export var closed_loop: bool = true:
	set(value):
		closed_loop = value
		_reset_motion_state()

var _tile_body: AnimatableBody3D
var _launch_area: Area3D
var _waypoint_state: Dictionary = PuzzlePlatformMotionScript.default_waypoint_state()
var _circle_state: Dictionary = PuzzlePlatformMotionScript.default_circle_state()


func _ready() -> void:
	if _tile_body == null:
		_rebuild()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_advance(delta)


## --- Saved-puzzle <-> live-node conversion --------------------------------

static func from_entry(entry: PuzzleMovingPlatformEntry) -> PuzzleMovingPlatformNode:
	var node := PuzzleMovingPlatformNode.new()
	node.apply_entry(entry)
	return node


func apply_entry(entry: PuzzleMovingPlatformEntry) -> void:
	position = entry.position
	path_type = entry.path_type
	speed = entry.speed
	is_jump_tile = entry.is_jump_tile
	tile_shape = entry.tile_shape
	tile_size = entry.tile_size
	circle_radius = entry.circle_radius
	circle_rotation_degrees = entry.circle_rotation_degrees
	closed_loop = entry.closed_loop
	for point_entry in entry.path_points:
		if point_entry == null:
			continue
		add_child(new_path_point(point_entry.position, point_entry.stop_seconds))
	_reset_motion_state()
	_rebuild()


func to_entry() -> PuzzleMovingPlatformEntry:
	var entry := PuzzleMovingPlatformEntry.new()
	entry.position = position
	entry.path_type = path_type
	entry.speed = speed
	entry.is_jump_tile = is_jump_tile
	entry.tile_shape = tile_shape
	entry.tile_size = tile_size
	entry.circle_radius = circle_radius
	entry.circle_rotation_degrees = circle_rotation_degrees
	entry.closed_loop = closed_loop
	var points: Array[PuzzlePlatformPathPointEntry] = []
	for point in path_point_children():
		var point_entry := PuzzlePlatformPathPointEntry.new()
		point_entry.position = point.position
		point_entry.stop_seconds = point.stop_seconds
		points.append(point_entry)
	entry.path_points = points
	return entry


## --- Path points ------------------------------------------------------------

func new_path_point(
	local_position: Vector3,
	stop_seconds: float = 0.0
) -> PuzzlePlatformPathPointNode:
	var point := PuzzlePlatformPathPointNode.new()
	point.position = local_position
	point.stop_seconds = stop_seconds
	return point


func path_point_children() -> Array[PuzzlePlatformPathPointNode]:
	var result: Array[PuzzlePlatformPathPointNode] = []
	for child in get_children():
		if child is PuzzlePlatformPathPointNode:
			result.append(child as PuzzlePlatformPathPointNode)
	return result


## --- Motion ----------------------------------------------------------------

func _reset_motion_state() -> void:
	_waypoint_state = PuzzlePlatformMotionScript.default_waypoint_state()
	_circle_state = PuzzlePlatformMotionScript.default_circle_state()


func _advance(delta: float) -> void:
	if path_type == PuzzleMovingPlatformEntry.PathType.CIRCLE:
		_circle_state = PuzzlePlatformMotionScript.advance_circle_state(
			_circle_state, _circle_stops(), circle_radius, speed, delta
		)
		var local := PuzzlePlatformMotionScript.circle_position(_circle_state, circle_radius)
		_move_tile(_circle_basis() * local)
		return

	var points := _path_point_positions()
	if points.size() < 2:
		return
	var closed := closed_loop and path_type == PuzzleMovingPlatformEntry.PathType.POLYGON
	_waypoint_state = PuzzlePlatformMotionScript.advance_waypoint_state(
		_waypoint_state, points, _path_point_stop_seconds(), speed, delta, closed
	)
	_move_tile(PuzzlePlatformMotionScript.waypoint_state_position(_waypoint_state, points))


func _move_tile(local_offset: Vector3) -> void:
	if _tile_body != null:
		_tile_body.position = local_offset


func _path_point_positions() -> Array:
	var result := []
	for point in path_point_children():
		result.append(point.position)
	return result


func _path_point_stop_seconds() -> Array:
	var result := []
	for point in path_point_children():
		result.append(point.stop_seconds)
	return result


## Each path point's dragged position, projected onto the circle's plane and
## read off as an angle — that's its stop angle.
func _circle_stops() -> Array:
	var result := []
	for point in path_point_children():
		result.append({"angle": _angle_on_circle(point.position), "seconds": point.stop_seconds})
	return result


func _angle_on_circle(local_pos: Vector3) -> float:
	var in_plane: Vector3 = _circle_basis().inverse() * local_pos
	return fposmod(atan2(in_plane.z, in_plane.x), TAU)


func _circle_basis() -> Basis:
	return Basis.from_euler(Vector3(
		deg_to_rad(circle_rotation_degrees.x),
		deg_to_rad(circle_rotation_degrees.y),
		deg_to_rad(circle_rotation_degrees.z)
	))


## --- Build / rebuild --------------------------------------------------------

func _rebuild() -> void:
	if not is_inside_tree() and _tile_body == null:
		## Called from a setter before _ready(); defer to _ready().
		return
	_clear_tile()
	_build_tile()
	if is_jump_tile:
		_build_launch_area()


## Only the tile body (+ its mesh/collision/launch-area children) gets
## rebuilt here — path point children are separate siblings and untouched.
func _clear_tile() -> void:
	if _tile_body != null and is_instance_valid(_tile_body):
		_tile_body.free()
	_tile_body = null
	_launch_area = null


func _build_tile() -> void:
	_tile_body = AnimatableBody3D.new()
	_tile_body.name = "Tile"
	_tile_body.collision_layer = 1
	_tile_body.collision_mask = 0
	## Moves via transform each physics frame; sync_to_physics lets a
	## CharacterBody3D standing on it inherit that motion (ride along).
	_tile_body.sync_to_physics = true

	var mesh_instance := MeshInstance3D.new()
	var color := JUMP_TILE_COLOR if is_jump_tile else TILE_COLOR
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.3
	material.emission_energy_multiplier = 1.0
	material.roughness = 0.6
	## Double-sided as insurance against a hand-built staircase mesh face
	## looking hollow/culled from a given angle.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material
	mesh_instance.layers = WorldVisualLayersScript.WORLD
	mesh_instance.set_meta("_edit_lock_", true)
	_tile_body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	_tile_body.add_child(collision)

	if tile_shape == PuzzleMovingPlatformEntry.TileShape.STAIRCASE:
		mesh_instance.mesh = StaircaseMeshScript.build_mesh(tile_size)
		var convex := ConvexPolygonShape3D.new()
		convex.points = StaircaseMeshScript.ramp_collision_points(tile_size)
		collision.shape = convex
	else:
		var box := BoxMesh.new()
		box.size = tile_size
		mesh_instance.mesh = box
		var shape := BoxShape3D.new()
		shape.size = tile_size
		collision.shape = shape

	add_child(_tile_body)


func _build_launch_area() -> void:
	_launch_area = Area3D.new()
	_launch_area.name = "LaunchTrigger"
	_launch_area.collision_layer = 0
	_launch_area.collision_mask = 1
	_launch_area.monitoring = true
	_launch_area.monitorable = false
	var trigger_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(tile_size.x * 0.9, 0.5, tile_size.z * 0.9)
	trigger_shape.shape = box
	trigger_shape.position = Vector3(0.0, tile_size.y * 0.5 + 0.25, 0.0)
	_launch_area.add_child(trigger_shape)
	_launch_area.body_entered.connect(_on_launch_area_body_entered)
	_tile_body.add_child(_launch_area)


func _on_launch_area_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return
	if body.is_in_group("player") and body.has_method("apply_ember_halo_jump_pad"):
		body.call("apply_ember_halo_jump_pad")
