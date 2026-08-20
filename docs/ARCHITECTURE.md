# Architecture

How the Z (1996) remake is put together, as of the Phase 2 relocation
(2026-08). Grounded in the engine's own guidance: match state belongs
to the match scene, autoloads only for wide-scope session services
(Godot docs, "Autoloads versus regular nodes" / "Scene organization").

## The match scene owns the match

`scenes/main.tscn` (script `scripts/game/match.gd`) is the whole match:

```
Main (match.gd — coordinator: loads the map, wires HUD/input,
      applies the launch config and saves, ends the game)
├── NavWorld          match-scoped: pathing grids, map bounds,
├── UnitRegistry      the body-clearance placement contract
├── SelectionManager  who exists (typed roster + queries)
├── MatchState        selection, drag rect, order stance (player intent)
│                    economy: money/zones/tech/pop caps
├── RtsCamera2D
└── CanvasLayer
    ├── HUD (TopBar, MiniMap, StanceBar, SelectionBar,
    │        FacilityList, ProductionPanel, SelectionRect, PauseMenu)
    └── (GameCursor installs here at runtime)
```

The four subsystem nodes are FIRST children on purpose: children ready
before the HUD, so the HUD can connect to their signals in `_ready`.

**The locator pattern.** Each subsystem script declares
`class_name` + `static var current` (set in `_ready`, cleared in
`_exit_tree`). Call sites read `MatchState.current.money`,
`NavWorld.current.request_path(...)`, etc. This keeps per-instance
state behind the familiar names while the instances themselves live and
die with the scene. Two matches can coexist in one tree — the
in-process MP loopback test depends on it.

**Why not full dependency injection?** The locator is the reversible
80/20: zero call-site churn for per-instance state today, and Phase 4's
entity composition can inject real references into the locomotion
solver when it extracts one. Do not add new autoloads for match state.

## Session services (the 8 autoloads)

ContentDB (content registry + .tres defs), Fx (presentation), SaveSystem
(per-entity save contract), GameSettings (persisted options),
GameState (match FLOW: next map, pending save/config, win/lose),
MusicPlayer, Campaign (mission progress), Net (lobby/session).

GameState is the seam between sessions and matches: it holds the
`MatchConfig` for the match being launched (`pending_config`) because
per-instance state cannot be written before the scene exists.

## Launch flow

```
skirmish / campaign-brief / title-continue / mp-lobby
        │  MatchConfig.make(source, map, player_team, save)
        ▼
GameState.prepare_match(cfg)     # resets, stores next_map/pending_load/pending_config
        │  change_scene_to_file(main.tscn)
        ▼
match.gd _ready                  # subsystem children already readied
  MatchState.current.player_team = pending_config.player_team
  MapLoader.load_map(...)        # fills NavWorld grids, spawns map entities
  _apply_load() if pending_load  # save contract restores roster/economy
```

The same `MatchConfig` shape is what MP peers will send over the wire
for in-match replication (milestone 2).

## Core contracts

- **One order intake**: players, AI and tests all issue orders through
  `Unit2D.issue_order(Order)`; production through `queue_unit`, rally
  through `set_rally`. These three are the MP replication surface.
- **One placement contract**: every instant position (spawn, dodge,
  unload, eject, repair exit, save restore) goes through
  `NavWorld.find_free_spot` — full body-box probes, per-kind
  half-extent. Path breadcrumbs are nudged body-clear by the same rule.
- **One geometry source**: building art rects come from
  `art_world_rect()`/`visual_center()` (Phase 5 makes this exhaustive).
- **Single-writer money**: production code only writes the economy via
  `MatchState.deposit/set_money/grant_ledger/spend`.
- **Walls and solids together**: `Building2D.apply_footprint()` paints
  physics walls AND nav solids from `_ready` (loaders complete the
  pair for scene maps whose children ready before grids exist).

## Tests

`scripts/tests/` — headless flag harness (see README for the sweep).
`SelfTests.run` routes flags; per-domain modules (path_tests,
placement_tests) take `(ctx, rig)`. A run passes with zero
`SCRIPT ERROR`, `CHECK FAILED:` and assertion-failure lines. The
default mode bypasses physics (`TestLevers.direct_step`) for speed;
`--placement-test` runs REAL physics frames. Every convention above
has a flag guarding it.

## Save contract = snapshot schema

`SaveSystem` + per-entity `to_dict/apply_dict` define the canonical
match snapshot. MP late-join/state reconciliation will reuse it
verbatim (Phase 7).
