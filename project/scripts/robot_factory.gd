class_name RobotFactory
extends ColorRect
## Robot factory building: belongs to the team owning its zone, spends
## that team's money to produce grunts at its doorstep.

const PRODUCE_SECONDS := 8.0
const COST := UnitData.ROBOTS.grunt.cost

var owner_team := 0
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
	if GameState.money.get(owner_team, 0) >= COST and GameState.spend(owner_team, COST):
		_spawn_grunt()


func _spawn_grunt() -> void:
	var unit: Unit2D = load("res://scenes/unit.tscn").instantiate()
	unit.unit_name = "grunt"
	unit.team = owner_team
	unit.position = position + size + Vector2(16, 8)
	var map := get_parent()
	if map is Node2D:
		map.add_child(unit)
