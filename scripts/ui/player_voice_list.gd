class_name PlayerVoiceList
extends VBoxContainer

## Player mute / volume list for Audio settings (and similar panels).

const PlayerVoiceChromeScript := preload("res://scripts/ui/player_voice_chrome.gd")

var _header: Label
var _empty_label: Label
var _rows_root: VBoxContainer
## peer_id -> { "button": Button, "volume": Control, "detail": Label }
var _row_controls: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override("separation", 8)
	_header = Label.new()
	_header.text = "Players"
	_header.add_theme_color_override("font_color", Color(0.75, 0.88, 1))
	add_child(_header)

	_empty_label = Label.new()
	_empty_label.add_theme_color_override("font_color", Color(0.65, 0.58, 0.78))
	_empty_label.add_theme_font_size_override("font_size", 13)
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.text = "Join a multiplayer session to adjust per-player voice."
	add_child(_empty_label)

	_rows_root = VBoxContainer.new()
	_rows_root.add_theme_constant_override("separation", 6)
	add_child(_rows_root)


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	_update_speaker_visuals()


func refresh() -> void:
	_row_controls.clear()
	for child in _rows_root.get_children():
		child.queue_free()

	if not NetworkManager.is_online():
		_empty_label.visible = true
		_empty_label.text = "Join a multiplayer session to adjust per-player voice."
		return

	var peer_ids := NetworkManager.get_lobby_peer_ids()
	if peer_ids.is_empty():
		_empty_label.visible = true
		_empty_label.text = "No other players in this session yet."
		return

	_empty_label.visible = false
	var local_id := multiplayer.get_unique_id()
	for peer_id in peer_ids:
		_rows_root.add_child(_build_row(peer_id, local_id))
	_update_speaker_visuals()


func _build_row(peer_id: int, local_id: int) -> VBoxContainer:
	var row_wrap := VBoxContainer.new()
	row_wrap.add_theme_constant_override("separation", 4)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	row_wrap.add_child(row)

	var is_local := peer_id == local_id
	var volume_row: HBoxContainer = null
	if not is_local:
		volume_row = PlayerVoiceChromeScript.make_volume_row(peer_id)
		row_wrap.add_child(volume_row)

	var speaker: Button = PlayerVoiceChromeScript.make_speaker_button()
	speaker.pressed.connect(_on_speaker_pressed.bind(peer_id))
	PlayerVoiceChromeScript.apply_speaker_button_state(speaker, peer_id, false)
	row.add_child(speaker)

	var name_column := VBoxContainer.new()
	name_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_column.add_theme_constant_override("separation", 2)
	row.add_child(name_column)

	var name_label := Label.new()
	name_label.text = NetworkManager.get_lobby_player_label(peer_id)
	name_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1))
	name_column.add_child(name_label)

	var detail := Label.new()
	detail.name = "DetailLabel"
	detail.add_theme_font_size_override("font_size", 12)
	detail.add_theme_color_override("font_color", Color(0.65, 0.58, 0.78))
	name_column.add_child(detail)

	_row_controls[peer_id] = {"button": speaker, "volume": volume_row, "detail": detail}
	_apply_detail_text(peer_id, detail, is_local)
	return row_wrap


func _on_speaker_pressed(peer_id: int) -> void:
	var controls: Dictionary = _row_controls.get(peer_id, {})
	var volume_row := controls.get("volume") as Control
	PlayerVoiceChromeScript.handle_speaker_pressed(peer_id, volume_row)
	_update_speaker_visuals()


func _update_speaker_visuals() -> void:
	for peer_id in _row_controls.keys():
		var controls: Dictionary = _row_controls[peer_id]
		var button := controls.get("button") as Button
		var volume_row := controls.get("volume") as Control
		var volume_visible := volume_row != null and volume_row.visible
		PlayerVoiceChromeScript.apply_speaker_button_state(button, int(peer_id), volume_visible)
		var detail := controls.get("detail") as Label
		if detail != null:
			_apply_detail_text(int(peer_id), detail, int(peer_id) == multiplayer.get_unique_id())


func _apply_detail_text(peer_id: int, detail: Label, is_local: bool) -> void:
	if is_local:
		detail.text = "Click to mute / unmute your mic"
		return
	if SteamProximityVoiceHub.is_peer_muted(peer_id):
		detail.text = "Muted — click to unmute"
	else:
		detail.text = "Click for volume, click again to mute"
