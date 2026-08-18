# Roadmap — Z (1996) remake in Godot

Final state at close: single-player feature-complete. Multiplayer was
deliberately left out (scope decision).

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

- Multiplayer (Zod's focus) — netcode not started
- Original GUI chrome (production menu art exists, unused), water
  animation, craters, unit shadows
- Full soundtrack needs one run of `tools/zod/render_midi.sh`
  (fluidsynth + soundfont required)
- Weapon classes/splash, veterancy, destructible rocks/bridges

## Modularization (2026-08)

Complete: master-art team palette swap, VFX overhaul, content as
inspector-editable .tres defs, scene-per-unit/building, Order/state
machine, one weapon resolver, entity signals (HUD is signal-driven),
GameState split into NavWorld/MatchState/SaveSystem, UnitRegistry,
MapCatalog. Recipes for adding content: docs/ASSET_CONVENTIONS.md.
