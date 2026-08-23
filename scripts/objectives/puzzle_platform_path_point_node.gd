@tool
class_name PuzzlePlatformPathPointNode
extends Node3D

## A single point along a PuzzleMovingPlatformNode's path. For a LINE/POLYGON
## platform this IS the route (visited in child order); for a CIRCLE
## platform it's ignored as a route point and only marks a stop angle
## (projected onto the circle) with a dwell time.
##
## Position is this node's own transform, relative to the owning platform —
## drag it in the viewport like any other placed object. Added via the
## workshop's "Path Point" entry in the Add Object dropdown while a
## PuzzleMovingPlatformNode is selected.

const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")

const MARKER_COLOR := Color(0.9, 0.75, 0.25)
const STOP_MARKER_COLOR := Color(0.95, 0.35, 0.25)
const MARKER_RADIUS := 0.16

## Seconds the platform pauses here on arrival. 0 = passes straight through.
@export_range(0.0, 10.0, 0.1) var stop_seconds: float = 0.0:
	set(value):
		stop_seconds = value
		_rebuild()

var _mesh_instance: MeshInstance3D


func _ready() -> void:
	if _mesh_instance == null:
		_rebuild()


func _rebuild() -> void:
	if not is_inside_tree() and _mesh_instance == null:
		## Called from the setter before _ready(); defer to _ready().
		return
	if _mesh_instance != null and is_instance_valid(_mesh_instance):
		_mesh_instance.free()

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Marker"
	var sphere := SphereMesh.new()
	sphere.radius = MARKER_RADIUS
	sphere.height = MARKER_RADIUS * 2.0
	_mesh_instance.mesh = sphere
	var color := STOP_MARKER_COLOR if stop_seconds > 0.0 else MARKER_COLOR
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.4
	material.emission_energy_multiplier = 1.3
	_mesh_instance.material_override = material
	_mesh_instance.layers = WorldVisualLayersScript.WORLD
	_mesh_instance.set_meta("_edit_lock_", true)
	add_child(_mesh_instance)
