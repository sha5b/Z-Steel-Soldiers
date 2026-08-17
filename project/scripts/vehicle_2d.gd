class_name Vehicle2D
extends Unit2D
## Mannable unit (vehicles & cannons): sits empty (gray sprites) until a
## robot walks in — then it fights for that robot's team. Destroyed
## vehicles leave the original wreck sprite.

@export var manned := false

var _asset_dir := ""
var _wheels: AnimatedSprite2D
var cargo: Array[Node] = []

const APC_CAPACITY := 3


func is_apc() -> bool:
	return unit_name == "apc"


func load_robot(robot: Unit2D) -> bool:
	if not is_apc() or not manned or cargo.size() >= APC_CAPACITY:
		return false
	cargo.append(robot)
	robot.carried = true
	robot.set_selected(false)
	robot.visible = false
	robot.velocity = Vector2.ZERO
	robot.move_target = Vector2.ZERO
	SelectionManager.drop_from_selection(robot)
	return true


func unload() -> void:
	for i in cargo.size():
		var robot: Node = cargo[i]
		if not is_instance_valid(robot):
			continue
		robot.carried = false
		robot.visible = true
		robot.global_position = global_position + Vector2(
			(i - (cargo.size() - 1) * 0.5) * 18.0, 20.0)
	cargo.clear()


func _on_arrived() -> void:
	if is_apc() and not cargo.is_empty():
		unload()


func setup_vehicle(vkind: String, type_name: String, owner_team: int) -> void:
	kind = vkind
	unit_name = type_name
	team = 0  # empty until manned; owner_team only records last holder
	manned = owner_team != 0
	if manned:
		team = owner_team
	_asset_dir = _dir_for(vkind, type_name)


static func _dir_for(vkind: String, type_name: String) -> String:
	match type_name:
		"jeep": return "res://assets/z/vehicles_jeep"
		"light": return "res://assets/z/vehicles_light"
		"medium": return "res://assets/z/vehicles_medium"
		"heavy": return "res://assets/z/vehicles_heavy"
		"apc": return "res://assets/z/vehicles_apc"
		"gatling": return "res://assets/z/cannons_gatling"
		"gun": return "res://assets/z/cannons_gun"
		"howitzer": return "res://assets/z/cannons_howitzer"
		"missile_cannon": return "res://assets/z/cannons_missile"
	return "res://assets/z/vehicles_jeep"


static func dir_exists(vkind: String, type_name: String) -> bool:
	var dir := _dir_for(vkind, type_name)
	return ResourceLoader.exists(dir + "/empty_r000.png") \
		or ResourceLoader.exists(dir + "/fire_r000_n00.png") \
		or ResourceLoader.exists(dir + "/empty.png")


func _build_frames() -> void:
	# vehicles/cannons have no per-team walk cycle: empty / base / fire
	var team_name: String = TEAM_NAMES.get(team, "null")
	var frames := SpriteFrames.new()
	for anim in ["empty", "base", "fire"]:
		for d in DIRECTIONS:
			var deg := d * 45
			var name := "%s_%d" % [anim, d]
			frames.add_animation(name)
			frames.set_animation_speed(name, 6.0 if anim == "base" else 10.0)
			frames.set_animation_loop(name, true)
			var frame := 0
			while true:
				var path := _anim_path(anim, team_name, deg, frame)
				if not ResourceLoader.exists(path):
					break
				frames.add_frame(name, load(path))
				frame += 1
				if anim == "empty":
					break
			if frame == 0:
				frames.remove_animation(name)  # missing direction
	frames.add_animation("wasted")
	frames.set_animation_loop("wasted", false)
	for i in 2:
		var path := "%s/wasted.png" % _asset_dir
		if ResourceLoader.exists(path):
			frames.add_frame("wasted", load(path))
			break
	sprite.sprite_frames = frames
	if not sprite.animation_finished.is_connected(_on_anim_finished):
		sprite.animation_finished.connect(_on_anim_finished)
	_build_wheels(team_name)


## Jeep-style vehicles keep their wheels in separate 'under' sprites —
## layer them beneath the body so it doesn't look like it's sliding.
func _build_wheels(team_name: String) -> void:
	if unit_name != "jeep":
		return
	if _wheels == null:
		_wheels = AnimatedSprite2D.new()
		_wheels.z_index = -1
		_wheels.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_wheels)
	var frames := SpriteFrames.new()
	var found := false
	for d in DIRECTIONS:
		var name := "wheels_%d" % d
		frames.add_animation(name)
		frames.set_animation_speed(name, 12.0)
		frames.set_animation_loop(name, true)
		var frame := 0
		while true:
			var path := "%s/under_%s_r%03d_n%02d.png" % [_asset_dir, team_name, d * 45, frame]
			if not ResourceLoader.exists(path):
				break
			frames.add_frame(name, load(path))
			frame += 1
		if frame == 0:
			frames.remove_animation(name)
		else:
			found = true
	if not found:
		_wheels.sprite_frames = null
	else:
		_wheels.sprite_frames = frames


func _anim_path(anim: String, team_name: String, deg: int, frame: int) -> String:
	match anim:
		"empty":
			return "%s/empty_r%03d.png" % [_asset_dir, deg]
		"base":
			return "%s/base_%s_r%03d_n%02d.png" % [_asset_dir, team_name, deg, frame]
		"fire":
			# cannons have team-coloured fire, vehicles a shared one
			var team_path := "%s/fire_%s_r%03d_n%02d.png" % [_asset_dir, team_name, deg, frame]
			if ResourceLoader.exists(team_path):
				return team_path
			return "%s/fire_r%03d_n%02d.png" % [_asset_dir, deg, frame]
	return ""


func _process(delta: float) -> void:
	voice_cooldown = maxf(0.0, voice_cooldown - delta)
	if not alive:
		return
	_fire_timer = maxf(0.0, _fire_timer - delta)
	if manned:
		_combat()
	_steer(delta)
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
				_on_arrived()
		else:
			velocity = offset.normalized() * speed
	if velocity.length_squared() > 1.0:
		_last_dir = _angle_to_dir(velocity.angle())
		_play("base" if manned else "empty", _last_dir)
		global_position += velocity * delta
		global_position = global_position.clamp(
			GameState.map_rect.position, GameState.map_rect.end)
	else:
		_play("base" if manned else "empty", _last_dir)
	if _wheels and _wheels.sprite_frames:
		var wname := "wheels_%d" % _last_dir
		if _wheels.sprite_frames.has_animation(wname):
			if velocity.length_squared() > 1.0:
				if _wheels.animation != wname or not _wheels.is_playing():
					_wheels.play(wname)
			else:
				_wheels.stop()
				_wheels.frame = 0


func _combat() -> void:
	if speed > 0.0 and velocity.length_squared() > 4.0:
		_last_dir = _angle_to_dir(velocity.angle())
		return
	_target = _find_target()
	if _target and _fire_timer <= 0.0:
		var to_target := _target.global_position - global_position
		if to_target.length() <= range_px * sprite_scale:
			_last_dir = _angle_to_dir(to_target.angle())
			_fire_timer = cooldown
			_play("fire", _last_dir, true)
			_tracer(global_position + to_target.normalized() * 10.0, _target.global_position)
			_target.take_damage(damage)


func enter(robot: Unit2D) -> void:
	manned = true
	team = robot.team
	hp = maxi(hp, max_hp)  # fresh crew repairs
	_build_frames()
	_play("base", _last_dir)


func die() -> void:
	alive = false
	velocity = Vector2.ZERO
	set_selected(false)
	remove_from_group("selectable")
	remove_from_group("units")
	_play_voice("explosion")
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("wasted") \
			and sprite.sprite_frames.get_frame_count("wasted") > 0:
		sprite.play("wasted")
		ring.visible = false
	else:
		queue_free()
