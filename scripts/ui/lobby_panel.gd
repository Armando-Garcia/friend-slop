class_name LobbyPanel
extends Control

signal closed
signal start_requested
signal settings_requested

const PlayerVoiceChromeScript := preload("res://scripts/ui/player_voice_chrome.gd")

var _host_mode: bool = false
var _busy: bool = false
var _in_lobby: bool = false
## peer_id -> { "button": Button, "volume": Control }
var _speaker_controls: Dictionary = {}

@onready var _lobby_panel_root: PanelContainer = $Panel
@onready var _title_label: Label = $Panel/MarginContainer/VBox/TitleLabel
@onready var _room_code_host_row: HBoxContainer = (
	$Panel/MarginContainer/VBox/RoomCodeHostRow
)
@onready var _room_code_display: LineEdit = (
	$Panel/MarginContainer/VBox/RoomCodeHostRow/RoomCodeDisplay
)
@onready var _copy_room_code_button: Button = (
	$Panel/MarginContainer/VBox/RoomCodeHostRow/CopyRoomCodeButton
)
@onready var _invite_friends_button: Button = (
	$Panel/MarginContainer/VBox/RoomCodeHostRow/InviteFriendsButton
)
@onready var _room_code_edit: LineEdit = $Panel/MarginContainer/VBox/RoomCodeEdit
@onready var _players_section: VBoxContainer = $Panel/MarginContainer/VBox/PlayersSection
@onready var _player_list_vbox: VBoxContainer = (
	$Panel/MarginContainer/VBox/PlayersSection/PlayerListScroll/PlayerListVBox
)
@onready var _lobby_voice_row: HBoxContainer = $Panel/MarginContainer/VBox/LobbyVoiceRow
@onready var _lobby_voice_switch: CheckButton = (
	$Panel/MarginContainer/VBox/LobbyVoiceRow/LobbyVoiceSwitch
)
@onready var _status_label: Label = $Panel/MarginContainer/VBox/StatusLabel
@onready var _primary_button: Button = $Panel/MarginContainer/VBox/PrimaryButton
@onready var _settings_button: Button = $Panel/MarginContainer/VBox/SettingsButton
@onready var _back_button: Button = $Panel/MarginContainer/VBox/BackButton


func _ready() -> void:
	## Inherit GameApp Lobby state's process_mode (disabled while Match/MainMenu).
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = false
	_primary_button.pressed.connect(_on_primary_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_copy_room_code_button.pressed.connect(_on_copy_room_code_pressed)
	_invite_friends_button.pressed.connect(_on_invite_friends_pressed)
	_lobby_voice_switch.toggled.connect(_on_lobby_voice_toggled)
	NetworkManager.status_changed.connect(_on_network_status)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.became_host.connect(_on_became_host)
	NetworkManager.joined_host.connect(_on_joined_host)
	NetworkManager.lobby_roster_changed.connect(_refresh_player_list)
	NetworkManager.lobby_roles_changed.connect(_refresh_player_list)
	NetworkManager.lobby_character_configs_changed.connect(_refresh_player_list)
	NetworkManager.session_ended.connect(_on_session_ended)
	NetworkManager.steam_lobby_invite_received.connect(_on_steam_lobby_invite_received)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _busy:
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if _in_lobby:
		settings_requested.emit()
	else:
		close_panel()
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _in_lobby or not visible:
		return
	_update_speaker_button_visuals()
	_refresh_lobby_voice_switch()


func open_host() -> void:
	_reset_panel_state()
	_host_mode = true
	visible = true
	_title_label.text = "Host"
	_room_code_host_row.visible = true
	_room_code_edit.visible = false
	_room_code_display.text = ""
	_room_code_display.placeholder_text = "Connecting…"
	_copy_room_code_button.disabled = true
	_invite_friends_button.disabled = true
	_status_label.text = "Starting lobby…"
	_primary_button.text = "Start Game"
	_primary_button.visible = true
	_primary_button.disabled = true
	_back_button.text = "Back"
	_back_button.disabled = false
	_set_busy(true)
	var err := await NetworkManager.host_session({})
	_set_busy(false)
	if err != OK:
		if _status_label.text == "Starting lobby…":
			_status_label.text = _host_failure_message()
		_primary_button.disabled = true
		return
	_enter_lobby_ui()
	_update_start_button_state()


func open_join() -> void:
	_reset_panel_state()
	_host_mode = false
	visible = true
	_title_label.text = "Join"
	_room_code_host_row.visible = false
	_room_code_edit.visible = true
	_room_code_edit.text = ""
	_status_label.text = _join_prompt_message()
	_primary_button.text = "Connect"
	_primary_button.visible = true
	_primary_button.disabled = false
	_back_button.text = "Back"
	_back_button.disabled = false


func close_panel() -> void:
	if _busy:
		return
	_leave_to_menu()


func _on_primary_pressed() -> void:
	if _host_mode:
		if not NetworkManager.is_host():
			_status_label.text = "Host session is not ready."
			return
		var peer_ids := NetworkManager.get_lobby_peer_ids()
		if not NetworkManager.lobby.can_start(peer_ids):
			_status_label.text = NetworkManager.lobby.get_start_block_reason(peer_ids)
			return
		NetworkManager.start_game()
		start_requested.emit()
		return

	if _busy or _in_lobby:
		return
	var room_code := _room_code_edit.text.strip_edges()
	if room_code.is_empty():
		_status_label.text = _join_prompt_message()
		return
	_set_busy(true)
	_status_label.text = "Connecting…"
	var err := await NetworkManager.join_session(room_code, {})
	_set_busy(false)
	if err != OK:
		_status_label.text = "Could not join. Check the lobby ID and try again."
		return
	_enter_lobby_ui()


func _on_back_pressed() -> void:
	close_panel()


func _on_settings_pressed() -> void:
	if not _in_lobby:
		return
	settings_requested.emit()


func _on_network_status(message: String) -> void:
	if not _in_lobby:
		_status_label.text = message


func _on_connection_failed(message: String) -> void:
	_status_label.text = message
	_set_busy(false)
	if _host_mode:
		_primary_button.disabled = true
	else:
		_primary_button.disabled = false


func _on_became_host(room_code: String) -> void:
	_room_code_display.text = room_code
	_room_code_display.placeholder_text = ""
	var is_local := room_code.is_empty() or room_code == "local"
	_copy_room_code_button.disabled = is_local
	_invite_friends_button.disabled = is_local
	if not is_local:
		_room_code_display.grab_focus()
		_room_code_display.select_all()
	_status_label.text = _host_ready_message()


func _on_copy_room_code_pressed() -> void:
	var room_code := _room_code_display.text.strip_edges()
	if room_code.is_empty():
		return
	DisplayServer.clipboard_set(room_code)
	_status_label.text = "Lobby ID copied to clipboard."


func _on_invite_friends_pressed() -> void:
	NetworkManager.invite_friends()
	_status_label.text = "Steam invite overlay opened."


func _on_joined_host() -> void:
	if _in_lobby:
		_refresh_player_list()


func _on_session_ended(reason: String) -> void:
	if not visible or _host_mode:
		return
	_status_label.text = reason
	_leave_to_menu()


func _on_steam_lobby_invite_received(lobby_id: int) -> void:
	if not visible or _host_mode or _in_lobby or _busy:
		return
	_room_code_edit.text = str(lobby_id)
	_status_label.text = "Steam invite received — press Connect to join."
	_primary_button.grab_focus()


func _enter_lobby_ui() -> void:
	_in_lobby = true
	_room_code_edit.visible = false
	_players_section.visible = true
	_settings_button.visible = true
	_lobby_voice_row.visible = _host_mode
	_lobby_voice_switch.disabled = not SteamService.is_ready()
	if _host_mode:
		_room_code_host_row.visible = true
		_primary_button.visible = true
		_update_start_button_state()
		_back_button.text = "Back"
		_status_label.text = _host_ready_message()
	else:
		_room_code_host_row.visible = false
		_primary_button.visible = false
		_back_button.text = "Leave"
		_status_label.text = "Waiting for the host to start…"
	_refresh_player_list()
	_apply_lobby_voice_preference()


func _apply_lobby_voice_preference() -> void:
	if not SteamService.is_ready():
		_set_lobby_voice_enabled(false)
		return
	_set_lobby_voice_enabled(SettingsManager.lobby_voice_default)


func _on_lobby_voice_toggled(enabled: bool) -> void:
	if not _in_lobby or not _host_mode or _lobby_voice_switch.disabled:
		return
	_set_lobby_voice_enabled(enabled)


func _is_lobby_voice_ui_on() -> bool:
	return SteamProximityVoiceHub.get_mode() == SteamProximityVoiceHub.Mode.LOBBY


func _set_lobby_voice_enabled(enabled: bool) -> void:
	if enabled:
		SteamProximityVoiceHub.set_mode(SteamProximityVoiceHub.Mode.LOBBY)
	else:
		SteamProximityVoiceHub.set_mode(SteamProximityVoiceHub.Mode.OFF)
	_refresh_lobby_voice_switch()
	if (
		enabled
		and SteamService.is_ready()
		and not SteamProximityVoiceHub.is_lobby_voice_active()
	):
		SteamProximityVoiceHub.set_mode(SteamProximityVoiceHub.Mode.OFF)
		_refresh_lobby_voice_switch()


func _refresh_lobby_voice_switch() -> void:
	var enabled := _is_lobby_voice_ui_on()
	_lobby_voice_switch.set_pressed_no_signal(enabled)
	_lobby_voice_switch.disabled = not SteamService.is_ready()
	_update_speaker_button_visuals()


func _refresh_player_list() -> void:
	if not _in_lobby or not NetworkManager.is_online():
		return
	_speaker_controls.clear()
	for child in _player_list_vbox.get_children():
		child.queue_free()
	var local_peer_id := multiplayer.get_unique_id()
	for peer_id in NetworkManager.get_lobby_peer_ids():
		_player_list_vbox.add_child(_build_player_row(peer_id, local_peer_id))
	_update_start_button_state()
	_update_speaker_button_visuals()


func _build_player_row(peer_id: int, local_peer_id: int) -> VBoxContainer:
	var row_wrap := VBoxContainer.new()
	row_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_wrap.add_theme_constant_override("separation", 4)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	row_wrap.add_child(row)

	var is_local := peer_id == local_peer_id
	var volume_row: HBoxContainer = null
	if not is_local:
		volume_row = PlayerVoiceChromeScript.make_volume_row(peer_id)
		row_wrap.add_child(volume_row)

	var speaker_button: Button = PlayerVoiceChromeScript.make_speaker_button()
	speaker_button.pressed.connect(_on_speaker_button_pressed.bind(peer_id))
	PlayerVoiceChromeScript.apply_speaker_button_state(speaker_button, peer_id, false)
	speaker_button.visible = _is_lobby_voice_ui_on()
	row.add_child(speaker_button)
	_speaker_controls[peer_id] = {"button": speaker_button, "volume": volume_row}

	var name_column := VBoxContainer.new()
	name_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_column.add_theme_constant_override("separation", 2)
	row.add_child(name_column)

	var name_label := Label.new()
	name_label.text = NetworkManager.get_lobby_player_label(peer_id)
	name_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1))
	name_column.add_child(name_label)

	var config := PlayerCharacterConfig.from_dict(
		NetworkManager.lobby.get_character_config(peer_id)
	)
	var detail_label := Label.new()
	detail_label.text = config.summary()
	detail_label.add_theme_font_size_override("font_size", 12)
	detail_label.add_theme_color_override("font_color", Color(0.65, 0.58, 0.78))
	name_column.add_child(detail_label)

	var role := NetworkManager.lobby.get_role(peer_id)
	if is_local:
		row.add_child(_build_role_button("Apprentice", GameState.PlayerRole.APPRENTICE, role))
		row.add_child(_build_role_button("Headmaster", GameState.PlayerRole.HEADMASTER, role))
	else:
		var role_label := Label.new()
		role_label.text = RoleAssignment.role_label(role)
		role_label.custom_minimum_size = Vector2(72, 0)
		role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		role_label.add_theme_color_override("font_color", Color(0.75, 0.88, 1))
		row.add_child(role_label)

	return row_wrap


func _on_speaker_button_pressed(peer_id: int) -> void:
	var controls: Dictionary = _speaker_controls.get(peer_id, {})
	var volume_row := controls.get("volume") as Control
	PlayerVoiceChromeScript.handle_speaker_pressed(peer_id, volume_row)
	_update_speaker_button_visuals()


func _update_speaker_button_visuals() -> void:
	var voice_on := _is_lobby_voice_ui_on()
	for peer_id in _speaker_controls.keys():
		var controls: Dictionary = _speaker_controls[peer_id]
		var button := controls.get("button") as Button
		var volume_row := controls.get("volume") as Control
		if button != null:
			button.visible = voice_on
		if volume_row != null and not voice_on:
			volume_row.visible = false
		if not voice_on or button == null:
			continue
		var volume_visible := volume_row != null and volume_row.visible
		PlayerVoiceChromeScript.apply_speaker_button_state(button, int(peer_id), volume_visible)


func _build_role_button(caption: String, role: int, selected_role: int) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(88, 32)
	button.pressed.connect(_on_role_button_pressed.bind(role))
	SelectionStyle.style_choice(button, selected_role == role)
	return button


func _on_role_button_pressed(role: int) -> void:
	NetworkManager.request_lobby_role(role)


func _update_start_button_state() -> void:
	if not _host_mode or not _in_lobby:
		return
	var peer_ids := NetworkManager.get_lobby_peer_ids()
	var can_start := NetworkManager.lobby.can_start(peer_ids)
	_primary_button.disabled = not can_start
	if can_start:
		_status_label.text = _host_ready_message()
	else:
		_status_label.text = NetworkManager.lobby.get_start_block_reason(peer_ids)
	_refresh_lobby_voice_switch()


func _leave_to_menu() -> void:
	_in_lobby = false
	_speaker_controls.clear()
	SteamProximityVoiceHub.set_mode(SteamProximityVoiceHub.Mode.OFF)
	NetworkManager.disconnect_session()
	visible = false
	_reset_panel_state()
	closed.emit()


func _reset_panel_state() -> void:
	_in_lobby = false
	_speaker_controls.clear()
	_players_section.visible = false
	_settings_button.visible = false
	_lobby_voice_row.visible = false
	_lobby_voice_switch.disabled = false
	_lobby_panel_root.visible = true
	for child in _player_list_vbox.get_children():
		child.queue_free()
	_room_code_host_row.visible = true
	_room_code_edit.visible = false
	_primary_button.visible = true
	_back_button.text = "Back"
	_invite_friends_button.disabled = true


func _set_busy(busy: bool) -> void:
	_busy = busy
	_back_button.disabled = busy
	if not _host_mode and not _in_lobby:
		_primary_button.disabled = busy


func _host_ready_message() -> String:
	if SettingsManager.dev_allow_any_lobby_size:
		return "Invite friends with Steam or share the lobby ID."
	return (
		"Start alone to preview, or invite friends. "
		+ "Full matches need 3 players (1 Headmaster, 2 Apprentices)."
	)


func _host_failure_message() -> String:
	if not SteamService.is_api_available() or not ClassDB.class_exists("SteamMultiplayerPeer"):
		return (
			"GodotSteam is not loaded. Open the project with the GodotSteam editor "
			+ "(see tools/versions.env) or run make setup-steam for stock Godot."
		)
	if not SteamService.is_ready():
		return "Steam is not running. Launch the Steam client and try again."
	return "Hosting failed. Check the Output log for details."


func _join_prompt_message() -> String:
	return "Enter the host's Steam lobby ID or accept a Steam invite."
