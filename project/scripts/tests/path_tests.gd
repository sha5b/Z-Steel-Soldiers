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
