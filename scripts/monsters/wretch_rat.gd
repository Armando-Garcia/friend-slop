class_name WretchRat
extends "res://scripts/monsters/summon_monster.gd"

## Small sphere minion for the Wretch. Sight-only aggro; explodes on player
## touch while chasing. Dies with host / fireball.

const GameWorldScript := preload("res://scripts/game_world.gd")

const SPHERE_MESH_RADIUS := 0.12
const FLASH_SPHERE_ALPHA := 0.6
const CHARGE_PULSE_HZ := 8.0
const LIGHT_START_RANGE := 0.15
## Wretch rats roam farther and hug the outer leash ring.
const LEASH_RADIUS_MULT := 1.4
const RAT_PATROL_EDGE_MIN := 0.88
const RAT_PATROL_EDGE_MAX := 0.99
const RAT_IDLE_DURATION_SEC := 0.35
const STILL_SPEED_EPS := 0.08

@export_range(0.2, 2.0, 0.05) var explode_radius: float = 0.55
## Knockback reaches farther than the damage / visual burst radius.
@export_range(0.5, 4.0, 0.05) var knockback_radius: float = 1.75
@export_range(0.1, 2.0, 0.01) var charge_sec: float = 0.34
@export_range(0.05, 0.5, 0.01) var flash_sec: float = 0.09
@export var glow_color: Color = Color(0.25, 1.0, 0.35, 1.0)
@export_range(1.0, 20.0, 0.5) var charge_light_energy: float = 12.0
@export_range(0.0, 40.0, 0.5) var explode_monster_damage: float = 8.0
## Explode if horizontal movement stays near zero this long.
@export_range(0.5, 10.0, 0.1) var still_explode_sec: float = 2.0

var _exploding: bool = false
var _exploded: bool = false
var _charge_age: float = 0.0
var _still_sec: float = 0.0

@onready var _explode_light: OmniLight3D = $Body/ExplodeLight


func bind_to_host(p_host: Node, p_leash_radius: float = 10.0) -> void:
	super.bind_to_host(p_host, p_leash_radius * LEASH_RADIUS_MULT)
	idle_duration_sec = RAT_IDLE_DURATION_SEC


func _random_leash_edge_point() -> Vector3:
	var host_pos := _host_position()
	var angle := _rng.randf() * TAU
	var dist := leash_radius * _rng.randf_range(RAT_PATROL_EDGE_MIN, RAT_PATROL_EDGE_MAX)
	return Vector3(
		host_pos.x + cos(angle) * dist,
		global_position.y,
		host_pos.z + sin(angle) * dist
	)


func _append_default_interest_candidates(_out: Array) -> void:
	## Rats use authored Sight sense only (no wide proximity aggro).
	pass


func apply_fireball_knockback(fireball_dir: Vector3) -> void:
	## Any fireball contact kills the rat.
	if not is_alive or _dying or _exploding or _exploded:
		return
	if fireball_dir.length_squared() > 0.0001:
		_last_hit_dir = fireball_dir.normalized()
	die()


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	if _exploding:
		_tick_explode_charge(delta)
		return
	super._physics_process(delta)
	_tick_stillness_fuse(delta)


func _tick_stillness_fuse(delta: float) -> void:
	if _exploding or _exploded or _dying or not is_alive:
		return
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if flat_speed <= STILL_SPEED_EPS:
		_still_sec += delta
		if _still_sec >= still_explode_sec:
			_begin_explode()
	else:
		_still_sec = 0.0


func _try_touch_damage(target: Node3D) -> void:
	## Single power: explode on player contact while chasing.
	if _exploding or _exploded or _dying or not is_alive:
		return
	if _ai_state != MonsterAIScript.State.CHASE:
		return
	if not _is_player_target(target) and not _player_in_attack_range():
		return
	_begin_explode()


func _is_player_target(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.is_in_group("player"):
		return true
	return (
		target.has_method("apply_rat_explode_hit")
		or target.has_method("apply_wretch_command_hit")
	)


func _player_in_attack_range() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for node in tree.get_nodes_in_group("player"):
		if node == null or not is_instance_valid(node) or not (node is Node3D):
			continue
		var player := node as Node3D
		var flat := Vector3(
			player.global_position.x - global_position.x,
			0.0,
			player.global_position.z - global_position.z
		)
		if flat.length() <= attack_range:
			return true
	return false


func _begin_explode() -> void:
	if _exploding or _exploded:
		return
	_exploding = true
	_charge_age = 0.0
	_still_sec = 0.0
	_cancel_cast()
	velocity = Vector3.ZERO

	var light := _explode_light
	if light != null:
		light.light_color = glow_color
		light.light_energy = charge_light_energy * 0.35
		light.omni_range = LIGHT_START_RANGE


func _tick_explode_charge(delta: float) -> void:
	if Engine.is_editor_hint() or not is_alive:
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_knockback_bleed(delta)
	move_and_slide()

	_charge_age += delta
	var t := clampf(_charge_age / maxf(charge_sec, 0.05), 0.0, 1.0)
	var light := _explode_light
	if light != null and is_instance_valid(light):
		## Strength pulses up/down while range grows toward explode_radius.
		var pulse := 0.35 + 0.65 * absf(sin(_charge_age * CHARGE_PULSE_HZ * TAU))
		var peak := lerpf(charge_light_energy * 0.45, charge_light_energy, t)
		light.light_energy = peak * pulse
		light.omni_range = lerpf(LIGHT_START_RANGE, explode_radius, t)

	if _charge_age >= charge_sec:
		_detonate()


func _detonate() -> void:
	if _exploded:
		return
	_exploded = true
	_exploding = true

	var origin := global_position + Vector3(0.0, 0.12, 0.0)
	## Hide / free authored visuals first so the burst reads clearly.
	_free_visual_children()
	_spawn_explode_flash(origin)
	_apply_explode_hits(origin)
	call_deferred("queue_free")


func _free_visual_children() -> void:
	for child_name in ["Body", "Head", "CollisionShape3D"]:
		var child := get_node_or_null(child_name)
		if child != null and is_instance_valid(child):
			child.queue_free()
	_explode_light = null


func _apply_explode_hits(origin: Vector3) -> void:
	var tree := get_tree()
	if tree == null:
		return

	var push_radius := maxf(knockback_radius, explode_radius)
	for node in tree.get_nodes_in_group("player"):
		if node == null or not is_instance_valid(node) or not (node is Node3D):
			continue
		var player := node as Node3D
		var flat := Vector3(
			player.global_position.x - origin.x,
			0.0,
			player.global_position.z - origin.z
		)
		if flat.length() > push_radius:
			continue
		var dir := flat
		if dir.length_squared() < 0.0001:
			dir = Vector3.FORWARD
		## Prefer the dedicated rat hit; authority is gated inside the player API.
		if player.has_method("apply_rat_explode_hit"):
			player.call("apply_rat_explode_hit", dir)
		elif player.has_method("apply_fireball_knockback"):
			player.call("apply_fireball_knockback", dir)

	if explode_monster_damage <= 0.0:
		return
	for node in tree.get_nodes_in_group("combat_target"):
		if node == null or not is_instance_valid(node) or node == self:
			continue
		if not (node is Node3D):
			continue
		var victim := node as Node3D
		if origin.distance_to(victim.global_position) > explode_radius:
			continue
		if victim.has_method("take_damage"):
			victim.call("take_damage", explode_monster_damage, self)


func _spawn_explode_flash(origin: Vector3) -> void:
	## Prefer the rat's 3D parent so the burst stays in the match world.
	var parent: Node = get_parent()
	if parent == null:
		parent = GameWorldScript.find_match_root(get_tree())
	if parent == null:
		return

	var flash := Node3D.new()
	flash.name = "WretchRatExplodeFlash"
	flash.top_level = true
	parent.add_child(flash)
	flash.global_position = origin

	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = SPHERE_MESH_RADIUS
	mesh.height = SPHERE_MESH_RADIUS * 2.0
	sphere.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(glow_color.r, glow_color.g, glow_color.b, FLASH_SPHERE_ALPHA)
	mat.emission_enabled = true
	mat.emission = glow_color
	mat.emission_energy_multiplier = 6.0
	sphere.material_override = mat
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sphere.layers = WorldVisualLayers.WORLD
	sphere.scale = Vector3.ONE * 0.2
	flash.add_child(sphere)

	var light := OmniLight3D.new()
	light.light_color = glow_color
	light.light_energy = charge_light_energy
	light.omni_range = explode_radius * 0.5
	light.shadow_enabled = false
	light.light_cull_mask = WorldVisualLayers.SCENE_LIGHT_MASK
	flash.add_child(light)

	var target_scale := explode_radius / SPHERE_MESH_RADIUS
	var duration := maxf(flash_sec, 0.05)
	var tween := flash.create_tween()
	tween.set_parallel(true)
	tween.tween_property(sphere, "scale", Vector3.ONE * target_scale, duration)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(light, "omni_range", explode_radius * 1.5, duration)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(light, "light_energy", 0.0, duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(flash.queue_free)
