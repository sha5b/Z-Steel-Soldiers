# Z (1996) — Godot Remake

A fan remake of the original **Z** (The Bitmap Brothers, 1996) — the 2D
robot RTS — in Godot 4, as faithful to the original as possible using the
assets and format knowledge from the open-source
[Zod Engine](https://github.com/a-sf-mirror/zod_engine) project.

> **Status:** single-player feature-complete — the ORIGINAL 20-level
> campaign converted from the retail data plus the 57 zod maps,
> full unit roster, territory economy, production, campaign, save/load,
> AI with difficulty, and a 46-flag headless test suite (every flag
> asserts). Multiplayer: P2P lobby, in-match intent replication,
> host-authoritative resync and late join. See `docs/ROADMAP.md` and
> `docs/BUGS.md`.

## Environment

- Godot **4.7.1 stable** (Flatpak: `org.godotengine.Godot`)
  ```bash
  flatpak run org.godotengine.Godot   # open project/project.godot, press F5
  ```
- Controls: WASD/arrows/edge pan, wheel zoom, drag = box select,
  right-click = order. **Every hotkey is the letter printed on the HUD
  plate it presses**, so the frame teaches its own keyboard — sidebar
  `T` smart idle, `D` defend, `Z` attack-move (D and Z are toggles;
  neither lit = plain move), bottom bar `R` all robots, `V` all
  hardware, `B` cycle factories, `G` cycle control groups, plus `X`
  dismount and Ctrl+digit / digit for control groups (a second press
  jumps the camera to that squad). Two original habits are on by
  default: an order DROPS the selection, and clicking a unit CENTRES
  the camera on it. The release's own 7 tutorial pages are on the title
  menu under **How To Play**.

## Repository layout

| Path                | Purpose                                             |
|---------------------|-----------------------------------------------------|
| `docs/`             | Research notes, roadmap, asset conventions          |
| `project/`          | Godot project (2D)                                  |
| `assets_original/gog/` | Extracted GOG release: sfx, soundtrack, HUD art (gitignored, 383 MB) |
| `assets_original/zod/` | Zod Engine asset set — unit/map sprites (gitignored, 84 MB) |
| `project/assets/z/` | Working asset set, built by `tools/gog/convert_assets.py` (gitignored) |

Asset tools live in `tools/`: `gog/level_to_json.py` (the original
20-level campaign from the retail `LEVEL##.MAP` data — format notes in
`docs/RESEARCH.md` §6), `gog/convert_assets.py` (sfx, music, HUD art), `zod/copy_art.py` (declarative copier for the zod pack),
`zod/build_hud.py` (the in-game HUD frame's own pieces, and the animated
head portraits — it recovers the face-piece offsets by brute force and
bakes whole frames; see `docs/RESEARCH.md` §2e),
`zod/map_to_json.py` + `zod/tileinfo_to_json.py` (map and terrain
tables) and `zod/verify_map_planets.py` (audits — and repairs — the
planet tag on every converted map; run it after any map conversion).

Maps are playable as JSON or as editable Godot scenes — open any
`project/assets/maps_scenes/*.tscn` in the editor, paint terrain with the
generated tilesets, move buildings/zones/units, press F6 to play; regenerate
them from the JSONs with `godot --headless --path project
res://tools/build_map_resources.tscn`.

Project code layout — autoloads: **ContentDB** (content registry,
inspector-editable `.tres` defs under `content/`), **Fx** (presentation),
**SaveSystem** (per-entity save contract), **NavWorld** (pathing),
**MatchState** (economy, upgrades, caps), **UnitRegistry** (typed unit
queries), **GameState** (match flow/win), **SelectionManager**,
**MusicPlayer**, **Campaign**. Then: `scripts/content` (Resource def
classes), `scripts/entities` (units, buildings, effects, scenes under
`scenes/{units,vehicles,cannons,buildings}`), `scripts/game` (orders,
combat, spawner, map loader/catalog, AI, self-tests), `scripts/ui` (HUD,
signal-driven). Adding content (units, buildings, pickups, effects,
maps, team colours) is documented step by step in
`docs/ASSET_CONVENTIONS.md` — copy a `.tres`, drop an art folder.

Headless test suite: 46 flags (`--combat-test`, `--teams-test`,
`--scenes-test`, ...), run in parallel lanes from `project/`:
`res://scenes/main.tscn --<flag>-test --quit-after N`. **`--quit-after`
counts FRAMES, not seconds** (Godot's own option): the real-physics
lanes (`--placement-test`, `--garrison-test`) need a few thousand, so
use `--quit-after 6000` for a whole-suite sweep. A run passes with zero
`SCRIPT ERROR` and zero `CHECK FAILED:` lines — the harness lives in
`project/scripts/tests/` (TestRig is the assertion helper, per-domain
modules like path_tests.gd, terrain_tests.gd and garrison_tests.gd split
out of self_tests.gd). EVERY flag now reports through TestRig, so a
regression fails the run instead of printing a number nobody reads.
Screenshot verification: add `--screenshot <seconds>` (warps the mouse
so edge pan stays put).

## Asset licensing

The original Z graphics/sounds are © The Bitmap Brothers. They are
extracted via the Zod Engine asset pack, kept **gitignored** in
`assets_original/` and `project/assets/` — every contributor copies them
locally. Do not redistribute. The code in this repo is original.
