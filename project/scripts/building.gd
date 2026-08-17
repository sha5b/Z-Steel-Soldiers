class_name Building2D
extends Node2D
## Original-sprite building (forts, factories, radar, repair). Loads the
## per-planet texture, shows an ownership flag, and computes a ground
## footprint (sprite is 2x tile scale -> footprint = texture/2) for
## clicks, zone ownership and targeting.

const DIRS := {0: "fort", 1: "fort", 2: "radar", 3: "repair", 4: "robot", 5: "vehicle"}
const TEAM_NAMES := {0: "null", 1: "red", 2: "blue", 3: "green", 4: "yellow"}

var building_id := 2
var team := 0
var planet := "desert"
var is_fort := false
var selected := false

var hp := 500
var max_hp := 500
var alive := true
var owner_team := 0  # factories: follows zone owner

var _sprite: Sprite2D
var _flag: AnimatedSprite2D
var _hp_bar: ColorRect
var _hp_bar_max_w := 64.0


func setup(id: int, owner_team_value: int, planet_name: String) -> void:
	building_id = id
	team = owner_team_value
	owner_team = owner_team_value
	planet = planet_name
	is_fort = id == 0 or id == 1


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = load(_texture_path(false))
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# bottom-center the sprite over the footprint
	var ts: Vector2 = _sprite.texture.get_size()
	_sprite.centered = false
	_sprite.position = Vector2(-ts.x * 0.25, -ts.y * 0.5)  # origin = footprint center
	add_child(_sprite)

	_flag = AnimatedSprite2D.new()
	_flag.sprite_frames = _flag_frames(TEAM_NAMES.get(team, "null"))
	_flag.position = Vector2(0, -ts.y * 0.5 - 4)
	_flag.scale = Vector2(2, 2)
	add_child(_flag)
	if _flag.sprite_frames:
		_flag.play("wave")

	if is_fort:
		add_to_group("buildings")
		_hp_bar = ColorRect.new()
		_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hp_bar.color = Color(0.2, 1.0, 0.2)
		var bar_w := ts.x * 0.5  # match the building footprint width
		_hp_bar_max_w = bar_w
		_hp_bar.size = Vector2(bar_w, 5)
		_hp_bar.position = Vector2(-bar_w * 0.5, -ts.y * 0.5 - 12)
		add_child(_hp_bar)


static func _flag_frames(team_name: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.add_animation("wave")
	frames.set_animation_loop("wave", true)
	frames.set_animation_speed("wave", 6.0)
	for i in 4:
		var path := "res://assets/z/flags/flag_%s_n%02d.png" % [team_name, i]
		if ResourceLoader.exists(path):
			frames.add_frame("wave", load(path))
	return frames


func _texture_path(destroyed: bool) -> String:
	match building_id:
		0: return "res://assets/z/buildings/fort/fort_%s_%s%s.png" % [planet, "front", "_destroyed" if destroyed else ""]
		1: return "res://assets/z/buildings/fort/fort_%s_%s%s.png" % [planet, "back", "_destroyed" if destroyed else ""]
		var d: return "res://assets/z/buildings/%s/base_%s%s.png" % [DIRS[building_id], planet, "_destroyed" if destroyed else ""]


func world_footprint() -> Rect2:
	# ground area under the sprite (world px), origin-centered
	var ts: Vector2 = _sprite.texture.get_size() if _sprite else Vector2(64, 64)
	var half := ts * 0.25
	return Rect2(global_position - half, half * 2.0)


func visual_center() -> Vector2:
	return global_position - Vector2(0, _sprite.texture.get_size().y * 0.25)


func set_selected(value: bool) -> void:
	selected = value
	if _sprite:
		_sprite.modulate = Color(1.3, 1.3, 0.9) if value else Color.WHITE


func update_flag(for_team: int) -> void:
	if not _flag:
		return
	var flag_name: String = TEAM_NAMES.get(for_team, "null")
	if _flag.name != flag_name and ResourceLoader.exists("res://assets/z/flags/flag_%s_n00.png" % flag_name):
		_flag.sprite_frames = _flag_frames(flag_name)
		_flag.name = flag_name
		_flag.play("wave")


func _process(_delta: float) -> void:
	# non-fort buildings (radar, repair) follow their zone's owner so the
	# flag recolors on capture; factories override with their own loop
	if is_fort:
		return
	var center := world_footprint().get_center()
	for z in GameState.zones:
		if z.world_rect().has_point(center):
			if z.owner_team != owner_team:
				owner_team = z.owner_team
				team = owner_team
				update_flag(owner_team)
			break


func take_damage(amount: int) -> void:
	if not alive or not is_fort:
		return
	hp -= amount
	if _sprite:
		_sprite.modulate = Color(3, 3, 3)
		var tween := create_tween()
		tween.tween_property(_sprite, "modulate", Color.WHITE, 0.15)
	if _hp_bar:
		_hp_bar.size.x = maxf(4.0, _hp_bar_max_w * clampf(float(hp) / float(max_hp), 0.0, 1.0))
	if hp <= 0:
		alive = false
		remove_from_group("buildings")
		_sprite.texture = load(_texture_path(true))
		_hp_bar.visible = false
		_flag.visible = false
		GameState.report_fort_destroyed(team)
