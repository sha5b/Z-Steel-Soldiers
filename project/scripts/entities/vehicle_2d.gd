@tool
class_name Vehicle2D
extends Unit2D
## Mannable unit (vehicles & cannons): sits empty (gray sprites) until a
## robot walks in — then it fights for that robot's team. Guns with a
## `projectile` def fire travelling shells (damage lands on impact);
## everything else is hitscan like robot small arms. Destroyed vehicles
## leave the original wreck sprite; tanks blow their turret off and burn.
##
## Layered rendering follows the original engine (see AnimLibrary):
## hull `base_*` below, turret/gun/crane layers above with per-facing
## offsets; jeep wheels render beneath the body and hide for the
## vertical facings where the original shipped no wheel art.

@export var manned := false

var _asset_dir := ""
var _wheels: AnimatedSprite2D
var _wheel_offsets := PackedVector2Array()
var _layer: AnimatedSprite2D          # turret / jeep gun / crane arm
var _hook: AnimatedSprite2D           # crane hook
var _doors: AnimatedSprite2D          # APC open animation
var _layer_dir := 0                   # turret/gun facing
var _layer_scan := false              # turret scans while idle
var _layer_canvas_off := PackedVector2Array()
var _layer_hull_off := PackedVector2Array()
var _layer_aim_off := PackedVector2Array()
var _hook_off := PackedVector2Array()
var _turret_fire := 0.0
var _scan_timer := 0.0
var _damaged := false
var _smoke_timer := 0.0
var _fire_flash := 0.0
var _install_timer := 0.0
var _wreck := false
var cargo: Array[Node] = []

const APC_CAPACITY := 3
const SCAN_STEP_SECONDS := 1.0  # zod turrent_time_int: idle turrets rotate one sector per second


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
	_play_doors()


## APC doors swing open (original `open_*` art) as the squad jumps out.
func _play_doors() -> void:
	if _doors == null or _doors.sprite_frames == null:
		return
	var name := "open_%d" % _last_dir
	if _doors.sprite_frames.has_animation(name):
		_doors.visible = true
		_doors.play(name)


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
	_build_layer()
	if unit_name == "jeep":
		var wset: Dictionary = AnimLibrary.jeep_wheel_set(_asset_dir, team, manned)
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
	if is_apc():
		var dset: Dictionary = AnimLibrary.apc_open_set(_asset_dir, team)
		if not dset.is_empty() and _doors == null:
			_doors = AnimatedSprite2D.new()
			_doors.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_doors.sprite_frames = dset.frames
			_doors.visible = false
			_doors.animation_finished.connect(func():
				if is_instance_valid(_doors):
					_doors.visible = false)
			add_child(_doors)
			move_child(_doors, ring.get_index())


## The turret / gun layer for tanks, missile launchers, APC scanners and
## the jeep gunner; the crane gets its arm + hook pair instead.
func _build_layer() -> void:
	var lset: Dictionary = {}
	if unit_name == "crane":
		lset = AnimLibrary.crane_set(_asset_dir)
	else:
		lset = AnimLibrary.turret_set(unit_name, _asset_dir, team)
	if lset.is_empty():
		if _layer:
			_layer.queue_free()
			_layer = null
		return
	if _layer == null:
		_layer = AnimatedSprite2D.new()
		_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_layer)
		move_child(_layer, ring.get_index())  # above hull, below ring
		_layer.animation_finished.connect(_on_layer_finished)
	_layer_canvas_off = lset.get("canvas_off", PackedVector2Array())
	_layer_hull_off = lset.get("hull_off", PackedVector2Array())
	_layer_aim_off = lset.get("aim_off", PackedVector2Array())
	_layer_scan = bool(lset.get("scans", false)) and unit_name != "crane"
	_layer.sprite_frames = lset.frames
	_layer.visible = manned
	if unit_name == "crane":
		_layer_dir = _last_dir
		if _hook == null and lset.frames.has_animation("hook"):
			_hook_off = lset.get("hook_off", PackedVector2Array())
			_hook = AnimatedSprite2D.new()
			_hook.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_hook.sprite_frames = lset.frames
			_hook.visible = false  # shown once manned
			add_child(_hook)
			move_child(_hook, _layer.get_index() + 1)
	_layer_dir = _last_dir


func _process(delta: float) -> void:
	voice_cooldown = maxf(0.0, voice_cooldown - delta)
	if _wreck:
		_update_wreck(delta)
		return
	if not alive:
		return
	_fire_timer = maxf(0.0, _fire_timer - delta)
	_fire_flash = maxf(0.0, _fire_flash - delta)
	_install_timer = maxf(0.0, _install_timer - delta)
	if manned:
		_combat()
	_steer(delta)
	_separation(delta)
	_update_layer(delta)
	_damage_fx(delta)
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
		_play_body()
		var dist_before := offset_to_next_waypoint()
		global_position += velocity * delta
		# consume waypoints leapfrogged by a large step (see Unit2D._steer)
		if not waypoints.is_empty() \
				and global_position.distance_to(waypoints[0]) > dist_before:
			waypoints.remove_at(0)
		global_position = global_position.clamp(
			GameState.map_rect.position, GameState.map_rect.end)
	else:
		_play_body()
	_sync_wheels()


## Hull animation: move/idle cycle, briefly replaced by the gunner
## install animation when a robot mans the hardware, then the muzzle
## flash on shots (`fire` art is a one-shot in the original).
func _play_body() -> void:
	if _install_timer > 0.0 and sprite.sprite_frames \
			and sprite.sprite_frames.has_animation("install_%d" % _last_dir):
		var install := "install_%d" % _last_dir
		if sprite.animation != install or not sprite.is_playing():
			_play("install", _last_dir)
		return
	if _fire_flash > 0.0 and sprite.sprite_frames \
			and sprite.sprite_frames.has_animation("fire_%d" % _last_dir):
		_play("fire", _last_dir)
		return
	_play("base" if manned else "empty", _last_dir)


func _sync_wheels() -> void:
	if _wheels == null or _wheels.sprite_frames == null:
		return
	var wname := "wheels_%d" % _last_dir
	# the original ships no wheel art for the vertical facings — the
	# wheels are simply hidden while driving straight up or down
	if not _wheels.sprite_frames.has_animation(wname):
		_wheels.visible = false
		return
	_wheels.visible = true
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
	# APC: the squad inside fires through the ports — the first cargo
	# robot's weapon stands in for the squad (original behaviour: every
	# passenger shoots with his own gun)
	if is_apc() and not cargo.is_empty() and _target and _fire_timer <= 0.0:
		var gunner = cargo[0]  # untyped: may hold any robot subtype
		var to_squad_target := _target.global_position - global_position
		if to_squad_target.length() <= 70.0 * sprite_scale:
			_last_dir = _angle_to_dir(to_squad_target.angle())
			_fire_timer = 0.8
			_fire_flash = 0.0  # no hull flash art for the APC
			var gname := "grunt"
			if gunner is Unit2D:
				gname = gunner.unit_name
			Fx.gunfire(String(ContentDB.def_for("robot", gname).get("sound", "RIFLE3")))
			Fx.bullet(global_position + to_squad_target.normalized() * 10.0,
				_target.global_position)
			_target.take_damage(6)
	if _target:
		# turret tracks the target even while the gun reloads; the hull
		# only turns when the aim genuinely changes sector (hysteresis —
		# otherwise the body flickers between two facings)
		var want := _angle_to_dir(
			(_target.global_position - global_position).angle())
		_layer_dir = want
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
			_fire_flash = 0.3
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
				var tid := target.get_instance_id()
				Fx.shell(global_position + to_target.normalized() * 12.0,
					target.global_position, projectile,
					func():
						var hit: Node2D = instance_from_id(tid) as Node2D
						if hit and hit.alive:
							hit.take_damage(amount))


## Below half HP the hull switches to its damaged art and leaks: smoke
## puffs (track_dust art, facing-aware) plus an oil stain underneath —
## the original ETankSmoke/ETankOil behaviour.
func take_damage(amount: int) -> void:
	super.take_damage(amount)
	if alive and not _damaged and hp < max_hp * 0.5:
		_damaged = true
		_build_frames()
		_play_body()
		_add_oil_stain()


func _damage_fx(delta: float) -> void:
	if not _damaged:
		return
	_smoke_timer -= delta
	if _smoke_timer <= 0.0:
		_smoke_timer = randf_range(0.35, 0.7)
		Fx.vehicle_smoke(global_position + Vector2(0, -6), _last_dir, hp < max_hp * 0.25)


func _add_oil_stain() -> void:
	var frames: SpriteFrames = AnimLibrary.effect_frames(
		"res://assets/z/effects/tank_oil", "tank_oil", 6.0)
	if frames == null or not frames.has_animation("fx"):
		return
	var stain := AnimatedSprite2D.new()
	stain.name = "OilStain"
	stain.sprite_frames = frames
	stain.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stain.frame = randi() % frames.get_frame_count("fx")
	stain.position = Vector2(0, 4)
	add_child(stain)
	move_child(stain, 1)
	stain.stop()


## Idle turrets rotate one sector per second (zod turrent_time_int);
## the APC scanner always spins, combat turrets track their target.
func _update_layer(delta: float) -> void:
	if _layer == null:
		return
	if not manned or not alive:
		_layer.visible = manned and alive
		return
	_layer.visible = true
	_turret_fire = maxf(0.0, _turret_fire - delta)
	# combat turrets track their target; everything else (and every idle
	# turret) rotates one sector per second — the APC scanner never stops
	var tracking := _target != null and is_instance_valid(_target) and _layer_scan
	if tracking:
		_scan_timer = 0.0
	else:
		_scan_timer += delta
		if _scan_timer >= SCAN_STEP_SECONDS:
			_scan_timer = 0.0
			_layer_dir = wrapi(_layer_dir + 1, 0, AnimLibrary.DIRECTIONS)
	if unit_name == "crane":
		_layer_dir = _last_dir
	_update_layer_transform()
	var anim := ("turretfire_%d" if _turret_fire > 0.0 else "turret_%d") % _layer_dir
	if unit_name == "crane":
		anim = "arm_%d" % _layer_dir
	if _layer.sprite_frames and _layer.sprite_frames.has_animation(anim):
		if _layer.animation != anim or not _layer.is_playing():
			_layer.play(anim)
			if not _layer.sprite_frames.get_animation_loop(anim):
				_layer.frame = _layer.sprite_frames.get_frame_count(anim) - 1
	if _hook:
		_hook.visible = true
		var hook := "hook"
		if _hook.sprite_frames.has_animation(hook):
			if _hook.animation != hook or not _hook.is_playing():
				_hook.play(hook)
		var hook_pos := Vector2(_layer_hull_off[_last_dir] if _layer_hull_off.size() == AnimLibrary.DIRECTIONS else Vector2.ZERO) \
			+ (_hook_off[_last_dir] if _hook_off.size() == AnimLibrary.DIRECTIONS else Vector2.ZERO)
		_hook.position = hook_pos


func _update_layer_transform() -> void:
	var hull_d := _last_dir
	var pos := Vector2.ZERO
	if _layer_canvas_off.size() == AnimLibrary.DIRECTIONS:
		pos += _layer_canvas_off[hull_d]
	if _layer_hull_off.size() == AnimLibrary.DIRECTIONS:
		pos += _layer_hull_off[hull_d]
	if _layer_aim_off.size() == AnimLibrary.DIRECTIONS:
		pos += _layer_aim_off[_layer_dir]
	_layer.position = pos


func _on_layer_finished() -> void:
	if _layer and _layer.animation == "pop":
		_layer.visible = false


func enter(robot: Unit2D) -> void:
	manned = true
	team = robot.team
	hp = maxi(hp, max_hp)  # fresh crew repairs
	_damaged = false
	_install_timer = 1.1  # gunner climbs aboard (place animation)
	if _hook:
		_hook.visible = true
	_build_frames()
	_play_body()
	_layer_dir = _last_dir


## Tanks have no wreck art: they explode (turret pops off, big blast)
## and remain as a burning damaged hull. Everyone else keeps their
## `wasted` sprite with looping fire/smoke.
func die() -> void:
	alive = false
	velocity = Vector2.ZERO
	set_selected(false)
	SelectionManager.drop_from_selection(self)
	remove_from_group("selectable")
	remove_from_group("units")
	Fx.destroyed(global_position)
	var has_wreck := sprite.sprite_frames \
		and sprite.sprite_frames.has_animation("wasted") \
		and sprite.sprite_frames.get_frame_count("wasted") > 0
	if _layer and _layer.sprite_frames and _layer.sprite_frames.has_animation("pop"):
		_layer.visible = true
		_layer.play("pop")  # turret flies off
	# passengers die with the transport
	for robot in cargo:
		if is_instance_valid(robot):
			robot.global_position = global_position
			robot.visible = true
			robot.die()
	cargo.clear()
	if has_wreck:
		sprite.play("wasted")
		ring.visible = false
		_add_wreck_fx()
	else:
		# tank: frozen last damaged hull frame + heavy smoke
		_wreck = true
		ring.visible = false
		_play_body()
		if _layer and _layer.sprite_frames and not _layer.sprite_frames.has_animation("pop"):
			_layer.visible = false


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


## Tank husks keep smoking until the end of the match.
func _update_wreck(delta: float) -> void:
	_smoke_timer -= delta
	if _smoke_timer <= 0.0:
		_smoke_timer = randf_range(0.4, 0.8)
		Fx.vehicle_smoke(global_position + Vector2(0, -6), _last_dir, true)
