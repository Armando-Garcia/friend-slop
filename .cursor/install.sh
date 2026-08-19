#!/usr/bin/env bash
# Cloud Agent install for FriendSlop (Godot 4.6.3).
# Idempotent: safe to run repeatedly and against a cached/partially-prepared VM.
# Prepares the full local dev loop documented in the Makefile + docs/STEAM_SETUP.md:
#   Python lint tooling (gdtoolkit), the pinned Godot binary, GodotSteam,
#   the gdvosk voice stack, and an initial headless asset import.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck source=tools/load_versions.sh
source "$ROOT/tools/load_versions.sh"
load_versions "$ROOT/tools/versions.env"

log() { printf '\n=== %s ===\n' "$*"; }

as_root() {
	if [[ "$(id -u)" -eq 0 ]]; then
		"$@"
	else
		sudo "$@"
	fi
}

log "System packages (Godot headless + GUI runtime)"
export DEBIAN_FRONTEND=noninteractive
as_root apt-get update -qq
as_root apt-get install -y --no-install-recommends \
	make unzip curl python3-venv \
	libfontconfig1 \
	libgl1 libglx-mesa0 libegl1 libgles2 \
	libx11-6 libxcursor1 libxinerama1 libxrandr2 libxi6 libxext6 libxrender1 \
	libasound2t64 libpulse0 libudev1

log "Python dev tooling (gdtoolkit / gdlint in .venv)"
make setup-dev

log "Pinned Godot ${GODOT_VERSION} (Linux editor binary)"
bash tools/setup_godot_linux.sh

log "Expose 'godot' on PATH for the Makefile + run_checks tooling"
GODOT_BIN="$ROOT/.cache/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64"
as_root ln -sfn "$GODOT_BIN" /usr/local/bin/godot
godot --version || true

log "GodotSteam GDExtension"
bash tools/run_setup_steam.sh

log "Voice stack (gdvosk GDExtension + Vosk speech model)"
bash tools/run_setup_voice.sh

log "Headless import of project assets (.godot cache)"
bash tools/run_godot_import.sh

log "FriendSlop environment ready — try: make lint / make test"
