## UI color tokens for overlays, menus, and HUD chrome.
## Source of truth: resources/ui/palette.json · Design guide: docs/design/ui-aesthetic.md
class_name UiPalette
extends RefCounted

# Base palette
const INK_BLACK := Color("06080f")
const DARK_AMETHYST := Color("261342")
const PRUSSIAN_BLUE := Color("14213d")
const HUNTER_GREEN := Color("355e3b")
const HONEY_BRONZE := Color("e2ab43")
const SNOW := Color("f6efee")

# Semantic roles
const BACKGROUND_DEEP := INK_BLACK
const BACKGROUND_PRIMARY := DARK_AMETHYST
const BACKGROUND_ELEVATED := PRUSSIAN_BLUE
const ACCENT_PRIMARY := HONEY_BRONZE
const ACCENT_SUCCESS := HUNTER_GREEN
const TEXT_PRIMARY := SNOW
const TEXT_MUTED := Color(SNOW, 0.72)
const TEXT_DISABLED := Color(SNOW, 0.45)
const BORDER_DEFAULT := HONEY_BRONZE
const BORDER_HOVER := Color("f0c05a")
const SCRIM := Color(INK_BLACK, 0.62)

# Shared layout tokens for panels and buttons
const PANEL_CORNER_RADIUS := 10
const BUTTON_CORNER_RADIUS := 8
const PANEL_BORDER_WIDTH := 2


static func panel_style(
	bg: Color = BACKGROUND_ELEVATED,
	border: Color = BORDER_DEFAULT
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(PANEL_BORDER_WIDTH)
	box.set_corner_radius_all(PANEL_CORNER_RADIUS)
	return box


static func button_style(
	bg: Color = BACKGROUND_PRIMARY,
	border: Color = BORDER_DEFAULT
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(PANEL_BORDER_WIDTH)
	box.set_corner_radius_all(BUTTON_CORNER_RADIUS)
	return box
