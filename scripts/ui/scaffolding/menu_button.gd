@tool
extends Button

## Menu button chrome. Outline is per-instance — does not mutate the Theme.

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


func _ready() -> void:
	_apply_chrome()


func _apply_chrome() -> void:
	if not is_node_ready():
		return
	UiPalette.paint_button_outline(self, show_outline, outline_swatch)
