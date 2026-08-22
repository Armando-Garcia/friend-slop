# UI design aesthetic

**Canonical reference** for UI styling — linked from [AGENTS.md](../../AGENTS.md) for all AI assistants (Cursor, Claude, etc.).

Curated palette and usage rules for **overlays, menus, settings, lobby, pause flow, and HUD chrome**. World geometry, spell VFX, and monster lookdev are out of scope unless explicitly noted.

Machine-readable palette: [`resources/ui/palette.json`](../../resources/ui/palette.json)  
Godot constants and style helpers: [`scripts/ui/ui_palette.gd`](../../scripts/ui/ui_palette.gd)

## Palette

| Name | Hex | Role |
|------|-----|------|
| Ink Black | `#06080f` | Deepest backdrop, scrim base |
| Dark Amethyst | `#261342` | Primary menu / panel fill |
| Prussian Blue | `#14213d` | Elevated surfaces, nested panels, tabs |
| Hunter Green | `#355e3b` | Success, active-positive states (e.g. voice live) |
| Honey Bronze | `#e2ab43` | Primary accent — borders, focus, CTAs |
| Snow | `#f6efee` | Primary text on dark surfaces |

## Mood

Gothic arcane library at night: deep purples and blues, warm bronze trim, readable snow text. Panels feel like bound tomes or warded glass — framed, not flat.

## Semantic tokens

Use `UiPalette` constants instead of hard-coded RGB in new UI work:

| Token | Constant | Typical use |
|-------|----------|-------------|
| Deep background | `BACKGROUND_DEEP` | Full-screen menu backdrop |
| Primary surface | `BACKGROUND_PRIMARY` | Button fill, card base |
| Elevated surface | `BACKGROUND_ELEVATED` | Modal panels, nested containers |
| Primary accent | `ACCENT_PRIMARY` | 2px borders, selected tab, key actions |
| Success / live | `ACCENT_SUCCESS` | Connected, speaking, confirmed |
| Primary text | `TEXT_PRIMARY` | Titles, labels, body |
| Muted text | `TEXT_MUTED` | Secondary labels, hints |
| Scrim | `SCRIM` | Overlay dimmer over gameplay |

## Component patterns

### Overlay stack

1. `ColorRect` scrim — `UiPalette.SCRIM`, full viewport, `mouse_filter` as needed.
2. Centered `PanelContainer` — `UiPalette.panel_style()` or equivalent StyleBox with `BACKGROUND_ELEVATED` + `BORDER_DEFAULT`.
3. Inner `MarginContainer` — 16–20px margins.

### Buttons

- Normal: `BACKGROUND_PRIMARY` fill, `BORDER_DEFAULT` 2px border, 8px corner radius.
- Hover: lighten fill toward `BACKGROUND_ELEVATED`, border toward `BORDER_HOVER`.
- Pressed: slightly darker fill than normal; keep bronze border.
- Prefer `UiPalette.button_style()` in scripts; match the same values in `.tscn` sub-resources when authoring in the editor.

### Typography

- Headings and body on dark panels: `TEXT_PRIMARY`.
- Supporting copy: `TEXT_MUTED`.
- Disabled controls: `TEXT_DISABLED`.
- Do not use pure white or legacy gold RGB tuples in new UI — map to palette tokens.

### Tabs and toggles

- Selected tab font: `TEXT_PRIMARY` or a lightened `ACCENT_PRIMARY`.
- Unselected: `TEXT_MUTED`.
- Hover: between muted and primary.
- Active toggle / connected state may use `ACCENT_SUCCESS` for the indicator.

## Do / don't

**Do**

- Reference `UiPalette` or `palette.json` when adding or restyling UI.
- Keep bronze borders at 2px on framed panels and primary buttons.
- Use consistent corner radii (8 buttons, 10 panels).

**Don't**

- Introduce new accent hues for menus without updating this doc and `palette.json`.
- Pull gameplay or environment colors into overlay chrome.
- Scatter one-off `Color(...)` literals in UI scripts when a semantic token exists.

## Migrating existing UI

Legacy screens (e.g. main menu, lobby) already approximate this look with ad-hoc gold borders. When touching those files, align values to `UiPalette` rather than tweaking RGB by eye.

## Extending the system

When adding tokens (spacing scale, font sizes, animation timing):

1. Add to this doc with a short usage note.
2. Mirror in `palette.json` under a new top-level key if machine-readable.
3. Expose Godot constants or helpers in `ui_palette.gd` (or a sibling `ui_theme.gd` if the file grows).
