@tool
class_name Zone
extends Node2D
## Territory sector (from Zod map zone rects): flag at center, capture by
## presence, feeds GameState income. Team colours come from Teams; the
## flag waves in the owner's own shipped art variant.

signal captured(new_team: int)

const CAPTURE_SECONDS := 2.0

@export var zone_rect := Rect2i()
@export var owner_team := 0

var _capturing_team := 0
var _capture_progress := 0.0
var _flag: AnimatedSprite2D
var _overlay: ColorRect
var _border: ColorRect


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	MatchState.register_zone(self)
	_build_visuals()


func _build_visuals() -> void:
	# border + pins are drawn procedurally in _draw (original style:
	# team-coloured outline with markers travelling the perimeter);
	# the fill overlay is only a faint ownership tint
	var world := Rect2(zone_rect.position * 16, zone_rect.size * 16)
	_overlay = ColorRect.new()
	_overlay.position = world.position
	_overlay.size = world.size
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.color = Teams.zone_color(owner_team)
	_overlay.color.a = 0.05
	add_child(_overlay)

	_flag = AnimatedSprite2D.new()
	_flag.sprite_frames = AnimLibrary.flag_frames(owner_team)
	_flag.position = world.get_center()
	_flag.scale = Vector2(2, 2)
	add_child(_flag)
	if _flag.sprite_frames and _flag.sprite_frames.has_animation("wave"):
		_flag.play("wave")


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	queue_redraw()
	var occupying := 0
	var contested := false
	for u in UnitRegistry.world_units():
		# neutral hardware (empty vehicles) does not hold territory
		if u.team != 0 and world_rect().has_point(u.global_position):
			if occupying == 0:
				occupying = u.team
			elif u.team != occupying:
				contested = true
				break
	if contested:
		_capturing_team = 0  # enemies present: nobody captures
		_capture_progress = 0.0
	elif occupying != 0 and occupying != owner_team:
		if _capturing_team != occupying:
			_capturing_team = occupying
			_capture_progress = 0.0
		_capture_progress += delta
		if _capture_progress >= CAPTURE_SECONDS:
			set_owner_team(occupying)
			_capturing_team = 0
			_capture_progress = 0.0
	elif occupying == 0 or occupying == owner_team:
		_capture_progress = 0.0
		_capturing_team = 0


func world_rect() -> Rect2:
	return Rect2(zone_rect.position * 16, zone_rect.size * 16)


func _draw() -> void:
	var r := Rect2(Vector2(zone_rect.position) * 16.0, Vector2(zone_rect.size) * 16.0)
	if Engine.is_editor_hint():
		draw_rect(r, Color(1, 1, 1, 0.08))
		draw_rect(r, Color(1, 1, 1, 0.5), false, 2.0)
		return
	# team-coloured outline with corner pins and markers that travel
	# the perimeter — the original territory look
	var color: Color = Teams.zone_color(owner_team)
	if _capturing_team != 0:
		# contested: blink between owner and capturer
		var taker: Color = Teams.zone_color(_capturing_team)
		color = color.lerp(taker, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.01))
	draw_rect(r, Color(color.r, color.g, color.b, 0.55), false, 2.0)
	for corner in [r.position, r.position + Vector2(r.size.x, 0),
			r.position + Vector2(0, r.size.y), r.end]:
		draw_rect(Rect2(corner - Vector2(3, 3), Vector2(6, 6)), color)
	# travelling markers: evenly spaced squares riding the border
	var perimeter := 2.0 * (r.size.x + r.size.y)
	var count := maxi(int(perimeter / 56.0), 3)
	var speed := 24.0  # px/s along the border
	var shift := fmod(Time.get_ticks_msec() * 0.001 * speed, perimeter / count)
	for i in count:
		var d := fmod(shift + i * perimeter / count, perimeter)
		draw_rect(Rect2(_perimeter_point(r, d) - Vector2(2.5, 2.5), Vector2(5, 5)),
			Color(color.r, color.g, color.b, 0.9))


func _perimeter_point(r: Rect2, d: float) -> Vector2:
	# walk the border clockwise from the top-left corner
	if d < r.size.x:
		return r.position + Vector2(d, 0)
	d -= r.size.x
	if d < r.size.y:
		return r.position + Vector2(r.size.x, d)
	d -= r.size.y
	if d < r.size.x:
		return r.position + Vector2(r.size.x - d, r.size.y)
	d -= r.size.x
	return r.position + Vector2(0, r.size.y - d)


func set_owner_team(team: int) -> void:
	if owner_team == MatchState.player_team and team != MatchState.player_team:
		Fx.announce("territory_lost")
	owner_team = team
	captured.emit(team)
	MatchState.notify_zone_captured(team)
	if _overlay:
		_overlay.color = Teams.zone_color(team)
		_overlay.color.a = 0.10
	if _flag:
		_flag.sprite_frames = AnimLibrary.flag_frames(team)
		if _flag.sprite_frames and _flag.sprite_frames.has_animation("wave"):
			_flag.play("wave")
