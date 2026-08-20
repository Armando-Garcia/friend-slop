extends Node

## Session lifecycle for online games. Transport: Steam P2P.

signal status_changed(message: String)
signal connection_failed(message: String)
signal became_host(room_code: String)
signal joined_host
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal lobby_roster_changed
signal lobby_roles_changed
signal lobby_character_configs_changed
signal session_ended(reason: String)
signal steam_lobby_invite_received(lobby_id: int)
signal players_spawned

const APPRENTICE_SCENE := preload("res://scenes/characters/apprentice.tscn")
const HEADMASTER_SCENE := preload("res://scenes/characters/headmaster.tscn")
const DEFAULT_HORROR_CONFIG := preload("res://resources/match/default_horror_config.tres")

const SteamTransportScript := preload("res://scripts/network/steam_transport.gd")
const SpellEffectSyncScript := preload("res://scripts/spells/spell_effect_sync.gd")
const GameWorldScript := preload("res://scripts/game_world.gd")
const DroppedBroomScript := preload("res://scripts/headmaster/dropped_broom.gd")

var transport: MultiplayerTransport
var is_session_active: bool = false
var lobby: LobbyMatchState = LobbyMatchState.new()

var _transport_ready: bool = false


func _ready() -> void:
	_configure_transport()
	transport.status_changed.connect(_forward_transport_status)
	_transport_ready = true

	if SteamService.lobby_invite_received.is_connected(_on_steam_lobby_invite_received):
		SteamService.lobby_invite_received.disconnect(_on_steam_lobby_invite_received)
	SteamService.lobby_invite_received.connect(_on_steam_lobby_invite_received)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_host() -> bool:
	return is_online() and multiplayer.is_server()


func get_room_code() -> String:
	return transport.get_room_code()


func get_player_index_for_peer(peer_id: int) -> int:
	var index := get_lobby_peer_ids().find(peer_id)
	return index if index >= 0 else 0


static func compute_player_index_for_peers(peer_id: int, connected_peers: Array) -> int:
	var ids: Array[int] = [1]
	for connected_id in connected_peers:
		ids.append(int(connected_id))
	ids.sort()
	return ids.find(peer_id)


static func collect_lobby_peer_ids(unique_peer_id: int, connected_peers: Array) -> Array[int]:
	var ids: Dictionary = {1: true}
	ids[unique_peer_id] = true
	for peer_id in connected_peers:
		ids[int(peer_id)] = true
	var result: Array[int] = []
	for id in ids.keys():
		result.append(int(id))
	result.sort()
	return result


static func format_lobby_player_label(
	peer_id: int,
	local_peer_id: int,
	connected_peers: Array
) -> String:
	var slot := compute_player_index_for_peers(peer_id, connected_peers) + 1
	var label := "Host" if peer_id == 1 else "Player %d" % slot
	if peer_id == local_peer_id:
		return "%s (You)" % label
	return label


func get_lobby_peer_ids() -> Array[int]:
	if not is_online():
		return []
	return collect_lobby_peer_ids(multiplayer.get_unique_id(), multiplayer.get_peers())


func get_lobby_player_label(peer_id: int) -> String:
	var steam_name := transport.get_player_display_name(peer_id)
	var suffix := " (You)" if peer_id == multiplayer.get_unique_id() else ""
	var label := ""
	if not steam_name.is_empty():
		if peer_id == 1:
			label = "Host — %s%s" % [steam_name, suffix]
		else:
			label = "%s%s" % [steam_name, suffix]
	else:
		label = format_lobby_player_label(
			peer_id,
			multiplayer.get_unique_id(),
			multiplayer.get_peers()
		)
	return label


func request_lobby_role(role: int) -> void:
	if not is_online():
		return
	if is_host():
		_apply_lobby_role(multiplayer.get_unique_id(), role)
	else:
		_request_lobby_role.rpc_id(1, role)


func request_character_config(config_data: Dictionary) -> void:
	if not is_online():
		return
	if is_host():
		_apply_character_config(multiplayer.get_unique_id(), config_data)
	else:
		_request_character_config.rpc_id(1, config_data)


func host_session(options: Dictionary = {}) -> Error:
	if not _transport_ready:
		return ERR_UNCONFIGURED
	disconnect_session()

	@warning_ignore("redundant_await")
	var err: Error = await transport.host(options)
	if err != OK:
		# Solo / offline preview: local OfflineMultiplayerPeer lobby (no Steam required).
		err = _host_offline_local_session()
		if err != OK:
			connection_failed.emit("Hosting failed.")
			return err
		return OK

	is_session_active = true
	lobby.reset()
	lobby.set_default_roles([1])
	_broadcast_lobby_state()
	became_host.emit(get_room_code())
	_notify_lobby_roster_changed()
	return OK


func _host_offline_local_session() -> Error:
	# One-player lobby without Steam — same start_game path as multiplayer.
	disconnect_session()
	var peer := OfflineMultiplayerPeer.new()
	multiplayer.multiplayer_peer = peer
	is_session_active = true
	lobby.reset()
	lobby.set_default_roles([1])
	lobby.apply_role(1, SettingsManager.dev_solo_role)
	_broadcast_lobby_state()
	became_host.emit("local")
	_notify_lobby_roster_changed()
	status_changed.emit("Local lobby ready. Start alone, or host online to invite friends.")
	return OK


func join_session(room_code: String, options: Dictionary = {}) -> Error:
	if not _transport_ready:
		return ERR_UNCONFIGURED
	disconnect_session()

	var join_options := options.duplicate()
	join_options["room_code"] = room_code

	@warning_ignore("redundant_await")
	var err: Error = await transport.join(join_options)
	if err != OK:
		connection_failed.emit("Join failed.")
		return err

	is_session_active = true
	joined_host.emit()
	_notify_lobby_roster_changed()
	return OK


func invite_friends() -> void:
	transport.invite_to_session()


func start_game() -> void:
	if not is_host():
		return
	_sync_steam_lobby_peers()
	_ensure_lobby_roles_for_peers()
	var peer_ids := get_lobby_peer_ids()
	if not lobby.can_start(peer_ids):
		status_changed.emit(lobby.get_start_block_reason(peer_ids))
		return
	var run_seed := randi()
	var roles_payload := _pack_roles_for_current_peers()
	var configs_payload := _pack_character_configs_for_current_peers()
	var match_snapshot := MatchStateSnapshot.pack_initial(DEFAULT_HORROR_CONFIG)
	TomeDebug.log(
		"NetworkManager",
		"Starting game seed=%s roles=%s configs=%s remote_peers=%s"
		% [run_seed, roles_payload, configs_payload, multiplayer.get_peers()]
	)
	_rpc_start_game.rpc(run_seed, roles_payload, configs_payload, match_snapshot)


func disconnect_session() -> void:
	is_session_active = false
	lobby.reset()
	MatchStateManager.reset()
	TrailRegistry.reset()
	# Autoload lookup needs an active tree (unit tests instantiate this off-tree).
	if is_inside_tree():
		SteamProximityVoiceHub.stop_session()
	if transport != null:
		transport.disconnect_session()


func spawn_players(
	players_root: Node3D,
	configure_local_player: Callable
) -> void:
	_clear_player_nodes(players_root)

	if not GameState.is_multiplayer:
		var solo_player := _instantiate_player_for_peer(1)
		solo_player.name = "Player"
		players_root.add_child(solo_player)
		solo_player.initialize_player(0)
		configure_local_player.call(solo_player)
		players_spawned.emit()
		return

	call_deferred("_spawn_multiplayer_players", players_root, configure_local_player)


func _clear_player_nodes(players_root: Node3D) -> void:
	## Keep PlayerSpawnSlot roster markers; only remove live character instances.
	var to_free: Array[Node] = []
	for child in players_root.get_children():
		if child is PlayerSpawnSlot:
			continue
		to_free.append(child)
	for child in to_free:
		set_player_sync_enabled(child, false)
		players_root.remove_child(child)
		child.queue_free()


func _spawn_multiplayer_players(
	players_root: Node3D,
	configure_local_player: Callable
) -> void:
	for peer_id in get_lobby_peer_ids():
		spawn_player_for_peer(peer_id, players_root, configure_local_player)
	players_spawned.emit()


func spawn_player_for_peer(
	peer_id: int,
	players_root: Node3D,
	configure_local_player: Callable
) -> void:
	if players_root.get_node_or_null(str(peer_id)) != null:
		return

	var player := _instantiate_player_for_peer(peer_id)
	player.name = str(peer_id)
	# Authority must be set before enter-tree: PlayableCharacter._ready() decides
	# camera ownership from is_multiplayer_authority(), and MultiplayerSynchronizer
	# registers against the authority it sees when it enters the tree. Assigning it
	# afterwards let every peer claim the first-person view of every body.
	player.set_multiplayer_authority(peer_id)
	players_root.add_child(player, true)
	player.initialize_player(get_player_index_for_peer(peer_id))
	var is_local := peer_id == multiplayer.get_unique_id()
	TomeDebug.log(
		"NetworkManager",
		"spawned peer=%d role=%s authority=%d local=%s"
		% [
			peer_id,
			RoleAssignment.role_label(GameState.get_role_for_peer(peer_id)),
			player.get_multiplayer_authority(),
			is_local,
		]
	)
	if is_local:
		configure_local_player.call(player)


@rpc("authority", "call_local", "reliable")
func _rpc_start_game(
	run_seed: int,
	roles: Dictionary,
	character_configs: Dictionary,
	match_snapshot: Dictionary
) -> void:
	TomeDebug.log(
		"NetworkManager",
		"Start game RPC received (peer_id=%s, seed=%s)"
		% [multiplayer.get_unique_id(), run_seed]
	)
	# Every peer (host + clients) must drop lobby chat before loading the match.
	SteamProximityVoiceHub.set_mode(SteamProximityVoiceHub.Mode.OFF)
	MatchStateManager.reset()
	GameState.prepare_match(run_seed, roles, character_configs)
	## Synchronize the deterministic clock used by clouds and other time-driven effects.
	GameState.match_start_time_msec = Time.get_ticks_msec()
	if not match_snapshot.is_empty():
		MatchStateManager.apply_snapshot(match_snapshot)
	MatchStateManager.log_summary()
	var app := get_tree().get_first_node_in_group("game_app")
	if app != null and app.has_method("enter_match"):
		app.call("enter_match")
	else:
		get_tree().change_scene_to_file("res://scenes/match.tscn")


func sync_match_phase(next: int) -> void:
	if not is_host():
		return
	var snapshot := MatchStateManager.snapshot
	if snapshot.is_empty():
		return
	var state := MatchState.from_snapshot(snapshot)
	if state.transition_to(next as MatchState.Phase) != OK:
		return
	_rpc_sync_match_snapshot.rpc(MatchStateSnapshot.pack(state))


@rpc("authority", "call_local", "reliable")
func _rpc_sync_match_snapshot(data: Dictionary) -> void:
	MatchStateManager.apply_snapshot(data)


@rpc("authority", "call_local", "reliable")
func _sync_lobby_roles(roles: Dictionary) -> void:
	lobby.roles = LobbyMatchState.normalize_roles(roles)
	lobby_roles_changed.emit()


@rpc("authority", "call_local", "reliable")
func _sync_lobby_character_configs(configs: Dictionary) -> void:
	lobby.character_configs = LobbyMatchState.normalize_character_configs(configs)
	lobby_character_configs_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _request_lobby_role(role: int) -> void:
	if not multiplayer.is_server():
		return
	_apply_lobby_role(multiplayer.get_remote_sender_id(), role)


@rpc("any_peer", "call_remote", "reliable")
func _request_character_config(config_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_apply_character_config(multiplayer.get_remote_sender_id(), config_data)


@rpc("any_peer", "call_remote", "reliable")
func request_spell_cast(spell_id: String, params: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	broadcast_spell_cast(multiplayer.get_remote_sender_id(), spell_id, params)


func broadcast_spell_cast(caster_peer_id: int, spell_id: String, params: Dictionary) -> void:
	if not GameState.is_multiplayer or not MatchStateManager.allows_gameplay_actions():
		return
	if multiplayer.is_server():
		var wire_params := _prepare_spell_cast_wire(caster_peer_id, spell_id, params)
		if wire_params.is_empty():
			return
		_execute_spell_cast.rpc(caster_peer_id, spell_id, wire_params)
	else:
		request_spell_cast.rpc_id(1, spell_id, params)


func _prepare_spell_cast_wire(
	caster_peer_id: int,
	spell_id: String,
	params: Dictionary
) -> Dictionary:
	var main: Node = GameWorldScript.find_match_root(get_tree())
	if main != null and main.has_method("prepare_spell_cast_wire"):
		return main.prepare_spell_cast_wire(caster_peer_id, spell_id, params)
	return SpellEffectSyncScript.pack_for_network(SpellEffectSyncScript.normalize_params(params))


@rpc("authority", "call_local", "reliable")
func _execute_spell_cast(caster_peer_id: int, spell_id: String, params: Dictionary) -> void:
	_forward_to_main("apply_synced_spell_cast", [caster_peer_id, spell_id, params])


@rpc("any_peer", "call_remote", "reliable")
func _request_spell_world_event(
	kind: String,
	event: String,
	object_id: String,
	pos_x: float,
	pos_y: float,
	pos_z: float
) -> void:
	if not multiplayer.is_server() or not MatchStateManager.allows_gameplay_actions():
		return
	## Host has not applied this event yet (client detected it).
	_forward_to_main(
		"apply_spell_world_event",
		[kind, event, object_id, pos_x, pos_y, pos_z]
	)
	_rpc_spell_world_event.rpc(kind, event, object_id, pos_x, pos_y, pos_z)


@rpc("authority", "call_remote", "reliable")
func _rpc_spell_world_event(
	kind: String,
	event: String,
	object_id: String,
	pos_x: float,
	pos_y: float,
	pos_z: float
) -> void:
	## call_remote: sender already applied locally.
	_forward_to_main(
		"apply_spell_world_event",
		[kind, event, object_id, pos_x, pos_y, pos_z]
	)


func request_match_victory(winner_peer_id: int) -> void:
	if not MatchStateManager.allows_gameplay_actions():
		TomeDebug.log("NetworkManager", "Victory blocked — gameplay actions not allowed")
		_forward_to_main("reset_maze_exit_trigger_from_network", [])
		return
	if multiplayer.is_server():
		_rpc_match_victory.rpc(winner_peer_id)
	else:
		_request_match_victory.rpc_id(1, winner_peer_id)


func relay_delivery_objective(op: int, payload: Variant = null) -> void:
	if not MatchStateManager.allows_gameplay_actions():
		return
	match op:
		DeliveryObjectiveSync.NetworkOp.REQUEST_INTERACT:
			_request_delivery_objective_interact.rpc_id(1, int(payload))
		DeliveryObjectiveSync.NetworkOp.BROADCAST_STATE:
			if not multiplayer.is_server():
				return
			_rpc_delivery_objective_state.rpc(payload as Dictionary)
		DeliveryObjectiveSync.NetworkOp.BROADCAST_PING:
			if not multiplayer.is_server():
				return
			_rpc_delivery_objective_ping.rpc()


@rpc("any_peer", "call_remote", "reliable")
func _request_delivery_objective_interact(action: int) -> void:
	if not multiplayer.is_server():
		return
	var actor_peer_id := multiplayer.get_remote_sender_id()
	_forward_to_main(
		"apply_delivery_objective_network",
		[DeliveryObjectiveSync.NetworkOp.REQUEST_INTERACT, [actor_peer_id, action]]
	)


@rpc("authority", "call_local", "reliable")
func _rpc_delivery_objective_state(data: Dictionary) -> void:
	_forward_to_main(
		"apply_delivery_objective_network",
		[DeliveryObjectiveSync.NetworkOp.BROADCAST_STATE, data]
	)


@rpc("authority", "call_local", "unreliable")
func _rpc_delivery_objective_ping() -> void:
	_forward_to_main(
		"apply_delivery_objective_network",
		[DeliveryObjectiveSync.NetworkOp.BROADCAST_PING, null]
	)


@rpc("any_peer", "call_remote", "reliable")
func _request_match_victory(winner_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_rpc_match_victory.rpc(winner_peer_id)


@rpc("authority", "call_local", "reliable")
func _rpc_match_victory(winner_peer_id: int) -> void:
	_forward_to_main("trigger_match_victory", [winner_peer_id])


@rpc("any_peer", "call_remote", "reliable")
func _request_broom_drop(
	spawn_id: String,
	pos_x: float,
	pos_y: float,
	pos_z: float,
	vel_x: float,
	vel_y: float,
	vel_z: float
) -> void:
	if not multiplayer.is_server() or not MatchStateManager.allows_gameplay_actions():
		return
	_rpc_broom_drop.rpc(spawn_id, pos_x, pos_y, pos_z, vel_x, vel_y, vel_z)


@rpc("authority", "call_local", "reliable")
func _rpc_broom_drop(
	spawn_id: String,
	pos_x: float,
	pos_y: float,
	pos_z: float,
	vel_x: float,
	vel_y: float,
	vel_z: float
) -> void:
	DroppedBroomScript.spawn_local(
		spawn_id, Vector3(pos_x, pos_y, pos_z), Vector3(vel_x, vel_y, vel_z)
	)


@rpc("any_peer", "call_remote", "reliable")
func _request_broom_pickup(spawn_id: String, peer_id: int) -> void:
	if not multiplayer.is_server() or not MatchStateManager.allows_gameplay_actions():
		return
	_rpc_broom_pickup.rpc(spawn_id, peer_id)


@rpc("authority", "call_local", "reliable")
func _rpc_broom_pickup(spawn_id: String, peer_id: int) -> void:
	DroppedBroomScript.apply_pickup(get_tree(), spawn_id, peer_id)


@rpc("any_peer", "call_remote", "unreliable")
func _submit_trail_sample(seq: int, x: float, z: float) -> void:
	if not multiplayer.is_server() or not MatchStateManager.allows_gameplay_actions():
		return
	TrailRegistry.host_accept_sample(multiplayer.get_remote_sender_id(), seq, x, z)


@rpc("authority", "call_local", "unreliable")
func _broadcast_trail_sample(peer_id: int, seq: int, x: float, z: float, time_msec: int) -> void:
	if not MatchStateManager.allows_gameplay_actions():
		return
	TrailRegistry.client_apply_sample(peer_id, seq, x, z, time_msec)


func _configure_transport() -> void:
	if not SteamService.is_api_available():
		TomeDebug.log(
			"NetworkManager",
			"GodotSteam unavailable — online play requires the GodotSteam editor or GDExtension."
		)
	transport = SteamTransportScript.new()
	transport.setup(get_tree())


func _forward_transport_status(message: String) -> void:
	status_changed.emit(message)


func _on_steam_lobby_invite_received(lobby_id: int) -> void:
	steam_lobby_invite_received.emit(lobby_id)


func _sync_steam_lobby_peers() -> void:
	if not is_host():
		return
	var lobby_id := SteamService.current_lobby_id
	if lobby_id == 0:
		return
	var count := SteamService.get_lobby_member_count(lobby_id)
	for index in range(count):
		var member_id := SteamService.get_lobby_member_by_index(index, lobby_id)
		if member_id == 0 or member_id == SteamService.get_steam_id():
			continue
		_try_add_steam_peer(member_id)


func _try_add_steam_peer(steam_id: int) -> void:
	if not is_host() or not is_session_active:
		return
	var mp_peer := multiplayer.multiplayer_peer
	if mp_peer == null or not mp_peer.has_method("add_peer"):
		TomeDebug.log("NetworkManager", "Cannot add Steam peer %s — multiplayer peer missing" % steam_id)
		return
	if _steam_peer_has_mapping(mp_peer, steam_id):
		return
	if _steam_peer_already_connected(mp_peer, steam_id):
		return
	var err: Error = mp_peer.call("add_peer", steam_id, 0)
	if err == OK:
		TomeDebug.log("NetworkManager", "add_peer steam_id=%s err=%s" % [steam_id, err])
	elif err == ERR_CANT_CREATE:
		# Client likely has not finished connect_to_lobby yet, or already connected
		# inbound — a duplicate outbound add_peer is invalid. Skip noisy retries.
		pass
	else:
		TomeDebug.log("NetworkManager", "add_peer steam_id=%s err=%s" % [steam_id, err])


func _steam_peer_has_mapping(mp_peer: Object, steam_id: int) -> bool:
	if not mp_peer.has_method("get_peer_id_for_steam_id"):
		return false
	return int(mp_peer.call("get_peer_id_for_steam_id", steam_id)) != 0


func _steam_peer_already_connected(mp_peer: Object, steam_id: int) -> bool:
	if not mp_peer.has_method("get_steam_id_for_peer_id"):
		return false
	for peer_id in multiplayer.get_peers():
		if int(mp_peer.call("get_steam_id_for_peer_id", peer_id)) == steam_id:
			return true
	return false


func _on_peer_connected(peer_id: int) -> void:
	if is_host():
		_ensure_lobby_roles_for_peers()
	peer_connected.emit(peer_id)
	_notify_lobby_roster_changed()


func _on_peer_disconnected(peer_id: int) -> void:
	if is_host() and lobby.remove_peer(peer_id):
		_broadcast_lobby_state()
	peer_disconnected.emit(peer_id)
	_notify_lobby_roster_changed()


func _on_connected_to_server() -> void:
	status_changed.emit("Connected to host.")
	_notify_lobby_roster_changed()


func _on_connection_failed() -> void:
	connection_failed.emit("Connection failed.")


func _on_server_disconnected() -> void:
	disconnect_session()
	session_ended.emit("Host disconnected.")
	status_changed.emit("Host disconnected.")


func _notify_lobby_roster_changed() -> void:
	if is_host():
		_ensure_lobby_roles_for_peers()
	lobby_roster_changed.emit()


func _ensure_lobby_roles_for_peers() -> void:
	if not is_host():
		return
	if lobby.ensure_roles_for_peers(get_lobby_peer_ids()):
		_broadcast_lobby_state()


func _apply_lobby_role(peer_id: int, role: int) -> void:
	lobby.apply_role(peer_id, role)
	_broadcast_lobby_state()


func _apply_character_config(peer_id: int, config_data: Dictionary) -> void:
	lobby.apply_character_config(peer_id, config_data)
	_broadcast_lobby_state()


func _broadcast_lobby_state() -> void:
	_sync_lobby_roles.rpc(lobby.roles.duplicate(true))
	_sync_lobby_character_configs.rpc(lobby.character_configs.duplicate(true))


func _pack_roles_for_current_peers() -> Dictionary:
	return LobbyMatchState.pack_roles_for_peers(lobby.roles, get_lobby_peer_ids())


func _pack_character_configs_for_current_peers() -> Dictionary:
	return LobbyMatchState.pack_character_configs_for_peers(
		lobby.character_configs,
		get_lobby_peer_ids()
	)


static func set_player_sync_enabled(player_root: Node, enabled: bool) -> void:
	var sync := player_root.get_node_or_null("MultiplayerSynchronizer") as MultiplayerSynchronizer
	if sync != null:
		sync.public_visibility = enabled


static func set_players_sync_enabled(players_root: Node3D, enabled: bool) -> void:
	for child in players_root.get_children():
		set_player_sync_enabled(child, enabled)


static func disable_player_sync(player_root: Node) -> void:
	set_player_sync_enabled(player_root, false)


func _forward_to_main(method: StringName, args: Array = []) -> void:
	# Victory / exit-reset must still reach Main even if the match is leaving ACTIVE.
	var always_forward := (
		method == &"trigger_match_victory"
		or method == &"reset_maze_exit_trigger_from_network"
	)
	if not always_forward and not MatchStateManager.allows_gameplay_actions():
		return
	var main: Node = GameWorldScript.find_match_root(get_tree())
	if main != null and main.has_method(method):
		main.callv(method, args)


func _instantiate_player_for_peer(peer_id: int) -> CharacterBody3D:
	var scene := (
		HEADMASTER_SCENE
		if GameState.get_role_for_peer(peer_id) == GameState.PlayerRole.HEADMASTER
		else APPRENTICE_SCENE
	)
	return scene.instantiate() as CharacterBody3D
