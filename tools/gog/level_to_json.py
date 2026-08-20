#!/usr/bin/env python3
"""Convert the ORIGINAL Z (1996) campaign levels to our map JSON.

Reads the retail GOG data in `assets_original/gog/` and writes the exact
schema `tools/zod/map_to_json.py` emits, so `map_loader.gd` loads the
result unchanged.

Inputs per level NN (NN = 01..20 campaign, 26..29 + 31 skirmish):
    LEVEL{NN}.MAP    terrain, size, tileset name, forts, rocks
    CPUPLR{NN}.DAT   the territory rectangles = the schema's `zones`
    OBJECT{NN}.DAT   scenery, pickups, unmanned vehicles/cannons
    BUILD{NN}.DAT    radar / repair / robot factory / vehicle factory
    BRIDGE{NN}.DAT   bridge spans
    levels.dat       level name + which files the level uses
    <PLANET>.BLK/.PAL   tile art (only needed to re-derive the tile map)

=============================================================================
LEVEL{NN}.MAP — 56433 bytes on every one of the 25 files
=============================================================================
VERIFIED offsets (checks and numbers in docs/RESEARCH.md §6):

    0                u8    unknown (0xf7 on LEVEL01)
    1     .. 6656    region array, byte-identical copy of the one at 43377
                     (verified: d[1:6657] == d[43377:50033] on all 25 files)
    6657  .. 9416    rock array: 20 records x 138 bytes
    9417  .. 10096   constant table, identical in every level — UNKNOWN
    10097 .. 10109   char[13] tileset 1 name, e.g. "DESERT.LBM"
    10110            u8 = 1 on all 25 files
    10111 .. 10123   char[13] tileset 2 name, e.g. "DESERT2.LBM"
    10124            u8 = 1 on all 25 files
    10125            u16 width  in tiles
    10127            u16 height in tiles
    10129 .. 26512   PLANE 1: 128x128 bytes, row-major, 1 byte per cell
    26513 .. 42896   PLANE 2: 128x128 bytes, row-major, 1 byte per cell
    42897 .. 43376   480 zero bytes
    43377 .. 56432   region array: 96 records x 136 bytes

The map occupies cells [0,width) x [0,height) of both 128x128 planes;
everything outside is 0xEF in plane 1 (uncleared editor scratch shows up
outside the declared rectangle on LEVEL01/04/08 only).

TILE INDEX = plane1 + 240 * (plane2 >> 7).

    Plane 1 is the index into the level's FIRST tileset (0..239) and
    plane 2's top bit selects the SECOND tileset. That is exactly the
    480-tile layout of our `assets/z/planets/<planet>.png` sheets, so the
    computed index is already a sheet index — no remap needed.
    Verified against the 20 zod `p02_bb_orig01..20` maps (which are the
    same original levels): 96.17% of 218000 cells match exactly, versus
    66% for plane 1 alone. The residual is where the zod authors edited
    the maps for 2 players (mostly the blanked fort ground, see below).

    <PLANET>.BLK holds 512 16x16 tiles; indices 240..255 and 496..511 are
    unused padding. Dropping them gives BLK 0..239 -> sheet 0..239 and
    BLK 256..495 -> sheet 240..479. Verified by image matching every BLK
    tile against every sheet tile on all 5 planets: that rule is the
    nearest match for 480/480 tiles per planet, worst mean channel error
    2.36/255 (the .PAL is 6-bit VGA, the sheets are 8-bit, so the pixels
    are near-identical but not bit-identical — 0 exact matches).

Plane 2's low 7 bits are a per-cell class 0..63 we did NOT crack. It
correlates with terrain kind (value 7 is 50% road tiles, 9 is 72% water,
19 is 63% impassable-by-tileinfo) and every rock in the zod maps sits on
a cell whose low 7 bits are 0, but we found no reading that predicts
anything, so this converter ignores it.

Region record (136 bytes, 96 slots, in-use when byte +10 != 0xFF):
    +0  u16 x1, +2 u16 y1, +4 u16 x2, +6 u16 y2   PIXELS, multiples of 16
    +8  u16 centre_cell = (cy * 128 + cx)         proves the 128 stride
    +10 u8[] neighbour region ids, terminated by 0xFF
    +53..135  filled with the first neighbour id (an uninitialised table)
Verified: LEVEL01 region 0 rect (160,288)-(272,400) has centre tile (13,21)
and centre_cell 2701 = 21*128+13; region 1 gives 2737 = 21*128+49.
LEVEL01 has 13 regions (six 7x7 boxes plus connecting corridors), LEVEL20
has 89. This is an adjacency graph, NOT the territory grid, so it is not
what this converter writes as `zones` — see CPUPLR below. We do not know
what the original uses it for and this converter ignores it.

FORTS are not in any .DAT file. They are cut out of the tile grid: the
ground under a fort is set to PLANE-1 value 238 on every planet (which
renders as the near-black sheet tile 478). Take the 8-connected components
of (plane1 == 238) with a 10-wide bounding box and >= 90 cells; 100 cells
is a north-facing fort (zod building id 0, `fort_front`), 96 cells is a
south-facing one (id 1, `fort_back`).
Verified against the 20 zod maps: 38 of 40 forts land on the zod anchor
exactly, id included; LEVEL03's fort_back and LEVEL16's fort_front are
one row off because a stray 238 cell extends the bounding box. Every one
of the 25 levels yields exactly 2 forts.

ROCKS live at 6657 as 20 records of 138 bytes (so the array ends at 9417):

    +0  u16 x, +2 u16 y   PIXELS, top-left of the stamp; a slot is free
                          when x is 0xFFFF, when x and y are both 0, or
                          when the point is outside the map
    +4  u8, +5 u8         (2,0) on 116 of the 147 in-use records, also
                          (0,0)/(2,5)/(2,1) — meaning UNKNOWN
    +6  u16               0 on 106 records, otherwise 624..3184 — UNKNOWN
    +10 .. +137           128 bytes = a 32x32 BIT MASK, row-major,
                          4 bytes per row, most-significant bit first;
                          a set bit is a rock on cell (x/16 + col,
                          y/16 + row)

Rocks are objects in the original, not terrain — in LEVEL01 all 151 of
them sit on passable plain ground. VERIFIED against the 20 zod maps:
5963 true positives, 75 false positives, 27 false negatives out of 5990
rock objects — precision 98.76%, recall 99.55%. Levels 02/07/10/18 hold
almost all of the error, which is where zod's 2-player edits are.

UNKNOWN in the .MAP:
  * byte 0.
  * 9417..10096: four more 138-byte records plus 128 bytes of 0xFF,
    byte-identical in every level, so a constant table of some kind.
  * plane 2 bits 0..6 (above).
  * most of each 136-byte region record past the neighbour list.
  * the rock record's bytes +4, +5 and +6.

=============================================================================
CPUPLR{NN}.DAT — 2217 bytes = 73 records x 30 bytes + a 27-byte tail
=============================================================================
    +0 u16 x1, +2 u16 y1, +4 u16 x2, +6 u16 y2   TILES (not pixels)
In use when x2 > x1, y2 > y1 and the rect fits the map; the rest of the
slots are zero or 0xFFFF. The remaining 22 bytes of a record and the tail
(which ends with 40000 and 50) are unread.

These rectangles are the territory grid: they tile the map in a 3x3 to
4x4 lattice with a one-tile gutter, covering 70-84% of the map. They are
what the zod maps carry as `zones` — the record count equals the zod zone
count on ALL 20 levels (9,9,10,15,9,12,10,15,10,11,10,12,12,14,14,15,16,
14,16,16) and 101 of 249 rects are bit-identical; the other 148 differ by
one tile on one edge because the zod authors closed the gutters. We write
the raw GOG rect.

=============================================================================
OBJECT{NN}.DAT — 1500 bytes = 150 records x 10 bytes
=============================================================================
    +0 u16 x, +2 u16 y   PIXELS (0xFFFF x = free slot)
    +4 u8  type          per-planet object table, 0..61
    +5 u8  sub-value     0xFF on scenery, a small constant per hardware type
    +6 u8[4] = 0xFF      (a pointer field in the original struct)
Verified over all 25 files: 1840 of 1847 in-use records land inside the
declared map and 1844 of 1847 are 16-aligned.

The `type` byte indexes a PER-PLANET table. We recovered it by matching
every record's cell against the zod `p02_bb_orig*` maps; OBJ_COMMON and
OBJ_PLANET below carry the record count and the hit count per type.
Scenery types are anchored one tile ABOVE the cell zod uses, hardware and
pickups are not — that `dy` is part of the table. Over levels 01-20 the
table converts 1406 in-use records, 1261 of them to a known id, and 1198
of those 1261 (95.0%) land on a zod object of exactly that kind and id.

Volcanic types 13/14/15/16 (144 records) have no counterpart in any zod
map, so their zod scenery id is UNKNOWN; they are emitted as map_item 0,
which renders nothing rather than the wrong sprite.

=============================================================================
BUILD{NN}.DAT — 2800 bytes = 35 records x 80 bytes
=============================================================================
    +0  u16 x, +2 u16 y  PIXELS, the same anchor zod uses (verified below)
    +4  u8  kind         0 repair, 1 vehicle factory, 4 robot factory,
                         8 radar; 0xFF on a free/stale slot
    +5  u8  = 8 on every in-use record
    +6  u8  flags        0 / 192 / 224 on live records, 240..255 on stale
    +12 u16 max health   500 for radar+repair, 1000..5000 for factories
    +26 u16, +28 u16     2000 for factories, 1500 for radar/repair
    +22, +30, +59 u32    heap pointers from the original 32-bit build
Everything else is padding, 0xFF, or unread.

`kind` -> zod building id was read off the ground truth, not guessed:
matching in-use records against the zod maps gives 257 hits with the
right position AND the right id and ZERO position hits with a wrong id.

=============================================================================
BRIDGE{NN}.DAT — 312 bytes = 12 records x 26 bytes
=============================================================================
    +0  u16 x, +2 u16 y   PIXELS (0xFFFF = free slot)
    +4  u16 w, +6 u16 h   PIXELS; 4x6 .. 10x4 tiles
    +8  u16, +10 u16      health / max health (300, 500 or 600)
    +12 u16               0 or 16
Orientation from the span: w > h is `bridge_horz` (zod building id 7),
h > w is `bridge_vert` (id 6). Included in the 257/0 count above.

=============================================================================
levels.dat — 12240 bytes = 51 records x 240 bytes, record N = level N
=============================================================================
    +0   char[20] level name   ("Virgin Soldiers", "Psychos", ... , "Z")
    +20  char[13] map file     +33  char[13] robots file
    +46  char[13] cpu file     +59  char[13] preset2 file
    +72  char[13] preset1 file +85  u8[12]  a 0..0x12 list, ff-terminated
    +97  char[14] object file  +111 char[13] mult file
    +124 u32 = 10000           +128 u32 = 10000   (starting credits?)
    +132 char[13] build file   +145 char[14] bridge file
Records 21..25 and 30, 36 name maps that the release does not ship.

WHAT THE RELEASE DOES NOT CONTAIN: the starting armies. Every record
names `preset1.wal` / `preset2.wal`; neither file exists in the install
(Z.exe holds the string, not the data). So a converted level has its
forts, factories, bridges, scenery and unmanned hardware but no starting
robots — the fort has to build them. Nothing in LEVEL/OBJECT/BUILD/
BRIDGE/CPUPLR/levels/robots/mult holds a coordinate near either fort
(searched every u16 pair in every file, +-80 px, 0 hits).

`player_count` is the number of forts found, which is 2 on all 25 levels.
`owner` copies the zod convention that every one of their 20 maps uses:
fort_front = team 2, fort_back = team 1, everything else neutral (0).
It is a convention, not a field we read.
"""
import json
import re
import struct
import sys
from pathlib import Path

TILE_PX = 16
GRID_STRIDE = 128          # both planes are 128x128 regardless of map size
NAME1_OFF = 10097
SIZE_OFF = 10125
PLANE1_OFF = 10129
PLANE2_OFF = 26513
PLANE_LEN = GRID_STRIDE * GRID_STRIDE
SHEET1_TILES = 240         # plane 2's top bit adds this
FORT_GROUND_TILE = 238     # plane-1 value under a fort, all planets
ROCKS_OFF = 6657
ROCK_STRIDE = 138
ROCK_SLOTS = 20
ROCK_MASK_OFF = 10         # 32x32 bits, 4 bytes per row, MSB first
ROCK_MASK_SIDE = 32

LEVELS_DAT_STRIDE = 240
OBJECT_STRIDE = 10
BUILD_STRIDE = 80
BRIDGE_STRIDE = 26
CPUPLR_STRIDE = 30

# the .MAP's tileset name -> our planet name. The .BLK/.PAL basename is
# the same word except ARTIC.LBM, whose art file is spelled ARCTIC.
PLANETS = {
    "DESERT": "desert",
    "VOLCAN": "volcanic",
    "ARTIC": "arctic",
    "CITY": "city",
    "JUNGLE": "jungle",
}

# BUILD.DAT +4 -> zod building id (0 fort_front 1 fort_back 2 radar
# 3 repair 4 robot_factory 5 vehicle_factory 6 bridge_vert 7 bridge_horz)
BUILD_KIND = {0: 3, 1: 5, 4: 4, 8: 2}

# OBJECT.DAT +4 -> (kind, zod id, dy) where dy is the tiles the record sits
# ABOVE the cell the zod maps use. `n`/`hit` in the comments are the record
# count and how many of them matched a zod object of that exact kind+id.
#
# Hardware, pickups and huts are planet-independent in position (dy = 0);
# the hut TYPE is planet-specific because it indexes the planet's table.
OBJ_COMMON = {
    5: ("cannon", 1, 0),      # gun               n=65  hit=62
    22: ("cannon", 0, 0),     # gatling           n=18  hit=16
    23: ("cannon", 2, 0),     # howitzer          n=11  hit=11
    21: ("cannon", 3, 0),     # missile cannon    n=1   hit=1
    33: ("vehicle", 0, 0),    # jeep              n=20  hit=16
    29: ("vehicle", 1, 0),    # light tank        n=36  hit=35
    8: ("vehicle", 2, 0),     # medium tank       n=19  hit=18
    26: ("vehicle", 3, 0),    # heavy tank        n=4   hit=4
    31: ("vehicle", 4, 0),    # apc               n=5   hit=5
    24: ("vehicle", 5, 0),    # missile launcher  n=4   hit=4
    35: ("vehicle", 6, 0),    # crane             n=21  hit=21
    9: ("map_item", 2, 0),    # grenades          n=2   hit=1
    10: ("map_item", 2, 0),   # grenades          n=99  hit=96
}
# per planet: type -> (kind, zod id, dy)
OBJ_PLANET = {
    "desert": {
        11: ("map_item", 4, 0),    # hut     n=46 hit=46
        39: ("map_item", 11, 1),   #         n=7  hit=7
        40: ("map_item", 12, 1),   #         n=23 hit=23
        41: ("map_item", 13, 1),   #         n=28 hit=27
        42: ("map_item", 14, 1),   #         n=10 hit=10
        43: ("map_item", 15, 0),   #         n=59 hit=57
        20: ("map_item", 0, 0),    # n=1   UNKNOWN, no zod counterpart
    },
    "volcanic": {
        17: ("map_item", 4, 0),    # hut     n=51 hit=50
        52: ("map_item", 20, 1),   #         n=30 hit=29
        53: ("map_item", 21, 1),   #         n=54 hit=52
        13: ("map_item", 0, 0),    # n=6   UNKNOWN
        14: ("map_item", 0, 0),    # n=29  UNKNOWN
        15: ("map_item", 0, 0),    # n=40  UNKNOWN
        16: ("map_item", 0, 0),    # n=69  UNKNOWN
    },
    "arctic": {
        19: ("map_item", 4, 0),    # hut     n=54 hit=51
        46: ("map_item", 8, 1),    #         n=46 hit=41
        47: ("map_item", 7, 1),    #         n=67 hit=63
        60: ("map_item", 9, 1),    #         n=11 hit=11
        61: ("map_item", 10, 0),   #         n=3  hit=3
    },
    "city": {
        18: ("map_item", 4, 0),    # hut     n=83 hit=63
        48: ("map_item", 16, 1),   #         n=63 hit=63
        49: ("map_item", 17, 1),   #         n=35 hit=34
        50: ("map_item", 18, 1),   #         n=14 hit=12
        51: ("map_item", 19, 1),   #         n=46 hit=43
    },
    "jungle": {
        12: ("map_item", 4, 0),    # hut     n=52 hit=51
        54: ("map_item", 23, 1),   #         n=22 hit=22
        55: ("map_item", 22, 1),   #         n=44 hit=42
        56: ("map_item", 25, 1),   #         n=40 hit=40
        57: ("map_item", 24, 1),   #         n=68 hit=68
    },
}

# palette_tile_info, same record as tools/zod/map_to_json.py reads
TILEINFO_FIELDS = struct.Struct("<6BHBhB")


def load_tileinfo(path: Path) -> list[tuple]:
    raw = path.read_bytes()
    return [TILEINFO_FIELDS.unpack_from(raw, off)
            for off in range(0, len(raw), TILEINFO_FIELDS.size)]


def level_name(gog: Path, number: int) -> str:
    """Record `number` of levels.dat, first 20 bytes."""
    dat = gog / "levels.dat"
    if not dat.exists():
        return f"level{number:02d}"
    raw = dat.read_bytes()
    off = number * LEVELS_DAT_STRIDE
    if off + LEVELS_DAT_STRIDE > len(raw):
        return f"level{number:02d}"
    name = raw[off:off + 20].split(b"\0")[0].decode("latin-1").strip()
    return name or f"level{number:02d}"


def read_planes(raw: bytes) -> tuple[int, int, str, list[int], list[int]]:
    """width, height, planet, row-major sheet tile index, cropped plane 1."""
    name1 = raw[NAME1_OFF:NAME1_OFF + 13].split(b"\0")[0].decode("latin-1")
    key = re.sub(r"\.LBM$", "", name1, flags=re.I).upper()
    if key not in PLANETS:
        raise ValueError(f"unknown tileset {name1!r}")
    planet = PLANETS[key]
    width, height = struct.unpack_from("<HH", raw, SIZE_OFF)
    p1 = raw[PLANE1_OFF:PLANE1_OFF + PLANE_LEN]
    p2 = raw[PLANE2_OFF:PLANE2_OFF + PLANE_LEN]
    tiles = []
    ground = []
    for y in range(height):
        row = y * GRID_STRIDE
        for x in range(width):
            i = row + x
            ground.append(p1[i])
            tiles.append(p1[i] + (SHEET1_TILES if p2[i] & 0x80 else 0))
    return width, height, planet, tiles, ground


def read_zones(raw: bytes, width: int, height: int) -> list[dict]:
    """Territory rectangles from CPUPLR{NN}.DAT, already in tile units."""
    zones = []
    for off in range(0, len(raw) - CPUPLR_STRIDE + 1, CPUPLR_STRIDE):
        x1, y1, x2, y2 = struct.unpack_from("<4H", raw, off)
        if x2 <= x1 or y2 <= y1 or x2 > width or y2 > height:
            continue
        zones.append({"x": x1, "y": y1, "w": x2 - x1, "h": y2 - y1})
    return zones


def read_forts(ground: list[int], width: int, height: int) -> list[dict]:
    """Forts, recovered from the tile-238 hole they punch in the ground.

    100 cells in a 10-wide box = fort_front, 96 = fort_back. Anything else
    that shape is ignored; single stray 238 cells are common."""
    hole = [t == FORT_GROUND_TILE for t in ground]
    seen = [False] * len(hole)
    out = []
    for start in range(len(hole)):
        if not hole[start] or seen[start]:
            continue
        seen[start] = True
        stack = [start]
        cells = []
        while stack:
            i = stack.pop()
            cells.append(i)
            cx, cy = i % width, i // width
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    nx, ny = cx + dx, cy + dy
                    if not (0 <= nx < width and 0 <= ny < height):
                        continue
                    j = ny * width + nx
                    if hole[j] and not seen[j]:
                        seen[j] = True
                        stack.append(j)
        if len(cells) < 90:
            continue
        xs = [i % width for i in cells]
        ys = [i // width for i in cells]
        if max(xs) - min(xs) + 1 != 10 or not 10 <= max(ys) - min(ys) + 1 <= 13:
            continue
        # 100 cells = north-facing (fort_front), 96 = south-facing
        bid = 0 if len(cells) >= 100 else 1
        out.append({"x": min(xs), "y": min(ys), "owner": 2 if bid == 0 else 1,
                    "type": "building", "id": bid, "level": 0, "health": 100})
    out.sort(key=lambda o: (o["x"], o["y"]))
    return out


def read_rocks(raw: bytes, width: int, height: int) -> list[dict]:
    """Rocks, from the 20 32x32 bit stamps at 6657. Emitted as zod
    `map_item` id 1, which `map_loader.gd` autotiles and marks solid."""
    out = []
    seen = set()
    for slot in range(ROCK_SLOTS):
        off = ROCKS_OFF + slot * ROCK_STRIDE
        x, y = struct.unpack_from("<HH", raw, off)
        if x == 0xFFFF or (x == 0 and y == 0):
            continue           # free slot
        if x >= width * TILE_PX or y >= height * TILE_PX:
            continue
        ax, ay = x // TILE_PX, y // TILE_PX
        mask = off + ROCK_MASK_OFF
        for row in range(ROCK_MASK_SIDE):
            for col in range(ROCK_MASK_SIDE):
                if not raw[mask + row * 4 + col // 8] >> (7 - col % 8) & 1:
                    continue
                cell = (ax + col, ay + row)
                if cell in seen or not (0 <= cell[0] < width
                                        and 0 <= cell[1] < height):
                    continue
                seen.add(cell)
                out.append({"x": cell[0], "y": cell[1], "owner": 0,
                            "type": "map_item", "id": 1, "level": 0,
                            "health": 100})
    return out


def read_objects(raw: bytes, planet: str, width: int, height: int) -> list[dict]:
    table = dict(OBJ_COMMON)
    table.update(OBJ_PLANET.get(planet, {}))
    out = []
    for off in range(0, len(raw) - OBJECT_STRIDE + 1, OBJECT_STRIDE):
        x, y = struct.unpack_from("<HH", raw, off)
        if x == 0xFFFF or x >= width * TILE_PX or y >= height * TILE_PX:
            continue
        entry = table.get(raw[off + 4])
        if entry is None:      # a type we never saw in the ground truth
            continue
        kind, oid, dy = entry
        out.append({"x": x // TILE_PX, "y": min(height - 1, y // TILE_PX + dy),
                    "owner": 0, "type": kind, "id": oid,
                    "level": 0, "health": 100})
    return out


def read_buildings(raw: bytes, width: int, height: int) -> list[dict]:
    out = []
    for off in range(0, len(raw) - BUILD_STRIDE + 1, BUILD_STRIDE):
        x, y = struct.unpack_from("<HH", raw, off)
        kind = raw[off + 4]
        if x == 0xFFFF or x >= width * TILE_PX or y >= height * TILE_PX:
            continue
        if kind not in BUILD_KIND:
            continue           # 0xFF: a free or stale editor slot
        bid = BUILD_KIND[kind]
        max_hp = struct.unpack_from("<H", raw, off + 12)[0]
        # INFERRED, not a field we found: the factories' max-health tier is
        # the only level-like number in the record. hp//1000, minus one for
        # robot factories, reproduces the zod maps' blevel on 165 of 170
        # factory records (97.1%). Radar and repair always read 500, and
        # their zod blevel varies 0..5 with no signal to predict it, so
        # they get 0 (they build nothing, so nothing reads it).
        level = 0
        if bid in (4, 5):
            level = max(0, min(5, max_hp // 1000 - (1 if bid == 4 else 0)))
        out.append({"x": x // TILE_PX, "y": y // TILE_PX, "owner": 0,
                    "type": "building", "id": bid, "level": level,
                    "health": 100})
    return out


# A bridge's ACROSS width is always 4 tiles and its LENGTH varies (3-12
# tiles) — so the dimension that measures 4 tells the orientation, and
# `w > h` does NOT: a 4x3 bridge is VERTICAL (4 across, 3 long) even
# though w > h. Verified against the 44 bridges that have a zod twin
# (p02_bb_orig01..20, the same levels hand-edited for 2 players): every
# record with w == 4 tiles is zod id 6 and every record with h == 4 is
# id 7, with zero exceptions, across lengths 3,4,5,6,7,8,9,12.
BRIDGE_ACROSS_TILES = 4


def read_bridges(raw: bytes, width: int, height: int) -> list[dict]:
    out = []
    for off in range(0, len(raw) - BRIDGE_STRIDE + 1, BRIDGE_STRIDE):
        x, y, span_w, span_h = struct.unpack_from("<4H", raw, off)
        if x == 0xFFFF or x >= width * TILE_PX or y >= height * TILE_PX:
            continue
        if span_w == 0 or span_h == 0 or span_w > 0xFF00 or span_h > 0xFF00:
            continue
        tiles_w = max(span_w // TILE_PX, 1)
        tiles_h = max(span_h // TILE_PX, 1)
        # vertical when the 4-tile dimension is the WIDTH (4x4 reads as
        # vertical, which is what the two zod twins of that shape say)
        vertical = tiles_w == BRIDGE_ACROSS_TILES
        out.append({"x": x // TILE_PX, "y": y // TILE_PX, "owner": 0,
                    "type": "building", "id": 6 if vertical else 7,
                    "level": 0, "health": 100,
                    # the span is PER BRIDGE here, unlike the zod maps
                    # (which carry no size): the loader honours it and
                    # falls back to the def when it is absent
                    "span_w": tiles_w, "span_h": tiles_h})
    return out


def convert(gog: Path, number: int, tileinfo_dir: Path | None = None) -> dict:
    raw = (gog / f"LEVEL{number:02d}.MAP").read_bytes()
    width, height, planet, tiles, ground = read_planes(raw)
    cpuplr = gog / f"CPUPLR{number:02d}.DAT"
    zones = read_zones(cpuplr.read_bytes(), width, height) \
        if cpuplr.exists() else []

    objects = read_forts(ground, width, height)
    objects += read_rocks(raw, width, height)
    for name, reader in (("BUILD", read_buildings), ("BRIDGE", read_bridges)):
        path = gog / f"{name}{number:02d}.DAT"
        if path.exists():
            objects += reader(path.read_bytes(), width, height)
    obj_dat = gog / f"OBJECT{number:02d}.DAT"
    if obj_dat.exists():
        objects += read_objects(obj_dat.read_bytes(), planet, width, height)

    passable = water = None
    if tileinfo_dir is not None:
        ti = tileinfo_dir / f"{planet}.tileinfo"
        if ti.exists():
            info = load_tileinfo(ti)
            water = [1 if info[t][0] else 0 for t in tiles]
            passable = [1 if info[t][1] else 0 for t in tiles]

    forts = sum(1 for o in objects if o["id"] in (0, 1)
                and o["type"] == "building")
    return {
        "name": level_name(gog, number),
        "width": width, "height": height,
        "terrain": planet,
        "player_count": forts,
        "zones": zones, "objects": objects, "tiles": tiles,
        "passable": passable, "water": water,
    }


CAMPAIGN = list(range(1, 21))
SKIRMISH = [26, 27, 28, 29, 31]


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    gog = Path(sys.argv[1])
    out_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(".")
    tileinfo_dir = Path(sys.argv[3]) if len(sys.argv) > 3 else None
    out_dir.mkdir(parents=True, exist_ok=True)
    for number in CAMPAIGN + SKIRMISH:
        if not (gog / f"LEVEL{number:02d}.MAP").exists():
            continue
        data = convert(gog, number, tileinfo_dir)
        tag = "c" if number in CAMPAIGN else "s"
        dst = out_dir / f"z{tag}{number:02d}_{_slug(data['name'])}.json"
        dst.write_text(json.dumps(data))
        from collections import Counter
        kinds = Counter(f"{o['type']}:{o['id']}" for o in data["objects"])
        blocked = sum(1 for p in data["passable"] or [] if not p)
        print(f"LEVEL{number:02d} {data['name']!r}: {data['width']}x"
              f"{data['height']} {data['terrain']} | {len(data['zones'])} zones"
              f" | {len(data['objects'])} objects | {blocked} blocked"
              f" -> {dst.name}")
        for k, c in kinds.most_common(6):
            print(f"   {c:3d}x {k}")


def _slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_") or "level"


if __name__ == "__main__":
    main()
