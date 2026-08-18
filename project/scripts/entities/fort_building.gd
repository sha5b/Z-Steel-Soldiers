class_name FortBuilding
extends Building2D
## Fort — the win/lose objective. Also produces robots like the original
## (select your fort to open the production panel). All damage/objective
## behaviour lives in Building2D.

const PRODUCE_SECONDS := 8.0

var queue := ProductionQueue.new()


func kind_key() -> String:
	return "robot_factory"


func queue_items() -> Array[String]:
	return queue.items


func _process(delta: float) -> void:
	# production tick (forts keep their fixed team — no zone following)
	if team == 0 or GameState.over:
		return
	var done := queue.tick(delta, PRODUCE_SECONDS)
	if done != "":
		_spawn(done)


## 0..1 progress of the item currently building.
func progress() -> float:
	if team == 0:
		return 0.0
	return queue.progress(PRODUCE_SECONDS)


func queue_unit(type_name: String) -> bool:
	if not ContentDB.has_unit("robot", type_name):
		return false
	var stats: Dictionary = ContentDB.def_for("robot", type_name)
	if not _pop_allows(stats):
		return false
	if not GameState.spend(team, int(stats.cost)):
		return false
	if not queue.enqueue(type_name):
		GameState.money[team] += int(stats.cost)  # queue full: refund
		GameState.money_changed.emit(team, GameState.money[team])
		return false
	return true


func cancel_at(index: int) -> void:
	var type_name := queue.cancel_at(index)
	if type_name == "" or team == 0:
		return
	var stats: Dictionary = ContentDB.def_for("robot", type_name)
	GameState.money[team] += int(stats.cost)
	GameState.money_changed.emit(team, GameState.money[team])


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
	unit.team = team
	unit.position = position + Vector2(48, 64)
	var map := get_parent()
	if map is Node2D:
		map.add_child(unit)
	if rally_point != Vector2.INF:
		unit.move_to(rally_point)
