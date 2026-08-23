class_name DamageTests
extends Object
## Damage-model domain of the headless harness: can every armed unit in
## the roster actually hurt a BUILDING?
##
## The `--fortkill-test` lane already asserts the numbers (`building_frac`
## is set, and the seconds-to-raze band is sane). This asserts the whole
## chain END TO END, per unit type, with real frames — because the
## numbers being right is not the same as the shot arriving:
##
##   acquire the building as a target  (Unit2D._find_target_within ->
##                                      BuildingRegistry.nearest_enemy)
##   get in range of it                (reach_point -> the footprint
##                                      edge, not the centre)
##   fire                              (Combat.fire -> weapon_of)
##   the shell FLIES                   (ShellSolver, a SceneTreeTimer —
##                                      which is exactly why this needs
##                                      real frames and not a hand-
##                                      stepped _process loop)
##   land on the building's own scale  (Combat.amount_against)
##
## Every explosive weapon in the game used to fail the last step: with no
## `building_frac` a tank shell charged a 33333 HP fort its flat 267, so
## a medium tank needed five minutes to raze one alone while a pyro robot
## did it in fourteen seconds.

## Frames to give one unit to land its first hit. The slowest weapon on
## the roster reloads in 4.86s (howitzer) and the slowest shell flies at
## 70px/s (missile launcher), so this is generous by design — a unit that
## cannot hurt a building at all is what we are looking for, not a slow
## one.
const SHOT_FRAMES := 420


static func every_armed_unit_hurts_a_building(ctx: Node, rig: TestRig) -> void:
	var levers_was: bool = TestLevers.direct_step
	var idle_was: bool = GameSettings.auto_idle
	TestLevers.direct_step = false  # real frames: shells fly on a tree timer
	GameSettings.auto_idle = false
	GameState.over = true           # the map's own war must not interfere
	var fort := FortBuilding.new()
	fort.setup(0, 2, "desert")
	fort.position = Vector2(400, 1600)
	ctx.add_child(fort)
	await ctx.get_tree().physics_frame
	fort.apply_footprint()
	var fp := fort.world_footprint()
	var rows: Array[String] = []
	var silent: Array[String] = []
	for kind in ["robot", "vehicle", "cannon"]:
		for name in ContentDB.buildable(kind):
			var def := ContentDB.def_for(kind, String(name))
			if def.damage <= 0:
				continue  # cranes and APCs carry no weapon at all
			var landed := await _one_shooter(ctx, fort, fp, kind, String(name), def)
			if landed <= 0:
				silent.append("%s:%s" % [kind, name])
			else:
				rows.append("%s %d" % [name, landed])
	rig.check(silent.is_empty(),
		"%d armed unit(s) could not damage a fort at all: %s"
		% [silent.size(), ", ".join(silent)])
	fort.queue_free()
	TestLevers.direct_step = levers_was
	GameSettings.auto_idle = idle_was
	print("DAMAGE first-hit: %s" % ", ".join(rows))


## Put ONE shooter just inside its own weapon range of the fort's wall,
## order it onto the fort, and return the damage its first hit did. The
## fort is topped back up every frame: inflating max_hp instead would not
## work, because building damage is a FRACTION of max HP, so a bigger
## fort simply takes bigger hits.
static func _one_shooter(ctx: Node, fort: FortBuilding, fp: Rect2,
		kind: String, name: String, def: UnitDef) -> int:
	# stand off the south wall at 60% of the weapon's reach
	var standoff: float = maxf(def.range_px * 0.6, 24.0)
	var want := Vector2(fp.get_center().x, fp.end.y + standoff)
	var at := NavWorld.current.find_free_spot(want,
		"robot" if kind == "robot" else "vehicle")
	if at == Vector2.INF:
		at = want
	var u: Unit2D = Spawner.spawn(ctx, kind, name, 1, at, true) as Unit2D
	if u == null:
		return -1
	u.hp = 100000000
	u.max_hp = 100000000
	u.grenades = 0  # the RIFLE has to work, not the throwable
	await ctx.get_tree().physics_frame
	u.issue_order(Order.attack(fort))
	var before: int = fort.hp
	var landed := 0
	for i in SHOT_FRAMES:
		await ctx.get_tree().physics_frame
		if fort.hp < before:
			landed = before - fort.hp
			fort.hp = fort.max_hp  # see above: hold it up, count the hit
			break
	if is_instance_valid(u):
		u.queue_free()
	fort.hp = fort.max_hp
	return landed
