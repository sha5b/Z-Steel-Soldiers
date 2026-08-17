class_name FortBuilding
extends Building2D
## Fort — the win/lose objective. Also produces robots like the original
## (select your fort to open the production panel). All damage/objective
## behaviour lives in Building2D.

const PRODUCE_SECONDS := 8.0

var queue: Array[String] = []
var _accum := 0.0


func kind_key() -> String:
	return "robot_factory"


func _process(delta: float) -> void:
	# production tick (forts keep their fixed team — no zone following)
	if team == 0 or GameState.over:
		return
	_accum += delta
	if _accum < PRODUCE_SECONDS or queue.is_empty():
		return
	_accum = 0.0
	_spawn(queue.pop_front())


## 0..1 progress of the item currently building.
func progress() -> float:
	if queue.is_empty() or team == 0:
		return 0.0
	return clampf(_accum / PRODUCE_SECONDS, 0.0, 1.0)


func queue_unit(type_name: String) -> bool:
	var stats: Dictionary = UnitData.ROBOTS.get(type_name, {})
	if stats.is_empty():
		return false
	if not GameState.spend(team, int(stats.cost)):
		return false
	queue.append(type_name)
	return true


func cancel_at(index: int) -> void:
	if index < 0 or index >= queue.size():
		return
	var type_name: String = queue.pop_front() if index == 0 else queue.pop_at(index)
	var stats: Dictionary = UnitData.ROBOTS.get(type_name, {})
	if not stats.is_empty() and team != 0:
		GameState.money[team] += int(stats.cost)
		GameState.money_changed.emit(team, GameState.money[team])


func _spawn(type_name: String) -> void:
	var unit: Unit2D = load("res://scenes/unit.tscn").instantiate()
	unit.unit_name = type_name
	unit.team = team
	unit.position = position + Vector2(48, 64)
	var map := get_parent()
	if map is Node2D:
		map.add_child(unit)
