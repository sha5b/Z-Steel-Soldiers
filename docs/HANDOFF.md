# Handoff — 2026-08-23

Two days of player-reported fixes, and one model we had wrong from the
first commit. Read this with `docs/BUGS.md` (verified open bugs) and
`docs/ROADMAP.md` (plan).

Test state at handoff: **49/49 headless lanes clean.** Lane list changed:
`--garrison-test` is now `--towercrew-test` (see *No units inside
buildings*). The count is unchanged.

> **Running the suite.** There is no `godot` on PATH here — it is the
> Flatpak. Every lane:
> `flatpak run org.godotengine.Godot --headless --path project res://scenes/main.tscn --<flag>-test --quit-after 30000`
> **After adding or renaming any `class_name`, run
> `flatpak run org.godotengine.Godot --headless --path project --import`
> first**, or every lane dies on `Could not find type "X"` — the global
> class cache is gitignored and only the editor writes it.

---

## 1. Production: Z has no build queue (the big one)

**We had a five-slot FIFO. That was invented, and wrong from the start.**
`docs/RESEARCH.md` listed "queues" under *what we already match*, which
was an assumption nobody had checked against the original.

In Z you point a factory at **one** unit type and it turns that out
**indefinitely** until you point it somewhere else. That is not cosmetic:
a queue makes production a burst you pay for once and forget, a line
makes it a standing commitment you keep re-deciding.

| Was | Now |
|---|---|
| `ProductionQueue`, `items: Array[String]`, cap 5 | `ProductionLine` (`entities/production_line.gd`): `selected`, `elapsed`, `paid` |
| Charged at enqueue | Charged as each unit **starts**. A stalled line costs nothing and banks no time. |
| Shift-click filled the queue | Gone with the queue it filled. One press points the line. |
| Cancel dropped the next item | **Cancel stops the line** and refunds the part-built unit. The factory goes idle and **stays** idle — `_defaulted` exists so the default cannot paper over the button. |
| Idle until you clicked | **Every producer defaults to the first entry of its own build list** on first activation, so a captured factory earns its keep immediately. |
| — | **Switching keeps the clock** (`ProductionLine.select`) and refunds the abandoned unit, so money stays straight either way. |

**Stalls, not refusals.** Three things pause a line without dropping the
selection, so it resumes by itself: no money, the population cap, and a
fort with all four cannon mounts full. `Producer._may_start` is the one
gate; `Building2D.accepts_product` is the capability query behind it
(only `FortBuilding` ever answers no).

Save contract changed: `"queue": [...]` → `"line"`, `"line_elapsed"`,
`"line_paid"`. `apply_dict` still reads a pre-line save — it takes the
head of the old list and drops the rest.

Wire: `Net.relay_line` / `relay_stop_line`. The intent kind is still
`"queue"` on the wire (identical payload); an **empty item means stop**.

**The AI drives the line too** (`CpuAi._produce`, fully rewritten):
- **Sticky.** Re-rolling the pick every pass would re-aim every factory
  every second, and because switching keeps the clock that emits a random
  unit whenever the timer lands. A line is only re-aimed when it is
  *wrong* (idle / off-roster / a cannon somewhere that must not build
  them) or `RELINE_MS` (25 s) has passed **and** the stance changed.
- **No unarmed lines.** APC and crane have `damage 0` — unarmed by
  design. A *permanent* line on one is a factory that never contributes
  another gun. They are off the ordinary choice entirely and built only
  against a concrete need (`_utility_need`: a crane when something of
  ours is broken and we own none; one APC once we hold ≥3 sectors).
- **Hardware needs a crew** (`crew_shortfall`). Vehicles and cannons
  spawn **team 0, unmanned** — a robot has to walk over and get in. Below
  `CREW_RESERVE` (3) spare robots plus one per empty hull near home,
  every facility that can make robots makes robots, and this *preempts*
  the stickiness. This was a real failure, not a theory: `--tactics-test`
  caught a run where the brain was down to one facility, its line was on
  `cannon:gun`, and it finished with **zero infantry to crew anything**.

Guarded by: `--prod-test`, `--fortprod-test`, `--cancel-test`,
`--factory-test`, `--cap-test`, `--capture-test`, `--qol-test`, and
`StrategyTests.builds_and_commits` (asserts every AI facility is aimed at
something on its own roster, and that six back-to-back think passes with
nothing changed re-aim **nothing**).

---

## 2. No units inside buildings

Robots used to walk into their own fort and crew a missile battery from
inside. Removed at the player's request, and it was the right call: a
unit inside a building cannot be seen, selected or counted, and no amount
of badge art on the roof fixes that.

Gone: `garrison`, `garrison_robot`, `release_garrison`, `kill_garrison`,
`crew_count`, the crew-pip badge, the garrison missile battery, the
`garrison_missile_*`/`garrison_cap` building-def exports (and their
values in `fort_front.tres`/`fort_back.tres`), the panel's EXIT strip,
`Commands._find_own_fort`, and **`Order.Type.GARRISON`**.

> `Order.Type` renumbered: **`STOP` is 8, was 9.** Deliberate — all peers
> run the same build. New kinds still go on the END. `--qol-test` pins it.

A fort now defends itself with its **tower guns**, which are real cannons
on real cells: they fire, they can be shot off the fort, and a destroyed
one frees its mount (`_slot_taken`) so a cannon line replaces it without
the player re-ordering. `--combat2-test` asserts that whole cycle.
`X`/`Commands.eject()` still works for **hulls** (crewed vehicles, loaded
APCs) — that was never the complaint.

---

## 3. Damage: every explosive weapon was harmless to buildings

`building_frac` (the anti-structure scale — a share of the target
building's max HP) existed only on small arms. Every tank, cannon,
missile and grenade had `0.0`, so it fell through to its flat *unit*
damage against a 33 333 HP fort. Measured, one unit alone:

| | before | after |
|---|---|---|
| heavy tank (cost 220) | **341 s** | 18 s |
| howitzer (110) | **486 s** | 35 s |
| medium tank (150) | **292 s** | 25 s |
| pyro robot (70) | 14 s | 14 s |

Two bugs kept it company:

- **`Vehicle2D._combat` is a separate copy of the firing logic** and its
  range gate still measured to `visual_center()` after `Unit2D` moved to
  the footprint edge. A fort's middle sits ~80 px inside its wall —
  further than a medium tank's whole 128 px reach — so **no crewed
  vehicle or cannon could fire on a fort at all.** It drove up, tracked
  the fort with its turret, and never pulled the trigger. *This was the
  bug the player actually saw.*
- That same pass asked `_find_target()` instead of
  `_ordered_or_nearest()`, so an explicit attack order never reached a
  tank's gun. And `Commands` excluded cannons from attack orders
  outright, so the howitzer — longest reach on the map at 200 px — was
  the one unit whose fire could not be directed.

`Combat.amount_against` is now the single conversion point and converts
**per victim**: a fort-aimed shell charges the fort on the building scale
and the units in its blast on the flat scale. Landing the fracs without
this would have made one heavy shell delete every unit within 50 px for
7 570.

Small-arms fracs are the transcribed reference and were left alone; the
explosive ones are derived as `cooldown / seconds-to-raze-a-fort-alone`.
The **pyro at 14 s is a known outlier** — the reference fractions ignore
fire rate, and its cooldown is 0.1 s. See `docs/RESEARCH.md` "Stat
fidelity".

**Not changed:** tanks one-shot infantry. A medium's 267 vs a grunt's 86
is 3.1× overkill; the original is 80 vs 8, i.e. 10×. Our port is already
~3.2× *less* lethal relative to HP than Z was, and `--balance-test`
asserts those flat numbers against `zsettings.cpp`. If it should change,
the lever is `hit_chance` — every explosive is at **1.00** and literally
cannot miss.

### Effects
- **`MOBIMIS` does not ship.** The pack has `MOBIMISS.wav` and
  `MOBIMIS2.wav`. The missile cannon and the fort battery were firing in
  total silence. → `MOBIMISS`.
- Medium/heavy tanks fired the **missile launcher's finned missile
  sprite**; the `gun` cannon fired a grenade sprite despite its `LTGUN`
  report. All three now use `vehicles_light/bullet.png` (7×4, the tank
  shell). The howitzer keeps the grenade art — consistent with `GRENLOBX`.
- `--vfx-test` now checks **every** def's sound resolves to a real wav
  and every projectile's impact effect has real art (not the particle
  fallback). That is what would have caught `MOBIMIS`.

---

## 4. Pathing and the AI's shape

**Units got stuck on building edges** because A* had no reason to prefer
open ground: an open cell touching a wall is 8 px off the wall face and a
vehicle's physics box is 16 px, so a wall-hugging route means permanent
contact for the whole leg — and it is usually the *shorter* route.
`NavWorld.paint_wall_margins()` costs the ring around every wall
(`WALL_MARGIN_WEIGHT`, passable but expensive), and `string_pull` will
not collapse the detour back onto the wall unless the anchor is already
inside the margin (the corridor case — a fort gate). Called once per
loader after every building has stamped its solids.

Also: `_repaths` resets per order (three brief jams *minutes apart* used
to cancel a move), a leashed sidestep detour replaces re-requesting the
identical failing route, and `_separation` has right-of-way so a doorway
stops deadlocking.

**The AI had no layer between the unit and the map.** Added:
- `game/ai_map.gd` — zone graph, adjacency, depth from our own fort,
  per-sector strength/value, all read once per think pass.
- `game/ai_squad.gd` — assemble → advance as a body (laggards close up)
  → engage → withdraw below 40 % of peak.
- `cpu_ai.gd` as commander: a four-way stance (turtle / consolidate /
  expand / press) with a defence budget and strike count.

Crucially **squad members are excluded** from the reactive defence, the
push and the ZBot assignment. Three layers all drafting from "the idle
units" is what dissolved every attack; `StrategyTests.single_owner` pins
it.

Two bugs fell out of writing those tests:
- The zone graph came out as **four disconnected islands** — a flat 40 px
  adjacency tolerance against the shipped map's 160 px seam. Tolerance is
  now a fraction of sector size.
- `power_ratio` compared us against **every other team summed**, so on a
  multi-team map the brain thought it was losing from minute one and
  turtled permanently. Now it compares against the strongest single
  rival.

**Pixel shadow.** The unit shadow was a `draw_circle` under a scale
transform — an antialiased vector ellipse under 16 px nearest-neighbour
sprites. Now rasterised as whole-pixel rows with hard edges.

---

## Open / next

1. **`--tactics-test` is noisy.** Zone count over a 3-minute sim ranges
   ~3–12 across seeds. It asserts *floors*, not values, deliberately —
   but a genuine regression inside that band would not be caught. Worth a
   longer, seeded AI lane.
2. **The pyro's 14 s fort razing.** Faithful to the reference table and
   still absurd next to a heavy tank's 18 s at 3× the cost. Fixing it
   means departing from a transcribed number; the player's call.
3. **Explosives cannot miss** (`hit_chance = 1.00`). See §3.
4. **`_utility_need` only fires when a line is already being re-aimed**,
   so a crane for a freshly-broken bridge can wait up to `RELINE_MS`.
   Acceptable; noted so it is not mistaken for a bug.
5. **`content/projectiles/garrison_missile.tres`** is now unreferenced.
   Left in place (harmless, `--defs-test` is clean); delete if you want
   the tree tidy.
6. Everything still open in `docs/BUGS.md` — the retail starting armies,
   the unconverted HUD frame and production chrome, MP determinism.
