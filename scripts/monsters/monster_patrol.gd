class_name MonsterPatrol
extends RefCounted

## Walk maze centerlines on a loose patrol rect. Cross rooms on maze lines.

const MazePathGraphScript := preload("res://scripts/maze_path_graph.gd")

const SAMPLE_COUNT := 8
const RAY_HEIGHT := 0.45
const RAY_START := 0.28
const WORLD_MASK := 1
const ARRIVE_DIST := 0.45
const WALK_SPEED_MULT := 0.8
const GROUP_PATHS := &"maze_paths"

var graph: Dictionary = {}
var home: Vector3 = Vector3.ZERO
var home_set: bool = false
var radius: float = 8.0
var size: Vector2 = Vector2(16.0, 16.0)
var preferred: PackedInt32Array = PackedInt32Array()
var viable: PackedInt32Array = PackedInt32Array()
var segment_id: int = -1
var toward_b: bool = true
var goal: Vector3 = Vector3.ZERO
var _pref_home: Vector3 = Vector3.INF
var _pref_size: Vector2 = Vector2(-1.0, -1.0)
var _pref_seg_count: int = -1


func set_home(world_pos: Vector3) -> void:
	home = world_pos
	home_set = true


func begin(body: CharacterBody3D, rng: RandomNumberGenerator, patrol_radius: float) -> void:
	radius = maxf(patrol_radius, 0.5)
	size = Vector2(radius * 2.0, radius * 2.0)
	graph = find_graph(body)
	if body != null and body.has_meta("patrol_home"):
		set_home(body.get_meta("patrol_home"))
	if not home_set and body != null:
		home = body.global_position if body.is_inside_tree() else body.position
		home_set = true
	_sync_routes(body)
	var segments: Array = graph.get("segments", [])
	if body == null or segments.is_empty():
		goal = pick_goal(body, radius, rng)
		segment_id = -1
		return
	_snap_to_path(body)
	_refresh_goal(body)


func tick(body: CharacterBody3D, rng: RandomNumberGenerator) -> void:
	if body == null:
		return
	_sync_routes(body)
	if _needs_resnap(body):
		_snap_to_path(body)
		_refresh_goal(body)
	if _arrived(body):
		if segment_id < 0:
			goal = pick_goal(body, radius, rng)
		else:
			_pick_next(body, rng)
			_refresh_goal(body)


func follow_velocity(body: CharacterBody3D, speed: float) -> Vector3:
	## Stay on the current centerline; never bee-line through walls.
	if body == null:
		return Vector3.ZERO
	var y := body.velocity.y
	var segments: Array = graph.get("segments", [])
	if segment_id < 0 or segment_id >= segments.size():
		return _toward(body.global_position, goal, speed, y)
	var seg: Dictionary = segments[segment_id]
	var on := _on_segment(body.global_position, seg["a"], seg["b"])
	var cell := maxf(float(graph.get("cell_size", 4.0)), 0.5)
	var off := Vector3(
		body.global_position.x - on.x, 0.0, body.global_position.z - on.z
	)
	var can_reach := MazePathGraphScript.line_is_open(
		graph, body.global_position, on, 0.38
	)
	if not can_reach:
		return Vector3(0.0, y, 0.0)
	if off.length() <= cell * 0.45:
		body.global_position = Vector3(on.x, body.global_position.y, on.z)
		var dest: Vector3 = seg["b"] if toward_b else seg["a"]
		return _toward(body.global_position, dest, speed, y)
	return _toward(body.global_position, on, speed, y)


static func find_graph(node: Node) -> Dictionary:
	if node != null and node.has_meta("maze_path_graph"):
		var meta_graph = node.get_meta("maze_path_graph")
		if meta_graph is Dictionary:
			return meta_graph
	if node == null or node.get_tree() == null:
		return {}
	var paths := node.get_tree().get_first_node_in_group(GROUP_PATHS)
	if paths != null and "graph" in paths:
		var g = paths.get("graph")
		if g is Dictionary:
			return g
	return {}


static func sample_dirs(forward: Vector3, count: int = SAMPLE_COUNT) -> PackedVector3Array:
	var fwd := Vector3(forward.x, 0.0, forward.z)
	if fwd.length_squared() < 0.0001:
		fwd = Vector3(0.0, 0.0, -1.0)
	else:
		fwd = fwd.normalized()
	var right := Vector3(fwd.z, 0.0, -fwd.x)
	var out := PackedVector3Array()
	out.resize(maxi(count, 1))
	for i in out.size():
		var ang := float(i) * TAU / float(out.size())
		out[i] = (fwd * cos(ang) + right * sin(ang)).normalized()
	return out


static func clear_distance(body: CollisionObject3D, dir: Vector3, max_dist: float) -> float:
	if body == null or not body.is_inside_tree():
		return maxf(max_dist, 0.0)
	var world := body.get_world_3d()
	if world == null or world.direct_space_state == null:
		return maxf(max_dist, 0.0)
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return 0.0
	flat = flat.normalized()
	var from := body.global_position + Vector3(0.0, RAY_HEIGHT, 0.0) + flat * RAY_START
	var span := maxf(max_dist, 0.05)
	var to := from + flat * span
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = WORLD_MASK
	query.exclude = [body.get_rid()]
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return span
	return maxf(from.distance_to(hit.position) - 0.12, 0.0)


static func pick_goal(
	body: CharacterBody3D, patrol_radius: float, rng: RandomNumberGenerator
) -> Vector3:
	if body == null:
		return Vector3.ZERO
	var forward := -body.global_transform.basis.z
	var dirs := sample_dirs(forward)
	var best_i := 0
	var best := -1.0
	for i in dirs.size():
		var clear := clear_distance(body, dirs[i], patrol_radius)
		if clear > best:
			best = clear
			best_i = i
	var factor := 0.7
	if rng != null:
		factor = rng.randf_range(0.45, 0.9)
	return body.global_position + dirs[best_i] * maxf(best * factor, 0.4)


func _snap_to_path(body: CharacterBody3D) -> void:
	var pos := body.global_position
	if MazePathGraphScript.is_in_clearing(graph, pos):
		var link := _nearest_reachable_via_clearing(pos)
		if link >= 0:
			segment_id = link
			var line: Dictionary = graph["segments"][segment_id]
			if _in_patrol_rect(pos) and _is_viable(link):
				toward_b = _homeward_on_segment(line["a"], line["b"])
			else:
				toward_b = MazePathGraphScript.homeward_toward_b(
					graph, segment_id, home, size
				)
			return
	if not _in_patrol_rect(pos) and preferred.size() > 0:
		var ret_id := MazePathGraphScript.nearest_segment_id_from(graph, pos, preferred)
		if not _segment_reachable(pos, ret_id):
			ret_id = _nearest_reachable_from_ids(pos, preferred)
		if ret_id >= 0:
			segment_id = ret_id
			toward_b = MazePathGraphScript.homeward_toward_b(graph, segment_id, home, size)
			return
	if not _in_patrol_rect(pos):
		var junc_i := _nearest_junction(pos)
		if junc_i >= 0:
			var homeward := MazePathGraphScript.homeward_next_segment(graph, junc_i, home, size)
			if homeward >= 0:
				segment_id = homeward
				toward_b = MazePathGraphScript.homeward_toward_b(graph, segment_id, home, size)
				return
	var nearest := MazePathGraphScript.nearest_segment_id(graph, pos)
	if not _segment_reachable(pos, nearest):
		nearest = _nearest_reachable_segment(pos)
	var off_network := (
		MazePathGraphScript.is_in_clearing(graph, pos) or not _is_viable(nearest)
	)
	if off_network and preferred.size() > 0:
		segment_id = MazePathGraphScript.nearest_segment_id_from(graph, pos, preferred)
	elif off_network and viable.size() > 0:
		segment_id = MazePathGraphScript.nearest_segment_id_from(graph, pos, viable)
	else:
		segment_id = nearest
	if not _segment_reachable(pos, segment_id):
		segment_id = nearest
	if segment_id < 0:
		return
	var seg: Dictionary = graph["segments"][segment_id]
	var a: Vector3 = seg["a"]
	var b: Vector3 = seg["b"]
	var facing := -body.global_transform.basis.z
	toward_b = facing.dot(Vector3(b.x - a.x, 0.0, b.z - a.z)) >= 0.0
	if off_network:
		toward_b = MazePathGraphScript.homeward_toward_b(graph, segment_id, home, size)


func _nearest_junction(pos: Vector3) -> int:
	var junctions: Array = graph.get("junctions", [])
	var best := -1
	var best_d := INF
	for i in junctions.size():
		var j_pos: Vector3 = junctions[i]["pos"]
		var d := Vector3(pos.x - j_pos.x, 0.0, pos.z - j_pos.z).length()
		if d < best_d:
			best_d = d
			best = i
	return best


func _homeward_on_segment(a: Vector3, b: Vector3) -> bool:
	var da := Vector3(a.x - home.x, 0.0, a.z - home.z).length()
	var db := Vector3(b.x - home.x, 0.0, b.z - home.z).length()
	return db <= da


func _needs_resnap(body: CharacterBody3D) -> bool:
	var segments: Array = graph.get("segments", [])
	if segment_id < 0 or segment_id >= segments.size():
		return true
	var seg: Dictionary = segments[segment_id]
	var on := _on_segment(body.global_position, seg["a"], seg["b"])
	var cell := maxf(float(graph.get("cell_size", 4.0)), 0.5)
	var off := Vector3(
		body.global_position.x - on.x, 0.0, body.global_position.z - on.z
	)
	return off.length() > cell * 0.45


func _nearest_via_clearing(pos: Vector3) -> int:
	var ids := PackedInt32Array()
	var segments: Array = graph.get("segments", [])
	for i in segments.size():
		if bool(segments[i].get("via_clearing", false)):
			ids.append(i)
	if ids.is_empty():
		return -1
	return MazePathGraphScript.nearest_segment_id_from(graph, pos, ids)


func _nearest_reachable_via_clearing(pos: Vector3) -> int:
	var ids := PackedInt32Array()
	var segments: Array = graph.get("segments", [])
	for i in segments.size():
		if bool(segments[i].get("via_clearing", false)) and _segment_reachable(pos, i):
			ids.append(i)
	if ids.is_empty():
		return _nearest_via_clearing(pos)
	return MazePathGraphScript.nearest_segment_id_from(graph, pos, ids)


func _nearest_reachable_segment(pos: Vector3) -> int:
	return _nearest_reachable_from_ids(pos, PackedInt32Array())


func _nearest_reachable_from_ids(pos: Vector3, ids: PackedInt32Array) -> int:
	var pick := PackedInt32Array()
	var segments: Array = graph.get("segments", [])
	if ids.is_empty():
		for i in segments.size():
			if _segment_reachable(pos, i):
				pick.append(i)
	else:
		for id in ids:
			if _segment_reachable(pos, id):
				pick.append(id)
	if pick.is_empty():
		if ids.is_empty():
			return MazePathGraphScript.nearest_segment_id(graph, pos)
		return MazePathGraphScript.nearest_segment_id_from(graph, pos, ids)
	return MazePathGraphScript.nearest_segment_id_from(graph, pos, pick)


func _segment_reachable(pos: Vector3, sid: int) -> bool:
	var segments: Array = graph.get("segments", [])
	if sid < 0 or sid >= segments.size():
		return false
	var seg: Dictionary = segments[sid]
	var on := _on_segment(pos, seg["a"], seg["b"])
	return MazePathGraphScript.line_is_open(graph, pos, on, 0.38)


func _on_segment(pos: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var ap := Vector3(pos.x - a.x, 0.0, pos.z - a.z)
	var len2 := ab.length_squared()
	var t := 0.0
	if len2 > 0.0001:
		t = clampf(ap.dot(ab) / len2, 0.0, 1.0)
	return Vector3(a.x + ab.x * t, pos.y, a.z + ab.z * t)


func _toward(from: Vector3, to: Vector3, speed: float, y_velocity: float) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if flat.length_squared() < 0.0001:
		return Vector3(0.0, y_velocity, 0.0)
	flat = flat.normalized()
	return Vector3(flat.x * speed, y_velocity, flat.z * speed)


func _pick_next(_body: CharacterBody3D, rng: RandomNumberGenerator) -> void:
	if segment_id < 0:
		return
	var seg: Dictionary = graph["segments"][segment_id]
	var junc: int = int(seg["b_j"] if toward_b else seg["a_j"])
	var junc_pos: Vector3 = graph["junctions"][junc]["pos"]
	if not _in_patrol_rect(junc_pos) or not _is_viable(segment_id):
		var next_sid := MazePathGraphScript.homeward_next_segment(graph, junc, home, size)
		if next_sid >= 0:
			segment_id = next_sid
			var hop: Dictionary = graph["segments"][segment_id]
			toward_b = int(hop["a_j"]) == junc
			return
	var choices := MazePathGraphScript.other_segment_ids(graph, junc, segment_id)
	var viable_choices := PackedInt32Array()
	for id in choices:
		if _is_viable(id):
			viable_choices.append(id)
	var pool := viable_choices if not viable_choices.is_empty() else choices
	var moving := PackedInt32Array()
	for id in pool:
		if _segment_progresses(junc, junc_pos, id):
			moving.append(id)
	if not moving.is_empty():
		pool = moving
	if pool.is_empty():
		toward_b = not toward_b
		return
	var pick := pool[0]
	if rng != null:
		pick = pool[rng.randi() % pool.size()]
	segment_id = pick
	var next: Dictionary = graph["segments"][segment_id]
	toward_b = int(next["a_j"]) == junc


func _segment_progresses(junc_idx: int, junc_pos: Vector3, seg_id: int) -> bool:
	var seg: Dictionary = graph["segments"][seg_id]
	var dest: Vector3 = seg["b"] if int(seg["a_j"]) == junc_idx else seg["a"]
	var step := Vector3(dest.x - junc_pos.x, 0.0, dest.z - junc_pos.z)
	return step.length() > ARRIVE_DIST


func _refresh_goal(body: CharacterBody3D) -> void:
	if segment_id < 0:
		return
	var seg: Dictionary = graph["segments"][segment_id]
	var dest: Vector3 = seg["b"] if toward_b else seg["a"]
	goal = dest
	goal.y = body.global_position.y


func _arrived(body: CharacterBody3D) -> bool:
	var flat := Vector3(
		goal.x - body.global_position.x, 0.0, goal.z - body.global_position.z
	)
	return flat.length() <= ARRIVE_DIST


func _in_patrol_rect(pos: Vector3) -> bool:
	return MazePathGraphScript.point_in_patrol_rect(pos, home, size)


func _is_viable(seg_id: int) -> bool:
	return _ids_has(viable, seg_id)


func _ids_has(ids: PackedInt32Array, seg_id: int) -> bool:
	for id in ids:
		if id == seg_id:
			return true
	return false


func _sync_routes(body: CharacterBody3D) -> void:
	if body != null and body.has_meta("patrol_size"):
		var raw = body.get_meta("patrol_size")
		if raw is Vector2:
			size = raw
			radius = maxf(size.x, size.y) * 0.5
	elif body != null and "patrol_radius" in body:
		radius = maxf(float(body.patrol_radius), 0.5)
		size = Vector2(radius * 2.0, radius * 2.0)
	if body != null and body.has_meta("patrol_home"):
		set_home(body.get_meta("patrol_home"))
	var seg_count: int = graph.get("segments", []).size()
	if home == _pref_home and size == _pref_size and seg_count == _pref_seg_count:
		return
	_pref_home = home
	_pref_size = size
	_pref_seg_count = seg_count
	viable = MazePathGraphScript.viable_patrol_segment_ids(graph, home, size)
	preferred = MazePathGraphScript.return_path_segment_ids(graph, home, size)
