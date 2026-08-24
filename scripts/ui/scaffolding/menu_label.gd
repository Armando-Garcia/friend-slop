@tool
extends Label

## Menu text with pre-baked styles. Pick a TextStyle in the Inspector — never raw hex.

enum TextStyle {
	## Honey bronze heading (Theme TitleLabel).
	TITLE,
	## Primary body copy on dark panels (default Label).
	BODY,
	## Secondary / supporting copy (Theme MutedLabel).
	MUTED,
	## Quiet hint / caption (Theme CaptionLabel).
	CAPTION,
}

@export var text_style: TextStyle = TextStyle.BODY:
	set(value):
		if value == text_style:
			return
		text_style = value
		_apply_chrome()


func _ready() -> void:
	_apply_chrome()


func _apply_chrome() -> void:
	if not is_node_ready():
		return
	match text_style:
		TextStyle.TITLE:
			theme_type_variation = &"TitleLabel"
		TextStyle.MUTED:
			theme_type_variation = &"MutedLabel"
		TextStyle.CAPTION:
			theme_type_variation = &"CaptionLabel"
		_:
			theme_type_variation = &""
	## Drop any one-off font_color override so the Theme variation wins.
	if has_theme_color_override("font_color"):
		remove_theme_color_override("font_color")
