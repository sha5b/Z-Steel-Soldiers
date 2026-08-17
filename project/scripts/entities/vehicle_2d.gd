class_name Vehicle2D
extends Unit2D
## Mannable unit (vehicles & cannons): sits empty (gray sprites) until a
## robot walks in — then it fights for that robot's team. Guns with a
## `projectile` def fire travelling shells (damage lands on impact);
## everything else is hitscan like robot small arms. Destroyed vehicles
## leave the original wreck sprite.

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
	robot.waypoints = PackedVector2Array()
	# out of the world until unloaded: not selectable, not targetable,
	# doesn't hold zones or trip pickups
	robot.remove_from_group("selectable")
	robot.remove_from_group("units")
	SelectionManager.drop_from_selection(robot)
	return true


func unload() -> void:
	for i in cargo.size():
		var robot: Node = cargo[i]
		if not is_instance_valid(robot):
			continue
		robot.carried = false
		robot.visible = true
		robot.add_to_group("selectable")
		robot.add_to_group("units")
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
	_asset_dir = String(ContentDB.def_for(vkind, type_name).get("dir", ""))


func _build_frames() -> void:
	# vehicles/cannons have no per-team walk cycle: empty / base / fire
	sprite.sprite_frames = AnimLibrary.vehicle_frames(_asset_dir, team)
	if not sprite.animation_finished.is_connected(_on_anim_finished):
		sprite.animation_finished.connect(_on_anim_finished)
	# jeep-style vehicles keep their wheels in separate 'under' sprites —
	# layer them beneath the body so it doesn't look like it's sliding
	if unit_name == "jeep":
		if _wheels == null:
			_wheels = AnimatedSprite2D.new()
			_wheels.z_index = -1
			_wheels.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			add_child(_wheels)
		_wheels.sprite_frames = AnimLibrary.jeep_wheel_frames(_asset_dir, team)


func _process(delta: float) -> void:
	voice_cooldown = maxf(0.0, voice_cooldown - delta)
	if not alive:
		return
	_fire_timer = maxf(0.0, _fire_timer - delta)
	if manned:
		_combat()
	_steer(delta)
	_separation(delta)
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
			Fx.gunfire(String(ContentDB.def_for(kind, unit_name).get("sound", "")))
			Fx.play("muzzle", global_position + to_target.normalized() * 12.0)
			var amount := int(round(damage * GameState.vehicle_damage_mult(team)))
			var projectile: Dictionary = ContentDB.def_for(kind, unit_name).get("projectile", {})
			var target := _target
			if projectile.is_empty():
				# hitscan weapon: instant damage, tracer visual
				Fx.bullet(global_position + to_target.normalized() * 10.0, target.global_position)
				target.take_damage(amount)
			else:
				# shell: damage lands when the shot arrives
				Fx.shell(global_position + to_target.normalized() * 12.0,
					target.global_position, projectile,
					func():
						if is_instance_valid(target) and target.alive:
							target.take_damage(amount))


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
	SelectionManager.drop_from_selection(self)
	remove_from_group("selectable")
	remove_from_group("units")
	Fx.destroyed(global_position)
	# passengers die with the transport
	for robot in cargo:
		if is_instance_valid(robot):
			robot.global_position = global_position
			robot.visible = true
			robot.die()
	cargo.clear()
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("wasted") \
			and sprite.sprite_frames.get_frame_count("wasted") > 0:
		sprite.play("wasted")
		ring.visible = false
	else:
		queue_free()
