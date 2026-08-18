@tool
extends Node3D

## Generates a random maze and builds floor + wall collision geometry.
## Uses iterative recursive-backtracker with mean corridor length, then clearings.

signal maze_ready(
	spawn_position: Vector3,
	exit_position: Vector3,
	spawn_cell: Vector2i,
	exit_cell: Vector2i
)
signal exit_reached(player: Node3D)

const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")
const MazeGeometryScript := preload("res://scripts/maze_geometry.gd")
const MazePathGraphScript := preload("res://scripts/maze_path_graph.gd")
const MazePathsScript := preload("res://scripts/maze_paths.gd")
const PlayerSpawnLayoutScript := preload("res://scripts/player_spawn_layout.gd")

const SPAWN_ZONE_PREVIEW_NAME := "SpawnZonePreview"
const WALL_COLLISION_PREVIEW_NAME := "WallCollisionPreview"
const WALL_COLLISION_PREVIEW_COLOR := Color(0.1, 0.95, 1.0, 0.32)

## Maze extent in cells along X (odd wall-grid size is derived from this).
@export var maze_width: int = 15:
	set(value):
		maze_width = maxi(value, 1)
		_on_editor_dims_changed()
## Maze extent in cells along Z (odd wall-grid size is derived from this).
@export var maze_height: int = 15:
	set(value):
		maze_height = maxi(value, 1)
		_on_editor_dims_changed()
## World size of one maze cell in meters (floor tiles and wall spacing).
@export var cell_size: float = 3.0:
	set(value):
		cell_size = maxf(value, 0.1)
		_on_editor_dims_changed()
## Height of carved wall meshes and collision in meters.
@export var wall_height: float = 3.0
## When true, generates a maze automatically when the match scene starts.
@export var regenerate_on_ready: bool = true
## Typical straight corridor run length in maze cells before the carver prefers to turn.
@export_range(1.0, 12.0, 0.5) var mean_corridor_length: float = 3.0:
	set(value):
		mean_corridor_length = maxf(value, 1.0)
		_on_editor_shape_changed()
## Random half-range around mean corridor length. Target run is sampled in [mean−var, mean+var].
@export_range(0, 8, 1) var corridor_length_variance: int = 1:
	set(value):
		corridor_length_variance = maxi(value, 0)
		_on_editor_shape_changed()
## Clearings to place in each maze quadrant (not the whole maze). 1 ≈ up to 4 total.
@export_range(0, 8, 1) var clearing_count: int = 1:
	set(value):
		clearing_count = maxi(value, 0)
		_on_editor_shape_changed()
## Average radius of each random clearing in maze cells (actual size varies slightly).
@export_range(0.0, 8.0, 0.5) var clearing_size: float = 2.0:
	set(value):
		clearing_size = maxf(value, 0.0)
		_on_editor_shape_changed()
## Preferred center-to-center distance in maze cells (also vs spire). Higher spreads clearings out.
@export_range(0.0, 24.0, 0.5) var clearing_separation: float = 6.0:
	set(value):
		clearing_separation = maxf(value, 0.0)
		_on_editor_shape_changed()
## Radius of a fixed square clearing at maze center in maze cells. 0 disables the spire clearing.
@export_range(0.0, 12.0, 0.5) var spire_clearing_size: float = 0.0:
	set(value):
		spire_clearing_size = maxf(value, 0.0)
		_on_editor_shape_changed()
@export_group("Editor Preview")
## Draws translucent wall collision shapes in the editor for debugging.
@export var show_wall_collision_shapes: bool = false:
	set(value):
		show_wall_collision_shapes = value
		if is_inside_tree():
			_sync_wall_collision_preview()
## Corridor centerlines, junctions, clearings, return-to-patrol paths. Lookdev.
@export var show_pathing: bool = false:
	set(value):
		show_pathing = value
		if is_inside_tree():
			_apply_show_pathing()

var _wall_grid: Array = []
var _exit_triggered: bool = false
var _exit_world_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	if Engine.is_editor_hint():
		## Prefer Match.editor_refresh_environment_preview (maze + moon/clouds).
		_notify_main_editor_preview()
		## Fallback: if Match orchestration did not build geometry (common when
		## match.tscn is the edited root and a deferred rebuild is skipped),
		## generate locally so the viewport is never an empty grid.
		call_deferred("_editor_ensure_maze_geometry")
		return
	call_deferred("_deferred_generate")


func _on_editor_dims_changed() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	_notify_main_editor_preview()


func _on_editor_shape_changed() -> void:
	## Corridor / clearing knobs: same editor rebuild path as size changes.
	_on_editor_dims_changed()


func _notify_main_editor_preview() -> void:
	var main := get_parent()
	if main != null and main.has_method("editor_refresh_environment_preview"):
		main.editor_refresh_environment_preview()


func _editor_ensure_maze_geometry() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	## Match preview already populated Floor/Walls.
	if get_node_or_null("Floor") != null:
		return
	generate_maze(4242)


func _deferred_generate() -> void:
	if regenerate_on_ready:
		var seed_value: int = GameState.run_seed if GameState.run_seed >= 0 else -1
		generate_maze(seed_value)


func generate_maze(seed_value: int = -1) -> void:
	_clear_maze()
	_exit_triggered = false

	if seed_value >= 0:
		seed(seed_value)
	else:
		randomize()

	_wall_grid = MazeCarver.generate(maze_width, maze_height, -1, {
		"mean_corridor_length": mean_corridor_length,
		"corridor_length_variance": corridor_length_variance,
		"clearing_count": clearing_count,
		"clearing_size": clearing_size,
		"clearing_separation": clearing_separation,
		"spire_clearing_size": spire_clearing_size,
	})
	_build_floor()
	_build_walls()
	_build_maze_paths()

	var spawn := _cell_to_world(0, 0)
	spawn.y = 0.5
	var exit := _cell_to_world(maze_width - 1, maze_height - 1)
	exit.y = 0.5
	_exit_world_pos = exit

	_build_exit_marker(exit)
	if _wants_spawn_zone_preview():
		_build_spawn_zone_preview()
	maze_ready.emit(spawn, exit, Vector2i(0, 0), Vector2i(maze_width - 1, maze_height - 1))


func get_wall_grid() -> Array:
	return _wall_grid


func cell_to_world(cell_x: int, cell_y: int) -> Vector3:
	var pos := _cell_to_world(cell_x, cell_y)
	pos.y = 1.2
	return pos


func grid_to_world(gx: int, gy: int) -> Vector3:
	## Raw wall-grid cell center (includes corridor cells between rooms).
	return _grid_to_world(gx, gy)


func is_grid_open(gx: int, gy: int) -> bool:
	if _wall_grid.is_empty():
		return false
	if gx < 0 or gy < 0 or gx >= _wall_grid.size():
		return false
	var row: Array = _wall_grid[gx]
	if gy >= row.size():
		return false
	return int(row[gy]) == 0


func world_to_cell(world_position: Vector3) -> Vector2i:
	var offset := _maze_offset()
	var gx := int(round((world_position.x + offset.x) / cell_size))
	var gy := int(round((world_position.z + offset.z) / cell_size))
	return Vector2i(gx, gy)


## Convert a world position to a maze room cell (not raw wall-grid coords).
func world_position_to_maze_cell(world_position: Vector3) -> Vector2i:
	var offset := _maze_offset()
	var gx := int(round((world_position.x + offset.x) / cell_size))
	var gy := int(round((world_position.z + offset.z) / cell_size))
	var cell_x := clampi(int(floor(float(gx) / 2.0)), 0, maze_width - 1)
	var cell_y := clampi(int(floor(float(gy) / 2.0)), 0, maze_height - 1)
	return Vector2i(cell_x, cell_y)


func _wants_spawn_zone_preview() -> bool:
	## Lookdev workspace draws only the selected monster/player pads.
	if not Engine.is_editor_hint():
		return false
	var parent := get_parent()
	return parent == null or not ("monster_spawn" in parent)


func rebuild_spawn_zone_preview_from_slots(slots: Array) -> void:
	## Replace default roster pads with pads matching PlayerSpawnSlot cells.
	if not Engine.is_editor_hint():
		return
	var existing := get_node_or_null(SPAWN_ZONE_PREVIEW_NAME)
	if existing != null:
		remove_child(existing)
		existing.free()
	if slots.is_empty():
		_build_spawn_zone_preview()
		return

	var root := Node3D.new()
	root.name = SPAWN_ZONE_PREVIEW_NAME
	add_child(root)

	var apprentice_i := 0
	var apprentice_colors: Array[Color] = [
		Color(0.2, 0.75, 1.0, 0.55),
		Color(0.15, 0.95, 0.85, 0.55),
		Color(0.35, 0.65, 1.0, 0.55),
	]
	for slot in slots:
		if slot == null or not (slot is PlayerSpawnSlot):
			continue
		var spawn_slot := slot as PlayerSpawnSlot
		var cell: Vector2i = spawn_slot.spawn_cell
		if spawn_slot.role == PlayerSpawnSlot.Role.HEADMASTER:
			root.add_child(
				_make_spawn_zone_marker(
					cell,
					cell_size * 2.4,
					0.35,
					Color(0.85, 0.25, 0.95, 0.55),
					Color(0.7, 0.15, 0.9),
					"HeadmasterZone"
				)
			)
		else:
			var tint: Color = apprentice_colors[apprentice_i % apprentice_colors.size()]
			root.add_child(
				_make_spawn_zone_marker(
					cell,
					cell_size * 2.2,
					0.28,
					tint,
					Color(tint.r, tint.g, tint.b),
					"ApprenticeZone_%d" % apprentice_i
				)
			)
			apprentice_i += 1


func _clear_maze() -> void:
	# Free immediately so editor rebuilds do not stack duplicate floors/walls.
	while get_child_count() > 0:
		var child := get_child(0)
		remove_child(child)
		child.free()
	_wall_grid.clear()


func _grid_to_world(gx: int, gy: int) -> Vector3:
	return MazeGeometryScript.grid_to_world(gx, gy, maze_width, maze_height, cell_size)


func _cell_to_world(cell_x: int, cell_y: int) -> Vector3:
	return _grid_to_world(cell_x * 2 + 1, cell_y * 2 + 1)


func _maze_offset() -> Vector3:
	return MazeGeometryScript.maze_offset(maze_width, maze_height, cell_size)


func _build_floor() -> void:
	MazeGeometryScript.add_floor(self, maze_width, maze_height, cell_size)


func _build_walls() -> void:
	MazeGeometryScript.add_walls(
		self, _wall_grid, maze_width, maze_height, cell_size, wall_height
	)
	_sync_wall_collision_preview()


func _build_maze_paths() -> void:
	var paths: Node = MazePathsScript.new()
	paths.name = "MazePaths"
	add_child(paths)
	if paths.has_method("set_graph"):
		paths.call(
			"set_graph",
			MazePathGraphScript.build(_wall_grid, maze_width, maze_height, cell_size)
		)
	paths.set("show_pathing", show_pathing)


func _apply_show_pathing() -> void:
	var paths := get_node_or_null("MazePaths")
	if paths != null:
		paths.set("show_pathing", show_pathing)


func _sync_wall_collision_preview() -> void:
	var existing := get_node_or_null(WALL_COLLISION_PREVIEW_NAME)
	if existing != null:
		remove_child(existing)
		existing.free()

	if not Engine.is_editor_hint() or not show_wall_collision_shapes:
		return
	if _wall_grid.is_empty():
		return

	var transforms: Array[Transform3D] = []
	var half_height := wall_height * 0.5
	for gx in _wall_grid.size():
		for gy in _wall_grid[gx].size():
			if _wall_grid[gx][gy] != 1:
				continue
			var center: Vector3 = _grid_to_world(gx, gy)
			center.y = half_height
			transforms.append(Transform3D(Basis.IDENTITY, center))

	if transforms.is_empty():
		return

	var box := BoxMesh.new()
	box.size = Vector3(cell_size, wall_height, cell_size)

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = WALL_COLLISION_PREVIEW_COLOR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var preview := MultiMeshInstance3D.new()
	preview.name = WALL_COLLISION_PREVIEW_NAME
	preview.multimesh = multimesh
	preview.material_override = material
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	preview.set_meta("_edit_lock_", true)
	add_child(preview)


func _build_exit_marker(exit_position: Vector3) -> void:
	var gate_root := Node3D.new()
	gate_root.name = "RestorationGate"
	gate_root.position = exit_position
	add_child(gate_root)

	var marker := MeshInstance3D.new()
	marker.name = "Crystal"

	var crystal := CylinderMesh.new()
	crystal.top_radius = 0.25
	crystal.bottom_radius = 0.45
	crystal.height = 2.4
	marker.mesh = crystal
	marker.position = Vector3(0.0, 1.2, 0.0)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.9, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.25, 0.7, 0.95)
	material.emission_energy_multiplier = 2.5
	material.roughness = 0.1
	material.metallic = 0.15
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.9
	marker.material_override = material
	marker.layers = WorldVisualLayersScript.WORLD
	gate_root.add_child(marker)

	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 0.85, 1.0)
	light.light_energy = 2.0
	light.omni_range = 8.0
	light.position = Vector3(0.0, 2.2, 0.0)
	gate_root.add_child(light)

	var trigger := Area3D.new()
	trigger.name = "ExitTrigger"
	trigger.collision_layer = 0
	trigger.collision_mask = 1
	trigger.monitoring = true
	trigger.monitorable = false
	trigger.body_entered.connect(_on_exit_body_entered)

	var trigger_shape := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.8
	shape.height = 3.5
	trigger_shape.shape = shape
	trigger_shape.position = Vector3(0.0, 1.5, 0.0)
	trigger.add_child(trigger_shape)
	gate_root.add_child(trigger)


func _build_spawn_zone_preview() -> void:
	## Editor-only: large role-colored pads at headmaster center + apprentice corners.
	var roster: Array[Vector2i] = PlayerSpawnLayoutScript.collect_roster_spawn_cells(
		_wall_grid,
		maze_width,
		maze_height
	)
	if roster.is_empty():
		return

	var root := Node3D.new()
	root.name = SPAWN_ZONE_PREVIEW_NAME
	add_child(root)

	# Headmaster — magenta center pad
	root.add_child(
		_make_spawn_zone_marker(
			roster[0],
			cell_size * 2.4,
			0.35,
			Color(0.85, 0.25, 0.95, 0.55),
			Color(0.7, 0.15, 0.9),
			"HeadmasterZone"
		)
	)

	# Apprentices — cyan corner pads
	var apprentice_colors: Array[Color] = [
		Color(0.2, 0.75, 1.0, 0.55),
		Color(0.15, 0.95, 0.85, 0.55),
		Color(0.35, 0.65, 1.0, 0.55),
	]
	for i in range(1, mini(roster.size(), 4)):
		var tint: Color = apprentice_colors[(i - 1) % apprentice_colors.size()]
		var emission := Color(tint.r, tint.g, tint.b)
		root.add_child(
			_make_spawn_zone_marker(
				roster[i],
				cell_size * 2.2,
				0.28,
				tint,
				emission,
				"ApprenticeZone_%d" % (i - 1)
			)
		)


func _make_spawn_zone_marker(
	cell: Vector2i,
	diameter: float,
	height: float,
	albedo: Color,
	emission: Color,
	marker_name: String
) -> MeshInstance3D:
	var world := _cell_to_world(cell.x, cell.y)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = marker_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = diameter * 0.5
	cylinder.bottom_radius = diameter * 0.5
	cylinder.height = height
	mesh_instance.mesh = cylinder
	mesh_instance.position = Vector3(world.x, height * 0.5, world.z)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = albedo
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = 2.0
	mat.disable_fog = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = mat
	return mesh_instance


func _on_exit_body_entered(body: Node3D) -> void:
	if _exit_triggered:
		return
	if not body.is_in_group("player"):
		return
	if not _is_exit_armed():
		return
	_exit_triggered = true
	exit_reached.emit(body)


func _is_exit_armed() -> bool:
	## Exit only resolves the match after the relic has been delivered.
	if not is_inside_tree():
		return false
	for node in get_tree().get_nodes_in_group("delivery_objective"):
		if node.has_method("is_complete"):
			return bool(node.call("is_complete"))
	# No delivery objective in the scene — keep legacy walk-in victory.
	return true


func reset_exit_trigger() -> void:
	_exit_triggered = false


func get_exit_approach_prompt(player: Node3D) -> String:
	if player == null or not _is_exit_armed():
		return ""
	var dx := player.global_position.x - _exit_world_pos.x
	var dz := player.global_position.z - _exit_world_pos.z
	if dx * dx + dz * dz > 9.0:
		return ""
	return "Walk into the gate to finish"
