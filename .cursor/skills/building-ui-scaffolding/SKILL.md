---
name: building-ui-scaffolding
description: >-
  Builds reusable pre-baked UI widgets under scenes/ui/scaffolding with
  inspector-tweakable @export parameters, UiPalette swatch colors, and unit-test
  coverage. Use when creating or restyling menu, HUD, overlay, lobby, or settings
  chrome, adding a scaffolding prefab, exposing a new widget parameter, or wiring
  a widget into the theme, palette, or test suite.
---

# Building UI scaffolding

Every piece of UI chrome in this repo is a **prefab scene + `@tool` script** whose look is
driven by `@export` parameters and `UiPalette.Swatch` colors. Designers drag the prefab in
and tune it in the Inspector; nobody edits colors or geometry in a consumer scene.

Read [docs/design/ui-aesthetic.md](../../../docs/design/ui-aesthetic.md) for the palette,
semantic tokens, and the current prefab inventory. This skill covers how to *build* one.

## Before adding anything

Check the prefab table in `docs/design/ui-aesthetic.md`. Prefer adding an `@export` to an
existing widget over creating a near-duplicate. A new prefab is justified when the widget
owns a distinct silhouette or behavior, not just different values.

## 1. Script contract

Location: `scripts/ui/scaffolding/<name>.gd`

```gdscript
@tool
extends PanelContainer

## One line on what this widget owns.

const DEFAULT_SIZE := Vector2i(200, 32)

@export var widget_size: Vector2i = DEFAULT_SIZE:
	set(value):
		var next := Vector2i(maxi(value.x, 32), maxi(value.y, 16))
		if next == widget_size:
			return
		widget_size = next
		custom_minimum_size = Vector2(widget_size)
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


func _ready() -> void:
	_apply_chrome()


func _apply_chrome() -> void:
	if not is_node_ready():
		return
	UiPalette.paint_panel_outline(self, show_outline, outline_swatch, 1)
```

Rules this encodes:

- **`@tool`** so the widget renders while authoring the consumer scene.
- **Every setter early-returns when the value is unchanged.** Without this, assigning the
  same value repaints, and repaints are not free.
- **Every setter routes to one `_apply_chrome()`**, which guards on `is_node_ready()`.
  No `_queue_chrome`, no deferred coalescing, no reentrancy flags — the guards above make
  them unnecessary.
- **Colors are `UiPalette.Swatch` exports**, never literal hex and never a raw `Color`
  export. Swatches keep the widget inside the palette and let the Inspector show names.
- **Sizes are `Vector2i` exports** with a `DEFAULT_` const and `maxi()` clamps, so an
  instance can shrink a widget without forking the prefab.

### Never repaint from NOTIFICATION_THEME_CHANGED

Writing a theme override re-emits `NOTIFICATION_THEME_CHANGED`, so a handler that repaints
re-enters itself until GDScript aborts at 1024 frames — and each abort prints a full
backtrace, which turns a test run into a hang. Repaint from `_ready()` and from setters.

`tools/run_checks.py` fails the lint stage on this shape, before Godot starts.

## 2. Drawing rules

**Default: theme styleboxes.** Use `UiPalette.paint_button_outline()` or
`paint_panel_outline()`. They read the pristine Theme box, duplicate it, and apply the
outline as a local override, so the widget keeps tracking the Theme.

**Custom silhouettes: `_draw()` with a cached `StyleBoxFlat`.**

```gdscript
var _track_box := StyleBoxFlat.new()

func _draw() -> void:
	_track_box.bg_color = UiPalette.swatch_color(fill_swatch)
	_track_box.set_corner_radius_all(int(size.y * 0.5))
	_track_box.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
```

`StyleBoxFlat` rounds and antialiases the whole shape in one pass. Two things to avoid:

- **Never rasterize `Image` / `ImageTexture` per repaint.** That was the original toggle
  switch and it burned CPU on every property change.
- **Never hand-composite a silhouette** from `draw_circle` plus `draw_rect`. The circles
  antialias and the rect does not, so you get seams at the tangents and a blurred edge
  wherever two shapes stack.

Cache the `StyleBoxFlat` as a member — `_draw()` runs every frame while a tween animates.

## 3. Scene contract

Location: `scenes/ui/scaffolding/<name>.tscn`

- Root node is the closest built-in Control (`Button`, `PanelContainer`, `CheckButton`…),
  named in PascalCase, with the script attached.
- Root sets `theme = ExtResource(...)` pointing at
  `resources/ui/serious_wiz_biz_theme.tres`.
- Children are named so the scene tree explains the widget — someone clicking through the
  dock should see the structure without reading the script.
- Keep the `uid://` stable once committed; consumer scenes reference it.

## 4. Theme and palette changes

**New theme entry** (a stylebox or type variation): edit
`scripts/ui/ui_theme_builder.gd`, then regenerate the baked resource:

```bash
godot --headless --path . --script res://tools/generate_ui_theme.gd
```

**New swatch**: update all three in lockstep, or the pipeline test fails.

| File | Change |
|------|--------|
| `resources/ui/palette.json` | Add the color entry |
| `scripts/ui/ui_palette.gd` | Add the `const`, **append** to `Swatch`, add a `swatch_color()` arm |
| `docs/design/ui-aesthetic.md` | Add the palette row |

`Swatch` values serialize as ints, so **only append** — inserting mid-enum silently
recolors every scene that already picked one.

## 5. Test coverage

Two suites guard this system. A new widget must land in the first one.

**`tests/unit/test_ui_scaffolding_chrome.gd`** — runtime behavior and loop safety:

1. Add a `preload` const: `const MyWidgetScene := preload("res://scenes/ui/scaffolding/my_widget.tscn")`
2. Add a `_churn(tree, MyWidgetScene.instantiate())` line to `_test_export_churn_terminates`.
3. Add any **new export names** to `_churn_writes()` so they actually get hammered.
4. If the widget has a `*_size` export, assert it drives `custom_minimum_size` in
   `_verify_settled()`.

**`tests/unit/test_ui_palette_pipeline.gd`** — token pipeline. Extend
`CHECKED_STYLEBOXES` or `CHECKED_COLORS` when adding a theme entry, and
`_swatch_by_json_id()` when adding a swatch.

Suites are registered in `tests/test_suites.tree.txt` (needs a `SceneTree`) and
`tests/test_suites.unit.txt` (pure). Tests take a failure-count return and `push_error` on
failure; they do not use an assertion framework.

## 6. Verify

```bash
python tools/run_checks.py
```

This runs gdlint, the UI repaint-loop guard, the GDScript analyzer, then the Godot suite.
Unit tests are **skipped while the Godot editor is open** — close it for the full run, or
use `--lint-only` for a fast pass.

When changing a guard or an invariant, confirm the test actually fails without the fix:
inject the bug, run, see the named failure, revert. A test that has never failed has not
been tested.

## Checklist

```
- [ ] Reused an existing prefab, or justified a new one
- [ ] @tool script under scripts/ui/scaffolding/
- [ ] Every visual knob is an @export with an unchanged-value early return
- [ ] All setters route to one is_node_ready()-guarded _apply_chrome()
- [ ] Colors are UiPalette.Swatch exports, no literal hex
- [ ] No repaint from NOTIFICATION_THEME_CHANGED
- [ ] No per-repaint Image/ImageTexture, no circle+rect compositing
- [ ] Scene under scenes/ui/scaffolding/ with the shared theme on the root
- [ ] Theme regenerated if ui_theme_builder.gd changed
- [ ] palette.json + ui_palette.gd + ui-aesthetic.md in lockstep if a swatch changed
- [ ] Added to the churn list and _churn_writes() in test_ui_scaffolding_chrome.gd
- [ ] Prefab table in docs/design/ui-aesthetic.md updated
- [ ] python tools/run_checks.py passes
```
