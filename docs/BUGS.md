# Known bugs & tolerated baselines

Live tracker for verified, evidence-backed bugs. Everything here has a
file:line root cause. Fixed items move to the bottom section with the
commit that fixed them — do not delete history.

## Open — verified, not yet fixed

Each of these was confirmed by reading the code or counting the data.
They are listed in the order I would tackle them.

0. **The pyro robot razes a fort in 14 seconds** — faithful to the
   reference table and still absurd beside a heavy tank's 18s at three
   times the cost. The small-arms `building_frac` values are transcribed
   from the source table and ignore FIRE RATE, so the 0.1s-cooldown pyro
   comes out 35x a 4.86s howitzer per second. The explosive fracs added
   2026-08-23 are derived from `cooldown / seconds-to-raze`, which does
   account for it; bringing small arms onto the same rule means departing
   from a transcribed number, so it is left as a decision rather than
   silently changed. UPDATE 2026-09-01: the "cannot miss" half of this
   item is FIXED — blast projectiles now scatter their impact around the
   led aim (see the fixed log); the `building_frac` rate question above
   remains the open decision.

1. **The retail campaign's STARTING ARMIES are not in the release.**
   Every `levels.dat` record names `preset1.wal` / `preset2.wal` and
   NEITHER FILE SHIPS (Z.exe holds only the strings). Searched for a
   coordinate within +-80px of either LEVEL01 fort across
   `LEVEL01.MAP`, all four `*01.DAT`, `levels/robots/mult.dat`, `Z.exe`,
   `CHARS.BIN` and `PHRASES.BIN`: **0 hits**. So a converted level
   arrives with forts, factories, bridges, rocks, scenery and derelict
   hardware, but no crew. Stopgap: each fort team that starts a map with
   no units at all gets `MatchRulesDef.starting_squad` grunts (3) at its
   fort — without it the original no-units rule ends the mission on the
   first robot lost. Also still open from that conversion: building
   LEVEL is inferred from max-HP (97.1% agreement with the zod twins,
   no byte predicts it), and 144 volcanic OBJECT records of types 13-16
   have no zod counterpart and are emitted as invisible `map_item 0`
   rather than guessing a sprite. `robots.dat` (a 44-byte named-robot
   roster) and `mult.dat` are unparsed.

4. **Multiplayer is not bit-deterministic** — by design now, not by
   omission: host-only brains, relayed intents, a 5s economy resync and
   a 10s FULL-ENTITY resync (`Net.push_entities` ->
   `MatchRelay.apply_entities`, reconciled by net id) plus late join.
   Peers still integrate their own float physics between corrections, so
   positions drift within `MatchRelay.SNAP_DISTANCE` (24px) until the
   next push. A lockstep sim would need fixed-point movement.

5. **GOG cutscenes** — 94 `.jv[iv]` pairs with no parser. (The
   TUTORIAL pages are done, see Fixed; what is left unconverted of the
   72 GOG PNGs is the iOS/Mac duplicates of the same pages, the credits
   sheets and the social-network icons.)

6. **`move_target` is fixed, but `Order` still carries a position for
   target orders** — `Order.attack` writes `position` from the target's
   location at issue time and nothing reads it afterwards. Harmless
   duplication, worth removing when the order struct is next touched.

7. **51 of 75 `ROB##` voice lines are unlabelled** — they are converted
   and reachable now (`bark_23..75`, played as idle chatter by
   `Fx.chatter`), but nothing in the pack documents what each line SAYS,
   so none of them can be used as a semantic cue (an acknowledgement, a
   death scream, a "we're under attack"). Labelling them needs a human
   ear, not code.

8. **Crane `arm_off` dead data** — WONTFIX, documented: the rig renders
   correctly via canvas alignment (the `hook_off` table IS applied);
   folding `arm_off` in has no proven defect to fix and no headless way
   to verify the visual.

9. **Rock autotiling ignores diagonals** — `MapLoader._rock_piece` uses
    8 of the 36 sheet pieces and only 4-neighbour masks, so inner
    corners where two arms of a formation meet show a straight edge.
    **NO LONGER UNDERIVABLE** (2026-08-20): `orock.cpp` is public and
    readable. It is not a table — it is a cascade of ~15 conditions per
    layer over `r/l/up/dn` PLUS diagonals (`dl/dr/ur`) PLUS
    DISTANCE-2 neighbours (`ddn`, `uup`, `uur`, `ddr`), selecting from
    named surfaces (`rock_center_top`, `rock_up_left_top`,
    `rock_vert_down_top`, ...). Each rock renders TWO layers
    (`render_img[0][j]` / `render_img[1][j]`, j = 0..2 vertical cells),
    which is also where the unused shadow and rubble columns go. Porting
    it is transcription now, not reverse engineering.

10. **Map-item TURRETS are missing entirely** — we load `map_item`
    scenery as an inert `Sprite2D` (`MapLoader._spawn_map_item`): no
    health, no weapon, indestructible. In the original `OMapObject` is a
    destructible object (`map_item_health = 40/240`) that FIRES:
    `ServerFireTurrentMissile` lobs a missile of
    `map_item_turrent_damage` (50/240) with a hardcoded `radius = 40` at
    a UNIFORM RANDOM point in a `max_turrent_horizontal_distance` x
    `max_turrent_vertical_distance` box (300 x 300, so +-300 = a 600px
    square) around its own centre — suppressive scatter, not aimed fire.
    This is the most likely root cause of the player's "turrets don't
    reach all around the building" (HANDOFF open item 1): the original's
    emplacements cover a huge area around themselves and ours do
    nothing at all. NOT YET IMPLEMENTED — it is a new gameplay feature
    (destructible, firing scenery), so it needs a scope decision.

## Fixed
- 2026-09-01 — **review-sweep batch** (the "last sweep for logical
  mistakes"): (1) the in-world HEALTH BAR was dead code — the
  attack-radius port stranded the `hp < max_hp` draw block after a
  `return` inside `_dot_covered`, so no damaged unit showed a bar at
  all; restored in `_draw`, for hurt units selected or not. (2) the
  radius-dot CULL used raw `range_px` while the circle draws at
  `range_px * sprite_scale + 3` — merged squad envelopes culled along
  the wrong boundary. (3) the robot frames cache FROZE the random death
  variant per type+team (the first grunt's roll served the whole army);
  the variant is part of the cache key now, so every spawn rolls its
  own. (4) save restore left `slot_cannons` full of freed refs and
  restored tower guns unlinked at stock range — a new cannon could
  mount STACKED on an occupied tower; `relink_tower_guns()` runs after
  `_apply_load`. (5) box-select's physics query capped at 256 hits
  WITH enemies counting against the budget — own units in a big battle
  silently missed the drag box; 1024 now. (6) the pick-box migration
  narrowed enter/board clicks to the 16px hull half-extent (was a 24px
  radius) — boarding keeps the old generosity on top of the box test.
  (7) `MatchState._owned_dirty` was set per FRAME above the income
  loop, quietly turning the once-per-capture zone census back into a
  per-frame rebuild; it invalidates once per income tick now. (8) the
  combat hot paths rebuilt and scanned `OS.get_cmdline_args()` per hit
  for the --brain-test flag — read once into a static. (9)
  `Combat.area_damage` re-derived a rock column's base cell from magic
  offsets beside the loader's own `base_cell` meta — one owner now.
- 2026-09-01 — **fort tower guns floated beside the fort, four of them,
  and could not cover their own gate.** Three defects in one report:
  (1) the mount table's outer pair sat at the art EDGES (x 10/150) —
  the real tower platforms centre at (25,16)/(135,16) and
  (26,63)/(134,63), measured off the art at 3x, identical on both fort
  variants; (2) map forts armed ALL FOUR towers at load, which turned
  the opening game into a siege — `STARTING_TOWER_GUNS = 1` now, the
  rest are the build-up; (3) a stock gatling reaches 120px and the fort
  art is 160 ACROSS, so a tower gun could not touch an enemy at its own
  gate — mounted guns get `TOWER_RANGE_SCALE = 1.8` (elevation pays in
  reach), applied in `mount_product` for built guns too.
- 2026-09-01 — **units watched their squadmates get shot** ("when one
  gets hit the others don't go attack it"). Nothing propagated a hit:
  a sniper outranging a grunt's return reach was ignored by everyone
  he was not currently hitting. `Unit2D.notify_attacked` (called from
  `Combat._land` on direct-fire hits) makes the victim retaliate and
  raises every idle friend inside 120px; a unit under real orders, on
  a DEFEND post, or already fighting is never diverted, and it is
  team-agnostic so the AI's squads answer fire too. A freshly-shot
  standing robot also holds its weapon-up stance for 3s
  (`_alert_timer` -> the fire pose in `_play_idle`).
- 2026-09-01 — **the verdict screen slammed down on the same frame as
  the deciding blow.** `GAME_OVER_LINGER = 3.0` — the losing HQ's
  collapse (debris, fire) plays in full view before the game-over
  overlay arrives.
- 2026-09-01 — **a fresh AI brain sat through one whole think interval
  (4-6s) before its opening move** — `_accum` now starts full, so the
  first think fires on the first frame ("the AI needs a long time till
  it does something"; the retaliation fix above covers the other half,
  AI units answering fire between think passes).
- 2026-09-01 — **the dotted route redrew itself whenever an attacked
  target moved** ("the path newly generates all the time — looks
  buggy"). `_chase_repath` funnels into `Unit2D._begin_move`, which
  unconditionally re-showed the PathIndicator for player units, so a
  chase re-plan every 28px of target drift spawned a fresh full route
  with marker each time. `_begin_move(announce)` now draws the route
  only for the player's own fresh order; chase upkeep, the stuck-unjam
  and self-issued orders (smart idle, return-to-post — which also
  played the acknowledgement bark nobody asked for) are silent.
- 2026-09-01 — **units ground themselves into parked units** ("units
  get stuck in the other units — other units also need to be considered
  when finding the path"). The nav grids know terrain and buildings
  only, so a walker wedged against a standing crowd re-planned the
  exact route it was stuck on — through the bodies — and burned its
  repath budget in place. `NavWorld.request_path_avoiding` stamps the
  cells of nearby STATIONARY units solid for the duration of one query
  (start-adjacent cells never stamped; plain-route fallback when the
  crowd seals the way), and `_unjam` routes with it. Moving units are
  not stamped — they clear the cell before the walker gets there.
- 2026-09-01 — **the jeep "spasm": firing units flicked between the
  shoot facing and the travel facing every shot.** Two causes, two
  fixes: a shot snaps `_last_dir` at the target but the next steering
  tick snapped it back to the velocity angle — `_face_lock` (0.35s,
  armed by every fire path) pins the facing across that boundary; and
  the chase stop-at-range had no hysteresis, so a target hovering ON
  the range line yo-yoed the chassis between hold and pursuit —
  `CHASE_RESUME = 1.15` keeps the stance until the target is genuinely
  clear. Idle turrets also all stepped their scan sectors in unison
  (every `_scan_timer` started at 0); they start at a random phase now.
- 2026-09-01 — **hitscan fire was a drawn yellow LINE, pinned to a
  firing position the unit had already left.** The original draws no
  tracer at all: the directional muzzle-flash art on the shooter is the
  gun, and the shot reads from where it LANDS. `Fx.bullet` now plays
  the `impact` spark on a hit and the pack's `ground_spark` ricochet
  puff (converted art, previously referenced by nothing) on a miss,
  each with a ±3px landing jitter; hitscan hits on UNITS therefore
  show an impact for the first time (only buildings ever sparked). The
  laser keeps its beam — that is the original's weapon sprite — and
  gains the same landing spark.
- 2026-09-01 — **lockstep volleys: every unit of a type fired on an
  identical clock** (the "we don't randomize" sweep). Reload gets ±10%
  jitter at every fire site (robots, vehicles/cannons, the APC port
  gunner), which desynchronises a battle line within a few shots
  without changing the average rate of fire.
- 2026-09-01 — **production-panel name tag: the sidebar's 96x14 team
  plate was squashed into the 45x13 name slot** at 47% scale, leaving
  bands of the window's own red painted slot showing above and below
  it ("name tags overlay the red background, not aligned"). The slot
  now shows the art cut FOR it — `object_name_button.png`, exactly
  45x13, previously referenced by nothing — with the unit name printed
  as text. More of the same sweep: the LOOP/WAIT badge printed
  straight over the factory title plate's own lettering (moved onto
  the object window with a drop shadow); the title plate was centred
  onto half-pixel offsets (left-aligned native now); the health gauge
  showed the top-left CORNER crop of the 62x16 bar art (now squashed
  to the slot inside a width-clipping wrapper); the whole panel was
  positioned at fractional camera coordinates every frame, shimmering
  its 8px glyphs (roundf); the status plate hung 1px past the window;
  the time slot was 1px too narrow for "10:00". Sidebar: the green
  health span and the bottom-bar army gauges could never render
  NARROWER than their own art (TextureRect minimum size — both were
  stuck at full width; EXPAND_IGNORE_SIZE), the health bar drew 3px
  above the frame's window cut, and the clock box was 2px too narrow
  for "0:00:00".
- 2026-09-01 — **GENERATED SKIRMISH MAPS** (new feature, not a bug):
  the skirmish list leads with a RANDOM MAP entry — players (2-8),
  starting money, size (96/128/176) and theme (5 planets or random),
  previewing the ACTUAL map the current seed builds; START plays
  exactly what is previewed. `MapGen` emits the shipped JSON schema
  (plain-ground sheet, ORock-assembled rock ridges kept out of
  guaranteed fort-to-fort corridors, a fort + two factories per team
  on an ellipse, zones tiling the map, a neutral flag per fortless
  zone, `passable`/`water` derived from tileinfo) to
  `user://generated_map.json`, so the loader, minimap, AI and saves
  treat it like any shipped map. `MatchConfig.starting_money`
  overrides every seated team's purse after load.
- 2026-08-20 — **an EXPORTED BUILD loaded none of its content, and nothing
  could see it.** Godot packs an imported file as a `.import` sidecar and
  renames the real texture under `.godot/imported/`; text resources are
  converted to binary. Every scan filtered on the source extension, so a
  packaged game had no building defs, no unit folders, no effect art and no
  map scenes — with all 47 lanes green in the editor. Two fixes, and the
  second is the one that matters long-term: `PackFiles` normalises packed
  listings, and `title.gd` hands over to `main.tscn` on a test flag so the
  suite RUNS INSIDE THE SHIPPED BINARY. 47/47 now pass both ways; the export
  lane is what found the defect.
- 2026-08-20 — **THE ORIGINAL 20-LEVEL CAMPAIGN IS IN.**
  `tools/gog/level_to_json.py` reads the retail data in
  `assets_original/gog/` and writes our map schema, so `map_loader.gd`
  loads it unchanged: `zc01_virgin_soldiers` … `zc20_z` (the levels'
  OWN names, out of `levels.dat`) plus 5 skirmish maps (`zs26`-`zs31`).
  `Campaign` chains those 20 in the game's order instead of 57 zod
  clone maps in alphabetical filename order, and menus show the level
  name. Format (docs/RESEARCH.md §6, VERIFIED/UNKNOWN marked per
  field): `LEVEL##.MAP` is 56,433 bytes with `u16` width/height at
  10125, two 128x128 byte PLANES at 10129 and 26513 where
  `tile = plane1 + 240 * (plane2 >> 7)`, a 20x138-byte ROCK array at
  6657 whose records carry a 32x32 BIT MASK, forts cut out of the tile
  grid as plane-1 value 238, and a 96x136-byte region adjacency array;
  `CPUPLR##.DAT` is the territory grid, `OBJECT/BUILD/BRIDGE##.DAT` the
  objects.
  The correction that made it rigorous: the shipped `p02_bb_orig01..20`
  maps — which this tracker called "the zod multiplayer pack" — ARE
  these 20 levels, edited for 2 players, so they are a per-cell oracle:
  **96.17% of 218,000 tiles agree exactly** (66% for plane 1 alone), and
  every id table was read off that instead of guessed. Independently:
  mean Pearson r 0.73 against the retail `Maps/LEVEL*.png` thumbnails
  (0.81 ignoring fort footprints), forts 38/40 exact including id, rocks
  98.8% precision / 99.6% recall of 5,990, buildings + bridges 257 exact
  with 0 wrong ids, all objects 96.0% exact, `passable`/`water` 98.3% /
  99.98%. Verified on this side too: `verify_map_planets.py` finds 0
  mis-tagged planets across all 83 maps, all 25 levels boot in the real
  engine with no errors, and `--retail-test` asserts every level's size,
  tile range, territory grid, two opposing fort teams and unit placement.

- 2026-08-20 — **the release's TUTORIAL pages were unreachable.** Seven
  512px "how to play" pages ship in the GOG set and nothing converted or
  showed them, so the remake had no instructions at all. Converted
  (`tools/gog/convert_assets.py`), shown by `scenes/tutorial.tscn`
  (arrow keys / prev-next, clamped at both ends — the pages are an
  ordered explanation, not a carousel) and reachable from the title menu.
  Asserted by `--ui-test`.
- 2026-08-20 — **a falling building threw no debris.** The pack ships
  84 frames for it (5 tumbling fort pieces, 2 generic ones, 12 frames
  each) and nothing referenced them: vehicles burned, buildings just
  puffed out. `Fx.building_debris` throws them on ballistic arcs from
  `Building2D._death_visuals` — the fort's own five for a fort, the
  generic pair for everything else.
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
- 2026-08-20 — **bridge spans are PER BRIDGE, not one number.** The
  retail campaign stores each bridge's own footprint, and it is always
  4 tiles ACROSS with a length of 3 to 12 — so the fixed 4x8 span
  cleared water a short bridge does not cover and left cells solid in
  the middle of a long one. It also fixes the ORIENTATION rule: the
  dimension that measures 4 tells which way a bridge runs, and `w > h`
  does not (a 4x3 bridge is VERTICAL). Verified against the 44 bridges
  that have a zod twin: 44/44 orientations agree with the swapped rule
  (43/44 before), and the map audit's wet-span count fell from 13 to 0
  once the real spans were used. `Building2D.bridge_span_override`
  carries it; the zod maps have no size field and keep the def span.
  KNOWN LIMIT: the art is ONE 4x8 frame, so 6 of the 65 retail bridges
  are longer than it and 8 are shorter — the art is capped at the
  frame and anchored at the near end while the FOOTPRINT stays the true
  span. Slicing the frame to length would need to know where its ramps
  stop, which is not established.
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
- 2026-09-01 — **attack-move "just stops after a time"** — two root
  causes. (1) `Unit2D._shoot` rolled the per-hit snipe chances (grunt
  0.3, laser 0.6, sniper 0.8 — the original zsettings numbers) straight
  into `target.eject_driver()`: the FIRST enemy volley in any firefight
  had ~30% per grunt per shot to kill the crew, and `eject_driver`
  drops every order and neutralizes the hull. Crewed hardware on amove
  halted to trade fire and immediately sat down empty. The original
  applies the roll to a driver HEALTH POOL (`DamageDriverHealth`, pool
  = a grunt's health, hit = the shooter's damage, hull untouched);
  `Vehicle2D.damage_driver` now does exactly that and only an emptied
  pool ejects. Pool persists through saves (`dhp` in the vehicle dict).
  (2) The amove HALT itself was dead code: `_combat` (in `_process`)
  zeroed `velocity`, but `_steer` (the next physics tick) overwrote it
  from the waypoint, so attack-move fired on the move and never held.
  `_amove_probe` now carries the halt across the tick boundary via
  `_amove_hold`, which `_steer` respects. Guarded by `--amove-test`
  (driver pool soak, halt+resume for robots and hardware, on real
  engine frames).
- 2026-09-01 — **cliffs rendered as blobby pillars** ("the cliffs look
  still wrong"). Our rock assembly inferred a piece per CELL from
  left/right neighbours and a depth-below rule — a rule that exists in
  no original engine. The original (zod `ORock`, ported line for line
  now) stores one object per 16px rock COLUMN rendering up to three
  tiles: a TOP piece from a 16-shape vocabulary picked by the exact
  four-neighbour if-chain, up to two UNDER (cliff-face) pieces wherever
  no rock continues below, and a cast SHADOW column drawn one tile EAST
  as a ground prerender. Only the BASE tile is impassable — cliffs
  overhang, units walk behind the face and the Y-sort covers them (the
  old build made every rock cell solid). Blasting a column now measures
  and clears its base and perm-stamps one of the six `rock_destroyed`
  rubble pieces on the base tile (`Decals.rock_rubble`), which the old
  path never left behind. Verified by rendering the ported table in
  isolation against the original sheet; asserted by the `--combat2-test`
  rubble check and the `--cliffshot-test` camera diagnostic.
- 2026-09-01 — **"attack order just rolls instead of attacking in
  range"** — the click tolerance. `Pick.at` tested a flat 8px radius
  around a unit's origin; the original (zod `ZObject::UnderCursor` /
  `WithinSelection`) tests the object's whole RENDERED BOX
  (`width_pix x height_pix`). Clicking a tank's hull edge or a walking
  robot's fringe missed the unit, the attack order fell through to a
  plain move, and the squad "just rolled" to the spot. Pick now uses a
  per-kind art-box hit test (`Pick.PICK_BOX`: robots 24x28, hardware
  32x32 half-extents), shared by the cursor, click selection, the
  vehicle/APC finders and order dispatch. The attack chase itself was
  verified sound against the original contract (stop at
  `range_px * sprite_scale`, fire immediately, follow a moving target —
  asserted by `--attack-click-test`, static and moving targets).
- 2026-09-01 — **the per-unit range display** — ported (zod
  `ZObject::RenderAttackRadius`): every SELECTED unit draws a dotted
  circle at its weapon range (`range_px * sprite_scale + 3`, the same
  expression the fire gate uses) in the owner's team colour — ten 2px
  dots per quadrant, mirrored into all four, crawling one slot per
  second (zod `radius_i`). A dot is suppressed where another selected
  unit's radius already covers it (`WithinAttackRadiusOf`), so a packed
  squad shows one merged envelope. Unarmed hardware draws nothing.
  Visible in the `--cliffshot-test` screenshot.
- 2026-09-01 — **"vehicles take no damage, the fight never ends"** —
  two hidden HEALS made hardware in a driver-snipe cycle undamageable.
  `eject_driver` popped the hull back to half HP when the crew died, and
  `enter` full-repaired it when anyone re-crewed — so a jeep whose
  driver got shot out healed to 50%, sat neutral until the AI re-crewed
  it, came back at 100%, and the fight restarted from scratch, forever.
  The original never heals either way (only repair shops / crane work
  do — zod `DamageDriverHealth` just clears the driver and flips the
  owner). Both heals removed; hull damage now persists and the damaged
  art stays honest. Also moved the driver-snipe roll from `Unit2D._shoot`
  into `Combat.fire` — zod rolls it in the generic damage path for every
  armed attacker, so JEEPS and GATLINGS now snipe crews too (they fired
  through their own `Combat.fire` block and never could). Snipes remain
  hit-gated (roll only on shots that pass hit chance, zod order) and
  wound the driver pool instead of the hull. Asserted by the extended
  `--jeepduel-test` (ordered duel + opportunistic fire + snipe pool).
- 2026-09-01 — **skirmish maps shipped NO terrain nav at all** — "vehicles
  can cross rivers" + "on some maps the AI does nothing". The zod
  multiplayer set (`bb_orig*`, `p03*`, `p04*`, `p08` — the whole skirmish
  pool) carries neither `passable` nor `water` arrays; the loader read a
  missing mask as "everything walkable", so ~5000 water cells (p08:
  5087) and thousands of cliff cells were open ground for every unit —
  tanks forded rivers, and the AI's zone/route reasoning ran on a flat
  world. Fix: when a map does not ship a mask (or ships a short one),
  the loader derives passability and water from the per-planet
  `tileinfo_<planet>.json` tables — validated 0 mismatches against the
  stored masks on all 27 maps that ship them. The AI-brain lane
  (`--brain-test --map=<any map>`) audits any map for adaptive
  behaviour: production, zone expansion, attack posture, plus the nav
  contract (water must block wheels somewhere).
- 2026-09-01 — **the player was eliminated 16 seconds into some
  skirmish maps** — two compounding causes. (1) Map forts spawned
  DEFENCELESS: the tower-gun design says "a fort defends itself with
  its tower guns", but nothing mounted them until someone built
  cannons, so the AI's opening squad razed an undefended fort (with the
  known explosive-vs-`building_frac` balance, see open item 0) and the
  elimination cascade ended the match. Map forts now spawn with their
  four tower gatlings manned. (2) The AI's single-unit assignment
  offered EVERY flag it did not own, so on first think the whole
  starting squad marched into the nearest enemy's home sector — that is
  squad work (the brain's own doctrine: held ground is squad ground);
  held enemy flags are now only grabbed by squads, or by single units
  once the posture goes all out. `--brain-test` on the 4-player map
  went from "match over at t=16s" to a 145s war with real armies.
- 2026-09-01 — **route legs grazed solid corners on cliff-heavy maps**.
  AStarGrid2D's ONLY_IF_NO_OBSTACLES allows a diagonal whose other
  shared neighbour is solid, and uniform-marching `segment_clear` could
  straddle the thin corner chord — the `--path-test` audit caught a
  walker's centre 1px inside a cliff. `request_path` now repairs
  diagonal legs by inserting the open shared cell, and `segment_clear`
  is an exact Amanatides-Woo cell walk with shrunk-rect intersection
  tests. Residual separation-drift grazing is tolerated at
  `KNOWN_CROSSING_BASELINE = 2`.
- 2026-09-01 — **tank and artillery shells landed perfectly every
  time** ("two tanks meet, they kill each other on a schedule").
  Explosives shipped `hit_chance = 1.00` and skipped the miss roll, so
  every shell hit the exact same led point and armour duels were
  deterministic. Every weapon with a travelling shell now adds GUNNER
  SCATTER: the impact spreads over a uniform disc sized by the weapon's
  own blast (`splash_radius * 0.6`, floor 20px) around the led aim, the
  crater lands where the shell lands, and damage resolves through the
  existing splash falloff — near-misses hurt, direct hits punish. This
  deliberately departs from zod (whose missiles reach their aim point
  exactly and relied on dodging for variance) because our units do not
  dodge area fire; the scatter is the replacement miss mechanic, and it
  covers every projectile attacker — tanks, artillery, missile
  launchers, emplaced cannons. Hitscan weapons keep their per-shot hit
  chance and never scatter. Asserted by the `--natives-test` scatter
  block (repeated fire at a fixed target must produce varying damage).
