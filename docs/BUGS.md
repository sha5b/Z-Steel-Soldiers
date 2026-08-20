# Known bugs & tolerated baselines

Live tracker for verified, evidence-backed bugs. Everything here has a
file:line root cause. Fixed items move to the bottom section with the
commit that fixed them — do not delete history.

## Open — stragglers from the consolidated sweep (tier 3/4)

1. **Radar dish wobbles sideways while spinning** — mixed-width frames
   (32/24/16) top-left anchored; planned fix: pad to a common
   content-centred canvas at load. Needs visual confirmation.
2. **Crane `arm_off` dead data / hook not anchored to the arm.**
3. **Minor:** cursor dead garrison branch (`game_cursor.gd`),
   BRIDGE self-test probes a centred span. (Net hello-race and the
   production-panel signal leak from the same tier are fixed.)
4. **Path corner-clipping baseline** — beeline segments between
   waypoints can graze solid-cell corners (center-cell crossings,
   seed-42 walker: 12/148 samples, down from 16 after breadcrumb
   nudging). `PathTests.KNOWN_CROSSING_BASELINE` tolerates 16; collapse
   it to 0 when the beeline class is fixed for good.
5. **Gatling cannon has no `building_frac`** — it keeps flat damage 3
   vs buildings (the original table in docs/RESEARCH.md doesn't cover
   it; harmless but inconsistent with the other small arms).

## Fixed

- 2026-08-20, phase 1 — the three reported bug classes:
  - `d842009` **driverless vehicles driving to the enemy HQ** —
    unmanned products take no rally; `issue_order` refuses unmanned
    hardware; `eject_driver` halts the hull (`--rally-test`).
  - `5a5c599` **units stuck in / walking into buildings** —
    `NavWorld.body_clear`/`find_free_spot` full-box placement contract
    behind every teleport; breadcrumbs nudged body-clear (corner-pocket
    stalls); leapfrog consume suppressed on wall slides;
    `apply_footprint` single front door for walls+solids with loud
    def==null; physics-ON test rig (`--placement-test`); NAVSOLID/
    BUILDINGGEO failures now fail the sweep.
  - phase-1e commit **forts unkillable** — cranes never repair forts
    (original Z), small arms deal fraction-of-target-max-HP vs buildings
    per the zsettings table (`--fortkill-test`).
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
