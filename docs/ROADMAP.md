# Roadmap — Z (1996) remake in Godot

Single-player feature-complete; multiplayer milestone 1 (P2P lobby)
shipped 2026-08 — see the bottom section.

## Phase 0 — pivot to Z (1996) ✅

- [x] Zod Engine asset pack imported (gitignored, per-contributor copy)
- [x] 2D project: RTS camera, drag-select, orders, original sprites

## Phase 1 — content & core loop ✅

- [x] Zod `.map` format reversed; all 57 original maps converted (all 5
      planets) with tileinfo passability; 256×256 maps supported
- [x] TileMapLayer terrain, rock scenery (zod sheet layout), bridges,
      per-planet building sprites with ownership flags
- [x] Territory: zone flags, capture by presence, income ticking
- [x] All 6 robots + 5 vehicles + 4 cannons; manning; APC transport
- [x] Forts as win/lose objectives; CPU opponent with difficulty
- [x] A* pathfinding with robot/vehicle rule split (water, rocks)

## Phase 2 — systems & polish ✅

- [x] Production: robot/vehicle factories + fort production, queue UI
      with progress, cancel with refund
- [x] Pickups: grenades (+40% robot dmg) / rockets (+60% vehicle dmg)
- [x] HUD: minimap (click/drag/right-click orders), selection portraits,
      top bar (money/zones/clock), red-dotted order paths
- [x] Idle humor animations; voice lines; looping music
- [x] Facing/zod DirectionFromLoc; Y-sorted layering; jeep wheel layer

## Phase 3 — game flow ✅

- [x] Title screen (splash art), map select (57 maps), ESC pause menu
- [x] Save/load (pause Save, title Continue)
- [x] Campaign: 57-mission chain, briefings, persistent progress
- [x] AI difficulty (Easy/Normal/Hard)

## Phase 4 — the 2026-08-20 correctness pass ✅

- [x] CITY/JUNGLE planet ids were swapped: 21 of 58 maps drew with the
      wrong tileset and navigated off the wrong tileinfo (see
      `docs/BUGS.md`; `tools/zod/verify_map_planets.py` audits it)
- [x] Bridges rendered their own wreck stacked on the end (two-frame
      sheet) and their walkable span was half the crossing
- [x] Terrain ANIMATION (the retraction below is now shipped):
      TerrainAnimator walks the tileinfo effect rings per cell
- [x] Building impassables for the repair shop and both factories
- [x] Control-group hotkeys, veterancy, MP full-entity resync + late join
- [x] Every test flag asserts through TestRig (46 flags)
- [x] Unreferenced pack art wired: selected-object panel, escape_tank /
      tank_fire / jump-*, per-planet rock + bridge debris, building level
      digits, announcer plaques, order-confirmation cursors, ambient
      birds, the unlabelled ROB voice bank as idle chatter

## Not done (known gaps for a future task)

- Multiplayer IN-MATCH sync — INTENT REPLICATION SHIPPED (2026-08-20):
  clients relay order/queue/rally intents to the host, the host
  validates the acting team against the sender's seat and rebroadcasts;
  every peer applies through the single intakes (MatchRelay, entities
  addressed by per-match net id). Human seats get no CpuAi stand-in.
  Peer sims are NOT bit-synchronized (float physics): each peer applies
  the same intents to its own sim; state resync / late-join reuses the
  save contract (future). Verified by --mpmatch-test over a real ENet
  loopback
- Verified open bugs live in `docs/BUGS.md` (root-caused, with
  file:line evidence) — keep that file current instead of the roadmap
- Remaining polish: the original production-menu chrome (42 of 48 files)
  and the full main_hud frame — both look-and-feel rebuilds that cannot
  be verified headlessly. (Control-group hotkeys, ambient birds and the
  HUD selected-object trio all shipped in the correctness pass above.)
  Shipped in that sweep instead: pop-cap meter (top bar), missile
  target-leading (original EstimateMissileTarget feel), robot order
  acknowledgement barks.
- CLOSED (was "impossible", then "rebuildable", now SHIPPED):
  water/terrain animation. The zod `planets/<planet>.tileinfo` records carry
  `is_effect` + `next_tile_in_effect`, which form closed 4-frame tile
  rings (desert 50 tiles, city 40, arctic 25, volcanic 18), and those
  frames are already distinct images inside the sheets we ship. Both
  converters discard the fields. See `docs/BUGS.md` open item 2.
  Unit shadows are still genuinely absent — though `buildings/{robot,
  vehicle}/base_shadow.png` does ship, so the blanket "no shadow art in
  either asset set" was also too strong.
- Full soundtrack needs one run of `tools/zod/render_midi.sh`
  (fluidsynth + soundfont required)
- Weapon classes/splash. (Veterancy shipped; rocks and bridges are
  already destructible.)

## Open items closed (2026-08, second sweep)

- radar station now grants minimap enemy intel (own it to see enemy
  blips) + comp_radar_activated announcement
- full commander announcer set wired: manufacture start/cancel, repair
  start/done, radar online, ten "you're losing" taunts under 35% fort
  HP; simultaneous one-shot voices capped (fixes audio slot exhaustion)
- original track marks (per-planet tank sheets + jeep) drop behind
  moving vehicles and fade; blast craters (per-planet, random variants)
  persist under a cap; ambient animals (15 species, planet pools)
  wander maps and die in blasts
- building ground bases are split from the structure: units walking on
  a base draw OVER it (was: hidden behind the whole sprite)
- saves match zones by rect (not order); facility quick bar is
  event-driven with a slow death sweep; parade/pose tests assert
  pass/fail now
- known cosmetic: 4 ogg instances report leaked at exit (Godot quit
  path holds the cached stream chain — present since the first log)

## Not rebuildable from the original assets

- water animation (single-frame tile art — the original palette-cycled
  its 8-bit sheets; nothing to animate from) and unit shadows (no
  shadow art ships in either asset set).

## Modularization (2026-08)

Complete: native per-team art variants (each team loads the original
engine's own recoloured sprites — no runtime recolouring), VFX overhaul,
content as inspector-editable .tres defs, scene-per-unit/building,
Order/state machine, one weapon resolver, entity signals (HUD is
signal-driven), GameState split into NavWorld/MatchState/SaveSystem,
UnitRegistry, MapCatalog. Recipes for adding content:
docs/ASSET_CONVENTIONS.md.

## Multiplayer milestone 1 — P2P lobby (2026-08)

All Godot-native networking, no master server, no addons:

- **LanDiscovery** (`scripts/net/lan_discovery.gd`): hosts broadcast a
  JSON announce on UDP 46755 every second; the browse screen lists them
  with a ~5s TTL. Announces are address-targetable — a future
  self-hostable community list server reuses the same packet.
- **Net** autoload (`scripts/net/net.gd`): the host player's process IS
  the game server (ENet, port 46656). Host-authoritative room state
  over `@rpc`: clients request seats/ready/chat, the host rebroadcasts
  the whole room dict. Graceful disconnect on leave; late joiners are
  told the match began. Best-effort UPnP port forward so internet
  direct-IP joins can reach the host; the lobby shows the shareable
  address.
- **Screens**: title → MULTIPLAYER browse (game list, HOST GAME / JOIN /
  direct IP) → game room (map pick with real previews, per-fort-team
  seats with OPEN/CPU/CLOSED cycling, ready-up, chat) — skirmish-screen
  look on the original IPBackground art. Commander name in settings.
- **Start**: every peer runs the skirmish launch chain with their own
  `MatchState.player_team`. In-match order replication is NOT shipped —
  until it lands, remote players act as AI stand-ins locally (the
  existing MapLoader behaviour) and the connection stays up for phase 2.
- Verified by `--mp-test` (headless): discovery announce/TTL over
  loopback + a REAL ENet loopback session (join, hello, seat, ready,
  chat, start config, host-lost) using a second Net instance under its
  own SceneMultiplayer.
