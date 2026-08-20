@tool
class_name DeliveryObjective
extends Node3D

## Find the noisy relic and bring it to the turn-in shrine (solo-first).

signal phase_changed(phase: int)
signal completed

const InputPromptScript := preload("res://scripts/ui/input_prompt.gd")
const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")
const HoveringOrbMotionScript := preload("res://scripts/spells/hovering_orb_motion.gd")
const INTERACT_RANGE := 2.5
const INTERACT_RANGE_SQ := INTERACT_RANGE * INTERACT_RANGE
const PING_INTERVAL_SEC := 3.5
## Fixed float height above the ground under the relic.
const FLOAT_HEIGHT := HoveringOrbMotionScript.HEIGHT_RELIC
const CARRY_OFFSET := Vector3(0.35, -0.15, -0.55)
const RING_HEIGHT_Y := 0.95
const BEACON_HEIGHT := 140.0
const BEACON_RADIUS := 1.9
const BEACON_MID_RADIUS := 1.15
const BEACON_CORE_RADIUS := 0.42
const BEACON_COLOR := Color(0.22, 1.0, 0.48, 0.16)
const BEACON_MID_COLOR := Color(0.35, 1.0, 0.55, 0.28)
const BEACON_CORE_COLOR := Color(0.8, 1.0, 0.88, 0.55)
const BEACON_LIGHT_ENERGY := 14.0
const BEACON_IGNITE_SEC := 0.9
const BEACON_RETRACT_SEC := 0.32
const BEACON_RESOLVE_SEC := 0.75
const RING_SPIN_SEC := 1.05
const RING_SHRINK_SEC := 0.55
const RING_IDLE_SPIN_RAD_PER_SEC := 0.65
const EDITOR_SELECT_ORB_RING := "EditorSelectOrbRing"
const EDITOR_SELECT_SHRINE_RING := "EditorSelectShrineRing"

var state: DeliveryObjectiveState = DeliveryObjectiveState.new()

var _maze: Node3D
var _cell_to_world: Callable
var _item_root: Node3D
var _item_mesh: MeshInstance3D
var _item_audio: AudioStreamPlayer3D
var _turn_in_root: Node3D
var _turn_in_mesh: MeshInstance3D
var _turn_in_ring: MeshInstance3D
var _beacon_beam: MeshInstance3D
var _beacon_mid: MeshInstance3D
var _beacon_core: MeshInstance3D
var _beacon_ground: MeshInstance3D
var _beacon_light: SpotLight3D
var _beacon_base_light: OmniLight3D
var _beacon_tween: Tween
var _shrine_resolve_tween: Tween
var _beacon_active: bool = false
var _shrine_resolved: bool = false
var _editor_selected: bool = false
var _item_world_pos: Vector3 = Vector3.ZERO
var _turn_in_pos: Vector3 = Vector3.ZERO
var _carrier_peer_id: int = -1
var _ping_timer: float = 0.0
var _bob_time: float = 0.0
var _item_cell: Vector2i = Vector2i(-1, -1)
var _turn_in_cell: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	add_to_group("delivery_objective")
	if Engine.is_editor_hint():
		set_process(true)


func setup(
	maze: Node3D,
	spawn_cell: Vector2i,
	cell_to_world: Callable,
	run_seed: int = -1
) -> void:
	if state.phase == DeliveryObjectiveState.Phase.COMPLETE and not Engine.is_editor_hint():
		return
	if Engine.is_editor_hint():
		_clear_visuals()
		state = DeliveryObjectiveState.new()
		_shrine_resolved = false
		_beacon_active = false
	elif GameState.is_multiplayer:
		set_multiplayer_authority(1)
	_maze = maze
	_cell_to_world = cell_to_world
	var placement_seed := run_seed
	if placement_seed < 0:
		placement_seed = GameState.run_seed if not Engine.is_editor_hint() else 4242
	var near_spawn := false
	if not Engine.is_editor_hint() and SettingsManager != null:
		near_spawn = SettingsManager.dev_spawn_relic_near_spawn
	var spire_size := 0.0
	if maze.get("spire_clearing_size") != null:
		spire_size = float(maze.spire_clearing_size)
	var plan := ObjectivePlacement.plan(
		maze.get_wall_grid(),
		maze.maze_width,
		maze.maze_height,
		spawn_cell,
		placement_seed,
		near_spawn,
		spire_size
	)
	if plan.is_empty():
		TomeDebug.log("DeliveryObjective", "Could not plan objective cells")
		return

	_item_cell = plan.get("item_cell")
	_turn_in_cell = plan.get("turn_in_cell")
	_item_world_pos = _cell_center(_item_cell)
	_turn_in_pos = _cell_center(_turn_in_cell)
	_build_visuals()
	_apply_visuals_for_phase()
	if Engine.is_editor_hint():
		# Force a selection refresh after preview rebuild.
		_editor_selected = false
		_update_editor_selection_highlight()
	phase_changed.emit(state.phase)


func get_interaction_prompt(player: Node) -> String:
	match state.phase:
		DeliveryObjectiveState.Phase.SEEK_ITEM:
			if _is_near(player.global_position, _item_world_pos):
				return InputPromptScript.with_action("interact", "Pick it up?")
		DeliveryObjectiveState.Phase.CARRIED:
			if state.carrier == player:
				if _is_near(player.global_position, _turn_in_pos):
					return InputPromptScript.with_action("interact", "Leave it?")
				return InputPromptScript.with_action("interact", "Drop it")
	return ""


func get_spell_target_nodes() -> Array[Node3D]:
	## Only the world relic is targetable (not the shrine).
	var nodes: Array[Node3D] = []
	if state.phase != DeliveryObjectiveState.Phase.SEEK_ITEM:
		return nodes
	if _item_root != null and is_instance_valid(_item_root):
		nodes.append(_item_root)
	return nodes


func spell_pull_relic_to(world_pos: Vector3) -> void:
	## Instant placement helper — animated pulls go through guided motion.
	if state.phase != DeliveryObjectiveState.Phase.SEEK_ITEM:
		return
	_item_world_pos = _snap_relic_to_ground(world_pos)
	_sync_item_transform()


func spell_follow_relic_to(world_pos: Vector3, blend: float = 1.0) -> void:
	if state.phase != DeliveryObjectiveState.Phase.SEEK_ITEM:
		return
	var t := clampf(blend, 0.0, 1.0)
	var dest := _snap_relic_to_ground(world_pos)
	_item_world_pos = _item_world_pos.lerp(dest, t)
	_item_world_pos = _snap_relic_to_ground(_item_world_pos)
	_sync_item_transform()


func spell_set_guided_relic_position(world_pos: Vector3, lock_to_ground: bool = true) -> void:
	## Update cruise base; bobbing continues on top via _update_world_bob.
	if state.phase != DeliveryObjectiveState.Phase.SEEK_ITEM:
		return
	if lock_to_ground:
		_item_world_pos = _snap_relic_to_ground(world_pos)
	else:
		_item_world_pos = world_pos
	_update_world_bob()


func get_relic_motion_base() -> Vector3:
	return _item_world_pos


func is_complete() -> bool:
	return state.phase == DeliveryObjectiveState.Phase.COMPLETE


func is_carrier(player: Node) -> bool:
	return (
		state.phase == DeliveryObjectiveState.Phase.CARRIED
		and state.carrier == player
	)


func try_interact(player: Node) -> bool:
	if not player.is_in_group("player"):
		return false
	if GameState.is_multiplayer:
		return _try_interact_multiplayer(player)
	return _try_interact_local(player)


func get_status_lines() -> PackedStringArray:
	return state.get_status_lines()


func _process(delta: float) -> void:
	_spin_idle_ring(delta)
	if Engine.is_editor_hint():
		_update_editor_selection_highlight()
		return
	_bob_time += delta
	if state.phase == DeliveryObjectiveState.Phase.SEEK_ITEM:
		_update_world_bob()

	if state.phase == DeliveryObjectiveState.Phase.COMPLETE:
		return
	if GameState.is_multiplayer and not multiplayer.is_server():
		return

	_ping_timer += delta
	if _ping_timer >= PING_INTERVAL_SEC:
		_ping_timer = 0.0
		if GameState.is_multiplayer:
			if MatchStateManager.allows_gameplay_actions():
				NetworkManager.relay_delivery_objective(
					DeliveryObjectiveSync.NetworkOp.BROADCAST_PING
				)
		else:
			_play_ping()


func _update_editor_selection_highlight() -> void:
	var selected := _is_selected_in_editor()
	if selected == _editor_selected:
		return
	_editor_selected = selected
	_apply_editor_selection_visuals()


func _is_selected_in_editor() -> bool:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return false
	var selection = _editor_selection()
	if selection == null:
		return false
	var selected: Array = selection.get_selected_nodes()
	for node in selected:
		if node == self:
			return true
		if node is Node and is_ancestor_of(node):
			return true
	return false


func _editor_selection():
	var root := get_tree().root
	if root == null:
		return null
	for child in root.get_children():
		if child.get_class() == "EditorNode" and child.has_method("get_editor_selection"):
			return child.get_editor_selection()
	return null


func _apply_editor_selection_visuals() -> void:
	_style_preview_mesh(
		_item_mesh,
		_editor_selected,
		Color(0.95, 0.78, 0.22),
		Color(0.95, 0.65, 0.15),
		0.8,
		5.0
	)
	_style_preview_mesh(
		_turn_in_mesh,
		_editor_selected,
		Color(0.35, 0.82, 0.42),
		Color(0.25, 0.65, 0.35),
		0.5,
		4.5
	)
	_style_preview_mesh(
		_turn_in_ring,
		_editor_selected,
		Color(0.45, 0.95, 0.55),
		Color(0.35, 0.85, 0.45),
		1.6,
		5.5
	)
	_update_editor_select_marker(
		_item_root,
		EDITOR_SELECT_ORB_RING,
		0.55,
		0.85,
		0.35,
		Color(1.0, 0.9, 0.25)
	)
	_update_editor_select_marker(
		_turn_in_root,
		EDITOR_SELECT_SHRINE_RING,
		1.7,
		2.2,
		0.06,
		Color(0.45, 1.0, 0.55)
	)


func _style_preview_mesh(
	mesh: MeshInstance3D,
	selected: bool,
	albedo: Color,
	emission: Color,
	unselected_energy: float,
	selected_energy: float
) -> void:
	if mesh == null or not is_instance_valid(mesh):
		return
	var mat := mesh.material_override as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		mesh.material_override = mat
	mat.albedo_color = albedo
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = selected_energy if selected else unselected_energy
	mat.disable_fog = true


func _update_editor_select_marker(
	parent: Node3D,
	marker_name: String,
	inner_radius: float,
	outer_radius: float,
	height_y: float,
	color: Color
) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var marker := parent.get_node_or_null(marker_name) as MeshInstance3D
	if not _editor_selected:
		if marker != null:
			marker.free()
		return
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = marker_name
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.set_meta("_edit_lock_", true)
		parent.add_child(marker)
	var torus := TorusMesh.new()
	torus.inner_radius = inner_radius
	torus.outer_radius = outer_radius
	marker.mesh = torus
	marker.position = Vector3(0.0, height_y, 0.0)
	marker.rotation.x = PI * 0.5
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.92)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 6.0
	mat.disable_fog = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.layers = WorldVisualLayersScript.WORLD


func _spin_idle_ring(delta: float) -> void:
	if _shrine_resolved:
		return
	if state.phase == DeliveryObjectiveState.Phase.COMPLETE:
		return
	if _turn_in_ring == null or not is_instance_valid(_turn_in_ring):
		return
	_turn_in_ring.rotation.y += RING_IDLE_SPIN_RAD_PER_SEC * delta


func _play_ping() -> void:
	if _item_audio != null and is_instance_valid(_item_audio):
		_item_audio.play()
	if _item_mesh != null:
		var tween := create_tween()
		tween.tween_property(_item_mesh, "scale", Vector3.ONE * 1.25, 0.08)
		tween.tween_property(_item_mesh, "scale", Vector3.ONE, 0.12)


func _try_interact_local(player: Node) -> bool:
	match state.phase:
		DeliveryObjectiveState.Phase.SEEK_ITEM:
			if state.try_pickup(player, player.global_position, _item_world_pos, INTERACT_RANGE_SQ):
				_carrier_peer_id = _peer_id_for_player(player)
				_stop_caster_spells(player)
				_apply_visuals_for_phase()
				phase_changed.emit(state.phase)
				return true
		DeliveryObjectiveState.Phase.CARRIED:
			if state.carrier != player:
				return false
			if _is_near(player.global_position, _turn_in_pos):
				if state.try_deliver(
					player,
					player.global_position,
					_turn_in_pos,
					INTERACT_RANGE_SQ
				):
					_carrier_peer_id = -1
					_apply_visuals_for_phase()
					completed.emit()
					phase_changed.emit(state.phase)
					return true
			elif state.try_drop(player, player.global_position):
				_carrier_peer_id = -1
				_item_world_pos = _drop_world_position(player)
				_apply_visuals_for_phase()
				phase_changed.emit(state.phase)
				return true
	return false


func _try_interact_multiplayer(player: Node) -> bool:
	if not MatchStateManager.allows_gameplay_actions():
		return false
	if not player.is_multiplayer_authority():
		return false
	var actor_peer_id := _peer_id_for_player(player)
	var action := DeliveryObjectiveSync.resolve_interact_action(
		state.phase,
		_carrier_peer_id,
		actor_peer_id,
		player.global_position,
		_item_world_pos,
		_turn_in_pos,
		INTERACT_RANGE_SQ
	)
	if action < 0:
		return false
	if multiplayer.is_server():
		return _host_apply_action(actor_peer_id, action, player.global_position)
	NetworkManager.relay_delivery_objective(
		DeliveryObjectiveSync.NetworkOp.REQUEST_INTERACT,
		action
	)
	return false


func _host_apply_action(actor_peer_id: int, action: int, _client_pos: Vector3) -> bool:
	var player := _find_player(actor_peer_id)
	if player == null:
		return false
	var player_pos := player.global_position
	if action == DeliveryObjectiveSync.Action.DROP:
		player_pos = _drop_world_position(player)
	var result := DeliveryObjectiveSync.apply_host_action(
		action,
		state.phase,
		_carrier_peer_id,
		actor_peer_id,
		player_pos,
		_item_world_pos,
		_turn_in_pos,
		INTERACT_RANGE_SQ,
		FLOAT_HEIGHT
	)
	if result.is_empty():
		return false
	NetworkManager.relay_delivery_objective(
		DeliveryObjectiveSync.NetworkOp.BROADCAST_STATE,
		DeliveryObjectiveSync.pack_snapshot(
			int(result.get("phase", state.phase)),
			int(result.get("carrier_peer_id", -1)),
			result.get("item_world_pos", _item_world_pos)
		)
	)
	return true


func apply_network_op(op: int, payload: Variant = null) -> void:
	match op:
		DeliveryObjectiveSync.NetworkOp.REQUEST_INTERACT:
			var interact := payload as Array
			_host_apply_action(int(interact[0]), int(interact[1]), Vector3.ZERO)
		DeliveryObjectiveSync.NetworkOp.BROADCAST_STATE:
			_apply_synced_state(DeliveryObjectiveSync.unpack_snapshot(payload as Dictionary))
		DeliveryObjectiveSync.NetworkOp.BROADCAST_PING:
			_play_ping()


func _apply_synced_state(result: Dictionary) -> void:
	var previous_phase := state.phase
	var previous_carrier := state.carrier
	var new_phase: int = int(result.get("phase", state.phase))
	_carrier_peer_id = int(result.get("carrier_peer_id", -1))
	_item_world_pos = result.get("item_world_pos", _item_world_pos)
	state.phase = new_phase as DeliveryObjectiveState.Phase
	state.carrier = _find_player(_carrier_peer_id) if _carrier_peer_id > 0 else null
	if (
		state.phase == DeliveryObjectiveState.Phase.CARRIED
		and state.carrier != null
		and (previous_phase != DeliveryObjectiveState.Phase.CARRIED or state.carrier != previous_carrier)
	):
		_stop_caster_spells(state.carrier)
	_apply_visuals_for_phase()
	if previous_phase != state.phase:
		if state.phase == DeliveryObjectiveState.Phase.COMPLETE:
			completed.emit()
		phase_changed.emit(state.phase)


func _apply_visuals_for_phase() -> void:
	if state.phase == DeliveryObjectiveState.Phase.COMPLETE:
		_resolve_completed_shrine()
		return
	if _item_root == null:
		_sync_beacon_for_phase()
		return
	match state.phase:
		DeliveryObjectiveState.Phase.SEEK_ITEM:
			if _item_root.get_parent() != self:
				_item_root.reparent(self)
			_item_root.scale = Vector3.ONE
			_sync_item_transform()
			_sync_beacon_for_phase()
		DeliveryObjectiveState.Phase.CARRIED:
			if state.carrier != null:
				_attach_to_carrier(state.carrier as Node3D)
			_sync_beacon_for_phase()


func _peer_id_for_player(player: Node) -> int:
	return int(player.get_multiplayer_authority())


func _find_player(peer_id: int) -> Node3D:
	if peer_id <= 0:
		return null
	for node in get_tree().get_nodes_in_group("player"):
		if node is Node3D and int(node.get_multiplayer_authority()) == peer_id:
			return node as Node3D
	return null


func _clear_visuals() -> void:
	_kill_beacon_tween()
	if _shrine_resolve_tween != null and is_instance_valid(_shrine_resolve_tween):
		_shrine_resolve_tween.kill()
		_shrine_resolve_tween = null
	while get_child_count() > 0:
		var child := get_child(0)
		remove_child(child)
		child.free()
	_item_root = null
	_item_mesh = null
	_item_audio = null
	_turn_in_root = null
	_turn_in_mesh = null
	_turn_in_ring = null
	_beacon_beam = null
	_beacon_mid = null
	_beacon_core = null
	_beacon_ground = null
	_beacon_light = null
	_beacon_base_light = null


func _cell_center(cell: Vector2i) -> Vector3:
	var pos: Vector3 = _cell_to_world.call(cell.x, cell.y)
	return _snap_relic_to_ground(pos)


func _snap_relic_to_ground(pos: Vector3) -> Vector3:
	var world_3d := get_world_3d() if is_inside_tree() else null
	return HoveringOrbMotionScript.snap_base(world_3d, pos, FLOAT_HEIGHT)


func _ping_max_distance() -> float:
	if _maze == null:
		return 0.0
	return DeliveryObjectiveAudio.ping_max_distance(
		int(_maze.get("maze_width")),
		int(_maze.get("maze_height")),
		float(_maze.get("cell_size"))
	)


func _is_near(a: Vector3, b: Vector3) -> bool:
	# Horizontal range so shrine hand-in isn't blocked by camera/height offsets.
	var dx := a.x - b.x
	var dz := a.z - b.z
	return dx * dx + dz * dz <= INTERACT_RANGE_SQ


func _drop_world_position(player: Node) -> Vector3:
	if _item_root != null and is_instance_valid(_item_root):
		return _snap_relic_to_ground(_item_root.global_position)
	if player is Node3D:
		return _snap_relic_to_ground((player as Node3D).global_position)
	return _snap_relic_to_ground(_item_world_pos)


func _build_visuals() -> void:
	if _item_root == null:
		_item_root = Node3D.new()
		_item_root.name = "RelicItem"
		add_child(_item_root)

		var item_shape := SphereMesh.new()
		item_shape.radius = 0.28
		item_shape.height = 0.56
		_item_mesh = MeshInstance3D.new()
		_item_mesh.mesh = item_shape
		var item_mat := StandardMaterial3D.new()
		item_mat.albedo_color = Color(0.95, 0.78, 0.22)
		item_mat.emission_enabled = true
		item_mat.emission = Color(0.95, 0.65, 0.15) * 0.8
		_item_mesh.material_override = item_mat
		_item_mesh.layers = WorldVisualLayersScript.WORLD
		_item_mesh.set_meta("_edit_lock_", true)
		_item_root.add_child(_item_mesh)
		_item_root.set_meta("_edit_lock_", true)

		_item_audio = AudioStreamPlayer3D.new()
		_item_audio.stream = PlaceholderPingAudio.create_stream()
		_item_audio.max_distance = _ping_max_distance()
		_item_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		_item_root.add_child(_item_audio)

	if _turn_in_root == null:
		_turn_in_root = Node3D.new()
		_turn_in_root.name = "TurnInShrine"
		add_child(_turn_in_root)
		# Anchor on the floor so the beacon rises from the ground around the shrine.
		_turn_in_root.global_position = Vector3(_turn_in_pos.x, 0.0, _turn_in_pos.z)

		var pillar := CylinderMesh.new()
		pillar.top_radius = 0.35
		pillar.bottom_radius = 0.45
		pillar.height = 2.0
		_turn_in_mesh = MeshInstance3D.new()
		_turn_in_mesh.mesh = pillar
		_turn_in_mesh.position.y = pillar.height * 0.5
		var shrine_mat := StandardMaterial3D.new()
		shrine_mat.albedo_color = Color(0.35, 0.82, 0.42)
		shrine_mat.emission_enabled = true
		shrine_mat.emission = Color(0.25, 0.65, 0.35) * 0.5
		_turn_in_mesh.material_override = shrine_mat
		_turn_in_mesh.layers = WorldVisualLayersScript.WORLD
		_turn_in_mesh.set_meta("_edit_lock_", true)
		_turn_in_root.add_child(_turn_in_mesh)
		_turn_in_root.set_meta("_edit_lock_", true)

		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.55
		torus.outer_radius = 0.75
		ring.name = "TurnInRing"
		ring.mesh = torus
		# Sit around the pillar midsection, clearly above the floor.
		ring.position.y = RING_HEIGHT_Y
		ring.rotation.x = PI * 0.5
		var ring_mat := StandardMaterial3D.new()
		ring_mat.albedo_color = Color(0.45, 0.95, 0.55)
		ring_mat.emission_enabled = true
		ring_mat.emission = Color(0.35, 0.85, 0.45) * 0.55
		ring_mat.emission_energy_multiplier = 1.6
		ring_mat.disable_fog = true
		ring.material_override = ring_mat
		ring.layers = WorldVisualLayersScript.WORLD
		ring.set_meta("_edit_lock_", true)
		_turn_in_ring = ring
		_turn_in_root.add_child(ring)

		_build_shrine_beacon()


func _build_shrine_beacon() -> void:
	# Wide outer volume the player can walk into, plus denser inner shells for depth.
	_beacon_beam = _make_beacon_cylinder(
		"DeliveryBeaconBeam",
		BEACON_RADIUS,
		BEACON_RADIUS * 0.92,
		BEACON_COLOR,
		1.4
	)
	_beacon_mid = _make_beacon_cylinder(
		"DeliveryBeaconMid",
		BEACON_MID_RADIUS,
		BEACON_MID_RADIUS * 0.9,
		BEACON_MID_COLOR,
		2.4
	)
	_beacon_core = _make_beacon_cylinder(
		"DeliveryBeaconCore",
		BEACON_CORE_RADIUS,
		BEACON_CORE_RADIUS * 0.85,
		BEACON_CORE_COLOR,
		4.2
	)
	_turn_in_root.add_child(_beacon_beam)
	_turn_in_root.add_child(_beacon_mid)
	_turn_in_root.add_child(_beacon_core)

	_beacon_ground = MeshInstance3D.new()
	_beacon_ground.name = "DeliveryBeaconGroundGlow"
	var ground_disk := CylinderMesh.new()
	ground_disk.top_radius = BEACON_RADIUS * 1.05
	ground_disk.bottom_radius = BEACON_RADIUS * 1.05
	ground_disk.height = 0.06
	ground_disk.radial_segments = 48
	_beacon_ground.mesh = ground_disk
	_beacon_ground.position.y = 0.03
	_beacon_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon_ground.layers = WorldVisualLayersScript.WORLD
	var ground_mat := StandardMaterial3D.new()
	ground_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ground_mat.albedo_color = Color(0.3, 1.0, 0.5, 0.45)
	ground_mat.emission_enabled = true
	ground_mat.emission = Color(0.3, 1.0, 0.5)
	ground_mat.emission_energy_multiplier = 2.8
	ground_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ground_mat.disable_receive_shadows = true
	_beacon_ground.material_override = ground_mat
	_turn_in_root.add_child(_beacon_ground)

	_beacon_light = SpotLight3D.new()
	_beacon_light.name = "DeliveryBeaconLight"
	_beacon_light.light_color = Color(0.3, 1.0, 0.5)
	_beacon_light.light_energy = 0.0
	_beacon_light.spot_range = BEACON_HEIGHT
	_beacon_light.spot_attenuation = 0.45
	_beacon_light.spot_angle = 18.0
	_beacon_light.shadow_enabled = true
	_beacon_light.shadow_bias = 0.04
	_beacon_light.shadow_normal_bias = 1.0
	_beacon_light.light_volumetric_fog_energy = 4.0
	_beacon_light.light_cull_mask = WorldVisualLayersScript.SCENE_LIGHT_MASK
	_beacon_light.shadow_caster_mask = WorldVisualLayersScript.WORLD_LIGHT_MASK
	_beacon_light.position = Vector3(0.0, 0.2, 0.0)
	# SpotLight aims along -Z; tip it so the cone points skyward.
	_beacon_light.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_turn_in_root.add_child(_beacon_light)

	_beacon_base_light = OmniLight3D.new()
	_beacon_base_light.name = "DeliveryBeaconBaseLight"
	_beacon_base_light.light_color = Color(0.35, 1.0, 0.55)
	_beacon_base_light.light_energy = 0.0
	_beacon_base_light.omni_range = 16.0
	_beacon_base_light.omni_attenuation = 1.1
	_beacon_base_light.shadow_enabled = true
	_beacon_base_light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	_beacon_base_light.shadow_bias = 0.04
	_beacon_base_light.shadow_normal_bias = 1.1
	_beacon_base_light.light_volumetric_fog_energy = 4.0
	_beacon_base_light.light_cull_mask = WorldVisualLayersScript.SCENE_LIGHT_MASK
	_beacon_base_light.shadow_caster_mask = WorldVisualLayersScript.WORLD_LIGHT_MASK
	_beacon_base_light.position = Vector3(0.0, 0.8, 0.0)
	_turn_in_root.add_child(_beacon_base_light)

	_set_beacon_extend(0.0)
	_beacon_active = false


func _make_beacon_cylinder(
	node_name: String,
	bottom_radius: float,
	top_radius: float,
	color: Color,
	emission_energy: float
) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top_radius
	cylinder.bottom_radius = bottom_radius
	cylinder.height = BEACON_HEIGHT
	cylinder.radial_segments = 48
	cylinder.rings = 1

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.mesh = cylinder
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.layers = WorldVisualLayersScript.WORLD
	mesh_instance.set_meta("_edit_lock_", true)

	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.albedo_color = color
	beam_mat.emission_enabled = true
	beam_mat.emission = Color(color.r, color.g, color.b)
	beam_mat.emission_energy_multiplier = emission_energy
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_mat.disable_receive_shadows = true
	beam_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mesh_instance.material_override = beam_mat
	return mesh_instance


func _set_beacon_extend(amount: float) -> void:
	var extend := clampf(amount, 0.0, 1.0)
	# Grow from the floor upward around the shrine (lightsaber ignition).
	var mid_y := BEACON_HEIGHT * 0.5 * extend
	var beacon_scale := Vector3(1.0, maxf(extend, 0.001), 1.0)
	var beacon_visible := extend > 0.001
	for mesh in [_beacon_beam, _beacon_mid, _beacon_core]:
		if mesh != null and is_instance_valid(mesh):
			mesh.visible = beacon_visible
			mesh.scale = beacon_scale
			mesh.position.y = mid_y
	if _beacon_ground != null and is_instance_valid(_beacon_ground):
		_beacon_ground.visible = beacon_visible
		_beacon_ground.scale = Vector3(
			lerpf(0.35, 1.0, extend),
			1.0,
			lerpf(0.35, 1.0, extend)
		)
	if _beacon_light != null and is_instance_valid(_beacon_light):
		_beacon_light.visible = beacon_visible
		_beacon_light.light_energy = BEACON_LIGHT_ENERGY * extend
		_beacon_light.spot_range = BEACON_HEIGHT * extend
	if _beacon_base_light != null and is_instance_valid(_beacon_base_light):
		_beacon_base_light.visible = beacon_visible
		_beacon_base_light.light_energy = 6.5 * extend


func _kill_beacon_tween() -> void:
	if _beacon_tween != null and is_instance_valid(_beacon_tween):
		_beacon_tween.kill()
	_beacon_tween = null


func _hide_beacon_completely() -> void:
	_set_beacon_extend(0.0)
	_beacon_active = false
	for mesh in [_beacon_beam, _beacon_mid, _beacon_core, _beacon_ground]:
		if mesh != null and is_instance_valid(mesh):
			mesh.visible = false
	if _beacon_light != null and is_instance_valid(_beacon_light):
		_beacon_light.visible = false
		_beacon_light.light_energy = 0.0
	if _beacon_base_light != null and is_instance_valid(_beacon_base_light):
		_beacon_base_light.visible = false
		_beacon_base_light.light_energy = 0.0


func _set_shrine_beacon_active(active: bool) -> void:
	if _beacon_beam == null:
		return
	if active == _beacon_active and _beacon_tween == null:
		if not active:
			_hide_beacon_completely()
		return
	_beacon_active = active
	_kill_beacon_tween()

	var from_extend := 0.0
	if _beacon_beam != null:
		from_extend = _beacon_beam.scale.y
	var to_extend := 1.0 if active else 0.0
	var duration := BEACON_IGNITE_SEC if active else BEACON_RETRACT_SEC

	if _turn_in_mesh != null and state.phase != DeliveryObjectiveState.Phase.COMPLETE:
		var shrine_mat := _turn_in_mesh.material_override as StandardMaterial3D
		if shrine_mat != null:
			shrine_mat.emission = (
				Color(0.55, 1.0, 0.65) * 1.15 if active else Color(0.25, 0.65, 0.35) * 0.5
			)

	if not active and from_extend <= 0.001:
		_hide_beacon_completely()
		return

	_beacon_tween = create_tween()
	_beacon_tween.set_trans(Tween.TRANS_CUBIC)
	_beacon_tween.set_ease(Tween.EASE_OUT if active else Tween.EASE_IN)
	_beacon_tween.tween_method(_set_beacon_extend, from_extend, to_extend, duration)
	_beacon_tween.finished.connect(func() -> void:
		_beacon_tween = null
		if not active:
			_hide_beacon_completely()
	)


func _sync_beacon_for_phase() -> void:
	match state.phase:
		DeliveryObjectiveState.Phase.CARRIED:
			_set_shrine_beacon_active(true)
		DeliveryObjectiveState.Phase.COMPLETE:
			pass
		_:
			_set_shrine_beacon_active(false)


func _resolve_completed_shrine() -> void:
	## Hand-in: clear pillar/beacon, spin the ring out of existence.
	if _shrine_resolved:
		return
	_shrine_resolved = true

	if _item_root != null and is_instance_valid(_item_root):
		_item_root.visible = false
	if _turn_in_mesh != null and is_instance_valid(_turn_in_mesh):
		_turn_in_mesh.visible = false

	_kill_beacon_tween()
	_hide_beacon_completely()
	_play_ring_resolve_animation()


func _play_ring_resolve_animation() -> void:
	if _turn_in_ring == null or not is_instance_valid(_turn_in_ring):
		return
	if _shrine_resolve_tween != null and is_instance_valid(_shrine_resolve_tween):
		_shrine_resolve_tween.kill()
		_shrine_resolve_tween = null

	var ring_mat := _turn_in_ring.material_override as StandardMaterial3D
	if ring_mat != null:
		ring_mat.emission = Color(0.55, 1.0, 0.7)
		ring_mat.emission_energy_multiplier = 2.4

	var start_yaw := _turn_in_ring.rotation.y
	_shrine_resolve_tween = create_tween()
	_shrine_resolve_tween.set_trans(Tween.TRANS_SINE)
	_shrine_resolve_tween.set_ease(Tween.EASE_IN_OUT)
	_shrine_resolve_tween.tween_property(
		_turn_in_ring,
		"rotation:y",
		start_yaw + TAU * 3.0,
		RING_SPIN_SEC
	)
	_shrine_resolve_tween.tween_property(
		_turn_in_ring,
		"scale",
		Vector3.ZERO,
		RING_SHRINK_SEC
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_shrine_resolve_tween.tween_callback(_undraw_resolved_ring)


func _undraw_resolved_ring() -> void:
	_shrine_resolve_tween = null
	if _turn_in_ring != null and is_instance_valid(_turn_in_ring):
		_turn_in_ring.visible = false
		_turn_in_ring.queue_free()
		_turn_in_ring = null
	if _turn_in_mesh != null and is_instance_valid(_turn_in_mesh):
		_turn_in_mesh.queue_free()
		_turn_in_mesh = null
	if _item_root != null and is_instance_valid(_item_root):
		_item_root.queue_free()
		_item_root = null
		_item_mesh = null
		_item_audio = null


func _sync_item_transform() -> void:
	if _item_root == null:
		return
	_item_root.global_position = _item_world_pos


func _update_world_bob() -> void:
	if _item_root == null:
		return
	_item_root.global_position = HoveringOrbMotionScript.visual_from_base(
		_item_world_pos, _bob_time * HoveringOrbMotionScript.BOB_SPEED
	)


func _attach_to_carrier(player: Node3D) -> void:
	if _item_root == null or player == null:
		return
	var anchor := player.get_node_or_null("Head") as Node3D
	if anchor == null:
		anchor = player
	if _item_root.get_parent() != anchor:
		_item_root.reparent(anchor)
	_item_root.position = CARRY_OFFSET
	_item_root.rotation = Vector3.ZERO


func _detach_item_to_turn_in() -> void:
	## Kept for tests / callers; completion now resolves the whole shrine.
	if _item_root == null:
		return
	if _turn_in_root != null and _item_root.get_parent() != _turn_in_root:
		_item_root.reparent(_turn_in_root)
	_item_root.position = Vector3(0.0, 1.2, 0.0)
	_item_root.scale = Vector3.ONE * 0.85
	_item_root.visible = false


func _stop_caster_spells(player: Node) -> void:
	if player is PlayableCharacter:
		(player as PlayableCharacter).stop_casting_for_relic_carry()
