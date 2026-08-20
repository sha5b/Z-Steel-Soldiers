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

## Not done (known gaps for a future task)

- Multiplayer IN-MATCH sync — the lobby/connection layer is done (next
  section); replicating player orders needs the determinism work
  (choke points are ready: `Unit2D.issue_order`, `queue_unit`,
  `set_rally`)
- Original GUI chrome (production menu art exists, unused), water
  animation, craters, unit shadows
- Full soundtrack needs one run of `tools/zod/render_midi.sh`
  (fluidsynth + soundfont required)
- Weapon classes/splash, veterancy, destructible rocks/bridges

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
