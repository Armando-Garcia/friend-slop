class_name PlayerStun
extends Node

## Authored under PlayableCharacter/Stun. Locks move + cast, launches on a
## ballistic arc, then keeps the player stunned until after they land.

const ChargerLaunchScript := preload("res://scripts/monsters/charger_launch.gd")
const WorldGroundScript := preload("res://scripts/world_ground.gd")

const POST_LAND_STUN_SEC := 1.5
const OVERLAY_WORD := "stunned"

@export var visual_active: bool = false:
	set(value):
		visual_active = value
		if is_inside_tree():
			_sync_visuals()

var _player: CharacterBody3D = null
var _stunned: bool = false
var _airborne: bool = false
var _post_land_left: float = 0.0
var _launch_vel: Vector3 = Vector3.ZERO
var _ground_y: float = 0.0
var _overlay_root: Node3D = null
var _world_stars: Node = null
var _cam_stars: Node = null


func _ready() -> void:
	_ensure_player()
	_sync_visuals()


func _ensure_player() -> CharacterBody3D:
	if _player == null or not is_instance_valid(_player):
		_player = get_parent() as CharacterBody3D
		_cache_fx_nodes()
	return _player


func is_stunned() -> bool:
	return _stunned


func is_launching() -> bool:
	return _stunned and _airborne


func begin_charger_hit(landing_world: Vector3, gravity: float) -> void:
	_ensure_player()
	if _player != null and not _player.is_multiplayer_authority() and GameState.is_multiplayer:
		return
	if _player == null:
		return
	_cancel_player_actions()
	var from := _player.global_position
	_ground_y = from.y
	var to := _snap_landing(landing_world, from.y)
	var horiz := Vector3(to.x - from.x, 0.0, to.z - from.z).length()
	var flight := ChargerLaunchScript.flight_time_for_distance(horiz)
	_launch_vel = ChargerLaunchScript.launch_velocity(from, to, gravity, flight)
	_player.velocity = _launch_vel
	_stunned = true
	_airborne = true
	_post_land_left = 0.0
	visual_active = true
	_knock_off_broom()


func tick_lookdev(delta: float, gravity: float) -> void:
	_ensure_player()
	if not _stunned or _player == null:
		return
	if _airborne:
		_player.velocity.y -= maxf(gravity, 0.0) * delta
		_player.global_position += _player.velocity * delta
		if _player.global_position.y <= _ground_y:
			_player.global_position.y = _ground_y
			_begin_post_land()
		return
	_player.velocity = Vector3.ZERO
	_post_land_left -= delta
	if _post_land_left <= 0.0:
		_end_stun()


func tick_physics(player: CharacterBody3D, delta: float, gravity: float) -> void:
	if not _stunned or player == null:
		return
	if not player.is_on_floor():
		player.velocity.y -= gravity * delta
	if _airborne:
		player.velocity.x = _launch_vel.x
		player.velocity.z = _launch_vel.z
		_launch_vel.y = player.velocity.y
		if player.is_on_floor() and player.velocity.y <= 0.15:
			_begin_post_land()
		return
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	_post_land_left -= delta
	if _post_land_left <= 0.0:
		_end_stun()


@rpc("any_peer", "call_remote", "reliable")
func rpc_begin_charger_hit(landing_world: Vector3) -> void:
	if GameState.is_multiplayer:
		var sender := multiplayer.get_remote_sender_id()
		if sender != 0 and sender != 1:
			return
	_ensure_player()
	var g := ChargerLaunchScript.gravity_of(_player, 18.0)
	begin_charger_hit(landing_world, g)


func _begin_post_land() -> void:
	_airborne = false
	_launch_vel = Vector3.ZERO
	_post_land_left = POST_LAND_STUN_SEC
	if _player != null:
		_player.velocity.x = 0.0
		_player.velocity.z = 0.0
		_player.velocity.y = 0.0


func _end_stun() -> void:
	_stunned = false
	_airborne = false
	_post_land_left = 0.0
	_launch_vel = Vector3.ZERO
	visual_active = false


func _cancel_player_actions() -> void:
	if _player == null:
		return
	if _player.has_method("stop_casting_for_relic_carry"):
		_player.call("stop_casting_for_relic_carry")
	if _player.has_method("_cancel_spell_fire_charge"):
		_player.call("_cancel_spell_fire_charge", true)


func _knock_off_broom() -> void:
	if _player == null:
		return
	var active = _player.get("broom_active")
	if active == null or not bool(active):
		return
	var flight := _player.get_node_or_null("BroomFlight")
	if flight != null and flight.has_method("knock_off"):
		flight.call("knock_off", _launch_vel)


func _snap_landing(landing_world: Vector3, fallback_y: float) -> Vector3:
	var pos := landing_world
	if _player == null or not _player.is_inside_tree():
		pos.y = fallback_y
		return pos
	pos = WorldGroundScript.with_height_above_ground(
		_player.get_world_3d(), pos, 0.0, fallback_y
	)
	return pos


func _cache_fx_nodes() -> void:
	if _player == null:
		return
	_world_stars = _player.get_node_or_null("StunStars")
	var cam := _player.get_node_or_null("%FirstPersonCamera") as Camera3D
	if cam != null:
		_overlay_root = cam.get_node_or_null("StunOverlay") as Node3D
	if _overlay_root != null:
		_cam_stars = _overlay_root.get_node_or_null("StunStars")
		var word := _overlay_root.get_node_or_null("StunnedWord") as Label3D
		if word != null:
			word.text = OVERLAY_WORD


func _uses_local_view() -> bool:
	if _player == null:
		return false
	if _player.has_method("_uses_local_view"):
		return bool(_player.call("_uses_local_view"))
	return true


func _set_stars_active(node: Node, on: bool) -> void:
	if node != null and node.has_method("set_active"):
		node.call("set_active", on)


func _sync_visuals() -> void:
	var on := visual_active
	var local_view := on and _uses_local_view()
	if _overlay_root != null:
		_overlay_root.visible = local_view
	_set_stars_active(_cam_stars, local_view)
	_set_stars_active(_world_stars, on and not local_view)
