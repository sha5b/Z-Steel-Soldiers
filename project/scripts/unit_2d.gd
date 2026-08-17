class_name Unit2D
extends CharacterBody2D
## Z (1996) robot/vehicle unit: 16x16 original sprites, 8 baked directions,
## animations loaded at runtime from project/assets/z/robots.

const SPEED := 60.0
const DIRECTIONS := 8
const TEAM_NAMES := {1: "red", 2: "blue", 3: "green", 4: "yellow"}

@export var unit_name := "grunt"
@export var team := 1
@export var sprite_scale := 2.0

var selected := false
var _last_dir := 0
var voice_cooldown := 0.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var ring: Node2D = $SelectionRing


func _process(delta: float) -> void:
	voice_cooldown = maxf(0.0, voice_cooldown - delta)


func _ready() -> void:
	add_to_group("selectable")
	add_to_group("units")
	scale = Vector2(sprite_scale, sprite_scale)
	_build_frames()
	set_selected(false)
	_play("stand", _last_dir)


func _build_frames() -> void:
	var team_name: String = TEAM_NAMES.get(team, "red")
	var frames := SpriteFrames.new()
	# body animations shared by all robots
	for anim in ["stand", "walk"]:
		for d in DIRECTIONS:
			var deg := d * 45
			var name := "%s_%d" % [anim, d]
			frames.add_animation(name)
			frames.set_animation_speed(name, 8.0 if anim == "walk" else 1.0)
			frames.set_animation_loop(name, true)
			var frame := 0
			while true:
				var suffix := "_n%02d" % frame if anim == "walk" else ""
				var path := "res://assets/z/robots/%s_%s_r%03d%s.png" % [anim, team_name, deg, suffix]
				if not ResourceLoader.exists(path):
					break
				frames.add_frame(name, load(path))
				frame += 1
				if anim == "stand":
					break
			if frame == 0:
				frames.remove_animation(name)  # missing direction
	# weapon fire animation, per robot type
	for d in DIRECTIONS:
		var deg := d * 45
		var name := "fire_%d" % d
		frames.add_animation(name)
		frames.set_animation_speed(name, 10.0)
		frames.set_animation_loop(name, true)
		var frame := 0
		while true:
			var path := "res://assets/z/robots_%s/fire_%s_r%03d_n%02d.png" % [unit_name, team_name, deg, frame]
			if not ResourceLoader.exists(path):
				break
			frames.add_frame(name, load(path))
			frame += 1
		if frame == 0:
			frames.remove_animation(name)
	sprite.sprite_frames = frames


func _physics_process(_delta: float) -> void:
	if velocity.length_squared() > 1.0:
		_last_dir = _angle_to_dir(velocity.angle())
		_play("walk", _last_dir)
	else:
		_play("stand", _last_dir)
	move_and_slide()


func move_to(world_pos: Vector2) -> void:
	# simple direct steering; formation offsets and pathing come later
	var offset := (world_pos - global_position)
	velocity = offset.normalized() * SPEED if offset.length() > 4.0 else Vector2.ZERO
	_play_voice("acknowledge")


func _play_voice(prefix: String) -> void:
	if voice_cooldown > 0.0:
		return
	voice_cooldown = 1.0
	var n := 10
	var path := "res://assets/z/sounds/%s_%02d.wav" % [prefix, randi() % n]
	if ResourceLoader.exists(path):
		var player := AudioStreamPlayer.new()
		player.stream = load(path)
		player.bus = "Master"
		add_child(player)
		player.finished.connect(player.queue_free)
		player.play()


func set_selected(value: bool) -> void:
	selected = value
	ring.visible = value
	ring.queue_redraw()


func _play(anim: String, dir: int) -> void:
	var name := "%s_%d" % [anim, dir]
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(name):
		if sprite.animation != name:
			sprite.play(name)
	elif sprite.is_playing():
		sprite.stop()


static func _angle_to_dir(angle: float) -> int:
	# r000 in the sprite set faces up (negative Y); rotate index accordingly
	var deg := fmod(rad_to_deg(angle) + 90.0 + 22.5, 360.0)
	return int(deg / 45.0) % DIRECTIONS


static func team_color(team: int) -> Color:
	match team:
		1: return Color(1.0, 0.25, 0.2)
		2: return Color(0.25, 0.5, 1.0)
		3: return Color(0.3, 0.9, 0.3)
		_: return Color(1.0, 0.9, 0.2)
