class_name KeybindRow
extends HBoxContainer

## One remappable action: label and current bind.

signal rebind_pressed(action: String)

const InputPromptScript := preload("res://scripts/ui/input_prompt.gd")

var action_name: String = ""

@onready var _label: Label = $Label
@onready var _bind_button: Button = $BindButton


func _ready() -> void:
	_bind_button.pressed.connect(func() -> void: rebind_pressed.emit(action_name))


func setup(action: String, display_label: String) -> void:
	action_name = action
	if _label != null:
		_label.text = display_label
	refresh()


func refresh() -> void:
	if _bind_button == null:
		return
	_bind_button.text = InputPromptScript.action_label(action_name, "—")


func set_listening(listening: bool) -> void:
	if _bind_button == null:
		return
	if listening:
		_bind_button.text = "Press a key…"
	else:
		refresh()


func set_conflict(is_conflict: bool) -> void:
	if _bind_button == null:
		return
	_bind_button.modulate = Color(1.0, 0.82, 0.35) if is_conflict else Color.WHITE
