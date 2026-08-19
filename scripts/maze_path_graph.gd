class_name MazePathGraph
extends RefCounted

## Corridor centerlines and 3x3+ clearings from a MazeCarver wall grid.

const MazeGeometryScript := preload("res://scripts/maze_geometry.gd")

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]
const CLEARING_MIN := 3
const PAD_NW := 0
const PAD_NE := 1
const PAD_SW := 2
const PAD_SE := 3
const PAD_CENTER := 4
const PAD_CLEARING := 5


static func build(
	wall_grid: Array, maze_width: int, maze_height: int, cell_size: float
) -> Dictionary:
	var empty := {
		"segments": [],
		"junctions": [],
		"clearing_cells": {},
		"clearing_rects": [],
		"wall_grid": [],
		"cell_size": maxf(cell_size, 0.1),
		"maze_width": maze_width,
		"maze_height": maze_height,
	}
	if wall_grid.is_empty() or maze_width < 1 or maze_height < 1:
		return empty
	var marked: Dictionary = mark_clearing_cells(wall_grid)
	var path_cells: Dictionary = _path_cells(wall_grid, marked)
	var junc_cells: Dictionary = _junction_cells(path_cells)
	var junctions: Array = []
	var junc_index: Dictionary = {}
	for cell: Vector2i in junc_cells.keys():
		junc_index[cell] = junctions.size()
		junctions.append({
			"cell": cell,
			"pos": MazeGeometryScript.grid_to_world(
				cell.x, cell.y, maze_width, maze_height, cell_size
			),
			"segment_ids": PackedInt32Array(),
		})
	var segments: Array = _build_segments(
		path_cells, junc_cells, junc_index, junctions, maze_width, maze_height, cell_size
	)
	var graph := {
		"segments": segments,
		"junctions": junctions,
		"clearing_cells": marked,
		"clearing_rects": _clearing_world_rects(
			marked, maze_width, maze_height, cell_size
		),
		"wall_grid": wall_grid,
		"cell_size": maxf(cell_size, 0.1),
		"maze_width": maze_width,
		"maze_height": maze_height,
	}
	_link_clearing_lines(graph)
	return graph


static func mark_clearing_cells(wall_grid: Array) -> Dictionary:
	## Any open cell that sits in a fully open 3x3 (or larger) square.
	var marked := {}
	if wall_grid.is_empty():
		return marked
	var gw: int = wall_grid.size()
	var gh: int = wall_grid[0].size()
	for ox in range(gw - CLEARING_MIN + 1):
		for oy in range(gh - CLEARING_MIN + 1):
			if not _square_open(wall_grid, ox, oy, CLEARING_MIN):
				continue
			for dx in CLEARING_MIN:
				for dy in CLEARING_MIN:
					marked[Vector2i(ox + dx, oy + dy)] = true
	return marked


static func nearest_segment_id(graph: Dictionary, world_pos: Vector3) -> int:
	var segments: Array = graph.get("segments", [])
	var best_id := -1
	var best := INF
	for i in segments.size():
		var seg: Dictionary = segments[i]
		var d := _point_to_segment_dist(world_pos, seg["a"], seg["b"])
		if d < best:
			best = d
			best_id = i
	return best_id


static func other_segment_ids(
	graph: Dictionary, junction_idx: int, from_segment: int
) -> PackedInt32Array:
	var out := PackedInt32Array()
	var junctions: Array = graph.get("junctions", [])
	if junction_idx < 0 or junction_idx >= junctions.size():
		return out
	var ids: PackedInt32Array = junctions[junction_idx]["segment_ids"]
	for id in ids:
		if id != from_segment:
			out.append(id)
	if out.is_empty() and from_segment >= 0:
		out.append(from_segment)
	return out


static func segment_in_area(
	graph: Dictionary, segment_id: int, home: Vector3, radius: float
) -> bool:
	return segment_touches_rect(
		graph, segment_id, home, Vector2(radius * 2.0, radius * 2.0)
	)


static func segment_touches_rect(
	graph: Dictionary, segment_id: int, home: Vector3, size: Vector2
) -> bool:
	var segments: Array = graph.get("segments", [])
	if segment_id < 0 or segment_id >= segments.size():
		return false
	var seg: Dictionary = segments[segment_id]
	return _segment_hits_rect(seg["a"], seg["b"], home, size)


static func point_in_patrol_rect(pos: Vector3, home: Vector3, size: Vector2) -> bool:
	if size.x <= 0.05 or size.y <= 0.05:
		return false
	return (
		absf(pos.x - home.x) <= size.x * 0.5
		and absf(pos.z - home.z) <= size.y * 0.5
	)


static func clip_goal_to_area(
	from: Vector3, to: Vector3, home: Vector3, radius: float
) -> Vector3:
	if radius <= 0.05 or _in_area(to, home, radius):
		return to
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var c := Vector2(home.x, home.z)
	var d := b - a
	var f := a - c
	var aa := d.dot(d)
	if aa < 0.0001:
		return to
	var bb := 2.0 * f.dot(d)
	var cc := f.dot(f) - radius * radius
	var disc := bb * bb - 4.0 * aa * cc
	if disc < 0.0:
		return to
	var t := (-bb + sqrt(disc)) / (2.0 * aa)
	t = clampf(t, 0.0, 1.0)
	var p := a + d * t
	return Vector3(p.x, from.y, p.y)


static func default_patrol_radius(home: Vector3, graph: Dictionary) -> float:
	var cell_size: float = float(graph.get("cell_size", 4.0))
	var nearest := _nearest_clearing_dist(home, graph)
	if nearest >= INF:
		return maxf(cell_size * 2.0, 8.0)
	return maxf(cell_size * 1.15, nearest - cell_size * 0.7)


static func default_patrol_size(home: Vector3, graph: Dictionary) -> Vector2:
	var side := default_patrol_radius(home, graph) * 2.0
	return Vector2(side, side)


static func pick_corridor_spawn(graph: Dictionary) -> Vector3:
	var junctions: Array = graph.get("junctions", [])
	if junctions.is_empty():
		return Vector3.ZERO
	var best_pos: Vector3 = junctions[0]["pos"]
	var best := -1.0
	for junc in junctions:
		var pos: Vector3 = junc["pos"]
		var d := _nearest_clearing_dist(pos, graph)
		if d > best:
			best = d
			best_pos = pos
	return best_pos


static func spawn_at_pad(graph: Dictionary, pad: int) -> Vector3:
	## Fixed maze areas: quadrant corridors, center, or a clearing.
	if pad == PAD_CLEARING:
		var clearing := _largest_clearing_center(graph)
		if clearing != Vector3.ZERO:
			clearing.y = 0.05
			return clearing
	var anchor := _pad_anchor(graph, pad)
	var path_pos := closest_path_point(graph, anchor)
	if path_pos == Vector3.ZERO:
		return Vector3(anchor.x, 0.05, anchor.z)
	path_pos.y = 0.05
	return path_pos


static func closest_path_point(graph: Dictionary, world_pos: Vector3) -> Vector3:
	var sid := nearest_segment_id(graph, world_pos)
	if sid < 0:
		var junctions: Array = graph.get("junctions", [])
		if junctions.is_empty():
			return Vector3.ZERO
		return junctions[0]["pos"]
	var seg: Dictionary = graph["segments"][sid]
	return _project_on_segment(world_pos, seg["a"], seg["b"])


static func is_in_clearing(graph: Dictionary, world_pos: Vector3) -> bool:
	for rect in graph.get("clearing_rects", []):
		var origin: Vector3 = rect["origin"]
		var size: Vector3 = rect["size"]
		if (
			world_pos.x >= origin.x
			and world_pos.x <= origin.x + size.x
			and world_pos.z >= origin.z
			and world_pos.z <= origin.z + size.z
		):
			return true
	return false


static func is_open_at(graph: Dictionary, pos: Vector3, radius: float = 0.38) -> bool:
	## Footprint must sit on open maze cells. Missing grid = no clip.
	if graph.get("wall_grid", []).is_empty():
		return true
	var r := maxf(radius, 0.05)
	var samples: Array[Vector3] = [
		pos,
		pos + Vector3(r, 0.0, 0.0),
		pos + Vector3(-r, 0.0, 0.0),
		pos + Vector3(0.0, 0.0, r),
		pos + Vector3(0.0, 0.0, -r),
	]
	for sample in samples:
		if not _cell_is_open(graph, _world_to_grid(graph, sample)):
			return false
	return true


static func line_is_open(
	graph: Dictionary, from: Vector3, to: Vector3, radius: float = 0.38
) -> bool:
	var delta := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var dist := delta.length()
	if dist < 0.02:
		return is_open_at(graph, to, radius)
	var steps := maxi(int(ceil(dist / 0.25)), 1)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := from.lerp(Vector3(to.x, from.y, to.z), t)
		if not is_open_at(graph, p, radius):
			return false
	return true


static func clip_world_move(
	graph: Dictionary, from: Vector3, to: Vector3, radius: float = 0.38
) -> Vector3:
	if is_open_at(graph, to, radius):
		return to
	var x_try := Vector3(to.x, from.y, from.z)
	var z_try := Vector3(from.x, from.y, to.z)
	var x_ok := is_open_at(graph, x_try, radius)
	var z_ok := is_open_at(graph, z_try, radius)
	if x_ok and z_ok:
		if absf(to.x - from.x) >= absf(to.z - from.z):
			return x_try
		return z_try
	if x_ok:
		return x_try
	if z_ok:
		return z_try
	return from


static func recover_open_position(graph: Dictionary, pos: Vector3, radius: float = 0.38) -> Vector3:
	if is_open_at(graph, pos, radius):
		return pos
	var origin := _world_to_grid(graph, pos)
	for ring in range(0, 5):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var cell := Vector2i(origin.x + dx, origin.y + dy)
				if not _cell_is_open(graph, cell):
					continue
				var world := MazeGeometryScript.grid_to_world(
					cell.x,
					cell.y,
					int(graph.get("maze_width", 1)),
					int(graph.get("maze_height", 1)),
					float(graph.get("cell_size", 4.0))
				)
				world.y = pos.y
				if is_open_at(graph, world, radius):
					return world
	return pos


static func nearest_segment_id_from(
	graph: Dictionary, world_pos: Vector3, ids: PackedInt32Array
) -> int:
	if ids.is_empty():
		return nearest_segment_id(graph, world_pos)
	var segments: Array = graph.get("segments", [])
	var best_id := -1
	var best := INF
	for id in ids:
		if id < 0 or id >= segments.size():
			continue
		var seg: Dictionary = segments[id]
		var d := _point_to_segment_dist(world_pos, seg["a"], seg["b"])
		if d < best:
			best = d
			best_id = id
	if best_id < 0:
		return nearest_segment_id(graph, world_pos)
	return best_id


static func return_path_segment_ids(
	graph: Dictionary, home: Vector3, size: Vector2
) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for edge in return_homeward_edges(graph, home, size):
		ids.append(int(edge["id"]))
	return ids


static func return_homeward_edges(graph: Dictionary, home: Vector3, size: Vector2) -> Array:
	## One maze-line hop from every outside junction toward the patrol rect.
	var out: Array = []
	var junctions: Array = graph.get("junctions", [])
	if junctions.is_empty():
		return out
	var bfs: Dictionary = _patrol_bfs(graph, home, size)
	var prev_j: PackedInt32Array = bfs.get("prev_j", PackedInt32Array())
	var prev_s: PackedInt32Array = bfs.get("prev_s", PackedInt32Array())
	var goals: Dictionary = bfs.get("goals", {})
	var seen := {}
	for i in junctions.size():
		if goals.has(i) or i >= prev_s.size() or prev_s[i] < 0:
			continue
		var sid: int = prev_s[i]
		if seen.has(sid):
			continue
		seen[sid] = true
		var dest: int = prev_j[i]
		if dest < 0 or dest >= junctions.size():
			continue
		out.append({
			"id": sid,
			"from": junctions[i]["pos"],
			"to": junctions[dest]["pos"],
		})
	return out


static func homeward_next_segment(
	graph: Dictionary, from_junc: int, home: Vector3, size: Vector2
) -> int:
	var bfs: Dictionary = _patrol_bfs(graph, home, size)
	var prev_s: PackedInt32Array = bfs.get("prev_s", PackedInt32Array())
	if from_junc < 0 or from_junc >= prev_s.size():
		return -1
	return prev_s[from_junc]


static func homeward_toward_b(
	graph: Dictionary, segment_id: int, home: Vector3, size: Vector2
) -> bool:
	var segments: Array = graph.get("segments", [])
	if segment_id < 0 or segment_id >= segments.size():
		return true
	var seg: Dictionary = segments[segment_id]
	var bfs: Dictionary = _patrol_bfs(graph, home, size)
	var prev_s: PackedInt32Array = bfs.get("prev_s", PackedInt32Array())
	var a_j := int(seg["a_j"])
	if a_j >= 0 and a_j < prev_s.size() and prev_s[a_j] == segment_id:
		return true
	return false


static func _patrol_bfs(graph: Dictionary, home: Vector3, size: Vector2) -> Dictionary:
	var goals := _patrol_goal_junctions(graph, home, size)
	if goals.is_empty():
		var nearest := _nearest_junction_idx(graph, home)
		if nearest >= 0:
			goals[nearest] = true
	if goals.is_empty():
		return {
			"prev_j": PackedInt32Array(),
			"prev_s": PackedInt32Array(),
			"goals": {},
		}
	var bfs: Dictionary = _bfs_from_goals(graph, goals)
	bfs["goals"] = goals
	return bfs


static func _clearing_mouth_indices(graph: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	var marked: Dictionary = graph.get("clearing_cells", {})
	if marked.is_empty():
		return out
	var junctions: Array = graph.get("junctions", [])
	for i in junctions.size():
		var cell: Vector2i = junctions[i]["cell"]
		if _adjacent_to_marked(cell, marked):
			out.append(i)
	return out


static func _adjacent_to_marked(cell: Vector2i, marked: Dictionary) -> bool:
	for dir in DIRS:
		if marked.has(cell + dir):
			return true
	return false


static func viable_patrol_segment_ids(
	graph: Dictionary, home: Vector3, size: Vector2
) -> PackedInt32Array:
	## Segments that touch the rect, plus routes from those back to the center.
	var out := PackedInt32Array()
	var seen := {}
	var segments: Array = graph.get("segments", [])
	if segments.is_empty() or size.x <= 0.05 or size.y <= 0.05:
		return out
	for i in segments.size():
		if not segment_touches_rect(graph, i, home, size):
			continue
		seen[i] = true
	if seen.is_empty():
		return out
	var center_j := _nearest_junction_idx(graph, home)
	if center_j >= 0:
		var bfs: Dictionary = _bfs_from_goals(graph, {center_j: true})
		for sid in seen.keys():
			var seg: Dictionary = segments[int(sid)]
			_walk_prev_segments(int(seg["a_j"]), bfs, seen)
			_walk_prev_segments(int(seg["b_j"]), bfs, seen)
	for sid in seen.keys():
		out.append(int(sid))
	return out


static func _patrol_goal_junctions(
	graph: Dictionary, home: Vector3, size: Vector2
) -> Dictionary:
	var goals := {}
	if size.x <= 0.05 or size.y <= 0.05:
		return goals
	var junctions: Array = graph.get("junctions", [])
	for i in junctions.size():
		if point_in_patrol_rect(junctions[i]["pos"], home, size):
			goals[i] = true
	var segments: Array = graph.get("segments", [])
	for sid in segments.size():
		if not segment_touches_rect(graph, sid, home, size):
			continue
		var seg: Dictionary = segments[sid]
		goals[int(seg["a_j"])] = true
		goals[int(seg["b_j"])] = true
	return goals


static func _nearest_junction_idx(graph: Dictionary, home: Vector3) -> int:
	var best := -1
	var best_d := INF
	var junctions: Array = graph.get("junctions", [])
	for i in junctions.size():
		var d := _dist_xz(junctions[i]["pos"], home)
		if d < best_d:
			best_d = d
			best = i
	return best


static func _junction_adj(graph: Dictionary) -> Array:
	var junctions: Array = graph.get("junctions", [])
	var adj: Array = []
	adj.resize(junctions.size())
	for i in junctions.size():
		adj[i] = []
	var segments: Array = graph.get("segments", [])
	for sid in segments.size():
		var seg: Dictionary = segments[sid]
		var a_j := int(seg["a_j"])
		var b_j := int(seg["b_j"])
		if a_j < 0 or b_j < 0 or a_j >= adj.size() or b_j >= adj.size():
			continue
		adj[a_j].append({"to": b_j, "seg": sid})
		adj[b_j].append({"to": a_j, "seg": sid})
	return adj


static func _bfs_from_goals(graph: Dictionary, goals: Dictionary) -> Dictionary:
	var n: int = graph.get("junctions", []).size()
	var prev_j := PackedInt32Array()
	var prev_s := PackedInt32Array()
	var dist := PackedInt32Array()
	prev_j.resize(n)
	prev_s.resize(n)
	dist.resize(n)
	prev_j.fill(-1)
	prev_s.fill(-1)
	dist.fill(-1)
	var adj := _junction_adj(graph)
	var queue: Array[int] = []
	for key in goals.keys():
		var goal_i := int(key)
		if goal_i < 0 or goal_i >= n:
			continue
		dist[goal_i] = 0
		queue.append(goal_i)
	var qi := 0
	while qi < queue.size():
		var u: int = queue[qi]
		qi += 1
		var edges: Array = adj[u]
		for edge in edges:
			var v: int = int(edge["to"])
			if dist[v] >= 0:
				continue
			dist[v] = dist[u] + 1
			prev_j[v] = u
			prev_s[v] = int(edge["seg"])
			queue.append(v)
	return {"prev_j": prev_j, "prev_s": prev_s}


static func _walk_prev_segments(junc: int, bfs: Dictionary, seen: Dictionary) -> void:
	var prev_j: PackedInt32Array = bfs["prev_j"]
	var prev_s: PackedInt32Array = bfs["prev_s"]
	if junc < 0 or junc >= prev_j.size():
		return
	var cur := junc
	while prev_j[cur] >= 0:
		seen[prev_s[cur]] = true
		cur = prev_j[cur]


static func _segment_hits_rect(a: Vector3, b: Vector3, home: Vector3, size: Vector2) -> bool:
	if point_in_patrol_rect(a, home, size) or point_in_patrol_rect(b, home, size):
		return true
	var min_x := home.x - size.x * 0.5
	var max_x := home.x + size.x * 0.5
	var min_z := home.z - size.y * 0.5
	var max_z := home.z + size.y * 0.5
	var hx := _clip_slab(a.x, b.x - a.x, min_x, max_x)
	var hz := _clip_slab(a.z, b.z - a.z, min_z, max_z)
	if hx.x > hx.y or hz.x > hz.y:
		return false
	var tmin := maxf(0.0, maxf(hx.x, hz.x))
	var tmax := minf(1.0, minf(hx.y, hz.y))
	return tmin <= tmax


static func _clip_slab(origin: float, delta: float, min_b: float, max_b: float) -> Vector2:
	if absf(delta) < 0.0001:
		if origin < min_b or origin > max_b:
			return Vector2(1.0, 0.0)
		return Vector2(0.0, 1.0)
	var t1 := (min_b - origin) / delta
	var t2 := (max_b - origin) / delta
	return Vector2(minf(t1, t2), maxf(t1, t2))


static func _pad_anchor(graph: Dictionary, pad: int) -> Vector3:
	var maze_w := maxi(int(graph.get("maze_width", 1)), 1)
	var maze_h := maxi(int(graph.get("maze_height", 1)), 1)
	var cell_size: float = float(graph.get("cell_size", 4.0))
	var cx := 0
	var cy := 0
	match pad:
		PAD_NE:
			cx = maze_w - 1
		PAD_SW:
			cy = maze_h - 1
		PAD_SE:
			cx = maze_w - 1
			cy = maze_h - 1
		PAD_CENTER, PAD_CLEARING:
			cx = int(maze_w / 2.0)
			cy = int(maze_h / 2.0)
		_:
			cx = 0
			cy = 0
	return MazeGeometryScript.grid_to_world(
		cx * 2 + 1, cy * 2 + 1, maze_w, maze_h, cell_size
	)


static func _largest_clearing_center(graph: Dictionary) -> Vector3:
	var best_area := 0.0
	var best := Vector3.ZERO
	for rect in graph.get("clearing_rects", []):
		var size: Vector3 = rect["size"]
		var area := size.x * size.z
		if area > best_area:
			best_area = area
			var origin: Vector3 = rect["origin"]
			best = origin + Vector3(size.x * 0.5, 0.05, size.z * 0.5)
	return best


static func _project_on_segment(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var ap := Vector3(p.x - a.x, 0.0, p.z - a.z)
	var len2 := ab.length_squared()
	var t := 0.0
	if len2 > 0.0001:
		t = clampf(ap.dot(ab) / len2, 0.0, 1.0)
	return Vector3(a.x + ab.x * t, 0.05, a.z + ab.z * t)


static func _nearest_clearing_dist(home: Vector3, graph: Dictionary) -> float:
	var best := INF
	for rect in graph.get("clearing_rects", []):
		best = minf(best, _dist_to_aabb_xz(home, rect["origin"], rect["size"]))
	return best


static func _dist_to_aabb_xz(p: Vector3, origin: Vector3, size: Vector3) -> float:
	var qx := clampf(p.x, origin.x, origin.x + size.x)
	var qz := clampf(p.z, origin.z, origin.z + size.z)
	return Vector3(p.x - qx, 0.0, p.z - qz).length()


static func _dist_xz(a: Vector3, b: Vector3) -> float:
	return Vector3(a.x - b.x, 0.0, a.z - b.z).length()


static func _world_to_grid(graph: Dictionary, pos: Vector3) -> Vector2i:
	var maze_w := maxi(int(graph.get("maze_width", 1)), 1)
	var maze_h := maxi(int(graph.get("maze_height", 1)), 1)
	var cell_size: float = maxf(float(graph.get("cell_size", 4.0)), 0.1)
	var offset: Vector3 = MazeGeometryScript.maze_offset(maze_w, maze_h, cell_size)
	var gx := int(round((pos.x + offset.x) / cell_size))
	var gy := int(round((pos.z + offset.z) / cell_size))
	return Vector2i(gx, gy)


static func _cell_is_open(graph: Dictionary, cell: Vector2i) -> bool:
	var grid: Array = graph.get("wall_grid", [])
	if grid.is_empty():
		return true
	if cell.x < 0 or cell.x >= grid.size():
		return false
	var col: Array = grid[cell.x]
	if cell.y < 0 or cell.y >= col.size():
		return false
	return int(col[cell.y]) == 0


static func _in_area(pos: Vector3, home: Vector3, radius: float) -> bool:
	return _dist_xz(pos, home) <= radius


static func _point_to_segment_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var ap := Vector3(p.x - a.x, 0.0, p.z - a.z)
	var len2 := ab.length_squared()
	var t := 0.0
	if len2 > 0.0001:
		t = clampf(ap.dot(ab) / len2, 0.0, 1.0)
	var proj := Vector3(a.x + ab.x * t, 0.0, a.z + ab.z * t)
	return Vector3(p.x - proj.x, 0.0, p.z - proj.z).length()


static func _square_open(wall_grid: Array, ox: int, oy: int, size: int) -> bool:
	var gw: int = wall_grid.size()
	var gh: int = wall_grid[0].size()
	if ox < 0 or oy < 0 or ox + size > gw or oy + size > gh:
		return false
	for dx in size:
		for dy in size:
			if int(wall_grid[ox + dx][oy + dy]) != 0:
				return false
	return true


static func _path_cells(wall_grid: Array, marked: Dictionary) -> Dictionary:
	var out := {}
	for gx in wall_grid.size():
		for gy in wall_grid[gx].size():
			if int(wall_grid[gx][gy]) != 0:
				continue
			var cell := Vector2i(gx, gy)
			if marked.has(cell):
				continue
			out[cell] = true
	return out


static func _junction_cells(path_cells: Dictionary) -> Dictionary:
	var out := {}
	for cell: Vector2i in path_cells.keys():
		var nbs := _path_neighbors(path_cells, cell)
		if nbs.size() != 2:
			out[cell] = true
			continue
		if nbs[0] + nbs[1] != cell * 2:
			out[cell] = true
	if out.is_empty():
		for cell: Vector2i in path_cells.keys():
			out[cell] = true
			break
	return out


static func _path_neighbors(path_cells: Dictionary, cell: Vector2i) -> Array[Vector2i]:
	var nbs: Array[Vector2i] = []
	for dir in DIRS:
		var nxt: Vector2i = cell + dir
		if path_cells.has(nxt):
			nbs.append(nxt)
	return nbs


static func _build_segments(
	path_cells: Dictionary,
	junc_cells: Dictionary,
	junc_index: Dictionary,
	junctions: Array,
	maze_width: int,
	maze_height: int,
	cell_size: float
) -> Array:
	var segments: Array = []
	var seen := {}
	var walk_dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
	for cell: Vector2i in junc_cells.keys():
		for dir in walk_dirs:
			var nxt: Vector2i = cell + dir
			if not path_cells.has(nxt):
				continue
			var cells := _walk_to_junction(cell, dir, path_cells, junc_cells)
			if cells.size() < 2:
				continue
			var other: Vector2i = cells[cells.size() - 1]
			var key := _edge_key(cell, other)
			if seen.has(key):
				continue
			seen[key] = true
			var a_j: int = int(junc_index[cell])
			var b_j: int = int(junc_index[other])
			var a_pos: Vector3 = MazeGeometryScript.grid_to_world(
				cell.x, cell.y, maze_width, maze_height, cell_size
			)
			var b_pos: Vector3 = MazeGeometryScript.grid_to_world(
				other.x, other.y, maze_width, maze_height, cell_size
			)
			var sid := segments.size()
			segments.append({
				"a": a_pos,
				"b": b_pos,
				"a_cell": cell,
				"b_cell": other,
				"a_j": a_j,
				"b_j": b_j,
			})
			var ids_a: PackedInt32Array = junctions[a_j]["segment_ids"]
			ids_a.append(sid)
			junctions[a_j]["segment_ids"] = ids_a
			var ids_b: PackedInt32Array = junctions[b_j]["segment_ids"]
			ids_b.append(sid)
			junctions[b_j]["segment_ids"] = ids_b
	return segments


static func _walk_to_junction(
	start: Vector2i, dir: Vector2i, path_cells: Dictionary, junc_cells: Dictionary
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [start]
	var cur: Vector2i = start + dir
	while path_cells.has(cur) and not junc_cells.has(cur):
		cells.append(cur)
		cur += dir
	if path_cells.has(cur) and junc_cells.has(cur):
		cells.append(cur)
		return cells
	return []


static func _edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return "%d,%d:%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d:%d,%d" % [b.x, b.y, a.x, a.y]


static func _link_clearing_lines(graph: Dictionary) -> void:
	## Extend maze rows/cols through rooms. No radial hub from the room center.
	var rects: Array = graph.get("clearing_rects", [])
	var junctions: Array = graph.get("junctions", [])
	if rects.is_empty() or junctions.is_empty():
		return
	var cell_size: float = float(graph.get("cell_size", 4.0))
	var mouths := _clearing_mouth_indices(graph)
	for rect in rects:
		var origin: Vector3 = rect["origin"]
		var size: Vector3 = rect["size"]
		var local_mouths := PackedInt32Array()
		for mouth in mouths:
			var pos: Vector3 = junctions[mouth]["pos"]
			if _dist_to_aabb_xz(pos, origin, size) <= cell_size * 1.01:
				local_mouths.append(mouth)
		if local_mouths.size() < 2:
			continue
		_add_clearing_grid(graph, local_mouths)


static func _add_clearing_grid(graph: Dictionary, mouths: PackedInt32Array) -> void:
	var junctions: Array = graph["junctions"]
	var marked: Dictionary = graph.get("clearing_cells", {})
	var cols := {}
	var rows := {}
	var cell_to_j := {}
	for mouth in mouths:
		var cell: Vector2i = junctions[mouth]["cell"]
		if cell.x < 0:
			continue
		cols[cell.x] = true
		rows[cell.y] = true
		cell_to_j[cell] = mouth
	var maze_w := int(graph.get("maze_width", 1))
	var maze_h := int(graph.get("maze_height", 1))
	var cell_size: float = float(graph.get("cell_size", 4.0))
	for gx in cols.keys():
		for gy in rows.keys():
			var cell := Vector2i(int(gx), int(gy))
			if cell_to_j.has(cell) or not marked.has(cell):
				continue
			cell_to_j[cell] = _new_clearing_junction(
				junctions, cell, maze_w, maze_h, cell_size
			)
	var xs: Array[int] = _sorted_int_keys(cols)
	var ys: Array[int] = _sorted_int_keys(rows)
	for gy in ys:
		_connect_clearing_row(graph, cell_to_j, marked, xs, gy)
	for gx in xs:
		_connect_clearing_col(graph, cell_to_j, marked, ys, gx)


static func _new_clearing_junction(
	junctions: Array, cell: Vector2i, maze_w: int, maze_h: int, cell_size: float
) -> int:
	var j_i: int = junctions.size()
	junctions.append({
		"cell": cell,
		"pos": MazeGeometryScript.grid_to_world(
			cell.x, cell.y, maze_w, maze_h, cell_size
		),
		"segment_ids": PackedInt32Array(),
	})
	return j_i


static func _sorted_int_keys(keys: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for key in keys.keys():
		out.append(int(key))
	out.sort()
	return out


static func _connect_clearing_row(
	graph: Dictionary, cell_to_j: Dictionary, marked: Dictionary, xs: Array[int], gy: int
) -> void:
	var pts: Array[Vector2i] = []
	for gx in xs:
		var cell := Vector2i(gx, gy)
		if cell_to_j.has(cell):
			pts.append(cell)
	_connect_clearing_run(graph, cell_to_j, marked, pts)


static func _connect_clearing_col(
	graph: Dictionary, cell_to_j: Dictionary, marked: Dictionary, ys: Array[int], gx: int
) -> void:
	var pts: Array[Vector2i] = []
	for gy in ys:
		var cell := Vector2i(gx, gy)
		if cell_to_j.has(cell):
			pts.append(cell)
	_connect_clearing_run(graph, cell_to_j, marked, pts)


static func _connect_clearing_run(
	graph: Dictionary, cell_to_j: Dictionary, marked: Dictionary, pts: Array[Vector2i]
) -> void:
	for i in range(pts.size() - 1):
		if not _clearing_run_open(pts[i], pts[i + 1], marked):
			continue
		_append_via_segment(graph, int(cell_to_j[pts[i]]), int(cell_to_j[pts[i + 1]]))


static func _clearing_run_open(a: Vector2i, b: Vector2i, marked: Dictionary) -> bool:
	var delta := b - a
	if delta.x != 0 and delta.y != 0:
		return false
	if delta.x == 0 and delta.y == 0:
		return false
	var step := Vector2i(signi(delta.x), signi(delta.y))
	var cur: Vector2i = a + step
	while cur != b:
		if not marked.has(cur):
			return false
		cur += step
	return true


static func _append_via_segment(graph: Dictionary, a_j: int, b_j: int) -> void:
	if a_j == b_j:
		return
	var junctions: Array = graph["junctions"]
	var segments: Array = graph["segments"]
	var a_cell: Vector2i = junctions[a_j]["cell"]
	var b_cell: Vector2i = junctions[b_j]["cell"]
	var key := _edge_key(a_cell, b_cell)
	for seg in segments:
		if _edge_key(seg["a_cell"], seg["b_cell"]) == key:
			return
	var sid: int = segments.size()
	segments.append({
		"a": junctions[a_j]["pos"],
		"b": junctions[b_j]["pos"],
		"a_cell": a_cell,
		"b_cell": b_cell,
		"a_j": a_j,
		"b_j": b_j,
		"via_clearing": true,
	})
	var ids_a: PackedInt32Array = junctions[a_j]["segment_ids"]
	ids_a.append(sid)
	junctions[a_j]["segment_ids"] = ids_a
	var ids_b: PackedInt32Array = junctions[b_j]["segment_ids"]
	ids_b.append(sid)
	junctions[b_j]["segment_ids"] = ids_b


static func _clearing_world_rects(
	marked: Dictionary, maze_width: int, maze_height: int, cell_size: float
) -> Array:
	var visited := {}
	var rects: Array = []
	for start: Vector2i in marked.keys():
		if visited.has(start):
			continue
		var min_c := start
		var max_c := start
		var stack: Array[Vector2i] = [start]
		visited[start] = true
		while not stack.is_empty():
			var cell: Vector2i = stack.pop_back()
			min_c = Vector2i(mini(min_c.x, cell.x), mini(min_c.y, cell.y))
			max_c = Vector2i(maxi(max_c.x, cell.x), maxi(max_c.y, cell.y))
			for dir in DIRS:
				var nxt: Vector2i = cell + dir
				if not marked.has(nxt) or visited.has(nxt):
					continue
				visited[nxt] = true
				stack.append(nxt)
		var a: Vector3 = MazeGeometryScript.grid_to_world(
			min_c.x, min_c.y, maze_width, maze_height, cell_size
		)
		var b: Vector3 = MazeGeometryScript.grid_to_world(
			max_c.x, max_c.y, maze_width, maze_height, cell_size
		)
		var origin := Vector3(
			minf(a.x, b.x) - cell_size * 0.5,
			0.02,
			minf(a.z, b.z) - cell_size * 0.5
		)
		var size := Vector3(absf(b.x - a.x) + cell_size, 0.04, absf(b.z - a.z) + cell_size)
		rects.append({"origin": origin, "size": size})
	return rects
