@tool
extends Node3D

const PlayerSpawnLayoutScript := preload("res://scripts/player_spawn_layout.gd")
const SpellEffectSyncScript := preload("res://scripts/spells/spell_effect_sync.gd")
const SpellWorldSyncScript := preload("res://scripts/spells/spell_world_sync.gd")
const NetworkManagerScript := preload("res://scripts/network/network_manager.gd")

# Fixed seed so opening match.tscn in the editor builds the same maze/clouds
# as a deterministic match.
const EDITOR_MATCH_SEED := 4242

var _game_won: bool = false
var _learn_confirm_pending: bool = false
var _local_player: CharacterBody3D
var _maze_spawn_cell: Vector2i = Vector2i(-1, -1)
var _maze_exit_cell: Vector2i = Vector2i(-1, -1)
var _maze_layout_ready: bool = false
var _players_spawned: bool = false
var _discoverables_spawned: bool = false
var _match_subsystems_active: bool = false
var _editor_rebuild_queued: bool = false

@onready var maze: Node3D = $MazeGenerator
@onready var moon: Moon = $Moon
@onready var cloud_system: CloudSystem = $CloudSystem
@onready var players_root: Node3D = $Players
@onready var smoke_trails: SmokeTrailManager = $SmokeTrails
@onready var discoverable_spawner: DiscoverableSpawner = $DiscoverableSpawner
@onready var spell_registry: SpellRegistry = $SpellRegistry
@onready var game_hud: CanvasLayer = $GameHUD
@onready var voice_validator: VoiceSpellValidator = $VoiceSpellValidator
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var delivery_objective: DeliveryObjective = $DeliveryObjective


func _ready() -> void:
	if Engine.is_editor_hint():
		call_deferred("editor_refresh_environment_preview")
		return

	_apply_voice_settings()
	SettingsManager.settings_applied.connect(_apply_voice_settings)
	maze.maze_ready.connect(_on_maze_ready)
	maze.exit_reached.connect(_on_exit_reached)
	pause_menu.quit_to_menu_requested.connect(_on_quit_to_menu)

	if GameState.is_multiplayer:
		MatchStateManager.snapshot_changed.connect(_on_match_snapshot_changed)
		multiplayer.peer_connected.connect(_on_peer_connected)
		var role_name := RoleAssignment.role_label(GameState.get_local_role())
		var phase_name := MatchState.phase_to_string(MatchStateManager.get_phase())
		TomeDebug.log(
			"Match",
			"Match start — role=%s phase=%s seed=%s"
			% [role_name, phase_name, GameState.run_seed]
		)
		MatchStateManager.log_summary()

	TrailRegistry.reset()

	await voice_validator.prepare_for_match()

	## Always start the match mic pipeline for wand STT (VoIP peers optional).
	## Solo / offline matches previously never enabled MATCH_FANOUT, so casts
	## recorded digital silence on a broken fallback path.
	SteamProximityVoiceHub.set_mode(SteamProximityVoiceHub.Mode.GAME)

	NetworkManager.spawn_players(
		players_root,
		_configure_local_player
	)
	await NetworkManager.players_spawned
	_players_spawned = true
	_finish_match_layout()


func editor_refresh_environment_preview() -> void:
	# Rebuild using the same generate_maze / configure_for_maze path as a real match.
	if not Engine.is_editor_hint():
		return
	## Allow re-entry after a completed rebuild (opening match.tscn as root can
	## queue notify-from-child + Match._ready; the second call used to no-op forever
	## if the first deferred build had not cleared the flag yet).
	if _editor_rebuild_queued:
		return
	_editor_rebuild_queued = true
	call_deferred("_editor_build_match_world")


func _editor_build_match_world() -> void:
	_editor_rebuild_queued = false
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var maze_node := get_node_or_null("MazeGenerator")
	if maze_node == null or not maze_node.has_method("generate_maze"):
		push_warning("Match: editor preview skipped — MazeGenerator missing")
		return
	if not maze_node.maze_ready.is_connected(_on_editor_maze_ready):
		maze_node.maze_ready.connect(_on_editor_maze_ready)
	maze_node.generate_maze(EDITOR_MATCH_SEED)


func _on_editor_maze_ready(
	_spawn_position: Vector3,
	_exit_position: Vector3,
	_spawn_cell: Vector2i,
	_exit_cell: Vector2i
) -> void:
	if not Engine.is_editor_hint():
		return
	_maze_spawn_cell = _spawn_cell
	_maze_exit_cell = _exit_cell
	_configure_sky_for_maze(EDITOR_MATCH_SEED, 1)
	_snap_player_spawn_slots()
	_editor_preview_delivery_objective()


func _editor_preview_delivery_objective() -> void:
	var maze_node := get_node_or_null("MazeGenerator")
	var objective := get_node_or_null("DeliveryObjective")
	if maze_node == null or objective == null:
		return
	if not objective.has_method("setup"):
		return
	objective.setup(
		maze_node,
		_maze_spawn_cell,
		Callable(maze_node, "cell_to_world"),
		EDITOR_MATCH_SEED
	)


func _configure_sky_for_maze(run_seed: int, start_time_msec: int) -> void:
	var maze_node := get_node_or_null("MazeGenerator")
	# Duck-type moon/clouds — typed `as Moon`/`as CloudSystem` can fail during
	# @tool script reloads and silently skip editor preview setup.
	var moon_node := get_node_or_null("Moon")
	var clouds := get_node_or_null("CloudSystem")
	if maze_node == null:
		return
	var cloud_field := Vector3.ZERO
	if clouds != null:
		var size_value = clouds.get("spawn_size")
		if size_value is Vector3:
			cloud_field = size_value
	if moon_node != null and moon_node.has_method("configure_for_maze"):
		moon_node.configure_for_maze(
			maze_node.maze_width,
			maze_node.maze_height,
			maze_node.cell_size,
			cloud_field
		)
	if clouds != null and clouds.has_method("configure_for_maze"):
		# Solo / editor: start the cloud clock now so shadows match a fresh preview.
		# Multiplayer: keep the shared match clock so peers stay in sync.
		var cloud_clock := start_time_msec
		if Engine.is_editor_hint() or cloud_clock <= 0:
			cloud_clock = Time.get_ticks_msec()
		elif not GameState.is_multiplayer:
			cloud_clock = Time.get_ticks_msec()
		var moon_height := 200.0
		if moon_node is Node3D:
			moon_height = (moon_node as Node3D).position.y
		clouds.configure_for_maze(
			maze_node.maze_width,
			maze_node.maze_height,
			maze_node.cell_size,
			moon_height,
			run_seed,
			cloud_clock
		)


func _snap_player_spawn_slots() -> void:
	var maze_node := get_node_or_null("MazeGenerator")
	var players_node := get_node_or_null("Players")
	if maze_node == null or players_node == null:
		return
	if not maze_node.has_method("get_wall_grid"):
		return

	var slots: Array = []
	for child in players_node.get_children():
		if child is PlayerSpawnSlot:
			var slot := child as PlayerSpawnSlot
			slot.sync_to_maze(maze_node)
			slots.append(slot)

	if maze_node.has_method("rebuild_spawn_zone_preview_from_slots"):
		maze_node.rebuild_spawn_zone_preview_from_slots(slots)


func _refresh_spawn_zone_preview_from_slots() -> void:
	var maze_node := get_node_or_null("MazeGenerator")
	var players_node := get_node_or_null("Players")
	if maze_node == null or players_node == null:
		return
	if not maze_node.has_method("rebuild_spawn_zone_preview_from_slots"):
		return
	var slots: Array = []
	for child in players_node.get_children():
		if child is PlayerSpawnSlot:
			slots.append(child)
	maze_node.rebuild_spawn_zone_preview_from_slots(slots)


func _on_match_snapshot_changed(_snapshot: Dictionary) -> void:
	_apply_match_gameplay_state()


func _apply_match_gameplay_state() -> void:
	if not GameState.is_multiplayer or not _players_spawned:
		return
	var enable := MatchStateManager.is_gameplay_active()
	if enable == _match_subsystems_active:
		return
	_match_subsystems_active = enable
	NetworkManagerScript.set_players_sync_enabled(players_root, enable)
	## Keep match voice / MATCH_FANOUT up for wand STT even between phases.
	## VoIP peer list is refreshed separately; do not tear down the mic here.


func _apply_voice_settings() -> void:
	if voice_validator != null:
		voice_validator.apply_settings_from_manager()


func _configure_local_player(player: CharacterBody3D) -> void:
	_local_player = player
	_wire_spell_system(player)


func _wire_spell_system(player: CharacterBody3D) -> void:
	var loadout: Node = player.get_spell_loadout()
	var casting_session: SpellCastingSession = player.get_casting_session()
	var effect_applier: Node = player.get_effect_applier()

	loadout.configure(spell_registry.get_all_spells())
	_apply_role_starting_spells(loadout)
	game_hud.configure(loadout, casting_session)
	var inventory := player.get_node_or_null("%PlayerInventory")
	if inventory == null:
		inventory = player.get_node_or_null("PlayerInventory")
	if inventory != null and game_hud.has_method("configure_inventory"):
		game_hud.configure_inventory(inventory)
	casting_session.configure(voice_validator, loadout)
	casting_session.add_to_group("casting_session")
	casting_session.state_changed.connect(_on_cast_state_changed)
	casting_session.cast_succeeded.connect(_on_cast_succeeded)
	casting_session.cast_failed.connect(_on_cast_failed)
	casting_session.spell_selected.connect(_on_spell_selected)
	casting_session.tome_teaching_changed.connect(_on_tome_teaching_changed)
	player.configure_interaction(loadout, casting_session, game_hud, effect_applier)


func _apply_role_starting_spells(loadout: Node) -> void:
	var peer_id := 1
	if GameState.is_multiplayer:
		peer_id = multiplayer.get_unique_id()
	var config := GameState.get_character_config_for_peer(peer_id)
	var starting_ids: Array[String] = config.get_starting_spell_ids()
	if loadout.has_method("apply_starting_spells"):
		loadout.apply_starting_spells(starting_ids)
		return
	for spell_id in starting_ids:
		loadout.learn_spell(spell_id, "starting")


func _on_peer_connected(peer_id: int) -> void:
	NetworkManager.spawn_player_for_peer(
		peer_id,
		players_root,
		_configure_local_player
	)
	if _maze_layout_ready and _players_spawned:
		call_deferred("_place_late_player", peer_id)


func _on_quit_to_menu() -> void:
	SettingsManager.stop_mic_test()
	NetworkManager.disconnect_session()
	_leave_match_scene("res://scenes/menu.tscn")


func _on_maze_ready(
	_spawn_position: Vector3,
	_exit_position: Vector3,
	spawn_cell: Vector2i,
	exit_cell: Vector2i
) -> void:
	_maze_spawn_cell = spawn_cell
	_maze_exit_cell = exit_cell
	_maze_layout_ready = true
	_configure_sky_for_maze(GameState.run_seed, GameState.match_start_time_msec)
	_finish_match_layout()


func _finish_match_layout() -> void:
	if not _maze_layout_ready or not _players_spawned:
		return

	var players := _collect_player_bodies()
	if players.is_empty():
		return

	players.sort_custom(func(a: CharacterBody3D, b: CharacterBody3D) -> bool:
		return a.player_index < b.player_index
	)

	_snap_player_spawn_slots()
	_place_players_at_spawn_slots(players)

	if GameState.is_multiplayer:
		NetworkManager.sync_match_phase(MatchState.Phase.ACTIVE)

	delivery_objective.setup(
		maze,
		_maze_spawn_cell,
		Callable(maze, "cell_to_world")
	)
	game_hud.configure_objective(delivery_objective)

	if _discoverables_spawned or discoverable_spawner.run_config == null:
		return

	_discoverables_spawned = true
	var placement_seed: int = DiscoverableSpawnPlan.derive_seed(GameState.run_seed)
	var wall_grid: Array = maze.get_wall_grid()
	var placements: Array[DiscoverablePlacement] = DiscoverableSpawnPlan.compute(
		wall_grid,
		maze.maze_width,
		maze.maze_height,
		_maze_spawn_cell,
		_maze_exit_cell,
		discoverable_spawner.run_config,
		placement_seed
	)
	discoverable_spawner.spawn_from_plan(
		placements,
		Callable(maze, "cell_to_world"),
		wall_grid
	)


func _collect_player_bodies() -> Array[CharacterBody3D]:
	var players: Array[CharacterBody3D] = []
	for child in players_root.get_children():
		if child is CharacterBody3D:
			players.append(child)
	return players


func _place_players_at_spawn_slots(players: Array[CharacterBody3D]) -> void:
	var positions := _compute_spawn_positions(players)
	for player in players:
		_apply_spawn_position(player, positions)


## peer_id -> spawn position. Every peer resolves this identically from authored
## slots plus replicated roles/teams, so no spawn data crosses the network.
func _compute_spawn_positions(players: Array[CharacterBody3D]) -> Dictionary:
	var headmaster_slot: PlayerSpawnSlot = null
	var apprentice_slots: Array[PlayerSpawnSlot] = []
	for child in players_root.get_children():
		if not (child is PlayerSpawnSlot):
			continue
		var slot := child as PlayerSpawnSlot
		if slot.role == PlayerSpawnSlot.Role.HEADMASTER:
			headmaster_slot = slot
		else:
			apprentice_slots.append(slot)
	apprentice_slots.sort_custom(func(a: PlayerSpawnSlot, b: PlayerSpawnSlot) -> bool:
		return a.spawn_slot_index < b.spawn_slot_index
	)

	var positions: Dictionary = {}
	var by_team: Dictionary = {}
	for player in players:
		var peer_id := _peer_id_for_player_node(player)
		if GameState.get_role_for_peer(peer_id) == GameState.PlayerRole.HEADMASTER:
			if headmaster_slot == null:
				push_warning(
					"Match: no headmaster spawn slot — peer %d keeps its scene pose" % peer_id
				)
				continue
			positions[peer_id] = headmaster_slot.get_spawn_world_position()
			continue
		var team_id := GameState.get_team_for_peer(peer_id)
		if not by_team.has(team_id):
			by_team[team_id] = []
		by_team[team_id].append(peer_id)

	for team_id in by_team:
		var mates: Array = by_team[team_id]
		var slot := _apprentice_slot_for_team(apprentice_slots, int(team_id))
		if slot == null:
			push_warning(
				"Match: no apprentice slot for team %d — %d peer(s) keep their scene pose"
				% [int(team_id), mates.size()]
			)
			continue
		var origin := slot.get_spawn_world_position()
		var offsets := PlayerSpawnLayoutScript.teammate_offsets(mates.size())
		for i in mates.size():
			positions[int(mates[i])] = origin + offsets[i]
	return positions


func _apply_spawn_position(player: CharacterBody3D, positions: Dictionary) -> void:
	var peer_id := _peer_id_for_player_node(player)
	if not positions.has(peer_id):
		return
	player.global_position = positions[peer_id]
	player.velocity = Vector3.ZERO
	## Remote voice emits from the body, so match chat gets proximity falloff.
	SteamProximityVoiceHub.set_peer_anchor(peer_id, player)
	TomeDebug.log(
		"Match",
		"spawn peer=%d role=%s team=%d authority=%d pos=%s"
		% [
			peer_id,
			RoleAssignment.role_label(GameState.get_role_for_peer(peer_id)),
			GameState.get_team_for_peer(peer_id),
			player.get_multiplayer_authority(),
			str(player.global_position),
		]
	)


## A peer that arrives after the initial layout would otherwise stay at the scene
## origin, stacked on whoever else spawned there.
func _place_late_player(peer_id: int) -> void:
	var player := players_root.get_node_or_null(str(peer_id)) as CharacterBody3D
	if player == null:
		return
	_apply_spawn_position(player, _compute_spawn_positions(_collect_player_bodies()))


func _apprentice_slot_for_team(
	apprentice_slots: Array[PlayerSpawnSlot],
	team_id: int
) -> PlayerSpawnSlot:
	for slot in apprentice_slots:
		if slot.spawn_slot_index == team_id:
			return slot
	return apprentice_slots[0] if not apprentice_slots.is_empty() else null


func _peer_id_for_player_node(player: Node) -> int:
	if player.name.is_valid_int():
		return int(player.name)
	return 1


func apply_delivery_objective_network(op: int, payload: Variant = null) -> void:
	delivery_objective.apply_network_op(op, payload)


func _get_casting_session() -> SpellCastingSession:
	if _local_player == null:
		return null
	return _local_player.get_casting_session()


func _get_spell_loadout() -> Node:
	if _local_player == null:
		return null
	return _local_player.get_spell_loadout()


func _get_effect_applier() -> Node:
	if _local_player == null:
		return null
	return _local_player.get_effect_applier()


func prepare_spell_cast_wire(
	caster_peer_id: int,
	spell_id: String,
	params: Dictionary
) -> Dictionary:
	var player := players_root.get_node_or_null(str(caster_peer_id)) as CharacterBody3D
	var spell := spell_registry.get_spell(spell_id)
	if spell == null:
		return {}
	var resolved := SpellEffectSyncScript.resolve_network_params(spell, player, params)
	if resolved.is_empty():
		return {}
	return SpellEffectSyncScript.pack_for_network(resolved)


func apply_synced_spell_cast(
	caster_peer_id: int,
	spell_id: String,
	params: Dictionary
) -> void:
	var player := players_root.get_node_or_null(str(caster_peer_id)) as CharacterBody3D
	if player == null:
		TomeDebug.log(
			"Match",
			"synced spell cast skipped: player %d not found" % caster_peer_id
		)
		return
	var spell := spell_registry.get_spell(spell_id)
	if spell == null:
		TomeDebug.log("Match", "synced spell cast skipped: unknown spell '%s'" % spell_id)
		return
	var applier := player.get_effect_applier() as SpellEffectApplier
	if applier == null and _local_player != null:
		applier = _local_player.get_effect_applier() as SpellEffectApplier
	if applier == null:
		TomeDebug.log("Match", "synced spell cast skipped: no effect applier")
		return
	TomeDebug.log(
		"Match",
		"synced spell cast peer=%d spell='%s' effect='%s'"
		% [caster_peer_id, spell_id, spell.effect_id]
	)
	applier.apply_synced_cast(player, spell, params)


func apply_spell_world_event(
	kind: String,
	event: String,
	object_id: String,
	pos_x: float,
	pos_y: float,
	pos_z: float
) -> void:
	if not is_inside_tree():
		return
	SpellWorldSyncScript.apply_event(
		get_tree(),
		kind,
		event,
		object_id,
		Vector3(pos_x, pos_y, pos_z)
	)


func _on_cast_state_changed(state: String, spell: SpellDefinition) -> void:
	var casting_session := _get_casting_session()
	if casting_session == null:
		return
	if state == SpellCastingSession.STATE_IDLE:
		if _learn_confirm_pending or casting_session.is_tome_teaching():
			return
		game_hud.hide_casting()
		return
	if (
		(
			casting_session.is_free_cast()
			or casting_session.is_wand_voice_select()
		)
		and not casting_session.is_tome_teaching()
	):
		return
	game_hud.show_casting_state(
		state,
		spell,
		casting_session.is_tome_teaching(),
		casting_session.is_free_cast() or casting_session.is_wand_voice_select()
	)


func _on_tome_teaching_changed(active: bool, _spell: SpellDefinition) -> void:
	if not active and not _learn_confirm_pending:
		game_hud.hide_casting()


func _on_spell_selected(spell: SpellDefinition) -> void:
	## Voice select arms LMB cast; player also reveals — ensure HUD once.
	if spell != null and game_hud != null and game_hud.has_method("reveal_cast_spell"):
		game_hud.reveal_cast_spell(spell)


func _on_cast_succeeded(
	spell: SpellDefinition,
	mode: String,
	validation: CastValidationResult = null
) -> void:
	var loadout := _get_spell_loadout()
	var casting_session := _get_casting_session()
	var effect_applier := _get_effect_applier()
	if loadout == null or casting_session == null or effect_applier == null:
		return

	TomeDebug.log(
		"Match",
		"cast_succeeded mode=%s spell='%s'"
		% [mode, spell.id if spell != null else ""]
	)
	if validation != null and (
		not validation.heard_text.is_empty() or not validation.incantation_text.is_empty()
	):
		TomeDebug.log("Match", validation.get_speech_match_line())
	if mode == "learn":
		_learn_confirm_pending = true
		loadout.learn_spell(spell.id, "tome")
		_consume_tome_for_spell(spell.id)
		game_hud.reveal_cast_spell(spell)
		game_hud.show_spell_learned(spell, validation)
		await get_tree().create_timer(3.5).timeout
		_learn_confirm_pending = false
		game_hud.hide_casting()
		game_hud.clear_spell_word()
	else:
		game_hud.reveal_cast_spell(spell)
		var params := SpellEffectSyncScript.build_params(spell, _local_player)
		var effect_duration := SpellEffectSyncScript.get_effect_duration_sec(spell, params)
		if spell.effect_id == "fake_wall":
			if _local_player.has_method("_begin_fake_wall_placement"):
				_local_player.call("_begin_fake_wall_placement", spell)
			if casting_session.is_free_cast():
				return
			game_hud.show_cast_success(spell, validation)
			await get_tree().create_timer(1.2).timeout
			game_hud.hide_casting()
			return
		effect_applier.cast_spell(_local_player, spell)
		if (
			spell.id == "clone"
			and not params.is_empty()
			and loadout.has_method("start_cooldown")
		):
			loadout.start_cooldown(spell.id)
		if effect_duration > 0.0:
			game_hud.show_spell_active(spell.id, effect_duration)
		if casting_session.is_free_cast():
			return
		game_hud.show_cast_success(spell, validation)
		await get_tree().create_timer(2.0).timeout
		game_hud.hide_casting()


func _on_cast_failed(
	_spell: SpellDefinition,
	reason: String,
	partial: CastValidationResult
) -> void:
	var casting_session := _get_casting_session()
	if casting_session == null:
		return

	TomeDebug.log(
		"Match",
		"cast_failed spell='%s' reason='%s'"
		% [_spell.id if _spell != null else "", reason]
	)
	if partial != null and (
		not partial.heard_text.is_empty() or not partial.incantation_text.is_empty()
	):
		TomeDebug.log("Match", partial.get_speech_match_line())
	game_hud.clear_spell_word()
	var from_tome: bool = casting_session.is_tome_teaching()
	var open_mic: bool = (
		casting_session.is_free_cast() or casting_session.is_wand_voice_select()
	)
	if not open_mic:
		if partial != null:
			game_hud.show_cast_feedback(partial, from_tome)
		else:
			game_hud.show_cast_feedback(CastValidationResult.fail(reason), from_tome)
	if from_tome:
		return
	if open_mic:
		return
	await get_tree().create_timer(3.0).timeout
	game_hud.hide_casting()


func _consume_tome_for_spell(spell_id: String) -> void:
	for child in discoverable_spawner.get_children():
		if child.has_method("get_spell"):
			var tome_spell: SpellDefinition = child.get_spell()
			if tome_spell != null and tome_spell.id == spell_id:
				if child.has_method("consume_with_vfx"):
					child.consume_with_vfx()
				else:
					child.queue_free()
				return


func _on_exit_reached(player: Node3D) -> void:
	if _game_won:
		return
	if delivery_objective != null and not delivery_objective.is_complete():
		_reset_maze_exit_trigger()
		return
	if GameState.is_multiplayer:
		if not MatchStateManager.allows_gameplay_actions():
			TomeDebug.log("Match", "Exit reached but match is not ACTIVE — ignoring")
			_reset_maze_exit_trigger()
			return
		if player.is_multiplayer_authority():
			NetworkManager.request_match_victory(multiplayer.get_unique_id())
		return
	_trigger_victory()


func _reset_maze_exit_trigger() -> void:
	var maze_node := get_node_or_null("MazeGenerator")
	if maze_node != null and maze_node.has_method("reset_exit_trigger"):
		maze_node.reset_exit_trigger()


func reset_maze_exit_trigger_from_network() -> void:
	_reset_maze_exit_trigger()


func trigger_match_victory(winner_peer_id: int) -> void:
	if _game_won:
		return
	_game_won = true
	if winner_peer_id == multiplayer.get_unique_id():
		GameState.local_player_form = GameState.PlayerForm.HUMAN
	_teardown_match_subsystems()
	_leave_match_scene("res://scenes/victory.tscn")


func _trigger_victory() -> void:
	trigger_match_victory(1)


func _teardown_match_subsystems() -> void:
	if not _match_subsystems_active:
		return
	_match_subsystems_active = false
	NetworkManagerScript.set_players_sync_enabled(players_root, false)
	SteamProximityVoiceHub.set_mode(SteamProximityVoiceHub.Mode.OFF)


func _leave_match_scene(scene_path: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	## Victory (and other non-app screens) still use change_scene.
	if scene_path.ends_with("victory.tscn"):
		get_tree().call_deferred("change_scene_to_file", scene_path)
		return
	var app := get_tree().get_first_node_in_group("game_app")
	if app != null and app.has_method("return_to_main_menu"):
		app.call_deferred("return_to_main_menu")
	else:
		get_tree().call_deferred("change_scene_to_file", "res://scenes/game_app.tscn")
