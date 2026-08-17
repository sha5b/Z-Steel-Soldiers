class_name FortBuilding
extends ColorRect
## Fort (win/lose objective). Damageable by enemy units; when destroyed the
## game ends. Recolors with its zone owner like factories do — but a fort
## only changes hands by destruction in Z, so team is fixed at spawn.

const TEAM_COLORS := {
	1: Color(0.75, 0.35, 0.25), 2: Color(0.35, 0.45, 0.8),
	3: Color(0.35, 0.7, 0.35), 4: Color(0.8, 0.75, 0.3),
}

var team := 0
var alive := true
var hp := 500
var max_hp := 500
var hp_bar: ColorRect


func setup(building_team: int) -> void:
	team = building_team


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _ready() -> void:
	color = TEAM_COLORS.get(team, Color(0.5, 0.5, 0.5))
	hp_bar = ColorRect.new()
	hp_bar.mouse_filter = MOUSE_FILTER_IGNORE
	hp_bar.color = Color(0.2, 1.0, 0.2)
	add_child(hp_bar)
	add_to_group("buildings")
	_update_bar()


func _update_bar() -> void:
	hp_bar.position = Vector2(0, -6)
	hp_bar.size = Vector2(size.x * clampf(float(hp) / float(max_hp), 0.0, 1.0), 3)


func take_damage(amount: int) -> void:
	if not alive:
		return
	hp -= amount
	_update_bar()
	if hp <= 0:
		alive = false
		remove_from_group("buildings")
		color = Color(0.25, 0.25, 0.25)
		hp_bar.visible = false
		GameState.report_fort_destroyed(team)
