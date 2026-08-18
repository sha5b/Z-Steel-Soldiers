@tool
class_name Building2D
extends Node2D
## Original-sprite building (forts, factories, radar, repair). Loads the
## per-planet texture, shows an ownership flag, and computes a ground
## footprint (sprite is 2x tile scale -> footprint = texture/2) for
## clicks, zone ownership and targeting.

const TEAM_NAMES := {0: "null", 1: "red", 2: "blue", 3: "green", 4: "yellow"}

@export var building_id := 2
@export var team := 0
@export var planet := "desert"
var is_fort := false
var selected := false

var hp := 500
var max_hp := 500
var alive := true
var owner_team := 0  # factories: follows zone owner
var rally_point := Vector2.INF  # produced units gather here when set

var _sprite: Sprite2D
var _rally_flag: Sprite2D
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
	# works with setup() (JSON loader) or straight @export values (map scenes)
	if not is_fort:
		is_fort = building_id == 0 or building_id == 1
	if owner_team == 0 and team != 0:
		owner_team = team
	_build_sprite()
	if Engine.is_editor_hint():
		return
	if is_fort:
		add_to_group("buildings")
	# producers register for the facility quick bar
	if ContentDB.building_def(building_id).get("produces", false) or is_fort:
		add_to_group("facilities")


func _build_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = load(_texture_path(false))
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# bottom-center the sprite over the footprint
	var ts: Vector2 = _sprite.texture.get_size()
	_sprite.centered = false
	_sprite.position = Vector2(-ts.x * 0.25, -ts.y * 0.5)  # origin = footprint center
	if building_id == 7:  # horizontal bridge: rotate the vertical strip
		_sprite.rotation_degrees = 90
		_sprite.position = Vector2(-ts.y * 0.25, ts.x * 0.5) - Vector2(0, ts.x)
	add_child(_sprite)

	_flag = AnimatedSprite2D.new()
	if building_id == 6 or building_id == 7:
		_flag.visible = false  # bridges carry no flag
	_flag.sprite_frames = _flag_frames(TEAM_NAMES.get(team, "null"))
	_flag.position = Vector2(0, -ts.y * 0.5 - 4)
	_flag.scale = Vector2(2, 2)
	add_child(_flag)
	if _flag.sprite_frames:
		_flag.play("wave")

	_build_overlays()

	if is_fort:
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


## Texture location comes from the building def's `tex` key — new building
## types only add art + a BuildingDefs entry.
func _texture_path(destroyed: bool) -> String:
	match String(ContentDB.building_def(building_id).get("tex", "")):
		"fort_front":
			return "res://assets/z/buildings/fort/fort_%s_front%s.png" % [
				planet, "_destroyed" if destroyed else ""]
		"fort_back":
			return "res://assets/z/buildings/fort/fort_%s_back%s.png" % [
				planet, "_destroyed" if destroyed else ""]
		"bridge":
			return "res://assets/z/planets/bridge_%s.png" % planet
		var kind:
			if destroyed:
				return "res://assets/z/buildings/%s/base_destroyed_%s.png" % [kind, planet]
			return "res://assets/z/buildings/%s/base_%s.png" % [kind, planet]


## Animated overlay layers from the def's `anims` (radar dish, factory
## spinner, repair smoke stack...): numbered frames `<prefix>_<i>.png`
## played as a loop over the base sprite.
func _build_overlays() -> void:
	for def in ContentDB.building_def(building_id).get("anims", []):
		var frames := SpriteFrames.new()
		frames.add_animation("loop")
		frames.set_animation_speed("loop", float(def.get("fps", 6.0)))
		frames.set_animation_loop("loop", true)
		var frame := 0
		while true:
			var path := "res://assets/z/buildings/%s/%s_%d.png" % [
				String(ContentDB.building_def(building_id).get("tex", "")),
				String(def.prefix), frame]
			if not ResourceLoader.exists(path):
				break
			frames.add_frame("loop", load(path))
			frame += 1
		if frame == 0:
			continue
		var overlay := AnimatedSprite2D.new()
		overlay.name = "Overlay_%s" % String(def.prefix)
		overlay.sprite_frames = frames
		overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		overlay.centered = false
		overlay.position = Vector2(def.get("offset", Vector2.ZERO)) - 			Vector2(8, 8)  # small overlay sprites anchor near their centre
		add_child(overlay)
		overlay.play("loop")


func world_footprint() -> Rect2:
	# ground area under the sprite (world px), origin-centered
	var ts: Vector2 = _sprite.texture.get_size() if _sprite else Vector2(64, 64)
	if building_id == 7:
		ts = Vector2(ts.y, ts.x)  # rotated horizontal bridge
	var half := ts * 0.25
	return Rect2(global_position - half, half * 2.0)


func visual_center() -> Vector2:
	return global_position - Vector2(0, _sprite.texture.get_size().y * 0.25)


func set_rally(world_position: Vector2) -> void:
	rally_point = world_position
	if _rally_flag == null:
		_rally_flag = Sprite2D.new()
		_rally_flag.texture = load("res://assets/z/flags/flag_red_n00.png")
		_rally_flag.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_rally_flag.scale = Vector2(2, 2)
		add_child(_rally_flag)
	_rally_flag.position = rally_point - global_position
	_rally_flag.visible = selected


func set_selected(value: bool) -> void:
	selected = value
	if _rally_flag:
		_rally_flag.visible = value and rally_point != Vector2.INF
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
	if Engine.is_editor_hint():
		return
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
		SelectionManager.drop_from_selection(self)
		Fx.destroyed(visual_center())
		_sprite.texture = load(_texture_path(true))
		for child in get_children():
			if child.name.begins_with("Overlay_"):
				child.visible = false
		_hp_bar.visible = false
		_flag.visible = false
		GameState.report_fort_destroyed(team)
