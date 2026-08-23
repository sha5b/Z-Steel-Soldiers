class_name PathTests
extends Object
## Pathing domain of the headless harness, split out of self_tests.gd
## as the pattern for per-domain test modules: one class_name per domain,
## static funcs taking (ctx, rig), flags still routed from
## SelfTests.run() so the CLI surface does not change.

## Solid-crossing tolerance for the seed-42 walker on the default test
## map: ZERO. It sat at 16 (then 10 observed) while A* handed back cell
## CORNER waypoints — every breadcrumb was half a cell up-left of the
## cell it stood for, so the beelines between them grazed walls. With
## the cell-centre contract in NavWorld.make_grid the walker samples
## clean (0/145), so any crossing at all is a real regression now.
const KNOWN_CROSSING_BASELINE := 0


## ASSAULTING A BUILDING — the "the AI gets stuck around buildings" lane.
##
## Two rules are asserted, and both used to be broken:
##
##  1. RANGE IS MEASURED TO THE FOOTPRINT, not the footprint CENTRE. A
##     fort is 160x144px, so its middle sits up to 100px inside the walls
##     — further than a grunt's 58px weapon range. Every range gate
##     measured to that middle, so a robot standing with its barrel
##     against the wall was "out of range": it never fired, the chase
##     re-pathed, it arrived on the same cell, re-pathed again. That is
##     what the twitching ring of attackers around a building was.
##
##  2. THE SQUAD SURROUNDS IT. Walking at the footprint centre routes
##     every attacker to the single open cell nearest that centre — on a
##     fort, the gate — so a squad queued up single file in one doorway.
##     Attackers approach the side they came from (Building2D
##     .approach_point), so a ring of six stands on more than one spot.
##
## Real physics: the whole failure lives in move_and_slide against the
## building walls, which the logic-only lanes cannot see.
static func assault_a_building(ctx: Node, rig: TestRig) -> void:
	var levers_was: bool = TestLevers.direct_step
	var idle_was: bool = GameSettings.auto_idle
	TestLevers.direct_step = false
	GameSettings.auto_idle = false
	GameState.over = true  # the map's own war must not shoot the squad
	var fort := FortBuilding.new()
	fort.setup(0, 2, "desert")
	# somewhere with room around it: the map's own south-west quarter
	fort.position = Vector2(400, 1600)
	ctx.add_child(fort)
	await ctx.get_tree().physics_frame
	fort.apply_footprint()
	# It has to SURVIVE the window: the loaded map's own army shoots at it
	# too, and a fort that falls mid-test drops every attack order and
	# reads as six wedged attackers. Inflating max_hp does NOT work —
	# small arms do a FRACTION of max HP per hit (building_frac), so a
	# bigger fort just takes bigger hits. Topping it back up every frame
	# is the only way to hold it at full health with real damage numbers.
	var fp := fort.world_footprint()
	# six attackers in an arc south of the fort, well outside its walls
	var squad: Array[Unit2D] = []
	for i in 6:
		var spot := NavWorld.current.find_free_spot(
			Vector2(fp.get_center().x + (float(i) - 2.5) * 28.0, fp.end.y + 120.0),
			"robot")
		if spot == Vector2.INF:
			continue
		var u: Unit2D = Spawner.spawn(ctx, "robot", "grunt", 1, spot) as Unit2D
		u.hp = 100000000
		u.max_hp = 100000000
		# no grenades: a lobbed grenade reaches 80px and would mask the
		# thing under test, which is whether the RIFLE ever gets a shot
		u.grenades = 0
		squad.append(u)
	rig.check(squad.size() >= 4,
		"only %d of 6 attackers found a clear start spot" % squad.size())
	if squad.size() < 4:
		TestLevers.direct_step = levers_was
		GameSettings.auto_idle = idle_was
		rig.finish()
		return
	# RANGE CONTRACT, straight from the unit: the point it measures to is
	# on the footprint, never the middle of it
	var probe: Unit2D = squad[0]
	var reach: Vector2 = probe.reach_point(fort)
	rig.check(fp.grow(1.0).has_point(reach),
		"reach_point %s is not on the fort footprint %s" % [reach, fp])
	rig.check(reach.distance_to(probe.global_position)
			< fort.visual_center().distance_to(probe.global_position),
		"reach_point is no closer than the footprint centre — the range "
		+ "gate still measures to the middle of the building")
	for u in squad:
		u.issue_order(Order.attack(fort))
	# run the WHOLE window, never break on first blood: the end state is
	# what the standoff assertions read, and stopping at an arbitrary
	# frame samples the squad mid-walk
	var first_blood := -1
	var damage_seen := 0
	for i in 1800:  # 30 simulated seconds at 60Hz
		await ctx.get_tree().physics_frame
		if fort.hp < fort.max_hp:
			if first_blood < 0:
				first_blood = i
			damage_seen += fort.max_hp - fort.hp
			fort.hp = fort.max_hp  # see above: hold it up, count the hits
	# THE ASSAULT LANDS. Not "some unit eventually shoots" — every
	# attacker has to end up somewhere it can fire from.
	rig.check(damage_seen > 0,
		"six attackers ordered onto the fort did it no damage in 30s")
	var out_of_range := 0
	var wedged := 0
	var spots := {}
	for u in squad:
		if not is_instance_valid(u):
			continue
		if u.global_position.distance_to(u.reach_point(fort)) > u.range_px * 1.6:
			out_of_range += 1
		if fort.alive and u.state == Unit2D.State.IDLE and u.attack_target == null:
			wedged += 1  # order dropped: the watchdog gave up on it
		spots[NavWorld.cell_at(u.global_position)] = true
	rig.check(out_of_range <= 1,
		"%d of %d attackers never got within reach of the fort"
		% [out_of_range, squad.size()])
	rig.check(wedged == 0,
		"%d of %d attackers had their attack order cancelled (wedged)"
		% [wedged, squad.size()])
	# and they SURROUND it instead of queueing in the gate
	rig.check(spots.size() >= mini(3, squad.size()),
		"%d attackers ended on only %d distinct cells — still funnelling "
		% [squad.size(), spots.size()] + "into one approach")
	# THE FUNNEL, measured. Walking at the footprint CENTRE sends every
	# attacker to the one open cell nearest that centre, and on a fort
	# that cell is inside the walls: the whole assault single-files
	# through a two-cell gate under fire to reach it. Attackers belong
	# OUTSIDE, standing off the wall they are shooting.
	var inside := 0
	for u in squad:
		if is_instance_valid(u) and fp.has_point(u.global_position):
			inside += 1
	rig.check(inside <= 1,
		"%d of %d attackers walked INSIDE the fort footprint — the assault "
		% [inside, squad.size()] + "is still routing at the building centre")
	for u in squad:
		if is_instance_valid(u):
			u.queue_free()
	fort.queue_free()
	TestLevers.direct_step = levers_was
	GameSettings.auto_idle = idle_was
	rig.finish("attackers=%d damage=%d first_blood=%df spots=%d inside=%d" % [
		squad.size(), damage_seen, first_blood, spots.size(), inside])


## MANY walkers, MANY routes: every unit handed a routable destination
## must actually GET there. One walker (walk_a_pair) proves the route is
## clean; this proves the ORDER completes, which is the failure the
## "units stop halfway and do nothing" reports describe. Runs with the
## fast direct-step so it can afford 24 routes.
static func walkers_arrive(ctx: Node, rig: TestRig) -> void:
	var grid: AStarGrid2D = NavWorld.current.nav_grid
	if grid == null:
		rig.check(false, "no nav grid")
		rig.finish()
		return
	GameSettings.auto_idle = false  # no self-ordered detours mid-errand
	GameState.over = true           # the map's own war must not kill them
	var open := PackedVector2Array()
	for y in grid.region.size.y:
		for x in grid.region.size.x:
			var c := grid.region.position + Vector2i(x, y)
			if not grid.is_point_solid(c):
				open.append(Vector2(c))
	if open.size() < 2:
		rig.finish("no open cells")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tried := 0
	var stalled := 0
	var worst := ""
	for attempt in 400:
		if tried >= 24:
			break
		var a: Vector2 = open[rng.randi_range(0, open.size() - 1)]
		var b: Vector2 = open[rng.randi_range(0, open.size() - 1)]
		if a.distance_to(b) < 40.0:
			continue
		var from := NavWorld.cell_center(Vector2i(a))
		var to := NavWorld.cell_center(Vector2i(b))
		if NavWorld.current.request_path(from, to, "robot").is_empty():
			continue
		tried += 1
		var w: Unit2D = load("res://scenes/unit.tscn").instantiate()
		w.team = 1
		w.position = from
		ctx.add_child(w)
		w.hp = 100000000
		w.max_hp = 100000000
		w.move_to(to)
		var steps := 0
		# generous budget: the longest route on a 256x256 map at 60px/s
		for i in 4000:
			steps = i
			w._process(0.05)
			w._physics_process(0.05)
			if not w.has_move_target():
				break
		var left: float = w.global_position.distance_to(to)
		if left > 24.0:
			stalled += 1
			if worst == "":
				worst = "from %s to %s stopped %.0fpx short after %d steps" % [
					from, to, left, steps]
		w.queue_free()
	rig.check(tried > 0, "no routable pairs found at all")
	rig.check(stalled == 0, "%d of %d walkers never arrived (%s)" % [
		stalled, tried, worst])
	rig.finish("routes=%d stalled=%d" % [tried, stalled])


## Random-pair walking audit over the loaded map's nav grid: a robot
## walks a routable pair while its cell is sampled for solidity — any
## solid sample is a placement/nav regression, not a printout.
static func walk_a_pair(ctx: Node, rig: TestRig) -> void:
	var grid: AStarGrid2D = NavWorld.current.nav_grid
	if grid == null:
		rig.check(false, "no nav grid")
		rig.finish()
		return
	var solid := 0
	var open_cells := PackedVector2Array()
	for y in grid.region.size.y:
		for x in grid.region.size.x:
			if not grid.is_point_solid(Vector2i(x, y)):
				open_cells.append(Vector2(x, y))
			else:
				solid += 1
	rig.check(open_cells.size() > 1, "grid has no open cells")
	if open_cells.size() <= 1:
		rig.finish()
		return
	# pick a routable pair (maps can have disconnected landmasses)
	var start_px := Vector2.ZERO
	var goal := Vector2.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for attempt in 200:
		var a2: Vector2 = open_cells[rng.randi_range(0, open_cells.size() - 1)]
		var b2: Vector2 = open_cells[rng.randi_range(0, open_cells.size() - 1)]
		if a2.distance_to(b2) < 60.0:
			continue
		var probe := NavWorld.current.request_path(a2 * 16.0 + Vector2(8, 8),
			b2 * 16.0 + Vector2(8, 8), "robot")
		if not probe.is_empty():
			start_px = a2 * 16.0 + Vector2(8, 8)
			goal = b2 * 16.0 + Vector2(8, 8)
			break
	if goal == Vector2.ZERO:
		# not a failure: the loaded fragment may be a single landmass
		print("PATH: no routable pair found (skipped)")
		rig.finish()
		return
	# SMOOTHING. The raw A* result is a cell-centre staircase; string
	# pulling drops the corners nobody has to turn at. Assert both halves
	# of the contract: it really removes points, and every segment it
	# keeps is one the walker would accept (same predicate).
	var raw := NavWorld.current.grid_for("robot").get_point_path(
		Vector2i((start_px / 16.0).floor()), Vector2i((goal / 16.0).floor()))
	var pulled := NavWorld.current.request_path(start_px, goal, "robot")
	rig.check(not pulled.is_empty(), "smoothed path came back empty")
	if not pulled.is_empty() and raw.size() > 2:
		rig.check(pulled.size() <= raw.size(),
			"string pull GREW the path: %d -> %d" % [raw.size(), pulled.size()])
		rig.check(pulled.size() < raw.size(),
			"string pull removed nothing (%d points, staircase kept)" % raw.size())
		var bad_leg := -1
		for leg in range(pulled.size() - 1):
			if not NavWorld.current.segment_clear(pulled[leg], pulled[leg + 1], "robot"):
				bad_leg = leg
				break
		rig.check(bad_leg < 0,
			"smoothed leg %d cuts through a solid cell" % bad_leg)
		rig.check(pulled[0].distance_to(raw[0]) < 24.0
			and pulled[pulled.size() - 1].distance_to(goal) < 24.0,
			"string pull moved the endpoints")

	var walker: Unit2D = load("res://scenes/unit.tscn").instantiate()
	walker.team = 1
	walker.position = start_px
	ctx.add_child(walker)
	walker.move_to(goal)
	var crossed_solid := 0
	var total := 0
	for i in 6000:
		walker._process(0.05)
		walker._physics_process(0.05)
		if i % 5 == 0:
			var cell := Vector2i((walker.position / 16.0).floor())
			if grid.is_point_solid(cell):
				crossed_solid += 1
			total += 1
		if not walker.has_move_target():
			break
	var dist: float = walker.position.distance_to(goal)
	rig.check(crossed_solid <= KNOWN_CROSSING_BASELINE,
		"walker crossed solid cells %d/%d samples (baseline %d)" % [
			crossed_solid, total, KNOWN_CROSSING_BASELINE])
	rig.check(not walker.has_move_target(),
		"walker never arrived (dist=%.1f)" % dist)
	walker.queue_free()
	rig.finish("solid_cells=%d waypoints=%d crossed_solid=%d/%d arrived=%s dist=%.1f" % [
		solid, walker.waypoints.size(), crossed_solid, total,
		not walker.has_move_target(), dist])
