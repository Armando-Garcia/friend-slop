# Instructions for AI assistants

Tool-agnostic guidance for this repo lives under **`docs/`**. Edit those files when curating conventions — not the tool-specific shims (`.cursor/rules/`, `CLAUDE.md`), which only point here.

## UI design (menus, overlays, HUD)

**Read before changing UI chrome:** [docs/design/ui-aesthetic.md](docs/design/ui-aesthetic.md)

| Asset | Path |
|-------|------|
| Design guide (canonical) | `docs/design/ui-aesthetic.md` |
| Palette data (JSON) | `resources/ui/palette.json` |
| Godot tokens & helpers | `scripts/ui/ui_palette.gd` (`UiPalette`) |
| Designed widgets | `scenes/ui/scaffolding/` — drag into menus/HUD; override text/icon/exports |

**Scope:** overlays, menus, settings, lobby, pause flow, and HUD chrome.  
**Out of scope:** world geometry, spell VFX, monster lookdev (unless explicitly restyling HUD).

When extending the palette or tokens, update the guide, JSON, and `ui_palette.gd` together.

**Building a new widget:** the `building-ui-scaffolding` skill
(`.cursor/skills/building-ui-scaffolding/SKILL.md`) carries the prefab contract — `@tool`
script, inspector-tweakable `@export` parameters, `UiPalette.Swatch` colors, the repaint
rules that keep chrome out of infinite recursion, and the test suite to register in.

## Other conventions

- **Scene tree as source of truth** — prefer authored scene hierarchy over invisible script-only wiring. See `.cursor/rules/scene-tree-source-of-truth.mdc`.
- **Lint after GDScript changes** — `python tools/run_checks.py --lint-only` (or `make lint`).

## Adding new agent-facing docs

1. Add or extend a doc under `docs/` (e.g. `docs/design/` for visual systems).
2. Link it from this file with a one-line summary and path.
3. Optionally add a thin Cursor rule or tool shim that points to the doc — do not duplicate the full content.
