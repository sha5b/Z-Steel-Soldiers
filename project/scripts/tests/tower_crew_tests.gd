class_name TowerCrewTests
extends Object
## Hardware-boarding domain of the headless harness: ordering a robot
## onto a gun that stands somewhere no robot can normally walk.
##
## This file used to also cover the fort GARRISON — robots ordered onto
## their own fort walked in through the gate and crewed a missile battery
## from inside. That whole feature is gone: a unit inside a building
## cannot be seen, selected or counted, so nothing enters a BUILDING any
## more and a fort defends itself with its tower guns. What is left here
## is the part that was never about entering a building at all:
##
##  1. re-crewing a fort TOWER GUN. Tower mounts sit on SOLID cells, so
##     no robot can ever reach contact distance; boarding has to resolve
##     from arm's length once the walk is over.
##  2. hardware that is genuinely unreachable must leave the robot IDLE
##     and retaskable, never parked in ENTERING for the whole match.
##
## Runs with REAL physics (direct_step off) because the bug class lives
## in the interaction between move_and_slide and the nav grid.
##
## Wait loops are written out INLINE on purpose: an `await` helper
## coroutine called from a static func does not resume here, so each loop
## awaits directly (same shape as placement_tests.gd).

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
		print("TOWERCREW: no player fort on this map (skipped)")
		GameSettings.auto_idle = idle_was
		rig.finish()
		return
	var team: int = fort.team
	var footprint := fort.world_footprint()

	# ---- 1. re-crew a tower gun whose driver was sniped -------------
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
			crew_spot if crew_spot != Vector2.INF else footprint.get_center()) as Unit2D
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

	# ---- 2. unreachable hardware must not park a robot forever -----
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
	rig.finish()
