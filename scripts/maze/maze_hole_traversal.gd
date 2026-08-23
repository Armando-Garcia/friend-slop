class_name MazeHoleTraversal
extends RefCounted

## Burrow dash through gnome holes for gnomes and crouching (or test-sized) players.


const GnomeDigExecutorScript := preload("res://scripts/gnomes/gnome_dig_executor.gd")
const PlayerCrouchScript := preload("res://scripts/characters/player_crouch.gd")

const META_ACTIVE := "_maze_hole_burrow_active"
const META_WAYPOINTS := "_maze_hole_burrow_waypoints"
const META_WAYPOINT_INDEX := "_maze_hole_burrow_wp_index"
const META_WAS_CROUCHING := "_maze_hole_was_crouching"

const BURROW_SPEED := 5.75
const HOLE_PROBE_RADIUS := 1.25
const HOLE_ENTER_DIST := 0.72
const HOLE_ALIGN_DOT := 0.15


static func is_active(body: CharacterBody3D) -> bool:
	return bool(body.get_meta(META_ACTIVE, false))


static func can_use_holes(body: CharacterBody3D) -> bool:
	if body == null:
		return false
	if body.is_in_group("gnome"):
		return true
	if body.is_in_group("player"):
		return PlayerCrouchScript.is_crouching(body)
	return false


static func begin_from_job(body: CharacterBody3D, job: Dictionary) -> void:
	var body_pos := _body_pos(body)
	var approach: Vector3 = job.get("approach", body_pos)
	var exit_pos: Vector3 = job.get("exit", approach)
	approach.y = body_pos.y
	exit_pos.y = body_pos.y
	var center := approach.lerp(exit_pos, 0.5)
	center.y = body_pos.y
	begin(body, [approach, center, exit_pos])


static func begin(body: CharacterBody3D, waypoints: Array) -> void:
	if body == null or waypoints.size() < 2:
		return
	body.set_meta(META_ACTIVE, true)
	body.set_meta(META_WAYPOINTS, waypoints.duplicate())
	body.set_meta(META_WAYPOINT_INDEX, 0)
	_apply_burrow_pose(body, true)
	body.velocity = Vector3.ZERO


## Returns true when the burrow path is finished.
static func tick(body: CharacterBody3D, delta: float) -> bool:
	if body == null or not is_active(body):
		return true
	var waypoints: Array = body.get_meta(META_WAYPOINTS, [])
	var idx := int(body.get_meta(META_WAYPOINT_INDEX, 0))
	if idx >= waypoints.size() - 1:
		_finish(body)
		return true
	var body_pos := _body_pos(body)
	var target: Vector3 = waypoints[idx + 1]
	target.y = body_pos.y
	var flat := Vector3(target.x - body_pos.x, 0.0, target.z - body_pos.z)
	var dist := flat.length()
	var step := BURROW_SPEED * delta
	if dist <= maxf(step, 0.08):
		_set_body_pos(body, target)
		idx += 1
		body.set_meta(META_WAYPOINT_INDEX, idx)
		if idx >= waypoints.size() - 1:
			_finish(body)
			return true
		return false
	var dir := flat / dist
	_set_body_pos(body, body_pos + dir * step)
	body.velocity = Vector3(dir.x * BURROW_SPEED, 0.0, dir.z * BURROW_SPEED)
	_face_horizontal(body, dir)
	return false


static func try_enter_nearby_hole(body: CharacterBody3D) -> bool:
	if body == null or is_active(body) or not can_use_holes(body):
		return false
	var vel := body.velocity
	if vel.length_squared() < 0.08:
		return false
	var move_dir := Vector3(vel.x, 0.0, vel.z).normalized()
	var tree := body.get_tree()
	if tree == null:
		return false
	var body_pos := _body_pos(body)
	var best_hole: Node3D = null
	var best_score := INF
	for node in tree.get_nodes_in_group("maze_hole"):
		if not (node is Node3D):
			continue
		var hole := node as Node3D
		if not hole.has_method("burrow_waypoints"):
			continue
		var mouth := hole.global_position
		mouth.y = body_pos.y
		var to_hole := Vector3(mouth.x - body_pos.x, 0.0, mouth.z - body_pos.z)
		var dist := to_hole.length()
		if dist > HOLE_PROBE_RADIUS:
			continue
		if dist > 0.001:
			var align := to_hole.normalized().dot(move_dir)
			if align < HOLE_ALIGN_DOT:
				continue
		var score := dist - to_hole.normalized().dot(move_dir) * 0.35
		if score < best_score:
			best_score = score
			best_hole = hole
	if best_hole == null:
		return false
	var waypoints: Array = best_hole.call("burrow_waypoints", body_pos.y)
	if waypoints.size() < 2:
		return false
	var entry: Vector3 = waypoints[0]
	entry.y = body_pos.y
	if body_pos.distance_to(entry) > HOLE_ENTER_DIST:
		return false
	begin(body, waypoints)
	return true


static func _apply_burrow_pose(body: CharacterBody3D, active: bool) -> void:
	if body.is_in_group("gnome"):
		GnomeDigExecutorScript.set_crawl_pose(body, active)
		return
	if not body.is_in_group("player"):
		return
	if active:
		body.set_meta(META_WAS_CROUCHING, PlayerCrouchScript.is_crouching(body))
		PlayerCrouchScript.apply_crouch_collision(body, true)
		return
	var was_crouching := bool(body.get_meta(META_WAS_CROUCHING, false))
	body.remove_meta(META_WAS_CROUCHING)
	if not was_crouching:
		PlayerCrouchScript.apply_crouch_collision(body, false)


static func _finish(body: CharacterBody3D) -> void:
	body.set_meta(META_ACTIVE, false)
	body.remove_meta(META_WAYPOINTS)
	body.remove_meta(META_WAYPOINT_INDEX)
	_apply_burrow_pose(body, false)
	body.velocity = Vector3.ZERO


static func _face_horizontal(body: CharacterBody3D, dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	var from := _body_pos(body)
	var target := from + dir
	target.y = from.y
	if body.is_inside_tree():
		body.look_at(target, Vector3.UP)
	else:
		body.look_at_from_position(from, target, Vector3.UP)


static func _body_pos(body: Node3D) -> Vector3:
	return body.global_position if body.is_inside_tree() else body.position


static func _set_body_pos(body: Node3D, pos: Vector3) -> void:
	if body.is_inside_tree():
		body.global_position = pos
	else:
		body.position = pos
