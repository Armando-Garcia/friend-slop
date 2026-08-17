class_name EmberHaloProjectile
extends Area3D

## Flat expanding ring that travels toward the player. Jump + knockback + slow on hit.

const EmberHaloFlightScript := preload("res://scripts/monsters/abilities/ember_halo_flight.gd")
const SpellWardBlockScript := preload("res://scripts/spells/spell_ward_block.gd")
const MAX_LIFE_SEC := 3.5

@export var travel_speed: float = EmberHaloFlightScript.TRAVEL_SPEED
@export var start_radius: float = EmberHaloFlightScript.START_RADIUS
@export var max_radius: float = EmberHaloFlightScript.MAX_RADIUS
@export var expand_per_meter: float = EmberHaloFlightScript.EXPAND_PER_METER

var _caster: Node3D = null
var _direction: Vector3 = Vector3.FORWARD
var _distance: float = 0.0
var _radius: float = EmberHaloFlightScript.START_RADIUS
var _age: float = 0.0
var _finished: bool = false
var _hit_bodies: Dictionary = {}
var _mesh: MeshInstance3D = null
var _shape: CollisionShape3D = null
var _cyl_shape: CylinderShape3D = null


static func spawn(
	parent: Node,
	origin: Vector3,
	toward: Vector3,
	caster: Node3D = null
) -> EmberHaloProjectile:
	var packed: PackedScene = load(
		"res://scenes/monsters/abilities/ember_halo_projectile.tscn"
	) as PackedScene
	var proj: EmberHaloProjectile = packed.instantiate() as EmberHaloProjectile
	parent.add_child(proj)
	proj.global_position = Vector3(origin.x, origin.y, origin.z)
	proj.setup(toward, caster)
	return proj


func setup(toward: Vector3, caster: Node3D = null) -> void:
	_caster = caster
	_direction = EmberHaloFlightScript.flat_direction(global_position, toward)
	## Keep the ring gliding parallel to the ground at a stable height.
	if caster != null:
		global_position.y = caster.global_position.y + 0.12
	_radius = start_radius
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1 | 2

	_shape = CollisionShape3D.new()
	_cyl_shape = CylinderShape3D.new()
	_cyl_shape.height = 0.35
	_cyl_shape.radius = _radius
	_shape.shape = _cyl_shape
	add_child(_shape)
	body_entered.connect(_on_body_entered)

	_mesh = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(0.05, _radius * 0.72)
	torus.outer_radius = _radius
	torus.rings = 16
	torus.ring_segments = 24
	_mesh.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.2, 0.08, 0.75)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.25, 0.1)
	mat.emission_energy_multiplier = 3.2
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	## TorusMesh is authored around +Y, so it already lies flat on the XZ ground plane.
	_mesh.rotation_degrees = Vector3.ZERO
	add_child(_mesh)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.3, 0.1)
	light.light_energy = 2.2
	light.omni_range = 2.5
	light.shadow_enabled = false
	add_child(light)

	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _finished:
		return
	_age += delta
	if _age >= MAX_LIFE_SEC:
		_finish()
		return
	var step := travel_speed * delta
	var next := global_position + _direction * step
	next.y = global_position.y
	global_position = next
	_distance += step
	_radius = EmberHaloFlightScript.radius_at_distance(
		_distance, start_radius, max_radius, expand_per_meter
	)
	_sync_radius_visual()
	_try_block_ward_overlap()


func _sync_radius_visual() -> void:
	if _cyl_shape != null:
		_cyl_shape.radius = 0.5
	if _mesh != null and _mesh.mesh is TorusMesh:
		var torus := _mesh.mesh as TorusMesh
		torus.outer_radius = _radius
		torus.inner_radius = maxf(0.05, _radius * 0.85)
		_mesh.scale.y = 1


func _on_body_entered(body: Node3D) -> void:
	if _finished or body == null or body == _caster:
		return
	if _block_if_ward(body):
		return
	if not body.is_in_group("player"):
		return
	var id := body.get_instance_id()
	if _hit_bodies.has(id):
		return
	_hit_bodies[id] = true
	var apply_local := true
	var state := get_tree().root.get_node_or_null("GameState") if get_tree() != null else null
	var mp := state != null and bool(state.get("is_multiplayer"))
	if mp and body is Node:
		apply_local = (body as Node).is_multiplayer_authority()
	if apply_local and body.has_method("apply_ember_halo_hit"):
		body.call("apply_ember_halo_hit", _direction)
	elif apply_local:
		if body.has_method("apply_fireball_knockback"):
			body.call("apply_fireball_knockback", _direction * 0.35)
		if body.has_method("apply_speed_boost"):
			body.call(
				"apply_speed_boost",
				EmberHaloFlightScript.SLOW_DURATION_SEC,
				EmberHaloFlightScript.SLOW_MULTIPLIER
			)


func _try_block_ward_overlap() -> bool:
	if not monitoring or not is_inside_tree():
		return false
	for body in get_overlapping_bodies():
		if body == _caster:
			continue
		if _block_if_ward(body):
			return true
	return false


func _block_if_ward(body: Node) -> bool:
	if not SpellWardBlockScript.try_block(body):
		return false
	_finish()
	return true


func _finish() -> void:
	if _finished:
		return
	_finished = true
	set_physics_process(false)
	queue_free()
