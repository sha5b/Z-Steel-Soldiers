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

## Turret placement from the original DoRender tables — carried by the
## per-type scenes (scenes/vehicles/<name>.tscn), editable in the editor.
@export var turret_hull_off := PackedVector2Array()  # 8 entries
@export var turret_aim_off := PackedVector2Array()   # 8 entries
@export var turret_scans := true

var driver_type := ""  # robot type of the crew (for sniper ejections)
var _lid_timer := 0.0  # crew hatch open while firing — the snipe window

var _asset_dir := ""
# the layered rig lives in the base vehicle scene as pre-placed nodes
# (Wheels under the hull, Turret/Doors/Hook/Cones above it, under the
# selection ring) — per-type scenes set identity and turret offsets
@onready var _wheels: AnimatedSprite2D = get_node_or_null("Wheels")
@onready var _layer: AnimatedSprite2D = get_node_or_null("Turret")
@onready var _doors: AnimatedSprite2D = get_node_or_null("Doors")
@onready var _hook: AnimatedSprite2D = get_node_or_null("Hook")
@onready var _cones: AnimatedSprite2D = get_node_or_null("Cones")
var _wheel_offsets := PackedVector2Array()
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
var _repairing_building: Building2D = null
var _repair_tick_time := 0.0
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
	var anim := "open_%d" % _last_dir
	if _doors.sprite_frames.has_animation(anim):
		_doors.visible = true
		_doors.play(anim)


func _on_arrived() -> void:
	if is_apc() and not cargo.is_empty():
		unload()


func _ready() -> void:
	super._ready()
	if _doors != null and not _doors.animation_finished.is_connected(_on_doors_finished):
		_doors.animation_finished.connect(_on_doors_finished)
	if _layer != null and not _layer.animation_finished.is_connected(_on_layer_finished):
		_layer.animation_finished.connect(_on_layer_finished)


func _on_doors_finished() -> void:
	if is_instance_valid(_doors):
		_doors.visible = false


func setup_vehicle(vkind: String, type_name: String, owner_team: int) -> void:
	kind = vkind
	unit_name = type_name
	team = 0  # empty until manned; owner_team only records last holder
	manned = owner_team != 0
	if manned:
		team = owner_team
	_asset_dir = ContentDB.def_for(vkind, type_name).asset_dir


func _build_frames() -> void:
	if _asset_dir == "":
		if Engine.is_editor_hint():
			# autoloads don't run in the editor — derive the folder from the
			# naming convention so scene previews still build
			_asset_dir = AnimLibrary.asset_dir_for(kind, unit_name)
		else:
			_asset_dir = ContentDB.def_for(kind, unit_name).asset_dir
	# vehicles/cannons have no per-team walk cycle: empty / base / fire
	# (base switches to the damaged hull set below half HP)
	sprite.sprite_frames = AnimLibrary.vehicle_frames(_asset_dir, team, _damaged)
	if not sprite.animation_finished.is_connected(_on_anim_finished):
		sprite.animation_finished.connect(_on_anim_finished)
	# hull art mixes neutral (empty) and team paint — the palette swap is
	# a no-op on neutral pixels, so one material covers both states
	Teams.apply(sprite, team)
	Teams.apply(ring, team)
	_build_layer()
	# the rig nodes come from the scene — assign frames when present
	if _wheels != null:
		var wset: Dictionary = AnimLibrary.jeep_wheel_set(_asset_dir, team, manned)
		if not wset.is_empty():
			_wheel_offsets = wset.offsets
			_wheels.sprite_frames = wset.frames
			_wheels.stop()
			_wheels.frame = 0  # visible before the first move
			_sync_wheels()
	if _doors != null:
		var dset: Dictionary = AnimLibrary.apc_open_set(_asset_dir, team)
		if not dset.is_empty():
			_doors.sprite_frames = dset.frames
	# one-shot layers keep their build-time material — refresh the tint
	# for the current team (capture/eject swaps materials, not frames)
	if _doors:
		Teams.apply(_doors, team)
	if _cones:
		Teams.apply(_cones, team)


## The turret / gun layer for tanks, missile launchers, APC scanners and
## the jeep gunner; the crane gets its arm + hook pair instead. The nodes
## come from the scene; offsets come from the exported DoRender tables.
func _build_layer() -> void:
	if _layer == null:
		return
	var lset: Dictionary = {}
	if unit_name == "crane":
		lset = AnimLibrary.crane_set(_asset_dir)
	else:
		lset = AnimLibrary.turret_set(unit_name, _asset_dir, team)
	if lset.is_empty():
		_layer.visible = false
		return
	Teams.apply(_layer, team)  # neutral turret tops pass through untouched
	_layer_canvas_off = lset.get("canvas_off", PackedVector2Array())
	_layer_hull_off = turret_hull_off
	_layer_aim_off = turret_aim_off
	_layer_scan = turret_scans and unit_name != "crane"
	_layer.sprite_frames = lset.frames
	_layer.visible = manned
	if unit_name == "crane":
		_layer_dir = _last_dir
		if _hook != null and lset.frames.has_animation("hook"):
			_hook_off = lset.get("hook_off", PackedVector2Array())
			_hook.sprite_frames = lset.frames
			_hook.visible = false  # shown once manned
	_layer_dir = _last_dir


func _building_order(b: Building2D) -> void:
	var dist := global_position.distance_to(b.world_footprint().get_center())
	if unit_name == "crane" and manned and b.team == team \
			and b.hp < b.max_hp and dist < 60.0:
		_start_crane_repair(b)
		return
	if b.is_repair_shop() and b.owner_team == team and dist < 60.0:
		if b.try_start_repair(self):
			enter_target = null
			move_target = Vector2.ZERO
			waypoints = PackedVector2Array()
			return
		# shop busy or we're healthy: don't keep trying
		if hp >= max_hp or b.repair_unit != null:
			enter_target = null
			move_target = Vector2.ZERO
		return
	if dist < 44.0:
		enter_target = null
		move_target = Vector2.ZERO


func _start_crane_repair(b: Building2D) -> void:
	_repairing_building = b
	_repair_tick_time = 0.0
	enter_target = null
	move_target = Vector2.ZERO
	waypoints = PackedVector2Array()
	velocity = Vector2.ZERO
	_play_body()
	if _cones != null and _cones.sprite_frames == null:
		var frames := SpriteFrames.new()
		frames.add_animation("loop")
		frames.set_animation_speed("loop", 8.0)
		frames.set_animation_loop("loop", true)
		var tn := AnimLibrary.team_name(team)
		var i := 0
		while true:
			var path := "%s/effects/conco_%s_n%02d.png" % [_asset_dir, tn, i]
			if not ResourceLoader.exists(path):
				break
			frames.add_frame("loop", load(path))
			i += 1
		if i > 0:
			_cones.sprite_frames = frames
	if _cones:
		_cones.visible = true
		_cones.play("loop")


func _crane_repair_tick(delta: float) -> void:
	if _repairing_building == null:
		return
	var b := _repairing_building
	if not is_instance_valid(b) or not manned or not alive or not b.alive \
			or b.hp >= b.max_hp:
		_stop_crane_repair()
		return
	_repair_tick_time += delta
	if _repair_tick_time >= 0.4:
		_repair_tick_time = 0.0
		b.repair_by(40)
		if _hook and _hook.sprite_frames and _hook.sprite_frames.has_animation("hook"):
			_hook.frame = 0  # yank the hook
	if b.hp >= b.max_hp:
		_stop_crane_repair()


func _stop_crane_repair() -> void:
	_repairing_building = null
	if _cones:
		_cones.visible = false
		_cones.stop()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	voice_cooldown = maxf(0.0, voice_cooldown - delta)
	if _wreck:
		_update_wreck(delta)
		return
	if not alive:
		return
	_fire_timer = maxf(0.0, _fire_timer - delta)
	_fire_flash = maxf(0.0, _fire_flash - delta)
	_install_timer = maxf(0.0, _install_timer - delta)
	_lid_timer = maxf(0.0, _lid_timer - delta)
	if manned:
		_combat()
	_steer(delta)
	_separation(delta)
	_try_enter()
	_update_layer(delta)
	_damage_fx(delta)
	_crane_repair_tick(delta)
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
func _on_anim_finished() -> void:
	if alive and sprite.animation.begins_with("fire_"):
		# the flash played once — never hold or restart it
		_fire_flash = 0.0
		_play_body()
		return
	super._on_anim_finished()


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
		# a jeep that never moved has no animation set yet — frame 0 of
		# an empty animation renders nothing, so pick the facing first
		if _wheels.animation != wname:
			_wheels.animation = wname
		_wheels.stop()
		_wheels.frame = 0


func _combat() -> void:
	if attack_move and move_target != Vector2.ZERO and manned:
		var probe := _find_target()
		if probe != null:
			velocity = Vector2.ZERO
			_target = probe
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
			var gsound := ContentDB.def_for("robot", gname).sound
			Fx.gunfire(gsound if gsound != "" else "RIFLE3")
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
			_lid_timer = 1.2  # hatch open: snipers take note
			Fx.gunfire(ContentDB.def_for(kind, unit_name).sound)
			Fx.play("muzzle", global_position + to_target.normalized() * 12.0)
			var def := ContentDB.def_for(kind, unit_name)
			var amount := int(round(damage * GameState.vehicle_damage_mult(team)))
			var projectile := def.projectile
			var hit_chance := def.hit_chance
			var target := _target
			if projectile == null:
				# hitscan weapon: per-shot chance, instant damage, tracer
				if randf() <= hit_chance:
					Fx.bullet(global_position + to_target.normalized() * 10.0, target.global_position)
					target.take_damage(amount)
				else:
					Fx.bullet(global_position + to_target.normalized() * 10.0,
						target.global_position + Vector2(randf_range(-16.0, 16.0), randf_range(-16.0, 16.0)))
			else:
				# shell: damage lands when the shot arrives; explosive
				# weapons splash around the impact
				var tid := target.get_instance_id()
				var radius := def.splash_radius
				var impact: Vector2 = target.global_position
				Fx.shell(global_position + to_target.normalized() * 12.0,
					impact, projectile,
					func():
						var hit: Node2D = instance_from_id(tid) as Node2D
						if hit_chance >= 1.0 or randf() <= hit_chance:
							if hit and hit.alive:
								hit.take_damage(amount)
						if radius > 0.0:
							Fx.area_damage(impact, radius, int(amount * 0.5), team))


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
	stain.scale = Vector2(2, 2)  # the unit baseline — was rendering 1x
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
	if _hook and _hook.sprite_frames:
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


## Crew hatch: opens for a moment whenever the gun fires — the window
## where a sniper can pick the driver off (original lid logic).
var lid_open: bool:
	get:
		return _lid_timer > 0.0


## A sniper killed the crew: the hardware goes neutral again and a
## wounded survivor bails out (original: DoDriverHitEffect + eject).
func eject_driver() -> void:
	if not manned or alive == false:
		return
	Fx.play("spark", global_position)
	if driver_type != "":
		var map := get_parent()
		if map is Node2D:
			var survivor := Spawner.spawn(map, "robot", driver_type, team,
				global_position + Vector2(0, 18)) as Unit2D
			if survivor:
				survivor.hp = maxi(1, int(survivor.max_hp / 3.0))
	manned = false
	team = 0
	driver_type = ""
	hp = maxi(hp, int(max_hp / 2.0))
	_damaged = hp < max_hp * 0.5
	if is_apc():
		unload()
	_build_frames()
	_play_body()
	if _layer:
		_layer.visible = false
func enter(robot: Unit2D) -> void:
	manned = true
	team = robot.team
	driver_type = robot.unit_name
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
	var fx_name: String = "big_smoke" if unit_name == "heavy" \
			else ["fire", "fire0", "fire1"].pick_random()
	var folder := "big_smoke" if fx_name == "big_smoke" else "fire"
	var frames := AnimLibrary.effect_frames(
		"res://assets/z/effects/%s" % folder, fx_name, 8.0)
	if frames == null or not frames.has_animation("fx"):
		return
	frames.set_animation_loop("fx", true)
	var fx := AnimatedSprite2D.new()
	fx.name = "WreckFx"
	fx.sprite_frames = frames
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.scale = Vector2(2, 2)  # the unit baseline — was rendering 1x
	fx.position = Vector2(0, -6)
	add_child(fx)
	fx.play("fx")


## Tank husks keep smoking until the end of the match.
func _update_wreck(delta: float) -> void:
	_smoke_timer -= delta
	if _smoke_timer <= 0.0:
		_smoke_timer = randf_range(0.4, 0.8)
		Fx.vehicle_smoke(global_position + Vector2(0, -6), _last_dir, true)
