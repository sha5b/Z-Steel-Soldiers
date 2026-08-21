@tool
class_name Unit2D
extends CharacterBody2D
## Z (1996) robot unit: 16x16 original sprites, 8 baked directions.
## Auto-engages enemies in range; dies with a random original death
## animation; celebrates a win. Sprites/stats come from ContentDB and
## AnimLibrary — see docs/ASSET_CONVENTIONS.md to add unit types.

@export var unit_name := "grunt"
@export var team := 1
@export var sprite_scale := 1.0  # ORIGINAL SCALE: everything renders at native art px (a robot = one 16px tile, like the buildings' 1:1 art)
@export var kind := "robot"  # robot | vehicle | cannon

const GRENADE: ProjectileDef = preload("res://content/projectiles/grenade.tres")

signal died(unit: Node)
signal damaged(amount: int)

var net_id := 0  # stable per-match identity for multiplayer intents
				 # (assigned by the registry at track time; spawn order)

enum State { IDLE, MOVING, ENTERING, GESTURE, DEAD }

## Boarding reach. CONTACT_REACH is the normal "walked right up to it"
## distance; STRANDED_REACH is how far a finished walk may still be from
## hardware parked on a cell nobody can stand on (a fort tower mount is
## one or two cells inside the wall) before the order is abandoned.
const CONTACT_REACH := 16.0
const STRANDED_REACH := 52.0

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
## Where this unit is walking. Vector2.INF means NO ORDER — the same
## explicit sentinel defend_post and rally_point use. It used to be
## Vector2.ZERO, which is a REAL position: a unit sent to the world
## origin was indistinguishable from a unit with nothing to do, and
## every "is it moving?" test in the codebase was that comparison.
## Read it through has_move_target(); write it through _begin_move /
## clear_move_target().
var move_target := Vector2.INF
var waypoints := PackedVector2Array()
var enter_target: Node2D = null
var _idle_time := 0.0
var _flavoring := false
var _entering: Node2D = null  # vehicle being boarded (enter_apc gesture)
var _enter_timer := 0.0
var carried := false
var grenades := 0  # throwable grenades from crates (original grenade_item)
## VETERANCY: confirmed kills, and the rank they buy. A veteran hits
## harder and more often (MatchRulesDef.veteran_*) — the roster used to
## carry no rank or XP field at all. Ranks are read through rank() so
## the thresholds live in the rules resource, not in the entity.
var kills := 0


## 0 = rookie. One rank per kill step reached.
func rank() -> int:
	var steps: Array = ContentDB.rules.veteran_kill_steps
	var r := 0
	for step in steps:
		if kills >= int(step):
			r += 1
	return r


## Damage/accuracy the rank is worth (1.0 = rookie).
func veteran_damage_scale() -> float:
	return 1.0 + rank() * ContentDB.rules.veteran_damage_bonus


func veteran_hit_bonus() -> float:
	return rank() * ContentDB.rules.veteran_hit_bonus


## One confirmed kill. Promotion is silent for everyone but the player,
## who hears the bark and sees the rank pips on the selection ring.
func credit_kill() -> void:
	if not alive:
		return
	var before := rank()
	kills += 1
	if rank() > before and team == MatchState.current.player_team:
		_play_voice("acknowledge")
var _grenade_timer := 0.0
var attack_move := false  # AGRO order: stop and fight en route
var attack_target: Node2D = null  # ATTACK order: chase THIS until it dies
var defend_post := Vector2.INF  # DEFEND order: hold this spot
var run_stamina := 1.0  # 0..1, sprinting drains it (original max_run_time)
var _run_flag := false  # sprint the current order (shift-click)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var ring: Node2D = $SelectionRing


func _ready() -> void:
	if Engine.is_editor_hint():
		_build_frames()
		_play("stand", 4)
		return
	add_to_group(Groups.SELECTABLE)
	add_to_group(Groups.UNITS)
	if not Engine.is_editor_hint():
		SelectionManager.current.listen(self)
		UnitRegistry.current.track(self)
	var stats := ContentDB.stats_for(kind, unit_name)
	hp = stats.hp
	max_hp = stats.hp
	damage = stats.damage
	range_px = stats.range_px
	cooldown = stats.cooldown
	speed = stats.speed
	scale = Vector2(sprite_scale, sprite_scale)
	collision_layer = 1
	collision_mask = 2  # physics solves unit-vs-BUILDING only
	_build_frames()


## Structural deregistration: whatever frees a unit (death, the
## save-restore roster swap, map teardown), the roster never keeps a
## dangling reference. die() additionally runs the elimination check —
## freeing without dying must NOT eliminate a team.
func _exit_tree() -> void:
	if UnitRegistry.current:
		UnitRegistry.current.forget(self)
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
	_chase(delta)
	_try_enter()
	if kind == "robot":
		if GameSettings.auto_idle and defend_post == Vector2.INF:
			_smart_idle(delta)
		_return_to_post()
		_idle(delta)
	ring.queue_redraw()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or carried or not alive:
		return
	_steer(delta)
	_separation(delta)


var _stuck_timer := 0.0
var _last_pos := Vector2.ZERO
var _repaths := 0


## REAL collision can pin a unit against a wall (corner hugs, crowds in
## the fort gate): when it strives but makes no ground, re-route from
## where it actually stands; after three re-routes, give the order up —
## a cancelled move beats a permanently jammed army.
## Does this unit have a destination? (See move_target — never compare
## it to a position yourself.)
func has_move_target() -> bool:
	return move_target != Vector2.INF


## Drop the destination: arrival, cancellation, boarding, death.
func clear_move_target() -> void:
	move_target = Vector2.INF


func _progress_watchdog(delta: float) -> void:
	if velocity.length_squared() < 4.0 or not has_move_target():
		_stuck_timer = 0.0
		return
	if global_position.distance_to(_last_pos) < 0.5:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0
	_last_pos = global_position
	if _stuck_timer > 0.7:
		_stuck_timer = 0.0
		_repaths += 1
		if _repaths > 3:
			_repaths = 0
			_arrive()
		else:
			waypoints = NavWorld.current.request_path(
				global_position, move_target, kind)


## THE movement engine — one implementation for robots and vehicles
## (Vehicle2D used to carry a copy that drifted: arrivals stopped arming
## defend posts and clearing orders for hardware). Per-type differences
## live in the hook methods below.
func _steer(delta: float) -> void:
	if has_move_target():
		var next: Vector2 = waypoints[0] if not waypoints.is_empty() else move_target
		var offset := next - global_position
		if offset.length() <= (6.0 if not waypoints.is_empty() else 8.0):
			if not waypoints.is_empty():
				waypoints.remove_at(0)
			else:
				_arrive()
		else:
			velocity = offset.normalized() * speed * _run_multiplier(delta)
	if not has_move_target():
		_run_flag = false
	run_stamina = minf(1.0, run_stamina + delta * 0.08)
	if velocity.length_squared() > 1.0:
		_last_dir = _angle_to_dir(velocity.angle())
		_play_move()
		var dist_before := offset_to_next_waypoint()
		# the final leg has no waypoint — offset_to_next_waypoint is INF
		# there, so capture it separately
		var final_before: float = global_position.distance_to(move_target) \
				if has_move_target() else INF
		# REAL collision (modern engine, no grid-only limits): the slide
		# follows the A* route and pushes back off building walls — the
		# corner-cutting that steered units through solid cells is gone
		var prev_pos := global_position
		if TestLevers.direct_step:
			global_position += velocity * delta
		else:
			move_and_slide()  # real collision — slides along building walls
		_on_stepped(prev_pos.distance_to(global_position))
		# a large step can leapfrog the waypoint (the arrival check
		# above only looks before moving): if we are now farther away
		# than before the step, we passed it — consume it. UNLESS the
		# step hit a wall: sliding along a building also increases
		# the distance, and consuming then sent the beeline straight
		# across the wall corner (units jammed against factories)
		var slid_into_wall := not TestLevers.direct_step \
				and get_last_slide_collision() != null
		if not slid_into_wall:
			if not waypoints.is_empty():
				if global_position.distance_to(waypoints[0]) > dist_before:
					waypoints.remove_at(0)
			elif has_move_target() \
					and global_position.distance_to(move_target) > final_before:
				# same for the FINAL leg: without this a fast unit
				# ping-pongs around the 4px arrival radius forever
				# (exposed by building orders that resolve on arrival)
				_arrive()
		global_position = global_position.clamp(
			NavWorld.current.map_rect.position, NavWorld.current.map_rect.end)
		_progress_watchdog(delta)
	else:
		_play_idle()
	_steer_tail()


# --------- locomotion hooks: robot defaults, Vehicle2D overrides ---------

## Sprint multiplier while running (robots: double time on stamina).
func _run_multiplier(delta: float) -> float:
	if _run_flag and run_stamina > 0.05:
		run_stamina = maxf(0.0, run_stamina - delta * 0.2)
		return 1.6  # double time (original run)
	return 1.0


func _play_move() -> void:
	_play("walk", _last_dir)


func _play_idle() -> void:
	_play("fire" if _target else "stand", _last_dir)


## Called with the step length after each actual move (vehicles stamp
## track decals every TRACK_SPACING of ground).
func _on_stepped(_step: float) -> void:
	pass


## Tail of the steering tick (vehicles sync their wheel layer).
func _steer_tail() -> void:
	pass


## Per-type arrival extras (vehicles unload APC cargo).
func _on_arrived_extras() -> void:
	pass


## Arrival (reached, leapfrogged, or given up) — ONE implementation:
## clear the move state, arm a DEFEND post when the order was DEFEND,
## land IDLE; an order with a target (ENTERING) keeps waiting on
## _try_enter to act.
func _arrive() -> void:
	clear_move_target()
	velocity = Vector2.ZERO
	# an ATTACK order outlives arrival: _chase re-routes while the target
	# lives, and only its death ends the order
	if enter_target == null and attack_target == null:
		if order != null and order.type == Order.Type.DEFEND:
			defend_post = global_position  # hold this spot
		state = State.IDLE
		order = null
		_advance_order_queue()  # next leg of a queued chain, if there is one
	_on_arrived_extras()


func offset_to_next_waypoint() -> float:
	if waypoints.is_empty():
		return INF
	return global_position.distance_to(waypoints[0])


## Keep units from piling into one spot: push nearby units apart a little
## every frame (zod robots shoulder each other aside while walking).
func _separation(delta: float) -> void:
	var push := Vector2.ZERO
	for u in UnitRegistry.current.world_units():
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
	if not _walkable(target) or _inside_building(target):
		# never shove units into water/rock/WALLS: the cell check alone
		# misses sub-cell overlaps — the shoulder push used to bury
		# bodies inside building physics rects, freezing them
		if _walkable(Vector2(target.x, global_position.y)) \
				and not _inside_building(Vector2(target.x, global_position.y)):
			target = Vector2(target.x, global_position.y)
		elif _walkable(Vector2(global_position.x, target.y)) \
				and not _inside_building(Vector2(global_position.x, target.y)):
			target = Vector2(global_position.x, target.y)
		else:
			return
	global_position = target
	global_position = global_position.clamp(
		NavWorld.current.map_rect.position, NavWorld.current.map_rect.end)


## True when the body box overlaps a nav-solid cell of the kind's OWN
## grid — the building walls ARE those cells. Probes center, edge
## midpoints and corners at the per-kind half-extent (6px probes once
## missed that 16x16 vehicle hulls shave into walls). Nine grid
## lookups, no geometry, no allocations: this runs per unit per physics
## tick and MUST stay cheap (the first version walked every building's
## footprint and cost the whole frame budget).
func _inside_building(p: Vector2) -> bool:
	return not NavWorld.current.body_clear(
		p, NavWorld.current.BODY_HALF.get(kind, 7.0), kind)


func _walkable(p: Vector2) -> bool:
	return not NavWorld.current.solid_at(p, kind)


## How often an idle robot says something (per idle-flavour trigger).
const CHATTER_CHANCE := 0.12


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
		# the robots BANTER when they have nothing to do (the pack's
		# unlabelled voice bank — Fx.chatter, player team only so the
		# map's far corners stay quiet)
		if team == MatchState.current.player_team and randf() < CHATTER_CHANCE:
			Fx.chatter()
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
	if attack_move and has_move_target():
		# AGRO order: halt and engage anything in range, resume after
		var probe := _find_target()
		if probe != null:
			velocity = Vector2.ZERO
			_target = probe
	if velocity.length_squared() > 4.0:
		return  # no fire-and-move yet
	_grenade_timer = maxf(0.0, _grenade_timer - get_process_delta_time())
	_target = _ordered_or_nearest()
	# throwable grenades: lobbed automatically at hardware and forts
	# within reach (original: robots throw grenades at vehicles/guns)
	if grenades > 0 and _target and _grenade_timer <= 0.0 \
			and (_target is Vehicle2D or (_target is Building2D and _target.is_fort)) \
			and global_position.distance_to(_target_point()) < 80.0:
		_grenade_timer = 3.0
		grenades -= 1
		play_gesture("throw")
		var g_impact: Vector2 = _target_point()  # the node is the fort's art TOP edge
		Fx.gunfire("GRENLOBX")
		ShellSolver.deliver(self, global_position, g_impact, GRENADE,
			func():
				Combat.area_damage(g_impact, 30.0, 133, team, true))  # grenade_damage 40/240 r30, x0.08
		return
	if _target and _fire_timer <= 0.0:
		var to_target := _target_point() - global_position
		if to_target.length() <= range_px * sprite_scale:
			_last_dir = _angle_to_dir(to_target.angle())
			_fire_timer = cooldown
			_shoot(_target, to_target)


## Where shots measure to: a building's footprint centre, a unit's body
## (fort nodes sit at the art TOP edge — measuring to the node made
## forts unreachable inside every weapon's range).
func _target_point() -> Vector2:
	if _target is Building2D:
		return _target.visual_center()
	return _target.global_position


## An explicit ATTACK order outranks opportunistic targeting: a unit told
## to kill something must not drift onto whatever wandered closer.
func _ordered_or_nearest() -> Node2D:
	if attack_target != null and is_instance_valid(attack_target) \
			and attack_target.alive:
		var aim: Vector2 = attack_target.visual_center() \
				if attack_target is Building2D else attack_target.global_position
		if global_position.distance_to(aim) <= range_px * sprite_scale:
			return attack_target
	return _find_target()


func _find_target() -> Node2D:
	return _find_target_within(range_px * sprite_scale)


## Nearest enemy unit from the registry, then enemy buildings in reach —
## forts AND the destructible factories/radar/repair (bridges are
## neutral and never shot at).
func _find_target_within(eff_range: float) -> Node2D:
	var best: Node2D = UnitRegistry.current.nearest_enemy(
		global_position, eff_range, team)
	var best_d: float = global_position.distance_to(best.global_position) \
			if best != null else eff_range
	var structure := BuildingRegistry.nearest_enemy(global_position, best_d, team)
	return structure if structure != null else best


## Robot weapons: per-shot HIT CHANCE (original zsettings), SNIPING —
## a lucky shot through an open lid kills the driver and re-empties the
## hardware — and missile weapons splash around the impact. Lasers are
## hitscan with a beam flash; everything else is a tracer.
func _shoot(target: Node2D, to_target: Vector2) -> void:
	_play("fire", _last_dir, true)
	var def := ContentDB.def_for(kind, unit_name)
	var muzzle := global_position + to_target.normalized() * 6.0
	var amount := damage
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


## How badly hurt a robot has to be before it shouts, and how long it
## then keeps quiet. Without the gate a squad under sustained fire talks
## over itself every frame.
const DISTRESS_AT := 0.6
const DISTRESS_GAP := 9.0
var _distress_quiet_until := 0.0


func take_damage(amount: int) -> void:
	if not alive:
		return
	hp -= amount
	damaged.emit(amount)
	_maybe_call_for_help()
	if ring:
		ring.visible = true
		ring.queue_redraw()
	# rapid-fire attackers restart this every hit — only start a new
	# flash when the previous one has fully faded (building.gd rule)
	if modulate == Color.WHITE:
		modulate = Color(3, 3, 3)
		var tween := create_tween()
		tween.tween_property(self, "modulate", Color.WHITE, 0.15)
	if hp <= 0:
		die()
	elif kind == "robot" and amount >= max_hp * 0.05 and alive:
		# a solid hit scrambles the robot aside (original: DodgeMissile —
		# ratio-based: raw damage thresholds died with the 10000-scale
		# rebalance, grunt hits are 1 and laser hits are 14)
		# validated scramble: the old center-cell check teleported robots
		# INTO building walls, where move_and_slide pinned them for good
		var spot := NavWorld.current.find_free_spot(global_position
			+ Vector2(randf_range(-14.0, 14.0), randf_range(-14.0, 14.0)), kind)
		# the LEAP matches where it lands: the original ships four
		# directional jump-* animations for exactly this (they were in no
		# animation table at all, so a dodge always played the plain
		# `dodge` frames)
		play_gesture(_leap_gesture(spot - global_position if spot != Vector2.INF
			else Vector2.ZERO))
		if spot != Vector2.INF:
			global_position = spot


## Which dodge animation a scramble plays: the leap the art shows in
## that direction, or the plain `dodge` frames when it goes nowhere.
## Screen space, so up/down beat left/right only when the move is mostly
## vertical.
static func _leap_gesture(delta_pos: Vector2) -> String:
	if delta_pos.length() < 2.0:
		return "dodge"
	if absf(delta_pos.y) > absf(delta_pos.x):
		return "jump-down" if delta_pos.y > 0.0 else "jump-up"
	return "jump-right" if delta_pos.x > 0.0 else "jump-left"


func die() -> void:
	alive = false
	state = State.DEAD
	UnitRegistry.current.untrack(self)
	died.emit(self)
	velocity = Vector2.ZERO
	set_selected(false)
	SelectionManager.current.drop_from_selection(self)
	remove_from_group(Groups.SELECTABLE)
	remove_from_group(Groups.UNITS)
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


## QUEUED ORDERS (ctrl+right-click). Orders wait in a FIFO and the next
## one starts the moment the current one finishes — the standard RTS
## waypoint chain, and the only way to route a squad around a chokepoint
## instead of through it. A plain click still wipes the queue, so the
## habit of clicking once and being obeyed is unchanged.
const MAX_QUEUED_ORDERS := 8
var order_queue: Array[Order] = []
## How close counts as "already standing on the post" for a DEFEND
## order — hold position arms the ground under the unit's feet.
const HOLD_REACH := 10.0


## Single order intake for players (Commands), the AI (CpuAi) and tests —
## nothing outside may write move_target/enter_target/attack_move.
## Three intents pass through here: STOP cancels, a QUEUED order joins
## the tail, anything else starts now and clears the tail.
func issue_order(new_order: Order) -> void:
	if not alive or carried:
		return
	if new_order.type == Order.Type.STOP:
		halt()
		return
	if new_order.queued and not _is_at_rest():
		if order_queue.size() < MAX_QUEUED_ORDERS:
			order_queue.append(new_order)
			if team == MatchState.current.player_team:
				# mark the waypoint NOW: a chain you cannot see is a chain
				# you cannot build (the red dotted path only ever shows the
				# leg being walked)
				PathIndicator.show_marker(get_parent(),
					_queued_anchor(new_order), new_order.confirm_marker())
		else:
			Fx.cap_denied()  # the chain is full: say so instead of nothing
		return
	order_queue.clear()
	_begin_order(new_order)


## Where a queued order will take the unit — its destination, or the
## thing it is about to walk to.
static func _queued_anchor(o: Order) -> Vector2:
	if o.target != null and is_instance_valid(o.target):
		return o.target.global_position
	return o.position


## STOP: drop the order, the queue, the chase and the post, and stand
## still. Everything a cancel has to release is released here — the queue
## included, or a halted unit would sit on a chain nothing advances.
func halt() -> void:
	if not alive or carried:
		return
	order_queue.clear()
	waypoints = PackedVector2Array()
	velocity = Vector2.ZERO
	_target = null
	_run_flag = false
	defend_post = Vector2.INF
	_order_done()


## True while we are pulling the next leg out of the queue, so the
## _order_done inside _begin_order cannot re-enter this.
var _advancing := false


## Start the next queued order, if any. Called from the ONE place an
## order ends (_order_done) and from arrival, so a chain advances
## whatever ended it — arrival, failure, or a dead target.
func _advance_order_queue() -> void:
	if _advancing or not alive or carried:
		return
	_advancing = true
	while not order_queue.is_empty():
		var next: Order = order_queue.pop_front()
		# a leg whose target died while we walked the previous one is
		# skipped, not attempted against a corpse
		if next.target != null and (not is_instance_valid(next.target) \
				or not next.target.get("alive")):
			continue
		_begin_order(next)
		break
	_advancing = false


func _begin_order(new_order: Order) -> void:
	# a REAL command is a fresh start: forget what smart idle already
	# tried, so a unit the player moves elsewhere may self-task again
	if not _auto_issuing:
		_auto_tried.clear()
	_idle_seconds = 0.0
	order = new_order
	_run_flag = order.run
	_flavoring = false
	_idle_time = 0.0
	_entering = null
	defend_post = Vector2.INF
	attack_target = null
	if order.type == Order.Type.ATTACK:
		attack_move = false
		enter_target = null
		attack_target = order.target
		_chase_repath()
		state = State.MOVING
	elif order.type == Order.Type.DEFEND \
			and global_position.distance_to(order.position) <= HOLD_REACH:
		# HOLD POSITION: the post IS the ground under our feet. Pathing to
		# your own position returns an empty route, which drops the order
		# and arms nothing — so arm it here and stay put.
		attack_move = false
		enter_target = null
		waypoints = PackedVector2Array()
		clear_move_target()
		velocity = Vector2.ZERO
		defend_post = global_position
		state = State.IDLE
		order = null
		if team == MatchState.current.player_team:
			PathIndicator.show_marker(get_parent(), global_position, "placed")
	elif order.type == Order.Type.MOVE or order.type == Order.Type.MOVE_ATTACK 			or order.type == Order.Type.DEFEND:
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
		# per-match identity: a multiplayer resync reconciles BY net id
		# (a save restore ignores it — the roster respawns from scratch)
		"net": net_id, "carried": carried, "kills": kills,
	}


func apply_dict(d: Dictionary) -> void:
	hp = int(d.get("hp", hp))
	grenades = int(d.get("grenades", 0))
	kills = int(d.get("kills", 0))  # a veteran stays a veteran
	_last_dir = wrapi(int(d.get("dir", _last_dir)), 0, AnimLibrary.DIRECTIONS)


## Idle = alive, not hidden in an APC, no order in flight AND nothing
## queued behind it. The AI and the idle-flavour system share this one
## definition, so a unit part-way through a waypoint chain still has
## work and neither may steal it.
func is_idle() -> bool:
	return alive and not carried and state == State.IDLE \
			and order_queue.is_empty()


## Compat wrapper: plain move order without building an Order by hand.
func move_to(world_pos: Vector2, sprint := false) -> void:
	issue_order(Order.move(world_pos, sprint))


func _order_anchor() -> Vector2:
	if order.target is Building2D:
		return (order.target as Building2D).world_footprint().get_center()
	return order.target.global_position


func _begin_move(world_pos: Vector2) -> void:
	waypoints = NavWorld.current.request_path(global_position, world_pos, kind)
	if waypoints.is_empty():
		clear_move_target()  # unreachable (e.g. water for vehicles)
		state = State.IDLE
	else:
		# THE DESTINATION IS THE END OF THE ROUTE, not the requested point.
		# request_path routes to the nearest cell the kind can actually
		# occupy, and snaps its last breadcrumb onto `world_pos` only when
		# that final approach is clear. Aiming move_target at the raw
		# request instead made ANY order into a solid cell unarrivable:
		# a robot sent to a fort (the anchor is the footprint CENTRE,
		# which is wall) pressed into the gate's dead end forever, since
		# _arrive never fired and _try_enter waits on move_target being
		# cleared. Garrisoning then depended on the stuck watchdog, which
		# never tripped because sliding in the corridor still counts as
		# making ground.
		move_target = waypoints[waypoints.size() - 1]
		state = State.MOVING
		if waypoints.size() > 1 and global_position.distance_to(waypoints[0]) < 10.0:
			waypoints.remove_at(0)  # don't step back to the start cell centre
	if team == MatchState.current.player_team:
		play_gesture("point")
		_play_voice("acknowledge")
		PathIndicator.show_path(get_parent(), waypoints,
			order.confirm_marker() if order != null else "placed")


## Order finished or superseded — one clear point instead of scattered
## field resets. Every failure path funnels here so the unit always
## lands back in a retaskable IDLE (a robot ordered onto something it
## can't use used to stick in ENTERING forever, invisible to the AI).
func _order_done() -> void:
	enter_target = null
	attack_target = null
	_chase_anchor = Vector2.INF
	clear_move_target()
	order = null
	state = State.IDLE
	attack_move = false
	_advance_order_queue()


## Man/load the assigned vehicle once actually adjacent to it.
## Ordered onto a BUILDING: vehicles act on it (repair shop / crane
## work); robots garrison their OWN fort, and any other building order
## resolves on ARRIVAL — the robot walks up first, then goes idle.
func _try_enter() -> void:
	# GODOT TRAP: a FREED instance compares == null. An enter target that
	# DIED mid-walk cancels the whole errand — the bot stops and becomes
	# retaskable instead of finishing its march to the corpse's spot.
	# (enter_target == null is the NORMAL state of every plain move
	# order — that case must do nothing.)
	if enter_target != null and (not is_instance_valid(enter_target) \
			or not enter_target.alive):
		enter_target = null
		clear_move_target()
		waypoints = PackedVector2Array()
		velocity = Vector2.ZERO
		_order_done()
		return
	if enter_target == null:
		return
	if enter_target is Building2D:
		# _steer clears move_target on arrival while enter_target keeps
		# the ENTERING state alive — that is the arrival signal here
		if not has_move_target():
			_building_order(enter_target)
		return
	# Hardware standing on a SOLID cell can never be reached at contact
	# distance: fort tower guns mount inside the walls, and a hull can
	# die wedged against a factory. request_path() then routes to the
	# nearest OPEN cell instead and the robot arrives as close as the
	# map allows — so once the walk is over (move_target cleared by
	# _arrive), board from arm's length. Without this the robot sat in
	# ENTERING forever: is_idle() false, so neither the player's auto-man
	# nor the AI ever retasked it, and a sniped tower gun stayed derelict
	# for the rest of the match.
	var gap := global_position.distance_to(enter_target.global_position)
	if gap > CONTACT_REACH:
		if has_move_target():
			return  # still walking
		if gap > STRANDED_REACH:
			_order_done()  # genuinely out of reach: be retaskable again
			return
	var v := enter_target
	enter_target = null
	if v is Vehicle2D and v.alive:
		if not v.manned and _entering == null:
			SelectionManager.current.drop_from_selection(self)
			clear_move_target()
			velocity = Vector2.ZERO
			_entering = v
			_enter_timer = 0.0
			play_gesture("enter_apc")  # boards when the anim finishes
		elif v.is_apc() and v.team == team:
			v.load_robot(self)


## ATTACK order upkeep: close on the target, hold at weapon range, and
## re-route whenever it has moved far enough that our route is stale.
## The order ends only when the target dies — that is what makes an
## attack FOLLOW instead of walking to a stale position.
const CHASE_REPATH := 28.0  # target drift that invalidates our route
var _chase_anchor := Vector2.INF


func _chase(_delta: float) -> void:
	if attack_target == null:
		return
	if not is_instance_valid(attack_target) or not attack_target.alive:
		attack_target = null
		_chase_anchor = Vector2.INF
		_order_done()
		return
	var aim: Vector2 = attack_target.visual_center() \
			if attack_target is Building2D else attack_target.global_position
	var reach := range_px * sprite_scale
	if global_position.distance_to(aim) <= reach:
		# in range: stop and shoot. _combat locks onto attack_target.
		clear_move_target()
		waypoints = PackedVector2Array()
		velocity = Vector2.ZERO
		_chase_anchor = aim
		return
	if _chase_anchor == Vector2.INF or aim.distance_to(_chase_anchor) > CHASE_REPATH \
			or not has_move_target():
		_chase_repath()


func _chase_repath() -> void:
	if attack_target == null or not is_instance_valid(attack_target):
		return
	var aim: Vector2 = attack_target.visual_center() \
			if attack_target is Building2D else attack_target.global_position
	_chase_anchor = aim
	var was := state
	_begin_move(aim)
	if not has_move_target():
		# unreachable (water, walled in): keep the order but do not spin
		state = was
	else:
		state = State.MOVING


## Smart idle (GameSettings.auto_idle, the T toggle): a robot standing
## around with nothing to do mans a nearby empty hull or walks onto a
## capturable flag, the way the original's idle robots do.
##
## THE RULE THIS MUST NEVER BREAK: it may only ever act on a unit that is
## doing nothing, and it may never take an action twice. It used to break
## both halves. The guard checked `move_target` but not `waypoints`, so a
## unit between two legs of a path counted as idle; and it re-tried every
## 1.5s forever, so a unit whose auto-target was unreachable re-issued
## the same order for the rest of the match — which looks exactly like
## "the unit just stops moving and ignores me".
##
## So: one attempt per target, ever. A target it failed to reach is
## remembered and never picked again, and any real order the player gives
## wipes that memory (a fresh command means a fresh start).
const AUTO_RADIUS := 110.0
## Stand still THIS long before self-tasking. A convenience for units
## nobody is commanding must never look like it cancelled an order.
const AUTO_IDLE_DELAY := 3.0
var _idle_seconds := 0.0
var _auto_tried := {}       # instance id / zone -> already attempted
var _auto_issuing := false  # true while WE issue, so issue_order can tell


## Is this unit genuinely at rest? `waypoints` is the one the old guard
## missed: a multi-leg path empties `move_target` between legs.
func _is_at_rest() -> bool:
	return not has_move_target() and waypoints.is_empty() and order == null \
			and state == State.IDLE and _entering == null and order_queue.is_empty() \
			and enter_target == null and attack_target == null and not carried


func _smart_idle(delta: float) -> void:
	if not _is_at_rest():
		_idle_seconds = 0.0
		return
	_idle_seconds += delta
	if _idle_seconds < AUTO_IDLE_DELAY:
		return
	# an empty hull to crew, nearest first
	for v in UnitRegistry.current.world_units():
		if not (v is Vehicle2D) or v.manned or not v.alive:
			continue
		if _auto_tried.has(v.get_instance_id()):
			continue
		if global_position.distance_to(v.global_position) >= AUTO_RADIUS:
			continue
		_auto_tried[v.get_instance_id()] = true
		_auto_order(Order.for_target(v))
		return
	# else a flag we could walk onto — presence is what captures
	for z: Zone in MatchState.current.zones:
		if z.owner_team == team or _auto_tried.has(z):
			continue
		if z.world_rect().has_point(global_position):
			continue
		var center := z.world_rect().get_center()
		if global_position.distance_to(center) < AUTO_RADIUS:
			_auto_tried[z] = true
			_auto_order(Order.move(center))
			return


## Issue an order the UNIT decided on, not the player. Flagged so
## issue_order keeps the try-once memory instead of clearing it.
func _auto_order(o: Order) -> void:
	_auto_issuing = true
	issue_order(o)
	_auto_issuing = false


## THE ROBOTS CALL FOR HELP. The original barks a distress line at the
## player when one of their units is being shot at ("we're under attack",
## "help", "they're all over us") — ours took hits in total silence, so a
## fight off-screen announced itself with nothing at all. Player team
## only, and only once the unit is genuinely hurt.
func _maybe_call_for_help() -> void:
	if kind != "robot" or not alive or team != MatchState.current.player_team:
		return
	if float(hp) / float(maxi(max_hp, 1)) > DISTRESS_AT:
		return
	var now := float(Time.get_ticks_msec()) / 1000.0
	if now < _distress_quiet_until:
		return
	_distress_quiet_until = now + DISTRESS_GAP
	Fx.distress()
	Fx.ping(global_position)  # and the radar shows WHERE they are shouting from


## DEFEND stance: a unit pushed off its post walks back and re-holds it.
func _return_to_post() -> void:
	if defend_post == Vector2.INF or not is_idle():
		return
	if global_position.distance_to(defend_post) > 36.0:
		issue_order(Order.move_defend(defend_post))


## Robots ordered onto their OWN fort walk in and garrison it
## (original: ENTER_FORT_WP); any other building order resolves as a
## walk-up-and-stop — through _order_done so the robot is idle again.
func _building_order(b: Building2D) -> void:
	if b is FortBuilding and b.team == team and b.alive \
			and global_position.distance_to(b.world_footprint().get_center()) < 56.0:
		if b.garrison_robot(self):
			# ALIVE but carried: the fort holds the real node. It used to
			# queue_free() here, which left the garrison array full of
			# freed entries — the missile battery then fired forever with
			# no crew, kill_garrison() became a no-op, garrison_cap
			# counted ghosts, and the defenders vanished from the
			# no-units rule that is supposed to count them.
			_order_done()
			return
	_order_done()


func portrait_path() -> String:
	match kind:
		"robot":
			# r270 = facing the camera (south, toward the viewer). No
			# `stand_null` art ships, so a team-0 robot would get a blank
			# portrait — Teams.palette never returns 0 for a real team,
			# so borrow team 1's set for the neutral case.
			var tn := AnimLibrary.team_name(team if team > 0 else 1)
			var path := "res://assets/z/robots/stand_%s_r270.png" % tn
			return path if ResourceLoader.exists(path) else ""
		"cannon", "vehicle":
			# the original names hull art three different ways and only
			# 3 of 11 hardware types ship `empty_r270` — probing that one
			# path left 8 types with a blank selection portrait. ONE
			# fallback walk, shared with the production panel's icons.
			return ProductionPanel.hardware_art(kind, unit_name)
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
			player.bus = GameSettings.SFX_BUS  # volume slider lives on the bus
			player.stream = load(path)
			add_child(player)
			player.finished.connect(player.queue_free)
			player.play()
			return


func set_selected(value: bool) -> void:
	selected = value
	ring.visible = value or hp < max_hp
	ring.queue_redraw()
	if value and team == MatchState.current.player_team and alive and not carried:
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
