#!/usr/bin/env bash
# Sync locally-extracted original assets into the Godot project.
# Original game data is copyrighted: project/assets stays gitignored.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=assets_original/converted/gltf
DST=project/assets/models

mkdir -p "$DST"
cp -v "$SRC"/*.glb "$DST/" | wc -l
echo "models synced -> $DST"

# level data
mkdir -p project/assets/levels
python3 tools/zss/parse_zlv.py \
    assets_original/demo/WorldData/demo/Campain/Demo1.zlv \
    project/assets/levels/demo1.json
