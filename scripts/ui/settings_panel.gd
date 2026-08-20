class_name SettingsPanel
extends Control

signal closed

const DisplayResolutionPresetsScript := preload("res://scripts/ui/display_resolution_presets.gd")

var _mic_test_active := false
var _mic_peak: float = 0.0
var _output_device_option: OptionButton
var _input_device_option: OptionButton
var _master_volume_slider: HSlider
var _master_volume_label: Label
var _mic_volume_slider: HSlider
var _mic_volume_label: Label
var _mic_test_button: Button
var _hear_myself_switch: CheckButton
var _mic_level_bar: ProgressBar
var _mic_status_label: Label
var _lobby_voice_switch: CheckButton
var _lobby_voice_hint: Label
var _player_voice_list: VBoxContainer
var _display_mode_option: OptionButton
var _resolution_option: OptionButton
var _resolution_hint_label: Label
var _crosshair_opacity_slider: HSlider
var _crosshair_opacity_label: Label
var _crosshair_thickness_slider: HSlider
var _crosshair_thickness_label: Label
var _crosshair_color_picker: ColorPickerButton
var _crosshair_outer_switch: CheckButton
var _crosshair_dot_switch: CheckButton
var _crosshair_preview: Control
var _dev_apprentice_button: Button
var _dev_headmaster_button: Button
var _voice_stub_checkbox: CheckBox
var _dev_spawn_relic_near_spawn_checkbox: CheckBox
var _dev_allow_any_lobby_size_checkbox: CheckBox
var _dev_solo_role: int = GameState.PlayerRole.APPRENTICE

@onready var _general_vbox: VBoxContainer = (
	$Panel/MarginContainer/VBox/TabContainer/General/MarginContainer/ScrollContainer/GeneralVBox
)
@onready var _graphics_vbox: VBoxContainer = (
	$Panel/MarginContainer/VBox/TabContainer/Graphics/MarginContainer/ScrollContainer/GraphicsVBox
)
@onready var _audio_vbox: VBoxContainer = (
	$Panel/MarginContainer/VBox/TabContainer/Audio/MarginContainer/ScrollContainer/AudioVBox
)
@onready var _dev_vbox: VBoxContainer = (
	$Panel/MarginContainer/VBox/TabContainer/Developer/MarginContainer/DevVBox
)
@onready var _close_button: Button = $Panel/MarginContainer/VBox/CloseButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_cache_node_refs()
	_master_volume_slider.min_value = 0.0
	_master_volume_slider.max_value = 1.0
	_master_volume_slider.step = 0.01
	_mic_volume_slider.min_value = 0.0
	_mic_volume_slider.max_value = 1.0
	_mic_volume_slider.step = 0.01
	_crosshair_opacity_slider.min_value = 0.0
	_crosshair_opacity_slider.max_value = 1.0
	_crosshair_opacity_slider.step = 0.01
	_crosshair_thickness_slider.min_value = 0.5
	_crosshair_thickness_slider.max_value = 5.0
	_crosshair_thickness_slider.step = 0.05
	_mic_level_bar.min_value = 0.0
	_mic_level_bar.max_value = 1.0
	_mic_level_bar.value = 0.0
	_close_button.pressed.connect(_on_close_pressed)
	_mic_test_button.pressed.connect(_on_mic_test_pressed)
	_hear_myself_switch.toggled.connect(_on_hear_myself_toggled)
	_master_volume_slider.value_changed.connect(_on_master_volume_changed)
	_mic_volume_slider.value_changed.connect(_on_mic_volume_changed)
	_crosshair_opacity_slider.value_changed.connect(_on_crosshair_opacity_changed)
	_crosshair_thickness_slider.value_changed.connect(_on_crosshair_thickness_changed)
	_crosshair_color_picker.color_changed.connect(_on_crosshair_color_changed)
	_crosshair_outer_switch.toggled.connect(_on_crosshair_outer_toggled)
	_crosshair_dot_switch.toggled.connect(_on_crosshair_dot_toggled)
	_lobby_voice_switch.toggled.connect(_on_lobby_voice_toggled)
	_dev_apprentice_button.pressed.connect(_on_dev_apprentice_pressed)
	_dev_headmaster_button.pressed.connect(_on_dev_headmaster_pressed)
	_display_mode_option.item_selected.connect(_on_display_mode_selected)
	_resolution_option.item_selected.connect(_on_resolution_selected)
	_input_device_option.item_selected.connect(_on_input_device_selected)
	_output_device_option.item_selected.connect(_on_output_device_selected)
	NetworkManager.lobby_roster_changed.connect(_on_lobby_roster_changed)
	_populate_from_settings()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()


func open() -> void:
	_populate_from_settings()
	visible = true
	_mic_test_active = false
	_mic_peak = 0.0
	_mic_level_bar.value = 0.0
	_mic_status_label.text = "Press Test Microphone to check input."
	_mic_test_button.text = "Test Microphone"
	_refresh_lobby_voice_switch()
	_refresh_player_voice_list()


func close_panel() -> void:
	if not visible:
		return
	if _mic_test_active:
		_stop_mic_test()
	## Persist whatever is live in SettingsManager (including mid-panel audio
	## device rebinds) when leaving the menu.
	_apply_to_manager()
	SettingsManager.save_settings()
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh_lobby_voice_switch()
	if not _mic_test_active:
		return

	var level: float = SettingsManager.poll_mic_level()
	_mic_peak = maxf(_mic_peak * 0.92, level)
	_mic_level_bar.value = _mic_peak
	if _mic_peak > 0.02:
		_mic_status_label.text = "Microphone detected — speak to see levels."
	elif _mic_peak > 0.005:
		_mic_status_label.text = "Quiet input detected — try speaking louder."
	else:
		_mic_status_label.text = "Listening… no input yet. Check device selection."


func _cache_node_refs() -> void:
	_display_mode_option = _graphics_vbox.get_node("DisplayModeOption")
	_resolution_option = _graphics_vbox.get_node("ResolutionOption")
	_resolution_hint_label = _graphics_vbox.get_node("ResolutionHintLabel")
	_crosshair_opacity_slider = _general_vbox.get_node(
		"CrosshairOpacityRow/CrosshairOpacitySlider"
	)
	_crosshair_opacity_label = _general_vbox.get_node(
		"CrosshairOpacityRow/CrosshairOpacityLabel"
	)
	_crosshair_thickness_slider = _general_vbox.get_node(
		"CrosshairThicknessRow/CrosshairThicknessSlider"
	)
	_crosshair_thickness_label = _general_vbox.get_node(
		"CrosshairThicknessRow/CrosshairThicknessLabel"
	)
	_crosshair_color_picker = _general_vbox.get_node(
		"CrosshairColorRow/CrosshairColorPicker"
	)
	_crosshair_outer_switch = _general_vbox.get_node(
		"CrosshairOuterRow/CrosshairOuterSwitch"
	)
	_crosshair_dot_switch = _general_vbox.get_node("CrosshairDotRow/CrosshairDotSwitch")
	_crosshair_preview = _general_vbox.get_node("CrosshairPreviewFrame/CrosshairPreview")
	_output_device_option = _audio_vbox.get_node("OutputDeviceOption")
	_input_device_option = _audio_vbox.get_node("InputDeviceOption")
	_master_volume_slider = _audio_vbox.get_node("MasterVolumeRow/MasterVolumeSlider")
	_master_volume_label = _audio_vbox.get_node("MasterVolumeRow/MasterVolumeLabel")
	_mic_volume_slider = _audio_vbox.get_node("MicVolumeRow/MicVolumeSlider")
	_mic_volume_label = _audio_vbox.get_node("MicVolumeRow/MicVolumeLabel")
	_mic_test_button = _audio_vbox.get_node("MicTestButton")
	_hear_myself_switch = _audio_vbox.get_node("HearMyselfRow/HearMyselfSwitch")
	_mic_level_bar = _audio_vbox.get_node("MicLevelBar")
	_mic_status_label = _audio_vbox.get_node("MicStatusLabel")
	_lobby_voice_switch = _audio_vbox.get_node("LobbyVoiceRow/LobbyVoiceSwitch")
	_lobby_voice_hint = _audio_vbox.get_node("LobbyVoiceHint")
	_player_voice_list = _audio_vbox.get_node_or_null("PlayerVoiceList") as VBoxContainer
	_dev_apprentice_button = _dev_vbox.get_node("DevRoleSection/DevApprenticeButton")
	_dev_headmaster_button = _dev_vbox.get_node("DevRoleSection/DevHeadmasterButton")
	_voice_stub_checkbox = _dev_vbox.get_node("VoiceStubCheckBox")
	_dev_spawn_relic_near_spawn_checkbox = _dev_vbox.get_node("DevSpawnRelicNearSpawnCheckBox")
	_dev_allow_any_lobby_size_checkbox = _dev_vbox.get_node("DevAllowAnyLobbySizeCheckBox")


func _populate_from_settings() -> void:
	_populate_display_mode_options()
	_select_display_mode(SettingsManager.fullscreen)
	_populate_resolution_options()
	_select_resolution(SettingsManager.get_window_resolution_preset_index())
	_fill_device_option(
		_output_device_option,
		SettingsManager.get_output_devices(),
		"System Default"
	)
	_fill_device_option(
		_input_device_option,
		SettingsManager.get_input_devices(),
		"System Default"
	)
	_output_device_option.set_block_signals(true)
	_input_device_option.set_block_signals(true)
	_select_device(_output_device_option, SettingsManager.output_device)
	_select_device(_input_device_option, SettingsManager.input_device)
	_output_device_option.set_block_signals(false)
	_input_device_option.set_block_signals(false)
	_master_volume_slider.value = SettingsManager.master_volume
	_update_master_volume_label(SettingsManager.master_volume)
	_mic_volume_slider.value = SettingsManager.mic_volume
	_update_mic_volume_label(SettingsManager.mic_volume)
	_hear_myself_switch.set_pressed_no_signal(SettingsManager.hear_myself)
	_crosshair_opacity_slider.value = SettingsManager.crosshair_opacity
	_update_crosshair_opacity_label(SettingsManager.crosshair_opacity)
	_crosshair_thickness_slider.value = SettingsManager.crosshair_thickness
	_update_crosshair_thickness_label(SettingsManager.crosshair_thickness)
	_crosshair_color_picker.set_block_signals(true)
	_crosshair_color_picker.color = SettingsManager.crosshair_color
	_crosshair_color_picker.set_block_signals(false)
	_crosshair_outer_switch.set_pressed_no_signal(SettingsManager.crosshair_show_outer)
	_crosshair_dot_switch.set_pressed_no_signal(SettingsManager.crosshair_show_dot)
	_refresh_crosshair_preview()
	_refresh_lobby_voice_switch()
	_dev_solo_role = SettingsManager.dev_solo_role
	_refresh_dev_solo_ui()
	_voice_stub_checkbox.button_pressed = SettingsManager.voice_use_stub
	_dev_spawn_relic_near_spawn_checkbox.button_pressed = (
		SettingsManager.dev_spawn_relic_near_spawn
	)
	_dev_allow_any_lobby_size_checkbox.button_pressed = (
		SettingsManager.dev_allow_any_lobby_size
	)


func _populate_display_mode_options() -> void:
	_display_mode_option.clear()
	_display_mode_option.add_item("Windowed")
	_display_mode_option.add_item("Fullscreen")


func _select_display_mode(is_fullscreen: bool) -> void:
	_display_mode_option.set_block_signals(true)
	_display_mode_option.select(1 if is_fullscreen else 0)
	_display_mode_option.set_block_signals(false)


func _populate_resolution_options() -> void:
	_resolution_option.clear()
	for resolution_size in SettingsManager.get_resolution_presets():
		_resolution_option.add_item(
			DisplayResolutionPresetsScript.format_label(resolution_size)
		)
	_update_resolution_hint()


func _update_resolution_hint() -> void:
	if _resolution_hint_label == null:
		return
	if SettingsManager.is_running_embedded_in_editor():
		_resolution_hint_label.text = (
			"Window size cannot change in the embedded Game tab, "
			+ "but render and UI scale still follow the chosen resolution."
		)
	elif SettingsManager.fullscreen:
		_resolution_hint_label.text = (
			"Fullscreen fills your monitor. Resolution sets the render and UI scale."
		)
	else:
		_resolution_hint_label.text = (
			"Windowed mode uses this size for the game window. "
			+ "Drag the window edges to resize manually."
		)


func _select_resolution(index: int) -> void:
	if _resolution_option.item_count == 0:
		return
	_resolution_option.set_block_signals(true)
	_resolution_option.select(clampi(index, 0, _resolution_option.item_count - 1))
	_resolution_option.set_block_signals(false)


func _refresh_dev_solo_ui() -> void:
	var is_apprentice := _dev_solo_role == GameState.PlayerRole.APPRENTICE
	SelectionStyle.style_choice(_dev_apprentice_button, is_apprentice)
	SelectionStyle.style_choice(_dev_headmaster_button, not is_apprentice)


func _fill_device_option(
	option: OptionButton,
	devices: PackedStringArray,
	default_label: String
) -> void:
	option.clear()
	option.add_item(default_label)
	for device_name in devices:
		option.add_item(device_name)


func _select_device(option: OptionButton, saved_device: String) -> void:
	if saved_device.is_empty():
		option.select(0)
		return
	for i in option.item_count:
		if option.get_item_text(i) == saved_device:
			option.select(i)
			return
	option.select(0)


func _apply_to_manager() -> void:
	## Push UI into live SettingsManager + audio/display systems.
	## Does not write settings.cfg — that happens on close/save.
	SettingsManager.fullscreen = _display_mode_option.selected == 1
	SettingsManager.set_window_resolution_preset_index(_resolution_option.selected)
	SettingsManager.master_volume = _master_volume_slider.value
	SettingsManager.mic_volume = _mic_volume_slider.value
	SettingsManager.hear_myself = _hear_myself_switch.button_pressed
	SettingsManager.output_device = _read_device_selection(_output_device_option)
	SettingsManager.input_device = _read_device_selection(_input_device_option)
	SettingsManager.crosshair_opacity = _crosshair_opacity_slider.value
	SettingsManager.crosshair_thickness = _crosshair_thickness_slider.value
	SettingsManager.crosshair_color = _crosshair_color_picker.color
	SettingsManager.crosshair_show_outer = _crosshair_outer_switch.button_pressed
	SettingsManager.crosshair_show_dot = _crosshair_dot_switch.button_pressed
	SettingsManager.dev_solo_role = _dev_solo_role
	SettingsManager.voice_use_stub = _voice_stub_checkbox.button_pressed
	SettingsManager.dev_spawn_relic_near_spawn = (
		_dev_spawn_relic_near_spawn_checkbox.button_pressed
	)
	SettingsManager.dev_allow_any_lobby_size = (
		_dev_allow_any_lobby_size_checkbox.button_pressed
	)
	SettingsManager.apply_audio_settings()
	SettingsManager.apply_display_settings()


func _read_device_selection(option: OptionButton) -> String:
	if option.selected <= 0:
		return ""
	return option.get_item_text(option.selected)


func _on_display_mode_selected(index: int) -> void:
	SettingsManager.fullscreen = index == 1
	_update_resolution_hint()
	SettingsManager.apply_display_settings()


func _on_resolution_selected(index: int) -> void:
	SettingsManager.set_window_resolution_preset_index(index)
	SettingsManager.apply_display_settings()


func _on_dev_apprentice_pressed() -> void:
	_dev_solo_role = GameState.PlayerRole.APPRENTICE
	_refresh_dev_solo_ui()


func _on_dev_headmaster_pressed() -> void:
	_dev_solo_role = GameState.PlayerRole.HEADMASTER
	_refresh_dev_solo_ui()


func _on_master_volume_changed(value: float) -> void:
	_update_master_volume_label(value)
	SettingsManager.master_volume = value
	SettingsManager.apply_audio_settings()


func _on_mic_volume_changed(value: float) -> void:
	_update_mic_volume_label(value)
	SettingsManager.mic_volume = value
	SettingsManager.apply_audio_settings()


func _on_crosshair_opacity_changed(value: float) -> void:
	_update_crosshair_opacity_label(value)
	SettingsManager.crosshair_opacity = value
	_refresh_crosshair_preview()


func _on_crosshair_thickness_changed(value: float) -> void:
	_update_crosshair_thickness_label(value)
	SettingsManager.crosshair_thickness = value
	_refresh_crosshair_preview()


func _on_crosshair_color_changed(color: Color) -> void:
	SettingsManager.crosshair_color = color
	_refresh_crosshair_preview()


func _on_crosshair_outer_toggled(enabled: bool) -> void:
	SettingsManager.crosshair_show_outer = enabled
	_refresh_crosshair_preview()


func _on_crosshair_dot_toggled(enabled: bool) -> void:
	SettingsManager.crosshair_show_dot = enabled
	_refresh_crosshair_preview()


func _on_hear_myself_toggled(enabled: bool) -> void:
	SettingsManager.hear_myself = enabled
	SettingsManager.apply_audio_settings()


func _on_input_device_selected(_index: int) -> void:
	## Live preview: free old mic stream and open the selected device.
	## Persisted to settings.cfg only when the panel is closed.
	SettingsManager.input_device = _read_device_selection(_input_device_option)
	SettingsManager.apply_audio_settings()


func _on_output_device_selected(_index: int) -> void:
	SettingsManager.output_device = _read_device_selection(_output_device_option)
	SettingsManager.apply_audio_settings()


func _is_lobby_voice_ui_on() -> bool:
	if NetworkManager.is_session_active:
		return SteamProximityVoiceHub.get_mode() == SteamProximityVoiceHub.Mode.LOBBY
	return SettingsManager.lobby_voice_default


func _can_toggle_lobby_voice_live() -> bool:
	return NetworkManager.is_session_active and NetworkManager.is_host()


func _refresh_lobby_voice_switch() -> void:
	if _lobby_voice_switch == null:
		return
	var enabled := _is_lobby_voice_ui_on()
	_lobby_voice_switch.set_pressed_no_signal(enabled)
	var steam_ready := SteamService.is_ready()
	if NetworkManager.is_session_active:
		_lobby_voice_switch.disabled = not steam_ready or not NetworkManager.is_host()
		if _lobby_voice_hint != null:
			_lobby_voice_hint.text = (
				"Same control as the lobby menu. Only the host can change lobby voice."
				if NetworkManager.is_host()
				else "Lobby voice is controlled by the host."
			)
	else:
		_lobby_voice_switch.disabled = false
		if _lobby_voice_hint != null:
			_lobby_voice_hint.text = (
				"Sets your default for the next lobby. Hosts can still toggle voice live "
				+ "from the lobby menu or here."
			)


func _on_lobby_voice_toggled(enabled: bool) -> void:
	if _lobby_voice_switch.disabled:
		_refresh_lobby_voice_switch()
		return

	SettingsManager.lobby_voice_default = enabled

	if _can_toggle_lobby_voice_live():
		_set_lobby_voice_enabled(enabled)
	_refresh_lobby_voice_switch()


func _set_lobby_voice_enabled(enabled: bool) -> void:
	if enabled:
		SteamProximityVoiceHub.set_mode(SteamProximityVoiceHub.Mode.LOBBY)
	else:
		SteamProximityVoiceHub.set_mode(SteamProximityVoiceHub.Mode.OFF)
	if (
		enabled
		and SteamService.is_ready()
		and not SteamProximityVoiceHub.is_lobby_voice_active()
	):
		SteamProximityVoiceHub.set_mode(SteamProximityVoiceHub.Mode.OFF)
		SettingsManager.lobby_voice_default = false
		_lobby_voice_switch.set_pressed_no_signal(false)


func _update_master_volume_label(value: float) -> void:
	_master_volume_label.text = "%d%%" % int(round(value * 100.0))


func _update_mic_volume_label(value: float) -> void:
	_mic_volume_label.text = "%d%%" % int(round(value * 100.0))


func _update_crosshair_opacity_label(value: float) -> void:
	_crosshair_opacity_label.text = "%d%%" % int(round(value * 100.0))


func _update_crosshair_thickness_label(value: float) -> void:
	_crosshair_thickness_label.text = "%.1f" % value


func _refresh_crosshair_preview() -> void:
	if _crosshair_preview != null:
		_crosshair_preview.queue_redraw()


func _on_mic_test_pressed() -> void:
	if _mic_test_active:
		_stop_mic_test()
	else:
		_start_mic_test()


func _start_mic_test() -> void:
	## Apply current UI to the live mic path (no file write); test forces Hear Myself.
	_apply_to_manager()
	_mic_peak = 0.0
	_mic_level_bar.value = 0.0
	SettingsManager.start_mic_test()
	_mic_test_active = true
	_mic_test_button.text = "Stop Microphone Test"
	_mic_status_label.text = "Listening… (Hear Myself on for this test)"


func _stop_mic_test() -> void:
	SettingsManager.stop_mic_test()
	_mic_test_active = false
	_mic_test_button.text = "Test Microphone"
	_mic_status_label.text = "Microphone test stopped."


func _on_lobby_roster_changed() -> void:
	if not visible:
		return
	_refresh_player_voice_list()


func _refresh_player_voice_list() -> void:
	if _player_voice_list != null and _player_voice_list.has_method("refresh"):
		_player_voice_list.call("refresh")


func _on_close_pressed() -> void:
	close_panel()
