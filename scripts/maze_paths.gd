@tool
class_name MazePaths
extends Node3D

## Runtime child of MazeGenerator. Lookdev overlay: patrol routes + spawn pads.

const MazePathGraphScript := preload("res://scripts/maze_path_graph.gd")
const MonsterRangeGizmosScript := preload("res://scripts/monsters/monster_range_gizmos.gd")

const PATH_COLOR := Color(0.35, 0.92, 1.0, 0.28)
const CLEAR_COLOR := Color(1.0, 0.82, 0.2, 0.18)
const VIABLE_COLOR := Color(0.2, 1.0, 0.48, 0.95)
const RETURN_COLOR := Color(0.95, 0.12, 0.14, 0.95)
const MONSTER_PAD_COLOR := Color(1.0, 0.18, 0.42, 0.95)
const PLAYER_PAD_COLOR := Color(0.15, 0.72, 1.0, 0.95)
const LINE_Y := 0.08
const RIBBON_Y := 0.14
const ARROW_Y := 0.22

var show_pathing: bool = false:
	set(value):
		show_pathing = value
		if is_inside_tree():
			_rebuild()

var graph: Dictionary = {}
var patrol_home: Vector3 = Vector3.ZERO
var patrol_size: Vector2 = Vector2.ZERO
var monster_pad: Vector3 = Vector3.ZERO
var player_pad: Vector3 = Vector3.ZERO


func _enter_tree() -> void:
	if not is_in_group("maze_paths"):
		add_to_group("maze_paths")


func set_graph(next: Dictionary) -> void:
	graph = next
	_rebuild()


func set_lookdev(state: Dictionary) -> void:
	monster_pad = state.get("monster_pad", Vector3.ZERO)
	player_pad = state.get("player_pad", Vector3.ZERO)
	patrol_home = state.get("patrol_home", Vector3.ZERO)
	patrol_size = state.get("patrol_size", Vector2.ZERO)
	_rebuild()


func _rebuild() -> void:
	_clear_kids()
	if not show_pathing:
		return
	if graph.is_empty():
		return
	_add_path_lines()
	_add_clearings()
	_add_preferred_paths()
	_add_return_paths()
	_add_center_marker()
	_add_spawn_pads()


func _clear_kids() -> void:
	var kids := get_children()
	for child in kids:
		remove_child(child)
		child.free()


func _add_path_lines() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var any := false
	for seg in graph.get("segments", []):
		var a: Vector3 = seg["a"]
		var b: Vector3 = seg["b"]
		st.add_vertex(Vector3(a.x, LINE_Y, a.z))
		st.add_vertex(Vector3(b.x, LINE_Y, b.z))
		any = true
	if not any:
		return
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "PathLines"
	mesh_inst.mesh = st.commit()
	mesh_inst.material_override = _line_mat(PATH_COLOR)
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_inst)


func _add_clearings() -> void:
	for rect in graph.get("clearing_rects", []):
		var origin: Vector3 = rect["origin"]
		var size: Vector3 = rect["size"]
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(maxf(size.x, 0.1), 0.05, maxf(size.z, 0.1))
		box.mesh = mesh
		box.position = origin + Vector3(size.x * 0.5, 0.04, size.z * 0.5)
		box.material_override = _fill_mat(CLEAR_COLOR)
		box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(box)


func _add_center_marker() -> void:
	var pos: Vector3 = _closest_corridor_point()
	if pos == Vector3.ZERO:
		pos = patrol_home
	var ball := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.22
	sph.height = 0.44
	ball.name = "PatrolCenter"
	ball.mesh = sph
	ball.position = Vector3(pos.x, 0.22, pos.z)
	ball.material_override = _line_mat(VIABLE_COLOR)
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ball)


func _add_spawn_pads() -> void:
	_add_spawn_marker("MonsterPad", monster_pad, MONSTER_PAD_COLOR, "Monster")
	_add_spawn_marker("PlayerPad", player_pad, PLAYER_PAD_COLOR, "Player")


func _add_preferred_paths() -> void:
	var ids: PackedInt32Array = MazePathGraphScript.viable_patrol_segment_ids(
		graph, patrol_home, patrol_size
	)
	for id in ids:
		var seg: Dictionary = graph["segments"][id]
		_add_ribbon("PreferredPath", seg["a"], seg["b"], VIABLE_COLOR)


func _add_return_paths() -> void:
	var skip := {}
	var viable_ids: PackedInt32Array = MazePathGraphScript.viable_patrol_segment_ids(
		graph, patrol_home, patrol_size
	)
	for id in viable_ids:
		skip[id] = true
	var edges: Array = MazePathGraphScript.return_homeward_edges(
		graph, patrol_home, patrol_size
	)
	for edge in edges:
		var sid := int(edge["id"])
		if skip.has(sid):
			continue
		_add_ribbon("ReturnPath", edge["from"], edge["to"], RETURN_COLOR)
	_add_homeward_arrows(edges, skip)


func _add_ribbon(node_name: String, a: Vector3, b: Vector3, color: Color) -> void:
	var delta := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length := delta.length()
	if length < 0.05:
		return
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.18, 0.06, length)
	box.name = node_name
	box.mesh = mesh
	box.position = Vector3((a.x + b.x) * 0.5, RIBBON_Y, (a.z + b.z) * 0.5)
	box.material_override = _fill_mat(color)
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(box)
	var look := Vector3(b.x, RIBBON_Y, b.z)
	if box.global_position.distance_squared_to(look) > 0.0001:
		box.look_at(look, Vector3.UP)


func _add_homeward_arrows(edges: Array, skip: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var cell := maxf(float(graph.get("cell_size", 4.0)), 1.0)
	for edge in edges:
		if skip.has(int(edge["id"])):
			continue
		if _append_chevrons(st, edge["from"], edge["to"], cell):
			any = true
	if not any:
		return
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "ReturnArrows"
	mesh_inst.mesh = st.commit()
	mesh_inst.material_override = _fill_mat(RETURN_COLOR)
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_inst)


func _append_chevrons(st: SurfaceTool, from: Vector3, to: Vector3, cell: float) -> bool:
	var delta := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var length := delta.length()
	if length < 0.35:
		return false
	var dir := delta / length
	var right := Vector3(-dir.z, 0.0, dir.x)
	var spacing := clampf(cell * 0.55, 1.2, 2.4)
	var count := maxi(int(floor(length / spacing)), 1)
	var added := false
	for i in count:
		var t := (float(i) + 0.55) / (float(count) + 0.1)
		t = clampf(t, 0.18, 0.88)
		var p := from.lerp(to, t)
		p.y = ARROW_Y
		var tip := p + dir * 0.32
		var back := p - dir * 0.18
		st.add_vertex(Vector3(tip.x, ARROW_Y, tip.z))
		st.add_vertex(Vector3(back.x - right.x * 0.16, ARROW_Y, back.z - right.z * 0.16))
		st.add_vertex(Vector3(back.x + right.x * 0.16, ARROW_Y, back.z + right.z * 0.16))
		added = true
	return added


func _closest_corridor_point() -> Vector3:
	## Prefer real maze lines in the patrol rect, not clearing crossings.
	var ids := PackedInt32Array()
	var segments: Array = graph.get("segments", [])
	for i in segments.size():
		if bool(segments[i].get("via_clearing", false)):
			continue
		if MazePathGraphScript.segment_touches_rect(graph, i, patrol_home, patrol_size):
			ids.append(i)
	if ids.is_empty():
		return MazePathGraphScript.closest_path_point(graph, patrol_home)
	var sid: int = MazePathGraphScript.nearest_segment_id_from(graph, patrol_home, ids)
	if sid < 0:
		return MazePathGraphScript.closest_path_point(graph, patrol_home)
	var seg: Dictionary = segments[sid]
	return _project_on_segment(patrol_home, seg["a"], seg["b"])


func _project_on_segment(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var ap := Vector3(p.x - a.x, 0.0, p.z - a.z)
	var len2 := ab.length_squared()
	var t := 0.0
	if len2 > 0.0001:
		t = clampf(ap.dot(ab) / len2, 0.0, 1.0)
	return Vector3(a.x + ab.x * t, 0.05, a.z + ab.z * t)


func _add_spawn_marker(node_name: String, pos: Vector3, color: Color, caption: String) -> void:
	var disc := MonsterRangeGizmosScript.ensure_disc(
		self, null, node_name, 1.15, Color(color.r, color.g, color.b, 0.55), 0.06, false
	)
	disc.position = Vector3(pos.x, 0.05, pos.z)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.05
	torus.outer_radius = 1.22
	ring.name = node_name + "Ring"
	ring.mesh = torus
	ring.position = Vector3(pos.x, 0.08, pos.z)
	ring.material_override = _fill_mat(color)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.07
	cyl.height = 2.4
	pole.name = node_name + "Beacon"
	pole.mesh = cyl
	pole.position = Vector3(pos.x, 1.2, pos.z)
	pole.material_override = _fill_mat(color)
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pole)
	var label := Label3D.new()
	label.name = node_name + "Label"
	label.text = caption
	label.font_size = 64
	label.pixel_size = 0.012
	label.outline_size = 14
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(pos.x, 2.55, pos.z)
	add_child(label)


func _line_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func _fill_mat(color: Color) -> StandardMaterial3D:
	var mat := _line_mat(color)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
