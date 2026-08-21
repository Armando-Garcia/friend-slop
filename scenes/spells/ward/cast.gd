class_name WardCastCharge
extends CastChargeFx

## Small translucent ward bubble that tints from white to spell blue.

const RADIUS_M := 0.0185
const SPIN_DEG := Vector3(52.0, 88.0, 24.0)
const RIM_SPIN_DEG := Vector3(-40.0, -96.0, 30.0)

var _bubble: MeshInstance3D
var _rim: MeshInstance3D
var _bubble_mat: StandardMaterial3D
var _rim_mat: StandardMaterial3D
var _spell_color := Color(0.35, 0.65, 1.0, 1.0)


func _build(spell_color: Color) -> void:
	_spell_color = spell_color
	var radius := _local_radius(RADIUS_M)
	_bubble = MeshInstance3D.new()
	_bubble.name = "Bubble"
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 28
	sphere.rings = 14
	_bubble.mesh = sphere
	_bubble_mat = _make_bubble_mat(Color.WHITE)
	_bubble.material_override = _bubble_mat
	add_child(_bubble)
	_rim = MeshInstance3D.new()
	_rim.name = "Rim"
	var rim_mesh := SphereMesh.new()
	rim_mesh.radius = radius * 1.04
	rim_mesh.height = radius * 2.08
	rim_mesh.radial_segments = 28
	rim_mesh.rings = 14
	_rim.mesh = rim_mesh
	_rim_mat = _make_rim_mat(Color.WHITE)
	_rim.material_override = _rim_mat
	add_child(_rim)


func _apply_progress(p: float) -> void:
	var target := _spell_color
	if target.a <= 0.001:
		target = Color(0.35, 0.65, 1.0, 1.0)
	var col := Color.WHITE.lerp(target, p)
	if _bubble_mat != null:
		_bubble_mat.albedo_color = Color(col.r, col.g, col.b, 0.38)
		_bubble_mat.emission = Color(
			lerpf(col.r, 1.0, 0.75),
			lerpf(col.g, 1.0, 0.75),
			lerpf(col.b, 1.0, 0.75),
			0.55
		)
	if _rim_mat != null:
		var edge := Color(col.r * 0.55, col.g * 0.65, col.b * 0.85, 0.7)
		_rim_mat.albedo_color = edge
		_rim_mat.emission = edge.lightened(0.15)


func tick(delta: float) -> void:
	if _bubble != null:
		_bubble.rotate_x(deg_to_rad(SPIN_DEG.x) * delta)
		_bubble.rotate_y(deg_to_rad(SPIN_DEG.y) * delta)
		_bubble.rotate_z(deg_to_rad(SPIN_DEG.z) * delta)
	if _rim != null:
		_rim.rotate_x(deg_to_rad(RIM_SPIN_DEG.x) * delta)
		_rim.rotate_y(deg_to_rad(RIM_SPIN_DEG.y) * delta)
		_rim.rotate_z(deg_to_rad(RIM_SPIN_DEG.z) * delta)


func _make_bubble_mat(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(col.r, col.g, col.b, 0.38)
	mat.emission_enabled = true
	mat.emission = col.lightened(0.35)
	mat.emission_energy_multiplier = 1.4
	return mat


func _make_rim_mat(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(col.r, col.g, col.b, 0.7)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.8
	return mat
