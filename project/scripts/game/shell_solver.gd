class_name ShellSolver
extends Object
## Sim-side ballistics. Flight TIME and damage-on-arrival are simulation
## facts; they used to ride inside the visual Projectile (Fx.shell
## carried the damage callback in the sprite — presentation owned
## gameplay timing, so shots died with their sprites). Combat, grenades
## and fort garrison missiles all deliver through here; Fx.shell is now
## pure presentation flying the same arc over the same duration.


## One shot: fly the visual, land the damage after the real flight time
## (distance / projectile speed — dodgeable, Z-style, and scaled by
## Engine.time_scale exactly like the old _process flight).
static func deliver(shooter: Node2D, from: Vector2, to: Vector2,
		proj: ProjectileDef, on_arrival: Callable) -> void:
	Fx.shell(from, to, proj)
	var flight: float = from.distance_to(to) / maxf(proj.speed, 1.0)
	if shooter != null and is_instance_valid(shooter) and shooter.is_inside_tree():
		# process_always=false keeps the count paused with the match
		var timer: SceneTreeTimer = shooter.get_tree().create_timer(flight, false)
		timer.timeout.connect(on_arrival)
	else:
		on_arrival.call_deferred()
