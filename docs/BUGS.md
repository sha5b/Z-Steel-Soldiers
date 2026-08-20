# Known bugs & tolerated baselines

Live tracker for verified, evidence-backed bugs. Everything here has a
file:line root cause. Fixed items move to the bottom section with the
commit that fixed them — do not delete history.

## Open — verified, not yet fixed

Each of these was confirmed by reading the code or counting the data.
They are listed in the order I would tackle them.

1. **The shipped map set is the zod MULTIPLAYER pack, not the original
   campaign** — reading each JSON's internal `name`, 56 of 57 read
   `clone_map` (orig01-35 = 2P, p03m01-10, p04m01-10) and
   `p08_sc_hunters` reads `Starcraft_Hunters`. The actual 20-level
   Bitmap Brothers campaign lives in `assets_original/gog/` as
   `LEVEL{01-20,26-29,31}.MAP` plus 100 `OBJECT/BUILD/BRIDGE/CPUPLR##.DAT`
   object tables and `levels.dat`/`robots.dat`/`mult.dat`. `Campaign`
   therefore chains the map list in alphabetical filename order with no
   planet progression. Format work in progress (see docs/RESEARCH.md):
   all 25 `.MAP` files are exactly 56,433 bytes; a 136-byte RECORD ARRAY
   starts at offset 1 and its first records are ZONES (u16 x1,y1,x2,y2 in
   pixels, then a u16 centre CELL index, then neighbour ids terminated by
   0xff); that centre index proves the campaign grid is **128 tiles
   wide** (zone 0 of LEVEL01: rect (160,288)-(272,400), centre tile
   (13,21), stored 2701 = 21*128+13). `Maps/LEVEL{1..25}.png` are
   rendered top-down images of each level and serve as the oracle.

2. **The full original HUD frame is still unreferenced** —
   `ui/hud/main_hud*.png` (10 files: the side panel per team, the bottom
   strip and its three segments). The SELECTED-OBJECT trio it belonged
   to is now wired (planet backdrop + portrait + name plate, see Fixed),
   but the panel chrome itself would mean rebuilding the HUD layout
   around a fixed 640x480 frame, and it cannot be verified headlessly.

3. **84 building/fort death-debris pieces unreferenced** —
   `buildings/death_effects/{fort_,}piece{0..4}_n{00..23}.png`. Vehicle
   wrecks already burn (`Vehicle2D._add_wreck_fx`); a falling building
   should throw these pieces. Needs a debris spawner with arcs, not just
   an art reference.

4. **42 of 48 production-GUI chrome files unconverted** — the original
   production menu's own frame (`other/production_gui/fus_*`,
   `object_back`, `selector_back`, the up/down/queue buttons). The panel
   works and uses the plates it has; this is a look-and-feel rebuild.

5. **Multiplayer is not bit-deterministic** — by design now, not by
   omission: host-only brains, relayed intents, a 5s economy resync and
   a 10s FULL-ENTITY resync (`Net.push_entities` ->
   `MatchRelay.apply_entities`, reconciled by net id) plus late join.
   Peers still integrate their own float physics between corrections, so
   positions drift within `MatchRelay.SNAP_DISTANCE` (24px) until the
   next push. A lockstep sim would need fixed-point movement.

6. **GOG cutscenes and tutorial screens** — 94 `.jv[iv]` pairs with no
   parser, and 37 of 72 GOG PNGs (the tutorial pages) unconverted.

7. **`move_target` is fixed, but `Order` still carries a position for
   target orders** — `Order.attack` writes `position` from the target's
   location at issue time and nothing reads it afterwards. Harmless
   duplication, worth removing when the order struct is next touched.

8. **51 of 75 `ROB##` voice lines are unlabelled** — they are converted
   and reachable now (`bark_23..75`, played as idle chatter by
   `Fx.chatter`), but nothing in the pack documents what each line SAYS,
   so none of them can be used as a semantic cue (an acknowledgement, a
   death scream, a "we're under attack"). Labelling them needs a human
   ear, not code.

9. **Crane `arm_off` dead data** — WONTFIX, documented: the rig renders
   correctly via canvas alignment (the `hook_off` table IS applied);
   folding `arm_off` in has no proven defect to fix and no headless way
   to verify the visual.

10. **Rock autotiling ignores diagonals** — `MapLoader._rock_piece` uses
    8 of the 36 sheet pieces and only 4-neighbour masks, so inner
    corners where two arms of a formation meet show a straight edge.
    Closing it needs the original `orock.cpp` table; it cannot be
    derived from the art alone.

## Fixed
- 2026-08-20 — **right-clicking a CRATE crashed the match.**
  `Pick.at` answers with units, crates AND buildings (a crate is a click
  target for the cursor), and `Commands._find_enemy` read `team` off
  whatever came back — a crate has no `team`, and `int(null)` is a hard
  runtime error: "Invalid call. Nonexistent 'int' constructor", killing
  the order dispatch mid-click. Anything with no team is simply not a
  combatant now. `--orders-test` runs the REAL dispatch over every Pick
  target (crate, ground, unit) with a robot, a vehicle and a cannon
  selected; reintroducing the bug turns the flag red immediately (three
  SCRIPT ERROR lines), which is how the guard was verified.
- 2026-08-20 — **CITY AND JUNGLE MAPS WERE SWAPPED.** The terrain byte
  is an index into a planet table and ids 3/4 were the wrong way round
  (`tools/zod/map_to_json.py` TERRAIN), so 21 of 58 maps drew with the
  WRONG TILESET — the "total mess" in the editor — and, worse, took
  their nav grids from the wrong `.tileinfo`: streets read as water,
  open ground as wall. The maps' own objects prove it without any
  reference data: a designer never places a unit in water or in a wall,
  and with the ids swapped back ZERO of 2,105 units on the shipped set
  stand on either (the wrong tag misplaced up to 35 units on one map).
  The art agrees independently — tile-seam continuity scores 12-15 for a
  correctly-tagged map and 39-41 for a mis-tagged one, desert scoring
  11.7 as the control. `tools/zod/verify_map_planets.py` measures it,
  repairs a mis-tagged JSON (re-tag + rebuilt passable/water arrays) and
  breaks the 2 ambiguous ties on the art; `--terrain-test` now audits
  every shipped map so it cannot come back. The map SCENES were
  regenerated, which is what puts the right tileset in the editor.
- 2026-08-20 — **every bridge drew itself twice.**
  `bridge_<planet>.png` is 64x256 = TWO stacked 4x8-tile frames, the
  intact bridge over its own WRECK (verified per planet: the lower half
  carries 1.5-2.6x the water-coloured pixels through its middle, i.e.
  the deck is gone). `Building2D._build_sprite` handed the whole sheet
  to the sprite, so an 8-tile bridge rendered as a 16-tile double with
  the ruin hanging off the end, and the destroyed state — having no art
  to swap to — faked it by dimming the sprite. Bridges now render one
  frame and swap frames on blow-up/repair. Their walkable span was also
  half the crossing: the maps show a DRY 4-tile corridor where a bridge
  stands, so the span is 4x8 / 8x4, not 2x8 / 8x2. That is asserted
  both ways — 0 of 7,520 span cells sit in water with the correct spans,
  1,747 with the orientations swapped and 491 if the span is 5 wide.
- 2026-08-20 — **scene maps opened fully neutral.** The zone FLAG
  markers (`map_item` 0) carry each zone's authored flag tile and its
  STARTING OWNER; the JSON loader applies them, and
  `tools/build_map_resources.gd` dropped them — so the same map played
  as a scene started with no pre-owned territory and its flags at
  derived centre spots. `--scenes-test` now compares all 58 scenes
  against their JSON on zones, flag tiles, pre-owned zones, buildings
  and robots. The scene builder also still stamped the OLD hard-coded
  rock piece (the flat pale slab bug) — it goes through
  `MapLoader._rock_piece` now, like the JSON path.
- 2026-08-20 — **the order-acknowledgement `point` gesture never had
  any frames.** `point` is stored as SINGLE-FRAME directional art
  (`point_<team>_r000.png`, exactly like `stand`), and
  `AnimLibrary._add_directional_or_numbered` only probed
  `_r000_n00`/`_n00` — so `play_gesture("point")` silently did nothing
  on every order ever issued. The gesture-vs-art audit in `--art-test`
  is what found it and now guards every gesture name.
- 2026-08-20 — **terrain animation shipped** (it was closed as
  "impossible"). The `.tileinfo` records carry `is_effect` and
  `next_tile_in_effect`; both converters threw them away. They form
  rings of 2-6 frames (desert 50 animated tiles, city 40, arctic 25,
  volcanic 18, jungle 0) whose frames are already distinct images in the
  planet sheet, so `TerrainAnimator` walks the ring per painted cell,
  keeping each cell's own PHASE (a shipped map paints 18-30 frames of
  the same rings side by side — that offset is what makes water flow
  instead of blink). The busiest map animates 1,877 cells at 5 Hz.
  Guarded by `--terrain-test`, including the 10 lead-in frames that run
  INTO a ring instead of sitting on one.
- 2026-08-20 — **`SetMapImpassables` covered 2 of 7 building types.**
  The repair shop and both factories had no table at all, so their whole
  art rect was solid — including the factories' rightmost 16px column,
  which is the CAST SHADOW (`base_shadow.png` is that same 16x80 strip),
  and the dark mouth at the foot of each factory, which is the exit with
  the map's own dirt painted into it. Tables are now authored for all
  three from the art (documented as DERIVED, not transcribed — the
  original source for these three is not in the pack), and
  `--building-test` asserts every type declares a table, that it fits
  inside the art and that its open cells fall inside it.
- 2026-08-20 — **`Vector2.ZERO` was the "no order" sentinel.** A real
  destination at the world origin was indistinguishable from "no order",
  and every "is it moving?" test in the codebase was that comparison.
  `move_target` now uses `Vector2.INF` like `defend_post` and
  `rally_point`, read through `has_move_target()` and cleared through
  `clear_move_target()` (57 call sites).
- 2026-08-20 — **no building registry.** `Unit2D._find_target_within`
  scanned the `all_buildings` group per unit per combat tick and
  `Combat.area_damage` per explosion. `BuildingRegistry` mirrors
  `UnitRegistry` (static queries, group fallback for the map-build tool)
  and owns building net ids; the per-frame minimap radar probe, the
  elimination cascade, the win check, click picking and the net-id
  lookup all go through it now.
- 2026-08-20 — **multiplayer full-entity resync + late join.** The host
  pushes the whole roster every 10s (`Net.push_entities`); peers
  reconcile BY NET ID (`MatchRelay.apply_entities`): a drifted unit past
  24px is snapped, a unit the host no longer has dies, a unit the peer
  never made is spawned and ADOPTS the host's id (so later intents
  address the same unit). A peer that connects mid-match is seated on
  the first open team and handed the map plus a save-contract snapshot,
  which the map replays after spawning — the "reuse the save contract"
  plan, now real. Asserted over the ENet loopback in `--mpmatch-test`.
- 2026-08-20 — **VETERANCY** (there was no rank or XP field anywhere).
  Kills are credited to whoever fired the killing shot (by instance id,
  so a shell outliving its gun credits nobody), rank comes from the
  kill steps in `MatchRulesDef`, and rank pays in damage and accuracy.
  Ranks show as pips under the selection box and survive a save.
  Remake values, deliberately small and tunable in the rules resource —
  the asset pack ships no table for this. Guarded by `--veteran-test`.
- 2026-08-20 — **control-group hotkeys** (there were no digit bindings
  at all). Ctrl+digit assigns the selection, digit recalls it, a second
  press inside 0.45s jumps the camera to the squad; dead members drop
  out on recall. Ten slots (1-9 then 0). Guarded by `--group-test`.
- 2026-08-20 — **the whole test suite asserts.** 43 flags shipped with
  ~29 that only PRINTED their findings, so a regression in those domains
  read as a passing run. All 47 flags now report through `TestRig`
  (`CHECK FAILED:` lines): the collected-problem blocks were routed
  through the rig, and the measurement-only ones (capture, combat,
  factory, dir, near, prod, fortprod, cancel, vehpath, apc, save,
  campaign, mount, cap, fx, tactics, ai) gained real invariants — a
  captured zone must flip and pay, a duel must draw blood, a destroyed
  factory must not produce, the cap must REFUSE at the cap, a vehicle
  route must never end in water, the AI must still be playing after two
  live minutes.
- 2026-08-20 — **art that shipped in the pack and nothing referenced.**
  Now wired, each behind an assertion in `--art-test`:
  the SELECTED-OBJECT panel (planet `backdrop_*` + portrait + the
  team-coloured `unit_label_*` plate, falling back to the neutral
  `label_*` weapon plate so all 19 types have one); `escape_tank` (the
  crew visibly bailing out of a hull) and `tank_fire` (the crew in the
  open hatch while the gun fires — the same hatch a sniper shoots
  through); the four directional `jump-*` leaps, picked by which way a
  dodge lands; per-planet ROCK debris (256 frames, all five planets used
  to share one grey puff) and BRIDGE rubble; the building LEVEL digits
  (levels 0-5 gate the roster and the build speed and the number was
  shown nowhere); the announcer's printed plaques, driven by one signal
  off `Fx.announce`; the seven neutral ORDER-CONFIRMATION cursors, one
  per order kind (only `placed` had been converted, so an attack, a
  board and crane work all confirmed with the move marker); ambient
  BIRDS with their per-planet calls; and the 53 unlabelled `ROB##` voice
  lines as idle chatter. `tools/zod/copy_art.py` grew a declarative
  SERIES table for the 478 files this needed.
- 2026-08-20 — **`tools/gog/convert_assets.py` deleted a file it had
  just created.** It converted `audio/GRENADE.RAW` to
  `sounds/GRENADE.wav` and then unlinked it with the comment "replaced
  by GRENADE.RAW"; `fx.gd` substituted the grenade-launcher shot and its
  comment blamed an upstream gap that did not exist. Both fixed.

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
