@tool
class_name FlareEffect
extends Area3D

## Flare rocket — launches fast, coasts, then sticks on contact as a beacon.

const DEFAULT_DURATION_SEC := 15.0
const SCENE_PATH := "res://scenes/spells/flare.tscn"

const FlareFlightScript := preload("res://scripts/spells/flare_flight.gd")
const FireballLightingScript := preload("res://scripts/spells/fireball_lighting.gd")
const SpellEphemeralFxScript := preload("res://scripts/spells/spell_ephemeral_fx.gd")

@export_group("Beacon")
@export_range(2.0, 80.0, 0.5) var light_peak_energy: float = 36.0
@export_range(40.0, 480.0, 1.0) var light_range: float = 320.0
@export_range(4.0, 60.0, 0.5) var duration_sec: float = DEFAULT_DURATION_SEC
@export_range(0.01, 0.5, 0.005) var core_radius: float = 0.04:
	set(value):
		core_radius = maxf(value, 0.005)
		_apply_core_visual_size()
@export_range(0.05, 1.0, 0.01) var hit_radius: float = FlareFlightScript.HIT_RADIUS:
	set(value):
		hit_radius = maxf(value, 0.02)
		_sync_hit_shape()

@export_group("Flight")
@export_range(1.0, 120.0, 0.5) var launch_speed: float = FlareFlightScript.LAUNCH_SPEED
@export_range(0.0, 8.0, 0.01) var drag: float = FlareFlightScript.DRAG
@export_range(0.0, 40.0, 0.1) var flight_gravity: float = FlareFlightScript.GRAVITY

@export_group("Editor preview")
@export var preview_loop := false:
	set(value):
		preview_loop = value
		if Engine.is_editor_hint() and is_inside_tree():
			_refresh_preview()
@export_tool_button("Replay Launch", "Callable")
var replay_launch_action := replay_launch

var _thermite_core: MeshInstance3D
var _thermite_material: StandardMaterial3D
var _beacon_light: OmniLight3D
var _collision: CollisionShape3D
var _hit_shape: SphereShape3D
var _pulse_tween: Tween
var _life_tween: Tween
var _runtime := false
var _playing := false
var _flying := false
var _direction := Vector3.UP
var _velocity := Vector3.ZERO
var _caster: Node3D
var _life_t := 0.0
var _pulse_t := 1.0


static func spawn(
	parent: Node,
	world_position: Vector3,
	duration: float = DEFAULT_DURATION_SEC
) -> FlareEffect:
	## Stationary lookdev / tests — no flight.
	return spawn_launched(parent, world_position, Vector3.ZERO, duration, false)


static func spawn_launched(
	parent: Node,
	origin: Vector3,
	direction: Vector3,
	duration: float = DEFAULT_DURATION_SEC,
	fly: bool = true,
	caster: Node3D = null
) -> FlareEffect:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var flare: FlareEffect = packed.instantiate() as FlareEffect
	flare._runtime = true
	flare.preview_loop = false
	flare.duration_sec = maxf(duration, 1.0)
	flare._flying = fly
	flare._caster = caster
	if fly:
		flare._velocity = FlareFlightScript.initial_velocity(direction, flare.launch_speed)
		flare._direction = FlareFlightScript.launch_direction(direction)
	else:
		flare._velocity = Vector3.ZERO
		flare._direction = Vector3.ZERO
	## Place before add_child so `_ready` beacon is not at Match origin.
	SpellEphemeralFxScript.add_child_at(parent, flare, origin)
	flare.play_launch()
	return flare


## charge 0 → base launch speed / dimmer beacon; charge 1 → +56.25% speed / full light.
func apply_charge_power(charge_factor: float) -> void:
	var t := clampf(charge_factor, 0.0, 1.0)
	light_peak_energy = light_peak_energy * lerpf(0.55, 1.0, t)
	var speed_max := launch_speed
	launch_speed = speed_max * lerpf(1.0, 1.5625, t)
	if _flying:
		var aim := _direction if _direction.length_squared() > 0.0001 else Vector3.FORWARD
		_velocity = FlareFlightScript.initial_velocity(aim, launch_speed)
	_refresh_visual_state()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	collision_layer = 0
	collision_mask = 1
	monitorable = false
	_cache_nodes()
	_configure_authored_nodes()
	_sync_hit_shape()
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	## Runtime play happens in spawn_launched() after global_position is set.
	if Engine.is_editor_hint() and not _runtime:
		monitoring = false
		set_physics_process(false)
		set_process(false)
		_refresh_preview()


func _process(delta: float) -> void:
	## Editor tool buttons don't tick physics — drive preview flight here.
	if Engine.is_editor_hint():
		_step_flight(delta)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_step_flight(delta)


func _step_flight(delta: float) -> void:
	if not _playing or not _flying:
		return
	_velocity = FlareFlightScript.step_velocity(_velocity, delta, drag, flight_gravity)
	var motion := _velocity * delta
	if _cast_motion_hit(motion):
		return
	global_position += motion
	if _velocity.length_squared() > 0.0001:
		_direction = _velocity.normalized()
	_touch_fake_walls()
	if _probe_players():
		return
	_refresh_visual_state()


func replay_launch() -> void:
	play_launch()


func play_launch() -> void:
	if not is_inside_tree():
		return
	_cache_nodes()
	_configure_authored_nodes()
	_sync_hit_shape()
	_stop_tweens()
	_playing = true
	_life_t = 0.0
	_pulse_t = 1.0

	_reset_core_visuals()
	_refresh_visual_state()
	_start_beacon_pulse()
	_start_lifespan()
	monitoring = _flying and _runtime and not Engine.is_editor_hint()
	## Physics ticks in play mode; editor previews use _process instead.
	set_physics_process(_flying and not Engine.is_editor_hint())
	set_process(_flying and Engine.is_editor_hint())


func _cache_nodes() -> void:
	_thermite_core = get_node_or_null("ThermiteCore") as MeshInstance3D
	_beacon_light = get_node_or_null("BeaconLight") as OmniLight3D
	_collision = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collision != null and _collision.shape is SphereShape3D:
		_hit_shape = _collision.shape as SphereShape3D
	_thermite_material = _duplicate_mesh_material(_thermite_core, _thermite_material)


func _duplicate_mesh_material(
	mesh: MeshInstance3D,
	cached: StandardMaterial3D
) -> StandardMaterial3D:
	if mesh == null or not (mesh.material_override is StandardMaterial3D):
		return cached
	if cached != null and mesh.material_override == cached:
		return cached
	var duplicated := (mesh.material_override as StandardMaterial3D).duplicate()
	mesh.material_override = duplicated
	return duplicated


func _configure_authored_nodes() -> void:
	_configure_beacon_lights()
	_harden_core_material()
	_ensure_unit_core_mesh()
	_apply_core_visual_size()


func _configure_beacon_lights() -> void:
	## CRITICAL: volumetric fog energy must stay 0. Non-zero draws a hard red ball
	## in match volumetric fog (omni_range sphere), even with no glow meshes.
	if _beacon_light != null:
		FireballLightingScript.configure_cast_light(
			_beacon_light,
			light_peak_energy,
			light_range,
			_beacon_light.light_color,
			false,
			0.0
		)
		_beacon_light.light_volumetric_fog_energy = 0.0
		_beacon_light.set_param(Light3D.PARAM_VOLUMETRIC_FOG_ENERGY, 0.0)
		_beacon_light.shadow_enabled = false


func _sync_hit_shape() -> void:
	if _collision == null:
		_collision = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collision == null:
		return
	var shape := _collision.shape as SphereShape3D
	if shape == null:
		shape = SphereShape3D.new()
		_collision.shape = shape
	shape.radius = hit_radius
	_hit_shape = shape


func _ensure_unit_core_mesh() -> void:
	## Unit sphere — visual size comes only from core_radius via node scale.
	if _thermite_core == null:
		_thermite_core = get_node_or_null("ThermiteCore") as MeshInstance3D
	if _thermite_core == null:
		return
	var sphere := _thermite_core.mesh as SphereMesh
	if sphere == null:
		sphere = SphereMesh.new()
		sphere.radial_segments = 12
		sphere.rings = 6
		_thermite_core.mesh = sphere
	sphere.radius = 1.0
	sphere.height = 2.0


func _apply_core_visual_size() -> void:
	if not is_inside_tree():
		return
	if _thermite_core == null:
		_thermite_core = get_node_or_null("ThermiteCore") as MeshInstance3D
	if _thermite_core == null:
		return
	_thermite_core.scale = Vector3.ONE * _core_display_radius()


func _core_display_radius() -> float:
	## core_radius is the authored visual size; life/pulse only shrinks it over time.
	var life_mul := lerpf(1.0, 0.35, clampf(_life_t, 0.0, 1.0))
	var pulse_mul := lerpf(0.96, 1.02, clampf(_pulse_t, 0.0, 1.0))
	return core_radius * life_mul * pulse_mul


func _harden_core_material() -> void:
	if _thermite_material == null:
		return
	## Opaque emissive point — additive/transparent soft discs read as a glow ball.
	_thermite_material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_thermite_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_thermite_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_thermite_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_thermite_material.cull_mode = BaseMaterial3D.CULL_BACK
	_thermite_material.no_depth_test = false
	_thermite_material.albedo_texture = null
	_thermite_material.emission_enabled = true
	_thermite_material.emission = Color(1.0, 0.95, 0.8)
	_thermite_material.albedo_color = Color(1.0, 0.97, 0.88, 1.0)


func _reset_core_visuals() -> void:
	if _thermite_core != null:
		_thermite_core.visible = true
	_apply_core_visual_size()
	if _thermite_material != null:
		_thermite_material.emission_energy_multiplier = 4.0
		_thermite_material.albedo_color = Color(1.0, 0.97, 0.88, 1.0)
	if _beacon_light != null:
		_beacon_light.visible = true
		_beacon_light.omni_range = light_range
		_beacon_light.light_volumetric_fog_energy = 0.0
		_beacon_light.set_param(Light3D.PARAM_VOLUMETRIC_FOG_ENERGY, 0.0)


func _refresh_preview() -> void:
	if preview_loop:
		_flying = false
		play_launch()
	else:
		_stop_tweens()


func _cast_motion_hit(motion: Vector3) -> bool:
	if _hit_shape == null or not is_inside_tree():
		return false
	var space_state := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _hit_shape
	params.transform = global_transform
	params.motion = motion
	params.exclude = _exclude_rids()
	params.collision_mask = collision_mask
	var contact := space_state.cast_motion(params)
	var safe_fraction: float = contact[0]
	if safe_fraction >= 1.0:
		return false
	global_position += motion * safe_fraction
	if _probe_players():
		return true
	_stick(null)
	return true


func _exclude_rids() -> Array:
	var rids: Array = [get_rid()]
	if _caster is CollisionObject3D:
		rids.append((_caster as CollisionObject3D).get_rid())
	return rids


func _probe_players() -> bool:
	if not is_inside_tree() or _hit_shape == null:
		return false
	var space_state := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _hit_shape
	params.transform = global_transform
	params.exclude = _exclude_rids()
	params.collision_mask = collision_mask
	var hits := space_state.intersect_shape(params, 8)
	for hit in hits:
		var collider: Variant = hit.get("collider")
		if collider is Node3D and _try_hit_player(collider as Node3D):
			return true
	return false


func _touch_fake_walls() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var radius := hit_radius * 1.35
	for node in tree.get_nodes_in_group("fake_wall"):
		if node != null and node.has_method("notify_spell_touch"):
			node.call("notify_spell_touch", global_position, radius)


func _on_body_entered(body: Node3D) -> void:
	if not _flying:
		return
	if _try_hit_player(body):
		return
	if body == _caster:
		return
	_stick(null)


func _try_hit_player(body: Node3D) -> bool:
	if body == null or body == _caster:
		return false
	if not body.is_in_group("player"):
		return false
	_stick(body)
	return true


func _stick(host: Node3D) -> void:
	if not _flying:
		return
	_flying = false
	_velocity = Vector3.ZERO
	monitoring = false
	set_physics_process(false)
	set_process(false)
	if host != null and host.is_in_group("player") and host.is_inside_tree():
		reparent(host, true)
	_refresh_visual_state()


func _start_beacon_pulse() -> void:
	_pulse_tween = create_tween()
	_pulse_tween.set_loops()
	_pulse_tween.tween_method(_set_pulse_t, 1.0, 0.55, 0.75)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_method(_set_pulse_t, 0.55, 1.0, 0.75)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _start_lifespan() -> void:
	if Engine.is_editor_hint() and not _runtime and preview_loop:
		_life_t = 0.0
		_refresh_visual_state()
		return
	var life_sec := maxf(duration_sec, 1.0)
	_life_tween = create_tween()
	_life_tween.tween_method(_set_life_t, 0.0, 1.0, life_sec)\
		.set_trans(Tween.TRANS_LINEAR)
	_life_tween.tween_callback(_on_finished)


func _set_pulse_t(value: float) -> void:
	_pulse_t = value
	_refresh_visual_state()


func _set_life_t(value: float) -> void:
	_life_t = value
	_refresh_visual_state()


func _refresh_visual_state() -> void:
	var envelope: float = pow(1.0 - clampf(_life_t, 0.0, 1.0), 1.25)
	var pulse: float = lerpf(0.82, 1.0, clampf(_pulse_t, 0.0, 1.0))
	var strength: float = envelope * pulse

	_apply_core_visual_size()

	if _thermite_material != null:
		_thermite_material.emission_energy_multiplier = 4.0 * strength
		_thermite_material.albedo_color = Color(1.0, 0.97, 0.88, 1.0)

	if _beacon_light != null:
		_beacon_light.light_energy = light_peak_energy * strength
		_beacon_light.omni_range = lerpf(light_range, light_range * 0.7, _life_t)
		## Re-assert every tick — shared light helpers default fog energy to 6.
		_beacon_light.light_volumetric_fog_energy = 0.0
		_beacon_light.set_param(Light3D.PARAM_VOLUMETRIC_FOG_ENERGY, 0.0)


func _on_finished() -> void:
	_playing = false
	_flying = false
	_stop_tweens()
	if Engine.is_editor_hint() and not _runtime and preview_loop:
		play_launch()
		return
	if _runtime:
		queue_free()


func _stop_tweens() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	if _life_tween != null and _life_tween.is_valid():
		_life_tween.kill()
	_life_tween = null
