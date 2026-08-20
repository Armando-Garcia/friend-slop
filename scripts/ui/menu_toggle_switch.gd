class_name MenuToggleSwitch
extends CheckButton

## Reusable large, caption-free on/off switch for menu rows.
## Drop this script on a CheckButton (used by settings / lobby panels).

const DEFAULT_GRAPHIC_SCALE := Vector2(1.5, 1.5)
const DEFAULT_MIN_SIZE := Vector2(48, 28)

@export var graphic_scale: Vector2 = DEFAULT_GRAPHIC_SCALE


func _ready() -> void:
	apply_style(self, graphic_scale)


## Style any CheckButton like a menu toggle (safe to call more than once).
static func apply_style(
	button: CheckButton,
	toggle_scale: Vector2 = DEFAULT_GRAPHIC_SCALE
) -> void:
	if button == null or not is_instance_valid(button):
		return
	button.text = ""
	button.custom_minimum_size = DEFAULT_MIN_SIZE
	button.scale = toggle_scale
