#!/usr/bin/env python3
"""Convert Zod Engine .map files to JSON.

Layout (from Zod's zmap.cpp / zmap.h, x86 struct packing):

    map_basics (62 bytes):
        u16 width, u16 height, char name[50], u8 player_count,
        (pad) u16 object_count, u8 terrain_type, (pad) u16 zone_count
    zone_count * map_zone  (8 bytes):  u16 x, y, w, h   (tile units)
    object_count * map_object (16 bytes):
        u16 x, y; i8 owner; u8 object_type, object_id, blevel;
        u16 extra_links; i32 health_percent
    width*height * map_tile (2 bytes): u16 palette index

Tile list is column-major (index = x*height + y) as written by the
original loops: for x in width: for y in height. Palette is 20x24 tiles
of 16x16 px; terrain 0=desert 1=volcanic 2=arctic 3=city 4=jungle.

Object types: 0 rock 1 bridge 2 building 3 cannon 4 vehicle 5 robot
6 animal 7 map_item. Owners: -1 neutral .. 0 null, 1 red 2 blue 3 green
4 yellow. Robots: 0 grunt 1 psycho 2 sniper 3 tough 4 pyro 5 laser.
Buildings: 0 fort_front 1 fort_back 2 radar 3 repair 4 robot_factory
5 vehicle_factory. Cannons: 0 gatling 1 gun 2 howitzer 3 missile.
Vehicles: 0 jeep 1 light 2 medium 3 heavy 4 apc 5 mml 6 crane.
"""
import json
import struct
import sys
from pathlib import Path

TERRAIN = ["desert", "volcanic", "arctic", "city", "jungle", "city2"]
OBJ_TYPES = ["rock", "bridge", "building", "cannon", "vehicle", "robot", "animal", "map_item"]


def convert(path: Path) -> dict:
    d = path.read_bytes()
    if len(d) < 62:
        raise ValueError("too small")
    width, height = struct.unpack_from("<HH", d, 0)
    name = d[4:54].split(b"\0")[0].decode("latin-1")
    player_count = d[54]
    object_count = struct.unpack_from("<H", d, 56)[0]
    terrain = d[58]
    zone_count = struct.unpack_from("<H", d, 60)[0]
    off = 62

    zones = []
    for _ in range(zone_count):
        zones.append(dict(zip(("x", "y", "w", "h"), struct.unpack_from("<HHHH", d, off))))
        off += 8

    objects = []
    for _ in range(object_count):
        x, y, owner, otype, oid, blevel, links = struct.unpack_from("<HHbBBBh", d, off)
        health = struct.unpack_from("<i", d, off + 12)[0]
        objects.append({
            "x": x, "y": y, "owner": owner, "type": OBJ_TYPES[otype] if otype < len(OBJ_TYPES) else str(otype),
            "id": oid, "level": blevel, "health": health,
        })
        off += 16

    tiles = list(struct.unpack_from(f"<{width * height}H", d, off))
    off += width * height * 2
    if off != len(d):
        raise ValueError(f"trailing data: consumed {off} of {len(d)}")

    return {
        "name": name, "width": width, "height": height,
        "terrain": TERRAIN[terrain] if terrain < len(TERRAIN) else terrain,
        "player_count": player_count,
        "zones": zones, "objects": objects, "tiles": tiles,
    }


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else src.with_suffix(".json")
    data = convert(src)
    dst.write_text(json.dumps(data))
    from collections import Counter
    kinds = Counter(f"{o['type']}:{o['id']}" for o in data["objects"])
    print(f"{src.name}: {data['width']}x{data['height']} {data['terrain']} "
          f"| {len(data['zones'])} zones | {len(data['objects'])} objects -> {dst}")
    for k, c in kinds.most_common(10):
        print(f"   {c:3d}x {k}")


if __name__ == "__main__":
    main()
