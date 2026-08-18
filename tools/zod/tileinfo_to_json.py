#!/usr/bin/env python3
"""Convert zod planet .tileinfo binaries to JSON lookup tables.

The original per-tile effect map (palette_tile_info, 12 bytes packed per
tile, 480 tiles) tells us which terrain tiles are water / impassable.
Scene-based maps derive navigation from the PAINTED tiles via these
tables, so editing terrain in the Godot editor updates passability
automatically. Output: project/assets/tilesets/tileinfo_<planet>.json
as { "<tile index>": [water, passable] }.
"""
import json
import struct
import sys
from pathlib import Path

TILEINFO_FIELDS = struct.Struct("<6BHBhB")
PLANETS = ["desert", "volcanic", "arctic", "city", "jungle"]


def convert(tileinfo_path: Path) -> dict:
    raw = tileinfo_path.read_bytes()
    out = {}
    for index in range(len(raw) // TILEINFO_FIELDS.size):
        w, p, _u, _r, _e, _we, _nxt, _tracks, _crater, _starter = \
            TILEINFO_FIELDS.unpack_from(raw, index * TILEINFO_FIELDS.size)
        out[str(index)] = [bool(w), bool(p)]
    return out


def main() -> None:
    src_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else \
        Path("assets_original/zod/planets")
    dst_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else \
        Path("project/assets/tilesets")
    dst_dir.mkdir(parents=True, exist_ok=True)
    for planet in PLANETS:
        src = src_dir / f"{planet}.tileinfo"
        if not src.exists():
            # the working asset set keeps them next to the tilesets
            src = Path("project/assets/z/planets") / f"{planet}.tileinfo"
        if not src.exists():
            print(f"skip {planet}: no .tileinfo found")
            continue
        table = convert(src)
        dst = dst_dir / f"tileinfo_{planet}.json"
        dst.write_text(json.dumps(table))
        blocked = sum(1 for w, p in table.values() if not p)
        water = sum(1 for w, _p in table.values() if w)
        print(f"{planet}: {len(table)} tiles, {blocked} impassable, {water} water -> {dst}")


if __name__ == "__main__":
    main()
