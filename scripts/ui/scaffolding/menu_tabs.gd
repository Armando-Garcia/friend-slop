@tool
extends TabContainer

## Multi-tab header chrome. Tab titles and the visible page are Inspector-tweakable;
## palette tokens drive selected / hover / muted fonts. Children are the tab pages.
## Listeners use the built-in `tab_changed` / `tab_selected` signals from TabContainer.

@export var tab_titles: PackedStringArray = PackedStringArray(["General", "Graphics"]):
	set(value):
		if value == tab_titles:
			return
		tab_titles = value
		_apply_chrome()

@export_range(0, 32, 1) var editor_tab: int = 0:
	set(value):
		var next := maxi(value, 0)
		if next == editor_tab:
			return
		editor_tab = next
		_apply_chrome()

@export var selected_swatch: UiPalette.Swatch = UiPalette.Swatch.SNOW_WHITE:
	set(value):
		if value == selected_swatch:
			return
		selected_swatch = value
		_apply_chrome()

@export var hover_swatch: UiPalette.Swatch = UiPalette.Swatch.BRONZE:
	set(value):
		if value == hover_swatch:
			return
		hover_swatch = value
		_apply_chrome()

@export var unselected_swatch: UiPalette.Swatch = UiPalette.Swatch.SNOW_WHITE:
	set(value):
		if value == unselected_swatch:
			return
		unselected_swatch = value
		_apply_chrome()

@export var muted_alpha: float = 0.72:
	set(value):
		var next := clampf(value, 0.15, 1.0)
		if is_equal_approx(next, muted_alpha):
			return
		muted_alpha = next
		_apply_chrome()


func _ready() -> void:
	if not tab_changed.is_connected(_on_tab_changed):
		tab_changed.connect(_on_tab_changed)
	_apply_chrome()


func get_selected_tab() -> int:
	return current_tab


func set_selected_tab(index: int) -> void:
	if get_tab_count() == 0:
		return
	var clamped := clampi(index, 0, get_tab_count() - 1)
	if current_tab == clamped:
		return
	set_block_signals(true)
	current_tab = clamped
	set_block_signals(false)
	editor_tab = clamped


func _apply_chrome() -> void:
	if not is_node_ready():
		return
	_apply_titles()
	_apply_tab_colors()
	if get_tab_count() == 0:
		return
	var clamped := clampi(editor_tab, 0, get_tab_count() - 1)
	if current_tab != clamped:
		set_block_signals(true)
		current_tab = clamped
		set_block_signals(false)


func _apply_titles() -> void:
	var count := mini(tab_titles.size(), get_tab_count())
	for i in count:
		var title := tab_titles[i].strip_edges()
		if title.is_empty():
			continue
		set_tab_title(i, title)


func _apply_tab_colors() -> void:
	var selected := UiPalette.swatch_color(selected_swatch)
	var hover := UiPalette.swatch_color(hover_swatch)
	var unselected := UiPalette.swatch_color(unselected_swatch)
	unselected.a = muted_alpha
	add_theme_color_override("font_selected_color", selected)
	add_theme_color_override("font_hovered_color", hover)
	add_theme_color_override("font_unselected_color", unselected)
	add_theme_color_override("font_disabled_color", UiPalette.TEXT_DISABLED)


func _on_tab_changed(index: int) -> void:
	if editor_tab != index:
		editor_tab = index
