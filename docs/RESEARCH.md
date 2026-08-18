# Research Notes — Z (1996)

Pivot note: this project originally targeted *Z: Steel Soldiers* (2001,
3D). We switched to the original 2D **Z (1996)** — earlier Z:SS reverse-
engineering work (model format, demo extraction) lives in git history.

## 1. Existing open-source projects (reference, not dependency)

- **[Zod Engine](https://github.com/a-sf-mirror/zod_engine)** — C++/SDL
  remake of Z, the source of our asset pack (`assets/` in its repo:
  9,539 PNGs, 261 WAVs, MID music). GPL — we only use it as an *asset
  source and format documentation*, not code.
- **[ZED Online](https://sourceforge.net/projects/zedonline/)** — another
  active remake (multiplayer focus).
- No official source code of Z exists.

## 2. Zod Engine asset inventory (in `assets_original/zod/`)

| Folder                    | Contents                                          |
|---------------------------|---------------------------------------------------|
| `units/robots/`           | shared robot body anims: stand, walk, throw, enter_apc, die1-5 + idle humor anims (beer, cigarette, pope, look_around, beat_ground, ...) — 16×16 palettized PNGs, `<anim>_<team>_r<deg>_n<frame>.png`, 4 team colors × 8 directions |
| `units/robots/<type>/`    | per-type fire anims: grunt, psycho, tough, sniper, pyro, laser |
| `units/vehicles/`         | jeep, light/medium/heavy tank, APC, crane, mobile gun... same naming scheme |
| `units/cannons/`          | stationary guns (gatling, howitzer, missile)       |
| `planets/`                | terrain tilesets: desert, arctic, city, jungle, volcanic (BMP 320×384 = 16×16 tiles + `.tileinfo` binary effect map) |
| `buildings/`              | fort (base), radar, robot/vehicle factory, repair  |
| `teams/`                  | team palette BMPs (red/blue/green/yellow recolors) |
| `sounds/`                 | voices (acknowledge/selected/order), weapons, MID music |
| root                      | splash art, cursors, fonts                         |

Also in the Zod repo (useful later): `blank_maps/`, `*.map` files
(Zod's text map format) and `zod_engine` source for map/physics
reference.

## 2b. GOG retail extract (in `assets_original/gog/`)

From our purchased `setup_z_2.3.0.8.exe` (Inno Setup; extracted with
`innoextract -I app`). This is the Win32 port build, but it carries the
original game data alongside port-specific resources:

| Path                      | Contents                                          |
|---------------------------|---------------------------------------------------|
| `LEVEL01.MAP`–`LEVEL25.MAP` | original level data (root)                      |
| `<PLANET>.BLK` + `.PAL`   | 5 tilesets + palettes: ARCTIC, CITY, DESERT, JUNGLE, VOLCANIC |
| `BRIDGE/BUILD/CPUPLR/GROUP/OBJECT*.DAT` | map object/unit placement data per level |
| `audio/`                  | 590 `.RAW` PCM sound effects + voices             |
| root `*.ogg` (242)        | music + voice lines, port re-encodes              |
| `CUTS/`                   | 47 `.jvi`+`.jvv` cutscene video pairs             |
| `PNG/`, `Maps/`, `Fonts/` | port UI art, level-select thumbnails, fonts       |
| `CHARS.BIN`               | port character/unit metadata                      |

Only file skipped: `__support/.../vcredist_x86_2012.exe` (duplicate,
no asset value).

## 2b. GOG release internals (reverse-engineered 2026-08-17)

`assets_original/gog/` — the Runesoft Mac/PC port of Z:

- `en.lproj/sprites.rsc` (3.9 MB): **the packed original sprite
  archive**. Format so far: `u16 entry_count` (7211), then
  `entry_count × u32 LE` absolute offsets; each record starts with a
  width byte (e.g. 0x10) followed by palette-index pixel runs (codec
  not yet decoded — likely RLE per row). `SHEADBI0-4.DAT` (~72 KB each,
  one per team?) look like the per-sprite header/index tables.
- `<PLANET>.PAL` — standard 768-byte 256-color RGB palettes (one per
  planet); `<PLANET>.BLK` (128 KB) — planet tile data blocks.
- `OBJECT/BUILD/BRIDGE/CPUPLR ##.DAT` — per-level object lists
  (10-byte records); `SINCOS/HSHWING/VSHWING` — precomputed render
  math tables; `LEVEL##.MAP` — compressed level data (different
  layout from zod's .map text format).
- `audio/*.RAW` — 115 sfx (8-bit unsigned PCM mono 11025 Hz);
  root + `lproj` oggs — soundtrack/voices.

Everything usable as files from this release is already wired into the
project (sfx, music, HUD panels, splash, backgrounds). The unit sprites
in `project/assets/z/` are the SAME original Bitmap Brothers art,
pre-extracted from the original archive by the Zod Engine project —
`sprites.rsc` contains the identical pixels in packed form. Extracting
them again would need: RLE codec, SHEADBI index semantics, sprite-ID →
name mapping and team palette recoloring — documented here for a future
attempt if GOG-only sourcing is ever required.

## 2c. Original sprite numbering & layer semantics (verified 2026-08-18)

Cross-checked zod engine source (`DirectionFromLoc`, `ROTATION`,
per-type `Init`/`DoRender`) against the actual sprite pixels:

- **Directions are counter-clockwise**: `r000`=E, `r045`=NE, `r090`=UP,
  `r135`=NW, `r180`=W, `r225`=SW, `r270`=DOWN, `r315`=SE. A unit moving
  down the screen renders the `r270` sprite. Angle→dir = sector of
  atan2 (y-down) + π/8 mapped counter-clockwise.
- **Tank hulls ship 4 of 8 facings** ({r000,r045,r090,r315}); the
  engine derives the rest. Zod reuses the source art *unflipped*
  (`base[i][j+4][2-k] = base[i][j][k]`) — visually wrong; the original
  mirrors. We flip horizontally and reverse the move anim.
- **Per-type layers** (all offsets live in `AnimLibrary.TURRET_TABLES`):
  light `top_r` + `initfire` muzzle effect + `tank_lid`; medium
  `topf_r` (idle AND fire; `top_r`/`cannon_r` files are legacy, loaded
  by nobody); heavy `top_<team>`; APC `top_r` scanner (always spins) +
  `open_<team>` doors on unload; missile launcher `top_<team>`;
  jeep `fire_r` gunner overlay (`n00` aim / `n01` flash); crane arm
  `crane_r` with **INVERTED** numbering + 16-frame `hook`.
- **Idle turrets scan** one sector per second (`turrent_time_int`);
  tracking turrets follow the target. Turrets blow off on death
  (`top_pop[_<team>]`, 8 frames).
- **Cannons**: gatling/howitzer manned idle is the *empty/passive* art
  (the gunner only exists in the fire frames); install = 3 shared
  `init-place` frames + 4 team `place` frames; gun/missile cannons idle
  on `equiped_r`. Missile-cannon/medium empty states exist per team but
  the engine only ever shows the neutral `empty_null`.
- **Weapons**: light tank fires a rocket (`light/bullet.png`); medium/
  heavy fire missiles (`missile_launcher/bullet.png`); howitzer/gun lob
  grenades (`other/grenades`); tough = rocket + mushroom, pyro = flame
  puffs (`robots_pyro/bullet_n`), laser = beam flash. APC passengers
  each fire their own weapon through the ports.
- **Damage VFX**: below half HP vehicles smoke facing-aware
  (`track_dust_r`), leak oil (`tank_oil_0-2`) and spark
  (`track_spark_r`/`ground_spark`); deaths use `death_effects/`
  (big_smoke/fire/little_fire/smoke/spark) and
  `other/explosions/side_explosion`.

### Original art still without a consumer (future work)

Ambient life (birds 228, hut_animals 734), planet impact art (craters
65, rock_effects 256, bridge_effects 60), ground track marks
(`track_effects/`, per planet), tank_dirt, HUD portraits (24 animated
faces), comp_messages announcer art, remaining factory/production GUI
and cursors, `fort_old` BMPs, team palette BMPs.

## 3. Game facts to recreate (Z, 1996)

- 2D tile maps on 5 planets; screen ~640×480 in original; units are
  16×16 sprites rendered from 8 baked directions.
- **Territory economy**: no harvesting — capturing **flags/sectors**
  grants income; more sectors = faster money. Forts produce robots;
  captured vehicle factories produce vehicles.
- Robots: Grunt, Psycho, Tough, Sniper, Pyro, Laser + constructors.
  Any robot can man empty vehicles/guns (enter_apc anim).
- Vehicles: Jeep, Light/Medium/Heavy Tank, APC, Crane, Mobile Gun...
- Combat: units auto-engage in range; player gives move/attack orders;
  robots have personality voice lines and idle animations.
- 20 singleplayer levels + multiplayer maps.

## 4. Godot environment

- Godot 4.7.1 stable via Flatpak (`org.godotengine.Godot`).
- 2D project: GL Compatibility renderer, nearest texture filtering,
  16×16 sprites scaled ×2 at runtime.

## 5. Licensing

- Z graphics/audio: © The Bitmap Brothers — gitignored locally, never
  committed or redistributed.
- Zod Engine assets: extracted/repacked originals, same copyright; GPL
  applies to its code, which we do not use.
