# Roadmap — Z (1996) remake in Godot

Principles: editor-first (scenes, input map, tilemaps, resources),
data-driven unit stats, faithful vertical slice before breadth.

## Phase 0 — pivot to Z (1996) ✅

- [x] Purge Steel Soldiers assets/tools
- [x] Zod Engine asset pack in `assets_original/zod/` (gitignored)
- [x] 2D project: RTS camera (edge pan/zoom), drag-select, right-click
      orders, robots walking with original 16×16 sprites on desert tiles

## Phase 1 — real terrain & units ✅ (core)

- [x] Zod `.map` format reversed (header/zones/objects/tiles) —
      `tools/zod/map_to_json.py`
- [x] MapLoader: TileMapLayer terrain from planet tilesets (5 planets),
      zones, robots, building placeholders; 3 stock maps converted
- [x] Territory system: zone flags (original animated flag sprites),
      capture by presence (2 s), income ticking per zone, money HUD
- [x] All 6 robot types with stand/walk/fire animations
- [x] Voice lines (acknowledge) on orders
- [ ] Unit stats as `.tres` resources; vehicles/cannons from map objects
- [ ] Selection portraits + command UI; weapon sounds
- [ ] Fire animations triggered on combat (needs combat system)

## Phase 2 — the game loop

- [ ] Territory/flag income system; factory production queues
- [ ] Combat: range, damage, deaths (die1-5 + wreck sprites)
- [ ] Robots entering vehicles/guns; constructor building/repair
- [ ] Zod map loader → playable stock multiplayer maps
- [ ] CPU opponent (expand → produce → attack state machine)

## Phase 3 — campaign & polish

- [ ] 20 campaign missions structure, briefings (Zod has map list)
- [ ] Idle humor animations (beer, cigarette, pope...) as done in Z
- [ ] Save/load, skirmish setup, balance pass
- [ ] Optional: original music (MID → rendered), cutscene stills
