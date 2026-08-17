class_name VehicleFactory
extends Building2D
## Vehicle factory: belongs to the zone owner, builds queued vehicles and
## delivers them unmanned (a robot must man them, Z-style).

const PRODUCE_SECONDS := 10.0

var queue: Array[String] = []
var _accum := 0.0


func kind_key() -> String:
	return "vehicle_factory"


func _process(delta: float) -> void:
	var center := world_footprint().get_center()
	for z in GameState.zones:
		if z.world_rect().has_point(center):
			owner_team = z.owner_team
			break
	if owner_team != team:
		team = owner_team
		update_flag(owner_team)
	if owner_team == 0:
		return
	_accum += delta
	if _accum < PRODUCE_SECONDS or queue.is_empty():
		return
	_accum = 0.0
	_spawn(queue.pop_front())


func queue_unit(type_name: String) -> bool:
	var stats: Dictionary = UnitData.VEHICLES.get(type_name, {})
	if stats.is_empty():
		return false
	if not GameState.spend(owner_team, int(stats.cost)):
		return false
	queue.append(type_name)
	return true


func _spawn(type_name: String) -> void:
	if not Vehicle2D.dir_exists("vehicle", type_name):
		return
	var vehicle: Vehicle2D = load("res://scenes/vehicle.tscn").instantiate()
	vehicle.setup_vehicle("vehicle", type_name, 0)  # spawns unmanned
	vehicle.position = global_position + Vector2(48, 40)
	var map := get_parent()
	if map is Node2D:
		map.add_child(vehicle)
