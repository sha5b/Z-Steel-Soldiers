# Known bugs & tolerated baselines

Live tracker for verified, evidence-backed bugs. Everything here has a
file:line root cause. Fixed items move to the bottom section with the
commit that fixed them — do not delete history.

## Open — Phase 1 targets (root-caused 2026-08-20)

1. **Driverless vehicles drive to the enemy HQ.** `building.gd` `spawn_produced()`
   issues `vehicle.move_to(rally_point)` on unmanned products, and
   `cpu_ai.gd` `_update_rallies()` rallies every AI facility at an enemy
   fort/zone objective. `issue_order()` and `Vehicle2D._steer()` have no
   `manned` gate (only `_combat` does). Original Z: empty vehicles wait
   for a driver.
2. **Units get stuck inside buildings.** Unchecked position teleports
   probe at most the center cell: dodge sidestep (`unit_2d.gd`
   `take_damage`), APC `unload()`, driver/fort-slot ejection
   (`vehicle_2d.gd`), repair-shop exit (`building.gd` — 16px vehicle
   boxes half-spawn in the wall), and `_separation` probes that
   undershoot the vehicle body and skip corners.
3. **Paths clip building corners.** Cell-center waypoints + corner-hugging
   diagonals + the replaced final leg make beelines cross solid-cell
   corners; the leapfrog waypoint-consume fires during wall slides and
   worsens it. Tolerated baseline: the `--path-test` seed-42 walker
   crosses 16/145 solid samples (`PathTests.KNOWN_CROSSING_BASELINE`).
4. **Walls-without-solids for loader-external buildings.** Physics walls
   build in `Building2D._ready` but nav solids are painted only by the
   two `MapLoader` paths (silent `def == null` skip included) —
   self-test fixtures are one missing def away from shipping the
   stuck+walk-through combo.
5. **Forts are practically unkillable.** (a) Cranes repair forts at
   1,750 HP/s (`vehicle_2d.gd` `_crane_repair_tick` 700/0.4s, no fort
   exclusion; AI `_maintenance` targets damaged forts; every fort build
   list contains `vehicle:crane`). (b) The ×3.33 stat rescale skipped
   small arms — grunt=1/laser=14 flat vs FORT_HP 33333 is ~6.6h solo,
   where the original's small arms were fraction-of-max-HP (grunt
   0.0011 ≈ 11 min; see docs/RESEARCH.md). Explosive TTK is faithful.
6. **The self-test suite runs with physics off.** `MatchState.direct_step`
   bypasses `move_and_slide` everywhere, and NAVSOLID failures only
   print — bug classes 2-4 are invisible to the sweep today.

## Open — stragglers from the consolidated sweep (tier 3/4)

7. **Radar dish wobbles sideways while spinning** — mixed-width frames
   (32/24/16) top-left anchored; planned fix: pad to a common
   content-centred canvas at load. Needs visual confirmation.
8. **Crane `arm_off` dead data / hook not anchored to the arm.**
9. **Minor:** cursor dead garrison branch (`game_cursor.gd`),
   BRIDGE self-test probes a centred span. (Net hello-race and the
   production-panel signal leak from the same tier are fixed.)

## Fixed

- 2026-08-20, `131b64e` — the consolidated 35-item sweep (jeep hull
  strobe, effect bottom-anchor, fort/bridge rects, mirrored turret
  tables, minimap fort blip, dead decals/animals via `map_root`,
  dead-factory production, vehicle-death elimination, carried-units
  check, repair-bay/radar group scans, APC squad fire, factory
  targeting, fort-held zones, grenade-vs-fort impact, garrison missile
  double-charge, bridge rubble physics, scene-map group queries, HP
  bars, dodge ratio, capture refunds, splash-to-rect, repair-shop
  offset, effect prefixes, hit-flash guard, plus BUILDINGGEO/NAVSOLID
  test updates). Plan doc: `.zcode/plans/plan-sess_f66e1fbc*.md`.
