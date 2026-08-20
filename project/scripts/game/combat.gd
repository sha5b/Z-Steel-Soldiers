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
	# small arms scale with the TARGET (original zsettings: damage is a
	# fraction of the target's max HP — flat integers left robot armies
	# needing 30-45x too long to burn down a fort; explosives already
	# carry the original scale)
	if target is Building2D and def.building_frac > 0.0:
		amount = maxi(1, int(round(def.building_frac * (target as Building2D).max_hp)))
	# crate upgrades: grenades boost robots, rockets boost hardware
	if shooter is Unit2D:
		amount = maxi(1, int(round(amount * MatchState.current.damage_multiplier(
			(shooter as Unit2D).team, (shooter as Unit2D).kind))))
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
	if randf() > def.hit_chance:
		# missed: the shot flies past
		var past: Vector2 = aim \
				+ Vector2(randf_range(-16.0, 16.0), randf_range(-16.0, 16.0))
		if weapon == "laser":
			Fx.laser(muzzle, past)
		else:
			Fx.bullet(muzzle, past)
		return
	match weapon:
		"laser":
			Fx.laser(muzzle, aim)
			_land(target, amount, aim)
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
						area_damage(aim, splash, amount, shooter_team)
					else:
						var hit: Node2D = instance_from_id(tid) as Node2D
						if hit and hit.alive:
							_land(hit, amount, aim))
		_:
			Fx.bullet(muzzle, aim)
			_land(target, amount, aim)


## Explosion splash (zod ProcessMissileDamage): ONE damage roll per
## object with linear falloff — full at the impact point, zero at the
## rim; a direct hit + splash on top of it double-charged the primary.
## Hits every enemy unit and BUILDING around the impact (not just
## forts/bridges), and crumbles rocks the blast reaches. Friendly fire
## is off — the shooter's team is spared.
static func area_damage(world_pos: Vector2, radius: float, amount: int,
		shooter_team: int, crater := false) -> void:
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
	for b in Engine.get_main_loop().root.get_tree().get_nodes_in_group(Groups.ALL_BUILDINGS):
		if b is Node2D and b is Building2D and b.alive \
				and b.team != shooter_team:
			# distance to the RECT, not the centre — a shell bursting on
			# a big factory's wall must not measure to the building middle
			# (<= like the unit/rock probes)
			var fp: Rect2 = b.world_footprint()
			var cp := world_pos.clamp(fp.position, fp.position + fp.size)
			var d: float = cp.distance_to(world_pos)
			if d <= radius:
				b.take_damage(_falloff(amount, d, radius), cp)
	for rock in Engine.get_main_loop().root.get_tree().get_nodes_in_group(Groups.ROCKS):
		if rock is Node2D and rock.global_position.distance_to(world_pos) <= radius:
			NavWorld.current.clear_rock(rock.global_position)
			Fx.play("debris", rock.global_position)
			rock.queue_free()


## Deliver damage and tell a BUILDING where it was hit. Buildings render
## their ground platform in the same sprite as their walls, so they show
## a local spark at the impact point instead of tinting the whole image
## (see Building2D._hit_flash); units take the plain call.
static func _land(target: Node2D, amount: int, at: Vector2) -> void:
	if target is Building2D:
		(target as Building2D).take_damage(amount, at)
	else:
		target.take_damage(amount)


static func _falloff(amount: int, dist: float, radius: float) -> int:
	return maxi(int(round(amount * (1.0 - dist / radius))), 1)
