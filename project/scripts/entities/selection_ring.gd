extends Node2D
## Selection indicator + health bar, drawn the ORIGINAL way (zod
## ZObject::RenderSelection / RenderHealth): four team-coloured corner
## brackets around the sprite (5px arms, 1px thick, 3px padding) and a
## small procedural health bar — black 4px backing, 2px green for
## current HP, yellow for what was lost. The bar's WIDTH is absolute
## (vs the toughest thing on the field), so length itself tells
## toughness: a grunt shows a sliver, a fort spans the full 30px.

const HP_REF := 500.0   # fort HP = the 30px reference (zod MAX_UNIT_HEALTH)
const BAR_MAX_W := 30.0
const ARM := 5.0
const PAD := 3.0

# zod team_color[] (zteam.cpp)
const TEAM_COLORS := {
	0: Color("737373"), 1: Color("df0000"), 2: Color("1337fb"),
	3: Color("178f13"), 4: Color("cb632f"),
}


func _draw() -> void:
	var unit := get_parent()
	if unit == null:
		return
	if unit.get("selected"):
		_draw_brackets(unit)
	if unit.get("hp") != null and unit.get("max_hp") != null:
		if unit.hp < unit.max_hp:
			_draw_health(unit.hp, unit.max_hp, _is_wide(unit))


## Four corner brackets in the owner's team colour around the sprite
## rect (robots are 16px art at 2x; vehicles/cannons wider).
func _draw_brackets(unit: Node) -> void:
	var col: Color = TEAM_COLORS.get(int(unit.get("team")), Color.WHITE)
	var wide := _is_wide(unit)
	var w := 34.0 if wide else 24.0
	var h := 24.0 if wide else 32.0
	var r := Rect2(-w * 0.5, -h * 0.5 + 6.0, w, h)  # centred at the feet
	for corner in [r.position, Vector2(r.end.x, r.position.y),
			Vector2(r.position.x, r.end.y), r.end]:
		var dx := 1.0 if corner.x >= r.get_center().x else -1.0
		var dy := 1.0 if corner.y >= r.get_center().y else -1.0
		var base: Vector2 = corner + Vector2(PAD * dx, PAD * dy)
		draw_line(base, base + Vector2(ARM * dx, 0), col, 1.0)
		draw_line(base, base + Vector2(0, ARM * dy), col, 1.0)


## Procedural health bar above the sprite: black backing, green current
## HP, yellow lost HP (widths absolute vs HP_REF — zod RenderHealth).
func _draw_health(hp: int, max_hp: int, wide: bool) -> void:
	var green_w := maxf(BAR_MAX_W * clampf(float(hp) / HP_REF, 0.0, 1.0), 1.0)
	var yellow_w := maxf(BAR_MAX_W * clampf(float(max_hp) / HP_REF, 0.0, 1.0)
		- green_w, 0.0)
	var top := -20.0 if wide else -18.0
	var x := -BAR_MAX_W * 0.5 - 1.0
	draw_rect(Rect2(x - 1, top - 1, green_w + yellow_w + 2, 4),
		Color(0, 0, 0, 0.8))
	draw_rect(Rect2(x, top, green_w, 2), Color(0.32, 0.75, 0.13))
	if yellow_w > 0:
		draw_rect(Rect2(x + green_w, top, yellow_w, 2), Color(0.97, 0.80, 0.42))


static func _is_wide(unit: Node) -> bool:
	return unit.get("kind") != null and unit.kind != "robot"
