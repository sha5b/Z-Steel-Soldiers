extends Node2D
## Selection indicator + health bar, drawn the ORIGINAL way (zod
## ZObject::RenderSelection -> zsdl draw_selection_box): four
## team-coloured corner brackets around the unit's CONTENT (the art's
## opaque pixels — framing the raw sprite canvas left big transparent
## margins that made brackets tower over robots), 5px arms lying ON the
## padded box edge, 1px thick, 3px padding. All native art scale. Health bar: black 4px
## backing, 2px green for current HP, yellow for what was lost. The
## bar's WIDTH is absolute (vs the toughest thing on the field), so
## length itself tells toughness: a grunt shows a sliver, a fort spans
## the full 30px.

const HP_REF := 800.0   # toughest field unit (crane) = the full 30px
# reference — absolute widths so length tells toughness (zod convention,
# rescaled to the original-balance HP table: the old 500 was the PRE-
# rebalance fort HP and pinned heavy/crane bars full forever)
const BAR_MAX_W := 30.0
const ARM := 5.0
const PAD := 3.0

# zod team_color[] (zteam.cpp)
const TEAM_COLORS := {
	0: Color("737373"), 1: Color("df0000"), 2: Color("1337fb"),
	3: Color("178f13"), 4: Color("cb632f"),
}

static var _content_cache := {}  # texture instance id -> alpha bbox Rect2


func _draw() -> void:
	var unit := get_parent()
	if unit == null:
		return
	if unit.get("selected"):
		_draw_brackets(unit)
		_draw_rank(unit)
		_draw_attack_radius(unit)


func _process(delta: float) -> void:
	# the range dots crawl one slot per second (zod radius_i += PI_shift
	# * time_dif) — redraw comes free, the unit already queues it
	_phase = fmod(_phase + PHASE_STEP * delta, PHASE_STEP)


## THE ATTACK RANGE, SHOWN THE ORIGINAL WAY (zod ZObject::
## RenderAttackRadius, drawn for every SELECTED unit): a dotted circle
## in the owner's team colour at weapon range + 3px, ten 2px dots per
## quadrant mirrored into all four, crawling one slot per second. A dot
## is NOT drawn where another selected unit's radius already covers it
## (zod WithinAttackRadiusOf) — a packed squad shows one merged envelope
## instead of forty overlapping circles.
const DOTS_PER_QUADRANT := 10
const PHASE_STEP := (PI / 2.0) / float(DOTS_PER_QUADRANT)
const DOT := 2.0
const RANGE_PAD := 3.0
var _phase := 0.0


func _draw_attack_radius(unit: Node) -> void:
	var reach: float = unit.get("range_px")
	if reach == null or reach <= 0.0:
		return  # unarmed hardware draws nothing (zod: !attack_radius)
	var scale: float = unit.get("sprite_scale")
	var radius := reach * scale + RANGE_PAD
	var col: Color = TEAM_COLORS.get(int(unit.get("team")), Color.WHITE)
	var avoid: Array = []
	if SelectionManager.current != null:
		avoid = SelectionManager.current.selected
	var deg := _phase
	while deg <= PI / 2.0:
		var spoke := Vector2(sin(deg), cos(deg)) * radius
		for corner in [
			spoke, Vector2(-spoke.x, spoke.y),
			Vector2(-spoke.x, -spoke.y), Vector2(spoke.x, -spoke.y),
		]:
			if _dot_covered(unit, corner, avoid):
				continue
			draw_rect(Rect2(corner - Vector2(DOT, DOT) * 0.5,
				Vector2(DOT, DOT)), col)
		deg += PHASE_STEP


func _dot_covered(unit: Node, local_dot: Vector2, avoid: Array) -> bool:
	var world_dot: Vector2 = unit.to_global(local_dot)
	for other in avoid:
		if other == unit or not is_instance_valid(other):
			continue
		var r: float = other.get("range_px")
		if r == null or r <= 0.0:
			continue
		if world_dot.distance_to(other.global_position) <= r:
			return true
	return false
	if unit.get("hp") != null and unit.get("max_hp") != null:
		if unit.hp < unit.max_hp:
			var r := _unit_rect(unit)
			_draw_health(unit.hp, unit.max_hp, r.position.y - PAD - 2.0)


## Four corner brackets in the owner's team colour around the unit's
## displayed frame content (zod frames the object footprint; the
## content box is our art-faithful equivalent).
func _draw_brackets(unit: Node) -> void:
	var col: Color = TEAM_COLORS.get(int(unit.get("team")), Color.WHITE)
	var box := _unit_rect(unit).grow(PAD)
	for corner in [box.position, Vector2(box.end.x, box.position.y),
			Vector2(box.position.x, box.end.y), box.end]:
		var dx := 1.0 if corner.x >= box.get_center().x else -1.0
		var dy := 1.0 if corner.y >= box.get_center().y else -1.0
		# arms lie ON the box edge, running inward from the corner
		draw_line(corner, corner + Vector2(-ARM * dx, 0), col, 1.0)
		draw_line(corner, corner + Vector2(0, -ARM * dy), col, 1.0)


## VETERANCY pips: one chevron dot per rank, under the selection box.
## Drawn only while selected, so a veteran army does not litter the
## field with markers.
const PIP := 2.0


func _draw_rank(unit: Node) -> void:
	if not unit.has_method("rank"):
		return
	var rank: int = unit.call("rank")
	if rank <= 0:
		return
	var box := _unit_rect(unit).grow(PAD)
	var col: Color = TEAM_COLORS.get(int(unit.get("team")), Color.WHITE).lightened(0.5)
	var start := Vector2(box.get_center().x - (rank - 1) * (PIP + 1.0) * 0.5,
		box.end.y + PIP + 1.0)
	for i in rank:
		draw_rect(Rect2(start + Vector2(i * (PIP + 1.0), 0.0) - Vector2(PIP, PIP) * 0.5,
			Vector2(PIP, PIP)), col)


## Procedural health bar above the sprite: black backing, green current
## HP, yellow lost HP (widths absolute vs HP_REF — zod RenderHealth).
func _draw_health(hp: int, max_hp: int, top: float) -> void:
	var green_w := maxf(BAR_MAX_W * clampf(float(hp) / HP_REF, 0.0, 1.0), 1.0)
	var yellow_w := maxf(BAR_MAX_W * clampf(float(max_hp) / HP_REF, 0.0, 1.0)
		- green_w, 0.0)
	var x := -BAR_MAX_W * 0.5 - 1.0
	draw_rect(Rect2(x - 1, top - 1, green_w + yellow_w + 2, 4),
		Color(0, 0, 0, 0.8))
	draw_rect(Rect2(x, top, green_w, 2), Color(0.32, 0.75, 0.13))
	if yellow_w > 0:
		draw_rect(Rect2(x + green_w, top, yellow_w, 2), Color(0.97, 0.80, 0.42))


## Content rect of the unit's CURRENT displayed frame, in ring-local
## coords (the frame draws centred on the unit origin). Falls back to a
## 24x32 box when there is no sprite/frame.
func _unit_rect(unit: Node) -> Rect2:
	var sprite: AnimatedSprite2D = unit.get("sprite")
	if sprite and sprite.sprite_frames:
		var tex: Texture2D = sprite.sprite_frames.get_frame_texture(
			sprite.animation, sprite.frame)
		if tex != null:
			var bb := _content_box(tex)
			if bb.size.x > 0:
				return Rect2(bb.position - tex.get_size() * 0.5, bb.size)
	return Rect2(-8, -8, 16, 16)


static func _content_box(tex: Texture2D) -> Rect2:
	var key := tex.get_instance_id()
	if _content_cache.has(key):
		return _content_cache[key]
	var img := tex.get_image()
	var bb := img.get_used_rect()  # alpha-content bbox of the frame
	_content_cache[key] = bb
	return bb
