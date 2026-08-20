class_name PlacementTests
extends Object
## Placement domain of the headless harness: every position TELEPORT
## (dodge sidestep, APC unload, driver ejection) and real-physics walk
## must leave bodies outside solid cells and building walls. Runs with
## REAL physics frames (direct_step off, awaiting physics_frame) — the
## rest of the suite bypasses move_and_slide, which is exactly why the
## wedge-inside-building bug class was invisible to it.


## All checks share one predicate: the body box of the unit sits on
## open cells of its own grid.
static func _clear(u: Unit2D) -> bool:
	return NavWorld.body_clear(u.global_position,
		NavWorld.BODY_HALF.get(u.kind, 7.0), u.kind)


static func run(ctx: Node, rig: TestRig) -> void:
	TestLevers.direct_step = false  # real move_and_slide this block
	# fixture: a vehicle factory (5x5 solid art) on open ground near the
	# map's second zone — same spot the factory tests use
	var vf := VehicleFactory.new()
	var z: Node2D = MatchState.zones[1]
	vf.position = z.position + z.world_rect().get_center() - Vector2(24, 24)
	ctx.add_child(vf)
	await ctx.get_tree().physics_frame  # _ready paints walls + solids
	var wall := vf.world_footprint()
	# a hugging spot right against the factory's south wall
	var hug := Vector2(wall.get_center().x, wall.end.y + 9.0)

	# 1. dodge beside a wall: a robot taking solid hits next to the
	# factory must always scramble somewhere its whole box fits
	var bot: Unit2D = Spawner.spawn(ctx, "robot", "tough", 1,
		NavWorld.find_free_spot(hug, "robot")) as Unit2D
	bot.hp = 1000000
	for i in 40:
		bot.take_damage(600)  # above the ratio-dodge threshold every hit
		await ctx.get_tree().physics_frame
	rig.check(_clear(bot), "dodge teleported robot into the wall")
	bot.queue_free()

	# 2. APC unload beside a wall: all cargo boxes must land clear
	var apc: Vehicle2D = Spawner.spawn(ctx, "vehicle", "apc", 1,
		Vector2(hug.x + 30.0, hug.y), true) as Vehicle2D
	for i in 3:
		var rider: Unit2D = Spawner.spawn(ctx, "robot", "grunt", 1,
			apc.global_position) as Unit2D
		apc.load_robot(rider)
	apc.global_position = hug
	apc.unload()
	await ctx.get_tree().physics_frame
	for c in ctx.get_children():
		if c is Unit2D and c.unit_name == "grunt" \
				and c.global_position.distance_to(hug) < 80.0:
			rig.check(_clear(c), "APC cargo unloaded into the wall")
			c.queue_free()
	apc.queue_free()

	# 3. sniper ejection beside a wall: the survivor bails to a clear box
	var jeep: Vehicle2D = Spawner.spawn(ctx, "vehicle", "jeep", 1,
		hug, true) as Vehicle2D
	jeep.driver_type = "grunt"  # guarantee a survivor spawns
	jeep.eject_driver()
	await ctx.get_tree().physics_frame
	for c in ctx.get_children():
		if c is Unit2D and c.unit_name == "grunt" \
				and c.global_position.distance_to(hug) < 60.0:
			rig.check(_clear(c), "ejected driver landed inside the wall")
			c.queue_free()
	jeep.queue_free()

	# 4. real-physics walk past the factory: the walker's CENTER must
	# never sit in a solid cell (physics walls stop real penetration —
	# brushing a wall at contact distance is legal sliding) and it must
	# arrive: wedging into a corner pocket forever was the reported bug
	var walker: Unit2D = Spawner.spawn(ctx, "robot", "grunt", 1,
		NavWorld.find_free_spot(
			Vector2(wall.position.x - 30.0, wall.get_center().y), "robot")) as Unit2D
	walker.move_to(NavWorld.find_free_spot(
		Vector2(wall.end.x + 30.0, wall.get_center().y), "robot"))
	var samples := 0
	var bad := 0
	var first_bad := Vector2.ZERO
	var rgrid := NavWorld.nav_grid
	for i in 600:
		await ctx.get_tree().physics_frame
		if i % 5 == 0:
			samples += 1
			var cell := Vector2i((walker.global_position / 16.0).floor())
			if rgrid.region.has_point(cell) and rgrid.is_point_solid(cell):
				bad += 1
				if first_bad == Vector2.ZERO:
					first_bad = walker.global_position
		if walker.move_target == Vector2.ZERO:
			break
	rig.check(bad == 0, "physics walker center entered solids %d/%d samples, first at %s" % [
		bad, samples, first_bad])
	rig.check(walker.move_target == Vector2.ZERO, "physics walker never arrived (stuck at %s)" % [
		walker.global_position])
	walker.queue_free()
	TestLevers.direct_step = true  # restore the harness default
	rig.finish("samples=%d bad=%d" % [samples, bad])
