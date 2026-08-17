# Roadmap — Z (1996) remake in Godot

Principles: editor-first (scenes, input map, tilemaps, resources),
data-driven unit stats, faithful vertical slice before breadth.

## Phase 0 — pivot to Z (1996) ✅

- [x] Purge Steel Soldiers assets/tools
- [x] Zod Engine asset pack in `assets_original/zod/` (gitignored)
- [x] 2D project: RTS camera (edge pan/zoom), drag-select, right-click
      orders, robots walking with original 16×16 sprites on desert tiles

## Phase 1 — real terrain & units

- [ ] TileMapLayer terrain from planet tilesets (`planets/*.bmp` +
      `.tileinfo`); map loader for Zod `*.map` text format
- [ ] Unit resource data (speed, hp, weapon, cost) as `.tres`
- [ ] All robot types + fire animations; vehicles (jeep/tanks/APC);
      cannons; fort/flag buildings with capture logic
- [ ] Selection portraits + command UI (Control scenes), HUD with money
- [ ] Sound: voice lines on select/order (assets/sounds), weapons fx,
      music

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
