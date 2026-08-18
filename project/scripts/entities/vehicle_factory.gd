class_name VehicleFactory
extends Building2D
## Vehicle factory: belongs to the zone owner, builds queued vehicles and
## delivers them unmanned (a robot must man them, Z-style).

const PRODUCE_SECONDS := 10.0

var queue := ProductionQueue.new()


func kind_key() -> String:
	return "vehicle_factory"


func queue_items() -> Array[String]:
	return queue.items


## 0..1 progress of the item currently building.
func progress() -> float:
	if owner_team == 0:
		return 0.0
	return queue.progress(PRODUCE_SECONDS)


func _process(delta: float) -> void:
	var center := world_footprint().get_center()
	for z in GameState.zones:
		if z.world_rect().has_point(center):
			owner_team = z.owner_team
			break
	if owner_team != team:
		team = owner_team
		update_flag(owner_team)
		queue.clear()  # a capture scraps the old owner's queue
	if owner_team == 0:
		return
	var done := queue.tick(delta, PRODUCE_SECONDS)
	if done != "":
		_spawn(done)


func queue_unit(type_name: String) -> bool:
	if not ContentDB.has_unit("vehicle", type_name) \
			or not ContentDB.has_sprites("vehicle", type_name):
		return false
	var stats: Dictionary = ContentDB.def_for("vehicle", type_name)
	if not _pop_allows(stats):
		return false
	if not GameState.spend(owner_team, int(stats.cost)):
		return false
	if not queue.enqueue(type_name):
		GameState.money[owner_team] += int(stats.cost)  # queue full: refund
		GameState.money_changed.emit(owner_team, GameState.money[owner_team])
		return false
	return true


func cancel_at(index: int) -> void:
	var type_name := queue.cancel_at(index)
	if type_name == "" or owner_team == 0:
		return
	var stats: Dictionary = ContentDB.def_for("vehicle", type_name)
	GameState.money[owner_team] += int(stats.cost)
	GameState.money_changed.emit(owner_team, GameState.money[owner_team])


## Cap gate: alive + queued + this unit must fit under the team cap.
func _pop_allows(stats: Dictionary) -> bool:
	var team_id := team if team != 0 else owner_team
	var queued := 0
	for item in queue.items:
		queued += int(ContentDB.def_for("robot" if kind_key() == "robot_factory" else "vehicle", item).get("pop", 1))
	var cost := int(stats.get("pop", 1))
	if GameState.unit_pop(team_id) + queued + cost > GameState.unit_cap(team_id):
		Fx.cap_denied()
		return false
	return true


func _spawn(type_name: String) -> void:
	if not ContentDB.has_sprites("vehicle", type_name):
		return
	var vehicle: Vehicle2D = load("res://scenes/vehicle.tscn").instantiate()
	vehicle.setup_vehicle("vehicle", type_name, 0)  # spawns unmanned
	vehicle.position = global_position + Vector2(48, 40)
	var map := get_parent()
	if map is Node2D:
		map.add_child(vehicle)
