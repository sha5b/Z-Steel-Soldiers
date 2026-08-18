@tool
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
var _turret: AnimatedSprite2D
var _turret_dir := 0
var _turret_offsets := PackedVector2Array()
var _wheel_offsets := PackedVector2Array()
var _turret_fire := 0.0
var _damaged := false
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
	if _asset_dir == "":
		_asset_dir = String(ContentDB.def_for(kind, unit_name).get("dir", ""))
	# vehicles/cannons have no per-team walk cycle: empty / base / fire
	# (base switches to the damaged hull set below half HP)
	sprite.sprite_frames = AnimLibrary.vehicle_frames(_asset_dir, team, _damaged)
	if not sprite.animation_finished.is_connected(_on_anim_finished):
		sprite.animation_finished.connect(_on_anim_finished)
	_build_turret()
	# jeep-style vehicles keep their wheels in separate 'under' sprites —
	# layer them beneath the body so it doesn't look like it's sliding
	if unit_name == "jeep":
		var wset: Dictionary = AnimLibrary.jeep_wheel_set(_asset_dir, team)
		if not wset.is_empty():
			if _wheels == null:
				_wheels = AnimatedSprite2D.new()
				_wheels.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				add_child(_wheels)
				# below the body via child order (z_index -1 would hide
				# the wheels behind the terrain in the Y-sorted world)
				move_child(_wheels, 0)
			_wheel_offsets = wset.offsets
			_wheels.sprite_frames = wset.frames
			_wheels.stop()
			_wheels.frame = 0  # visible before the first move
			_sync_wheels()


## Tanks carry their turret in separate `top_*` art: it rides above the
## hull, aims at the target independently and blows off on destruction.
func _build_turret() -> void:
	var tset: Dictionary = AnimLibrary.turret_set(_asset_dir, team)
	if tset.is_empty():
		if _turret:
			_turret.queue_free()
			_turret = null
		return
	if _turret == null:
		_turret = AnimatedSprite2D.new()
		_turret.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_turret)
		move_child(_turret, ring.get_index())  # above hull, below ring
		_turret.animation_finished.connect(_on_turret_finished)
	_turret_offsets = tset.offsets
	_turret.sprite_frames = tset.frames
	_turret.visible = manned


func _process(delta: float) -> void:
	voice_cooldown = maxf(0.0, voice_cooldown - delta)
	if not alive:
		return
	_fire_timer = maxf(0.0, _fire_timer - delta)
	if manned:
		_combat()
	_steer(delta)
	_separation(delta)
	_update_turret(delta)
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
	_sync_wheels()


func _sync_wheels() -> void:
	if _wheels == null or _wheels.sprite_frames == null:
		return
	var wname := "wheels_%d" % _last_dir
	if _wheels.sprite_frames.has_animation(wname):
		if _wheel_offsets.size() == AnimLibrary.DIRECTIONS:
			_wheels.position = _wheel_offsets[_last_dir]
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
	if _target:
		# turret tracks the target even while the gun reloads; the hull
		# only turns when the aim genuinely changes sector (hysteresis —
		# otherwise the body flickers between two facings)
		var want := _angle_to_dir(
			(_target.global_position - global_position).angle())
		_turret_dir = want
		if want != _last_dir:
			var current_angle := _last_dir * (TAU / 8.0)
			var want_angle := want * (TAU / 8.0)
			var diff := absf(angle_difference(current_angle, want_angle))
			if diff >= 0.35:
				_last_dir = want
	if _target and _fire_timer <= 0.0:
		var to_target := _target.global_position - global_position
		if to_target.length() <= range_px * sprite_scale:
			_last_dir = _angle_to_dir(to_target.angle())
			_fire_timer = cooldown
			_turret_fire = 0.25
			# tanks fire through the turret layer — the hull keeps its
			# base cycle where no hull fire art exists
			_play("fire", _last_dir, true, "base" if manned else "empty")
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


## Below half HP the hull switches to its damaged art set.
func take_damage(amount: int) -> void:
	super.take_damage(amount)
	if alive and not _damaged and hp < max_hp * 0.5:
		_damaged = true
		_build_frames()
		_play("base" if manned else "empty", _last_dir)


## Burning wreck: looping smoke/fire from the original death_effects art.
func _add_wreck_fx() -> void:
	var fx_name := "big_smoke" if unit_name == "heavy" else "fire"
	var frames := AnimLibrary.effect_frames(
		"res://assets/z/effects/%s" % fx_name, fx_name, 8.0)
	if frames == null or not frames.has_animation("fx"):
		return
	frames.set_animation_loop("fx", true)
	var fx := AnimatedSprite2D.new()
	fx.name = "WreckFx"
	fx.sprite_frames = frames
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.position = Vector2(0, -6)
	add_child(fx)
	fx.play("fx")


func _update_turret(delta: float) -> void:
	if _turret == null or not manned or not alive:
		return
	if _target == null or not is_instance_valid(_target):
		_turret_dir = _last_dir  # idle: turret follows the hull
	_turret_fire = maxf(0.0, _turret_fire - delta)
	if _turret_offsets.size() == AnimLibrary.DIRECTIONS:
		_turret.position = _turret_offsets[_turret_dir]
	var anim := ("turretfire_%d" if _turret_fire > 0.0 else "turret_%d") % _turret_dir
	if _turret.sprite_frames and _turret.sprite_frames.has_animation(anim):
		if _turret.animation != anim or not _turret.is_playing():
			_turret.play(anim)
			if not _turret.sprite_frames.get_animation_loop(anim):
				_turret.frame = _turret.sprite_frames.get_frame_count(anim) - 1


func _on_turret_finished() -> void:
	if _turret and _turret.animation == "pop":
		_turret.visible = false


func enter(robot: Unit2D) -> void:
	manned = true
	team = robot.team
	hp = maxi(hp, max_hp)  # fresh crew repairs
	_damaged = false
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
	if _turret and _turret.sprite_frames and _turret.sprite_frames.has_animation("pop"):
		_turret.visible = true
		_turret.play("pop")  # turret flies off
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
		_add_wreck_fx()
	else:
		queue_free()
