#!/usr/bin/env bash
# Render the Zod Engine's MIDI soundtrack to loopable OGG files for Godot.
#
# Requires: fluidsynth + a soundfont (e.g. Fedora: sudo dnf install
# fluidsynth fluidsynth-soundfont-gm) and oggenc/ffmpeg for compression.
#
# Usage: tools/zod/render_midi.sh
# Output: project/assets/z/music/<name>.ogg
set -euo pipefail
cd "$(dirname "$0")/../.."

SOUNDFONT="${SOUNDFONT:-/usr/share/soundfonts/FluidR3_GM.sf2}"
SRC=assets_original/zod/sounds
DST=project/assets/z/music
ENCODER="${ENCODER:-oggenc}"

if ! command -v fluidsynth >/dev/null; then
  echo "fluidsynth not found. Install it (dnf install fluidsynth" \
       "fluidsynth-soundfont-gm) and re-run." >&2
  exit 1
fi
if [ ! -f "$SOUNDFONT" ]; then
  echo "Soundfont not found at $SOUNDFONT — set SOUNDFONT=/path/to.sf2" >&2
  exit 1
fi

mkdir -p "$DST"
for mid in "$SRC"/*.MID "$SRC"/*.mid; do
  [ -f "$mid" ] || continue
  name="$(basename "$mid" | tr 'A-Z' 'a-z' | sed 's/\.mid$//')"
  if [ -f "$DST/$name.ogg" ]; then
    echo "skip $name (exists)"
    continue
  fi
  echo "render $name"
  wav="$(mktemp --suffix=.wav)"
  fluidsynth -ni -g 0.4 -F "$wav" "$SOUNDFONT" "$mid" >/dev/null
  if command -v "$ENCODER" >/dev/null && [ "$ENCODER" = "oggenc" ]; then
    oggenc -Q -o "$DST/$name.ogg" "$wav"
  elif command -v ffmpeg >/dev/null; then
    ffmpeg -loglevel error -y -i "$wav" -c:a libvorbis "$DST/$name.ogg"
  else
    cp "$wav" "$DST/$name.wav"
  fi
  rm -f "$wav"
done
echo "done -> $DST"
