# UI design aesthetic

**Canonical reference** for UI styling — linked from [AGENTS.md](../../AGENTS.md) for all AI assistants (Cursor, Claude, etc.).

Curated palette and usage rules for **overlays, menus, settings, lobby, pause flow, and HUD chrome**. World geometry, spell VFX, and monster lookdev are out of scope unless explicitly noted.

Machine-readable palette: `[resources/ui/palette.json](../../resources/ui/palette.json)`  
Godot constants and style helpers: `[scripts/ui/ui_palette.gd](../../scripts/ui/ui_palette.gd)`

## Palette


| Name           | Hex       | Role                                                                 |
| -------------- | --------- | -------------------------------------------------------------------- |
| Ink Black      | `#06080f` | Deepest backdrop, scrim base                                         |
| Dark Amethyst  | `#261342` | Accents, gems, flare                                                 |
| Prussian Blue  | `#14213d` | Elevated surfaces, nested panels, tabs, menus                        |
| Hunter Green   | `#355e3b` | Success, active-positive states (e.g. voice live)                    |
| Honey Bronze   | `#e2ab43` | Primary accent — borders, focus, CTAs                                |
| Snow           | `#f6efee` | Primary text on dark surfaces                                        |
| Mist           | `#9699a2` | Cool mid-light between Ink and Snow — toggle on-track, soft lit cues |
| Health Crimson | `#9b2c2c` | HP fill and optional outline / accent                                |




## Mood

Gothic arcane library at night: deep purples and blues, warm bronze trim, readable snow text. Panels feel like bound tomes or warded glass — framed, not flat.

## Semantic tokens

Use `UiPalette` constants instead of hard-coded RGB in new UI work:


| Token            | Constant              | Typical use                                         |
| ---------------- | --------------------- | --------------------------------------------------- |
| Deep background  | `BACKGROUND_DEEP`     | Full-screen menu backdrop                           |
| Primary surface  | `BACKGROUND_PRIMARY`  | Nested wells, amethyst accents — not button fill    |
| Elevated surface | `BACKGROUND_ELEVATED` | Modal panels, nested containers                     |
| Button fill      | `BUTTON_FILL`         | Menu / settings buttons — lifted Prussian `#1e3054` |
| Button hover     | `BUTTON_HOVER`        | Hover / pressed-adjacent — `#2a4068`                |
| Primary accent   | `ACCENT_PRIMARY`      | 2px borders, selected tab, key actions              |
| Success / live   | `ACCENT_SUCCESS`      | Connected, speaking, confirmed                      |
| Primary text     | `TEXT_PRIMARY`        | Titles, labels, body                                |
| Muted text       | `TEXT_MUTED`          | Secondary labels, hints                             |
| Scrim            | `SCRIM`               | Overlay dimmer over gameplay                        |
| Health fill      | `HEALTH_FILL`         | Status-bar fill when `fill_swatch` is Health        |
| Mist             | `MIST`                | Toggle on-track / soft highlight (`Swatch.MIST`)    |




## Component patterns



### Overlay stack

1. `ColorRect` scrim — `UiPalette.SCRIM`, full viewport, `mouse_filter` as needed.
2. Centered `PanelContainer` — `UiPalette.panel_style()` or equivalent StyleBox with `BACKGROUND_ELEVATED` + `BORDER_DEFAULT`.
3. Inner `MarginContainer` — 16–20px margins.



### Buttons

- **Paint (shared):** Theme `Button` — `BUTTON_FILL` (lifted Prussian), `BORDER_DEFAULT` 2px, 8px radius. Hover uses `BUTTON_HOVER`. Do not fill buttons with Amethyst on Prussian panels.
- **Chrome (once):** `[scenes/ui/scaffolding/menu_button.tscn](../../scenes/ui/scaffolding/menu_button.tscn)` — navy fill, bronze border, icon + label (v6).
- **Copy (per use):** Instance the prefab and override `text` / `icon` / `theme_type_variation` / `show_outline` / `outline_swatch` on that instance only. Do not edit the prefab unless every instance should change.
- Settings footer / compact controls stay stock themed `Button`s (different size, no menu chrome).



### Status / resource bars

- **Generic:** `[scenes/ui/scaffolding/status_bar.tscn](../../scenes/ui/scaffolding/status_bar.tscn)` — title, value label, increment ticks, optional tick numbers. Inspector: `tick_divisions`, `show_title`, `show_value_label`, `show_tick_labels`, `bar_theme_variation`, `track_swatch`, `fill_swatch` (palette fill, including Health Crimson), `show_outline` + `outline_swatch`, and flare placements + `flare_swatch`.
- **Script API:** `set_value` / `set_maximum` / `set_amount(current, maximum)` snap the fill. `tween_value` / `tween_amount` animate it. `get_value` / `get_maximum` read the current range.
- **Binding:** Bars do not poll. Call the setters, or pass the local `Health` into `GameHud.configure(...)` so the HUD HP bar follows `Health.changed` (damage and heal).
- **Health:** `[health_bar.tscn](../../scenes/ui/scaffolding/health_bar.tscn)` — `HP` label, HealthBar fill, increment lines, no numeric tick row (v11).
- Ticks redraw on resize / export change only — not every frame.
- **Flares:** `[title_flare.tscn](../../scenes/ui/scaffolding/title_flare.tscn)` — `show_rule`, `diamond_align` (Left / Center / Right), `diamond_swatch`.



### Typography

- Headings and body on dark panels: `TEXT_PRIMARY`.
- Supporting copy: `TEXT_MUTED`.
- Disabled controls: `TEXT_DISABLED`.
- Do not use pure white or legacy gold RGB tuples in new UI — map to palette tokens.
- Prefer `[menu_label.tscn](../../scenes/ui/scaffolding/menu_label.tscn)` over raw Labels — Inspector `text_style` picks Title (bronze), Body (snow), Muted, or Caption (disabled-weight).



### Tabs and toggles

- Selected tab font: `TEXT_PRIMARY` or a lightened `ACCENT_PRIMARY`.
- Unselected: `TEXT_MUTED`.
- Hover: between muted and primary.
- Active toggle / connected state may use `ACCENT_SUCCESS` for the indicator.
- Settings and other multi-page chrome use `[menu_tabs.tscn](../../scenes/ui/scaffolding/menu_tabs.tscn)` (or attach `menu_tabs.gd` to a `TabContainer`). Inspector: `tab_titles`, `editor_tab`, `selected_swatch` / `hover_swatch` / `unselected_swatch`, `muted_alpha`. Runtime: `set_selected_tab` / `get_selected_tab`; listen on built-in `tab_changed` / `tab_selected`.
- On/off rows instance `[toggle_switch.tscn](../../scenes/ui/scaffolding/toggle_switch.tscn)` — pill only (no panel). Inspector: `show_outline`, `outline_swatch`, `on_swatch` (default Mist), `off_swatch` (default Ink), `thumb_swatch` (default Snow). All `UiPalette.Swatch`. Two-way choices instance `[toggle_slider.tscn](../../scenes/ui/scaffolding/toggle_slider.tscn)`. Host lobby uses the slider for Steam vs LAN.
- Color rows instance `[color_picker.tscn](../../scenes/ui/scaffolding/color_picker.tscn)` — Inspector `picker_size`, `show_outline`, `outline_swatch`, `edit_alpha_channel`.
- Volume / opacity / numeric rows instance `[value_slider.tscn](../../scenes/ui/scaffolding/value_slider.tscn)` — HSlider + clickable `LineEdit`, with division marks drawn into the track. Inspector: `min_value` / `max_value`, `default_value` (+ tool buttons Set Current as Default / Reset to Default), `tick_divisions` (interior dividers: 1 = halves, 2 = thirds, …), `show_tick_labels`, `snap_to_divisions`, `value_kind` (Float / Int), `show_as_percent` (1.0 = 100% unity — mic dial is 0–2 so midpoint is 100%; past midpoint eases up to ~5× hearback/VoIP gain), `step_size`, `show_outline` / `outline_swatch`, `tick_swatch` / `tick_label_swatch`. Runtime: `value_changed`, `set_value_no_signal`, `reset_to_default`, `set_current_as_default`.
- Outlined scaffolding (`menu_button`, `hud_slot`, `status_bar`, `toggle_slider`, `toggle_switch`, `color_picker`, `value_slider`, inventory / spell slots): Inspector `show_outline` and `outline_swatch` (`UiPalette.Swatch`, including Health). Each instance duplicates its StyleBoxes so one button can be bronze-rimmed and another crimson without editing the prefab.



## Do / don't

**Do**

- Reference `UiPalette` or `palette.json` when adding or restyling UI.
- Keep bronze borders at 2px on framed panels and primary buttons.
- Use consistent corner radii (8 buttons, 10 panels).

**Don't**

- Introduce new accent hues for menus without updating this doc and `palette.json`.
- Pull gameplay or environment colors into overlay chrome.
- Scatter one-off `Color(...)` literals in UI scripts when a semantic token exists.



## Editable screens (open these in the 2D editor)

Packed scenes stay visible so you can layout chrome without playing. Runtime `_ready()` hides overlays. Instances under `game_app.tscn` / `match.tscn` stay `visible = false` so they do not cover other states.


| Screen       | Scene to open                                                                        |
| ------------ | ------------------------------------------------------------------------------------ |
| Main menu    | `scenes/menu.tscn`                                                                   |
| Pause        | `scenes/ui/pause_menu.tscn` (settings child stays hidden — edit settings below)      |
| Settings     | `scenes/ui/settings_panel.tscn`                                                      |
| Player menu  | `scenes/ui/player_menu.tscn` — Inspector `editor_tab` for Inventory / Spells / Guide |
| Lobby (host) | `scenes/ui/lobby_host.tscn` or `lobby_panel.tscn`                                    |
| Lobby (join) | `scenes/ui/lobby_join.tscn` — or Inspector `editor_layout` on `lobby_panel.tscn`     |


Slot prefabs: `inventory_slot.tscn`, `spell_menu_slot.tscn`, `lobby_player_row.tscn`.

## Migrating existing UI

Main menu, pause, settings, lobby, player menu, and HUD chrome inherit the project Theme. When touching leftover screens (books), drop inline RGB StyleBoxes and use `UiPalette` / Theme type variations.

## Theme + prefab workflow

No editor plugin. Compose in the FileSystem and scene tree.

```
UiPalette → Theme     fill, border, fonts (shared)
scaffolding/*.tscn    structure (diamonds, ticks, size)
menu / HUD scenes     instances + text/icon/export overrides
```

1. Edit colors in `[scripts/ui/ui_palette.gd](../../scripts/ui/ui_palette.gd)` and `[resources/ui/palette.json](../../resources/ui/palette.json)`.
2. Rebuild the Theme: `godot --headless --path . --script res://tools/generate_ui_theme.gd`
3. Edit a prefab under `[scenes/ui/scaffolding/](../../scenes/ui/scaffolding/)` for shape. Prefabs reference the Theme (so the 2D editor shows paint without copied StyleBoxes).
4. Drag that `.tscn` into a menu or HUD. Override `text` / `icon` / exports only. Keep instances linked.


| Prefab                 | Path                                                                           |
| ---------------------- | ------------------------------------------------------------------------------ |
| Menu button            | `scenes/ui/scaffolding/menu_button.tscn`                                       |
| Title flare            | `scenes/ui/scaffolding/title_flare.tscn` — rule on/off, diamond align + swatch |
| Settings section       | `scenes/ui/scaffolding/settings_section.tscn`                                  |
| Status / health bar    | `status_bar.tscn`, `health_bar.tscn`                                           |
| HUD slot / row         | `hud_slot.tscn`, `hud_slot_row.tscn`                                           |
| Inventory / spell slot | `inventory_slot.tscn`, `spell_menu_slot.tscn`                                  |
| Lobby player row       | `lobby_player_row.tscn`                                                        |
| Toggle switch          | `toggle_switch.tscn` — on/off CheckButton (lobby voice)                        |
| Toggle slider          | `toggle_slider.tscn` — sliding window between two labels (Steam / LAN)         |
| Color picker           | `color_picker.tscn` — outlined ColorPickerButton (crosshair color)             |
| Menu label             | `menu_label.tscn` — Inspector `text_style` (Title / Body / Muted / Caption)     |
| Menu tabs              | `menu_tabs.tscn` — TabContainer with titles, editor tab, palette font swatches |
| Value slider           | `value_slider.tscn` — track ticks + labels, max, int/float, %, editable, default |


Mockups: menus `docs/design/mockups/menus/v6-*.png`, HUD `docs/design/mockups/hud/v11-hud.png`.

## Extending the system

When adding tokens (spacing scale, font sizes, animation timing):

1. Add to this doc with a short usage note.
2. Mirror in `palette.json` under a new top-level key if machine-readable.
3. Expose Godot constants or helpers in `ui_palette.gd`.
4. Rebuild the Theme so scenes inherit the new look.



## Authoring a new prefab

Prefabs follow a fixed contract: `@tool` script, `@export` parameters with unchanged-value
early returns, `UiPalette.Swatch` colors, no repaint from `NOTIFICATION_THEME_CHANGED`, and
coverage in `tests/unit/test_ui_scaffolding_chrome.gd`. The full workflow and a starting
template live in the `building-ui-scaffolding` skill
(`[.cursor/skills/building-ui-scaffolding/SKILL.md](../../.cursor/skills/building-ui-scaffolding/SKILL.md)`).