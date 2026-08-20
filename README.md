# Z (1996) — Godot Remake

A fan remake of the original **Z** (The Bitmap Brothers, 1996) — the 2D
robot RTS — in Godot 4, as faithful to the original as possible using the
assets and format knowledge from the open-source
[Zod Engine](https://github.com/a-sf-mirror/zod_engine) project.

> **Status:** single-player feature-complete — the ORIGINAL 20-level
> campaign converted from the retail data plus the 57 zod maps,
> full unit roster, territory economy, production, campaign, save/load,
> a tactical CPU opponent with difficulty, and a 47-flag headless test
> suite (every flag asserts). Multiplayer: P2P lobby, in-match intent
> replication, host-authoritative resync and late join. See
> `docs/ROADMAP.md` and `docs/BUGS.md`.

The Zod Engine's **C++ source is the reference of record** — the 1996
Bitmap Brothers code was never released, and Zod is the reimplementation
this project's asset pack comes from. Behaviour is ported from it and
cited in `docs/RESEARCH.md` rather than guessed: the building burn model
(`ZBuilding::ProcessBuildingsEffects`), every explosive radius and the
splash model (`zsettings.cpp`, `ZServer::ProcessMissileDamage`), and the
AI's adaptive commitment (`ZBot::GoAllOut_3`). Read it before calling
anything underivable.

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

Headless test suite: 47 flags (`--combat-test`, `--teams-test`,
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

## The CPU opponent

One brain per non-player fort team, running a full loop each think pass:
produce from every owned facility, defend owned ground, crew the empty
hardware lying around the map, run maintenance (cranes repair, damaged
tanks visit the repair shop), hold the frontier **bridges** (the only
place armour crosses a Z map), then **assign** the rest.

The assignment is the `ZBot Stage1AI_3` port and it is what stops the
brain swarming one point:

1. **Posture** (`GoAllOut_3`) — the bot reads its share of the map's
   zones against a fair share (1/teams) and picks two numbers from it:
   what fraction of the idle army is re-tasked, and how long until the
   next cycle. Holding a fair share means a *small* slice on a *slow*
   cadence with a *wider* target list (`all_out` adds enemy units and
   robots); falling behind means re-tasking a third of the army every
   few seconds.
2. **Targets in the original's priority order** — map items (zone flags,
   crates), then buildings, then empty hardware, and enemy units only
   once all out.
3. **Mutual-nearest matching** (`MatchTargets_3` / `GiveOutOrders_3`) —
   a pair is ordered only when the unit is that target's nearest
   candidate *and* that target is the unit's. A unit with no mutual
   partner is left alone this cycle. Buildings take a squad (focus
   fire); everything else takes one, so the army fans out.

`--tactics-test` asserts the posture table flips with the map share and
that the matching spreads units instead of piling them.

## Building the desktop releases

All three targets cross-build from Linux. You need the matching Godot
**4.7.1** export templates and the icon set:

```bash
python3 tools/gog/make_icons.py        # cuts the Z logo out of the retail splash
tools/build_releases.sh                # linux + windows + macos
tools/build_rpm.sh                     # wraps the Linux binary as a Fedora RPM
```

| Target  | Output | Notes |
|---|---|---|
| Fedora  | `build/rpm/z-remake-*.rpm` (+ raw `build/linux/z-remake.x86_64`) | installs `/usr/bin/z-remake`, a `.desktop` entry and the full hicolor icon tree |
| Windows | `build/windows/z-remake.exe` | self-contained. The **Explorer file icon** stays Godot's default: embedding one needs `rcedit`, which needs wine, which is deliberately not installed. The in-game window icon is correct. |
| macOS   | `build/macos/z-remake.zip` | universal (x86_64 + arm64), **unsigned**. Cross-building is fine but signing/notarization need a Mac, so first launch needs right-click → Open, or `xattr -dr com.apple.quarantine "Z Remake (1996).app"`. A `.dmg` cannot be produced off a Mac. |

The icon is the release's own riveted metal **Z**, cropped out of
`PNG/IPSplash.png`. Because that is Bitmap Brothers art it is generated
locally into the gitignored `project/assets/icon/`, never committed.

> **Every built binary embeds the original art and sound.** The builds
> are for local use. Do not attach them to a release or redistribute
> them — `build/` is gitignored for that reason.

## Asset licensing

The original Z graphics/sounds are © The Bitmap Brothers. They are
extracted via the Zod Engine asset pack, kept **gitignored** in
`assets_original/` and `project/assets/` — every contributor copies them
locally. Do not redistribute. The code in this repo is original.
