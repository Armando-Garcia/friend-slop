class_name PlayerVoiceChrome
extends RefCounted

## Shared lobby / settings styling and click behavior for per-player voice.

const SPEAKER_IDLE := Color(0.72, 0.82, 0.92, 0.85)
const SPEAKER_ACTIVE := Color(0.45, 1.0, 0.62, 1.0)
const SPEAKER_MUTED := Color(0.55, 0.45, 0.55, 0.75)


static func apply_speaker_button_state(
	button: Button,
	peer_id: int,
	volume_visible: bool = false
) -> void:
	if button == null or not is_instance_valid(button):
		return
	var muted: bool = SteamProximityVoiceHub.is_peer_muted(peer_id)
	var speaking: bool = (
		SteamProximityVoiceHub.is_active()
		and SteamProximityVoiceHub.is_peer_speaking(peer_id)
	)
	if muted:
		button.text = "🔇"
		button.modulate = SPEAKER_MUTED
	else:
		button.text = "🔊" if speaking else "🔈"
		button.modulate = SPEAKER_ACTIVE if speaking else SPEAKER_IDLE
	button.disabled = false
	button.tooltip_text = _tooltip_for(peer_id, muted, volume_visible)


static func make_speaker_button() -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(36, 32)
	button.focus_mode = Control.FOCUS_NONE
	button.flat = true
	button.tooltip_text = "Voice"
	## No grey button chrome — emoji only.
	var empty := StyleBoxEmpty.new()
	for style_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(style_name, empty)
	return button


static func make_volume_row(peer_id: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.visible = false
	row.add_theme_constant_override("separation", 6)

	var slider := HSlider.new()
	slider.name = "VolumeSlider"
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(96, 0)
	slider.value = SteamProximityVoiceHub.get_peer_volume(peer_id)
	var volume_label := Label.new()
	volume_label.name = "VolumeLabel"
	volume_label.custom_minimum_size = Vector2(36, 0)
	volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	volume_label.add_theme_color_override("font_color", Color(0.75, 0.88, 1))
	volume_label.text = "%d%%" % int(round(slider.value * 100.0))
	slider.value_changed.connect(
		func(value: float) -> void:
			SteamProximityVoiceHub.set_peer_volume(peer_id, value)
			volume_label.text = "%d%%" % int(round(value * 100.0))
	)
	row.add_child(slider)
	row.add_child(volume_label)
	return row


## Local: toggle mute. Remote: first click shows volume, second click mutes; muted click unmutes.
static func handle_speaker_pressed(peer_id: int, volume_row: Control = null) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var local_id := 0
	if tree != null:
		local_id = tree.get_multiplayer().get_unique_id()
	var is_local := peer_id == local_id
	var muted: bool = SteamProximityVoiceHub.is_peer_muted(peer_id)

	if is_local:
		SteamProximityVoiceHub.set_peer_muted(peer_id, not muted)
		return

	if muted:
		SteamProximityVoiceHub.set_peer_muted(peer_id, false)
		if volume_row != null:
			volume_row.visible = false
		return

	if volume_row == null:
		SteamProximityVoiceHub.set_peer_muted(peer_id, true)
		return

	if volume_row.visible:
		SteamProximityVoiceHub.set_peer_muted(peer_id, true)
		volume_row.visible = false
	else:
		var slider := volume_row.get_node_or_null("VolumeSlider") as HSlider
		if slider != null:
			slider.set_value_no_signal(SteamProximityVoiceHub.get_peer_volume(peer_id))
			var label := volume_row.get_node_or_null("VolumeLabel") as Label
			if label != null:
				label.text = "%d%%" % int(round(slider.value * 100.0))
		volume_row.visible = true


static func _tooltip_for(peer_id: int, muted: bool, volume_visible: bool) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var local_id := 0
	if tree != null:
		local_id = tree.get_multiplayer().get_unique_id()
	if peer_id == local_id:
		return "Unmute mic" if muted else "Mute mic"
	if muted:
		return "Unmute"
	if volume_visible:
		return "Mute"
	return "Show volume"
