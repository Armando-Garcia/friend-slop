# Steam multiplayer setup

FriendSlop uses **GodotSteam** with **`SteamMultiplayerPeer`** for all online play.

## Quick checklist

1. Install **Steam** and sign in.
2. Run **`make setup-steam`** (downloads the pinned GDExtension; ~27 MB first run).
3. Use the pinned **GodotSteam editor** in `tools/versions.env`, **or** stock Godot 4.6.3 + `make setup-steam` — not both loading Steam at once. If you use the GodotSteam editor, run `make restore-voice` once so the GDExtension manifest is disabled (the editor already includes Steam).
4. Keep `steam_appid.txt` next to the game executable (repo root for editor dev uses App ID **480**).
5. Run the game from the editor or export — host/join from the menu lobby.

## One-time setup (local dev)

From repo root:

```bash
make setup-steam    # GodotSteam GDExtension only
make setup          # Python dev tools + voice + GodotSteam
make verify-steam   # quick layout check
```

Windows PowerShell equivalents:

```powershell
powershell -ExecutionPolicy Bypass -File tools/setup_godotsteam.ps1
powershell -ExecutionPolicy Bypass -File tools/verify_godotsteam.ps1
```

Pinned version lives in `tools/versions.env`:

```ini
GODOTSTEAM_VERSION=4.19.1
GODOTSTEAM_GDE_RELEASE_TAG=v4.19.1-gde
GODOTSTEAM_GDE_ZIP=godotsteam-4.19.1-gdextension-plugin-4.4.zip
```

## Godot binary (Windows local dev)

The project pins the GodotSteam editor in `tools/versions.env`:

```ini
GODOT_EDITOR_WIN=C:/Users/iamem/Downloads/win64-g463-s164-gs4191-editor/godotsteam.463.editor.win64.exe
```

**Make / VS Code / tests** use this path when present. You can also use stock Godot 4.6.3 + `make setup-steam` instead.

Used by:

- `make test` / `make import`
- `tools/run_checks.py` (when `GODOT_PATH` is unset)
- VS Code **Godot Tools** (`.vscode/settings.json` → `godotTools.editorPath`)

## CI and release builds

GitHub Actions installs GodotSteam automatically via `tools/run_setup_steam.sh` (cached under `addons/godotsteam/` and `.cache/steam-setup/`). The **test** and **release** jobs both require it before Godot import/export.

Local smoke tests mirror CI:

```bash
make test-ci      # ubuntu:24.04 container — Godot + GodotSteam + unit tests
make release-ci   # ubuntu:24.04 container — Godot + GodotSteam + Linux export
```

## Manual smoke test (two Steam accounts)

1. Account A: **Host Game** → note **Lobby ID** or click **Invite**.
2. Account B: accept invite or paste Lobby ID → **Connect**.
3. Host clicks **Start Game** — both clients should load the maze.

## Export notes

- Copy `steam_appid.txt` into the export output directory (replace `480` with your App ID before release).
- Run `make setup-steam` before export so Godot bundles the GDExtension native libs.
- GitHub Actions release workflow runs GodotSteam setup before export.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| “GodotSteam not installed” in tests | Not required for `make test` — tests run offline. Use `make verify-steam` before export. |
| “GodotSteam not loaded” in game | Re-run `make setup-steam`, restart Godot |
| “Steam is not running” | Launch Steam client |
| GodotSteam "already registered" spam in Output | You are on the **GodotSteam editor** with `addons/godotsteam/godotsteam.gdextension` also enabled. Run `make restore-voice` (syncs extensions) and restart Godot — the GDExtension is disabled automatically for the GodotSteam editor. Use stock Godot + `make setup-steam` if you prefer the GDExtension instead. |
| CI fails on GodotSteam download | Check Codeberg availability; cache key uses `tools/versions.env` |

See also `docs/adr/002-steam-p2p-transport.md`.
