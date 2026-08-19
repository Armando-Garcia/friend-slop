extends RefCounted

## Same path Monster._begin_patrol uses after a match spawn: begin(radius=8) at
## maze start (cell 0,0). No lookdev patrol_home / patrol_size / Fit Patrol.

const MazeCarverScript := preload("res://scripts/maze_carver.gd")
const MazeGeometryScript := preload("res://scripts/maze_geometry.gd")
const MazePathGraphScript := preload("res://scripts/maze_path_graph.gd")
const MonsterPatrolScript := preload("res://scripts/monsters/monster_patrol.gd")

const MAZE_W := 8
const MAZE_H := 8
const CELL := 4.0
const PATROL_RADIUS := 8.0
const PATROL_SIZE := Vector2(16.0, 16.0)


func run() -> int:
	var failures := 0
	failures += _test_begin_uses_spawn_home_and_radius_square()
	failures += _test_begin_snaps_onto_maze_centerline()
	failures += _test_follow_stays_on_centerline()
	failures += _test_tick_keeps_walking_viable_lines()
	failures += _test_clearing_resnap_returns_toward_spawn()
	failures += _test_outside_rect_follows_homeward_return()
	return failures


func _test_begin_uses_spawn_home_and_radius_square() -> int:
	var setup := _begin_at_maze_start()
	if setup.is_empty():
		return 1
	var patrol: RefCounted = setup["patrol"]
	var spawn: Vector3 = setup["spawn"]
	setup["body"].free()
	var home: Vector3 = patrol.get("home")
	var size: Vector2 = patrol.get("size")
	if Vector3(home.x - spawn.x, 0.0, home.z - spawn.z).length() > 0.05:
		push_error("In-game patrol home should be maze start, got %s vs %s" % [home, spawn])
		return 1
	if size != PATROL_SIZE:
		push_error("In-game size is 2*patrol_radius (16x16), got %s" % size)
		return 1
	return 0


func _test_begin_snaps_onto_maze_centerline() -> int:
	var setup := _begin_at_maze_start()
	if setup.is_empty():
		return 1
	var graph: Dictionary = setup["graph"]
	var patrol: RefCounted = setup["patrol"]
	setup["body"].free()
	var sid: int = int(patrol.get("segment_id"))
	var segments: Array = graph.get("segments", [])
	if sid < 0 or sid >= segments.size():
		push_error("Maze start patrol should snap onto a corridor, sid=%s" % sid)
		return 1
	var goal: Vector3 = patrol.get("goal")
	var seg: Dictionary = segments[sid]
	var a: Vector3 = seg["a"]
	var b: Vector3 = seg["b"]
	var on_a := Vector3(goal.x - a.x, 0.0, goal.z - a.z).length() <= 0.05
	var on_b := Vector3(goal.x - b.x, 0.0, goal.z - b.z).length() <= 0.05
	if not on_a and not on_b:
		push_error("Patrol goal should be the current corridor end, got %s" % goal)
		return 1
	return 0


func _test_follow_stays_on_centerline() -> int:
	var setup := _begin_at_maze_start()
	if setup.is_empty():
		return 1
	var patrol: RefCounted = setup["patrol"]
	var body: CharacterBody3D = setup["body"]
	var sid: int = int(patrol.get("segment_id"))
	var segments: Array = setup["graph"]["segments"]
	if sid < 0 or sid >= segments.size():
		body.free()
		push_error("Need a corridor before testing centerline follow")
		return 1
	var seg: Dictionary = segments[sid]
	var along := Vector3(seg["b"].x - seg["a"].x, 0.0, seg["b"].z - seg["a"].z)
	if along.length_squared() < 0.0001:
		body.free()
		push_error("Corridor segment was degenerate")
		return 1
	along = along.normalized()
	var perp := Vector3(-along.z, 0.0, along.x)
	body.global_position += perp * 0.3
	body.velocity = Vector3.ZERO
	var vel: Vector3 = patrol.call("follow_velocity", body, 2.4)
	var on: Vector3 = _on_segment(body.global_position, seg["a"], seg["b"])
	var off := Vector3(body.global_position.x - on.x, 0.0, body.global_position.z - on.z)
	body.free()
	if off.length() > 0.05:
		push_error("Follow should snap onto the corridor centerline, off=%s" % off.length())
		return 1
	if Vector3(vel.x, 0.0, vel.z).length() < 0.5:
		push_error("Follow should walk the corridor, got %s" % vel)
		return 1
	return 0


func _test_tick_keeps_walking_viable_lines() -> int:
	var setup := _begin_at_maze_start()
	if setup.is_empty():
		return 1
	var patrol: RefCounted = setup["patrol"]
	var body: CharacterBody3D = setup["body"]
	var graph: Dictionary = setup["graph"]
	body.global_position = patrol.get("goal")
	patrol.call("tick", body, setup["rng"])
	var sid: int = int(patrol.get("segment_id"))
	var viable: PackedInt32Array = patrol.get("viable")
	body.free()
	if sid < 0 or sid >= graph["segments"].size():
		push_error("Tick at a junction must stay on the maze graph, sid=%s" % sid)
		return 1
	if not _ids_has(viable, sid):
		push_error("From maze start, next line should stay in the 16m patrol rect")
		return 1
	return 0


func _test_clearing_resnap_returns_toward_spawn() -> int:
	var setup := _begin_at_maze_start()
	if setup.is_empty():
		return 1
	var graph: Dictionary = setup["graph"]
	var clearing := _clearing_center(graph)
	if clearing == Vector3.ZERO:
		setup["body"].free()
		push_error("Expected a clearing so return-to-spawn can be tested")
		return 1
	var body: CharacterBody3D = setup["body"]
	var patrol: RefCounted = setup["patrol"]
	body.global_position = clearing
	patrol.call("tick", body, setup["rng"])
	var sid: int = int(patrol.get("segment_id"))
	var preferred: PackedInt32Array = patrol.get("preferred")
	body.free()
	if sid < 0 or sid >= graph["segments"].size():
		push_error("From a clearing, patrol should resnap onto a path")
		return 1
	var seg: Dictionary = graph["segments"][sid]
	if bool(seg.get("via_clearing", false)):
		return 0
	if _ids_has(preferred, sid):
		return 0
	push_error("From a clearing, should take a hub spoke or return corridor")
	return 1


func _test_outside_rect_follows_homeward_return() -> int:
	var setup := _begin_at_maze_start()
	if setup.is_empty():
		return 1
	var graph: Dictionary = setup["graph"]
	var patrol: RefCounted = setup["patrol"]
	var body: CharacterBody3D = setup["body"]
	var home: Vector3 = patrol.get("home")
	var size: Vector2 = patrol.get("size")
	var far := Vector3.ZERO
	var far_d := -1.0
	for junc in graph.get("junctions", []):
		var pos: Vector3 = junc["pos"]
		if MazePathGraphScript.point_in_patrol_rect(pos, home, size):
			continue
		var d := Vector3(pos.x - home.x, 0.0, pos.z - home.z).length()
		if d > far_d:
			far_d = d
			far = pos
	if far == Vector3.ZERO:
		body.free()
		push_error("Expected a junction outside the 16m patrol square")
		return 1
	far.y = body.global_position.y
	body.global_position = far
	patrol.call("tick", body, setup["rng"])
	var sid: int = int(patrol.get("segment_id"))
	var preferred: PackedInt32Array = patrol.get("preferred")
	var toward_b: bool = bool(patrol.get("toward_b"))
	body.free()
	if not _ids_has(preferred, sid):
		push_error("Outside the patrol square should walk a red return line, sid=%s" % sid)
		return 1
	if MazePathGraphScript.homeward_toward_b(graph, sid, home, size) != toward_b:
		push_error("Return walk should follow the homeward arrows")
		return 1
	return 0


func _begin_at_maze_start() -> Dictionary:
	## Match spawn: MazeGenerator emits cell (0,0). Monster.begin uses patrol_radius.
	var grid: Array = MazeCarverScript.generate(MAZE_W, MAZE_H, 4242, {
		"mean_corridor_length": 2.5,
		"corridor_length_variance": 3,
		"clearing_count": 1,
		"clearing_size": 1.5,
		"clearing_separation": 6.0,
		"spire_clearing_size": 1.0,
	})
	var graph: Dictionary = MazePathGraphScript.build(grid, MAZE_W, MAZE_H, CELL)
	if graph.get("segments", []).is_empty():
		push_error("Expected corridor centerlines at maze start")
		return {}
	var spawn := MazeGeometryScript.grid_to_world(1, 1, MAZE_W, MAZE_H, CELL)
	spawn.y = 0.05
	var body := CharacterBody3D.new()
	body.global_position = spawn
	body.set_meta("maze_path_graph", graph)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var patrol: RefCounted = MonsterPatrolScript.new()
	patrol.call("begin", body, rng, PATROL_RADIUS)
	return {
		"graph": graph,
		"spawn": spawn,
		"body": body,
		"patrol": patrol,
		"rng": rng,
	}


func _clearing_center(graph: Dictionary) -> Vector3:
	for rect in graph.get("clearing_rects", []):
		var origin: Vector3 = rect["origin"]
		var size: Vector3 = rect["size"]
		return origin + Vector3(size.x * 0.5, 0.05, size.z * 0.5)
	return Vector3.ZERO


func _on_segment(pos: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var ap := Vector3(pos.x - a.x, 0.0, pos.z - a.z)
	var len2 := ab.length_squared()
	var t := 0.0
	if len2 > 0.0001:
		t = clampf(ap.dot(ab) / len2, 0.0, 1.0)
	return Vector3(a.x + ab.x * t, pos.y, a.z + ab.z * t)


func _ids_has(ids: PackedInt32Array, sid: int) -> bool:
	for id in ids:
		if id == sid:
			return true
	return false
