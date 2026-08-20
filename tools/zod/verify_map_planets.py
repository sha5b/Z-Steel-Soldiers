#!/usr/bin/env python3
"""Audit (and repair) the PLANET tag on every converted map JSON.

Why this exists: the terrain byte in a zod .map is an index into a planet
table, and ours had ids 3 and 4 the wrong way round (`city` and `jungle`
swapped). Every jungle map therefore drew with the city tileset and every
city map with the jungle one — a chaotic tile jumble — and, worse, the
nav grids came from the wrong `.tileinfo`, so units and buildings stood
on cells the game believed were water or wall.

The test that finds it needs no reference data: THE MAP'S OWN OBJECTS.
A robot, vehicle or cannon placed by the level designer always stands on
walkable, non-water ground, so the correct planet is the one whose
tileinfo puts ZERO units in water or in a wall. Measured over the shipped
set with the ids swapped back:

    planet    units audited   in water   impassable
    desert         ...            0           0
    volcanic       ...            0           0
    arctic         ...            0           0
    city           ...            0           0
    jungle         ...            0           0

(Buildings are excluded on purpose: ~160 of them are BRIDGES, whose
anchor tile is water by design.)

Run:
    python3 tools/zod/verify_map_planets.py            # audit only
    python3 tools/zod/verify_map_planets.py --fix      # re-tag + rebuild

--fix rewrites `terrain` and recomputes the `passable`/`water` arrays
from the winning planet's tileinfo. It is IDEMPOTENT: the planet is
chosen by evidence every time, not by flipping a flag, so running it
twice changes nothing. The map SCENES cache the tileset per map, so
after a fix re-run:

    godot --headless --path project res://tools/build_map_resources.tscn
"""
from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAPS = ROOT / "project" / "assets" / "maps"
TILEINFO_DIRS = [
    ROOT / "assets_original" / "zod" / "planets",
    ROOT / "project" / "assets" / "z" / "planets",
]
PLANETS = ["desert", "volcanic", "arctic", "city", "jungle"]
UNIT_TYPES = {"robot", "vehicle", "cannon"}
TILEINFO_FIELDS = struct.Struct("<6BHBhB")  # see tools/zod/map_to_json.py


def load_tileinfo(planet: str) -> list[tuple[bool, bool]]:
    """[(is_water, is_passable)] per tile index, or [] when not found."""
    for d in TILEINFO_DIRS:
        path = d / f"{planet}.tileinfo"
        if path.is_file():
            raw = path.read_bytes()
            out = []
            for i in range(len(raw) // TILEINFO_FIELDS.size):
                w, p = TILEINFO_FIELDS.unpack_from(raw, i * TILEINFO_FIELDS.size)[:2]
                out.append((bool(w), bool(p)))
            return out
    return []


def violations(data: dict, info: list[tuple[bool, bool]]) -> int:
    """Units standing in water or in a wall under this planet's table."""
    w, h, tiles = data["width"], data["height"], data["tiles"]
    bad = 0
    for o in data["objects"]:
        if o["type"] not in UNIT_TYPES:
            continue
        x, y = int(o["x"]), int(o["y"])
        if not (0 <= x < w and 0 <= y < h):
            continue
        t = tiles[y * w + x]
        if t >= len(info):
            bad += 1
            continue
        water, passable = info[t]
        if water or not passable:
            bad += 1
    return bad


def seam_score(data: dict, planet: str) -> float:
    """Tie-break by ART: terrain tiles are drawn to butt seamlessly, so
    the right sheet is the one whose neighbouring tiles' touching edges
    match. Needs Pillow; returns inf when it is not installed, and the
    caller then leaves an ambiguous map alone rather than guessing."""
    try:
        import numpy as np
        from PIL import Image
    except ImportError:
        return float("inf")
    sheet = ROOT / "project" / "assets" / "z" / "planets" / f"{planet}.png"
    if not sheet.is_file():
        return float("inf")
    a = np.asarray(Image.open(sheet).convert("RGB")).astype(np.int16)
    tiles = [a[(i // 20) * 16:(i // 20) * 16 + 16, (i % 20) * 16:(i % 20) * 16 + 16]
             for i in range(480)]
    w, h, t = data["width"], data["height"], data["tiles"]
    total = 0.0
    n = 0
    for y in range(0, h - 1, 3):
        for x in range(0, w - 1, 3):
            c = tiles[t[y * w + x] % 480]
            r = tiles[t[y * w + x + 1] % 480]
            d = tiles[t[(y + 1) * w + x] % 480]
            total += float(np.abs(c[:, 15] - r[:, 0]).mean())
            total += float(np.abs(c[15, :] - d[0, :]).mean())
            n += 2
    return total / max(n, 1)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--fix", action="store_true",
                    help="re-tag mismatched maps and rebuild passable/water")
    args = ap.parse_args()

    tables = {p: load_tileinfo(p) for p in PLANETS}
    missing = [p for p, t in tables.items() if not t]
    if missing:
        print(f"no tileinfo for {missing} — nothing to check")
        return 0

    files = sorted(MAPS.glob("*.json"))
    if not files:
        print(f"no map JSONs under {MAPS}")
        return 0

    mismatched = 0
    for f in files:
        data = json.loads(f.read_text())
        declared = str(data.get("terrain", ""))
        scored = sorted((violations(data, tables[p]), p) for p in PLANETS)
        best_bad, best = scored[0]
        declared_bad = violations(data, tables[declared]) if declared in tables else -1
        if best_bad > 0:
            continue  # no planet fits: not a mis-tag, report nothing
        clear = [p for bad, p in scored if bad == 0]
        if len(clear) > 1:
            # several planets leave every unit on walkable land (a map
            # with few units, or two tables that agree there). Break the
            # tie on the ART: 2 of the shipped maps land here.
            ranked = sorted((seam_score(data, p), p) for p in clear)
            if ranked[0][0] == float("inf"):
                print(f"{f.stem}: AMBIGUOUS ({clear}) — install Pillow to "
                      "break the tie on tile art; left as {declared}")
                continue
            best = ranked[0][1]
        if declared == best:
            continue
        mismatched += 1
        print(f"{f.stem}: tagged {declared} ({declared_bad} units misplaced) "
              f"-> {best} (0)")
        if args.fix:
            data["terrain"] = best
            info = tables[best]
            data["passable"] = [1 if info[t][1] else 0 for t in data["tiles"]]
            data["water"] = [1 if info[t][0] else 0 for t in data["tiles"]]
            f.write_text(json.dumps(data))

    print(f"{len(files)} maps checked, {mismatched} mis-tagged"
          + (" (fixed)" if args.fix and mismatched else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
