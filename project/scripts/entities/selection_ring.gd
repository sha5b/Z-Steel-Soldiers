extends Node2D
## Selection ellipse + health bar, sized to the unit (robots are 16x16
## sprites at 2x; vehicles/cannons are wider).

const BAR_W := 30.0
const BAR_H := 3.5

var color := Color(0.4, 1.0, 0.4)


func _draw() -> void:
	var unit := get_parent()
	if unit == null:
		return
	var wide: bool = unit.get("kind") != null and unit.kind != "robot"
	var rx := 15.0 if wide else 11.0
	var ry := 9.0 if wide else 11.0
	var center := Vector2(0, 6)  # at the unit's feet
	if unit.get("selected"):
		draw_ellipse(center, rx, ry, color, false, 1.6)
	if unit.get("hp") != null and unit.get("max_hp") != null:
		var hp: int = unit.hp
		var max_hp: int = unit.max_hp
		if hp < max_hp:
			var frac := clampf(float(hp) / float(max_hp), 0.0, 1.0)
			var top := -16.0 if wide else -15.0
			draw_rect(Rect2(-BAR_W / 2.0, top, BAR_W, BAR_H), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(-BAR_W / 2.0, top, BAR_W * frac, BAR_H),
				Color(0.2, 1.0, 0.2) if frac > 0.5 else Color(1.0, 0.5, 0.2))
