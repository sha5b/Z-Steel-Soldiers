class_name RobotFactory
extends Building2D
## Robot factory: belongs to the team owning its zone. Player factories
## produce the queue from the production panel; CPU factories
## auto-produce grunts when affordable.

const PRODUCE_SECONDS := 8.0

var queue := ProductionQueue.new()


func kind_key() -> String:
	return "robot_factory"


func queue_items() -> Array[String]:
	return queue.items


## CPU teams auto-produce; the player uses the queued production panel.
func _auto() -> bool:
	return owner_team != 0 and owner_team != GameState.player_team


## 0..1 progress of the item currently building (auto-mode included).
func progress() -> float:
	if owner_team == 0 or not (_auto() or not queue.items.is_empty()):
		return 0.0
	return queue.progress(PRODUCE_SECONDS)


func _process(delta: float) -> void:
	# factory belongs to whoever owns the zone it stands in
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
	if _auto() and queue.items.is_empty() and _affordable_grunt():
		GameState.spend(owner_team, _grunt_cost())
		queue.enqueue("grunt")
	var done := queue.tick(delta, PRODUCE_SECONDS)
	if done != "":
		_spawn(done)


func queue_unit(type_name: String) -> bool:
	if not ContentDB.has_unit("robot", type_name):
		return false
	var stats: Dictionary = ContentDB.def_for("robot", type_name)
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
	var stats: Dictionary = ContentDB.def_for("robot", type_name)
	GameState.money[owner_team] += int(stats.cost)
	GameState.money_changed.emit(owner_team, GameState.money[owner_team])


func _grunt_cost() -> int:
	return int(ContentDB.def_for("robot", "grunt").cost)


func _affordable_grunt() -> bool:
	return GameState.money.get(owner_team, 0) >= _grunt_cost()


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
	var unit: Unit2D = load("res://scenes/unit.tscn").instantiate()
	unit.unit_name = type_name
	unit.team = owner_team
	unit.position = global_position + Vector2(48, 40)
	var map := get_parent()
	if map is Node2D:
		map.add_child(unit)
