@tool
extends CanvasLayer

## F6 play HUD for MonsterWorkspace: type, dummy, abilities, combo, fireball.

const TYPE_LABELS := ["Rat Queen", "Ice Caster", "Ember Caster"]

var _rebuilding: bool = false
var _type_option: OptionButton
var _combo_button: Button
var _ability_box: VBoxContainer


func _ready() -> void:
	visible = not Engine.is_editor_hint()
	if Engine.is_editor_hint():
		return
	rebuild()


func rebuild() -> void:
	if Engine.is_editor_hint():
		return
	var box := get_node_or_null("Panel/Buttons") as VBoxContainer
	if box == null:
		return
	_rebuilding = true
	_clear_box(box)
	var ws := _workspace()
	_type_option = OptionButton.new()
	_type_option.name = "TypeOption"
	for label in TYPE_LABELS:
		_type_option.add_item(label)
	if ws != null:
		_type_option.select(int(ws.get("monster_type")))
	_type_option.item_selected.connect(_on_type_selected)
	box.add_child(_type_option)
	_add_button(box, "Spawn Player Dummy", _on_spawn_dummy)
	_add_button(box, "Clear Dummy", _on_clear_dummy)
	_combo_button = _add_button(box, "Preview Combo", _on_combo)
	_combo_button.visible = ws != null and bool(ws.call("has_preview_combo"))
	_ability_box = VBoxContainer.new()
	_ability_box.name = "AbilityButtons"
	box.add_child(_ability_box)
	_rebuild_ability_buttons(ws)
	_add_button(box, "Cast Fireball", _on_fireball)
	_add_button(box, "Reload Monster", _on_reload)
	_rebuilding = false


func _rebuild_ability_buttons(ws: Node) -> void:
	if _ability_box == null:
		return
	_clear_box(_ability_box)
	if ws == null or not ws.has_method("ability_preview_labels"):
		return
	var labels: PackedStringArray = ws.call("ability_preview_labels")
	for i in range(labels.size()):
		var label := labels[i]
		if label.is_empty() or label.begins_with("—"):
			continue
		var idx := i
		var btn := Button.new()
		btn.text = label
		btn.pressed.connect(func() -> void: _on_ability(idx))
		_ability_box.add_child(btn)


func _add_button(parent: Node, text: String, handler: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(handler)
	parent.add_child(btn)
	return btn


func _clear_box(box: Node) -> void:
	var kids := box.get_children()
	for child in kids:
		box.remove_child(child)
		child.free()


func _workspace() -> Node:
	return get_parent()


func _on_type_selected(index: int) -> void:
	if _rebuilding:
		return
	var ws := _workspace()
	if ws != null:
		ws.set("monster_type", index)


func _on_spawn_dummy() -> void:
	var ws := _workspace()
	if ws != null and ws.has_method("spawn_player_dummy"):
		ws.call("spawn_player_dummy")


func _on_clear_dummy() -> void:
	var ws := _workspace()
	if ws != null and ws.has_method("clear_player_dummy"):
		ws.call("clear_player_dummy")


func _on_combo() -> void:
	var ws := _workspace()
	if ws != null and ws.has_method("preview_combo"):
		ws.call("preview_combo")


func _on_ability(index: int) -> void:
	var ws := _workspace()
	if ws != null and ws.has_method("preview_ability_slot"):
		ws.call("preview_ability_slot", index)


func _on_fireball() -> void:
	var ws := _workspace()
	if ws != null and ws.has_method("cast_fireball_at_monster"):
		ws.call("cast_fireball_at_monster")


func _on_reload() -> void:
	var ws := _workspace()
	if ws != null and ws.has_method("reload_selected_monster"):
		ws.call("reload_selected_monster")
