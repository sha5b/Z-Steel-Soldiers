@tool
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

const GRENADE: ProjectileDef = preload("res://content/projectiles/grenade.tres")

signal died(unit: Node)
signal damaged(amount: int)

enum State { IDLE, MOVING, ENTERING, GESTURE, DEAD }

var state := State.IDLE
var order: Order = null
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
var _entering: Node2D = null  # vehicle being boarded (enter_apc gesture)
var _enter_timer := 0.0
var carried := false
var grenades := 0  # throwable grenades from crates (original grenade_item)
var _grenade_timer := 0.0
var attack_move := false  # AGRO order: stop and fight en route
var run_stamina := 1.0  # 0..1, sprinting drains it (original max_run_time)
var _run_flag := false  # sprint the current order (shift-click)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var ring: Node2D = $SelectionRing


func _ready() -> void:
	if Engine.is_editor_hint():
		_build_frames()
		_play("stand", 4)
		return
	add_to_group("selectable")
	add_to_group("units")
	if not Engine.is_editor_hint():
		SelectionManager.listen(self)
		UnitRegistry.track(self)
	var stats := ContentDB.stats_for(kind, unit_name)
	hp = stats.hp
	max_hp = stats.hp
	damage = stats.damage
	range_px = stats.range_px
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
## animation from the shared zod folders — already in the unit's team
## colours (the original per-team art variants).
func _build_frames() -> void:
	sprite.sprite_frames = AnimLibrary.robot_frames(unit_name, team)
	if not sprite.animation_finished.is_connected(_on_anim_finished):
		sprite.animation_finished.connect(_on_anim_finished)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or carried:
		return
	voice_cooldown = maxf(0.0, voice_cooldown - delta)
	if not alive:
		return
	_fire_timer = maxf(0.0, _fire_timer - delta)
	if _entering != null:
		_enter_timer += delta
		if _enter_timer > 0.9:  # gesture missing or signal never came
			_finish_entering()
	_combat()
	_steer(delta)
	_separation(delta)
	_try_enter()
	if kind == "robot":
		_auto_enter()
		_idle(delta)
	ring.queue_redraw()


func _steer(delta: float) -> void:
	if move_target != Vector2.ZERO:
		var next: Vector2 = waypoints[0] if not waypoints.is_empty() else move_target
		var offset := next - global_position
		if offset.length() <= (6.0 if not waypoints.is_empty() else 8.0):
			if not waypoints.is_empty():
				waypoints.remove_at(0)
			else:
				_arrive_at_target()
		else:
			velocity = offset.normalized() * speed
			if _run_flag and run_stamina > 0.05:
				velocity *= 1.6  # double time (original run)
				run_stamina = maxf(0.0, run_stamina - delta * 0.2)
	if move_target == Vector2.ZERO:
		_run_flag = false
	run_stamina = minf(1.0, run_stamina + delta * 0.08)
	if velocity.length_squared() > 1.0:
		_last_dir = _angle_to_dir(velocity.angle())
		_play("walk", _last_dir)
		var dist_before := offset_to_next_waypoint()
		# the final leg has no waypoint — offset_to_next_waypoint is INF
		# there, so capture it separately
		var final_before: float = global_position.distance_to(move_target) \
				if move_target != Vector2.ZERO else INF
		global_position += velocity * delta
		# a large step can leapfrog the waypoint (the arrival check
		# above only looks before moving): if we are now farther away
		# than before the step, we passed it — consume it
		if not waypoints.is_empty():
			if global_position.distance_to(waypoints[0]) > dist_before:
				waypoints.remove_at(0)
		elif move_target != Vector2.ZERO \
				and global_position.distance_to(move_target) > final_before:
			# same for the FINAL leg: without this a fast unit ping-pongs
			# around the 4px arrival radius forever (exposed by building
			# orders that resolve on arrival)
			_arrive_at_target()
		global_position = global_position.clamp(
			NavWorld.map_rect.position, NavWorld.map_rect.end)
	else:
		_play("fire" if _target else "stand", _last_dir)


## Final destination reached (or leapfrogged): clear the move state; an
## order with a target (ENTERING) keeps waiting on _try_enter to act.
func _arrive_at_target() -> void:
	move_target = Vector2.ZERO
	velocity = Vector2.ZERO
	if enter_target == null:
		state = State.IDLE
		order = null


func offset_to_next_waypoint() -> float:
	if waypoints.is_empty():
		return INF
	return global_position.distance_to(waypoints[0])


## Keep units from piling into one spot: push nearby units apart a little
## every frame (zod robots shoulder each other aside while walking).
func _separation(delta: float) -> void:
	var push := Vector2.ZERO
	for u in UnitRegistry.world_units():
		if u == self or not (u is Unit2D) or not u.alive or u.carried:
			continue
		var d: Vector2 = global_position - u.global_position
		var dist := d.length()
		if dist < 14.0 and dist > 0.01:
			push += (d / dist) * (14.0 - dist)
		elif dist <= 0.01:
			push += Vector2(randf() - 0.5, randf() - 0.5)  # perfectly stacked
	var step := push * clampf(delta * 6.0, 0.0, 1.0) * 0.5
	var target := global_position + step
	if not _walkable(target):
		# never shove units into water/rock: try axes separately, else stay
		if _walkable(Vector2(target.x, global_position.y)):
			target = Vector2(target.x, global_position.y)
		elif _walkable(Vector2(global_position.x, target.y)):
			target = Vector2(global_position.x, target.y)
		else:
			return
	global_position = target
	global_position = global_position.clamp(
		NavWorld.map_rect.position, NavWorld.map_rect.end)


func _walkable(p: Vector2) -> bool:
	var grid := NavWorld.vehicle_grid if kind != "robot" else NavWorld.nav_grid
	if grid == null:
		return true
	var cell := Vector2i((p / 16.0).floor())
	if not grid.region.has_point(cell):
		return false
	return not grid.is_point_solid(cell)


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
		var anim := "%s_%d" % [flavor, _last_dir]
		if not sprite.sprite_frames or not sprite.sprite_frames.has_animation(anim):
			anim = "%s_0" % flavor
		if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim) \
				and sprite.sprite_frames.get_frame_count(anim) > 0:
			sprite.play(anim)
		else:
			_flavoring = false


## One-shot contextual animation (point, pickup-*, enter_apc...).
## Directional gestures pick the current facing; plain ones run as-is.
func play_gesture(gesture: String) -> void:
	if not alive or carried:
		return
	var anim := "%s_%d" % [gesture, _last_dir]
	if not sprite.sprite_frames or not sprite.sprite_frames.has_animation(anim):
		anim = "%s_0" % gesture
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim) \
			and sprite.sprite_frames.get_frame_count(anim) > 0:
		_flavoring = true
		_idle_time = 0.0
		if state == State.IDLE:
			state = State.GESTURE
		sprite.play(anim)


func _combat() -> void:
	if attack_move and move_target != Vector2.ZERO:
		# AGRO order: halt and engage anything in range, resume after
		var probe := _find_target()
		if probe != null:
			velocity = Vector2.ZERO
			_target = probe
	if velocity.length_squared() > 4.0:
		return  # no fire-and-move yet
	_grenade_timer = maxf(0.0, _grenade_timer - get_process_delta_time())
	_target = _find_target()
	# throwable grenades: lobbed automatically at hardware and forts
	# within reach (original: robots throw grenades at vehicles/guns)
	if grenades > 0 and _target and _grenade_timer <= 0.0 \
			and (_target is Vehicle2D or (_target is Building2D and _target.is_fort)) \
			and global_position.distance_to(_target.global_position) < 80.0:
		_grenade_timer = 3.0
		grenades -= 1
		play_gesture("throw")
		var g_impact: Vector2 = _target.global_position
		Fx.gunfire("GRENLOBX")
		Fx.shell(global_position, g_impact, GRENADE,
			func():
				Combat.area_damage(g_impact, 34.0, 26, team, true))
		return
	if _target and _fire_timer <= 0.0:
		var to_target := _target.global_position - global_position
		if to_target.length() <= range_px * sprite_scale:
			_last_dir = _angle_to_dir(to_target.angle())
			_fire_timer = cooldown
			_shoot(_target, to_target)


func _find_target() -> Node2D:
	# nearest enemy unit from the registry, then enemy forts in range
	var best: Node2D = UnitRegistry.nearest_enemy(
		global_position, range_px * sprite_scale, team)
	var best_d: float = global_position.distance_to(best.global_position) \
			if best != null else range_px * sprite_scale
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is Node2D and b.alive and b.team != 0 and b.team != team:
			var d: float = global_position.distance_squared_to(b.visual_center())
			if d < best_d * best_d:
				best_d = sqrt(d)
				best = b
	return best


## Robot weapons: per-shot HIT CHANCE (original zsettings), SNIPING —
## a lucky shot through an open lid kills the driver and re-empties the
## hardware — and missile weapons splash around the impact. Lasers are
## hitscan with a beam flash; everything else is a tracer.
func _shoot(target: Node2D, to_target: Vector2) -> void:
	_play("fire", _last_dir, true)
	var def := ContentDB.def_for(kind, unit_name)
	var muzzle := global_position + to_target.normalized() * 10.0
	var amount := int(round(damage * MatchState.robot_damage_mult(team)))
	# the lid over a tank's crew hatch opens while it fires — that is the
	# window a marksman takes (original: can_be_sniped = lid_open)
	if def.snipe_chance > 0.0 and target is Vehicle2D and target.manned \
			and target.lid_open and randf() < def.snipe_chance:
		Fx.laser(muzzle, target.global_position) \
			if def.weapon == "laser" else Fx.bullet(muzzle, target.global_position)
		Fx.play("muzzle", muzzle)
		target.eject_driver()
		return
	Combat.fire(self, def, muzzle, target, amount)


func take_damage(amount: int) -> void:
	if not alive:
		return
	hp -= amount
	damaged.emit(amount)
	if ring:
		ring.visible = true
		ring.queue_redraw()
	modulate = Color(3, 3, 3)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.15)
	if hp <= 0:
		die()
	elif kind == "robot" and amount >= 10 and alive:
		# near-miss scrambles the robot aside (original: DodgeMissile)
		play_gesture("dodge")
		var sidestep := Vector2(randf_range(-14.0, 14.0), randf_range(-14.0, 14.0))
		if _walkable(global_position + sidestep):
			global_position += sidestep


func die() -> void:
	alive = false
	state = State.DEAD
	UnitRegistry.untrack(self)
	died.emit(self)
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


func _finish_entering() -> void:
	var v := _entering
	_entering = null
	if v != null and is_instance_valid(v) and v.alive and not v.manned:
		v.enter(self)
		queue_free()
		return
	# vehicle lost mid-gesture: robot stays put


func _on_anim_finished() -> void:
	if not alive and sprite.animation == "die":
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 0.8)
		tween.tween_callback(queue_free)
	elif sprite.animation.begins_with("fire_"):
		# the muzzle flash is a one-shot: straight back to standing
		_play("stand", _last_dir)
	elif _entering != null and sprite.animation.begins_with("enter_apc"):
		_finish_entering()
	elif _flavoring:
		_flavoring = false
		_idle_time = 0.0
		if state == State.GESTURE:
			state = State.IDLE


## Single order intake for players (Commands), the AI (CpuAi) and tests —
## nothing outside may write move_target/enter_target/attack_move.
func issue_order(new_order: Order) -> void:
	if not alive or carried:
		return
	order = new_order
	_run_flag = order.run
	_flavoring = false
	_idle_time = 0.0
	_entering = null
	if order.type == Order.Type.MOVE or order.type == Order.Type.MOVE_ATTACK:
		attack_move = order.type == Order.Type.MOVE_ATTACK
		enter_target = null
		_begin_move(order.position)
	else:
		attack_move = false
		enter_target = order.target
		_begin_move(_order_anchor())
		state = State.ENTERING  # supersedes MOVING: walking WITH a target

## ---- save contract ----

func to_dict() -> Dictionary:
	return {
		"kind": kind, "type": unit_name, "team": team,
		"x": global_position.x, "y": global_position.y, "hp": hp,
		"dir": _last_dir, "grenades": grenades,
	}


func apply_dict(d: Dictionary) -> void:
	hp = int(d.get("hp", hp))
	grenades = int(d.get("grenades", 0))
	_last_dir = wrapi(int(d.get("dir", _last_dir)), 0, AnimLibrary.DIRECTIONS)


## Idle = alive, not hidden in an APC, no order in flight. The AI and
## the idle-flavour system share this one definition.
func is_idle() -> bool:
	return alive and not carried and state == State.IDLE


## Compat wrapper: plain move order without building an Order by hand.
func move_to(world_pos: Vector2, sprint := false) -> void:
	issue_order(Order.move(world_pos, sprint))


func _order_anchor() -> Vector2:
	if order.target is Building2D:
		return (order.target as Building2D).world_footprint().get_center()
	return order.target.global_position


func _begin_move(world_pos: Vector2) -> void:
	move_target = world_pos
	waypoints = NavWorld.request_path(global_position, world_pos, kind)
	if waypoints.is_empty():
		move_target = Vector2.ZERO  # unreachable (e.g. water for vehicles)
		state = State.IDLE
	else:
		state = State.MOVING
		if waypoints.size() > 1 and global_position.distance_to(waypoints[0]) < 10.0:
			waypoints.remove_at(0)  # don't step back to the start cell centre
	if team == MatchState.player_team:
		play_gesture("point")
		_play_voice("acknowledge")
		PathIndicator.show_path(get_parent(), waypoints)


## Order finished or superseded — one clear point instead of scattered
## field resets. Every failure path funnels here so the unit always
## lands back in a retaskable IDLE (a robot ordered onto something it
## can't use used to stick in ENTERING forever, invisible to the AI).
func _order_done() -> void:
	enter_target = null
	move_target = Vector2.ZERO
	order = null
	state = State.IDLE
	attack_move = false


## Man/load the assigned vehicle once actually adjacent to it.
## Ordered onto a BUILDING: vehicles act on it (repair shop / crane
## work); robots garrison their OWN fort, and any other building order
## resolves on ARRIVAL — the robot walks up first, then goes idle.
func _try_enter() -> void:
	# GODOT TRAP: a FREED instance compares == null, so this one guard
	# covers null, freed and dead targets — an ENTERING order whose
	# target is gone resolves back to retaskable idle (robots used to
	# stick in ENTERING forever when their target died mid-walk)
	if enter_target == null or not is_instance_valid(enter_target) \
			or not enter_target.alive:
		enter_target = null
		if state == State.ENTERING:
			_order_done()
		return
	if enter_target is Building2D:
		# _steer clears move_target on arrival while enter_target keeps
		# the ENTERING state alive — that is the arrival signal here
		if move_target == Vector2.ZERO:
			_building_order(enter_target)
		return
	if global_position.distance_to(enter_target.global_position) > 16.0:
		return
	var v := enter_target
	enter_target = null
	if v is Vehicle2D and v.alive:
		if not v.manned and _entering == null:
			SelectionManager.drop_from_selection(self)
			move_target = Vector2.ZERO
			velocity = Vector2.ZERO
			_entering = v
			_enter_timer = 0.0
			play_gesture("enter_apc")  # boards when the anim finishes
		elif v.is_apc() and v.team == team:
			v.load_robot(self)


## Idle robots automatically hop into empty hardware standing next to
## them (original: WithinAutoEnterRadius) — a fresh crew for any gun or
## vehicle left unattended at their feet.
func _auto_enter() -> void:
	if move_target != Vector2.ZERO or _entering != null or enter_target != null:
		return
	for v in UnitRegistry.world_units():
		if v is Vehicle2D and not v.manned and v.alive \
				and global_position.distance_to(v.global_position) < 36.0:
			enter_target = v
			return


## Robots ordered onto their OWN fort walk in and garrison it
## (original: ENTER_FORT_WP); any other building order resolves as a
## walk-up-and-stop — through _order_done so the robot is idle again.
func _building_order(b: Building2D) -> void:
	if b is FortBuilding and b.team == team and b.alive \
			and global_position.distance_to(b.world_footprint().get_center()) < 56.0:
		if b.garrison_robot(self):
			queue_free()  # the garrison list remembers the stats we need
			return
	_order_done()


func portrait_path() -> String:
	match kind:
		"robot":
			# r270 = facing the camera (south, toward the viewer)
			return "res://assets/z/robots/stand_%s_r270.png" % AnimLibrary.team_name(team)
		"cannon", "vehicle":
			return "%s/empty_r270.png" % ContentDB.def_for(kind, unit_name).asset_dir
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
		"selected":
			# per-type voice where the original shipped one
			paths.append("res://assets/z/sounds/selected_%s.wav" % unit_name)
			for i in 6:
				paths.append("res://assets/z/sounds/selected_%02d.wav" % i)
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
	if value and team == MatchState.player_team and alive and not carried:
		_play_voice("selected")


## `fallback` names the anim to keep showing when `anim` has no art
## (tanks fire through their turret, so the hull keeps its base cycle).
func _play(anim: String, dir: int, once := false, fallback := "") -> void:
	var anim_name := "%s_%d" % [anim, dir]
	if sprite.sprite_frames and not sprite.sprite_frames.has_animation(anim_name) \
			and fallback != "" and sprite.sprite_frames.has_animation("%s_%d" % [fallback, dir]):
		anim_name = "%s_%d" % [fallback, dir]
	if once and sprite.sprite_frames:
		sprite.stop()
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim_name):
		# finished one-shots (gunner install) hold their last frame —
		# restarting them would loop the install animation forever
		var restarts: bool = sprite.animation != anim_name \
				or not sprite.is_playing() and sprite.sprite_frames.get_animation_loop(anim_name)
		if restarts:
			sprite.play(anim_name)
	elif sprite.is_playing():
		sprite.stop()


## Zod DirectionFromLoc: sector of atan2 (y-down) + PI/8, mapped so the
## direction index runs counter-clockwise — dir d loads sprite r{d*45}:
## r000 faces east (+X), r090 north (up), r180 west, r270 south (down).
static func _angle_to_dir(angle: float) -> int:
	var a := angle
	if a < 0.0:
		a += TAU
	a += PI / 8.0
	return wrapi(8 - int(a / (PI / 4.0)), 0, AnimLibrary.DIRECTIONS)
