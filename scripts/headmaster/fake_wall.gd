class_name FakeWall
extends Area3D

## Visual maze-wall decoy: looks solid, players and fireballs pass through.
## Contact briefly flickers the illusion; Dispell destroys it.
## Uses SpellWorldSync for multiplayer spawn identity + events.

const SpellWorldSyncScript := preload("res://scripts/spells/spell_world_sync.gd")
const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")

const GROUP_NAME := SpellWorldSyncScript.KIND_FAKE_WALL
const PLAYER_LAYER := 1
const FLICKER_COOLDOWN_SEC := 0.4
const FLICKER_PULSE_SEC := 0.08
const DESPAWN_FADE_SEC := 0.6

var spawn_id := ""
var grid_cell := Vector2i(-1, -1)

var _half_extents := Vector3(1.5, 1.5, 1.5)
var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _base_albedo := Color(0.52, 0.46, 0.58)
var _flicker_tween: Tween
var _despawn_tween: Tween
var _next_flicker_at_msec := 0
var _despawning := false


static func spawn(
	parent: Node,
	world_position: Vector3,
	wall_size: Vector3,
	cell: Vector2i
) -> Area3D:
	var wall = new()
	wall.grid_cell = cell
	wall.spawn_id = SpellWorldSyncScript.make_cell_id(cell)
	parent.add_child(wall)
	wall.global_position = world_position
	wall._build(wall_size)
	return wall


func _ready() -> void:
	if spawn_id.is_empty() and grid_cell.x >= 0:
		spawn_id = SpellWorldSyncScript.make_cell_id(grid_cell)
	SpellWorldSyncScript.register(self, SpellWorldSyncScript.KIND_FAKE_WALL, spawn_id)
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = PLAYER_LAYER
	body_entered.connect(_on_body_entered)


func get_spell_world_kind() -> String:
	return SpellWorldSyncScript.KIND_FAKE_WALL


func get_spell_world_id() -> String:
	if not spawn_id.is_empty():
		return spawn_id
	return SpellWorldSyncScript.make_cell_id(grid_cell)


func destroy_from_spell(from_network: bool = false) -> void:
	if _despawning or not is_inside_tree():
		return
	_despawning = true
	if not from_network:
		SpellWorldSyncScript.broadcast_event(self, SpellWorldSyncScript.EVENT_REMOVE)
	_begin_despawn_fade()


func notify_spell_touch(point: Vector3, radius: float) -> void:
	## Fireballs are simulated on every peer; keep flicker local to avoid RPC storms.
	if _despawning:
		return
	if _sphere_overlaps(point, radius):
		flicker(false, false)


func flicker(from_network: bool = false, sync_to_peers: bool = true) -> void:
	if _despawning or _material == null or not is_inside_tree():
		return
	var now := Time.get_ticks_msec()
	if now < _next_flicker_at_msec:
		return
	_next_flicker_at_msec = now + int(FLICKER_COOLDOWN_SEC * 1000.0)
	_play_flicker_visual()
	if from_network or not sync_to_peers:
		return
	SpellWorldSyncScript.broadcast_event(self, SpellWorldSyncScript.EVENT_FLICKER)


func _begin_despawn_fade() -> void:
	monitoring = false
	collision_mask = 0
	if is_in_group(GROUP_NAME):
		remove_from_group(GROUP_NAME)
	if is_in_group(SpellWorldSyncScript.GROUP_NAME):
		remove_from_group(SpellWorldSyncScript.GROUP_NAME)
	if _flicker_tween != null and _flicker_tween.is_valid():
		_flicker_tween.kill()
		_flicker_tween = null
	if _despawn_tween != null and _despawn_tween.is_valid():
		_despawn_tween.kill()
	if _material == null:
		queue_free()
		return
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if _mesh_instance != null:
		_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var clear := Color(_base_albedo.r, _base_albedo.g, _base_albedo.b, 0.0)
	_despawn_tween = create_tween()
	_despawn_tween.set_trans(Tween.TRANS_SINE)
	_despawn_tween.set_ease(Tween.EASE_IN)
	_despawn_tween.tween_property(_material, "albedo_color", clear, DESPAWN_FADE_SEC)
	_despawn_tween.tween_callback(queue_free)


func _play_flicker_visual() -> void:
	if _despawning or _material == null:
		return
	if _flicker_tween != null and _flicker_tween.is_valid():
		_flicker_tween.kill()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = _base_albedo
	_flicker_tween = create_tween()
	_flicker_tween.set_trans(Tween.TRANS_SINE)
	_flicker_tween.set_ease(Tween.EASE_IN_OUT)
	var ghost := Color(_base_albedo.r, _base_albedo.g, _base_albedo.b, 0.22)
	var mid := Color(_base_albedo.r, _base_albedo.g, _base_albedo.b, 0.72)
	_flicker_tween.tween_property(_material, "albedo_color", ghost, FLICKER_PULSE_SEC)
	_flicker_tween.tween_property(_material, "albedo_color", mid, FLICKER_PULSE_SEC)
	_flicker_tween.tween_property(_material, "albedo_color", ghost, FLICKER_PULSE_SEC)
	_flicker_tween.tween_property(_material, "albedo_color", _base_albedo, FLICKER_PULSE_SEC)
	_flicker_tween.tween_callback(_restore_opaque)


func _on_body_entered(body: Node3D) -> void:
	if _despawning:
		return
	if body == null or not body.is_in_group("player"):
		return
	## Only the owning peer of the walker broadcasts; remote puppets skip.
	var game_state := get_tree().root.get_node_or_null("GameState") if get_tree() else null
	if (
		game_state != null
		and bool(game_state.get("is_multiplayer"))
		and not body.is_multiplayer_authority()
	):
		return
	flicker(false, true)


func _restore_opaque() -> void:
	if _despawning or _material == null:
		return
	_material.albedo_color = _base_albedo
	_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED


func _sphere_overlaps(point: Vector3, radius: float) -> bool:
	var local := to_local(point)
	var closest := Vector3(
		clampf(local.x, -_half_extents.x, _half_extents.x),
		clampf(local.y, -_half_extents.y, _half_extents.y),
		clampf(local.z, -_half_extents.z, _half_extents.z)
	)
	return local.distance_squared_to(closest) <= radius * radius


func _build(wall_size: Vector3) -> void:
	_half_extents = wall_size * 0.5
	_mesh_instance = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = wall_size
	_mesh_instance.mesh = box
	_material = StandardMaterial3D.new()
	_material.albedo_color = _base_albedo
	_material.roughness = 0.7
	_mesh_instance.material_override = _material
	_mesh_instance.layers = WorldVisualLayersScript.WORLD
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = wall_size
	collision.shape = shape
	add_child(collision)
