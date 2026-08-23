@tool
extends Node3D

## Live editor for WizardChallengeHeight jump-puzzle towers. Open this scene
## directly in the Godot editor to place/shape/trap steps by dragging them in
## the 3D viewport, then Save Puzzle to a PuzzleDefinition .tres that
## WizardChallengeHeight can load at match time.
##
## Pick what "Add Object" creates from the Object To Add dropdown, click
## Add Object, then drag the new step (or pendulum peg, or platform) around
## in the viewport — pendulums swing live right there in the editor. A
## Moving Platform's route is authored with "Path Point" objects: pick the
## platform from the Target Platform dropdown, then Add Object → Path Point
## to extend its route, and drag each point into place.
## Moving platforms only animate at actual runtime (F6), not while editing.
## The tower's ground-level footprint is built from Base Piece objects —
## Rectangular Base (a flat slab), Rectangular Hole, and Cylindrical Hole
## (open-topped pits) — add as many as you like and drag them into place.
## Select an object in the Scene tree and click Remove Object to delete it.
## Placed objects are real scene children (owned by this scene root), so
## Ctrl+S persists your layout and pressing F6 runs THIS exact layout — a
## test player is dropped in automatically so you can climb it immediately.

enum ObjectType {
	BOX_STEP,
	CYLINDER_STEP,
	RAMP_STEP,
	CRUMBLE_TRAP,
	LAUNCH_TRAP,
	SUMMIT,
	PENDULUM,
	MOVING_PLATFORM,
	PATH_POINT,
	STAIRCASE_STEP,
	RECT_BASE_PIECE,
	RECT_HOLE_PIECE,
	CYLINDER_HOLE_PIECE,
}

const PlayableScene := preload("res://scenes/characters/playable_character.tscn")
const PuzzleStepNodeScript := preload("res://scripts/objectives/puzzle_step_node.gd")
const PuzzlePendulumNodeScript := preload("res://scripts/objectives/puzzle_pendulum_node.gd")
const PuzzleMovingPlatformNodeScript := preload(
	"res://scripts/objectives/puzzle_moving_platform_node.gd"
)
const PuzzleBasePieceNodeScript := preload("res://scripts/objectives/puzzle_base_piece_node.gd")

const SUMMIT_SIZE := Vector3(2.4, 0.35, 2.4)
## Default spawn spot for a fresh pendulum peg — centered above the tower;
## drag it into place afterward.
const DEFAULT_PENDULUM_POSITION := Vector3(0.0, 3.5, 0.0)
## Default spawn spot for a fresh moving platform's path anchor.
const DEFAULT_PLATFORM_POSITION := Vector3(0.0, 1.0, 0.0)
## Default offset for a fresh path point, relative to the platform's last
## point (or its anchor, if it has none yet).
const DEFAULT_PATH_POINT_OFFSET := Vector3(1.5, 0.0, 0.0)
## Default spawn spot for a fresh base piece — centered under the tower.
const DEFAULT_BASE_PIECE_POSITION := Vector3.ZERO

@export_group("Puzzle")
@export var puzzle_name: String = "New Puzzle"
## Where a freshly-added step lands relative to the previous one.
@export_range(0.1, 1.0, 0.05) var default_step_rise: float = 0.4
@export_range(1.0, 6.0, 0.1) var default_radius: float = 3.0
@export_range(0.1, 3.0, 0.05) var default_angle_step_turns: float = 0.35

@export_group("Objects")
@export_enum(
	"Box Step", "Cylinder Step", "Ramp Step", "Crumble Trap", "Launch Trap", "Summit",
	"Pendulum", "Moving Platform", "Path Point", "Staircase Step",
	"Rectangular Base", "Rectangular Hole", "Cylindrical Hole"
)
var object_to_add: int = ObjectType.BOX_STEP
## Which Moving Platform a new Path Point (see Object To Add above) is
## appended to. Populated from the platforms currently placed; add a Moving
## Platform first if this shows "No platforms yet". Hint is refreshed
## dynamically in _validate_property() below.
@export var target_platform_index: int = 0
@export_tool_button("Add Object", "Callable")
var add_object_action := add_object
## Removes whichever step(s) are currently selected in the Scene tree.
@export_tool_button("Remove Object", "Callable")
var remove_object_action := remove_object
@export_tool_button("Clear All Objects", "Callable")
var clear_all_objects_action := clear_all_objects

@export_group("Save / Load")
@export_file("*.tres") var puzzle_path: String = (
	"res://resources/objectives/puzzles/new_puzzle.tres"
)
@export_tool_button("Save Puzzle", "Callable")
var save_puzzle_action := save_puzzle
@export_tool_button("Load Puzzle", "Callable")
var load_puzzle_action := load_puzzle

@export_group("Playtest")
## A test player auto-spawns when you run this scene (F6). F9 / F10
## manually respawn / clear it while editing.
@export_tool_button("Spawn Test Player", "Callable")
var spawn_player_action := spawn_test_player
@export_tool_button("Clear Test Player", "Callable")
var clear_player_action := clear_test_player


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_unhandled_input(true)
	if _is_playing():
		call_deferred("spawn_test_player")


## Redraws the Target Platform dropdown's options from the platforms
## currently placed, every time the inspector asks about it.
func _validate_property(property: Dictionary) -> void:
	if property.name != "target_platform_index":
		return
	var names := _platform_names()
	property.hint = PROPERTY_HINT_ENUM
	property.hint_string = "No platforms yet" if names.is_empty() else ",".join(names)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() and not _is_playing():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_F9:
			spawn_test_player()
		KEY_F10:
			clear_test_player()
		_:
			return
	get_viewport().set_input_as_handled()


## --- Object placement ---------------------------------------------------

func add_object() -> void:
	match object_to_add:
		ObjectType.BOX_STEP:
			_append_step(PuzzleStepEntry.Shape.BOX, PuzzleStepEntry.Trap.NONE, false)
		ObjectType.CYLINDER_STEP:
			_append_step(PuzzleStepEntry.Shape.CYLINDER, PuzzleStepEntry.Trap.NONE, false)
		ObjectType.RAMP_STEP:
			_append_step(PuzzleStepEntry.Shape.RAMP, PuzzleStepEntry.Trap.NONE, false)
		ObjectType.CRUMBLE_TRAP:
			_append_step(PuzzleStepEntry.Shape.BOX, PuzzleStepEntry.Trap.CRUMBLE, false)
		ObjectType.LAUNCH_TRAP:
			_append_step(PuzzleStepEntry.Shape.BOX, PuzzleStepEntry.Trap.LAUNCH, false)
		ObjectType.SUMMIT:
			_append_step(PuzzleStepEntry.Shape.BOX, PuzzleStepEntry.Trap.NONE, true)
		ObjectType.PENDULUM:
			_append_pendulum()
		ObjectType.MOVING_PLATFORM:
			_append_platform()
		ObjectType.PATH_POINT:
			_append_path_point()
		ObjectType.STAIRCASE_STEP:
			_append_step(PuzzleStepEntry.Shape.STAIRCASE, PuzzleStepEntry.Trap.NONE, false)
		ObjectType.RECT_BASE_PIECE:
			_append_base_piece(PuzzleBasePieceEntry.Shape.RECT_BASE)
		ObjectType.RECT_HOLE_PIECE:
			_append_base_piece(PuzzleBasePieceEntry.Shape.RECT_HOLE)
		ObjectType.CYLINDER_HOLE_PIECE:
			_append_base_piece(PuzzleBasePieceEntry.Shape.CYLINDER_HOLE)


func remove_object() -> void:
	var steps_root := get_node_or_null("StepsRoot")
	var pendulums_root := get_node_or_null("PendulumsRoot")
	var platforms_root := get_node_or_null("PlatformsRoot")
	var base_pieces_root := get_node_or_null("BasePiecesRoot")
	var removed := 0
	for node in _editor_selection():
		if node is PuzzleStepNode and steps_root != null and node.get_parent() == steps_root:
			steps_root.remove_child(node)
			node.free()
			removed += 1
		elif (
			node is PuzzlePendulumNode
			and pendulums_root != null
			and node.get_parent() == pendulums_root
		):
			pendulums_root.remove_child(node)
			node.free()
			removed += 1
		elif (
			node is PuzzleMovingPlatformNode
			and platforms_root != null
			and node.get_parent() == platforms_root
		):
			platforms_root.remove_child(node)
			node.free()
			removed += 1
		elif node is PuzzlePlatformPathPointNode and node.get_parent() is PuzzleMovingPlatformNode:
			var parent: Node = node.get_parent()
			parent.remove_child(node)
			node.free()
			removed += 1
		elif (
			node is PuzzleBasePieceNode
			and base_pieces_root != null
			and node.get_parent() == base_pieces_root
		):
			base_pieces_root.remove_child(node)
			node.free()
			removed += 1
	if removed == 0:
		push_warning(
			"PuzzleWorkshop: select one or more objects in the Scene tree, then click Remove Object."
		)
	else:
		notify_property_list_changed()  ## Refresh the Target Platform dropdown.


func clear_all_objects() -> void:
	_clear_node("StepsRoot")
	_clear_node("PendulumsRoot")
	_clear_node("PlatformsRoot")
	_clear_node("BasePiecesRoot")
	notify_property_list_changed()  ## Refresh the Target Platform dropdown.


func _append_step(
	shape: PuzzleStepEntry.Shape,
	trap: PuzzleStepEntry.Trap,
	is_summit: bool
) -> void:
	var root := _ensure_bucket("StepsRoot", true)
	var prev := _last_step(root)
	var node: PuzzleStepNode = PuzzleStepNodeScript.new()
	node.name = "Summit" if is_summit else "Step_%d" % root.get_child_count()
	node.position = _default_next_position(prev)
	node.size = SUMMIT_SIZE if is_summit else _default_size_for(shape)
	root.add_child(node)
	_own(node)
	node.shape = shape
	node.trap_type = trap
	if trap == PuzzleStepEntry.Trap.LAUNCH:
		## trap_param's default (0.6) is tuned for CRUMBLE's seconds-before-drop
		## meaning; a fresh Launch Trap should start at normal jump pad strength.
		node.trap_param = 1.0
	if is_summit:
		_clear_other_summits(root, node)
		node.is_summit = true


func _clear_other_summits(root: Node3D, keep: PuzzleStepNode) -> void:
	for child in root.get_children():
		if child is PuzzleStepNode and child != keep:
			(child as PuzzleStepNode).is_summit = false


func _default_size_for(shape: PuzzleStepEntry.Shape) -> Vector3:
	match shape:
		PuzzleStepEntry.Shape.CYLINDER:
			return Vector3(1.3, 0.3, 1.3)
		PuzzleStepEntry.Shape.RAMP:
			return Vector3(1.6, 0.6, 1.4)
		PuzzleStepEntry.Shape.STAIRCASE:
			return Vector3(1.6, 0.8, 1.8)
		_:
			return Vector3(1.6, 0.3, 1.15)


func _default_next_position(prev: PuzzleStepNode) -> Vector3:
	if prev == null:
		return Vector3(default_radius, default_step_rise, 0.0)
	var radius := Vector2(prev.position.x, prev.position.z).length()
	if radius < 0.1:
		radius = default_radius
	var angle := atan2(prev.position.z, prev.position.x) + TAU * default_angle_step_turns
	return Vector3(
		cos(angle) * radius,
		prev.position.y + default_step_rise,
		sin(angle) * radius
	)


func _last_step(root: Node3D) -> PuzzleStepNode:
	if root.get_child_count() == 0:
		return null
	return root.get_child(root.get_child_count() - 1) as PuzzleStepNode


func _append_pendulum() -> void:
	var root := _ensure_bucket("PendulumsRoot", true)
	var node: PuzzlePendulumNode = PuzzlePendulumNodeScript.new()
	node.name = "Pendulum_%d" % root.get_child_count()
	node.position = DEFAULT_PENDULUM_POSITION
	root.add_child(node)
	_own(node)


func _append_platform() -> void:
	var root := _ensure_bucket("PlatformsRoot", true)
	var node: PuzzleMovingPlatformNode = PuzzleMovingPlatformNodeScript.new()
	node.name = "Platform_%d" % root.get_child_count()
	node.position = DEFAULT_PLATFORM_POSITION
	root.add_child(node)
	_own(node)
	notify_property_list_changed()  ## Refresh the Target Platform dropdown.


## Adds a path point to the platform picked in the Target Platform dropdown.
func _append_path_point() -> void:
	var platform := _target_platform_for_path_point()
	if platform == null:
		push_warning(
			"PuzzleWorkshop: add a Moving Platform first, then pick it from the Target"
			+ " Platform dropdown before Add Object → Path Point."
		)
		return
	var existing := platform.path_point_children()
	var local_pos := DEFAULT_PATH_POINT_OFFSET
	if not existing.is_empty():
		local_pos = existing[existing.size() - 1].position + DEFAULT_PATH_POINT_OFFSET
	var point := platform.new_path_point(local_pos)
	point.name = "Point_%d" % existing.size()
	platform.add_child(point)
	_own(point)


func _platform_nodes() -> Array[PuzzleMovingPlatformNode]:
	var result: Array[PuzzleMovingPlatformNode] = []
	var root := get_node_or_null("PlatformsRoot")
	if root == null:
		return result
	for child in root.get_children():
		if child is PuzzleMovingPlatformNode:
			result.append(child as PuzzleMovingPlatformNode)
	return result


func _platform_names() -> PackedStringArray:
	var names := PackedStringArray()
	for platform in _platform_nodes():
		names.append(platform.name)
	return names


func _target_platform_for_path_point() -> PuzzleMovingPlatformNode:
	var platforms := _platform_nodes()
	if platforms.is_empty():
		return null
	return platforms[clampi(target_platform_index, 0, platforms.size() - 1)]


func _append_base_piece(shape: PuzzleBasePieceEntry.Shape) -> void:
	var root := _ensure_bucket("BasePiecesRoot", true)
	var node: PuzzleBasePieceNode = PuzzleBasePieceNodeScript.new()
	node.name = "BasePiece_%d" % root.get_child_count()
	node.position = DEFAULT_BASE_PIECE_POSITION
	root.add_child(node)
	_own(node)
	node.shape = shape
	node.size = _default_base_piece_size(shape)


func _default_base_piece_size(shape: PuzzleBasePieceEntry.Shape) -> Vector3:
	match shape:
		PuzzleBasePieceEntry.Shape.RECT_HOLE:
			return Vector3(2.0, 1.5, 2.0)
		PuzzleBasePieceEntry.Shape.CYLINDER_HOLE:
			return Vector3(1.5, 1.5, 1.5)
		_:
			return Vector3(5.4, 0.2, 5.4)


## --- Save / load --------------------------------------------------------

func save_puzzle() -> void:
	var puzzle := PuzzleDefinition.new()
	puzzle.puzzle_name = puzzle_name
	var steps: Array[PuzzleStepEntry] = []
	var root := get_node_or_null("StepsRoot")
	if root != null:
		for child in root.get_children():
			if child is PuzzleStepNode:
				steps.append((child as PuzzleStepNode).to_entry())
	puzzle.steps = steps

	var pendulums: Array[PuzzlePendulumEntry] = []
	var pendulums_root := get_node_or_null("PendulumsRoot")
	if pendulums_root != null:
		for child in pendulums_root.get_children():
			if child is PuzzlePendulumNode:
				pendulums.append((child as PuzzlePendulumNode).to_entry())
	puzzle.pendulums = pendulums

	var platforms: Array[PuzzleMovingPlatformEntry] = []
	var platforms_root := get_node_or_null("PlatformsRoot")
	if platforms_root != null:
		for child in platforms_root.get_children():
			if child is PuzzleMovingPlatformNode:
				platforms.append((child as PuzzleMovingPlatformNode).to_entry())
	puzzle.platforms = platforms

	var base_pieces: Array[PuzzleBasePieceEntry] = []
	var base_pieces_root := get_node_or_null("BasePiecesRoot")
	if base_pieces_root != null:
		for child in base_pieces_root.get_children():
			if child is PuzzleBasePieceNode:
				base_pieces.append((child as PuzzleBasePieceNode).to_entry())
	puzzle.base_pieces = base_pieces

	var dir := puzzle_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := ResourceSaver.save(puzzle, puzzle_path)
	if err != OK:
		push_error("PuzzleWorkshop: failed to save '%s' (error %d)" % [puzzle_path, err])
	else:
		print(
			"PuzzleWorkshop: saved %d step(s), %d pendulum(s), %d platform(s), %d base piece(s) to %s"
			% [steps.size(), pendulums.size(), platforms.size(), base_pieces.size(), puzzle_path]
		)


func load_puzzle() -> void:
	if not ResourceLoader.exists(puzzle_path):
		push_error("PuzzleWorkshop: no puzzle found at '%s'" % puzzle_path)
		return
	var puzzle := ResourceLoader.load(
		puzzle_path, "", ResourceLoader.CACHE_MODE_IGNORE
	) as PuzzleDefinition
	if puzzle == null:
		push_error("PuzzleWorkshop: failed to load '%s' as a PuzzleDefinition" % puzzle_path)
		return

	_clear_node("StepsRoot")
	_clear_node("PendulumsRoot")
	_clear_node("PlatformsRoot")
	_clear_node("BasePiecesRoot")
	puzzle_name = puzzle.puzzle_name
	var root := _ensure_bucket("StepsRoot", true)
	for i in puzzle.steps.size():
		var entry: PuzzleStepEntry = puzzle.steps[i]
		var node: PuzzleStepNode = PuzzleStepNodeScript.from_entry(entry)
		node.name = "Summit" if entry.is_summit else "Step_%d" % i
		root.add_child(node)
		_own(node)

	var pendulums_root := _ensure_bucket("PendulumsRoot", true)
	for i in puzzle.pendulums.size():
		var pendulum_entry: PuzzlePendulumEntry = puzzle.pendulums[i]
		var pendulum_node: PuzzlePendulumNode = PuzzlePendulumNodeScript.from_entry(pendulum_entry)
		pendulum_node.name = "Pendulum_%d" % i
		pendulums_root.add_child(pendulum_node)
		_own(pendulum_node)

	var platforms_root := _ensure_bucket("PlatformsRoot", true)
	for i in puzzle.platforms.size():
		var platform_entry: PuzzleMovingPlatformEntry = puzzle.platforms[i]
		var platform_node: PuzzleMovingPlatformNode = PuzzleMovingPlatformNodeScript.from_entry(
			platform_entry
		)
		platform_node.name = "Platform_%d" % i
		platforms_root.add_child(platform_node)
		_own(platform_node)
		for j in platform_node.path_point_children().size():
			_own(platform_node.path_point_children()[j])

	var base_pieces_root := _ensure_bucket("BasePiecesRoot", true)
	for i in puzzle.base_pieces.size():
		var base_piece_entry: PuzzleBasePieceEntry = puzzle.base_pieces[i]
		var base_piece_node: PuzzleBasePieceNode = PuzzleBasePieceNodeScript.from_entry(
			base_piece_entry
		)
		base_piece_node.name = "BasePiece_%d" % i
		base_pieces_root.add_child(base_piece_node)
		_own(base_piece_node)

	print(
		(
			"PuzzleWorkshop: loaded %d step(s), %d pendulum(s), %d platform(s), %d base piece(s)"
			+ " from %s"
		)
		% [
			puzzle.steps.size(), puzzle.pendulums.size(), puzzle.platforms.size(),
			puzzle.base_pieces.size(), puzzle_path
		]
	)
	notify_property_list_changed()  ## Refresh the Target Platform dropdown.


## --- Playtest --------------------------------------------------------------

func spawn_test_player() -> void:
	clear_test_player()
	var player := PlayableScene.instantiate() as Node3D
	if player == null:
		push_error("PuzzleWorkshop: Spawn Test Player failed to instance playable_character.tscn")
		return
	var playing := _is_playing()
	player.name = "PlayableCharacter"
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	var root := _ensure_bucket("PlayerRoot", false)
	root.add_child(player)
	_prepare_sandbox_player(player, playing)
	player.global_position = Vector3(default_radius + 1.5, 0.5, 0.0)
	_set_overview_current(not playing)


func clear_test_player() -> void:
	_clear_node("PlayerRoot")
	_set_overview_current(true)


func _prepare_sandbox_player(player: Node3D, playing: bool) -> void:
	## Editor does not run PlayableCharacter._ready (script is not @tool).
	if "is_alive" in player:
		player.set("is_alive", true)
	if not player.is_in_group("player"):
		player.add_to_group("player")
	if player is CollisionObject3D:
		(player as CollisionObject3D).collision_layer = 1
		(player as CollisionObject3D).collision_mask = 1
	if playing:
		return
	var cam := player.find_child("FirstPersonCamera", true, false) as Camera3D
	if cam != null:
		cam.current = false
	var sync := player.get_node_or_null("MultiplayerSynchronizer")
	if sync != null:
		sync.process_mode = Node.PROCESS_MODE_DISABLED


func _set_overview_current(enabled: bool) -> void:
	var cam := get_node_or_null("Camera3D") as Camera3D
	if cam != null:
		cam.current = enabled


## --- Shared helpers --------------------------------------------------------

func _is_playing() -> bool:
	return not Engine.is_editor_hint() or (
		get_tree() != null and get_tree().edited_scene_root == null
	)


## Marks a node as owned by the scene root so Ctrl+S (and F6, which always
## runs what's on disk) actually serializes it — required for placed steps
## to persist and for drag edits to survive a save.
func _own(node: Node) -> void:
	if node == null:
		return
	var root: Node = self
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		root = get_tree().edited_scene_root
	node.owner = root


func _ensure_bucket(bucket_name: String, persist: bool) -> Node3D:
	var bucket := get_node_or_null(bucket_name) as Node3D
	if bucket != null:
		return bucket
	bucket = Node3D.new()
	bucket.name = bucket_name
	bucket.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(bucket)
	if persist:
		_own(bucket)
	return bucket


func _clear_node(node_name: String) -> void:
	var node := get_node_or_null(node_name)
	if node == null:
		return
	var kids := node.get_children()
	for child in kids:
		node.remove_child(child)
		child.free()


## Editor-only: returns the nodes currently selected in the Scene tree dock.
## There is no EditorSelection access from a plain @tool script without a
## custom EditorPlugin, so this walks the scene tree for the running
## EditorNode singleton the same way wizard_challenge_height.gd does.
func _editor_selection() -> Array:
	if not Engine.is_editor_hint() or get_tree() == null:
		return []
	for child in get_tree().root.get_children():
		if child.get_class() == "EditorNode" and child.has_method("get_editor_selection"):
			return child.get_editor_selection().get_selected_nodes()
	return []
