@tool
class_name WizardChallengeHeight
extends Node3D

## Race objective: climb a procedural jumping-puzzle tower that spawns in the
## largest clearing on the map, and be first to press [interact] at the
## summit statue. Completes for the whole match (like DeliveryObjective).

signal phase_changed(phase: int)
signal completed(winner_peer_id: int)

const InputPromptScript := preload("res://scripts/ui/input_prompt.gd")
const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")
const PuzzleStepNodeScript := preload("res://scripts/objectives/puzzle_step_node.gd")
const PuzzlePendulumNodeScript := preload("res://scripts/objectives/puzzle_pendulum_node.gd")
const PuzzleMovingPlatformNodeScript := preload(
	"res://scripts/objectives/puzzle_moving_platform_node.gd"
)
const PuzzleBasePieceNodeScript := preload("res://scripts/objectives/puzzle_base_piece_node.gd")
const RoundedBoxMeshScript := preload("res://scripts/objectives/rounded_box_mesh.gd")

## Bottom-rim fillet radius for procedural steps (matches PuzzleStepNode).
const BOTTOM_ROUND_RADIUS := 0.1

const INTERACT_RANGE := 1.8
const INTERACT_RANGE_SQ := INTERACT_RANGE * INTERACT_RANGE

## Clearing margin kept clear around the tower footprint (meters).
const CLEARING_MARGIN := 1.0
const MIN_TOWER_RADIUS := 2.0
const MAX_TOWER_RADIUS := 6.0

const PLATFORM_SIZE := Vector3(1.6, 0.3, 1.15)
const STATUE_HEIGHT := 1.9

## Steps in the ascending spiral. Total tower height ≈ step_count * step_rise.
@export_range(6, 120, 1) var step_count: int = 42
## Vertical rise per step (meters). Kept small — a single jump reaches ~0.3m.
@export_range(0.1, 1.0, 0.05) var step_rise: float = 0.4
## Roughly how far apart (arc length, meters) consecutive platforms sit.
@export_range(0.6, 3.0, 0.1) var step_arc_length: float = 1.3
## Every Nth step is spaced further out, forcing an actual horizontal jump.
@export_range(2, 12, 1) var gap_every: int = 5
## Multiplies the angular spacing on a gap step.
@export_range(1.1, 3.0, 0.1) var gap_spacing_multiplier: float = 1.8

## Hand-built layout from scenes/objectives/puzzle_workshop.tscn. When set,
## the tower is built from these steps instead of the procedural spiral
## above (the procedural knobs are then ignored).
@export var puzzle: PuzzleDefinition

var state: WizardChallengeHeightState = WizardChallengeHeightState.new()

var _tower_root: Node3D
var _statue_root: Node3D
var _statue_world_pos: Vector3 = Vector3.ZERO
var _winner_peer_id: int = -1
var _has_spawn: bool = false


func _ready() -> void:
	add_to_group("wizard_challenge_height")


func setup(maze: Node3D, run_seed: int = -1) -> void:
	if state.phase == WizardChallengeHeightState.Phase.COMPLETE and not Engine.is_editor_hint():
		return
	if Engine.is_editor_hint():
		_clear_visuals()
		state = WizardChallengeHeightState.new()
		_winner_peer_id = -1
	if maze == null or not maze.has_method("get_wall_grid"):
		return

	var wall_grid: Array = maze.get_wall_grid()
	var maze_width: int = int(maze.get("maze_width"))
	var maze_height: int = int(maze.get("maze_height"))
	var cell_size: float = float(maze.get("cell_size"))
	if wall_grid.is_empty() or maze_width <= 0 or maze_height <= 0:
		return

	var clearing := ClearingPlacement.largest_clearing(wall_grid, maze_width, maze_height, cell_size)
	if clearing.is_empty():
		TomeDebug.log("WizardChallengeHeight", "No clearing available — skipping spawn")
		_has_spawn = false
		return

	_has_spawn = true
	if puzzle != null and not puzzle.steps.is_empty():
		_build_tower_from_puzzle(clearing["center"], puzzle)
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = _derive_seed(run_seed)
		_build_tower(clearing["center"], clearing["size"], rng)
	phase_changed.emit(state.phase)


func _derive_seed(run_seed: int) -> int:
	var base_seed := run_seed
	if base_seed < 0:
		base_seed = GameState.run_seed if not Engine.is_editor_hint() else 4242
	return hash("%d:wizard_challenge_height" % base_seed)


func is_complete() -> bool:
	return state.phase == WizardChallengeHeightState.Phase.COMPLETE


func has_spawn() -> bool:
	return _has_spawn


func get_status_lines() -> PackedStringArray:
	if not _has_spawn:
		return PackedStringArray()
	return state.get_status_lines()


func get_interaction_prompt(player: Node) -> String:
	if not _has_spawn or state.phase != WizardChallengeHeightState.Phase.ACTIVE:
		return ""
	if player is Node3D and _is_near((player as Node3D).global_position, _statue_world_pos):
		return InputPromptScript.with_action("interact", "Press to win the challenge!")
	return ""


func try_interact(player: Node) -> bool:
	if not _has_spawn or not player.is_in_group("player"):
		return false
	if GameState.is_multiplayer:
		return _try_interact_multiplayer(player)
	return _try_interact_local(player)


func apply_network_op(op: int, payload: Variant = null) -> void:
	match op:
		WizardChallengeHeightSync.NetworkOp.REQUEST_WIN:
			var interact := payload as Array
			_host_apply_win(int(interact[0]))
		WizardChallengeHeightSync.NetworkOp.BROADCAST_STATE:
			_apply_synced_state(WizardChallengeHeightSync.unpack_snapshot(payload as Dictionary))


func _try_interact_local(player: Node) -> bool:
	if not (player is Node3D):
		return false
	var body := player as Node3D
	if state.try_win(body, body.global_position, _statue_world_pos, INTERACT_RANGE_SQ):
		_winner_peer_id = _peer_id_for_player(player)
		completed.emit(_winner_peer_id)
		phase_changed.emit(state.phase)
		return true
	return false


func _try_interact_multiplayer(player: Node) -> bool:
	var can_try := (
		MatchStateManager.allows_gameplay_actions()
		and player.is_multiplayer_authority()
		and state.phase == WizardChallengeHeightState.Phase.ACTIVE
		and player is Node3D
	)
	if not can_try:
		return false
	var body := player as Node3D
	if not _is_near(body.global_position, _statue_world_pos):
		return false
	var actor_peer_id := _peer_id_for_player(player)
	if multiplayer.is_server():
		return _host_apply_win(actor_peer_id)
	NetworkManager.relay_wizard_challenge_height(
		WizardChallengeHeightSync.NetworkOp.REQUEST_WIN,
		[actor_peer_id]
	)
	return false


func _host_apply_win(actor_peer_id: int) -> bool:
	var player := _find_player(actor_peer_id)
	if player == null:
		return false
	var result := WizardChallengeHeightSync.apply_host_win(
		state.phase,
		actor_peer_id,
		player.global_position,
		_statue_world_pos,
		INTERACT_RANGE_SQ
	)
	if result.is_empty():
		return false
	var new_phase: int = int(result.get("phase", state.phase))
	state.phase = new_phase as WizardChallengeHeightState.Phase
	_winner_peer_id = int(result.get("winner_peer_id", -1))
	completed.emit(_winner_peer_id)
	phase_changed.emit(state.phase)
	NetworkManager.relay_wizard_challenge_height(
		WizardChallengeHeightSync.NetworkOp.BROADCAST_STATE,
		WizardChallengeHeightSync.pack_snapshot(state.phase, _winner_peer_id)
	)
	return true


func _apply_synced_state(result: Dictionary) -> void:
	var previous_phase := state.phase
	var new_phase: int = int(result.get("phase", state.phase))
	state.phase = new_phase as WizardChallengeHeightState.Phase
	_winner_peer_id = int(result.get("winner_peer_id", -1))
	if previous_phase != state.phase:
		if state.phase == WizardChallengeHeightState.Phase.COMPLETE:
			completed.emit(_winner_peer_id)
		phase_changed.emit(state.phase)


func _peer_id_for_player(player: Node) -> int:
	return int(player.get_multiplayer_authority())


func _find_player(peer_id: int) -> Node3D:
	if peer_id <= 0:
		return null
	for node in get_tree().get_nodes_in_group("player"):
		if node is Node3D and int(node.get_multiplayer_authority()) == peer_id:
			return node as Node3D
	return null


func _is_near(a: Vector3, b: Vector3) -> bool:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return dx * dx + dz * dz <= INTERACT_RANGE_SQ


func _clear_visuals() -> void:
	while get_child_count() > 0:
		var child := get_child(0)
		remove_child(child)
		child.free()
	_tower_root = null
	_statue_root = null


## --- Hand-authored tower (from a saved PuzzleDefinition) -------------------

func _build_tower_from_puzzle(center: Vector3, puzzle_def: PuzzleDefinition) -> void:
	_clear_visuals()

	_tower_root = Node3D.new()
	_tower_root.name = "TowerRoot"
	_tower_root.position = Vector3(center.x, 0.0, center.z)
	add_child(_tower_root)

	for base_piece_entry in puzzle_def.base_pieces:
		if base_piece_entry == null:
			continue
		var base_piece: PuzzleBasePieceNode = PuzzleBasePieceNodeScript.from_entry(base_piece_entry)
		base_piece.name = "BasePiece"
		_tower_root.add_child(base_piece)

	for entry in puzzle_def.steps:
		if entry == null:
			continue
		var node: PuzzleStepNode = PuzzleStepNodeScript.from_entry(entry)
		node.name = "Step"
		_tower_root.add_child(node)

	for pendulum_entry in puzzle_def.pendulums:
		if pendulum_entry == null:
			continue
		var pendulum: PuzzlePendulumNode = PuzzlePendulumNodeScript.from_entry(pendulum_entry)
		pendulum.name = "Pendulum"
		_tower_root.add_child(pendulum)

	for platform_entry in puzzle_def.platforms:
		if platform_entry == null:
			continue
		var platform: PuzzleMovingPlatformNode = PuzzleMovingPlatformNodeScript.from_entry(
			platform_entry
		)
		platform.name = "MovingPlatform"
		_tower_root.add_child(platform)

	var summit := puzzle_def.find_summit_step()
	if summit != null:
		_build_statue(summit.position, summit.size.y)


## --- Procedural jumping-puzzle tower -------------------------------------

func _build_tower(center: Vector3, footprint: Vector3, rng: RandomNumberGenerator) -> void:
	_clear_visuals()

	_tower_root = Node3D.new()
	_tower_root.name = "TowerRoot"
	_tower_root.position = Vector3(center.x, 0.0, center.z)
	add_child(_tower_root)

	var radius := clampf(
		minf(footprint.x, footprint.z) * 0.5 - CLEARING_MARGIN,
		MIN_TOWER_RADIUS,
		MAX_TOWER_RADIUS
	)
	var steps_per_loop := maxi(6, int(round(TAU * radius / step_arc_length)))
	var start_angle := rng.randf_range(0.0, TAU)

	_build_base_pad(radius)

	var angle := start_angle
	var last_pos := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	for i in step_count:
		var angle_step := TAU / float(steps_per_loop)
		if gap_every > 0 and i > 0 and i % gap_every == 0:
			angle_step *= gap_spacing_multiplier
		angle += angle_step
		var y := float(i + 1) * step_rise
		var pos := Vector3(cos(angle) * radius, y, sin(angle) * radius)
		var is_summit := i == step_count - 1
		_add_platform(pos, last_pos, is_summit)
		last_pos = pos

	_build_statue(last_pos)


func _build_base_pad(radius: float) -> void:
	var pad := _make_platform_node(
		"BasePad",
		Vector3(radius * 2.0 + 0.6, 0.2, radius * 2.0 + 0.6),
		Color(0.28, 0.22, 0.4)
	)
	## Top face sits a hair above the maze floor to avoid z-fighting with it.
	pad.position = Vector3(0.0, -0.08, 0.0)
	_tower_root.add_child(pad)


func _add_platform(pos: Vector3, from_pos: Vector3, is_summit: bool) -> void:
	var size := PLATFORM_SIZE
	if is_summit:
		size = Vector3(2.4, 0.35, 2.4)
	var body := _make_platform_node(
		"Step",
		size,
		Color(0.42, 0.34, 0.58) if not is_summit else Color(0.55, 0.42, 0.85),
		true
	)
	body.position = pos
	_tower_root.add_child(body)
	var facing := Vector3(pos.x - from_pos.x, 0.0, pos.z - from_pos.z)
	if facing.length_squared() > 0.0001:
		body.look_at(pos + facing, Vector3.UP)


func _make_platform_node(
	node_name: String, size: Vector3, color: Color, rounded: bool = false
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0

	var mesh_instance := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.35
	material.emission_energy_multiplier = 1.2
	material.roughness = 0.6
	## Double-sided as insurance against a hand-built rounded-box mesh face
	## looking hollow/culled from a given angle.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material
	mesh_instance.layers = WorldVisualLayersScript.WORLD
	mesh_instance.set_meta("_edit_lock_", true)
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	body.add_child(collision)

	if rounded:
		mesh_instance.mesh = RoundedBoxMeshScript.build_mesh(size, BOTTOM_ROUND_RADIUS)
		var convex := ConvexPolygonShape3D.new()
		convex.points = RoundedBoxMeshScript.build_collision_points(size, BOTTOM_ROUND_RADIUS)
		collision.shape = convex
	else:
		var box := BoxMesh.new()
		box.size = size
		mesh_instance.mesh = box
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape

	return body


func _build_statue(summit_platform_pos: Vector3, step_height: float = -1.0) -> void:
	var resolved_height := step_height if step_height >= 0.0 else PLATFORM_SIZE.y
	_statue_root = Node3D.new()
	_statue_root.name = "Statue"
	_statue_root.position = summit_platform_pos + Vector3(0.0, resolved_height * 0.5 + 0.175, 0.0)
	_tower_root.add_child(_statue_root)

	var pedestal := MeshInstance3D.new()
	var pedestal_shape := CylinderMesh.new()
	pedestal_shape.top_radius = 0.4
	pedestal_shape.bottom_radius = 0.5
	pedestal_shape.height = 0.4
	pedestal.mesh = pedestal_shape
	pedestal.position.y = 0.2
	var pedestal_mat := StandardMaterial3D.new()
	pedestal_mat.albedo_color = Color(0.3, 0.28, 0.35)
	pedestal_mat.roughness = 0.5
	pedestal.material_override = pedestal_mat
	pedestal.layers = WorldVisualLayersScript.WORLD
	pedestal.set_meta("_edit_lock_", true)
	_statue_root.add_child(pedestal)

	var figure := MeshInstance3D.new()
	var figure_shape := CapsuleMesh.new()
	figure_shape.radius = 0.35
	figure_shape.height = STATUE_HEIGHT
	figure.mesh = figure_shape
	figure.position.y = 0.4 + STATUE_HEIGHT * 0.5
	var figure_mat := StandardMaterial3D.new()
	figure_mat.albedo_color = Color(0.85, 0.75, 0.35)
	figure_mat.emission_enabled = true
	figure_mat.emission = Color(0.95, 0.8, 0.3)
	figure_mat.emission_energy_multiplier = 1.6
	figure_mat.metallic = 0.4
	figure_mat.roughness = 0.25
	figure.material_override = figure_mat
	figure.layers = WorldVisualLayersScript.WORLD
	figure.set_meta("_edit_lock_", true)
	_statue_root.add_child(figure)

	var light := OmniLight3D.new()
	light.light_color = Color(0.95, 0.8, 0.35)
	light.light_energy = 3.0
	light.omni_range = 14.0
	light.position.y = 0.4 + STATUE_HEIGHT
	_statue_root.add_child(light)

	var label := Label3D.new()
	label.text = "PRESS [F] TO WIN"
	label.font_size = 72
	label.pixel_size = 0.015
	label.outline_size = 16
	label.modulate = Color(1.0, 0.92, 0.6)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position.y = 0.4 + STATUE_HEIGHT + 0.6
	_statue_root.add_child(label)

	_statue_world_pos = _statue_root.global_position
