class_name Unit2D
extends CharacterBody2D
## Z (1996) robot unit: 16x16 original sprites, 8 baked directions.
## Auto-engages enemies in range; dies with original death animation.

const DIRECTIONS := 8
const TEAM_NAMES := {1: "red", 2: "blue", 3: "green", 4: "yellow"}

@export var unit_name := "grunt"
@export var team := 1
@export var sprite_scale := 2.0
@export var kind := "robot"  # robot | vehicle | cannon

var selected := false
var hp := 1
var max_hp := 1
var damage := 5
var range_px := 58.0
var cooldown := 0.75
var speed := 60.0
var alive := true
var voice_cooldown := 0.0

var _last_dir := 0
var _fire_timer := 0.0
var _target: Node2D = null

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var ring: Node2D = $SelectionRing


func _ready() -> void:
	add_to_group("selectable")
	add_to_group("units")
	var stats := UnitData.stats_for(kind, unit_name)
	hp = stats.hp
	max_hp = stats.hp
	damage = stats.damage
	range_px = stats.range
	cooldown = stats.cooldown
	speed = stats.speed
	scale = Vector2(sprite_scale, sprite_scale)
	_build_frames()
	set_selected(false)
	_play("stand", _last_dir)


func _build_frames() -> void:
	var team_name: String = TEAM_NAMES.get(team, "red")
	var frames := SpriteFrames.new()
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
				frames.remove_animation(name)
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
	# death animation (no facing variants)
	frames.add_animation("die")
	frames.set_animation_speed("die", 8.0)
	frames.set_animation_loop("die", false)
	var die := 0
	while true:
		var path := "res://assets/z/robots/die1_%s_n%02d.png" % [team_name, die]
		if not ResourceLoader.exists(path):
			break
		frames.add_frame("die", load(path))
		die += 1
	if die == 0:
		frames.remove_animation("die")
	sprite.sprite_frames = frames
	sprite.animation_finished.connect(_on_anim_finished)


func _process(delta: float) -> void:
	voice_cooldown = maxf(0.0, voice_cooldown - delta)
	if not alive:
		return
	_fire_timer = maxf(0.0, _fire_timer - delta)
	_combat()
	if velocity.length_squared() > 1.0:
		_last_dir = _angle_to_dir(velocity.angle())
		_play("walk", _last_dir)
	else:
		_play("fire" if _target else "stand", _last_dir)
	ring.queue_redraw()
	move_and_slide()


func _combat() -> void:
	if velocity.length_squared() > 4.0:
		return  # no fire-and-move yet
	_target = _find_target()
	if _target and _fire_timer <= 0.0:
		var to_target := _target.global_position - global_position
		if to_target.length() <= range_px * sprite_scale:
			_last_dir = _angle_to_dir(to_target.angle())
			_fire_timer = cooldown
			_shoot(_target, to_target)


func _find_target() -> Node2D:
	var best: Node2D = null
	var best_d := range_px * sprite_scale
	for u in get_tree().get_nodes_in_group("units"):
		if u is Node2D and u != self and u.alive and u.team != 0 and u.team != team:
			var d: float = global_position.distance_squared_to(u.global_position)
			if d < best_d * best_d:
				best_d = sqrt(d)
				best = u
	return best


func _shoot(target: Node2D, to_target: Vector2) -> void:
	_play("fire", _last_dir, true)
	_tracer(global_position + to_target.normalized() * 10.0, target.global_position)
	target.take_damage(damage)


func _tracer(from: Vector2, to: Vector2) -> void:
	var line := Line2D.new()
	line.points = PackedVector2Array([from, to])
	line.width = 1.5
	line.default_color = Color(1.0, 0.9, 0.4, 0.9)
	get_parent().add_child(line)
	var tween := line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.12)
	tween.tween_callback(line.queue_free)


func take_damage(amount: int) -> void:
	if not alive:
		return
	hp -= amount
	if ring:
		ring.visible = true
		ring.queue_redraw()
	modulate = Color(3, 3, 3)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.15)
	if hp <= 0:
		die()


func die() -> void:
	alive = false
	velocity = Vector2.ZERO
	set_selected(false)
	remove_from_group("selectable")
	remove_from_group("units")
	_play_voice("explosion")
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("die"):
		sprite.play("die")
		ring.visible = false
	else:
		queue_free()


func _on_anim_finished() -> void:
	if not alive and sprite.animation == "die":
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 0.8)
		tween.tween_callback(queue_free)


func move_to(world_pos: Vector2) -> void:
	var offset := (world_pos - global_position)
	velocity = offset.normalized() * speed if offset.length() > 4.0 else Vector2.ZERO
	_play_voice("acknowledge")


func _play_voice(prefix: String) -> void:
	if voice_cooldown > 0.0:
		return
	voice_cooldown = 1.0
	var paths := []
	match prefix:
		"acknowledge":
			for i in 10:
				paths.append("res://assets/z/sounds/acknowledge_%02d.wav" % i)
		"explosion":
			for i in 3:
				paths.append("res://assets/z/sounds/explosion_%02d.wav" % i)
	paths.shuffle()
	for path in paths:
		if ResourceLoader.exists(path):
			var player := AudioStreamPlayer.new()
			player.stream = load(path)
			add_child(player)
			player.finished.connect(player.queue_free)
			player.play()
			return


func set_selected(value: bool) -> void:
	selected = value
	ring.visible = value or hp < max_hp
	ring.queue_redraw()


func _play(anim: String, dir: int, once := false) -> void:
	var name := "%s_%d" % [anim, dir]
	if once and sprite.sprite_frames:
		sprite.stop()
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(name):
		if sprite.animation != name or not sprite.is_playing():
			sprite.play(name)
	elif sprite.is_playing():
		sprite.stop()


static func _angle_to_dir(angle: float) -> int:
	var deg := fmod(rad_to_deg(angle) + 90.0 + 22.5, 360.0)
	return int(deg / 45.0) % DIRECTIONS


static func team_color(team: int) -> Color:
	match team:
		1: return Color(1.0, 0.25, 0.2)
		2: return Color(0.25, 0.5, 1.0)
		3: return Color(0.3, 0.9, 0.3)
		_: return Color(1.0, 0.9, 0.2)
