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
		if walker.move_target == Vector2.ZERO:
			break
	var dist: float = walker.position.distance_to(goal)
	rig.check(crossed_solid <= KNOWN_CROSSING_BASELINE,
		"walker crossed solid cells %d/%d samples (baseline %d)" % [
			crossed_solid, total, KNOWN_CROSSING_BASELINE])
	rig.check(walker.move_target == Vector2.ZERO,
		"walker never arrived (dist=%.1f)" % dist)
	walker.queue_free()
	rig.finish("solid_cells=%d waypoints=%d crossed_solid=%d/%d arrived=%s dist=%.1f" % [
		solid, walker.waypoints.size(), crossed_solid, total,
		walker.move_target == Vector2.ZERO, dist])
