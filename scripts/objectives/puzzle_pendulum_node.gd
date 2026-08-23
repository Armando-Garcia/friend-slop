@tool
class_name PuzzlePendulumNode
extends Node3D

## A swinging pendulum trap: a bob hung by two strings from a floating peg,
## arcing back and forth through the tower. Doubles as:
## - the live, draggable node you place/tune in puzzle_workshop.tscn (it
##   swings live in the editor viewport too — drag the peg, watch it settle)
## - the node WizardChallengeHeight instantiates at match runtime from a
##   saved PuzzleDefinition
##
## The peg sits at this node's own position (drag it in the 3D viewport).
## Radius/speed/amplitude/size/plane/bounce-pads are exported fields; the
## structural ones live-rebuild the visuals, same idiom as PuzzleStepNode.
## Optional bounce pads reuse the same footfall-launch trick as PuzzleStepNode's
## LAUNCH trap; the bob itself knocks players back on contact, reusing
## PlayableCharacter.apply_ember_halo_hit (displacement only — no HP damage).

const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")

const PEG_COLOR := Color(0.3, 0.28, 0.24)
const STRING_COLOR := Color(0.55, 0.5, 0.42)
const BOB_COLOR := Color(0.62, 0.22, 0.22)
const PAD_COLOR := Color(0.3, 0.72, 0.95)
const STRING_RADIUS := 0.03
## Lateral offset between the two strings where they meet the bob.
const STRING_SPAN := 0.12
const PAD_SIZE := Vector3(1.1, 0.25, 1.1)
## Minimum time between bob hits on the same player (seconds).
const HIT_COOLDOWN_SEC := 0.4

@export_range(0.5, 8.0, 0.1) var radius: float = 2.5:
	set(value):
		radius = value
		_rebuild()
@export_range(0.05, 4.0, 0.05) var speed: float = 1.0
@export_range(5.0, 90.0, 1.0) var swing_amplitude_degrees: float = 45.0:
	set(value):
		swing_amplitude_degrees = value
		_rebuild()
@export_range(0.3, 3.0, 0.05) var bob_size: float = 0.8:
	set(value):
		bob_size = value
		_rebuild()
@export_range(0.0, 360.0, 1.0) var swing_plane_rotation_degrees: float = 0.0:
	set(value):
		swing_plane_rotation_degrees = value
		_rebuild()
@export var bounce_pad_left: bool = false:
	set(value):
		bounce_pad_left = value
		_rebuild()
@export var bounce_pad_right: bool = false:
	set(value):
		bounce_pad_right = value
		_rebuild()

var _peg: MeshInstance3D
var _string_a: MeshInstance3D
var _string_b: MeshInstance3D
var _bob_mesh: MeshInstance3D
var _bob_area: Area3D
var _phase: float = 0.0
var _last_hit_msec: int = 0


func _ready() -> void:
	if _peg == null:
		_rebuild()


func _process(delta: float) -> void:
	_phase += delta * speed
	_update_swing()


## --- Saved-puzzle <-> live-node conversion --------------------------------

static func from_entry(entry: PuzzlePendulumEntry) -> PuzzlePendulumNode:
	var node := PuzzlePendulumNode.new()
	node.apply_entry(entry)
	return node


func apply_entry(entry: PuzzlePendulumEntry) -> void:
	position = entry.position
	radius = entry.radius
	speed = entry.speed
	swing_amplitude_degrees = entry.swing_amplitude_degrees
	bob_size = entry.bob_size
	swing_plane_rotation_degrees = entry.swing_plane_rotation_degrees
	bounce_pad_left = entry.bounce_pad_left
	bounce_pad_right = entry.bounce_pad_right
	_rebuild()


func to_entry() -> PuzzlePendulumEntry:
	var entry := PuzzlePendulumEntry.new()
	entry.position = position
	entry.radius = radius
	entry.speed = speed
	entry.swing_amplitude_degrees = swing_amplitude_degrees
	entry.bob_size = bob_size
	entry.swing_plane_rotation_degrees = swing_plane_rotation_degrees
	entry.bounce_pad_left = bounce_pad_left
	entry.bounce_pad_right = bounce_pad_right
	return entry


## --- Motion ----------------------------------------------------------------

func current_angle() -> float:
	return deg_to_rad(swing_amplitude_degrees) * sin(_phase)


## Local-space offset of the bob relative to the peg, in the swing plane,
## before the plane's yaw is applied. Hangs straight down at angle 0.
func _local_bob_offset(angle: float) -> Vector3:
	return Vector3(sin(angle) * radius, -cos(angle) * radius, 0.0)


func _plane_basis() -> Basis:
	return Basis(Vector3.UP, deg_to_rad(swing_plane_rotation_degrees))


func _update_swing() -> void:
	if _bob_mesh == null:
		return
	var offset := _plane_basis() * _local_bob_offset(current_angle())
	_bob_mesh.position = offset
	if _bob_area != null:
		_bob_area.position = offset
	_update_strings(offset)


func _update_strings(bob_offset: Vector3) -> void:
	var lateral := _plane_basis() * (Vector3(0.0, 0.0, 1.0) * STRING_SPAN)
	_orient_string(_string_a, bob_offset + lateral)
	_orient_string(_string_b, bob_offset - lateral)


func _orient_string(mesh_instance: MeshInstance3D, to_point: Vector3) -> void:
	if mesh_instance == null:
		return
	var length := to_point.length()
	mesh_instance.position = to_point * 0.5
	if length < 0.001:
		return
	var cyl := mesh_instance.mesh as CylinderMesh
	if cyl != null:
		cyl.height = length
	mesh_instance.basis = _basis_from_up(to_point / length)


## CylinderMesh points along local +Y — build a basis whose Y axis is `dir`.
func _basis_from_up(dir: Vector3) -> Basis:
	var y := dir
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## --- Build / rebuild --------------------------------------------------------

func _rebuild() -> void:
	if not is_inside_tree() and _peg == null:
		## Called from a setter before _ready(); defer to _ready().
		return
	_clear_children()
	_build_peg()
	_build_strings()
	_build_bob()
	_build_bounce_pads()
	_update_swing()


func _clear_children() -> void:
	while get_child_count() > 0:
		var child := get_child(0)
		remove_child(child)
		child.free()
	_peg = null
	_string_a = null
	_string_b = null
	_bob_mesh = null
	_bob_area = null


func _build_peg() -> void:
	_peg = MeshInstance3D.new()
	_peg.name = "Peg"
	var box := BoxMesh.new()
	box.size = Vector3(0.18, 0.12, 0.18)
	_peg.mesh = box
	_finish_static_mesh(_peg, PEG_COLOR)
	add_child(_peg)


func _build_strings() -> void:
	_string_a = _make_string_mesh("StringA")
	_string_b = _make_string_mesh("StringB")
	add_child(_string_a)
	add_child(_string_b)


func _make_string_mesh(node_name: String) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var cyl := CylinderMesh.new()
	cyl.top_radius = STRING_RADIUS
	cyl.bottom_radius = STRING_RADIUS
	cyl.height = radius
	mesh_instance.mesh = cyl
	_finish_static_mesh(mesh_instance, STRING_COLOR)
	return mesh_instance


func _build_bob() -> void:
	_bob_mesh = MeshInstance3D.new()
	_bob_mesh.name = "Bob"
	var sphere := SphereMesh.new()
	sphere.radius = bob_size * 0.5
	sphere.height = bob_size
	_bob_mesh.mesh = sphere
	_finish_static_mesh(_bob_mesh, BOB_COLOR)
	add_child(_bob_mesh)

	_bob_area = Area3D.new()
	_bob_area.name = "BobArea"
	_bob_area.collision_layer = 0
	_bob_area.collision_mask = 1
	_bob_area.monitoring = true
	_bob_area.monitorable = false
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = bob_size * 0.5
	col.shape = shape
	_bob_area.add_child(col)
	if not _bob_area.body_entered.is_connected(_on_bob_body_entered):
		_bob_area.body_entered.connect(_on_bob_body_entered)
	add_child(_bob_area)


func _build_bounce_pads() -> void:
	if bounce_pad_left:
		add_child(_make_bounce_pad("BouncePadLeft", -1.0))
	if bounce_pad_right:
		add_child(_make_bounce_pad("BouncePadRight", 1.0))


## Sits at ground level directly under wherever the bob reaches on that side
## of its swing, so the pad reads as "the landing spot at the end of the arc".
func _make_bounce_pad(node_name: String, side: float) -> StaticBody3D:
	var extreme_angle := deg_to_rad(swing_amplitude_degrees) * side
	var extreme_offset := _plane_basis() * _local_bob_offset(extreme_angle)
	var pad_offset := extreme_offset + Vector3(
		0.0, -(bob_size * 0.5 + PAD_SIZE.y * 0.5 + 0.08), 0.0
	)

	var pad := StaticBody3D.new()
	pad.name = node_name
	pad.collision_layer = 1
	pad.collision_mask = 0
	pad.position = pad_offset

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = PAD_SIZE
	mesh_instance.mesh = box
	_finish_static_mesh(mesh_instance, PAD_COLOR)
	pad.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = PAD_SIZE
	collision.shape = box_shape
	pad.add_child(collision)

	var trigger := Area3D.new()
	trigger.name = "LaunchTrigger"
	trigger.collision_layer = 0
	trigger.collision_mask = 1
	trigger.monitoring = true
	trigger.monitorable = false
	var trigger_shape := CollisionShape3D.new()
	var trigger_box := BoxShape3D.new()
	trigger_box.size = Vector3(PAD_SIZE.x * 0.9, 0.5, PAD_SIZE.z * 0.9)
	trigger_shape.shape = trigger_box
	trigger_shape.position = Vector3(0.0, PAD_SIZE.y * 0.5 + 0.25, 0.0)
	trigger.add_child(trigger_shape)
	trigger.body_entered.connect(_on_bounce_pad_body_entered)
	pad.add_child(trigger)

	return pad


func _finish_static_mesh(mesh_instance: MeshInstance3D, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.3
	material.emission_energy_multiplier = 1.0
	material.roughness = 0.6
	mesh_instance.material_override = material
	mesh_instance.layers = WorldVisualLayersScript.WORLD
	mesh_instance.set_meta("_edit_lock_", true)


## --- Player interaction (runtime only — inert while editing) --------------

func _on_bob_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint() or not body.is_in_group("player"):
		return
	var now := Time.get_ticks_msec()
	if now - _last_hit_msec < int(HIT_COOLDOWN_SEC * 1000.0):
		return
	_last_hit_msec = now
	var away := body.global_position - _bob_mesh.global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = -global_transform.basis.z
	else:
		away = away.normalized()
	if body.has_method("apply_ember_halo_hit"):
		body.call("apply_ember_halo_hit", away)


func _on_bounce_pad_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return
	if body.is_in_group("player") and body.has_method("apply_ember_halo_jump_pad"):
		body.call("apply_ember_halo_jump_pad")
