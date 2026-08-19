extends RefCounted

const MazeCarverScript := preload("res://scripts/maze_carver.gd")
const MazeGeometryScript := preload("res://scripts/maze_geometry.gd")
const MazePathGraphScript := preload("res://scripts/maze_path_graph.gd")


func run() -> int:
	var failures := 0
	failures += _test_marks_3x3_clearing_not_corridor()
	failures += _test_plus_has_junction_and_lines()
	failures += _test_junction_choices_skip_arrival_segment()
	failures += _test_patrol_radius_stops_before_clearing()
	failures += _test_generated_maze_has_paths_and_clearing()
	failures += _test_spawn_pads_are_fixed_maze_areas()
	failures += _test_return_paths_link_clearing_to_patrol()
	failures += _test_return_paths_cover_far_corridors()
	failures += _test_homeward_walk_points_into_patrol()
	failures += _test_viable_paths_touch_rect_and_reach_center()
	failures += _test_clearing_lines_connect_opposite_mouths()
	failures += _test_clip_move_cannot_enter_wall()
	return failures


func _open_grid(n: int) -> Array:
	var grid: Array = []
	for _x in n:
		var col: Array = []
		for _y in n:
			col.append(1)
		grid.append(col)
	return grid


func _plus_and_room() -> Array:
	## 11x11: plus corridors through (3,*) and (*,3), 3x3 room at 7..9, 7..9.
	var grid := _open_grid(11)
	for i in range(1, 10):
		grid[3][i] = 0
		grid[i][3] = 0
	for x in range(7, 10):
		for y in range(7, 10):
			grid[x][y] = 0
	grid[3][7] = 0
	grid[3][8] = 0
	grid[3][9] = 0
	return grid


func _test_marks_3x3_clearing_not_corridor() -> int:
	var grid := _plus_and_room()
	var marked: Dictionary = MazePathGraphScript.mark_clearing_cells(grid)
	if not marked.has(Vector2i(8, 8)):
		push_error("Expected 3x3 room center to be a clearing cell")
		return 1
	if marked.has(Vector2i(3, 3)):
		push_error("Plus junction must not count as a clearing")
		return 1
	if marked.has(Vector2i(1, 3)):
		push_error("Narrow corridor must not count as a clearing")
		return 1
	return 0


func _test_plus_has_junction_and_lines() -> int:
	var graph: Dictionary = MazePathGraphScript.build(_plus_and_room(), 5, 5, 2.0)
	var segments: Array = graph.get("segments", [])
	var junctions: Array = graph.get("junctions", [])
	if segments.is_empty():
		push_error("Expected corridor centerline segments")
		return 1
	if junctions.is_empty():
		push_error("Expected at least one junction")
		return 1
	var found_plus := false
	for junc in junctions:
		var ids: PackedInt32Array = junc["segment_ids"]
		if ids.size() >= 3:
			found_plus = true
			break
	if not found_plus:
		push_error("Expected a junction with 3+ lines at the plus")
		return 1
	return 0


func _test_junction_choices_skip_arrival_segment() -> int:
	var graph: Dictionary = MazePathGraphScript.build(_plus_and_room(), 5, 5, 2.0)
	var junc_i := -1
	for i in graph["junctions"].size():
		var ids: PackedInt32Array = graph["junctions"][i]["segment_ids"]
		if ids.size() >= 3:
			junc_i = i
			break
	if junc_i < 0:
		push_error("Expected a multi-line junction for choice test")
		return 1
	var from: int = graph["junctions"][junc_i]["segment_ids"][0]
	var opts: PackedInt32Array = MazePathGraphScript.other_segment_ids(graph, junc_i, from)
	if opts.has(from) and opts.size() > 1:
		push_error("Should not keep the arrival line when other lines exist")
		return 1
	if opts.is_empty():
		push_error("Expected other lines at the plus junction")
		return 1
	return 0


func _test_patrol_radius_stops_before_clearing() -> int:
	var graph: Dictionary = MazePathGraphScript.build(_plus_and_room(), 5, 5, 2.0)
	var home: Vector3 = MazePathGraphScript.pick_corridor_spawn(graph)
	var radius: float = MazePathGraphScript.default_patrol_radius(home, graph)
	if radius <= 0.5:
		push_error("Expected a usable patrol radius, got %s" % radius)
		return 1
	for rect in graph.get("clearing_rects", []):
		var origin: Vector3 = rect["origin"]
		var size: Vector3 = rect["size"]
		var center := origin + size * 0.5
		var dist := Vector3(home.x - center.x, 0.0, home.z - center.z).length()
		if dist + 0.01 < radius:
			push_error("Patrol disc should not cover the clearing center")
			return 1
	return 0


func _test_generated_maze_has_paths_and_clearing() -> int:
	var grid: Array = MazeCarverScript.generate(8, 8, 4242, {
		"mean_corridor_length": 4.0,
		"corridor_length_variance": 1,
		"clearing_count": 1,
		"clearing_size": 1.5,
		"clearing_separation": 6.0,
		"spire_clearing_size": 1.0,
	})
	var graph: Dictionary = MazePathGraphScript.build(grid, 8, 8, 4.0)
	if graph.get("segments", []).is_empty():
		push_error("Generated maze should expose corridor centerlines")
		return 1
	if graph.get("clearing_cells", {}).is_empty():
		push_error("Generated maze with spire/clearing tools should have a clearing")
		return 1
	return 0


func _test_spawn_pads_are_fixed_maze_areas() -> int:
	var grid: Array = MazeCarverScript.generate(8, 8, 4242, {
		"mean_corridor_length": 4.0,
		"clearing_count": 1,
		"clearing_size": 1.5,
		"spire_clearing_size": 1.0,
	})
	var graph: Dictionary = MazePathGraphScript.build(grid, 8, 8, 4.0)
	var nw: Vector3 = MazePathGraphScript.spawn_at_pad(graph, MazePathGraphScript.PAD_NW)
	var se: Vector3 = MazePathGraphScript.spawn_at_pad(graph, MazePathGraphScript.PAD_SE)
	if nw.x >= se.x - 0.5 and nw.z >= se.z - 0.5:
		push_error("Expected NW pad west/north of SE pad, got %s vs %s" % [nw, se])
		return 1
	var clearing: Vector3 = MazePathGraphScript.spawn_at_pad(
		graph, MazePathGraphScript.PAD_CLEARING
	)
	var in_clearing := false
	for rect in graph.get("clearing_rects", []):
		var origin: Vector3 = rect["origin"]
		var size: Vector3 = rect["size"]
		if (
			clearing.x >= origin.x
			and clearing.x <= origin.x + size.x
			and clearing.z >= origin.z
			and clearing.z <= origin.z + size.z
		):
			in_clearing = true
			break
	if not in_clearing:
		push_error("Clearing spawn pad should land inside a clearing")
		return 1
	return 0


func _plus_room_connected() -> Array:
	## Plus corridors plus a 3x3 room joined by a north-south corridor at x=7.
	var grid := _plus_and_room()
	for y in range(4, 7):
		grid[7][y] = 0
	return grid


func _cell_touches_clearing(cell: Vector2i, marked: Dictionary) -> bool:
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	for dir in dirs:
		if marked.has(cell + dir):
			return true
	return false


func _test_return_paths_link_clearing_to_patrol() -> int:
	var graph: Dictionary = MazePathGraphScript.build(_plus_room_connected(), 5, 5, 2.0)
	var home: Vector3 = MazePathGraphScript.pick_corridor_spawn(graph)
	var size := Vector2(4.0, 4.0)
	var ids: PackedInt32Array = MazePathGraphScript.return_path_segment_ids(
		graph, home, size
	)
	if ids.is_empty():
		push_error("Expected a return corridor from the room to the patrol disc")
		return 1
	var marked: Dictionary = graph.get("clearing_cells", {})
	var touches_mouth := false
	var segments: Array = graph.get("segments", [])
	for id in ids:
		if id < 0 or id >= segments.size():
			continue
		var seg: Dictionary = segments[id]
		if (
			_cell_touches_clearing(seg["a_cell"], marked)
			or _cell_touches_clearing(seg["b_cell"], marked)
		):
			touches_mouth = true
			break
	if not touches_mouth:
		push_error("Return path should start at a clearing mouth")
		return 1
	if MazePathGraphScript.is_in_clearing(graph, home):
		push_error("Corridor spawn used as patrol home should not sit in the room")
		return 1
	return 0


func _east_hall() -> Array:
	var grid := _open_grid(15)
	for x in range(1, 14):
		grid[x][1] = 0
	return grid


func _test_return_paths_cover_far_corridors() -> int:
	var graph: Dictionary = MazePathGraphScript.build(_east_hall(), 15, 15, 2.0)
	var home: Vector3 = MazeGeometryScript.grid_to_world(1, 1, 15, 15, 2.0)
	var size := Vector2(3.0, 3.0)
	var ids: PackedInt32Array = MazePathGraphScript.return_path_segment_ids(
		graph, home, size
	)
	if ids.is_empty():
		push_error("Expected return lines covering the hall outside the patrol square")
		return 1
	var far: Vector3 = MazeGeometryScript.grid_to_world(13, 1, 15, 15, 2.0)
	if MazePathGraphScript.point_in_patrol_rect(far, home, size):
		push_error("Far hall cell should sit outside the tiny patrol square")
		return 1
	var sid: int = MazePathGraphScript.nearest_segment_id_from(graph, far, ids)
	if sid < 0:
		push_error("Far hall should snap onto a red return line")
		return 1
	return 0


func _test_homeward_walk_points_into_patrol() -> int:
	var graph: Dictionary = MazePathGraphScript.build(_east_hall(), 15, 15, 2.0)
	var home: Vector3 = MazeGeometryScript.grid_to_world(1, 1, 15, 15, 2.0)
	var size := Vector2(3.0, 3.0)
	var far_j := -1
	var far_d := -1.0
	for i in graph["junctions"].size():
		var pos: Vector3 = graph["junctions"][i]["pos"]
		var d := Vector3(pos.x - home.x, 0.0, pos.z - home.z).length()
		if d > far_d:
			far_d = d
			far_j = i
	if far_j < 0:
		push_error("Expected a far hall junction")
		return 1
	var next_sid: int = MazePathGraphScript.homeward_next_segment(graph, far_j, home, size)
	if next_sid < 0:
		push_error("Far junction should have a maze hop toward the patrol square")
		return 1
	var edges: Array = MazePathGraphScript.return_homeward_edges(graph, home, size)
	var found := false
	for edge in edges:
		if int(edge["id"]) != next_sid:
			continue
		var from: Vector3 = edge["from"]
		var to: Vector3 = edge["to"]
		var from_d := Vector3(from.x - home.x, 0.0, from.z - home.z).length()
		var to_d := Vector3(to.x - home.x, 0.0, to.z - home.z).length()
		if to_d >= from_d - 0.01:
			push_error("Return arrow must point toward the patrol square")
			return 1
		found = true
		break
	if not found:
		push_error("Homeward hop should appear as a directed return edge")
		return 1
	return 0


func _test_viable_paths_touch_rect_and_reach_center() -> int:
	var graph: Dictionary = MazePathGraphScript.build(_plus_room_connected(), 5, 5, 2.0)
	var home: Vector3 = MazePathGraphScript.pick_corridor_spawn(graph)
	var size := Vector2(4.0, 4.0)
	var ids: PackedInt32Array = MazePathGraphScript.viable_patrol_segment_ids(
		graph, home, size
	)
	if ids.is_empty():
		push_error("Tiny patrol rect should still keep corridors that touch it")
		return 1
	var segments: Array = graph.get("segments", [])
	for i in segments.size():
		if not MazePathGraphScript.segment_touches_rect(graph, i, home, size):
			continue
		var found := false
		for id in ids:
			if id == i:
				found = true
				break
		if not found:
			push_error("Touching corridor %s missing from viable set" % i)
			return 1
	var marked: Dictionary = graph.get("clearing_cells", {})
	for id in ids:
		var seg: Dictionary = segments[id]
		if (
			_cell_touches_clearing(seg["a_cell"], marked)
			or _cell_touches_clearing(seg["b_cell"], marked)
		):
			push_error("Small patrol rect should not treat the room mouth as viable")
			return 1
	if not MazePathGraphScript.point_in_patrol_rect(home, home, size):
		push_error("Patrol center should lie inside its own rect")
		return 1
	return 0


func _room_two_doors() -> Array:
	## Hallway through a 3x3 room so opposite mouths only meet via the clearing.
	var grid := _open_grid(11)
	for x in range(1, 10):
		grid[x][5] = 0
	for x in range(4, 7):
		for y in range(4, 7):
			grid[x][y] = 0
	return grid


func _test_clearing_lines_connect_opposite_mouths() -> int:
	var graph: Dictionary = MazePathGraphScript.build(_room_two_doors(), 5, 5, 2.0)
	for junc in graph["junctions"]:
		if bool(junc.get("hub", false)):
			push_error("Clearing crossings must be maze lines, not a room-center hub")
			return 1
	var left := -1
	var right := -1
	for i in graph["junctions"].size():
		var cell: Vector2i = graph["junctions"][i]["cell"]
		if cell == Vector2i(3, 5):
			left = i
		if cell == Vector2i(7, 5):
			right = i
	if left < 0 or right < 0:
		push_error("Expected hallway mouths on both sides of the room")
		return 1
	if not _junctions_connected(graph, left, right):
		push_error("Opposite hallway mouths should connect across the room")
		return 1
	for seg in graph["segments"]:
		if not bool(seg.get("via_clearing", false)):
			continue
		var a: Vector3 = seg["a"]
		var b: Vector3 = seg["b"]
		var axis := is_equal_approx(a.x, b.x) or is_equal_approx(a.z, b.z)
		if not axis:
			push_error("Clearing path %s -> %s must stay on a maze row/col" % [a, b])
			return 1
	return 0


func _test_clip_move_cannot_enter_wall() -> int:
	var graph: Dictionary = MazePathGraphScript.build(_plus_and_room(), 5, 5, 2.0)
	var open_pos: Vector3 = MazeGeometryScript.grid_to_world(3, 1, 5, 5, 2.0)
	open_pos.y = 0.05
	var wall_pos: Vector3 = MazeGeometryScript.grid_to_world(0, 0, 5, 5, 2.0)
	wall_pos.y = 0.05
	if not MazePathGraphScript.is_open_at(graph, open_pos, 0.2):
		push_error("Plus corridor should be open at (3,1)")
		return 1
	if MazePathGraphScript.is_open_at(graph, wall_pos, 0.2):
		push_error("Grid corner (0,0) should be a wall")
		return 1
	if MazePathGraphScript.line_is_open(graph, open_pos, wall_pos, 0.2):
		push_error("Line from corridor into a wall cell must be blocked")
		return 1
	var clipped: Vector3 = MazePathGraphScript.clip_world_move(
		graph, open_pos, wall_pos, 0.2
	)
	if not MazePathGraphScript.is_open_at(graph, clipped, 0.2):
		push_error("Clipped move must remain in open cells, got %s" % clipped)
		return 1
	return 0


func _junctions_connected(graph: Dictionary, start_j: int, goal_j: int) -> bool:
	var seen := {}
	var queue: Array[int] = [start_j]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if cur == goal_j:
			return true
		if seen.has(cur):
			continue
		seen[cur] = true
		var sids: PackedInt32Array = graph["junctions"][cur]["segment_ids"]
		for sid in sids:
			var seg: Dictionary = graph["segments"][sid]
			var nxt: int = int(seg["b_j"] if int(seg["a_j"]) == cur else seg["a_j"])
			if not seen.has(nxt):
				queue.append(nxt)
	return false
