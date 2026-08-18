class_name RobotFactory
extends Building2D
## Robot factory: belongs to the team owning its zone. Builds from the
## robot-factory build list for its level (robots AND the smaller
## cannons, like the original) — production is queue-driven for the
## player and the CPU opponent alike, money- and cap-gated.


func kind_key() -> String:
	return "robot_factory"


func producer_key() -> String:
	return "robot_factory"


func produce_seconds() -> float:
	return 8.0 * build_time_mult()


func _process(delta: float) -> void:
	# factory belongs to whoever owns the zone it stands in
	var center := world_footprint().get_center()
	for z in MatchState.zones:
		if z.world_rect().has_point(center):
			owner_team = z.owner_team
			break
	if owner_team != team:
		team = owner_team
		update_flag(owner_team)
		queue.clear()  # a capture scraps the old owner's queue
	tick_production(delta)
