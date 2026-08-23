@tool
class_name ToggleSlider
extends Control

## Two-option sliding window. Click a side to move the window.

signal selected_changed(index: int)

const DEFAULT_SLIDER_SIZE := Vector2i(200, 30)
const _INSET := 2.0

@export var slider_size: Vector2i = DEFAULT_SLIDER_SIZE:
	set(value):
		var next := Vector2i(maxi(value.x, 48), maxi(value.y, 20))
		if next == slider_size:
			return
		slider_size = next
		custom_minimum_size = Vector2(slider_size)
		_apply_chrome()

@export var left_text: String = "Left":
	set(value):
		if value == left_text:
			return
		left_text = value
		_apply_chrome()

@export var right_text: String = "Right":
	set(value):
		if value == right_text:
			return
		right_text = value
		_apply_chrome()

@export_range(0, 1, 1) var selected: int = 0:
	set(value):
		var next := clampi(value, 0, 1)
		var changed := next != selected
		selected = next
		_apply_chrome()
		if changed and not Engine.is_editor_hint() and is_node_ready():
			selected_changed.emit(selected)

@export var disabled: bool = false:
	set(value):
		disabled = value
		modulate = Color(1, 1, 1, 0.55) if disabled else Color.WHITE

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

var _window_tween: Tween

@onready var _track: Panel = $Track
@onready var _window: Panel = $Track/Window
@onready var _left_label: Label = $Track/Options/LeftLabel
@onready var _right_label: Label = $Track/Options/RightLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(slider_size)
	_apply_chrome()
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)


func get_selected() -> int:
	return selected


func set_selected(index: int, emit_change: bool = true) -> void:
	if emit_change:
		selected = index
		return
	selected = clampi(index, 0, 1)
	_apply_chrome()


func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or disabled:
		return
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	selected = 0 if mouse.position.x < size.x * 0.5 else 1
	accept_event()


func _on_resized() -> void:
	_place_window(false)


func _apply_chrome() -> void:
	if not is_node_ready():
		return
	_left_label.text = left_text
	_right_label.text = right_text
	_left_label.add_theme_color_override(
		"font_color",
		UiPalette.TEXT_PRIMARY if selected == 0 else UiPalette.TEXT_MUTED
	)
	_right_label.add_theme_color_override(
		"font_color",
		UiPalette.TEXT_PRIMARY if selected == 1 else UiPalette.TEXT_MUTED
	)
	UiPalette.paint_panel_outline(_track, show_outline, outline_swatch, 1)
	_place_window(not Engine.is_editor_hint() and is_inside_tree())


func _place_window(animate: bool) -> void:
	if _window == null:
		return
	var inner := Rect2(
		Vector2(_INSET, _INSET),
		Vector2(maxf(size.x - _INSET * 2.0, 1.0), maxf(size.y - _INSET * 2.0, 1.0))
	)
	var half := inner.size.x * 0.5
	_window.size = Vector2(half, inner.size.y)
	var target := Vector2(inner.position.x + (0.0 if selected == 0 else half), inner.position.y)
	if _window_tween != null and _window_tween.is_valid():
		_window_tween.kill()
	if animate:
		_window_tween = create_tween()
		_window_tween.tween_property(_window, "position", target, 0.16)
	else:
		_window.position = target
