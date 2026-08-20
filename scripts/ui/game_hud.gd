class_name GameHud
extends CanvasLayer

## In-game HUD: casting overlay, hotbar, Tab player menu (Inventory / Guide),
## and the standalone spellbook overlay (B).

const SpellDefinitionScript := preload("res://scripts/spells/spell_definition.gd")
const InputPromptScript := preload("res://scripts/ui/input_prompt.gd")
const PlayerInventoryScript := preload("res://scripts/inventory/player_inventory.gd")
const SpellbookPanelScene := preload("res://scenes/ui/book/spell/spell_book.tscn")

var _loadout: Node
var _inventory: Node
var _selected_spell_id: String = ""
var _active_spell: Resource
var _from_tome := false
var _coaching_countdown := 0.0
var _active_strip: VBoxContainer
var _active_rows: Dictionary = {}
var _player_menu_open := false
var _objective_lines: PackedStringArray = PackedStringArray()
var _hotbar_row: HBoxContainer
var _hotbar_labels: Array[Label] = []
var _mana_root: Control
var _mana_fill: ColorRect
## Typed as Control: the panel is duck-typed (open_book/close_book/is_open).
var _spellbook_panel: Control

@onready var player_menu: Node = $PlayerMenu
@onready var aim_cursor: Control = $AimCursor

@onready var prompt_label: Label = $MarginContainer/PromptLabel
@onready var casting_panel: PanelContainer = $CastingPanel
@onready var casting_title: Label = $CastingPanel/MarginContainer/VBox/TitleLabel
@onready var casting_words: Label = $CastingPanel/MarginContainer/VBox/WordsLabel
@onready var casting_guide: Label = $CastingPanel/MarginContainer/VBox/GuideLabel
@onready var casting_status: Label = $CastingPanel/MarginContainer/VBox/StatusLabel
@onready var mic_level_bar: ProgressBar = $CastingPanel/MarginContainer/VBox/MicLevelBar
@onready var casting_feedback: Label = $CastingPanel/MarginContainer/VBox/FeedbackLabel
@onready var casting_detail: Label = $CastingPanel/MarginContainer/VBox/DetailLabel
@onready var spell_word_banner: Control = $SpellWordBanner


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("game_hud")
	prompt_label.text = ""
	$MarginContainer.visible = false
	casting_panel.visible = false
	mic_level_bar.min_value = 0.0
	mic_level_bar.max_value = 1.0
	mic_level_bar.value = 0.0
	_setup_spellbook_panel()
	_setup_active_strip()
	_setup_hotbar()
	_setup_mana_bar()
	_update_aim_cursor_visibility()


func _input(event: InputEvent) -> void:
	## While open, catch Tab/Esc before TabBar or pause can claim them.
	if not _player_menu_open:
		return
	if event.is_action_pressed("guide_menu") or event.is_action_pressed("ui_cancel"):
		close_player_menu()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _player_menu_open:
		return
	if not event.is_action_pressed("guide_menu"):
		return
	_open_player_menu()
	get_viewport().set_input_as_handled()


func toggle_player_menu() -> void:
	if _player_menu_open:
		close_player_menu()
	else:
		_open_player_menu()


func _open_player_menu() -> void:
	if is_spellbook_open():
		close_spellbook()
	_player_menu_open = true
	player_menu.visible = true
	if _inventory != null and player_menu.has_method("configure_inventory"):
		player_menu.configure_inventory(_inventory)
	if player_menu.has_method("reset_to_main"):
		player_menu.reset_to_main()
	_refresh_player_menu_content()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_player_menu_open() -> bool:
	return _player_menu_open


func is_monster_book_open() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for node in tree.get_nodes_in_group("player"):
		var book := node.get_node_or_null("MonsterBook")
		if book != null and book.has_method("is_book_open") and bool(book.call("is_book_open")):
			return true
	return false


func close_monster_book() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("player"):
		var book := node.get_node_or_null("MonsterBook")
		if book != null and book.has_method("cancel_all"):
			book.call("cancel_all")


func close_player_menu() -> void:
	if not _player_menu_open:
		return
	_player_menu_open = false
	player_menu.visible = false
	if player_menu.has_method("reset_to_main"):
		player_menu.reset_to_main()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func configure_objective(objective: DeliveryObjective) -> void:
	if objective == null:
		return
	if not objective.phase_changed.is_connected(_on_objective_phase_changed):
		objective.phase_changed.connect(_on_objective_phase_changed)
	if not objective.completed.is_connected(_on_objective_completed):
		objective.completed.connect(_on_objective_completed)
	_refresh_objective_lines(objective)


func configure(loadout: Node, casting_session: Node = null) -> void:
	_loadout = loadout
	if _loadout != null and _loadout.has_signal("spell_learned"):
		_loadout.spell_learned.connect(_on_spell_learned)
	if _loadout != null and _loadout.has_signal("loadout_changed"):
		_loadout.loadout_changed.connect(_on_loadout_changed)
	if casting_session != null and casting_session.has_signal("listen_level_changed"):
		casting_session.listen_level_changed.connect(_update_listen_level)
	if casting_session != null and casting_session.has_signal("listen_coaching_changed"):
		casting_session.listen_coaching_changed.connect(_update_listen_coaching)
	if casting_session != null and casting_session.has_signal("tome_retry_tick"):
		casting_session.tome_retry_tick.connect(update_tome_coaching_countdown)


func configure_inventory(inventory: Node) -> void:
	if (
		_inventory != null
		and _inventory.has_signal("inventory_changed")
		and _inventory.inventory_changed.is_connected(_refresh_hotbar)
	):
		_inventory.inventory_changed.disconnect(_refresh_hotbar)
	_inventory = inventory
	if _inventory != null and _inventory.has_signal("inventory_changed"):
		_inventory.inventory_changed.connect(_refresh_hotbar)
	if player_menu != null and player_menu.has_method("configure_inventory"):
		player_menu.configure_inventory(_inventory)
	_refresh_hotbar()


func set_interaction_prompt(text: String) -> void:
	if prompt_label == null:
		return
	prompt_label.text = text
	var margin := prompt_label.get_parent()
	if margin is Control:
		(margin as Control).visible = not text.is_empty()


func toggle_spellbook() -> void:
	if _spellbook_panel == null:
		return
	if is_spellbook_open():
		close_spellbook()
		return
	if _player_menu_open:
		close_player_menu()
	if _spellbook_panel.has_method("configure_loadout"):
		_spellbook_panel.call("configure_loadout", _loadout)
	if _spellbook_panel.has_method("set_selected_spell_id"):
		_spellbook_panel.call("set_selected_spell_id", _selected_spell_id)
	_spellbook_panel.call("open_book")


func close_spellbook() -> void:
	if is_spellbook_open():
		_spellbook_panel.call("close_book")


func is_spellbook_open() -> bool:
	return (
		_spellbook_panel != null
		and _spellbook_panel.has_method("is_open")
		and bool(_spellbook_panel.call("is_open"))
	)


func _setup_spellbook_panel() -> void:
	_spellbook_panel = SpellbookPanelScene.instantiate()
	_spellbook_panel.name = "SpellbookPanel"
	add_child(_spellbook_panel)
	if _spellbook_panel.has_signal("spell_selected"):
		_spellbook_panel.spell_selected.connect(_on_codex_spell_selected)
	if _spellbook_panel.has_signal("closed"):
		_spellbook_panel.closed.connect(_on_spellbook_closed)


func _on_spellbook_closed() -> void:
	if _player_menu_open or get_tree().paused:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func get_selected_spell_id() -> String:
	return _selected_spell_id


func reveal_cast_spell(spell: Resource, color: Color = Color(1, 1, 1, 1)) -> void:
	## Typewriter the spell display name above the hotbar (box invisible; glyphs only).
	if spell_word_banner == null or not spell_word_banner.has_method("reveal"):
		return
	var def := spell as SpellDefinitionScript
	if def == null:
		return
	var word := def.display_name.strip_edges()
	if word.is_empty():
		word = def.id.capitalize()
	## Category color from the spell; optional override when caller passes non-white.
	var ink := def.get_word_display_color()
	if not color.is_equal_approx(Color(1, 1, 1, 1)):
		ink = color
	spell_word_banner.call("reveal", word, ink)


func clear_spell_word() -> void:
	if spell_word_banner != null and spell_word_banner.has_method("clear"):
		spell_word_banner.call("clear")


func show_mana(
	current: float,
	maximum: float = 100.0,
	fill_color: Color = Color(0.35, 0.14, 0.32, 1.0)
) -> void:
	if _mana_root == null:
		return
	_mana_root.visible = true
	set_mana(current, maximum, fill_color)


func set_mana(
	current: float,
	maximum: float = 100.0,
	fill_color: Color = Color(0.35, 0.14, 0.32, 1.0)
) -> void:
	if _mana_fill == null:
		return
	_mana_fill.color = fill_color
	var max_v := maxf(maximum, 0.001)
	var ratio := clampf(current / max_v, 0.0, 1.0)
	## Fill stays on the left; empty grows from the right.
	_mana_fill.anchor_left = 0.0
	_mana_fill.anchor_right = ratio
	_mana_fill.offset_left = 0.0
	_mana_fill.offset_right = 0.0


func hide_mana() -> void:
	if _mana_root != null:
		_mana_root.visible = false


func _setup_mana_bar() -> void:
	## Between spell-word band and hotbar (hotbar top ≈ -96 from bottom).
	var anchor := MarginContainer.new()
	anchor.name = "ManaBarMargin"
	anchor.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	anchor.offset_left = -160.0
	anchor.offset_top = -128.0
	anchor.offset_right = 160.0
	anchor.offset_bottom = -108.0
	anchor.grow_horizontal = Control.GROW_DIRECTION_BOTH
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.visible = false
	add_child(anchor)
	_mana_root = anchor

	var track := PanelContainer.new()
	track.name = "ManaTrack"
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track_style := StyleBoxFlat.new()
	track_style.bg_color = Color(0.08, 0.06, 0.12, 0.92)
	track_style.set_border_width_all(1)
	track_style.border_color = Color(0.18, 0.12, 0.22, 0.9)
	track_style.set_corner_radius_all(4)
	track_style.content_margin_left = 2.0
	track_style.content_margin_top = 2.0
	track_style.content_margin_right = 2.0
	track_style.content_margin_bottom = 2.0
	track.add_theme_stylebox_override("panel", track_style)
	anchor.add_child(track)

	var fill_host := Control.new()
	fill_host.name = "ManaFillHost"
	fill_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill_host.custom_minimum_size = Vector2(0.0, 12.0)
	track.add_child(fill_host)

	_mana_fill = ColorRect.new()
	_mana_fill.name = "ManaFill"
	_mana_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mana_fill.color = Color(0.35, 0.14, 0.32, 1.0)
	_mana_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill_host.add_child(_mana_fill)
	set_mana(100.0, 100.0)


func _setup_hotbar() -> void:
	var anchor := MarginContainer.new()
	anchor.name = "HotbarMargin"
	anchor.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	anchor.offset_left = -220.0
	anchor.offset_top = -96.0
	anchor.offset_right = 220.0
	anchor.offset_bottom = -16.0
	anchor.grow_horizontal = Control.GROW_DIRECTION_BOTH
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	_hotbar_row = HBoxContainer.new()
	_hotbar_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hotbar_row.add_theme_constant_override("separation", 8)
	_hotbar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(_hotbar_row)

	_hotbar_labels.clear()
	for i in PlayerInventoryScript.HOTBAR_COUNT:
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(96, 64)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.06, 0.14, 0.82)
		style.set_border_width_all(1)
		style.border_color = Color(0.45, 0.75, 0.95, 0.4)
		style.set_corner_radius_all(8)
		cell.add_theme_stylebox_override("panel", style)
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color(0.9, 0.94, 1, 1))
		label.text = "%d\n—" % (i + 1)
		cell.add_child(label)
		_hotbar_row.add_child(cell)
		_hotbar_labels.append(label)
	_refresh_hotbar()


func _refresh_hotbar() -> void:
	if _hotbar_labels.is_empty():
		return
	for i in _hotbar_labels.size():
		var item_id := ""
		if _inventory != null and _inventory.has_method("get_slot"):
			item_id = str(_inventory.call("get_slot", i))
		var item_name := ""
		if _inventory != null and _inventory.has_method("display_name"):
			item_name = str(_inventory.call("display_name", item_id))
		elif not item_id.is_empty():
			item_name = item_id.capitalize()
		if item_name.is_empty():
			_hotbar_labels[i].text = "%d\n—" % (i + 1)
		else:
			_hotbar_labels[i].text = "%d\n%s" % [i + 1, item_name]


func show_casting_state(
	state: String,
	spell: Resource,
	from_tome: bool = false,
	free_cast: bool = false
) -> void:
	if spell == null and not free_cast:
		if not _from_tome:
			casting_panel.visible = false
		return
	if free_cast:
		_show_free_cast_state(state)
		return
	var def := spell as SpellDefinitionScript
	if def == null:
		casting_panel.visible = false
		return
	_from_tome = from_tome
	_active_spell = spell
	casting_panel.visible = true
	if from_tome:
		casting_title.text = "Tome: Learning %s" % def.display_name
		casting_words.text = 'Incantation: "%s"' % def.get_incantation_text()
		casting_guide.text = def.get_tome_lesson_text()
	else:
		casting_title.text = "Casting: %s" % def.display_name
		casting_words.text = 'Incantation: "%s"' % def.get_incantation_text()
		var guide_parts: PackedStringArray = []
		var timing: String = def.get_timing_guide_text()
		var pitch: String = def.get_pitch_guide_text()
		if not timing.is_empty():
			guide_parts.append(timing)
		if not pitch.is_empty():
			guide_parts.append(pitch)
		casting_guide.text = "\n".join(guide_parts)
	var leave_hint := "\n\nPress [F] to leave the tome." if from_tome else ""
	match state:
		"arming":
			casting_status.text = "Get ready..."
			casting_detail.text = def.get_listen_coaching_text() + leave_hint
			mic_level_bar.visible = false
			casting_feedback.text = ""
		"listening":
			casting_status.text = "Speak now!"
			casting_detail.text = def.get_listen_coaching_text() + leave_hint
			mic_level_bar.visible = true
			mic_level_bar.value = 0.0
			casting_feedback.text = ""
		"validating":
			casting_status.text = "Checking your cast..."
			casting_detail.text = ""
			mic_level_bar.visible = false
		"coaching":
			casting_status.text = "Not quite — adjust and try again"
			mic_level_bar.visible = false
		_:
			casting_status.text = ""
			if not from_tome:
				casting_detail.text = ""
			mic_level_bar.visible = false
	if state != "coaching":
		casting_feedback.text = ""


func _show_free_cast_state(state: String) -> void:
	_from_tome = false
	casting_panel.visible = true
	casting_title.text = "Voice cast"
	casting_words.text = "Say any spell you know"
	casting_guide.text = _format_known_incantations()
	match state:
		"arming":
			casting_status.text = "Get ready..."
			casting_detail.text = casting_guide.text
			mic_level_bar.visible = false
			casting_feedback.text = ""
		"listening":
			casting_status.text = "Speak now!"
			mic_level_bar.visible = true
			mic_level_bar.value = 0.0
			casting_feedback.text = ""
		"validating":
			casting_status.text = "Identifying your spell..."
			casting_detail.text = ""
			mic_level_bar.visible = false
		_:
			casting_status.text = ""
			casting_detail.text = ""
			mic_level_bar.visible = false


func _format_known_incantations() -> String:
	if _loadout == null:
		return ""
	var known: Array[String] = _loadout.get_known_spell_ids()
	if known.is_empty():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for spell_id in known:
		var spell: Resource = _loadout.get_spell_definition(spell_id)
		var def := spell as SpellDefinitionScript
		if def != null:
			parts.append('"%s" (%s)' % [def.get_incantation_text(), def.display_name])
	return "Known: " + ", ".join(parts)


func _update_listen_level(level: float) -> void:
	if not casting_panel.visible:
		return
	mic_level_bar.value = clampf(level / 0.08, 0.0, 1.0)


func _update_listen_coaching(message: String) -> void:
	if not casting_panel.visible or message.is_empty():
		return
	if _from_tome:
		casting_detail.text = message + "\n\nPress [F] to leave the tome."
	else:
		casting_detail.text = message


func hide_casting() -> void:
	casting_panel.visible = false
	casting_feedback.text = ""
	casting_detail.text = ""
	_active_spell = null
	_from_tome = false
	_coaching_countdown = 0.0


func show_cast_feedback(result: RefCounted, from_tome: bool = false) -> void:
	if result == null:
		return
	var lines: PackedStringArray = PackedStringArray()
	if result.has_method("get_coaching_lines"):
		lines = result.get_coaching_lines(from_tome)
	elif result.has_method("get_feedback_lines"):
		lines = result.get_feedback_lines()
	if lines.is_empty():
		return
	mic_level_bar.visible = false
	casting_feedback.text = lines[0]
	if lines.size() > 1:
		casting_detail.text = "\n".join(lines.slice(1))
	else:
		casting_detail.text = ""
	if from_tome:
		_coaching_countdown = 2.0


func show_spell_learned(spell: Resource, validation: RefCounted = null) -> void:
	var def := spell as SpellDefinitionScript
	if def == null:
		return
	_from_tome = false
	_active_spell = spell
	casting_panel.visible = true
	casting_title.text = "Spell Learned!"
	casting_words.text = def.display_name
	casting_guide.text = def.get_learned_confirmation_text()
	casting_status.text = "The tome's magic is yours now."
	casting_feedback.text = 'Incantation: "%s"' % def.get_incantation_text()
	if validation != null and validation.has_method("get_speech_match_line") \
			and not validation.heard_text.is_empty():
		casting_detail.text = validation.get_speech_match_line()
	else:
		casting_detail.text = ""
	mic_level_bar.visible = false


func show_cast_success(spell: Resource, validation: RefCounted = null) -> void:
	var def := spell as SpellDefinitionScript
	if def == null:
		return
	_from_tome = false
	_active_spell = spell
	casting_panel.visible = true
	casting_title.text = "Cast successful: %s" % def.display_name
	casting_words.text = 'Incantation: "%s"' % def.get_incantation_text()
	casting_guide.text = ""
	casting_status.text = "Success!"
	casting_feedback.text = def.get_cast_success_text()
	if validation != null and validation.has_method("get_speech_match_line") \
			and not validation.heard_text.is_empty():
		casting_detail.text = validation.get_speech_match_line()
	else:
		casting_detail.text = ""
	mic_level_bar.visible = false


func show_spell_active(spell_id: String, duration_sec: float) -> void:
	if duration_sec <= 0.0:
		return
	_ensure_active_row(spell_id)
	var row: Dictionary = _active_rows[spell_id]
	var now := Time.get_ticks_msec() / 1000.0
	row["total_sec"] = duration_sec
	row["active_until"] = now + duration_sec
	_refresh_active_row(spell_id)
	_active_strip.visible = true


func update_tome_coaching_countdown(seconds_left: float) -> void:
	if not _from_tome or not casting_panel.visible:
		return
	_coaching_countdown = seconds_left
	var countdown_line := "Next attempt in %.0fs..." % maxf(0.0, seconds_left)
	if casting_detail.text.is_empty():
		casting_detail.text = countdown_line
	elif not casting_detail.text.contains("Next attempt"):
		casting_detail.text += "\n" + countdown_line
	else:
		var parts: PackedStringArray = casting_detail.text.split("\n")
		var kept: PackedStringArray = PackedStringArray()
		for part in parts:
			if not str(part).begins_with("Next attempt"):
				kept.append(str(part))
		kept.append(countdown_line)
		casting_detail.text = "\n".join(kept)


func _on_codex_spell_selected(spell_id: String) -> void:
	_selected_spell_id = spell_id


func _on_spell_learned(spell_id: String) -> void:
	_selected_spell_id = spell_id
	if _spellbook_panel == null:
		return
	if _spellbook_panel.has_method("set_selected_spell_id"):
		_spellbook_panel.call("set_selected_spell_id", spell_id)
	if is_spellbook_open() and _spellbook_panel.has_method("refresh_pages"):
		_spellbook_panel.call("refresh_pages")


func _process(_delta: float) -> void:
	_update_aim_cursor_visibility()
	_update_active_strip()


func _update_aim_cursor_visibility() -> void:
	if aim_cursor == null:
		return
	# Matches FPS aim: captured mouse uses the screen-center crosshair.
	aim_cursor.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _refresh_player_menu_content() -> void:
	if player_menu != null and player_menu.has_method("refresh"):
		player_menu.refresh(_objective_lines)


func _on_loadout_changed() -> void:
	if is_spellbook_open() and _spellbook_panel.has_method("refresh_pages"):
		_spellbook_panel.call("refresh_pages")
	if _player_menu_open:
		_refresh_player_menu_content()


func _on_objective_phase_changed(_phase: int) -> void:
	_sync_objective_lines_from_scene()
	if _player_menu_open:
		_refresh_player_menu_content()


func _on_objective_completed() -> void:
	_sync_objective_lines_from_scene()
	if _player_menu_open:
		_refresh_player_menu_content()


func _refresh_objective_lines(objective: DeliveryObjective) -> void:
	_objective_lines = objective.get_status_lines()
	if _player_menu_open:
		_refresh_player_menu_content()


func _sync_objective_lines_from_scene() -> void:
	var objective := get_tree().get_first_node_in_group("delivery_objective") as DeliveryObjective
	if objective != null:
		_objective_lines = objective.get_status_lines()
	else:
		_objective_lines = PackedStringArray()


func _setup_active_strip() -> void:
	_active_strip = VBoxContainer.new()
	_active_strip.name = "ActiveEffectStrip"
	_active_strip.add_theme_constant_override("separation", 4)
	add_child(_active_strip)
	_active_strip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_active_strip.offset_left = -220.0
	_active_strip.offset_top = 12.0
	_active_strip.offset_right = -16.0
	_active_strip.offset_bottom = 12.0
	_active_strip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_active_strip.visible = false


func _ensure_active_row(spell_id: String) -> void:
	if _active_rows.has(spell_id):
		return
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.custom_minimum_size = Vector2(96, 0)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.72, 1))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(120, 14)
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.show_percentage = false
	container.add_child(label)
	container.add_child(bar)
	_active_strip.add_child(container)
	_active_rows[spell_id] = {
		"container": container,
		"label": label,
		"bar": bar,
		"total_sec": 1.0,
	}


func _refresh_active_row(spell_id: String) -> void:
	if not _active_rows.has(spell_id):
		return
	var row: Dictionary = _active_rows[spell_id]
	var display_name: String = spell_id
	if _loadout != null:
		var spell: Resource = _loadout.get_spell_definition(spell_id)
		var def := spell as SpellDefinitionScript
		if def != null:
			display_name = def.display_name
	var remaining: float = maxf(
		0.0,
		float(row.get("active_until", 0.0)) - Time.get_ticks_msec() / 1000.0
	)
	var total: float = maxf(float(row.get("total_sec", 1.0)), 0.001)
	row["label"].text = "%s %.1fs" % [display_name, remaining]
	row["bar"].value = clampf(remaining / total, 0.0, 1.0)


func _remove_active_row(spell_id: String) -> void:
	if not _active_rows.has(spell_id):
		return
	var row: Dictionary = _active_rows[spell_id]
	row["container"].queue_free()
	_active_rows.erase(spell_id)
	_active_strip.visible = not _active_rows.is_empty()


func _update_active_strip() -> void:
	for spell_id in _active_rows.keys():
		var row: Dictionary = _active_rows[spell_id]
		var remaining: float = maxf(
			0.0,
			float(row.get("active_until", 0.0)) - Time.get_ticks_msec() / 1000.0
		)
		if remaining <= 0.0:
			_remove_active_row(spell_id)
			continue
		_refresh_active_row(spell_id)
	_active_strip.visible = not _active_rows.is_empty()
