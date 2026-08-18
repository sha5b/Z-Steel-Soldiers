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

## 2d. Original engine code sweep — features we have NOT rebuilt (2026-08-18)

STATUS UPDATE (same day): items 1-13 below are now IMPLEMENTED except
where noted — building levels + tiered build lists (forts build robots/
vehicles/cannons; factories build cannons too), cannon production,
repair shop + crane repairs (incl. rebuilt bridges), drivers + lid
window + sniper ejections (survivor bails out), throwable grenades,
attack-move (A+click) + auto-enter, sprint (shift-click) with stamina,
dodge sidestep on near-misses, destroyable bridges/rocks, fort
garrison + fort missiles, the announcer (comp_* lines), per-shot hit
chance + explosive splash radii + snipe chances (zsettings). Still
missing: radar building function (needs a fog-of-war concept), ground
track marks, craters, hut animals/birds, HUD portraits, unit-group
formations. The list below is kept as the original reference.

Full function-level sweep of the zod engine source (137 cpp files,
~70k lines) against our remake. What we already match: 8-direction
rendering + mirroring + layered turrets/gunner/crane hook/APC doors,
install anims, damage states, wreck/turret-pop deaths, all 17 unit
types, APC transport, pathing, zones/income, queues/cap/rally, tactical
AI, save/campaign, HUD panels/icons/minimap, gestures/idle anims.

### Whole missing systems (gameplay-changing)

1. **Building levels & tiered build lists** (`zbuildlist.cpp`): every
   production building has levels 0–5 (the map `level` field feeds
   this; ours is parsed but unused). FORTS build robots + vehicles +
   cannons (full roster by level 5: everything incl. heavy tank and
   missile cannon); ROBOT factories build robots + gatling→gun→
   howitzer cannons by level; VEHICLE factories build vehicles + the
   same cannons. Higher level = faster build (`RecalcBuildTime`).
   Ours: fixed rosters, fort = robots only, no cannon production.
2. **Cannon manufacturing & placement** (`BuildingCreateCannon`,
   `StoreBuiltCannon`, `CannonsInZone`, `CannonNotPlacable`,
   `SetEjectableCannon`): built cannons pop out beside the building
   and are placed in its zone.
3. **Repair loop**: repair shops repair vehicles
   (`UnitEnterRepairBuilding`, repair entrance/center, repair anim);
   cranes repair buildings AND destroyed bridges (`ProcessCraneRepairWP`,
   cones art); `DoAutoRepair` self-repair. Ours: both decorative.
4. **Drivers & sniping**: vehicles/cannons carry driver objects with
   health; units have per-type `attack_snipe_chance` — snipers can
   kill the driver and re-empty hardware (`CanBeSniped`,
   `DamageDriverHealth`). Lids open while firing = the snipe window.
5. **Grenades as throwable weapons**: grenade crates grant
   `grenade_amount`, robots throw them (`CanThrowGrenades`,
   `PICKUP_GRENADES_WP`, pickup + throw anims already wired as art).
   Ours: the crate only boosts damage.
6. **Order types** (`waypoint_mode` enum): ATTACK, FORCE_MOVE,
   AGRO (attack-move), ENTER_FORT (garrison), DODGE, PICKUP_GRENADES,
   CRANE_REPAIR, UNIT_REPAIR — plus unit GROUPS with leader/minion
   waypoint cloning. Ours: move + implicit enter only.
7. **Run & dodge**: double-time running on stamina (`max_run_time`
   per unit, `ProcessRunStance`... `AttemptStartRun`); robots dodge
   slow missiles (`DodgeMissile`, dodge gesture art exists).
8. **Auto behaviors**: `WithinAutoEnterRadius` (auto-man nearby empty
   hardware), `WithinAutoGrabFlagRadius` (auto zone capture on walk-by).
9. **Destroyable bridges & rocks**: bridges have HP, explode
   (`CheckDestroyedBridge`), and cranes rebuild them; rocks are
   blastable (rock debris art, passability changes).
10. **Fort garrison**: robots can enter their fort
    (`CanEnterFort`, `RenderUnitCover`).
11. **Radar building function**: zone flags link to a radar in their
    zone (`OFlag::HasRadar`, `radar_activated` message). Ours:
    decorative.
12. **Announcer** (`zcomp_message_engine` + `comp_messages` art +
    COMP*.wav / comp_* oggs): "robot manufactured", "fort under
    attack", "territory lost", "radar activated", "you're losing"…
    Files present, nothing plays them.
13. **Terrain damage**: explosions leave craters per tile type
    (`CoordCraterType`, 65 crater art files per planet).
14. **Ambient life**: huts spawn wandering animals (`CreateAnimals`,
    734 art files) and birds fly over.
15. **Combat nuance**: per-shot hit CHANCE (0.65–0.8; missiles always
    hit), explosive damage RADIUS (40–45 px), target-leading for
    missiles (`EstimateMissileTarget`), approach from nearest edge
    (`NearestAttackLoc`), passive engage checks, damaged tanks shed
    tracks (`TryDropTracks`), APC carries one DRIVER per passenger
    (`SetInitialDrivers` — each fires its own gun), `ScuffleUnits`
    start-of-round shuffle, map-defined robot GROUPS with
    `health_percent`.

### Stat fidelity (zsettings.cpp SetDefaults vs our invented numbers)

| Unit | move | range | dmg/hit (chance) | fire s | HP | snipe | build s |
|---|---|---|---|---|---|---|---|
| grunt | 14 | 120 | 0.0011 (0.7) | 0.5 | 8/74 | 0.3 | 72 |
| psycho | 12 | 120 | 0.0026 (0.65) | 0.1 | 13/74 | 0.3 | 98 |
| sniper | 14 | 144 | 0.0070 (0.8) | 0.4 | 13/74 | 0.8 | 148 |
| tough | 12 | 120 | 40/240 r40 missile 150 | 1.44 | 25/74 | – | 116 |
| pyro | 12 | 120 | 0.0105 (0.7) | 0.1 | 20/74 | – | 161 |
| laser | 14 | 136 | 0.0178 (0.7) | 0.4 | 15/74 | 0.6 | 179 |
| jeep | 17 | 120 | 0.0027 (0.65) | 0.1 | 13/74 | 0.4 | 81 |
| light | 14 | 120 | 50/240 r40 missile 225 | 1.13 | 25/74 | – | 137 |
| medium | 12 | 128 | 80/240 r45 missile 160 | 2.34 | 50/74 | – | ~150 |

(HP normalized to /74; damage is a fraction of target max HP per hit;
our flat integers with 100% hit chance make combat far more lethal.)

### Unwired effects (art exists in the original)

bridge debris/repair effect, cannon-death anim (wasted sprite flying),
crane cones, tank_dirt, per-planet ground track marks (`etrack`),
tough mushroom/smoke, fort/map-object turret missiles, muzzle
initfire effect, rock/bridge debris, craters.

### Unwired audio

ROB01–75 robot barks, COMP01–20 + comp_* announcer lines, radar ping.

### Out of scope for us

multiplayer/server stack (zserver sockets, mysql ladder), map editor,
zportrait lip-synced HUD faces (11k lines — candidate if we ever want
talking portraits; art = 24 animated face folders, not yet copied).

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
