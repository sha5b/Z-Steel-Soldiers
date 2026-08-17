# Roadmap — Godot remake

Principles:

1. **Idiomatic Godot**: scenes + built-in nodes first, scripts only for
   behaviour. No "everything in code" — use the editor for what the editor
   does (input maps, tweens, animation, UI, navigation, resources).
2. **Data-driven**: unit/building stats as `Resource` (`.tres`) files;
   levels defined by a converter from the original `.zlv` format.
3. **Faithful vertical slice first** (demo mission), then breadth.

## Phase 0 — project scaffold ✅ (partially)

- [x] Research, demo extraction, asset decryption, sound scraping
- [x] Docs: RESEARCH, FORMATS, ROADMAP
- [ ] Create Godot 4.7 project (`project/`), editor settings, input map,
      directory conventions, first commit opened in Godot

## Phase 1 — asset conversion pipeline

- [ ] `tools/zss/zrb_to_gltf.py`: decode ZRB token stream → glTF
      (nodes/hierarchy, transforms, materials + TGA textures, then meshes)
- [ ] `tools/zss/convert_textures.py`: TGA → PNG (Godot reads TGA fine, but
      normalizing sizes/formats keeps the project tidy)
- [ ] `tools/zss/parse_zlv.py`: `.zlv` → JSON level description
- [ ] Godot importer: JSON → `LevelData` resource; hot-reload friendly
- [ ] Sound curation: pick/copy demo WAVs + Sounds Resource packs into
      `project/assets/sfx/` with a naming scheme

## Phase 2 — core RTS framework (editor-first)

- [ ] `RtsCamera` (`Camera3D` rig): edge pan, zoom, rotate — input actions
      defined in Project Settings
- [ ] Terrain: heightmap mesh from level data (`MeshInstance3D` +
      `StaticBody3D`); water plane; `NavigationRegion3D` baked from it
- [ ] Selection: `Area3D` drag-box + ray picking; `SelectionManager`
      autoload (events via signals)
- [ ] `Unit` scene: `CharacterBody3D`/`Node3D` + `NavigationAgent3D`,
      `AnimationPlayer`, team material swap; orders (move/attack/garrison)
      via typed signals
- [ ] `Building` scene: production queue UI, spawn points, capture logic
- [ ] HUD: `Control` scenes for command bar, factory queue, radar minimap
      (`SubViewport` top-down camera)

## Phase 3 — gameplay systems (Z:SS identity)

- [ ] **Sector/territory system**: sector map (grid overlay), capture by
      proximity, income per sector-value tick, power distribution
- [ ] Full demo-mission object set: CC, radar, factories, guns, bunkers,
      robots (Grunt/Psycho/Tough/Sniper/Pyro/Technician), vehicles
- [ ] Crewed vehicles: robots enter/exit empty vehicles
- [ ] Mission scripting: event VM replacement — translate `.zrc/.zrh`
      logic (briefings, triggers, win/lose) into GDScript resource-driven
      mission definitions
- [ ] CPU opponent: state-machine AI (expand sectors → build → attack)

## Phase 4 — the demo mission, end to end

- [ ] Load `Demo1.zlv` data: Desert 256×256 map, Stormy/Midnight settings,
      both bases, all placed objects
- [ ] Mission brief flow, in-game dialogue triggers, win/lose conditions
- [ ] Juice: explosions (`GPUParticles3D`), tracers, taunts from sound packs

## Phase 5 — breadth & polish

- [ ] Remaining unit roster + balance pass
- [ ] More maps/missions; skirmish setup screen; save/load
      (`ResourceSaver`); audio buses; settings menu
- [ ] "Original assets" toggle vs CC0 fallback pack for public builds
- [ ] Packaging: Linux/Windows export presets

## Open RE questions (blocking fidelity)

| Question                                   | Where to look next            |
|--------------------------------------------|-------------------------------|
| ZRB mesh/animation chunk layout            | token-stream decode + `zrgeom.dll` strings |
| `.zrh` mission bytecode opcodes            | `EventSys.dll`/`EventEd.dll`  |
| `.dbs` sector/pathing layout               | compare with `.zlv`/`.map`    |
| `Symbols/*_sym.h` encipherment             | not single-byte XOR; check `zrcore.dll` |
| DIMEDSF audio codec                        | community unsolved; low priority |
