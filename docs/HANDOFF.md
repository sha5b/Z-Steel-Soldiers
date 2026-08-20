# Handoff — 2026-08-20

State of the HUD/gameplay fidelity pass, and what is still open. Written
at the end of the session that rebuilt the in-game HUD; read this with
`docs/BUGS.md` (verified open bugs) and `docs/ROADMAP.md` (plan).

Test state at handoff: **47/47 headless lanes clean.**

## Landed this session

Verified by test unless noted otherwise.

| Area | What changed |
|---|---|
| HUD frame | The original chrome replaces the floating panels: 100px sidebar + 36px bottom bar, world inset into the rest. Clock, animated portrait, name plate, equipment art, grenade tally, 74px health bar, weapon plate, A/T/D/Z + R/V/B/G/Menu, radar in its own window, `unit_amount_bar` army gauges. `--ui-test` asserts every art file and that `view_rect()` excludes the chrome. |
| Portraits | `tools/zod/build_hud.py` recovers the SHEADBI face-piece offsets by brute force and bakes 696 whole frames per pack. Blink + talk flipbooks, battered second head below 45% HP. `--ui-test` steps the flipbook and asserts the frame changes. |
| Build menu | Rebuilt on the original's own 112x80 `base_image` window at NATIVE scale, with the Time countdown, building health %, level/progress gauges, Cancel/Ok and the garrison EXIT. |
| Hotkeys | Every key is now the letter on the plate it presses: T/D/Z (sidebar modes), R/V/B/G (bottom-bar actions), X dismount, Ctrl+digit/digit groups. |
| Selection habits | Auto-deselect on order and centre-on-select, both from the original, both switchable (`GameSettings`). |
| Capture | Taking a sector now inherits the unit on its production line with its elapsed time, instead of scrapping the queue. `--capture-test`. |
| Smart idle | Rewritten so it can never touch a unit that is doing something, and never repeats an attempt. `--orders-test` asserts both. |
| Path smoothing | `NavWorld.string_pull` removes the A* staircase. `--path-test` asserts it shrinks the path and that every kept leg is clear. |
| Fort/ground layering | Forts render entirely on the ground layer (what `BFort::DoRender` does); other buildings take their ground cut from `solid_tiles` instead of a flat 50% of art height. |
| Rock cliffs | The sheet's rows 2-4 are all cliff FACE; the autotile now draws the face top-to-base instead of always the middle row. |
| Flags | Were drawn at 2x. One `AnimLibrary.FLAG_SCALE` for all three flag sprites. |
| Turret facing | A manned gun's passive look is the `empty` set; for types named `empty_<team>_r<deg>` that resolved to one non-directional frame, so the gun snapped to its aim only while firing. |
| AI | Holds ground: posts DEFEND guards on frontier bridges (the only place armour crosses a Z map), capped at ~1/3 of the army, and guards are excluded from the push. Cannons — immobile once built — are only produced at the facility nearest the frontier. `--tactics-test`. |
| Research | `RESEARCH.md` 2e (PHRASES.BIN), 2e.1 (portrait offsets), 2f (HUD slot derivation). Corrected the stale claim that our stats were unported. |

### Landed after the handoff was written

| Area | What changed |
|---|---|
| Structures burn | Player-reported open item 2. Buildings had NO damage VFX: a fort one shot from collapse looked untouched, and the ruin it left sat clean for the rest of the match. Ported from the Zod Engine source rather than invented (`ZBuilding::ProcessBuildingsEffects`, see `RESEARCH.md` 2c): a damaged building holds a POPULATION of `max_effects * (1 - hp/max_hp)` looping effects, topped up when short, each at a uniform random point in a per-type `effects_box`; the mix is the original's one-roll 10/10/30/50 big_smoke / small_fire_smoke / fire / little_fire, so a burning structure is mostly FIRE. The loop has no destroyed check in zod either — that is exactly why a ruin goes on burning. Boxes and caps are verbatim from `bfort`/`brobot`/`bvehicle`/`brepair`/`bradar`. `--art-test` asserts the cap range, that the population grows with damage and maxes at death, that every fire lands inside the box, and that repair puts them out. |
| Debris follows the footprint | Every piece left the exact visual centre, and a one-tile hut threw the same 4 pieces as a 128px fort. `Fx.building_debris` now takes the footprint rect: origins scatter across the structure's upper two thirds and the count scales with area (1 piece per ~2x2 tiles, 4-12). |

## Open

### Reported by the player, not resolved

1. **Turrets "don't reach all around the building."** One cause of the
   *spasm* is fixed (above). The reach half is unverified — it could not
   be reproduced headlessly. **Needs a repro: which map, which gun, and
   whether the gun is a fort tower mount or a free-standing cannon.**
2. **Building smoke and debris effects** — CLOSED. The root cause was
   not tuning: **structures never burned at all.** Now ported verbatim
   from the Zod Engine source, not guessed (`Fx.burn_effect`,
   `Building2D._burn_fx`, `--art-test`; model and constants in
   `RESEARCH.md` 2c). Eyeball with `--screenshot 3 --burn-building`.
3. **Cliff faces** — improved but not confirmed against the original.
   Still unused in the autotile: the shadow column (col 4) and the
   rubble column (col 5) of `rocks_<planet>.png`, and row 5 (the ground
   at the foot of the drop). If cliffs still read flat, those three are
   where the remaining depth cues live.
4. **The non-fort ground cut is a visible change.** Radar, repair and
   both factories now have NO ground band at all (their `solid_tiles`
   covers their whole art), so they Y-sort as one sprite. That is
   correct by the data but it is the first time it has been seen —
   worth a look at a unit walking past a factory's south edge.

### Known divergences from the original (decisions, not bugs)

5. **Z has no resource; we have money.** The original's only currency is
   TIME — build seconds, scaled by how many sectors you hold
   (`BuildTimeModified`, implemented). Our `cost`/`spend` layer on top is
   an addition: every unit def carries a cost, the AI banks before
   committing to vehicles, and `--balance-test` asserts "no free
   producers". Removing it would touch the defs, the AI's banking, the
   save format and several tests. **Nobody has decided whether to.**
6. **HUD button semantics are ours.** Nothing the release ships records
   what A / T / D / Z / R / V / B / G mean. The bindings are documented
   as ours in `hud_frame.gd` and `selection_filters.gd`. The one thing
   the art *does* tell us is which are modes and which are actions (the
   frame draws the sidebar four inactive and the bottom five active).
7. **Build-picker UX.** The roster flyout is ours; the pack ships
   `factory_gui` art for a scrolling list (`main_entry`, `scrollbar_*`,
   `fup`/`fdown`) which is probably what the original used. The player
   said "forget it" for now — the art is copied and waiting.

### THE ZOD ENGINE SOURCE IS READABLE (2026-08-20)

The whole C++ source is public and fetchable file by file
(`github.com/capehill/zodengine`, mirrors on `erezsh/zodengine` and
SourceForge). Several items below and in `docs/BUGS.md` were written as
"cannot be derived" when they only needed this. Already used it to port
the building burn model and to verify every area-of-effect number.
**Read it before calling anything underivable.** The 1996 Bitmap
Brothers code itself was never released — Zod is the reimplementation
the whole asset pack comes from, and is the reference of record.

Known next candidates:
- `orock.cpp` — the rock autotile table. `docs/BUGS.md` open item 9
  says closing it "needs the original `orock.cpp` table; it cannot be
  derived from the art alone". It can just be read.
- `zbuilding.cpp` `level_img[MAX_BUILDING_LEVELS]` — loaded, but
  `BFort::DoRender`/`DoAfterEffects` draw only the base surface, the
  production `show_time_img` and the team flag. **No level digit is
  drawn in the world**, so our `Building2D._build_level_plate` map digit
  is ours (and its art comes out of `ui/hud/`). The production panel
  already shows level as a gauge.
- `zpath_finding*.cpp`, `zbot*.cpp` — formation movement (item 12) and
  the AI's real behaviour list (item 13) instead of our approximations.

### Reverse-engineering still open

8. **`PHRASES.BIN` per-frame stream** (`RESEARCH.md` 2e). The record
   layout is known — 64 records of 552 bytes, 31-char name plus a
   per-frame animation stream — and the names give the whole expression
   set. The stream itself is not decoded, so the portraits blink and
   talk but do not lip-sync.
9. **Portrait gesture pieces.** The 64x64 and 48x64 cut-outs (5+2 per
   folder) are the salute and thumbs-up hands named in the phrase table.
   They are LARGER than the base head, so the offset search has nothing
   to lock onto and their placement is unknown.
10. **`ROB23-75` bark mapping.** The phrase table names 46 voiced lines
    and the group boundary matches (`ROB01-22` really are the 22
    selection/order lines), but the order-preserving hypothesis fails on
    clip length, so the remaining 53 files stay an unlabelled pool.
    `Fx.chatter()`/`Fx.distress()` draw from it without claiming which
    line is which.
11. **`LEVEL.MAP` leftovers** (`RESEARCH.md` 6.12): byte 0, the rock
    record's bytes +4/+5/+6, the four 138-byte records at 9417, plane 2
    bits 0-6, most of each region record, `robots.dat`.

### Engineering follow-ups

12. **No formation movement.** Orders scatter units on a ring offset;
    the original clones a leader's waypoints to its minions
    (`RESEARCH.md` 2d, "unit GROUPS with leader/minion waypoint
    cloning").
13. **AI has no chokepoint concept beyond bridges.** A map with no
    bridges gets no guards. A grid-derived corridor pass (open cells
    with few open neighbours) would cover those maps. Also absent:
    retreat/regroup, focus fire, and using the APC to move infantry.
14. **Path smoothing is bounded at `SMOOTH_WINDOW = 24` points** to keep
    it linear. Long cross-map routes still keep corners every ~24 cells
    that a full string-pull would remove.
15. **Three screenshot aids in `match.gd`:** `--select-first`,
    `--select-factory` and `--burn-building` (drops the player's first
    structure to 12% HP and pans to it, so the burn VFX can be judged),
    in the same spirit as the existing `--dump-visible`. They exist so
    visual changes can be eyeballed from one run; delete them if that
    stops being useful.

## Not mine

These files were already modified in the working tree before this
session and are unrelated to it: `scripts/core/campaign.gd`,
`scripts/game/map_catalog.gd`, `scripts/game/map_loader.gd` (the retail
campaign work), `content/match/default.tres`,
`scripts/content/defs/match_rules_def.gd`, `scripts/tests/terrain_tests.gd`,
`tools/build_map_resources.gd`, `tools/gog/level_to_json.py`,
`docs/BUGS.md`.
