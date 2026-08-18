@tool
class_name StunStars
extends Node3D

## Cartoon 5-point stars that orbit a host. Shared by Charger wall-stun and
## player ram-stun. Toggle with set_active.

enum OrbitMode { HORIZONTAL, FACING }

const StunStarMeshScript := preload("res://scripts/fx/stun_star_mesh.gd")
const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")

@export_range(3, 8, 1) var star_count: int = 5
@export_range(0.04, 0.8, 0.01) var orbit_radius: float = 0.28
@export_range(0.5, 10.0, 0.1) var orbit_speed: float = 4.2
@export_range(0.02, 0.2, 0.005) var star_size: float = 0.07
@export var star_color: Color = Color(1.0, 0.92, 0.25, 1.0)
@export var orbit_mode: OrbitMode = OrbitMode.HORIZONTAL
@export_range(0.0, 0.12, 0.005) var bob_amp: float = 0.03

@export_group("Editor preview")
@export_tool_button("Play Animation", "Callable")
var play_animation_action := play_animation
@export_tool_button("Stop Animation", "Callable")
var stop_animation_action := stop_animation

var _stars: Array[MeshInstance3D] = []
var _angle: float = 0.0
var _active: bool = false


func _ready() -> void:
	visible = false
	_rebuild()
	set_process(false)


func play_animation() -> void:
	if not is_inside_tree():
		return
	_rebuild()
	if Engine.is_editor_hint():
		process_mode = Node.PROCESS_MODE_ALWAYS
	set_active(true)


func stop_animation() -> void:
	set_active(false)


func set_active(on: bool) -> void:
	_active = on
	visible = on
	set_process(on)
	if not on:
		_angle = 0.0


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	if not _active:
		return
	if _stars.is_empty():
		_rebuild()
	_angle += delta * orbit_speed
	var count := maxi(_stars.size(), 1)
	for i in _stars.size():
		var star := _stars[i]
		if star == null:
			continue
		var a := _angle + float(i) * TAU / float(count)
		star.position = _orbit_point(a)
		var pulse := 1.0 + sin(a * 3.0) * 0.12
		star.scale = Vector3.ONE * pulse


func _orbit_point(angle: float) -> Vector3:
	var c := cos(angle) * orbit_radius
	var s := sin(angle) * orbit_radius
	var bob := sin(angle * 2.0) * bob_amp
	if orbit_mode == OrbitMode.FACING:
		return Vector3(c, s, 0.0)
	return Vector3(c, 0.06 + bob, s)


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_stars.clear()
	var mesh := StunStarMeshScript.build(star_size)
	var mat := _make_material()
	for i in maxi(star_count, 1):
		var inst := MeshInstance3D.new()
		inst.name = "Star%d" % i
		inst.mesh = mesh
		inst.material_override = mat
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.layers = WorldVisualLayersScript.WORLD
		add_child(inst)
		_stars.append(inst)


func _make_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.albedo_color = star_color
	mat.emission_enabled = true
	mat.emission = star_color
	mat.emission_energy_multiplier = 3.4
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat
