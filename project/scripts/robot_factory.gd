class_name RobotFactory
extends ColorRect
## Robot factory: belongs to the team owning its zone. Player factories
## produce whatever is queued from the production panel; CPU factories
## auto-produce grunts when affordable.

const PRODUCE_SECONDS := 8.0
const COST := UnitData.ROBOTS.grunt.cost

var owner_team := 0
var queue: Array[String] = []
var auto_mode := false
var selected := false
var _accum := 0.0


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	color = Color(0.6, 0.6, 0.35)


func _process(delta: float) -> void:
	# factory belongs to whoever owns the zone it stands in
	for z in GameState.zones:
		if z.world_rect().has_point(global_position + size * 0.5):
			owner_team = z.owner_team
			break
	if owner_team == 0:
		color = Color(0.45, 0.45, 0.45)
		return
	color = Color(0.6, 0.6, 0.35) if owner_team == 1 else Color(0.45, 0.5, 0.65)
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


func set_selected(value: bool) -> void:
	selected = value
	color = Color(0.85, 0.8, 0.4) if value and owner_team == GameState.player_team else \
		(Color(0.6, 0.6, 0.35) if owner_team == 1 else Color(0.45, 0.5, 0.65))


func _spawn(type_name: String) -> void:
	var unit: Unit2D = load("res://scenes/unit.tscn").instantiate()
	unit.unit_name = type_name
	unit.team = owner_team
	unit.position = position + size + Vector2(16, 8)
	var map := get_parent()
	if map is Node2D:
		map.add_child(unit)
