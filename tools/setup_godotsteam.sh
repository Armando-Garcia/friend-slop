#!/usr/bin/env bash
# Installs GodotSteam GDExtension for FriendSlop (Godot 4.6.x + stock Godot editor/exports).
# Run from repo root: bash tools/setup_godotsteam.sh
#
# Downloads ~27 MB on first run; later runs use .cache/steam-setup/ and skip re-download
# when addons/godotsteam/ is already present.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tools/load_versions.sh
source "$ROOT/tools/load_versions.sh"
load_versions "$ROOT/tools/versions.env"

CACHE="$ROOT/.cache/steam-setup"
ADDONS_DIR="$ROOT/addons/godotsteam"
GDE="$ADDONS_DIR/godotsteam.gdextension"
GDE_DISABLED="$ADDONS_DIR/godotsteam.gdextension.disabled"
EDITOR_PANEL="$ADDONS_DIR/editor/steamworks_panel.tscn"

godotsteam_complete() {
	local has_manifest=0
	[[ -f "$GDE" || -f "$GDE_DISABLED" ]] && has_manifest=1
	[[ "$has_manifest" -eq 1 \
		&& -f "$EDITOR_PANEL" \
		&& -f "$ADDONS_DIR/win64/libgodotsteam.windows.template_debug.x86_64.dll" \
		&& -f "$ADDONS_DIR/linux64/libgodotsteam.linux.template_debug.x86_64.so" ]]
}

GODOTSTEAM_URL="https://codeberg.org/godotsteam/godotsteam/releases/download/${GODOTSTEAM_GDE_RELEASE_TAG}/${GODOTSTEAM_GDE_ZIP}"

mkdir -p "$CACHE" "$(dirname "$ADDONS_DIR")"

download_if_missing() {
	local url="$1"
	local dest="$2"
	if [[ -f "$dest" ]]; then
		echo "Using cached $(basename "$dest")"
		return
	fi
	echo "Downloading $url ..."
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL -o "$dest" "$url"
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O "$dest" "$url"
	else
		echo "error: need curl or wget to download GodotSteam." >&2
		exit 1
	fi
}

require_unzip() {
	if command -v unzip >/dev/null 2>&1; then
		return
	fi
	echo "error: unzip is required to extract GodotSteam." >&2
	exit 1
}

find_godotsteam_root() {
	local search_root="$1"
	local candidates=(
		"$search_root/addons/godotsteam"
		"$search_root/godotsteam"
		"$search_root"
	)
	local candidate
	for candidate in "${candidates[@]}"; do
		if [[ -f "$candidate/godotsteam.gdextension" ]]; then
			echo "$candidate"
			return 0
		fi
	done
	return 1
}

ZIP_PATH="$CACHE/$GODOTSTEAM_GDE_ZIP"

if godotsteam_complete; then
	echo "GodotSteam already installed at $ADDONS_DIR"
else
	if [[ -d "$ADDONS_DIR" ]]; then
		echo "GodotSteam install incomplete (missing editor panel or libs); reinstalling ..."
	fi
	require_unzip
	download_if_missing "$GODOTSTEAM_URL" "$ZIP_PATH"
	echo "Extracting GodotSteam to addons/ ..."
	TEMP_EXTRACT="$(mktemp -d)"
	trap 'rm -rf "$TEMP_EXTRACT"' EXIT
	unzip -q "$ZIP_PATH" -d "$TEMP_EXTRACT"
	if [[ -d "$TEMP_EXTRACT/addons/godotsteam" ]]; then
		rm -rf "$ADDONS_DIR"
		mkdir -p "$ROOT/addons"
		cp -R "$TEMP_EXTRACT/addons/godotsteam" "$ADDONS_DIR"
	else
		SOURCE="$(find_godotsteam_root "$TEMP_EXTRACT")"
		rm -rf "$ADDONS_DIR"
		mkdir -p "$(dirname "$ADDONS_DIR")"
		cp -R "$SOURCE" "$ADDONS_DIR"
	fi
	echo "GodotSteam installed to $ADDONS_DIR"
fi

if [[ ! -f "$ADDONS_DIR/linux64/libgodotsteam.linux.template_debug.x86_64.so" ]]; then
	echo "error: GodotSteam Linux x86_64 libraries missing under $ADDONS_DIR/linux64/" >&2
	exit 1
fi

if [[ ! -f "$ADDONS_DIR/win64/libgodotsteam.windows.template_debug.x86_64.dll" ]]; then
	echo "error: GodotSteam Windows x86_64 libraries missing under $ADDONS_DIR/win64/" >&2
	exit 1
fi

if [[ ! -f "$ROOT/steam_appid.txt" ]]; then
	echo "error: steam_appid.txt missing at repo root." >&2
	exit 1
fi

echo ""
echo "Done. GodotSteam ${GODOTSTEAM_VERSION} ready (GDExtension ${GODOTSTEAM_GDE_RELEASE_TAG})."
echo "Fully quit Godot, reopen the project, then host/join from the menu lobby."
