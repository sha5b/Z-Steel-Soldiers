class_name Unit2D
extends CharacterBody2D
## Z (1996) robot unit: 16x16 original sprites, 8 baked directions.
## Auto-engages enemies in range; dies with a random original death
## animation; celebrates a win. Sprites/stats come from ContentDB and
## AnimLibrary — see docs/ASSET_CONVENTIONS.md to add unit types.

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
var move_target := Vector2.ZERO
var waypoints := PackedVector2Array()
var enter_target: Node2D = null
var _idle_time := 0.0
var _flavoring := false
var carried := false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var ring: Node2D = $SelectionRing


func _ready() -> void:
	add_to_group("selectable")
	add_to_group("units")
	var stats := ContentDB.stats_for(kind, unit_name)
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
	if not GameState.game_over.is_connected(_on_game_over):
		GameState.game_over.connect(_on_game_over)


## All sprite scanning lives in AnimLibrary; robots get stand/walk/fire,
## a random death variant, idle humor flavors and the victory celebrate
## animation from the shared zod folders.
func _build_frames() -> void:
	sprite.sprite_frames = AnimLibrary.robot_frames(unit_name, team)
	if not sprite.animation_finished.is_connected(_on_anim_finished):
		sprite.animation_finished.connect(_on_anim_finished)


func _process(delta: float) -> void:
	if carried:
		return
	voice_cooldown = maxf(0.0, voice_cooldown - delta)
	if not alive:
		return
	_fire_timer = maxf(0.0, _fire_timer - delta)
	_combat()
	_steer(delta)
	_separation(delta)
	_try_enter()
	if kind == "robot":
		_idle(delta)
	ring.queue_redraw()


func _steer(delta: float) -> void:
	if move_target != Vector2.ZERO:
		var next: Vector2 = waypoints[0] if not waypoints.is_empty() else move_target
		var offset := next - global_position
		if offset.length() <= (6.0 if not waypoints.is_empty() else 4.0):
			if not waypoints.is_empty():
				waypoints.remove_at(0)
			else:
				move_target = Vector2.ZERO
				velocity = Vector2.ZERO
		else:
			velocity = offset.normalized() * speed
	if velocity.length_squared() > 1.0:
		_last_dir = _angle_to_dir(velocity.angle())
		_play("walk", _last_dir)
		global_position += velocity * delta
		global_position = global_position.clamp(
			GameState.map_rect.position, GameState.map_rect.end)
	else:
		_play("fire" if _target else "stand", _last_dir)


## Keep units from piling into one spot: push nearby units apart a little
## every frame (zod robots shoulder each other aside while walking).
func _separation(delta: float) -> void:
	var push := Vector2.ZERO
	for u in get_tree().get_nodes_in_group("units"):
		if u == self or not (u is Unit2D) or not u.alive or u.carried:
			continue
		var d: Vector2 = global_position - u.global_position
		var dist := d.length()
		if dist < 14.0 and dist > 0.01:
			push += (d / dist) * (14.0 - dist)
		elif dist <= 0.01:
			push += Vector2(randf() - 0.5, randf() - 0.5)  # perfectly stacked
	global_position += push * clampf(delta * 6.0, 0.0, 1.0) * 0.5
	global_position = global_position.clamp(
		GameState.map_rect.position, GameState.map_rect.end)


func _idle(delta: float) -> void:
	if kind != "robot":
		return
	if velocity.length_squared() > 1.0 or _target:
		_idle_time = 0.0
		_flavoring = false
		return
	if _flavoring:
		return
	_idle_time += delta
	if _idle_time > randf_range(5.0, 12.0):
		_flavoring = true
		_idle_time = 0.0
		var flavor: String = AnimLibrary.IDLE_FLAVORS.pick_random()
		var name := "%s_%d" % [flavor, _last_dir]
		if not sprite.sprite_frames or not sprite.sprite_frames.has_animation(name):
			name = "%s_0" % flavor
		if sprite.sprite_frames and sprite.sprite_frames.has_animation(name) \
				and sprite.sprite_frames.get_frame_count(name) > 0:
			sprite.play(name)
		else:
			_flavoring = false


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
		if u is Node2D and u != self and u.alive and u.team != 0 and u.team != team \
				and not u.carried:
			var d: float = global_position.distance_squared_to(u.global_position)
			if d < best_d * best_d:
				best_d = sqrt(d)
				best = u
	# enemy buildings (forts) in range
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is Node2D and b.alive and b.team != 0 and b.team != team:
			var d: float = global_position.distance_squared_to(b.visual_center())
			if d < best_d * best_d:
				best_d = sqrt(d)
				best = b
	return best


## Robot small arms are hitscan: damage lands instantly, the tracer is
## visual only (Z-style).
func _shoot(target: Node2D, to_target: Vector2) -> void:
	_play("fire", _last_dir, true)
	Fx.gunfire(String(ContentDB.def_for(kind, unit_name).get("sound", "")))
	Fx.bullet(global_position + to_target.normalized() * 10.0, target.global_position)
	Fx.play("muzzle", global_position + to_target.normalized() * 12.0)
	target.take_damage(int(round(damage * GameState.robot_damage_mult(team))))


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
	SelectionManager.drop_from_selection(self)
	remove_from_group("selectable")
	remove_from_group("units")
	Fx.explosion(global_position)
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("die"):
		sprite.play("die")
		ring.visible = false
	else:
		queue_free()


func _on_game_over(winning_team: int) -> void:
	if not alive or carried or winning_team != team:
		return
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("celebrate") \
			and velocity.length_squared() <= 1.0:
		sprite.play("celebrate")
		_flavoring = true  # holds the anim until it finishes


func _on_anim_finished() -> void:
	if not alive and sprite.animation == "die":
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 0.8)
		tween.tween_callback(queue_free)
	elif _flavoring:
		_flavoring = false
		_idle_time = 0.0


func move_to(world_pos: Vector2) -> void:
	enter_target = null  # a fresh order supersedes any pending man/load
	move_target = world_pos
	waypoints = GameState.request_path(global_position, world_pos, kind)
	if waypoints.is_empty():
		move_target = Vector2.ZERO  # unreachable (e.g. water for vehicles)
	elif waypoints.size() > 1 and global_position.distance_to(waypoints[0]) < 10.0:
		waypoints.remove_at(0)  # don't step back to the start cell centre
	if team == GameState.player_team:
		_play_voice("acknowledge")
		PathIndicator.show_path(get_parent(), waypoints)


## Man/load the assigned vehicle once actually adjacent to it.
func _try_enter() -> void:
	if enter_target == null or not is_instance_valid(enter_target) or not enter_target.alive:
		enter_target = null
		return
	if global_position.distance_to(enter_target.global_position) > 16.0:
		return
	var v := enter_target
	enter_target = null
	if v is Vehicle2D and v.alive:
		if not v.manned:
			SelectionManager.drop_from_selection(self)
			v.enter(self)
			queue_free()
		elif v.is_apc() and v.team == team:
			v.load_robot(self)


func portrait_path() -> String:
	match kind:
		"robot":
			return "res://assets/z/robots/stand_%s_r180.png" % AnimLibrary.team_name(team)
		"cannon", "vehicle":
			return "%s/empty_r180.png" % String(ContentDB.def_for(kind, unit_name).get("dir", ""))
	return ""


func _play_voice(prefix: String) -> void:
	if voice_cooldown > 0.0:
		return
	voice_cooldown = 1.0
	var paths := []
	match prefix:
		"acknowledge":
			for i in 10:
				paths.append("res://assets/z/sounds/acknowledge_%02d.wav" % i)
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


## Zod DirectionFromLoc: sector of atan2 (y-down) + PI/8, mapped
## counter-clockwise; sprite r000 faces +X (right), r090 down, r180 left, r270 up.
static func _angle_to_dir(angle: float) -> int:
	var a := angle
	if a < 0.0:
		a += TAU
	a += PI / 8.0
	return wrapi(8 - int(a / (PI / 4.0)), 0, AnimLibrary.DIRECTIONS)


static func team_color(team: int) -> Color:
	match team:
		1: return Color(1.0, 0.25, 0.2)
		2: return Color(0.25, 0.5, 1.0)
		3: return Color(0.3, 0.9, 0.3)
		_: return Color(1.0, 0.9, 0.2)
