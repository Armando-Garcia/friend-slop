---
name: serious-wiz-biz-ui
description: >-
  Iterate Serious Wiz Biz UI mockups (menus, spellbook, hud, iconography).
  Use when generating or revising UI aesthetic references, menu/HUD mockups,
  icon sheets, or advancing mockup generations under docs/design/mockups/.
---

# Serious Wiz Biz UI mockups

Game title: **Serious Wiz Biz** (always use this exact title in mockups; never FriendSlop or other placeholders).

## Hard constraints (verbatim)

1. No references to trains, machines, or people. This is not a hyper realistic game, and this promises something I wont deliver.
2. The title of the game should be "Serious Wiz Biz"
3. lets move the version to the left side so that it auto sorts

**Clarifications**

- No people / human silhouettes / faces. Animals as *symbolic glyphs* (e.g. owl) are allowed when specified.
- No trains / railroads / locomotives / factories / robots / engine machinery.
- **Exception:** a simple **settings gear** glyph is allowed when the user asks for it (abstract UI control, not industrial machinery).
- Furniture and objects (conference table, door, briefcase, book) are fine.

## Pipeline layout

```
docs/design/mockups/
  menus/              # home, pause, settings screens
  spellbook/          # latest locked book set only
  hud/                # HUD screen mockups
  iconography/
    (sheets live here as separate files per role)
```

Filename pattern (version first for sorting):

```
vN-<role>.png
```

Iconography roles (separate files — do not dump everything into one mega-sheet):

| File | Contents |
|------|----------|
| `vN-menu-icons.png` | Main-menu actions only |
| `vN-hud-icons.png` | In-game HUD pips / status / cursor |
| `vN-item-icons.png` | Inventory / item glyphs |
| `vN-spell-slot-icons.png` | Spell hotbar / slot chrome + spell marks |

Also: `vN-home-menu.png`, `vN-pause-menu.png`, `vN-settings.png`, `vN-hud.png`, etc.

## Icon craft rules

1. **Same size and scale** — every icon on a sheet sits in an identical invisible square canvas (same bounding box). No one glyph larger than another. Align optical centers. Leave equal padding inside each cell.
2. **Filled body** — chunky filled shapes with soft shading; avoid thin line-only icons and heavy circular leather frames around every glyph.
3. **Role colors** — menu / HUD / items / spell slots may use different fills; within a sheet, keep a coherent palette.
4. **Door** — hinged and attached to the frame (never floating off-hinge).
5. **Spellbook / spell-slot book marks** — match locked book reference: dark chocolate leather, gold corners, purple jewels / ribbon (`spellbook/v3-spellbook.png`).
6. Read latest icon sheets + `NOTES-v*.md` before regenerating.

### HUD layout (locked direction)

Bottom chrome for `hud/vN-hud.png`:

- **Health** section (HP bar only) — **no mana**
- **4 spell** quick slots (equal size)
- **4 item** quick slots (equal size, same scale as spell slots)
- No people portraits, no trains/clocks/factory chrome
- Icon language matches individual `v11-icon-*.png` / current iconography (filled, no snow, no decorative stars)

Generate **one icon per file** before any atlas. No backgrounds, text, borders, frames, or star emblems littered on props.

```
iconography/vN-icon-host.png
iconography/vN-icon-join.png
iconography/vN-icon-settings.png
iconography/vN-icon-book.png
iconography/vN-icon-exit.png
```

Atlas packing comes later (separate step).

### Locked main-menu glyphs

| Action | Glyph |
|--------|--------|
| Host | Long conference table (empty — no people) |
| Join | Owl taking flight (no chest star) |
| Settings | Gear (allowed exception; v10 gear look) |
| Book | Leather spellbook (chocolate + gold corners + purple jewel/ribbon; no star plate) |
| Exit | Hinged arched door like v8 (no star, no snow) |

No snow/frost. No decorative stars on furniture/creatures/doors unless explicitly requested.

## Visual direction

- **Colorway:** ink `#06080f`, navy `#14213d`, honey bronze `#e2ab43`, snow `#f6efee`, hunter green `#355e3b`, dark amethyst `#261342`. Quiet negative space.
- **Not:** futuristic neon/glass; railroad / bank-vault over-ornament; photoreal cinematic stills.
- **Spellbook screens:** leather + gold + purple jewels + bookmark; keep only the latest generation in `spellbook/`.
- **Menus:** shared chrome; generate **iconography files first**, then menu mockups that use them.

Written tokens: `docs/design/ui-aesthetic.md`, `resources/ui/palette.json`, `scripts/ui/ui_palette.gd`.

## How to iterate

1. Read `docs/design/mockups/README.md` and latest `NOTES-v*.md`.
2. Pick system(s): `menus`, `iconography`, `hud`, `spellbook`.
3. Next version `N` from existing `v*-` prefixes in that folder.
4. Generate with equal-scale rules + hard constraints + title.
5. Save as `vN-<role>.png` under the correct folder.
6. **Spellbook only:** replace older book files so the folder holds the latest set only.
7. Write `NOTES-vN.md` (what changed / locked).
8. Do not overwrite prior menu/hud/iconography versions.

## Icon → menu order

1. `iconography/vN-menu-icons.png` (and other roles if needed).
2. `menus/vN-home-menu.png` (etc.) using those glyphs.

## Prompt reminders

- Title: `Serious Wiz Biz`
- Equal icon bounding boxes / scale
- No people, trains, factories, robots; gear only for Settings when requested
- Flat premium game UI, not photoreal
