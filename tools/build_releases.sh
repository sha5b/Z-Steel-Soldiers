#!/usr/bin/env bash
# Build the desktop releases for all three targets from this Linux box.
#
#   tools/build_releases.sh            # all three
#   tools/build_releases.sh linux      # one target: linux | windows | macos
#
# Requirements
#   - Godot 4.7.1 (flatpak by default; override with GODOT=...)
#   - the matching EXPORT TEMPLATES, installed into
#       ~/.var/app/org.godotengine.Godot/data/godot/export_templates/4.7.1.stable/
#     (Editor > Manage Export Templates, or unzip the .tpz there)
#   - project/assets/icon/ generated: python3 tools/gog/make_icons.py
#
# WHAT YOU GET, and what you do NOT
#   linux    a single self-contained x86_64 binary (.pck embedded)
#   windows  a single self-contained .exe. Its EXPLORER FILE ICON stays
#            Godot's default: embedding a custom one needs rcedit, which
#            needs wine, which is deliberately not installed. The in-game
#            window icon is correct.
#   macos    an UNSIGNED .app inside a .zip. Cross-building this from
#            Linux is fine, but signing and notarization need a Mac, so
#            on first launch macOS will refuse it until the user does
#            right-click > Open (or removes the quarantine attribute:
#            xattr -dr com.apple.quarantine "Z Remake (1996).app").
#            A .dmg cannot be produced off a Mac.
#
# EVERY BINARY EMBEDS THE ORIGINAL BITMAP BROTHERS ART AND SOUND.
# These builds are for local use. Do not redistribute them.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/project"
BUILD="$ROOT/build"
GODOT="${GODOT:-flatpak run org.godotengine.Godot}"

if [[ ! -d "$PROJECT/assets/icon" ]]; then
	echo "!! project/assets/icon missing — run: python3 tools/gog/make_icons.py" >&2
	exit 1
fi

build_one() {
	local preset="$1" out="$2"
	mkdir -p "$(dirname "$out")"
	echo "==> $preset -> ${out#$ROOT/}"
	# --export-release implies --headless in 4.x but pass it anyway so the
	# script works over ssh with no display
	$GODOT --headless --path "$PROJECT" --export-release "$preset" "$out"
}

targets=("${@:-all}")
if [[ "${targets[0]}" == "all" ]]; then
	targets=(linux windows macos)
fi

for t in "${targets[@]}"; do
	case "$t" in
		linux)   build_one "Linux/Fedora" "$BUILD/linux/z-remake.x86_64" ;;
		windows) build_one "Windows"      "$BUILD/windows/z-remake.exe" ;;
		macos)   build_one "macOS"        "$BUILD/macos/z-remake.zip" ;;
		*) echo "unknown target: $t (want linux|windows|macos)" >&2; exit 2 ;;
	esac
done

echo
echo "built:"
find "$BUILD" -maxdepth 2 -type f -printf '  %-44p %10s bytes\n' 2>/dev/null | sed "s|$ROOT/||"
