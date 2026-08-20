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
- **Structures burn** — `ZBuilding::ProcessBuildingsEffects`, ported
  exactly (read off the Zod Engine source, 2026-08-20). A damaged
  building holds a POPULATION of effects, not a spawn rate:
  `should_effects = max_effects * (1 - health/max_health)`, topped up
  when short, each placed uniformly inside a per-type `effects_box` in
  art-local px. The loop has **no destroyed check**, which is why a Z
  ruin keeps burning — at zero health the population sits at
  `max_effects` for good. The mix is one `rand() % 100` roll:
  **<10 big_smoke, <20 small_fire_smoke, <50 fire, else little_fire** —
  so a burning building is mostly FIRE, and `smoke`/`little_smoke`/
  `spark` are the VEHICLE death effects, never used by a building.
  Constructor values, verbatim:

  | source | effects_box (x,y,w,h) | max_effects |
  |---|---|---|
  | `bfort.cpp` | 18, 18, 136, 118 | `20 + rand()%8` |
  | `brobot.cpp` / `bvehicle.cpp` | 8, 8, w-24, h-24 | `8 + rand()%4` |
  | `brepair.cpp` | 8, 8, w-24, h-24 | `6 + rand()%4` |
  | `bradar.cpp` | 1, 6, 44, 30 | `6 + rand()%3` |
  | `zbuilding.cpp` (fallback) | 16, 16, 32, 32 | 8 |

  ONE deliberate deviation: zod never shrinks `extra_effects`, so a
  repaired zod building burns for the rest of the match. We repair
  buildings, so `_burn_fx` trims the population back down.
  `buildings/death_effects/` holds only the 7 tumbling piece sets, so
  the smoke/fire art is shared with the vehicle folder.

### Original art still without a consumer (future work)

Ambient life (birds 228, hut_animals 734), planet impact art (craters
65, rock_effects 256, bridge_effects 60), ground track marks
(`track_effects/`, per planet), tank_dirt, the portrait GESTURE pieces
(the 64x64/48x64 salute and thumbs-up hands — placement unknown, 2e.1),
the factory_gui scrollbar set, `fort_old` BMPs, team palette BMPs.

## 2d. Original engine code sweep — features we have NOT rebuilt (2026-08-18)

STATUS UPDATE (same day): items 1-13 below are now IMPLEMENTED except
where noted — building levels + tiered build lists (forts build robots/
vehicles/cannons; factories build cannons too), cannon production,
repair shop + crane repairs (incl. rebuilt bridges), drivers + lid
window + sniper ejections (survivor bails out), throwable grenades,
attack-move (A+click) + auto-enter, sprint (shift-click) with stamina,
dodge sidestep on near-misses, destroyable bridges/rocks, fort
garrison + fort missiles, the announcer (comp_* lines), per-shot hit
chance + explosive splash radii + snipe chances (zsettings). Also done
since (2026-08-19): radar gates minimap intel, ground track marks +
craters + hut animals, fort tower cannon slots (manned, capped),
contextual animated cursors, R/V/G production roster tabs, native-scale
world render, map previews with roads + building footprints. Also done since (2026-08-20): the whole in-game HUD FRAME (the
original's 100px sidebar + 36px bottom bar, replacing our floating
panels — clock, animated portrait, name plate, equipment art, grenade
tally, 74px health bar, weapon plate, A/T/D/Z and R/V/B/G/Menu buttons,
the radar in its own window, and the unit_amount_bar army gauges),
robot portraits (SHEADBI, baked — see 2e), the build menu on the
original's 112x80 window with its Time/Cancel/Ok readouts, distress
barks under fire, auto-deselect on order, centre-on-select, and
production changing hands on capture. Still missing (non-blocking):
EXIT_C eject cursor, birds, unit-group formations, missile
target-leading, and the per-file mapping of ROB23-75 (see 2e).
The list below is kept as the original reference.

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

(HP normalized to /74; damage is a fraction of target max HP per hit.)

**AREAS OF EFFECT ARE VERIFIED (2026-08-20)** against
`zsettings.cpp SetDefaults` in the Zod Engine source. Every non-zero
`attack_damage_radius` matches ours exactly — tough 40, light 40,
medium 45, heavy 50, missile_launcher 80, gun 40, howitzer 40,
missile_cannon 50 — as do the zeros (grunt/psycho/sniper/pyro/laser/
jeep/apc/crane/gatling) and `grenade_damage_radius = 30`. The fort
turret's radius is not a setting at all: `OMapObject::
ServerFireTurrentMissile` hardcodes `radius = 40`, which is what
`fort_building.gd` uses. The splash MODEL matches too
(`ZServer::ProcessMissileDamage`): one roll per object, LINEAR falloff
`damage * (1 - mag/radius)`, friendly fire OFF, a circle not a box,
buildings and rocks included. One knowing divergence — the original
measures `mag` to the object's CENTRE; we clamp to a building's
footprint rect (`BuildingRegistry.blast_targets`) so a shell on a big
factory's wall does not measure to its middle.

**THIS TABLE IS NOW PORTED, and `--balance-test` asserts it** — every
stat above plus the per-level build lists from `zbuildlist.cpp
LoadDefaults`, so drift fails the run. Our HP sits on a 0..800 scale
rather than the original's /74 (a constant x10.8: grunt 86, psycho 141,
tough 270, medium 541, crane 800), which keeps the original's
proportions while giving the selection-ring health bars whole pixels to
work with. Small-arms damage against BUILDINGS uses the original's
fraction-of-max-HP model (`building_frac`); unit-vs-unit uses the flat
integer at the same x0.08 scale. The older note here claimed our numbers
were invented and "far more lethal" — that was true when it was written
and is no longer.

### Unwired effects (art exists in the original)

bridge debris/repair effect, cannon-death anim (wasted sprite flying),
crane cones, tank_dirt, per-planet ground track marks (`etrack`),
tough mushroom/smoke, fort/map-object turret missiles, muzzle
initfire effect, rock/bridge debris, craters.

### Unwired audio

ROB01–75 robot barks, COMP01–20 + comp_* announcer lines, radar ping.

### Out of scope for us

multiplayer/server stack (zserver sockets, mysql ladder), map editor,
zportrait lip-synced HUD faces: the 11k-line engine module stays out of
scope, but the ART is in and the faces DO animate — blink and talk
cycles baked from the 24 folders (see 2e.1). True phoneme lip-sync
driven by PHRASES.BIN's per-frame stream is the part still undone.

## 2e. `PHRASES.BIN` — the phrase/expression table (2026-08-20)

`PHRASES.BIN` (35328 b) is **64 records of 552 bytes** after an 8-byte
header: a 31-char name, then a per-frame animation stream. It is the
table behind BOTH the robots' voice lines and their animated HUD faces,
and the names are plain English, so it tells us the original's whole
expression and bark vocabulary:

- **order/selection lines** (22): `yes-sir-1-and-2`, `yes-sir-3`,
  `unit-reporting-1/2`, `<type>s-reporting` for all six robots,
  `were-on-our-way`, `here-we-go`, `youve-got-it`, `moving-in`, `okay`,
  `alright`, `no-problem`, `over-n-out`, `affirmative`, `going-in`,
  `lets-do-it`, `lets-get-em`
- **distress** (4): `we're-under-attack`, `i-said-we're-under-attack`,
  `help-help`, `theyer-all-over-us`
- **losing** (4): `wereloseing-it` x2, `for-chris-sake`, `you're-joking`
- **combat/results** (11): `target-destroyed`, `good-hit`, `nice-one`,
  `oh-yeah`, `gotche`, `smookin`, `cool`, `wipe-out`, `no-way`,
  `forget-it`, `get-outta-here`
- **events** (5): `territory-taken`, `fire-extinguished`,
  `gun-captueed`, `vehicle-captueed`, `grenades-collected` (sic)
- **PORTRAIT EXPRESSIONS** (17, no audio): `blink`, `wink`, `surprise`,
  `anger`, `grin`, `scared`, `eyes-{left,right,up,down}`, `whistle`,
  `look-{left,right}`, `salute`, `thumbsup`, `yes-sir-salute`,
  `goingin-thumbsup`

That last group is what the 64x64 and 48x64 gesture cut-outs in each
portrait folder are for — the salute/thumbs-up hand.

**We did NOT get a bark mapping out of it.** The obvious hypothesis is
that the voiced records run in the same order as `ROB01-75`, and the
group boundary supports it: the first 22 voiced records are exactly the
selection/order lines, and `ROB01-22` are exactly the 12 `selected_*` +
10 `acknowledge_*` files zod had already named. But it fails on clip
LENGTH — `bark_24` would have to be `i-said-we're-under-attack`, the
longest line in its group, and it is the shortest at 0.50 s. So
`ROB23-75` stay an unlabelled pool (`Fx.chatter`/`Fx.distress` draw
from it) and the per-file mapping is still unknown. The per-frame stream
in each record is not decoded either.

### 2e.1 Animated portraits — recovering the piece offsets

The pack ships 24 `portraits/<type>_<team>/` folders of 40 pieces each,
and the same signature every time: 3 heads (~80x60), 16 mouths (32x32),
11 eye bands (48x16), plus the gesture pieces above. The original does
not ship whole faces — the engine composites the cut-outs onto a base
head at fixed offsets, and those offsets live in the engine, not the
pack.

`tools/zod/build_hud.py` recovers them the same way 6.6b cracked the
rock stamps: slide each piece over the base head and score the mean
error over pixels both images draw. Two things make the answer
trustworthy rather than a coincidence:

- the group is scored **jointly** — one cut-out can be almost all key
  colour (a wide-open mouth barely overlaps the closed one the base
  head draws), so its own best position is noisy, but summing every
  member's error over the same candidate offset puts all the evidence
  behind one decision;
- the base head is **chosen by the same score**, per unit TYPE. Two of
  the three 80x6x frames are the same face on canvases 16px apart, so
  they score almost equally; picking by "draws the most pixels" chose a
  different crop per team and shifted that team's offsets with it.

Grunt locks hardest (mouth (27,24), eyes (19,8), runner-up ~1.4x worse);
the alternate head needs its OWN offsets, since it is usually that
16px-shifted crop. Whole frames are then baked to
`ui/portraits/<type>_<team>/{base,hurt,blink_nNN,talk_nNN}.png` so the
runtime plays a flipbook and never knows a piece offset. `hurt` is the
second head, shown below 45% HP.

## 2f. The HUD frame's slots came out of the frame art

The frame art draws a plate in every slot it does not own, and draws the
lettered buttons in place — so template-matching the loose button plates
against it recovers their positions at **0.00 error**: A (8,8), then
T/D/Z at (8|38|68, 264) on the sidebar; R/V/B/G at (8|38|68|98, 10) and
Menu at right+64,10 on the bottom bar. Note which STATE the art embeds:
the sidebar's four are drawn *inactive* and the bottom bar's five
*active*, which is the original telling us the sidebar letters are mode
toggles and the bottom-bar letters are actions.

The dark windows in the art give the rest: portrait (8,44) 86x74 — the
same 86x74 as the `backdrop_*` art — health bar (14,210) **74** wide,
which is the original's HP scale of 74 (2d) at one pixel per hit point,
and the radar at (6,298) 94x98.

What the letters MEAN is not recorded in anything the release ships. The
bindings in `hud_frame.gd` / `selection_filters.gd` are therefore ours,
and flagged as such in those files.

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

## 6. Original campaign level format (reverse-engineered 2026-08-20)

Parser: `tools/gog/level_to_json.py`. It reads `assets_original/gog/` and
writes the same JSON schema `tools/zod/map_to_json.py` emits, so
`map_loader.gd` loads the original 20 campaign levels plus the 5 extra
maps (`LEVEL26-29`, `LEVEL31`) unchanged.

Every claim below names the check that produced it. Anything I could not
prove is under "Still unknown" and the tool leaves it out.

### 6.1 The ground truth that made this possible

`project/assets/maps/p02_bb_orig01..20.json` — which BUGS.md item 1 calls
"the zod multiplayer pack" — **are the 20 original campaign levels**,
edited by the zod authors for 2 players. Proof: each one has the exact
width, height and planet of the matching `LEVEL{01-20}.MAP`, and 96.17%
of all 218,000 tiles agree cell for cell. That gives a per-cell and
per-object oracle that is far stronger than eyeballing
`Maps/LEVEL*.png`, and every id table in the tool was *read off* it, not
guessed. `Maps/LEVEL*.png` stays useful as an independent check because
zod's edits do not appear in it.

### 6.2 `LEVEL{NN}.MAP` — 56433 bytes, identical size on all 25 files

| Offset | Size | Field | Status |
|---|---|---|---|
| 0 | 1 | unknown (0xF7 on LEVEL01) | GUESSED |
| 1 | 6656 | byte-identical copy of the region array at 43377 | VERIFIED |
| 6657 | 2760 | rock array, 20 × 138 bytes | VERIFIED |
| 9417 | 680 | 4 × 138 bytes + 128 × 0xFF, identical in every level | UNKNOWN |
| 10097 | 13 | `char` tileset-1 name, e.g. `DESERT.LBM` | VERIFIED |
| 10110 | 1 | `u8` = 1 on all 25 files | VERIFIED |
| 10111 | 13 | `char` tileset-2 name, e.g. `DESERT2.LBM` | VERIFIED |
| 10124 | 1 | `u8` = 1 on all 25 files | VERIFIED |
| 10125 | 2 | `u16` width in tiles | VERIFIED |
| 10127 | 2 | `u16` height in tiles | VERIFIED |
| 10129 | 16384 | plane 1, 128×128 bytes, row-major | VERIFIED |
| 26513 | 16384 | plane 2, 128×128 bytes, row-major | VERIFIED |
| 42897 | 480 | zeros | VERIFIED |
| 43377 | 13056 | region array, 96 × 136 bytes | VERIFIED |

- **Duplicate array**: `d[1:6657] == d[43377:50033]` on all 25 files.
- **Width/height**: the values (64×86 … 128×128) reproduce the aspect
  ratio of the rendered `Maps/LEVEL*.png` thumbnails to within 0.5% on
  24 of 25 levels (LEVEL13 is 4.5% off; its thumbnail looks cropped).
- **Grid stride 128**: region record 0 of LEVEL01 has rect
  (160,288)-(272,400) px, centre tile (13,21), and stores centre_cell
  2701 = 21·128+13; record 1 gives 2737 = 21·128+49.
- **The used rectangle is exactly `width × height`**: outside it plane 1
  is 0xEF. Checked per row on all 25 files — exact on 22; LEVEL01, 04
  and 08 carry uncleared editor scratch a few rows/columns past the
  declared size, which the tool ignores.

### 6.3 The tile index — `plane1 + 240 × (plane2 >> 7)`

Plane 1 is an index into the level's **first** tileset (0…239) and plane
2's top bit selects the **second** tileset. That is exactly the 480-tile
layout of our `assets/z/planets/<planet>.png` sheets, so the sum is
already a sheet index — no per-level remap exists or is needed.

- VERIFIED: 96.172% of 218,000 cells match the zod ground truth exactly.
  Plane 1 alone scores 66%. The residual is where the zod authors edited
  for 2 players — 200 of LEVEL01's 311 mismatches are the two fort
  footprints, where zod paints plain ground and the original punches a
  dark hole (see 6.6).
- VERIFIED: rendering the tool's output with the zod sheets and
  downscaling to the thumbnail size gives a mean Pearson correlation of
  **0.7216** against `Maps/LEVEL1-25.png` (0.8105 if the fort footprints
  are excluded, since the thumbnails show the fort sprite there and a
  bare tile render shows the hole). Plane 1 alone scores 0.6129.

**GOG `.BLK` → zod sheet.** `<PLANET>.BLK` is 512 × 16×16 8-bit tiles
and `<PLANET>.PAL` is a 6-bit VGA palette. Indices 240-255 and 496-511
are unused padding, so `sheet = blk if blk < 240 else blk - 16`
(240 + 240 = the 480 tiles of our sheet). Verified by rendering every BLK
tile and matching it against every sheet tile on all five planets: that
rule is the **nearest** match for **480/480** tiles on every planet, with
a worst mean per-channel error of 2.36/255. There are **zero exact**
matches — the palettes are quantised differently (6-bit vs 8-bit), so the
art is the same but not bit-identical. Map cells never index above 239 in
plane 1, so for level data the mapping is the identity.

**Plane 2 bits 0-6** are a per-cell class 0…63, UNKNOWN. It clearly
tracks terrain kind (value 7 is 50% road tiles, 9 is 72% water, 19 is
63% impassable by tileinfo) and every rock in the zod maps sits on a cell
whose low bits are 0, but no reading predicted anything, so the tool
ignores it.

### 6.4 Region array (43377, 96 × 136) — parsed but NOT used

`u16 x1,y1,x2,y2` in pixels, `u16 centre_cell`, then neighbour ids
terminated by 0xFF; bytes 53-135 are an uninitialised table filled with
the first neighbour id. A slot is in use when byte +10 is not 0xFF.
LEVEL01 has 13 records (six 7×7 boxes plus connecting corridors),
LEVEL20 has 89. This is an **adjacency graph, not the territory grid** —
it does not tile the map and its count does not match the zod zone count.
What the original uses it for is UNKNOWN.

### 6.5 `CPUPLR{NN}.DAT` — 2217 b = 73 × 30 + a 27-byte tail — the zones

`u16 x1, y1, x2, y2` in **tiles** (not pixels); in use when the rect is
non-empty and fits the map. The remaining 22 bytes and the tail (which
ends with 40000 and 50) are UNKNOWN.

These are the territory rectangles: a 3×3 … 4×4 lattice with a one-tile
gutter covering 70-84% of the map. VERIFIED: the in-use record count
equals the zod zone count on **all 20** levels (9,9,10,15,9,12,10,15,10,
11,10,12,12,14,14,15,16,14,16,16) and **101 of 249** rects are
bit-identical; the other 148 differ by one tile on one edge because zod
closed the gutters. The tool writes the raw GOG rect.

### 6.6 Forts — cut out of the tile grid, not stored as objects

No `.DAT` file holds a fort. The ground under one is set to **plane-1
value 238 on every planet** (which renders as a near-black hole, sheet
tile 478). Take 8-connected components of `plane1 == 238` with a 10-tile
wide bounding box and ≥ 90 cells: **100 cells is a north-facing fort**
(zod building id 0, `fort_front`), **96 cells is south-facing** (id 1,
`fort_back`).

- VERIFIED: 38 of 40 forts land on the zod anchor exactly, id included.
  The two misses (LEVEL03 `fort_back`, LEVEL16 `fort_front`) are one row
  off because a stray 238 cell extends the bounding box.
- All 25 levels yield exactly 2 forts, which is what the tool writes as
  `player_count`.
- `owner` copies the convention every one of the 20 zod maps uses —
  `fort_front` = team 2, `fort_back` = team 1 — CONFIRMED against
  `Maps/LEVEL1.png`, where the north fort carries a blue plaque and the
  south fort a red one. It is a convention, not a field we read.

### 6.6b Rocks — 20 × 138 bytes at 6657, a 32×32 bit stamp each

| Offset | Field |
|---|---|
| +0 | `u16 x`, `u16 y` — PIXELS, top-left of the stamp |
| +4 | `u8`, `u8` — (2,0) on 116 of the 147 in-use records, also (0,0)/(2,5)/(2,1). UNKNOWN |
| +6 | `u16` — 0 on 106 records, else 624…3184. UNKNOWN |
| +10 | 128 bytes = a **32×32 bit mask**, row-major, 4 bytes per row, MSB first |

A set bit is a rock on cell `(x/16 + col, y/16 + row)`. A slot is free
when `x` is 0xFFFF, when `x` and `y` are both 0, or when the point falls
outside the map.

Rocks are **objects**, not terrain: all 151 of LEVEL01's rocks sit on
passable plain ground (tiles 105/121/120/85/122), which is why a bare
tile render shows bare ground where the thumbnail shows rock walls.
VERIFIED against the 20 zod maps: **5963 true positives, 75 false
positives, 27 false negatives** out of 5990 rock objects — precision
98.76%, recall 99.55%. Levels 02/07/10/18 carry almost all of the error,
and that is where zod's 2-player edits are.

The layout was found by brute force: for every start offset 4…23 and
every row width 8…72 bits, score the reconstructed cell set against the
zod rock set. `start=10, width=32` scores 76/76 and 75/75 on LEVEL01's
two stamps with **zero** false positives; nothing else comes close.

### 6.7 `OBJECT{NN}.DAT` — 1500 b = 150 × 10

`u16 x, u16 y` in pixels (0xFFFF = free slot), `u8 type`, `u8 sub-value`,
then 4 bytes of 0xFF (a pointer in the original struct). VERIFIED: 1840
of 1847 in-use records land inside the declared map and 1844 of 1847 are
16-aligned.

`type` indexes a **per-planet** table. Recovered by matching every
record's cell against the zod maps. Hardware and pickups use the cell as
stored; scenery is anchored **one tile above** the cell zod uses, and
that `dy` is part of the table. Table with the record count and how many
matched that exact kind+id:

| type | → | n / hit | | type | → | n / hit |
|---|---|---|---|---|---|---|
| 5 | cannon gun | 65/62 | | 22 | cannon gatling | 18/16 |
| 23 | cannon howitzer | 11/11 | | 21 | cannon missile | 1/1 |
| 33 | vehicle jeep | 20/16 | | 29 | vehicle light | 36/35 |
| 8 | vehicle medium | 19/18 | | 26 | vehicle heavy | 4/4 |
| 31 | vehicle apc | 5/5 | | 24 | vehicle missile launcher | 4/4 |
| 35 | vehicle crane | 21/21 | | 9, 10 | map_item grenades | 101/97 |
| 11/12/17/18/19 | hut (desert/jungle/volcanic/city/arctic) | 286/261 | | | | |
| desert 39,40,41,42,43 | map_item 11,12,13,14,15 | 127/124 | | arctic 46,47,60,61 | map_item 8,7,9,10 | 127/118 |
| city 48,49,50,51 | map_item 16,17,18,19 | 158/152 | | jungle 54,55,56,57 | map_item 23,22,25,24 | 174/172 |
| volcanic 52,53 | map_item 20,21 | 84/81 | | volcanic 13,14,15,16 | **UNKNOWN** | 144/0 |

Over levels 01-20 the table converts 1406 in-use records, 1261 of them
to a known id, and **1198 of those 1261 (95.0%)** land on a zod object of
exactly that kind and id.

Volcanic types 13/14/15/16 (144 records) have no counterpart in any zod
map, so their scenery id is unknown; the tool emits them as `map_item 0`,
which renders nothing rather than the wrong sprite. `desert 20` (n=1) and
`city 33` (n=4) are also unmatched; `city 33` is almost certainly a jeep
by cross-planet consistency and is mapped as one.

The `sub-value` byte is 0xFF on scenery and a small per-type constant on
hardware. Its meaning is UNKNOWN and the tool ignores it.

### 6.8 `BUILD{NN}.DAT` — 2800 b = 35 × 80

`u16 x, u16 y` in pixels — the **same anchor zod uses** — then
`u8 kind` (**0 repair, 1 vehicle factory, 4 robot factory, 8 radar**,
0xFF on a free/stale slot), `u8` = 8 on every live record, `u8` flags
(0/192/224 live, 240-255 stale), and `u16 max health` at +12 (500 for
radar and repair, 1000-5000 for factories). +22, +30 and +59 are heap
pointers from the original 32-bit build; the rest is padding or unread.

`kind` → zod id was read off the ground truth, not guessed. Together
with the bridges below, matching in-use records against the zod maps
gives **257 hits with the right position AND the right id and ZERO
position hits with a wrong id**; 27 more have no zod object (zod removed
them when rebalancing).

**Building level is INFERRED, not found.** No byte in the 80 predicts
zod's `blevel` (best purity 0.678, and that byte has 126 distinct
values). The factories' max-health tier is the only level-like number:
`max_hp/1000`, minus one for robot factories, reproduces zod's `blevel`
on **165 of 170** factory records (97.1%). The off-by-one between the two
factory types is unexplained. Radar and repair always read 500 and their
zod `blevel` scatters 0-5 with nothing to predict it, so the tool writes
0 for them (they build nothing, so nothing reads it).

### 6.9 `BRIDGE{NN}.DAT` — 312 b = 12 × 26

`u16 x, y` in pixels (0xFFFF = free), `u16 w, h` in pixels (4×6 … 10×4
tiles), `u16 health`, `u16 max health` (300/500/600), `u16` 0-or-16.
ORIENTATION comes from which dimension measures 4 TILES, not from
`w > h`: a bridge is always 4 tiles ACROSS and 3-12 long, so `w == 4`
means VERTICAL (zod id 6) and `h == 4` HORIZONTAL (id 7). Verified on
the 44 bridges that have a zod twin — every `w == 4` record is id 6 and
every `h == 4` record is id 7, no exceptions, across lengths 3,4,5,6,7,
8,9,10,12 (a 4x4 bridge reads as vertical, which both of its twins
confirm). `w > h` gets 43 of 44 right and mislabels the one 4x3 bridge
on LEVEL15. The span is emitted per bridge as `span_w`/`span_h` (tiles);
`Building2D.bridge_span_override` honours it and the zod maps, which
carry no size, fall back to the def. Included in the 257/0 count above.

### 6.10 `levels.dat` — 12240 b = 51 records × 240, record N = level N

| Offset | Field |
|---|---|
| +0 | `char[20]` level name |
| +20 / +33 / +46 | `char[13]` map / robots / cpuplr file |
| +59 / +72 | `char[13]` `preset2.wal` / `preset1.wal` |
| +85 | `u8[12]` list of 0…0x12 values, 0xFF-terminated — UNKNOWN |
| +97 / +111 | `char[14]` object file / `char[13]` mult file |
| +124 / +128 | `u32` = 10000 twice (starting credits? GUESSED) |
| +132 / +145 | `char[13]` build file / `char[14]` bridge file |

The 20 campaign names: Virgin Soldiers, Psychos, Death Valley, Desert
Islands, Hot Nuts, Sooty Bolts, Pyro Technics, Molten Kombat, Slippery
Jim, The Wall, Heavy Metal, Chilly Willy, Hot n Steamy, Restoration,
Swamp Fever, Light Brigade, Car Park, Mayhem, Bridge Game, Z. Records
21-25, 30 and 36-40 name maps the release does not ship; 26-29 and 31
(the files we do have) are just planet names.

### 6.11 `passable` / `water`

Taken from the zod `<planet>.tileinfo` record of the **corrected** tile
index, i.e. exactly what `tools/zod/map_to_json.py` does. VERIFIED
against the zod maps' own arrays: **98.28%** agreement on `passable` and
**99.98%** on `water` over 218,000 cells; the residual tracks the 3.8%
of tiles zod edited.

Rocks come from the bit stamps in 6.6b, so `passable` does NOT have to
carry them — `map_loader.gd` marks every `map_item 1` cell solid itself.
Note for the record that the earlier guess "rocks are baked into the
terrain" was WRONG: zod rock cells keep the same tile index in both files
86.6% of the time precisely because the rock is drawn on top of untouched
ground.

### 6.12 Still unknown / not in the release

- **The starting armies.** Every `levels.dat` record names
  `preset1.wal` / `preset2.wal`; **neither file exists in the install**
  (`Z.exe` holds the string, not the data). A converted level therefore
  has its forts, factories, bridges, scenery and unmanned hardware but
  no starting robots — the fort has to build them. Confirmed by
  searching every `u16` pair in `LEVEL01.MAP`, `OBJECT01`, `BUILD01`,
  `BRIDGE01`, `CPUPLR01`, `levels.dat`, `robots.dat`, `mult.dat`,
  `Z.exe`, `CHARS.BIN` and `PHRASES.BIN` for a coordinate within 80 px
  of either LEVEL01 fort (found by template-matching the fort sprite in
  `Maps/LEVEL1.png` at r=0.82): **0 hits**.
- `LEVEL.MAP` byte 0; the rock record's bytes +4/+5/+6; the four
  138-byte records plus 128 bytes of 0xFF at 9417, which are identical in
  every level; plane 2 bits 0-6; and most of each 136-byte region
  record.
- `robots.dat` (25000 b): a 44-byte-stride roster of named robots
  ("Grant", "Tough", "Sniper") with 5-byte stat blocks. Shared by every
  level, so it is a name/stat pool, not per-level placement. Not parsed.
- `mult.dat` (628 b) and the `CPUPLR` tail: AI tuning, not parsed.
- `OBJECT` sub-value byte; `BUILD` flags byte and the fields at +26/+28.
- Volcanic scenery types 13/14/15/16 → zod scenery id.

### 6.13 Running it

```
python3 tools/gog/level_to_json.py assets_original/gog <out_dir> \
        assets_original/zod/planets
```

Writes `zc01_virgin_soldiers.json` … `zc20_z.json` plus
`zs26_desert.json` … `zs31_city_1.json` (25 files). The third argument is
the tileinfo directory; without it `passable`/`water` come out `null`,
which `map_loader.gd` treats as fully passable.

Verified end to end on 2026-08-20 with Godot 4.7.1 headless, running
against a throwaway copy of `project/` with two converted files dropped
into `assets/maps/`:

- `MapCatalog.meta()` reads `zc01_virgin_soldiers` as 64×86 desert,
  `players = 2`, `fort_team_ids = [1, 2]`; `zc02_psychos` as 72×90.
- Building the same `TileSetAtlasSource` `MapLoader._build_terrain`
  builds and calling `set_cell` for every entry of `tiles` paints
  5504/5504 and 6480/6480 cells — no index falls outside the 20×24 sheet.
- `tiles`, `passable` and `water` are all exactly `width × height`, every
  index is in `[0, 480)`, and every object coordinate is inside the map.
- `AStarGrid2D` built from `passable` marks 1215 / 1198 cells solid.

What that run does NOT cover: `MapLoader.load_map` itself. Godot's
`--script` mode uses a bare `SceneTree` and never instantiates the
autoloads, so `map_loader.gd` fails to compile there on `ContentDB`
(`project.godot` line 20). Exercising the spawn half needs the game
booted normally with a real map in `assets/maps/`, which is a project
change and out of scope for the converter.

Object totals across the 20 campaign levels, scored against the zod maps
by exact `(x, y, type, id)`: **7455 of 7768 emitted objects (96.0%)**.

### 6.14 Score summary

| Check | Result |
|---|---|
| Tile index vs zod ground truth | 96.172% of 218,000 cells |
| Render vs `Maps/LEVEL*.png`, mean Pearson r | 0.7295 (0.8105 ignoring fort footprints); plane 1 alone 0.6129 |
| `.BLK` → sheet tile rule | nearest match for 480/480 tiles × 5 planets |
| Zone count vs zod | 20/20 levels; 101/249 rects bit-identical |
| Forts | 38/40 exact including id; 2 forts on all 25 levels |
| Rocks | precision 98.76%, recall 99.55% of 5,990 |
| Buildings + bridges | 257 exact, 0 wrong id, 27 with no zod twin |
| `OBJECT.DAT` id table | 1198/1261 mapped records exact (95.0%) |
| `passable` / `water` vs zod | 98.28% / 99.98% |
| All objects, exact `(x,y,type,id)` | 7455/7768 (96.0%) |
