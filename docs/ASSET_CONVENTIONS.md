# Asset conventions & adding content

The game is data-driven: gameplay code never hardcodes a sprite path or
unit stat. Everything flows through two pieces:

- **`scripts/content/*.gd`** — definition tables (stats, folders, costs).
- **`ContentDB`** (autoload) — merges those tables and auto-discovers
  sprite folders on disk that have no entry yet.

Drop correctly-named PNGs into `project/assets/z/` and they become
playable content. This file lists the naming patterns the scanners look
for — they double as a spec for generated assets.

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
Directions `r000 r045 r090 ... r315` face +X, down, -X, up (8 total).
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
<dir>/empty_r<deg>.png            unmanned, directional  — or plain:
<dir>/empty.png / empty_<team>.png  unmanned, single facing
<dir>/base_<team>_r<deg>_n<frame>.png   manned idle
<dir>/fire_[<team>_]r<deg>_n<frame>.png firing (shared when no team art)
<dir>/wasted.png                  wreck
<dir>/under_<team>_r<deg>_n<frame>.png  jeep wheel layer
```

A `projectile` key in the def (`{speed, sprite, impact}`) makes the gun
fire a travelling shell that damages on impact; without it, fire is
hitscan with a tracer.

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

JSON from `tools/zod/map_to_json.py` (drop the output into
`project/assets/maps/`). No registration needed — map select and campaign
pick up every `.json` automatically.

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
