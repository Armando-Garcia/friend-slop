@tool
extends Node

## Root app: exclusive MainMenu / Lobby / Match states + shared VoiceEngine.
## Per-state VoiceSession nodes configure how voice works for that player group.
## In the editor, selecting a state (or its children) previews that state's UI/world.

signal state_changed(state: int)

enum AppState { MAIN_MENU, LOBBY, MATCH }

const MATCH_SCENE := preload("res://scenes/match.tscn")
const SteamMultiplayerPeerAdapterScript := preload(
	"res://scripts/network/steam_multiplayer_peer_adapter.gd"
)
const MicCaptureBrokerScript := preload("res://scripts/voice/mic_capture_broker.gd")
const VOICE_PEER_RETRY_SEC := 0.5

@export var debug_voice: bool = false

var state: AppState = AppState.MAIN_MENU
var _match_instance: Node = null
var _local_transmit_muted: bool = false
var _editor_preview_state: AppState = AppState.MAIN_MENU
var _voice_peer_retry_queued: bool = false
## peer_id -> true while that peer has no Steam ID mapping (log once per gap).
var _unmapped_peers: Dictionary = {}

@onready var mic_broker: Node = $MicCaptureBroker
@onready var voice_engine: Node = $VoiceEngine
@onready var main_menu: Node = $States/MainMenu
@onready var lobby: Node = $States/Lobby
@onready var match_state: Node = $States/Match
@onready var lobby_voice: Node = $States/Lobby/VoiceSession
@onready var match_voice: Node = $States/Match/VoiceSession
@onready var lobby_panel: LobbyPanel = $States/Lobby/LobbyPanel
@onready var menu_screen: Control = $States/MainMenu
@onready var settings_panel: SettingsPanel = $SettingsPanel


func _enter_tree() -> void:
	## Authoring keeps Match/Match in the scene for editor preview. Strip it before
	## child _ready so play does not boot STT/match systems on the main menu.
	if Engine.is_editor_hint():
		return
	var world := get_node_or_null("States/Match/Match")
	if world != null:
		world.free()


func _ready() -> void:
	if Engine.is_editor_hint():
		_editor_setup_preview()
		return

	add_to_group("game_app")
	_bind_voice_sessions()
	_wire_menu()
	_wire_lobby()
	if settings_panel != null:
		settings_panel.closed.connect(_on_settings_closed)
	if NetworkManager.peer_connected.is_connected(_on_peer_changed):
		NetworkManager.peer_connected.disconnect(_on_peer_changed)
	NetworkManager.peer_connected.connect(_on_peer_changed)
	if NetworkManager.peer_disconnected.is_connected(_on_peer_changed):
		NetworkManager.peer_disconnected.disconnect(_on_peer_changed)
	NetworkManager.peer_disconnected.connect(_on_peer_changed)
	if NetworkManager.lobby_roster_changed.is_connected(_on_peer_changed):
		NetworkManager.lobby_roster_changed.disconnect(_on_peer_changed)
	NetworkManager.lobby_roster_changed.connect(_on_peer_changed)
	if SteamService.lobby_member_joined.is_connected(_on_peer_changed):
		SteamService.lobby_member_joined.disconnect(_on_peer_changed)
	SteamService.lobby_member_joined.connect(_on_peer_changed)
	set_state(AppState.MAIN_MENU)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_editor_sync_preview_from_selection()


func get_active_voice_session() -> Node:
	match state:
		AppState.LOBBY:
			return lobby_voice
		AppState.MATCH:
			return match_voice
		_:
			return null


func set_state(next: AppState) -> void:
	_stop_all_voice()
	_set_state_process(main_menu, false)
	_set_state_process(lobby, false)
	_set_state_process(match_state, false)

	if state == AppState.MATCH and next != AppState.MATCH:
		_unload_match()

	state = next
	match next:
		AppState.MAIN_MENU:
			_set_state_process(main_menu, true)
			_show_menu_chrome(true)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		AppState.LOBBY:
			_set_state_process(lobby, true)
			_show_menu_chrome(false)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		AppState.MATCH:
			_set_state_process(match_state, true)
			_show_menu_chrome(false)
			_load_match()
			## Wand STT shares MicCaptureBroker — enable match fan-out as soon as
			## we enter match so solo casts are not stuck on CHAT_ONLY.
			if mic_broker != null and mic_broker.has_method("set_fanout_policy"):
				mic_broker.call(
					"set_fanout_policy",
					MicCaptureBrokerScript.FanoutPolicy.MATCH_FANOUT
				)
	state_changed.emit(state)
	TomeDebug.log("GameApp", "State → %s" % _state_label(state))


func open_lobby_host() -> void:
	set_state(AppState.LOBBY)
	lobby_panel.open_host()


func open_lobby_join() -> void:
	set_state(AppState.LOBBY)
	lobby_panel.open_join()


func open_settings(from_lobby: bool = false) -> void:
	if from_lobby:
		lobby_panel.visible = false
	else:
		_show_menu_chrome(false)
	settings_panel.set_meta("return_to_lobby", from_lobby)
	settings_panel.open()


func get_match_root() -> Node:
	return _match_instance


func enter_match() -> void:
	if lobby_panel != null:
		lobby_panel.visible = false
	set_state(AppState.MATCH)


func return_to_main_menu() -> void:
	set_state(AppState.MAIN_MENU)


func is_voice_active() -> bool:
	var session := get_active_voice_session()
	return session != null and bool(session.call("is_session_active"))


func is_lobby_voice_active() -> bool:
	return state == AppState.LOBBY and is_voice_active()


func set_lobby_voice_enabled(enabled: bool) -> void:
	if state != AppState.LOBBY:
		return
	if enabled:
		_local_transmit_muted = SettingsManager.mic_muted
		if mic_broker != null:
			mic_broker.set("debug_logging", debug_voice)
		lobby_voice.set("debug_logging", debug_voice)
		lobby_voice.call("start_session")
		lobby_voice.call("set_transmit_muted", _local_transmit_muted)
		## Roster / Steam ID mapping can land a frame after join; retry peers.
		_schedule_voice_peer_refresh()
	else:
		lobby_voice.call("stop_session")


func set_match_voice_enabled(enabled: bool) -> void:
	if state != AppState.MATCH:
		return
	if enabled:
		_local_transmit_muted = SettingsManager.mic_muted
		if mic_broker != null:
			mic_broker.set("debug_logging", debug_voice)
		match_voice.set("debug_logging", debug_voice)
		match_voice.call("start_session")
		match_voice.call("set_transmit_muted", _local_transmit_muted)
		_schedule_voice_peer_refresh()
	else:
		match_voice.call("stop_session")


func stop_voice() -> void:
	_stop_all_voice()


func refresh_voice_peers() -> void:
	var session := get_active_voice_session()
	if session != null:
		session.call("refresh_peers")


func _schedule_voice_peer_refresh() -> void:
	refresh_voice_peers()
	call_deferred("refresh_voice_peers")
	if _voice_peer_retry_queued or not is_inside_tree():
		return
	_voice_peer_retry_queued = true
	get_tree().create_timer(VOICE_PEER_RETRY_SEC).timeout.connect(
		_on_voice_peer_retry_timeout,
		CONNECT_ONE_SHOT
	)


func _on_voice_peer_retry_timeout() -> void:
	_voice_peer_retry_queued = false
	refresh_voice_peers()


func resolve_steam_id_for_peer(peer_id: int) -> int:
	if peer_id <= 0:
		return 0
	var tree := get_tree()
	if tree == null:
		return 0
	var mp := tree.get_multiplayer()
	if mp != null and peer_id == int(mp.get_unique_id()):
		return SteamService.get_steam_id()
	if mp == null:
		return 0
	var steam_id := SteamMultiplayerPeerAdapterScript.get_steam_id_for_peer(
		mp.multiplayer_peer, peer_id
	)
	## Without this mapping the peer shows as "Player N" and its voice indicator
	## can never light, whatever audio arrives. Say so once instead of silently 0.
	if steam_id == 0:
		if not _unmapped_peers.has(peer_id):
			_unmapped_peers[peer_id] = true
			TomeDebug.log(
				"GameApp",
				"peer %d has no Steam ID mapping — remote voice indicator stays dark"
				% peer_id
			)
	else:
		_unmapped_peers.erase(peer_id)
	return steam_id


func is_peer_speaking(peer_id: int, timeout_ms: int = 350) -> bool:
	var steam_id := resolve_steam_id_for_peer(peer_id)
	if steam_id == 0:
		return false
	var session := get_active_voice_session()
	if session == null:
		return false
	if steam_id == SteamService.get_steam_id():
		if _local_transmit_muted:
			return false
		return bool(session.call("is_local_speaking", timeout_ms))
	return bool(session.call("is_remote_speaking", steam_id, timeout_ms))


func is_peer_muted(peer_id: int) -> bool:
	var steam_id := resolve_steam_id_for_peer(peer_id)
	if steam_id == 0:
		return false
	if steam_id == SteamService.get_steam_id():
		return _local_transmit_muted
	var session := get_active_voice_session()
	if session == null:
		return false
	return bool(session.call("is_peer_muted", steam_id))


func set_peer_muted(peer_id: int, muted: bool) -> void:
	var steam_id := resolve_steam_id_for_peer(peer_id)
	if steam_id == 0:
		return
	var session := get_active_voice_session()
	if steam_id == SteamService.get_steam_id():
		_local_transmit_muted = muted
		if SettingsManager.mic_muted != muted:
			SettingsManager.mic_muted = muted
			SettingsManager.save_settings()
		if session != null:
			session.call("set_transmit_muted", muted)
		return
	if session != null:
		session.call("set_peer_muted", steam_id, muted)


func get_peer_volume(peer_id: int) -> float:
	var steam_id := resolve_steam_id_for_peer(peer_id)
	if steam_id == 0 or steam_id == SteamService.get_steam_id():
		return 1.0
	var session := get_active_voice_session()
	if session == null:
		return 1.0
	return float(session.call("get_peer_volume", steam_id))


func set_peer_volume(peer_id: int, linear: float) -> void:
	var steam_id := resolve_steam_id_for_peer(peer_id)
	if steam_id == 0 or steam_id == SteamService.get_steam_id():
		return
	var session := get_active_voice_session()
	if session != null:
		session.call("set_peer_volume", steam_id, linear)


func _bind_voice_sessions() -> void:
	if mic_broker != null:
		mic_broker.add_to_group("mic_capture_broker")
		mic_broker.set("debug_logging", debug_voice)
	if lobby_voice != null:
		lobby_voice.call("bind_engine", voice_engine)
		lobby_voice.set("debug_logging", debug_voice)
	if match_voice != null:
		match_voice.call("bind_engine", voice_engine)
		match_voice.set("debug_logging", debug_voice)


func _wire_menu() -> void:
	if menu_screen == null:
		return
	if menu_screen.has_signal("host_pressed"):
		menu_screen.host_pressed.connect(open_lobby_host)
	if menu_screen.has_signal("join_pressed"):
		menu_screen.join_pressed.connect(open_lobby_join)
	if menu_screen.has_signal("settings_pressed"):
		menu_screen.settings_pressed.connect(func() -> void: open_settings(false))


func _wire_lobby() -> void:
	if lobby_panel == null:
		return
	lobby_panel.closed.connect(_on_lobby_closed)
	lobby_panel.settings_requested.connect(func() -> void: open_settings(true))


func _on_lobby_closed() -> void:
	set_state(AppState.MAIN_MENU)


func _on_peer_changed(_arg = null) -> void:
	_schedule_voice_peer_refresh()


func _on_settings_closed() -> void:
	var back_to_lobby := bool(settings_panel.get_meta("return_to_lobby", false))
	settings_panel.remove_meta("return_to_lobby")
	if back_to_lobby and state == AppState.LOBBY:
		lobby_panel.visible = true
		return
	if state == AppState.MAIN_MENU:
		_show_menu_chrome(true)


func _show_menu_chrome(show_buttons: bool) -> void:
	if menu_screen != null and menu_screen.has_method("set_menu_visible"):
		menu_screen.call("set_menu_visible", show_buttons)


func _set_state_process(node: Node, enabled: bool) -> void:
	if node == null:
		return
	if node is CanvasItem or node is Node3D:
		(node as Node).set("visible", enabled)
	node.process_mode = (
		Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	)


func _load_match() -> void:
	if _match_instance != null and is_instance_valid(_match_instance):
		return
	## Drop the editor-authored Match world (if present) so play always starts clean.
	var existing := match_state.get_node_or_null("Match")
	if existing != null:
		match_state.remove_child(existing)
		existing.free()
	_match_instance = MATCH_SCENE.instantiate()
	_match_instance.name = "Match"
	match_state.add_child(_match_instance)


func _unload_match() -> void:
	if _match_instance != null and is_instance_valid(_match_instance):
		_match_instance.queue_free()
	_match_instance = null


func _stop_all_voice() -> void:
	if lobby_voice != null:
		lobby_voice.call("stop_session")
	if match_voice != null:
		match_voice.call("stop_session")


func _state_label(value: AppState) -> String:
	match value:
		AppState.MAIN_MENU:
			return "main_menu"
		AppState.LOBBY:
			return "lobby"
		AppState.MATCH:
			return "match"
		_:
			return "?"


func _editor_setup_preview() -> void:
	set_process(true)
	_editor_hide_app_settings()
	_editor_apply_preview_state(AppState.MAIN_MENU)


func _editor_hide_app_settings() -> void:
	var panel := get_node_or_null("SettingsPanel") as CanvasItem
	if panel != null:
		panel.visible = false


func _editor_sync_preview_from_selection() -> void:
	var editor_interface := Engine.get_singleton("EditorInterface")
	if editor_interface == null:
		return
	var selection: Object = editor_interface.get_selection()
	if selection == null:
		return
	var selected: Array = selection.get_selected_nodes()
	if selected.is_empty():
		return
	var node: Node = selected[0] as Node
	if node == null:
		return

	var lobby_node := get_node_or_null("States/Lobby")
	var match_node := get_node_or_null("States/Match")
	var menu_node := get_node_or_null("States/MainMenu")
	var settings_node := get_node_or_null("SettingsPanel")

	var show_settings := false
	var next := _editor_preview_state
	var cursor: Node = node
	while cursor != null and cursor != self:
		if settings_node != null and (cursor == settings_node or settings_node.is_ancestor_of(cursor)):
			## Only the GameApp SettingsPanel — not PauseMenu's copy under Main.
			if not _editor_is_under_match_world(cursor):
				show_settings = true
				next = AppState.MAIN_MENU
				break
		if lobby_node != null and (cursor == lobby_node or lobby_node.is_ancestor_of(cursor)):
			next = AppState.LOBBY
			break
		if match_node != null and (cursor == match_node or match_node.is_ancestor_of(cursor)):
			next = AppState.MATCH
			break
		if menu_node != null and (cursor == menu_node or menu_node.is_ancestor_of(cursor)):
			next = AppState.MAIN_MENU
			break
		cursor = cursor.get_parent()

	if next != _editor_preview_state:
		_editor_apply_preview_state(next)
	if settings_node is CanvasItem:
		(settings_node as CanvasItem).visible = show_settings


func _editor_is_under_match_world(node: Node) -> bool:
	var world := get_node_or_null("States/Match/Match")
	if world == null:
		return false
	return node == world or world.is_ancestor_of(node)


func _editor_apply_preview_state(next: AppState) -> void:
	_editor_preview_state = next
	var menu_node := get_node_or_null("States/MainMenu")
	var lobby_node := get_node_or_null("States/Lobby")
	var match_node := get_node_or_null("States/Match")
	var lobby_ui := get_node_or_null("States/Lobby/LobbyPanel") as CanvasItem

	_set_state_process(menu_node, next == AppState.MAIN_MENU)
	_set_state_process(lobby_node, next == AppState.LOBBY)
	_set_state_process(match_node, next == AppState.MATCH)
	if lobby_ui != null:
		lobby_ui.visible = next == AppState.LOBBY

	_editor_set_match_preview_visible(next == AppState.MATCH)
	_editor_hide_app_settings()

	if next == AppState.MATCH:
		var match_preview := get_node_or_null("States/Match/Match")
		if match_preview != null and match_preview.has_method("editor_refresh_environment_preview"):
			match_preview.call_deferred("editor_refresh_environment_preview")


func _editor_set_match_preview_visible(enabled: bool) -> void:
	## Match is a plain Node (no visible). Hide the 3D world and especially CanvasLayers
	## (PauseMenu embeds SettingsPanel and draws above MainMenu/Lobby in the 2D editor).
	var world := get_node_or_null("States/Match/Match") as Node3D
	if world == null:
		return
	world.visible = enabled
	for child in world.get_children():
		if child is CanvasLayer:
			## Keep pause/settings overlays off while editing; HUD only in Match preview.
			if child.name == "PauseMenu":
				(child as CanvasLayer).visible = false
			else:
				(child as CanvasLayer).visible = enabled
