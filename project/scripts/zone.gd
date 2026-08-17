class_name Zone
extends Node2D
## Territory sector (from Zod map zone rects): flag at center, capture by
## presence, feeds GameState income.

const CAPTURE_SECONDS := 2.0
const FLAG_COLORS := {
	0: Color(0.85, 0.85, 0.85, 0.9),
	1: Color(1.0, 0.3, 0.25, 0.9),
	2: Color(0.3, 0.55, 1.0, 0.9),
	3: Color(0.35, 0.9, 0.35, 0.9),
	4: Color(1.0, 0.9, 0.25, 0.9),
}

@export var zone_rect := Rect2i()
@export var owner_team := 0

var _capturing_team := 0
var _capture_progress := 0.0
var _flag: AnimatedSprite2D
var _overlay: ColorRect
var _border: ColorRect


static func team_name(team: int) -> String:
	match team:
		1: return "red"
		2: return "blue"
		3: return "green"
		4: return "yellow"
		_: return "null"


func _ready() -> void:
	GameState.register_zone(self)
	_build_visuals()


func _build_visuals() -> void:
	var world := Rect2(zone_rect.position * 16, zone_rect.size * 16)
	_overlay = ColorRect.new()
	_overlay.position = world.position
	_overlay.size = world.size
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.color = FLAG_COLORS.get(owner_team, FLAG_COLORS[0])
	_overlay.color.a = 0.10
	add_child(_overlay)

	_border = ColorRect.new()
	_border.position = world.position
	_border.size = world.size
	_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_border.color = Color(1, 1, 1, 0.0)
	add_child(_border)

	_flag = AnimatedSprite2D.new()
	var frames := SpriteFrames.new()
	var team_str := team_name(owner_team)
	frames.add_animation("wave")
	frames.set_animation_loop("wave", true)
	frames.set_animation_speed("wave", 6.0)
	var loaded := 0
	for i in 4:
		var path := "res://assets/z/flags/flag_%s_n%02d.png" % [team_str, i]
		if ResourceLoader.exists(path):
			frames.add_frame("wave", load(path))
			loaded += 1
	_flag.sprite_frames = frames if loaded > 0 else null
	_flag.position = world.get_center()
	_flag.scale = Vector2(2, 2)
	add_child(_flag)
	if loaded > 0:
		_flag.play("wave")


func _process(delta: float) -> void:
	var occupying := 0
	for u in get_tree().get_nodes_in_group("units"):
		if world_rect().has_point(u.global_position):
			occupying = u.team
			break
	if occupying != 0 and occupying != owner_team:
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


func set_owner_team(team: int) -> void:
	owner_team = team
	if _overlay:
		_overlay.color = FLAG_COLORS.get(team, FLAG_COLORS[0])
		_overlay.color.a = 0.10
	if _flag and _flag.sprite_frames:
		var frames: SpriteFrames = _flag.sprite_frames
		for i in frames.get_frame_count("wave"):
			frames.remove_frame("wave", 0)
		var team_str := team_name(team)
		for i in 4:
			var path := "res://assets/z/flags/flag_%s_n%02d.png" % [team_str, i]
			if ResourceLoader.exists(path):
				frames.add_frame("wave", load(path))
		_flag.play("wave")
