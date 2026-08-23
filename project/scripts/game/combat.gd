class_name Combat
extends Object
## Weapon resolution and damage rules — one implementation for robots,
## vehicles and cannons. The weapon behaviour comes from the UnitDef:
## `weapon` names it explicitly ("laser"); otherwise a projectile def
## means a travelling shell and everything else is a hitscan tracer.
## Visuals go through Fx (pure presentation); damage rules live here.

## Resolve the weapon behaviour for a def ("hitscan" | "laser" | "shell").
static func weapon_of(def: UnitDef) -> String:
	if def.weapon != "":
		return def.weapon
	return "shell" if def.projectile != null else "hitscan"


## Fire one shot at `target`. Applies the def's per-shot hit chance,
## plays the weapon's visuals via Fx and delivers damage — instantly for
## hitscan/laser, on arrival for shells (Z-style, dodgeable) with the
## def's splash radius around the impact.
static func fire(shooter: Node2D, def: UnitDef, muzzle: Vector2,
		target: Node2D, amount: int) -> void:
	# TWO SCALES, CONVERTED PER VICTIM — never up front.
	#
	# Unit HP runs 86..800; a fort has 33333. One number cannot serve
	# both, so a weapon carries a flat integer for units and
	# `building_frac` (a share of the target's max HP) for structures.
	# The conversion used to happen HERE, off the intended target, and
	# the resulting number was then handed to area_damage — which damages
	# units AND buildings in the blast. So the scale was decided by
	# whatever the shell was aimed at and then applied to everything it
	# actually hit: a shell aimed at a unit did unit-scale damage to the
	# factory it landed on, and (once explosives had a building_frac at
	# all) a shell aimed at a fort would have deleted every unit within
	# its blast radius with a five-figure number.
	#
	# So `amount` stays UNIT scale all the way down, `building_frac`
	# travels beside it, and each victim is charged on its own scale at
	# the point of impact. The shooter's multipliers fold into BOTH.
	var hit_chance := def.hit_chance
	var frac := def.building_frac
	if shooter is Unit2D:
		# crate upgrades: grenades boost robots, rockets boost hardware
		var mult: float = MatchState.current.damage_multiplier(
			(shooter as Unit2D).team, (shooter as Unit2D).kind) \
			* (shooter as Unit2D).veteran_damage_scale()
		amount = maxi(1, int(round(amount * mult)))
		frac *= mult
		# VETERANCY: rank pays in damage and in accuracy
		hit_chance = minf(1.0, hit_chance + (shooter as Unit2D).veteran_hit_bonus())
	Fx.gunfire(def.sound)
	Fx.play("muzzle", muzzle)
	var weapon := weapon_of(def)
	# building nodes sit at the art TOP/middle (Y-sort lift) — every
	# visual terminates at the building's visual centre, like shells
	var aim: Vector2 = (target.visual_center()
			if target is Building2D else target.global_position)
	# LEAD moving targets (original EstimateMissileTarget): project the
	# target's velocity over the approximate flight time — a fully-led
	# aim would land where they WILL be; the 0.8 factor keeps fast
	# units partially dodgeable, like the original felt
	if def.projectile != null and target is Unit2D:
		aim += (target as Unit2D).velocity \
				* (muzzle.distance_to(aim) / maxf(def.projectile.speed, 1.0)) * 0.8
	if randf() > hit_chance:
		# missed: the shot flies past
		var past: Vector2 = aim \
				+ Vector2(randf_range(-16.0, 16.0), randf_range(-16.0, 16.0))
		if weapon == "laser":
			Fx.laser(muzzle, past)
		else:
			Fx.bullet(muzzle, past)
		return
	var shooter_id := shooter.get_instance_id() if shooter != null else 0
	match weapon:
		"laser":
			Fx.laser(muzzle, aim)
			_land(target, amount_against(target, amount, frac), aim, shooter_id)
		"shell":
			var splash := def.splash_radius
			# capture ids, not nodes — the shooter and target may be
			# freed by the time the shell lands (lambdas capture by value)
			var shooter_team: int = shooter.team
			var tid := target.get_instance_id()
			ShellSolver.deliver(shooter, muzzle, aim, def.projectile,
				func():
					if splash > 0.0:
						Decals.crater(aim, splash > 36.0)
						area_damage(aim, splash, amount, shooter_team,
							false, frac)
					else:
						var hit: Node2D = instance_from_id(tid) as Node2D
						if hit and hit.alive:
							_land(hit, amount_against(hit, amount, frac),
								aim, shooter_id))
		_:
			Fx.bullet(muzzle, aim)
			_land(target, amount_against(target, amount, frac), aim, shooter_id)


## THE NUMBER THAT ACTUALLY LANDS ON THIS VICTIM. A building is charged
## `building_frac` of its own max HP; everything else takes the flat
## unit-scale amount. One definition, called at every point of impact —
## direct hit, shell arrival and splash all route through it, so the two
## scales can never be crossed again.
static func amount_against(target: Node2D, unit_amount: int,
		building_frac: float) -> int:
	if target is Building2D and building_frac > 0.0:
		return maxi(1, int(round(building_frac * (target as Building2D).max_hp)))
	return unit_amount


## Explosion splash (zod ProcessMissileDamage): ONE damage roll per
## object with linear falloff — full at the impact point, zero at the
## rim; a direct hit + splash on top of it double-charged the primary.
## Hits every enemy unit and BUILDING around the impact (not just
## forts/bridges), and crumbles rocks the blast reaches. Friendly fire
## is off — the shooter's team is spared.
## `building_frac` is the anti-structure scale of the weapon that fired
## (0 = none, charge buildings the flat amount like everything else).
static func area_damage(world_pos: Vector2, radius: float, amount: int,
		shooter_team: int, crater := false, building_frac := 0.0) -> void:
	if crater:
		Decals.crater(world_pos, radius > 36.0)
	# NEUTRAL objects are not immune. `team != 0` used to sit here on both
	# loops, and team 0 is exactly what unmanned hardware spawns as (and
	# what 230 of the 235 bridges on the shipped maps load as) — so empty
	# vehicles and cannons could not be destroyed at all, and the fully
	# implemented destructible-bridge path (_bridge_damage -> rubble
	# solids -> crane repair) was unreachable in play. AUTO-TARGETING
	# still ignores team 0 (units must not wander off to shoot derelicts
	# and neutral factories); explosions do not get to be that polite.
	for u in UnitRegistry.current.in_radius(world_pos, radius):
		if u.team != shooter_team:
			u.take_damage(_falloff(amount, u.global_position.distance_to(world_pos), radius))
	# distance measures to the footprint RECT, not the centre — a shell
	# bursting on a big factory's wall must not measure to the building
	# middle (BuildingRegistry.blast_targets owns that clamp)
	for hit in BuildingRegistry.blast_targets(world_pos, radius, shooter_team):
		var b: Building2D = hit.building
		var cp: Vector2 = hit.at
		b.take_damage(_falloff(amount_against(b, amount, building_frac),
			cp.distance_to(world_pos), radius), cp)
	for rock in Engine.get_main_loop().root.get_tree().get_nodes_in_group(Groups.ROCKS):
		if rock is Node2D and rock.global_position.distance_to(world_pos) <= radius:
			NavWorld.current.clear_rock(rock.global_position)
			Fx.rock_debris(rock.global_position)
			rock.queue_free()


## Deliver damage and tell a BUILDING where it was hit. Buildings render
## their ground platform in the same sprite as their walls, so they show
## a local spark at the impact point instead of tinting the whole image
## (see Building2D._hit_flash); units take the plain call.
## `shooter_id` is an INSTANCE ID, not a node: a shell can land after
## its shooter has been destroyed, and a freed node cannot be touched.
static func _land(target: Node2D, amount: int, at: Vector2,
		shooter_id := 0) -> void:
	var was_alive: bool = target.get("alive") == true
	if target is Building2D:
		(target as Building2D).take_damage(amount, at)
	else:
		target.take_damage(amount)
	# VETERANCY: whoever fired the killing shot gets the credit
	if not was_alive or shooter_id == 0 or target.get("alive") == true:
		return
	var shooter := instance_from_id(shooter_id)
	if shooter is Unit2D and (shooter as Unit2D).alive:
		(shooter as Unit2D).credit_kill()


static func _falloff(amount: int, dist: float, radius: float) -> int:
	return maxi(int(round(amount * (1.0 - dist / radius))), 1)
