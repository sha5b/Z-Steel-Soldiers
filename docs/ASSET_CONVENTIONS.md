# Asset conventions & adding content

The game is data-driven: gameplay code never hardcodes a sprite path or
unit stat. Content is **Resource `.tres` files** (inspector-editable)
plus on-disk art folders:

- **`content/{units,vehicles,cannons,buildings,effects,pickups,projectiles}/`**
  — one `.tres` per thing (stats, art folder, weapon behaviour,
  producer rosters). Copy one next to its siblings and edit it in the
  inspector to add content. A `UnitDef` may also point at a per-type
  **scene** (`scenes/<kind-plural>/<name>.tscn`) carrying the visual
  rig — turret offsets are exported arrays, tweakable per type.
- **`ContentDB`** (autoload, `@tool` so editor previews work) — scans
  `content/`, resolves scenes by convention, and auto-discovers sprite
  folders on disk that have no `.tres` yet (default stats).

Drop correctly-named PNGs into `project/assets/z/` and they become
playable content. This file lists the naming patterns the scanners look
for — they double as a spec for generated assets.

## Recipes — adding content

**New unit/vehicle/cannon**: copy a `.tres` from `content/units/` (or
`vehicles/`, `cannons/`) → set `id`, `asset_dir`, stats. Drop the art
folder following the patterns below. Optionally add
`scenes/<kind-plural>/<name>.tscn` (inherit the base scene; set
`unit_name`/`kind` and the turret offset arrays). That's it — build
menus, AI, saves and the minimap pick it up from ContentDB.

**New weapon behaviour**: `weapon` on the UnitDef picks the resolver —
`"hitscan"`, `"laser"`, `"shell"` (a `ProjectileDef` sub-resource with
speed/impact/texture). A genuinely new behaviour = one class registered
in `Combat` (scripts/game/combat.gd).

**New building**: `.tres` in `content/buildings/` (size, flags, anims,
per-level `build_lists` rosters as `"kind:name"` entries) + a scene in
`scenes/buildings/` with the behaviour script + art under
`assets/z/buildings/<kind>/base_<planet>.png` (+ `_destroyed`).

**New effect/VFX**: drop a folder under `assets/z/effects/<name>/` with
`<name>_n00.png...` frames — auto-registered, playable via
`Fx.play("<name>")`. Tune fps/scale/grounding in a
`content/effects/<name>.tres` (scale is relative to the 2x unit
baseline; `art` plays another folder's frames).

**New item/crate**: `.tres` in `content/pickups/` — the effect is data
(`upgrade_key` grants a team upgrade, `grenades` arms the collector).
Wire new upgrade effects in MatchState.

**New map**: drop the JSON (and/or generated `.tscn`) under
`assets/maps/` — MapCatalog picks it up everywhere (map select,
campaign, cycler); `sandbox*` names are excluded from the campaign.

**New team colour**: one entry in `scripts/core/teams.gd` (id, name,
UI/minimap colours) **plus the `_<team>` art variants** — the original
engine shipped its own recoloured sprite set per team (`stand_blue_r000`,
`flag_green_n00`, `icon_jeep_yellow`, ... verified pure colour swaps of
the red set: neutral pixels untouched, identical canvases). Every team
loads its own files directly; nothing recolours at runtime. The
`--teams-test` self-test audits the full red→blue/green/yellow parity
(888 art files) so a missing variant fails loudly instead of rendering
an invisible unit.

## Folder layout

| Folder | Contents |
|---|---|
| `robots/` | shared robot art (all types) |
| `robots_<type>/` | per-type weapon fire anims |
| `vehicles_<type>/`, `cannons_<type>/` | mannable hardware |
| `buildings/<kind>/` | building bases + destroyed variants |
| `planets/` | terrain tilesets, rock sheets, bridges |
| `map_items/` | pickups, huts, scenery objects |
| `effects/<name>/` | one-shot effect frames (explosions, shells...) |
| `sounds/`, `music/`, `flags/`, `ui/` | audio, flags, UI art (GOG-sourced, see below) |

`<team>` is `red | blue | green | yellow | null` (null = unmanned).
Directions `r000 r045 r090 ... r315` (8 total) are numbered
**counter-clockwise**: r000 = east (+X), r045 = north-east, r090 =
north (up), r135 = north-west, r180 = west, r225 = south-west, r270 =
south (down), r315 = south-east. This matches the original engine's
`DirectionFromLoc` + `ROTATION` tables (verified against the sprite
pixels). Tank hulls ship only the right-hand half (r000/r045/r090/
r315); left-hand facings render as horizontal flips with the move
animation reversed. The crane arm is numbered the opposite way round
(arm facing d is stored in `crane_r{(d+4)*45}`).
Frame suffix `_n00 _n01 ...` (zero-padded, 2 digits).

## Robots

```
robots/<anim>_<team>_r<deg>[_n<frame>].png     stand, walk (directional)
robots_<type>/fire_<team>_r<deg>_n<frame>.png  weapon fire
robots/die[1-5]_<team>_n<frame>.png            death (one variant picked per unit)
robots/<flavor>_<team>[_r<deg>]_n<frame>.png   idle humor (beer, cigarette, ...)
robots/celebrate_<team>_n<frame>.png           victory celebration
```

Add a unit: create `robots_<type>/` with fire frames (or reuse another
type's), then add an entry to `UnitDefs.ROBOTS`. No entry needed to just
see it work — auto-discovery registers unknown folders with grunt stats.

## Vehicles & cannons

```
<dir>/empty_r<deg>.png            unmanned, directional (jeep, gatling,
                                   howitzer) — or plain:
<dir>/empty_null.png / empty.png  unmanned, single facing (always neutral)
<dir>/base_<team>_r<deg>_n<frame>.png   manned idle (hull for tanks)
<dir>/base_damaged_<team>_r<deg>_n<frame>.png  shown below half HP
<dir>/equiped_<team>_r<deg>.png   gun/missile-cannon manned idle
<dir>/fire_[<team>_]r<deg>_n<frame>.png muzzle FLASH (one-shot, holds its
                                   last frame; gatling/howitzer idle art
                                   IS their empty/passive art)
<dir>/top_[<team>_]r<deg>.png     turret layer — aims independently of
                                   the hull (light/APC neutral, heavy and
                                   missile launcher team-coloured)
<dir>/topf_r<deg>.png             medium tank turret (idle AND fire)
<dir>/fire_r<deg>_n00/n01.png     jeep gunner overlay (aim / flash)
<dir>/top_pop[_<team>]_n<frame>.png  turret blowing off on destruction
<dir>/wasted[_<team>].png         wreck (tanks have none — they burn)
<dir>/under_r<deg>_n<frame>.png   jeep wheel layer (no art for the
                                   vertical facings — wheels hide)
<dir>/open_<team>_r<deg>_n<frame>.png  APC doors (unload animation)
<dir>/crane_r<deg>.png            crane arm — INVERTED numbering (facing
                                   d uses r{(d+4)*45})
<dir>/hook_n<frame>.png           crane hook (16-frame swing)
<dir>/place_<team>_n<frame>.png   gunner install animation (plays once
                                   when a robot mans the hardware)
<dir>/bullet.png                  shell/rocket sprite (projectile visual)
cannons_common/init-place_n<frame>.png  shared install anim prefix
```

Building LEVELS (0-5, the map `level` field) gate each producer's
roster — see `BuildingDefs.BUILD_LISTS` (transcribed from the original
zbuildlist: the fort builds robots AND vehicles AND cannons). Higher
levels also build faster.

Unmanned hardware always resolves neutral art (`empty_null.png` /
`empty.png`) — never a team colour. Idle turrets scan (one sector per
second, like the original); tracking turrets freeze on their target.
A `projectile` key in the def (`{speed, impact, texture}`) makes the gun
fire a travelling shell that damages on impact; without it, fire is
hitscan with a tracer (lasers get a beam flash). Below half HP vehicles
smoke (facing-aware `track_dust`) and leak oil; tanks die into a
burning husk with their turret popped off.

## Effects

```
effects/<name>/<name>_n00.png ...   frames, played once at fps
```

Registered automatically. `Fx.play(name, pos)`, `Fx.explosion(pos[, big])`,
`Fx.impact(pos)`, `Fx.bullet(from, to)`, `Fx.shell(from, to, opts, on_hit)`.
Without sprite frames an effect falls back to a native `CPUParticles2D`
burst tinted from `EffectDefs.BY_NAME[name].color` — so effects work
before art exists and upgrade automatically when art appears.

## Buildings

`base_<planet>.png` (+ `_destroyed`) under `buildings/<tex-key>/`, fort
variants and bridges have their own patterns (see `Building2D._texture_path`).
Add `BuildingDefs.BY_ID` entry with size, script class, `tex` key,
`solid`, optional `fort` / `bridge_span`. The map loader instantiates
`script`, the flags/HUD come free.

## Pickups & scenery

Pickups: art in `map_items/` + a `PickupDefs.TYPES` entry (`grants` names
the upgrade). Scenery map items (non-rock, non-pickup ids) resolve through
`SceneryDefs.for_id(id, planet)` — huts are id 4, ids 5+ index
`map_object<id-5>.png`.

## Maps

Two interchangeable formats; the match, map select and the M-key map
cycle accept both:

- **JSON** from `tools/zod/map_to_json.py` (drop into
  `project/assets/maps/`) — the campaign runs on these.
- **Editable scenes** (`.tscn` in `project/assets/maps_scenes/`) — open
  one in the Godot editor to see the map tile by tile: paint the Terrain
  TileMapLayer with the planet tileset (`assets/tilesets/<planet>.tres`,
  generated), move or add Zone / building / unit / scenery nodes, then
  press F6 to fight it. Navigation derives from the painted tiles via
  `assets/tilesets/tileinfo_<planet>.json`, so editing terrain updates
  passability and water automatically.

Regenerate the scenes and tilesets after converting new JSONs:

    godot --headless --path project res://tools/build_map_resources.tscn

Both formats and the derived scenes are gitignored (original-game data).

## GOG release assets

`tools/gog/convert_assets.py` (re)builds `sounds/`, `music/` and `ui/`
from the extracted GOG release in `assets_original/gog/`:

- `audio/*.RAW` — 115 original sound effects (8-bit unsigned PCM mono,
  11025 Hz) converted to wav under their original names (EXP1, GATTGUN,
  HTANKGUN, LASERGUN, MOBIMISS...). Unit defs pick their weapon sound via
  the `sound` key; `Fx` plays explosion/impact/pickup/click sets.
- root `*.ogg` — the original soundtrack: menu loop (ipOPTIONS16), battle
  loops (ipBATTLE16, AA16, aC16, aJ16), win/lose jingles (ipWIN/ipLOSE),
  selected by `MusicPlayer`.
- `PNG/Box*.png` — the original HUD panels, composed by
  `ui/original_panel.gd` (cap-stretch-cap) behind the production panel,
  pause menu and game-over screen. `Background.png` is the title backdrop.
- `LEVEL*.MAP` in the GOG root use a different (compressed) format than
  the zod maps — not currently convertible; maps stay zod-sourced.
- Robot/vehicle sprites are engine-packed in the GOG release and not
  present as files — they stay sourced from the zod pack.

## Wired in the final sweep

- Robot idle flavors: beer, cigarette, pope, look_around, head_stretch,
  beat_ground, **confused, full_area_scan, praise_the_lord**.
- One-shot gestures: **point** (order acknowledgement), **pickup-up**
  (crate collection), **enter_apc** (boarding, completes the man on
  finish), throw/dodge loaded and available. Death variants die1-5
  **+ melt**.
- Selection voices: `selected_<type>.wav` per robot type (+ generic
  `selected_00-05`), played when a player unit is selected.
- Building animation overlays (def `anims`): radar dish, robot/vehicle
  factory spinner, repair smoke stack — hidden when destroyed.
- Destroyed art naming fixed (`base_destroyed_<planet>.png`).
- Original in-game mouse cursor (`ui/cursor/`, animated contextual
  cursor set available in the zod pack: attack/grenade/enter/...).

## Available in the packs, not yet wired (candidates)

- Ambient animals: `other/birds`, `other/hut_animals` (planet birds,
  rabbits) — converted maps carry no animal objects.
- Vehicle movement effects: track dust/sparks/oil/dirt frames, jeep
  `tire_spin_*`, APC `open_*` door animation, medium-tank `cannon_r*`
  barrel layer, `initfire` muzzle flashes.
- Robot anims: dodge, jump-*, escape_tank, tank_fire, throw (combat
  context), `exhaust_*` puffs.
- 75 `ROB*.wav` robot barks, `COMP*` computer voice, losing taunts.
- Original production/factory GUI sheets (`other/production_gui`,
  `factory_gui`), full HUD set (`other/hud`), menu art, animated
  contextual cursors, `planets_1-10-10` alt tileset.

## Missing original art (wanted)

- `cannons_missile/` is empty — missile cannons don't spawn.
- No `missile_launcher`/`crane` vehicle folders.
- `map_items/rockets.png` doesn't exist — rocket crates render blank.
- Original HUD sheets (portraits frame, money counter) beyond `ui/splash.png`.
- Explosion/projectile effect sprites — particle fallbacks cover these;
  drop frames into `effects/` to upgrade (GOG has none as files either).
- `en.lproj/` planet stingers (e_dtrav1, e_dwint1...) and cutscene audio
  are copied nowhere yet — wire per-planet stingers when wanted.

## Generating assets

Any generator (image model, script) only needs to honor the filename
patterns above and 16x16 pixel-art constraints (nearest filtering, x2
runtime scale). Nothing else in the codebase needs to change.
