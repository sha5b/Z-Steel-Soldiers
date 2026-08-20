class_name GarrisonTests
extends Object
## Fort-entry domain of the headless harness: everything about ordering
## a robot ONTO a building, or onto hardware parked somewhere no robot
## can stand. Runs with REAL physics (direct_step off) because the whole
## bug class lives in the interaction between move_and_slide and the nav
## grid — the fast logic-only lanes cannot see it.
##
## The three failures this module was written for:
##  1. the fort GATE. A fort's solid pattern leaves a 2-cell corridor
##     open (BuildingDef.open_tiles); a robot ordered onto its own fort
##     has to walk that corridor and garrison. While A* handed back cell
##     CORNER waypoints, the breadcrumbs inside the gate sat ON the wall
##     line, the robot ground itself against the wall and the stuck
##     watchdog cancelled the order after three re-routes.
##  2. re-crewing a fort TOWER GUN. Tower mounts are solid cells, so no
##     robot can ever reach contact distance; boarding has to resolve
##     from arm's length once the walk is over.
##  3. hardware that is genuinely unreachable must leave the robot IDLE
##     and retaskable, never parked in ENTERING for the whole match.
##
## Wait loops are written out INLINE on purpose: an `await` helper
## coroutine called from a static func does not resume here, so each
## loop awaits directly (same shape as placement_tests.gd).

const SETTLE_FRAMES := 600


## The player's fort on the loaded map (null when the map has none).
static func _player_fort(ctx: Node) -> FortBuilding:
	for b in ctx.get_tree().get_nodes_in_group(Groups.BUILDINGS):
		if b is FortBuilding and is_instance_valid(b) and b.alive \
				and b.team == MatchState.current.player_team:
			return b
	return null


static func run(ctx: Node, rig: TestRig) -> void:
	TestLevers.direct_step = false  # REAL move_and_slide for this block
	var idle_was: bool = GameSettings.auto_idle
	GameSettings.auto_idle = false  # no self-ordered detours mid-errand
	var fort := _player_fort(ctx)
	if fort == null:
		print("GARRISON: no player fort on this map (skipped)")
		GameSettings.auto_idle = idle_was
		rig.finish()
		return
	var team: int = fort.team
	var footprint := fort.world_footprint()

	# ---- 1. walk in through the gate and garrison -------------------
	# start clear of the footprint, south of it: request_path routes to
	# whichever gate mouth this fort variant actually opens
	var start := NavWorld.current.find_free_spot(
		Vector2(footprint.get_center().x, footprint.end.y + 96.0), "robot")
	rig.check(start != Vector2.INF, "no clear approach spot south of the fort")
	if start == Vector2.INF:
		GameSettings.auto_idle = idle_was
		rig.finish()
		return
	var before: int = fort.garrison.size()
	var walker: Unit2D = Spawner.spawn(ctx, "robot", "grunt", team, start) as Unit2D
	await ctx.get_tree().physics_frame
	walker.issue_order(Order.for_target(fort))
	rig.check(not walker.waypoints.is_empty() or walker.move_target != Vector2.ZERO,
		"fort order produced no route at all from %s" % start)
	var walk_frames := 0
	for i in SETTLE_FRAMES:
		if fort.garrison.size() > before or not is_instance_valid(walker):
			break
		walk_frames = i
		await ctx.get_tree().physics_frame
	rig.check(fort.garrison.size() > before,
		"robot never garrisoned the fort in %d frames (stopped at %s, state %s)" % [
			walk_frames, walker.global_position if is_instance_valid(walker) else Vector2.INF,
			walker.state if is_instance_valid(walker) else -1])
	# the garrison must hold LIVE nodes: freeing them made the battery
	# crewless-but-firing, garrison_cap count ghosts and kill_garrison a
	# no-op, and dropped the defenders out of the no-units rule
	var ghosts := 0
	for member in fort.garrison:
		if not is_instance_valid(member) or not member.alive or not member.carried:
			ghosts += 1
	rig.check(ghosts == 0,
		"%d of %d garrison entries are not live carried robots" % [
			ghosts, fort.garrison.size()])
	# and the fort falling has to kill them
	var held: Array[Node] = fort.garrison.duplicate()
	fort.kill_garrison()
	var survivors := 0
	for member in held:
		if is_instance_valid(member) and member.alive:
			survivors += 1
	rig.check(survivors == 0 and fort.garrison.is_empty(),
		"kill_garrison left %d of %d defenders alive (list size %d)" % [
			survivors, held.size(), fort.garrison.size()])

	# ---- 2. re-crew a tower gun whose driver was sniped -------------
	# mount a gun on a tower slot (a SOLID cell inside the walls), empty
	# it, then order a robot onto it from outside
	var mounted: bool = fort.mount_product("cannon", "gatling")
	rig.check(mounted, "fort refused to mount a tower cannon")
	var gun: Vehicle2D = null
	for c in fort.slot_cannons:
		if c is Vehicle2D and is_instance_valid(c):
			gun = c
			break
	rig.check(gun != null, "mounted cannon never landed in slot_cannons")
	if gun != null:
		await ctx.get_tree().physics_frame
		gun.eject_driver()
		rig.check(not gun.manned, "eject_driver left the tower gun manned")
		var crew_spot := NavWorld.current.find_free_spot(
			Vector2(footprint.get_center().x, footprint.end.y + 64.0), "robot")
		var crew: Unit2D = Spawner.spawn(ctx, "robot", "grunt", team,
			crew_spot if crew_spot != Vector2.INF else start) as Unit2D
		await ctx.get_tree().physics_frame
		crew.issue_order(Order.for_target(gun))
		var crew_frames := 0
		for i in SETTLE_FRAMES:
			if gun.manned or not is_instance_valid(crew):
				break
			crew_frames = i
			await ctx.get_tree().physics_frame
		rig.check(gun.manned,
			"tower gun on a solid cell could not be re-crewed in %d frames" % crew_frames)
		if is_instance_valid(crew):
			crew.queue_free()

	# ---- 3. unreachable hardware must not park a robot forever -----
	# a gun deep inside the walls with no route to it: the robot has to
	# land back in IDLE (retaskable) instead of holding ENTERING forever
	var far := NavWorld.current.find_free_spot(
		Vector2(footprint.get_center().x, footprint.position.y - 128.0), "robot")
	if far != Vector2.INF:
		var stray: Unit2D = Spawner.spawn(ctx, "robot", "grunt", team, far) as Unit2D
		var derelict: Vehicle2D = Spawner.spawn(ctx, "cannon", "gatling", 0,
			footprint.get_center()) as Vehicle2D
		await ctx.get_tree().physics_frame
		stray.issue_order(Order.for_target(derelict))
		var stray_frames := 0
		for i in SETTLE_FRAMES:
			if not is_instance_valid(stray) or stray.is_idle() or derelict.manned:
				break
			stray_frames = i
			await ctx.get_tree().physics_frame
		rig.check(not is_instance_valid(stray) or stray.is_idle() or derelict.manned,
			"robot held state %d for %d frames chasing unreachable hardware" % [
				stray.state if is_instance_valid(stray) else -1, stray_frames])
		if is_instance_valid(stray):
			stray.queue_free()
		if is_instance_valid(derelict):
			derelict.queue_free()

	GameSettings.auto_idle = idle_was
	rig.finish("garrison=%d" % fort.garrison.size())
