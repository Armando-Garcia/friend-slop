class_name HudSection
extends VBoxContainer

## Titled HUD cluster: label, rule, then the slotted row.


func setup(title: String, body: Control) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 2)
	var header := Label.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.text = title
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.90, 0.84, 0.68, 1))
	add_child(header)
	var rule := HSeparator.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.modulate = Color(0.82, 0.70, 0.38, 0.75)
	add_child(rule)
	if body.get_parent() != null:
		body.get_parent().remove_child(body)
	add_child(body)
