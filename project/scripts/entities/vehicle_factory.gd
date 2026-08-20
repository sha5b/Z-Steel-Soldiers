class_name VehicleFactory
extends Building2D
## Vehicle factory: belongs to the team owning its zone, builds from the
## vehicle-factory build list for its level (vehicles and the heavier
## cannons) and delivers them unmanned (a robot must man them, Z-style).


func kind_key() -> String:
	return "vehicle_factory"


func producer_key() -> String:
	return "vehicle_factory"




func _process(delta: float) -> void:
	if not alive:
		return  # a ruin produces nothing
	var center := world_footprint().get_center()
	for z in MatchState.current.zones:
		if z.world_rect().has_point(center):
			owner_team = z.owner_team
			break
	if owner_team != team:
		team = owner_team
		update_flag(owner_team)
		_refund_queue()
		queue.clear()  # a capture scraps the old owner's queue
	tick_production(delta)
