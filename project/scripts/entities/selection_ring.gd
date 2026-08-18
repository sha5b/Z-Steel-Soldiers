extends Node2D
## Selection ellipse + health bar, sized to the unit (robots are 16x16
## sprites at 2x; vehicles/cannons are wider). The HP bar uses the
## original `unit_amount_bar_<team>` art, revealed proportionally to
## remaining health (draw_texture_rect_region crops it) — falls back to
## plain rects when the art is missing.

const BAR_W := 31.0
const BAR_H := 8.0

var color := Color(0.4, 1.0, 0.4)
static var _bar_cache := {}  # team -> Texture2D


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
			var top := -20.0 if wide else -18.0
			var bar := _bar_for(int(unit.get("team")))
			if bar:
				# black backing, then the original bar cropped to health
				draw_rect(Rect2(-BAR_W / 2.0 - 1, top - 1, BAR_W + 2, BAR_H + 2),
					Color(0, 0, 0, 0.6))
				draw_texture_rect_region(bar,
					Rect2(-BAR_W / 2.0, top, BAR_W * frac, BAR_H),
					Rect2(0, 0, bar.get_width() * frac, bar.get_height()))
			else:
				draw_rect(Rect2(-BAR_W / 2.0, top, BAR_W, BAR_H), Color(0, 0, 0, 0.6))
				draw_rect(Rect2(-BAR_W / 2.0, top, BAR_W * frac, BAR_H),
					Color(0.2, 1.0, 0.2) if frac > 0.5 else Color(1.0, 0.5, 0.2))


static func _bar_for(team: int) -> Texture2D:
	if _bar_cache.has(team):
		return _bar_cache[team]
	var path := "res://assets/z/ui/hud/unit_amount_bar_%s.png" \
			% AnimLibrary.team_name(team)
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_bar_cache[team] = tex
	return tex
