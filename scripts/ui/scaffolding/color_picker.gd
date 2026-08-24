@tool
extends ColorPickerButton

## Palette-styled color picker. Outline and size are per-instance Inspector knobs.

const DEFAULT_PICKER_SIZE := Vector2i(120, 32)

@export var picker_size: Vector2i = DEFAULT_PICKER_SIZE:
	set(value):
		var next := Vector2i(maxi(value.x, 48), maxi(value.y, 24))
		if next == picker_size:
			return
		picker_size = next
		custom_minimum_size = Vector2(picker_size)
		_apply_chrome()

@export var show_outline: bool = true:
	set(value):
		if value == show_outline:
			return
		show_outline = value
		_apply_chrome()

@export var outline_swatch: UiPalette.Swatch = UiPalette.Swatch.BRONZE:
	set(value):
		if value == outline_swatch:
			return
		outline_swatch = value
		_apply_chrome()

@export var edit_alpha_channel: bool = false:
	set(value):
		if value == edit_alpha_channel:
			return
		edit_alpha_channel = value
		_apply_chrome()


func _ready() -> void:
	_apply_chrome()


func _apply_chrome() -> void:
	if not is_node_ready():
		return
	custom_minimum_size = Vector2(picker_size)
	edit_alpha = edit_alpha_channel
	text = ""
	UiPalette.paint_button_outline(self, show_outline, outline_swatch)
