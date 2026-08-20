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
	Fx.gunfire(def.sound)
	Fx.play("muzzle", muzzle)
	var weapon := weapon_of(def)
	# building nodes sit at the art TOP/middle (Y-sort lift) — every
	# visual terminates at the building's visual centre, like shells
	var aim: Vector2 = (target.visual_center()
			if target is Building2D else target.global_position)
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
			target.take_damage(amount)
		"shell":
			var splash := def.splash_radius
			# capture ids, not nodes — the shooter and target may be
			# freed by the time the shell lands (lambdas capture by value)
			var shooter_team: int = shooter.team
			var tid := target.get_instance_id()
			Fx.shell(muzzle, aim, def.projectile,
				func():
					if splash > 0.0:
						Decals.crater(aim, splash > 36.0)
						area_damage(aim, splash, amount, shooter_team)
					else:
						var hit: Node2D = instance_from_id(tid) as Node2D
						if hit and hit.alive:
							hit.take_damage(amount))
		_:
			Fx.bullet(muzzle, aim)
			target.take_damage(amount)


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
	for u in UnitRegistry.current.in_radius(world_pos, radius):
		if u.team != shooter_team and u.team != 0:
			u.take_damage(_falloff(amount, u.global_position.distance_to(world_pos), radius))
	for b in Engine.get_main_loop().root.get_tree().get_nodes_in_group(Groups.ALL_BUILDINGS):
		if b is Node2D and b is Building2D and b.alive \
				and b.team != shooter_team and b.team != 0:
			# distance to the RECT, not the centre — a shell bursting on
			# a big factory's wall must not measure to the building middle
			# (<= like the unit/rock probes)
			var fp: Rect2 = b.world_footprint()
			var cp := world_pos.clamp(fp.position, fp.position + fp.size)
			var d: float = cp.distance_to(world_pos)
			if d <= radius:
				b.take_damage(_falloff(amount, d, radius))
	for rock in Engine.get_main_loop().root.get_tree().get_nodes_in_group(Groups.ROCKS):
		if rock is Node2D and rock.global_position.distance_to(world_pos) <= radius:
			var cell := Vector2i(((rock.global_position - Vector2(8, 8)) / 16.0).floor())
			if NavWorld.current.nav_grid and NavWorld.current.nav_grid.is_point_solid(cell):
				NavWorld.current.nav_grid.set_point_solid(cell, false)
			if NavWorld.current.vehicle_grid and NavWorld.current.vehicle_grid.is_point_solid(cell):
				NavWorld.current.vehicle_grid.set_point_solid(cell, false)
			Fx.play("debris", rock.global_position)
			rock.queue_free()


static func _falloff(amount: int, dist: float, radius: float) -> int:
	return maxi(int(round(amount * (1.0 - dist / radius))), 1)
