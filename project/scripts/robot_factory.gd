class_name RobotFactory
extends Building2D
## Robot factory: belongs to the team owning its zone. Player factories
## produce the queue from the production panel; CPU factories
## auto-produce grunts when affordable.

const PRODUCE_SECONDS := 8.0
const COST := UnitData.ROBOTS.grunt.cost

var queue: Array[String] = []
var auto_mode := false
var _accum := 0.0


func kind_key() -> String:
	return "robot_factory"


## 0..1 progress of the item currently building (auto-mode included).
func progress() -> float:
	var building: bool = auto_mode or not queue.is_empty()
	return clampf(_accum / PRODUCE_SECONDS, 0.0, 1.0) if building and owner_team != 0 else 0.0


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
	if owner_team == 0:
		return
	_accum += delta
	if _accum < PRODUCE_SECONDS:
		return
	_accum = 0.0
	if auto_mode and owner_team != GameState.player_team:
		if GameState.money.get(owner_team, 0) >= COST and GameState.spend(owner_team, COST):
			_spawn("grunt")
	elif not queue.is_empty():
		_spawn(queue.pop_front())


func queue_unit(type_name: String) -> bool:
	var stats: Dictionary = UnitData.ROBOTS.get(type_name, {})
	if stats.is_empty():
		return false
	if not GameState.spend(owner_team, int(stats.cost)):
		return false
	queue.append(type_name)
	return true


func cancel_at(index: int) -> void:
	if index < 0 or index >= queue.size():
		return
	var type_name: String = queue.pop_front() if index == 0 else queue.pop_at(index)
	var stats: Dictionary = UnitData.ROBOTS.get(type_name, {})
	if not stats.is_empty() and owner_team != 0:
		GameState.money[owner_team] += int(stats.cost)
		GameState.money_changed.emit(owner_team, GameState.money[owner_team])


func _spawn(type_name: String) -> void:
	var unit: Unit2D = load("res://scenes/unit.tscn").instantiate()
	unit.unit_name = type_name
	unit.team = owner_team
	unit.position = global_position + Vector2(48, 40)
	var map := get_parent()
	if map is Node2D:
		map.add_child(unit)
