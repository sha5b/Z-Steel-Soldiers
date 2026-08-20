# Known bugs & tolerated baselines

Live tracker for verified, evidence-backed bugs. Everything here has a
file:line root cause. Fixed items move to the bottom section with the
commit that fixed them — do not delete history.

## Open — verified, not yet fixed

Each of these was confirmed by reading the code or counting the data.
They are listed in the order I would tackle them. Nothing here is a
one-line fix; the cheap, evidence-backed ones are all in Fixed below.

1. **The shipped map set is the zod MULTIPLAYER pack, not the original
   campaign** — reading each JSON's internal `name`, 56 of 57 read
   `clone_map` (orig01-35 = 2P, p03m01-10, p04m01-10) and
   `p08_sc_hunters` reads `Starcraft_Hunters`. The actual 20-level
   Bitmap Brothers campaign lives in `assets_original/gog/` as
   `LEVEL{01-20,26-29,31}.MAP` plus 100 `OBJECT/BUILD/BRIDGE/CPUPLR##.DAT`
   object tables and `levels.dat`/`robots.dat`/`mult.dat` — **128 files
   with zero parsers anywhere in `tools/`**. `Campaign` therefore chains
   the map list in alphabetical filename order with no planet
   progression. This is the single biggest content gap left.

2. **Terrain animation is NOT impossible** — `ROADMAP.md` closes it as
   "single-frame tile art, nothing to animate from". The zod
   `planets/<planet>.tileinfo` files are 480 tiles x 12 bytes and carry
   `is_effect` + `next_tile_in_effect`, which form closed 4-frame rings
   (desert 50 animated tiles, city 40, arctic 25, volcanic 18, jungle 0);
   the frames of each ring are already distinct images inside
   `assets/z/planets/<planet>.png`. Both converters throw the fields
   away (`tools/zod/tileinfo_to_json.py` emits only `[water, passable]`,
   `map_to_json.py` keeps 3 of 10). Needs a converter change plus a tile
   animator. Caveat: the last 4 bytes of that record
   (`takes_tank_tracks`/`crater_type`/`is_starter`) read implausibly and
   the layout for them is unverified.

3. **`SetMapImpassables` is transcribed for 2 of 7 building types** —
   `solid_tiles`/`open_tiles` exist for `fort_front`, `fort_back` and
   `radar`; `repair.tres`, `robot_factory.tres` and
   `vehicle_factory.tres` carry none, so their entire art rect is solid.
   Factories should have walkable aprons like the forts do.

4. **~29 of 43 test flags still only print** — 14 now assert through
   TestRig in `self_tests.gd` plus 3 domain modules (was 7 total). The
   rest accumulate a local array and print it, so a regression in those
   domains still reads as a passing run.

5. **Multiplayer is not deterministic** — the AI fork is fixed (host-only
   brains, intents relayed, economy resync now actually running on a
   cadence), but peers still apply the same intents to their own float
   physics, so positions drift. Full-entity resync and late-join both
   reuse the save contract and are unimplemented.

6. **Converted-but-unreferenced art, in rough value order** — the full
   original HUD frame (`ui/hud/main_hud*.png`, 10 files, including the
   selected-object trio), 30 `unit_label_*` name plates, 6 minimap
   `backdrop_*` frames, 84 building/fort death-debris pieces, and **176
   robot animation frames** for `escape_tank` / `tank_fire` /
   `jump-*` that are in neither `AnimLibrary.IDLE_FLAVORS` nor
   `GESTURES` — `escape_tank` + `tank_fire` alone is a whole original
   mechanic (the crew visibly operating and bailing out of a tank).

7. **Never converted out of the zod pack** — 256 rock-destruction debris
   frames (all 5 planets share one generic `effects/debris`), 60 bridge
   debris frames, 228 ambient-bird frames (the bird CALL wavs are
   already converted and unreferenced), 6 building level plaques (levels
   0-5 are fully implemented and the player cannot read them), 42 of 48
   production-GUI chrome files, 51 of 75 `ROB##` barks, tank dirt spray,
   exhaust puffs, announcer plaques, and 7 of 8 order-confirmation
   cursors. `tools/zod/copy_art.py` is the place to add them — it now
   exists for exactly this reason.

8. **`tools/gog/convert_assets.py` deletes a file it just created** —
   line ~65 converts `audio/GRENADE.RAW` to `sounds/GRENADE.wav`, then
   line ~121 unlinks it with the comment "replaced by GRENADE.RAW".
   `fx.gd` then substitutes the grenade-launcher shot and its comment
   blames an upstream gap that does not exist.

9. **Still missing features** — control-group hotkeys (no digit actions
   in `project.godot` at all), veterancy (no rank/XP field anywhere),
   late-join, GOG cutscenes (94 `.jv[iv]` pairs, no parser) and the
   tutorial screens (37 of 72 GOG PNGs unconverted).

10. **`move_target == Vector2.ZERO` is the "no order" sentinel** — a real
    destination at the world origin is indistinguishable from "no
    order". Structural smell, not a live bug; wants an explicit flag or
    `Vector2.INF`.

11. **No building registry** — `Unit2D._find_target_within` scans the
    `all_buildings` group per unit per combat tick, and
    `Combat.area_damage` scans it per explosion. A `BuildingRegistry`
    mirroring `UnitRegistry` removes about six per-frame tree scans.

12. **Crane `arm_off` dead data** — WONTFIX, documented: the rig renders
    correctly via canvas alignment (the `hook_off` table IS applied);
    folding `arm_off` in has no proven defect to fix and no headless way
    to verify the visual.

## Fixed

- 2026-08-20 — **rock fields rendered as flat light-brown slabs.**
  `_build_rocks` gave EVERY clustered rock one hard-coded piece, (1,1),
  which is the plateau INTERIOR fill of a 6x6 autotile sheet — so a rock
  field came out as a featureless pale blob with a stepped outline that
  read as a misplaced texture sitting on top of the map. Pieces are now
  chosen from the 4-neighbour mask (`MapLoader._rock_piece`): left /
  middle / right / single columns, and top-edge / interior / south
  CLIFF-FACE rows. The two constants the old code used are exactly the
  special cases of that mapping, which is what confirmed the layout — a
  lone rock is single-width with nothing below it, (3,3), and a fully
  enclosed rock is middle-column interior, (1,1). KNOWN LIMIT: the
  mapping uses 8 of the 36 pieces and ignores DIAGONAL neighbours, so
  inner corners where two arms of a formation meet still show a straight
  edge instead of a corner piece. Closing that needs the original
  orock.cpp table; it cannot be derived from the art alone.
- 2026-08-20 — **the terrain tilesets are NOT broken.** Checked rather
  than assumed: all five planet sheets are 320x384 = 20x24 = 480 cells,
  and the highest tile index any shipped map uses is 479 (jungle). The
  index -> atlas mapping in `_build_terrain` is in range for every map,
  so the "chaotic tileset" look was the rock bug above, not terrain.
- 2026-08-20 — **auto-grab cancelled your orders.** `_smart_idle` fired
  the moment `move_target` cleared — i.e. the instant a robot reached
  the spot you sent it to — so 0.4s after arriving it walked off to a
  zone centre or an empty hull up to 110px away. Worse, the zone branch
  re-issued `move_to(centre)` every 0.4s forever for a zone the unit
  could not take (a live fort holds its ground), which reads as a unit
  standing still doing nothing and ignoring commands. Auto-grab now
  requires the unit to have been genuinely AT REST (no order, no target,
  state IDLE) for `AUTO_IDLE_DELAY`, skips zones it is already standing
  in, and retries slowly. Its idle clock also uses the delta it was
  stepped with instead of `get_process_delta_time()`, which is the real
  frame delta and is nearly zero in an unthrottled headless run.
  Asserted both ways by `--orders-test`.
- 2026-08-20 — **there was no ATTACK order at all.** `Order.Type` had
  MOVE / MOVE_ATTACK / DEFEND / MAN_VEHICLE / BOARD_APC / GARRISON /
  REPAIR_BUILDING / CRANE_REPAIR and nothing that named an enemy, so
  right-clicking a foe fell through to a plain move: the unit walked to
  where that enemy stood at click time and stopped, while the cursor had
  been showing "attack" all along. Added `Order.attack`, a chase step
  (`Unit2D._chase`) that re-routes when the target drifts past
  `CHASE_REPATH`, holds at weapon range, and ends the order only when
  the target dies — plus `_ordered_or_nearest()` so an explicit order
  outranks opportunistic targeting. `Commands._find_enemy` dispatches it
  for players (neutral team-0 hardware still means "go man it"), and
  vehicles chase too. Asserted by `--orders-test`.
- 2026-08-20 — **buildings cut units in half with their own ground.** A
  building's art is one image that also contains its apron, its cast
  shadow, and — on the repair shop and radar — painted TERRAIN along the
  right edge. As a single Y-sorted sprite the whole block sorted at the
  wall base, so a unit north of that line was covered by dirt pixels.
  The art below the sort line is ground by construction, so it now lives
  on its own sprite at the decal z layer (`Building2D._split_ground_layer`),
  where z ordering puts it under every unit regardless of y; the
  structure above the line keeps normal Y-sorting, so walking BEHIND a
  factory still hides the unit, which is correct. This is the
  "ground bases split from the structure" the roadmap already claimed.
  RESIDUAL: terrain baked in ABOVE the cut line (the repair shop's
  upper-right corner) can still occlude, and it visibly mismatches the
  map's own ground. That is a source-art problem — the building sprites
  were cut with terrain attached — and needs the art re-cut, not code.
- 2026-08-20 — **the minimap's ownership overlay never refreshed.**
  `minimap.gd` connected a 0-argument `_refresh_owners` to the 1-argument
  `zone_captured` signal, so every capture threw
  "Method expected 0 argument(s), but called with 1" at emit time and the
  handler simply never ran. Fixed, and `--ui-test` now performs a
  REFLECTIVE arity audit over every signal on MatchState,
  SelectionManager, UnitRegistry and GameState, so the whole bug class
  (silent at parse time, only visible as a runtime error nothing greps
  for) cannot come back. Verified by reintroducing the bug and watching
  the audit name it.
- 2026-08-20 — **the mission briefing led with a tileset dump.**
  `ui/planets/<terrain>.png` is not planet art: it is the GOG release's
  320x200 terrain SAMPLE MOSAIC, a patchwork of ground tiles. It was the
  hero image while the real generated map thumbnail sat in the corner.
  The map is now the briefing image and the mosaic is gone.
- 2026-08-20 — **the map list's scroll gutter rendered as colour noise,**
  and its rows were ragged. Two causes. (1) `UiTheme._nine_piece`
  mis-placed 6 of 9 pieces: `part.ends_with("left")` also matches
  "top_left"/"bottom_left", so the left column and both left corners
  were blended at x = left_width instead of 0; `right` landed in the top
  row; and only the bare "bottom" piece matched `ends_with("bottom")`,
  so both bottom corners sat in the middle row. The composed atlas was
  scrambled, and zod's list frame puts its 15px-wide SCROLL GUTTER in the
  right column, which is where the garbage showed. Placement is now an
  explicit (col, row) table, margins come from the CORNERS (this art has
  3px edges but 17px corners, so slicing at the edge heights cut through
  them), and thin edge strips are tiled to fill their band. (2) The list
  handed `MapPreview.texture` straight to `ItemList`, and those are one
  pixel per map TILE — 64x86 up to 256x256 — so every row was as tall as
  its own icon and the widest item made the list scroll sideways.
  `MapPreview.thumbnail` letterboxes to a square and the list sets
  `fixed_icon_size`. The original's own `list_scroller` and up/down
  arrow art is now wired too (`UiTheme._theme_scrollbar`); it had never
  been referenced, so every scrolling list drew Godot's default grey bar
  inside Z's gutter.

- 2026-08-20 — **you can get your units back out of things.** There was
  no dismount action anywhere: a robot ordered into a fort went
  invisible, degrouped and unselectable for the rest of the match, a
  crewed hull could never be un-crewed, and an APC squad only came out
  by arriving somewhere. `Commands.eject()` is the one action for all
  three (X, or the production panel's EXIT button, which shows the
  garrison count); `FortBuilding.release_garrison` is the reverse of
  `garrison_robot` with body-validated placement. The original's
  `exit_*` cursor art — 32 frames that no code path could reach — is
  what the hover now shows over an ejectable selection. Asserted by
  `--cursor-test`.
- 2026-08-20 — **buildings no longer flash their own ground.** A
  building's art is ONE image that includes its ground platform (the
  fort's whole apron lives in `fort_<planet>_front.png`), so
  `take_damage`'s `modulate = Color(3, 3, 3)` blew the terrain white
  along with the walls and a fort under sustained fire strobed its
  entire tile footprint. There is no separate platform layer in the
  shipped art to exclude, so damage feedback is now a LOCAL spark at the
  impact point (`Building2D._hit_flash`); `Combat` passes the impact
  position down every weapon path. Bridges got the same treatment —
  their art IS the road surface units stand on. The destroyed-bridge
  darkening stays, because that is a state and not a flash.
- 2026-08-20 — **`map_item` id 0 is the zone flag, and all 956 were
  being dropped.** `SceneryDefs` has no art for id 0, so the loader
  discarded every one. Verified across the shipped maps: 956 markers,
  every single one inside a zone, exactly one per zone, never two in the
  same zone — 956 of 1118 zones, the other 162 being fort zones that fly
  the fort's own flag. 330 carry a non-zero owner. So every flag on
  every map stood at a derived centre spot, and every map opened fully
  neutral. `p02_bb_orig22` now starts 14/14/8 instead of 36 neutral.
  Asserted by `--flag-test`.
- 2026-08-20 — **crate upgrades were dead data end to end.**
  `upgrade_key` was unset on both `.tres`, so `grant_upgrade` never
  fired, `has_upgrade` was permanently false, `TopBar._sync_upgrades`
  could never render, and no damage multiplier existed anywhere in
  combat despite the documented "+40% robot / +60% vehicle". Rockets
  were a byte-clone of grenades. Now: grenades grant the robot bonus and
  throwables, rockets grant the hardware bonus, the multipliers are
  tunable `MatchRulesDef` fields resolved in one place
  (`MatchState.damage_multiplier`), and a crate only opens for a unit
  that can USE it (a tank rolling over a grenade box used to consume it
  and arm nobody). Fully asserted by `--pickup-test`.
- 2026-08-20 — **neutral objects were splash-immune.** `team != 0` sat
  on both loops in `Combat.area_damage`, and team 0 is exactly what
  unmanned hardware spawns as — and what 230 of the 235 bridges on the
  shipped maps load as. So empty vehicles and cannons could not be
  destroyed at all, and the fully implemented destructible-bridge path
  (`_bridge_damage` -> rubble solids -> crane repair) was unreachable in
  play. Auto-targeting still ignores team 0 on purpose, so units do not
  wander off to shoot derelicts.
- 2026-08-20 — **the CPU AI forked every multiplayer sim.** Every peer
  spawned its own `CpuAi` for the same seats with an unseeded RNG, and
  the AI wrote `issue_order`/`queue_unit`/`set_rally` directly, bypassing
  `Net` entirely — so peers' rosters and unit net-id sequences diverged
  the moment the first CPU unit rolled out. Now only the host runs a
  brain (`Net.owns_ai()`) and it relays what it decides through the same
  seam a player's orders use. Also: `Net.push_state()` — the shipped
  economy resync — had NO caller at all; it now runs on a 5s host
  cadence.
- 2026-08-20 — **two factory plates and two planet themes were never
  copied out of the zod pack.** `FactoryLabels` showed the FORT's plate
  on the robot factory and a generic one on the vehicle factory, and
  `play_battle()` picked at random from 4 tracks so desert and volcanic
  never had a theme (their oggs exist). `tools/zod/copy_art.py` is a new
  declarative, idempotent copier for exactly this class of gap — the
  zod-sourced art in `project/assets/z/` had NO reproducible tool
  behind it, which is why these were invisible.
- 2026-08-20 — `Decals.track` asked for all 8 headings but the original
  ships only `{E, NE, N, SE}`, so **half of all vehicle headings laid no
  tracks**. Now routed through `AnimLibrary.dir_texture`, which mirrors
  the missing four — a helper that already existed with zero callers.
- 2026-08-20 — `Unit2D.portrait_path` probed only `empty_r270.png`,
  which **3 of 11** hardware types ship; the other 8 showed a blank
  selection portrait. Now uses the shared
  `ProductionPanel.hardware_art` fallback walk (all 11 resolve). A
  team-0 robot also has no `stand_null` art and now falls back.
- 2026-08-20 — `ProjectileDef` was scanned out of `content/projectiles/`
  and **thrown away** by `ContentDB._register`; the two existing defs
  only worked because call sites `preload` them, so a new projectile def
  was silently inert.
- 2026-08-20 — `Fx._enforce_voice_cap` leaked: `stop()` does not emit
  `finished`, so the `queue_free` hook never fired for a capped voice
  and stopped `AudioStreamPlayer` children piled up all match.
- 2026-08-20 — 3 of 15 ambient animal species (`green_snake`,
  `red_worm`, `yellow_worm`) were silently dropped by an over-strict
  probe: they ship walk/dead frames but no `look` idle. Volcanic and
  city had lost one of three species each.
- 2026-08-20 — `MapCatalog`'s docstring promised "scene versions replace
  their JSON twins" while the code did the exact opposite, so none of
  the 58 scene maps ever registered. Precedence is now ONE explicit
  switch (`PREFER_SCENES`, JSON by default because that is the path play
  has exercised) instead of an accident, and the docstring matches.
- 2026-08-20 — six test blocks converted from print-only to real
  assertions (`--pickup-test`, `--flag-test`, `--cursor-test`,
  `--pose-test`, `--parade-test`, `--teams-test`). The last three printed
  the word `FAIL`, which is not the `CHECK FAILED:` string the
  documented pass criterion greps for, so a regression read as a pass.

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
