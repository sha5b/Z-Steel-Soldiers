extends Node2D
## Selection ellipse + health bar for a unit (draws each frame the unit
## asks it to, or when selected).

const BAR_W := 20.0
const BAR_H := 3.0

var color := Color(0.4, 1.0, 0.4)


func _draw() -> void:
	var unit := get_parent()
	if unit and unit.get("selected"):
		draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 24, color, 1.5)
	if unit and unit.get("hp") != null and unit.get("max_hp") != null:
		var hp: int = unit.hp
		var max_hp: int = unit.max_hp
		if hp < max_hp:
			var frac := clampf(float(hp) / float(max_hp), 0.0, 1.0)
			var top := -14.0
			draw_rect(Rect2(-BAR_W / 2.0, top, BAR_W, BAR_H), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(-BAR_W / 2.0, top, BAR_W * frac, BAR_H),
				Color(0.2, 1.0, 0.2) if frac > 0.5 else Color(1.0, 0.5, 0.2))
