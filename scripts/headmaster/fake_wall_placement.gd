class_name FakeWallPlacement
extends Node

## After Fake Wall voice cast: aim ghost over open passages; confirm with interact.

signal placement_finished(confirmed: bool)

const MazePassageQueryScript := preload("res://scripts/headmaster/maze_passage_query.gd")
const FakeWallScript := preload("res://scripts/headmaster/fake_wall.gd")
const InputPromptScript := preload("res://scripts/ui/input_prompt.gd")
const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")
const GameWorldScript := preload("res://scripts/game_world.gd")

var _player: CharacterBody3D
var _spell: SpellDefinition
var _active := false
var _ghost: MeshInstance3D
var _ghost_material: StandardMaterial3D
var _target_cell := Vector2i(-1, -1)
var _target_valid := false


func configure(player: CharacterBody3D) -> void:
	_player = player


func is_active() -> bool:
	return _active


func begin(spell: SpellDefinition) -> bool:
	if _player == null or spell == null:
		return false
	if _active:
		cancel()
	_spell = spell
	_active = true
	_ensure_ghost()
	_ghost.visible = true
	set_process(true)
	_update_target()
	return true


func cancel() -> void:
	if not _active:
		return
	_teardown(false)


func try_confirm() -> bool:
	if not _active or not _target_valid:
		return false
	var maze := _find_maze()
	if maze == null:
		return false
	var cell := _target_cell
	if _cell_occupied(cell):
		return false
	var spell := _spell
	_teardown(true)
	_emit_place_request(spell, cell, maze)
	return true


func get_prompt() -> String:
	if not _active:
		return ""
	if _target_valid:
		return InputPromptScript.with_action("interact", "Place Fake Wall")
	return "Aim at an open corridor to place a Fake Wall"


func _process(_delta: float) -> void:
	if not _active:
		return
	_update_target()


func _update_target() -> void:
	_target_valid = false
	_target_cell = Vector2i(-1, -1)
	var maze := _find_maze()
	if maze == null or _ghost == null:
		_ghost.visible = false
		return
	var wall_grid: Array = maze.get_wall_grid()
	var aim := _aim_world_point()
	var origin_cell: Vector2i = maze.world_to_cell(aim)
	var cell := MazePassageQueryScript.nearest_open_passage_cell(wall_grid, origin_cell)
	if cell.x < 0 or _cell_occupied(cell):
		_ghost.visible = false
		return
	_target_cell = cell
	_target_valid = true
	var wall_size := _wall_size(maze)
	(_ghost.mesh as BoxMesh).size = wall_size
	var pos: Vector3 = maze.grid_to_world(cell.x, cell.y)
	pos.y = wall_size.y * 0.5
	_ghost.global_position = pos
	_ghost.visible = true


func _emit_place_request(spell: SpellDefinition, cell: Vector2i, maze: Node) -> void:
	if _player == null or spell == null:
		return
	var wall_size := _wall_size(maze)
	var origin: Vector3 = maze.grid_to_world(cell.x, cell.y)
	origin.y = wall_size.y * 0.5
	var params := {
		"effect_id": "fake_wall",
		"grid_x": cell.x,
		"grid_y": cell.y,
		"origin": origin,
		"size": wall_size,
	}
	if _player.has_method("_confirm_fake_wall_placement"):
		_player.call("_confirm_fake_wall_placement", spell, params)


func _teardown(confirmed: bool) -> void:
	_active = false
	set_process(false)
	if _ghost != null:
		_ghost.visible = false
	_target_valid = false
	_target_cell = Vector2i(-1, -1)
	placement_finished.emit(confirmed)


func _ensure_ghost() -> void:
	if _ghost != null:
		return
	_ghost = MeshInstance3D.new()
	_ghost.name = "FakeWallGhost"
	var box := BoxMesh.new()
	box.size = Vector3(3.0, 3.0, 3.0)
	_ghost.mesh = box
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.albedo_color = Color(0.55, 0.85, 1.0, 0.35)
	_ghost_material.emission_enabled = true
	_ghost_material.emission = Color(0.35, 0.7, 1.0)
	_ghost_material.emission_energy_multiplier = 0.8
	_ghost_material.roughness = 0.4
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = _ghost_material
	_ghost.layers = WorldVisualLayersScript.WORLD
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	var match_root := GameWorldScript.find_match_root(_player.get_tree())
	var parent: Node = match_root if match_root != null else _player
	parent.add_child(_ghost)


func _aim_world_point() -> Vector3:
	## Prefer reticle hit; fall back to wand→crosshair ray.
	if _player != null and _player.has_method("_crosshair_world_point"):
		return _player.call("_crosshair_world_point")
	if _player != null and _player.has_method("get_wand_cast_origin"):
		var origin: Vector3 = _player.call("get_wand_cast_origin")
		var look := Vector3.FORWARD
		if _player.has_method("get_wand_cast_direction"):
			look = _player.call("get_wand_cast_direction")
		return origin + look * 8.0
	if _player != null and _player.has_method("get_view_origin"):
		var view_origin: Vector3 = _player.call("get_view_origin")
		var view_look := Vector3.FORWARD
		if _player.has_method("get_view_direction"):
			view_look = _player.call("get_view_direction")
		return view_origin + view_look * 8.0
	return _player.global_position if _player != null else Vector3.ZERO


func _find_maze() -> Node:
	if _player == null or not _player.is_inside_tree():
		return null
	var match_root := GameWorldScript.find_match_root(_player.get_tree())
	if match_root != null:
		return match_root.get_node_or_null("MazeGenerator")
	return _player.get_tree().root.find_child("MazeGenerator", true, false)


func _wall_size(maze: Node) -> Vector3:
	var cell_size := 3.0
	var wall_height := 3.0
	if maze.get("cell_size") != null:
		cell_size = float(maze.get("cell_size"))
	if maze.get("wall_height") != null:
		wall_height = float(maze.get("wall_height"))
	return Vector3(cell_size, wall_height, cell_size)


func _cell_occupied(cell: Vector2i) -> bool:
	if _player == null or not _player.is_inside_tree():
		return false
	for node in _player.get_tree().get_nodes_in_group(FakeWallScript.GROUP_NAME):
		if node == null:
			continue
		var occupied: Variant = node.get("grid_cell")
		if occupied is Vector2i and occupied == cell:
			return true
	return false
