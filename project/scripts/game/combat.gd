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
	Fx.gunfire(def.sound)
	Fx.play("muzzle", muzzle)
	var weapon := weapon_of(def)
	if randf() > def.hit_chance:
		# missed: the shot flies past
		var past: Vector2 = target.global_position \
				+ Vector2(randf_range(-16.0, 16.0), randf_range(-16.0, 16.0))
		if weapon == "laser":
			Fx.laser(muzzle, past)
		else:
			Fx.bullet(muzzle, past)
		return
	match weapon:
		"laser":
			Fx.laser(muzzle, target.global_position)
			target.take_damage(amount)
		"shell":
			var tid := target.get_instance_id()
			var impact: Vector2 = target.global_position
			var splash := def.splash_radius
			# capture the team, not the shooter — the shooter may be
			# freed by the time the shell lands (lambdas capture by value)
			var shooter_team: int = shooter.team
			Fx.shell(muzzle, impact, def.projectile,
				func():
					var hit: Node2D = instance_from_id(tid) as Node2D
					if hit and hit.alive:
						hit.take_damage(amount)
					if splash > 0.0:
						Decals.crater(impact, splash > 36.0)
						area_damage(impact, splash, int(amount * 0.5),
							shooter_team))
		_:
			Fx.bullet(muzzle, target.global_position)
			target.take_damage(amount)


## Explosion splash (original damage_missile with radius): hits every
## enemy unit and fort/bridge around the impact, and crumbles rocks the
## blast reaches. Friendly fire is off — the shooter's team is spared.
static func area_damage(world_pos: Vector2, radius: float, amount: int,
		shooter_team: int, crater := false) -> void:
	if crater:
		Decals.crater(world_pos, radius > 36.0)
	var r2 := radius * radius
	for u in UnitRegistry.in_radius(world_pos, radius):
		if u.team != shooter_team and u.team != 0:
			u.take_damage(amount)
	for b in Engine.get_main_loop().root.get_tree().get_nodes_in_group("buildings"):
		if b is Node2D and b is Building2D and b.alive \
				and (b.is_bridge() or (b.is_fort and b.team != shooter_team and b.team != 0)):
			if b.world_footprint().get_center().distance_squared_to(world_pos) <= r2:
				b.take_damage(amount)
	for rock in Engine.get_main_loop().root.get_tree().get_nodes_in_group("rocks"):
		if rock is Node2D and rock.global_position.distance_squared_to(world_pos) <= r2:
			var cell := Vector2i(((rock.global_position - Vector2(8, 8)) / 16.0).floor())
			if NavWorld.nav_grid and NavWorld.nav_grid.is_point_solid(cell):
				NavWorld.nav_grid.set_point_solid(cell, false)
			if NavWorld.vehicle_grid and NavWorld.vehicle_grid.is_point_solid(cell):
				NavWorld.vehicle_grid.set_point_solid(cell, false)
			Fx.play("debris", rock.global_position)
			rock.queue_free()
