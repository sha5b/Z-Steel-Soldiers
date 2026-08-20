class_name VehicleFactory
extends Building2D
## Vehicle factory: belongs to the team owning its zone, builds from the
## vehicle-factory build list for its level (vehicles and the heavier
## cannons) and delivers them unmanned (a robot must man them, Z-style).


func kind_key() -> String:
	return "vehicle_factory"


func producer_key() -> String:
	return "vehicle_factory"
