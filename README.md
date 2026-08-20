# Z (1996) — Godot Remake

A fan remake of the original **Z** (The Bitmap Brothers, 1996) — the 2D
robot RTS — in Godot 4, as faithful to the original as possible using the
assets and format knowledge from the open-source
[Zod Engine](https://github.com/a-sf-mirror/zod_engine) project.

> **Status:** single-player feature-complete — all 57 original maps,
> full unit roster, territory economy, production, campaign, save/load,
> AI with difficulty, and a 34-check headless test suite. Multiplayer
> intentionally out of scope. See `docs/ROADMAP.md`.

## Environment

- Godot **4.7.1 stable** (Flatpak: `org.godotengine.Godot`)
  ```bash
  flatpak run org.godotengine.Godot   # open project/project.godot, press F5
  ```
- Controls: WASD/arrows/edge pan, wheel zoom, drag = box select,
  right-click = move order.

## Repository layout

| Path                | Purpose                                             |
|---------------------|-----------------------------------------------------|
| `docs/`             | Research notes, roadmap, asset conventions          |
| `project/`          | Godot project (2D)                                  |
| `assets_original/gog/` | Extracted GOG release: sfx, soundtrack, HUD art (gitignored, 383 MB) |
| `assets_original/zod/` | Zod Engine asset set — unit/map sprites (gitignored, 84 MB) |
| `project/assets/z/` | Working asset set, built by `tools/gog/convert_assets.py` (gitignored) |

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

Headless test suite: 37 flags (`--combat-test`, `--teams-test`,
`--scenes-test`, ...), run in parallel lanes from `project/`:
`res://scenes/main.tscn --<flag>-test --quit-after N`. A run passes
with zero `SCRIPT ERROR` and zero `CHECK FAILED:` lines — the harness
lives in `project/scripts/tests/` (TestRig is the assertion helper,
per-domain modules like path_tests.gd split out of self_tests.gd).
Screenshot verification: add `--screenshot <seconds>` (warps the mouse
so edge pan stays put).

## Asset licensing

The original Z graphics/sounds are © The Bitmap Brothers. They are
extracted via the Zod Engine asset pack, kept **gitignored** in
`assets_original/` and `project/assets/` — every contributor copies them
locally. Do not redistribute. The code in this repo is original.
