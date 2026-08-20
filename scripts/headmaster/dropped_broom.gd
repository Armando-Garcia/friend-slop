class_name DroppedBroom
extends Interactable

## World broom after knock-off / contested dismount. Any player can pick up and mount.

const GameWorldScript := preload("res://scripts/game_world.gd")
const WorldGroundScript := preload("res://scripts/world_ground.gd")
const BroomScene := preload("res://scenes/characters/broom.tscn")
const BroomFlightScript := preload("res://scripts/headmaster/broom_flight.gd")
const SpellWorldSyncScript := preload("res://scripts/spells/spell_world_sync.gd")
const BUCKET_NAME := "DroppedBrooms"
const GRAVITY := 12.0
const LAND_SNAP_HEIGHT := 0.35
const MAX_FALL_SEC := 8.0

var spawn_id := ""
var _velocity := Vector3.ZERO
var _falling := true
var _elapsed := 0.0
var _visual: Node3D
var _claimed := false


static func spawn_networked(
	world_pos: Vector3,
	velocity: Vector3,
	from_player: Node = null
) -> void:
	var id := SpellWorldSyncScript.make_spawn_id(from_player as CharacterBody3D)
	if GameState.is_multiplayer and MatchStateManager.allows_gameplay_actions():
		_broadcast_drop(id, world_pos, velocity)
	else:
		spawn_local(id, world_pos, velocity)


static func _broadcast_drop(object_id: String, world_pos: Vector3, velocity: Vector3) -> void:
	if NetworkManager.multiplayer.is_server():
		NetworkManager._rpc_broom_drop.rpc(
			object_id,
			world_pos.x,
			world_pos.y,
			world_pos.z,
			velocity.x,
			velocity.y,
			velocity.z
		)
	else:
		NetworkManager._request_broom_drop.rpc_id(
			1,
			object_id,
			world_pos.x,
			world_pos.y,
			world_pos.z,
			velocity.x,
			velocity.y,
			velocity.z
		)


static func spawn_local(object_id: String, world_pos: Vector3, velocity: Vector3) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	if not object_id.is_empty():
		for node in tree.get_nodes_in_group("dropped_broom"):
			if node != null and str(node.get("spawn_id")) == object_id:
				return node
	var world := GameWorldScript.find_match_root(tree)
	if world == null:
		return null
	var bucket := world.get_node_or_null(BUCKET_NAME)
	if bucket == null:
		bucket = Node3D.new()
		bucket.name = BUCKET_NAME
		world.add_child(bucket)
	var broom = new()
	broom.spawn_id = object_id
	broom._velocity = velocity
	bucket.add_child(broom)
	broom.global_position = world_pos
	return broom


func _ready() -> void:
	prompt_text = "Pick up broom"
	super._ready()
	add_to_group("dropped_broom")
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.55
	shape.shape = sphere
	add_child(shape)
	_visual = BroomScene.instantiate() as Node3D
	add_child(_visual)
	_visual.rotation_degrees = Vector3(0.0, 0.0, -25.0)
	set_physics_process(true)


func interact(player: Node) -> void:
	if _claimed or player == null:
		return
	if not player is CharacterBody3D:
		return
	if bool(player.get("broom_active")):
		return
	_claimed = true
	var object_id := spawn_id
	if GameState.is_multiplayer and MatchStateManager.allows_gameplay_actions():
		var peer_id := 0
		if player.is_inside_tree() and player.multiplayer != null:
			peer_id = int(player.multiplayer.get_unique_id())
		_broadcast_pickup(object_id, peer_id)
	_mount_player(player as CharacterBody3D)
	queue_free()


static func _broadcast_pickup(object_id: String, peer_id: int) -> void:
	if NetworkManager.multiplayer.is_server():
		NetworkManager._rpc_broom_pickup.rpc(object_id, peer_id)
	else:
		NetworkManager._request_broom_pickup.rpc_id(1, object_id, peer_id)


static func apply_pickup(tree: SceneTree, object_id: String, _peer_id: int) -> void:
	## Picker mounts locally in interact(); every peer removes the world prop.
	if tree == null or object_id.is_empty():
		return
	for node in tree.get_nodes_in_group("dropped_broom"):
		if node != null and str(node.get("spawn_id")) == object_id:
			node.queue_free()
			return


func _mount_player(player: CharacterBody3D) -> void:
	## Pickup grants broom possession, then mounts (mesh becomes visible).
	var flight := BroomFlightScript.ensure_on(player, true)
	if flight != null and flight.has_method("mount_world_broom"):
		flight.call("mount_world_broom")
	elif flight != null and flight.has_method("mount"):
		flight.call("mount")


func _physics_process(delta: float) -> void:
	if not _falling:
		return
	_elapsed += delta
	_velocity.y -= GRAVITY * delta
	global_position += _velocity * delta
	if _elapsed >= MAX_FALL_SEC or _try_land():
		_land()


func _try_land() -> bool:
	if not is_inside_tree():
		return false
	var world_3d := get_world_3d()
	if world_3d == null or world_3d.direct_space_state == null:
		return false
	var from := global_position + Vector3.UP * 0.4
	var to := global_position + Vector3.DOWN * 0.8
	var ray := PhysicsRayQueryParameters3D.create(from, to)
	ray.collision_mask = 1
	var hit := world_3d.direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and _velocity.y <= 0.2


func _land() -> void:
	_falling = false
	_velocity = Vector3.ZERO
	set_physics_process(false)
	global_position = _snap_to_maze_floor(global_position)


func _snap_to_maze_floor(pos: Vector3) -> Vector3:
	var tree := get_tree()
	var maze: Node = null
	var match_root := GameWorldScript.find_match_root(tree)
	if match_root != null:
		maze = match_root.get_node_or_null("MazeGenerator")
	var floor_pos := pos
	if maze != null and maze.has_method("world_to_cell") and maze.has_method("is_grid_open"):
		var cell: Vector2i = maze.call("world_to_cell", pos)
		if not bool(maze.call("is_grid_open", cell.x, cell.y)):
			cell = _nearest_open_grid(maze, cell)
		if maze.has_method("grid_to_world"):
			floor_pos = maze.call("grid_to_world", cell.x, cell.y)
	var world_3d := get_world_3d()
	floor_pos = WorldGroundScript.with_height_above_ground(
		world_3d, floor_pos, LAND_SNAP_HEIGHT, floor_pos.y
	)
	return floor_pos


func _nearest_open_grid(maze: Node, start: Vector2i) -> Vector2i:
	if bool(maze.call("is_grid_open", start.x, start.y)):
		return start
	for radius in range(1, 24):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var c := Vector2i(start.x + dx, start.y + dy)
				if bool(maze.call("is_grid_open", c.x, c.y)):
					return c
	return start
