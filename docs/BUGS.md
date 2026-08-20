# Known bugs & tolerated baselines

Live tracker for verified, evidence-backed bugs. Everything here has a
file:line root cause. Fixed items move to the bottom section with the
commit that fixed them — do not delete history.

## Open — verified, not yet fixed

Each of these was confirmed by reading the code or counting the data,
not inferred. They are listed in the order I would fix them.

1. **`map_item` id 0 is the zone flag, and 956 of them are discarded** —
   `scripts/content/scenery_defs.gd:23` returns `{}` for id 0, so
   `map_loader.gd:_spawn_map_item` drops it. Counted across
   `assets/maps/*.json`: **956 id-0 objects on 57 of 58 maps**, owner
   byte `{0: 626, 1: 135, 2: 135, 3: 36, 4: 15, 5-8: 9}` — perfectly
   team-symmetric, so it is authored data, not noise. Per map,
   `zones - id0_count` equals the map's player count, which matches the
   "a zone holding a fort flies no flag of its own" rule in
   `entities/zone.gd`. Two consequences: flag positions are re-derived
   from zone-rect centres instead of the designer-placed tile, and
   `map_loader.gd:_build_zones` hardcodes `owner_team = 0`, so **330
   pre-owned territories start neutral on every map**. Fixing it shifts
   opening income and balance on all 58 maps, so it is a design call,
   not a drop-in patch.

2. **All 58 map scenes are unreachable; `MapCatalog` inverts its own
   contract** — `scripts/game/map_catalog.gd:14-37`. The docstring says
   *"Scene versions replace their JSON twins"*, but the code fills
   `json_names` from `assets/maps` FIRST and then registers a `.tscn`
   only `if not json_names.has(basename)`. Both directories hold the
   same 58 basenames, so `entries()` yields 58 JSON and 0 scenes,
   permanently. `MapLoader.load_map_scene` (162 lines, plus
   `_clear_bridge`/`_tileinfo`/`_water_array`/`_tree_children`) never
   runs in normal play, and the editor workflow advertised in
   `README.md` is reachable only via `--map=` or F6. Flipping the
   condition switches every map to a loader path that play has never
   exercised — do it behind `--scenes-test` coverage first.

3. **Neutral objects are immune to splash, which makes empty hardware
   indestructible** — `scripts/game/combat.gd:86,90` both require
   `team != 0` (units and buildings), and `unit_2d.gd:_find_target_within`
   skips `b.team == 0`. Unmanned vehicles and cannons spawn at team 0
   (`producer.gd`, `Vehicle2D.eject_driver`), so they can be neither
   targeted nor blown up. The same guard makes the fully implemented
   destructible-bridge path (`building.gd:_bridge_damage` / `repair_by`,
   with rubble solids and crane repair) unreachable: **230 of 235
   bridges across the shipped maps load with `owner = 0`**. The only
   caller of bridge damage in the repo is a self-test that calls
   `take_damage` directly. This is a balance change, so it wants a
   deliberate decision rather than a silent flip.

4. **Pickup upgrades are dead data** — `content/defs/pickup_def.gd:10`
   documents `upgrade_key` as the team-upgrade grant, but neither
   `content/pickups/grenades.tres` nor `rockets.tres` sets it, so
   `entities/pickup.gd:44` never fires. `MatchState.has_upgrade` is
   therefore always false and `ui/top_bar.gd:_sync_upgrades` can never
   render. `ROADMAP.md`'s "+40% robot / +60% vehicle damage" claim has
   no corresponding multiplier anywhere in `combat.gd`, and
   `rockets.tres` is a clone of `grenades.tres`.

5. **Most test flags cannot fail** — `scripts/tests/self_tests.gd` has
   43 flags and 8 `TestRig.start` call sites; every other block
   accumulates a local array and `print()`s it. `--parade-test` and
   `--pose-test` print the literal `FAIL`, which is not the
   `CHECK FAILED:` string the documented pass criterion greps for. Any
   "verified by --x-test" claim in the docs rests on this.

6. **Multiplayer sims diverge structurally, not just by float drift** —
   `map_loader.gd` spawns a `CpuAi` per non-human team on every peer and
   `cpu_ai.gd` uses unseeded `randi()`/`randf()`, so after the first CPU
   production the peers hold different rosters and `_next_net_id`
   diverges. `ROADMAP.md` admits only float-physics drift. Related:
   `net.gd:push_state` (the shipped economy-resync entry point) has no
   callers — the test drives `Net._apply_state` directly.

7. **Crane `arm_off` dead data** — WONTFIX, documented: the rig renders
   correctly via canvas alignment (the `hook_off` table IS applied);
   folding `arm_off` in has no proven defect to fix and no headless way
   to verify the visual.

## Fixed

- 2026-08-20 — **the pathfinding root cause**: `AStarGrid2D.offset` was
  never set, so `get_point_path` returned cell TOP-LEFT CORNERS, half a
  cell up-left of the cell each waypoint stood for. Every breadcrumb sat
  on a 4-cell junction, so routes through 1-2 cell gaps (the fort gate)
  aimed at the wall line and units ground themselves against it. Fixed
  in `NavWorld.make_grid` — the one grid factory, `offset = CELL/2`
  (cell-centre contract documented at the top of `nav_world.gd`), used
  by both loader paths. The `--path-test` walker went from ~10/147
  solid-cell samples to **0**, and `PathTests.KNOWN_CROSSING_BASELINE`
  dropped 16 -> 0. Also in this pass:
  - diagonal mode `AT_LEAST_ONE_WALKABLE` -> `ONLY_IF_NO_OBSTACLES`:
    the permissive mode let a leg pass exactly through a wall corner,
    which was the last 1/145 of grazing.
  - `BODY_HALF` vehicle/cannon 9.0 -> 7.5. 9.0 exceeds a half cell, so
    every cell touching a wall probed dirty and no vehicle could
    legally stand, spawn, eject or park along any building.
  - `_build_vehicle_grid` used the LOCAL row-major index as a cell id,
    which shifted every water cell on any scene map not starting at
    (0,0).
- 2026-08-20 — **units could not reach anything standing on a solid
  cell**. `Unit2D._begin_move` aimed `move_target` at the raw requested
  point; for a building order the anchor is the footprint CENTRE, which
  is wall, so `_arrive()` never fired and `_try_enter` (which waits on
  `move_target` clearing) never resolved. Robots pressed into the fort
  gate forever. `move_target` is now the END of the computed route.
  `_try_enter` additionally boards stranded hardware from arm's length
  (`STRANDED_REACH`) and gives the order up beyond that, so a robot
  ordered onto an unreachable hull lands back in IDLE instead of
  holding ENTERING for the match. Fort tower guns (mounted on solid
  cells by design) can now be re-crewed after a sniper kill; the mount
  occupancy rule is one predicate (`FortBuilding._slot_taken`) shared
  by the build gate and `mount_product`, which used to disagree.
  Guarded by the new `--garrison-test`.
- 2026-08-20 — **garrisoning a fort freed the robot**
  (`Unit2D._building_order` called `queue_free()` after
  `garrison_robot`). The garrison array filled with freed entries, so
  the missile battery fired forever with no crew, `kill_garrison()` was
  a no-op, `garrison_cap` counted ghosts and the defenders dropped out
  of the no-units rule that is supposed to count them. Robots now stay
  alive and carried, exactly like APC cargo. Asserted by
  `--garrison-test`.
- 2026-08-20 — **the production queue showed no icons**. The original
  HUD icons sit on a fixed 96px-wide canvas around a small sprite, and
  the queue slots were 40x44 squares whose theme plate ate 10px of
  content margin per side — `expand_icon` scaled a grunt to about
  20x7px. Icons are now cropped to their opaque region (the shared
  `ProductionPanel.icon_for`, reusing `UiTheme.trimmed`) and drawn in
  landscape slots with slim content margins. The panel's vertical
  budget was also 245px of 240 available, which pressed the queue row
  onto the panel's bottom bevel; it is now 225 of 240.
- 2026-08-20 — the facility quick bar shows the **queued count**
  (`queued/cap`, red when full) beside the queue thumbnails.
- 2026-08-20 — `Building2D.net_id` was declared and never assigned, so
  every multiplayer facility intent travelled as id 0 and `MatchRelay`
  resolved it to whichever building came first in the group. Buildings
  now take an id from `UnitRegistry.next_building_net_id()` in map
  order.
- 2026-08-20 — `Unit2D.portrait_path` probed only `empty_r270.png`,
  which **3 of 11** hardware types ship; the other 8 showed a blank
  selection portrait. It now uses the shared
  `ProductionPanel.hardware_art` fallback walk (all 11 resolve).
- 2026-08-20 — `Decals.track` requested `_r%03d` for all 8 headings,
  but the original ships only `{E, NE, N, SE}`, so **half of all
  vehicle headings laid no tracks**. It now goes through
  `AnimLibrary.dir_texture`, which mirrors the missing four (that
  helper existed and had no callers at all).
- 2026-08-20 — `Building2D._exit_tree` called
  `MatchState.current.unregister_facility` unguarded; on scene teardown
  the match-scoped `MatchState` can already be gone.
- 2026-08-20 — `KEY_M` cycled the map mid-match in exported builds with
  no confirmation; now gated behind `OS.is_debug_build()`.
- 2026-08-20, `d91e75c`+ — tracker truth pass: the radar-dish padding
  (building.gd `_overlay_frames` — content-bbox centred, foot-aligned),
  the BRIDGE span top-left probe and the cursor dead branch were ALREADY
  fixed by the grand sweep; the gatling cannon gained
  `building_frac = 0.0027` (jeep-class interpolation — the original
  table does not cover it).
- 2026-08-20, phase 1 — the three reported bug classes (see git log
  d842009 / 5a5c599 / d7ce62a: driverless rallies, placement teleports
  + corner pockets, unkillable forts).
- 2026-08-20, `131b64e` — the consolidated 35-item sweep.
