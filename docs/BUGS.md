# Known bugs & tolerated baselines

Live tracker for verified, evidence-backed bugs. Everything here has a
file:line root cause. Fixed items move to the bottom section with the
commit that fixed them — do not delete history.

## Open — tolerated baselines

1. **Path boundary-hugging samples** — the `--path-test` seed-42 walker
   logs ~10/147 center-cell solid samples (tolerance
   `PathTests.KNOWN_CROSSING_BASELINE = 16`). These are borderline
   cell-boundary graze samples along one wall-adjacent route, NOT wall
   penetration — the physics-ON walker (`--placement-test`) is clean
   (bad=0), and the final-leg segment check + nudge-repair pass in
   `NavWorld.request_path` (2026-08-20) reduced this from 16. The
   residual is sampling noise at cell edges; collapse to 0 only with a
   per-segment marching solver in the locomotion work.
2. **Crane `arm_off` dead data** — WONTFIX, documented: the rig renders
   correctly via canvas alignment (hook_off table IS applied);
   folding arm_off in has no proven defect to fix and no headless way
   to verify the visual.

## Fixed

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
