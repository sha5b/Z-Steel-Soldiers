class_name FortBuilding
extends Building2D
## The fort: fixed team (the map owner), the win objective, a full
## producer (robots/vehicles/cannons per its level) — and a garrison:
## robots ordered inside man the fort's own missile launcher (original:
## ENTER_FORT_WP + fort turret missiles), just like the original game's
## screaming fort defenses.

const PRODUCE_SECONDS := 8.0
const GARRISON_MISSILE_RANGE := 180.0
const GARRISON_MISSILE: ProjectileDef = preload(
	"res://content/projectiles/garrison_missile.tres")
const GARRISON_MISSILE_COOLDOWN := 3.0
const GARRISON_CAP := 5

# Cannon mount slots, in fort-ART pixels from the art's top-left (each
# variant's two inner towers flanking the gate + the two outer corner
# towers). Manufactured guns MOUNT here, one per slot — no unlimited
# turret spam (the original's tower guns; zod stores max 4 built cannons
# per producer). Slot guns spawn MANNED: tower cells are solid, a robot
# could never walk up to crew them.
const SLOTS_FRONT := [Vector2(38, 80), Vector2(122, 80),
	Vector2(10, 26), Vector2(150, 26)]
const SLOTS_BACK := [Vector2(40, 64), Vector2(120, 64),
	Vector2(10, 14), Vector2(150, 14)]

var garrison: Array[Node] = []
var _missile_timer := 0.0
var _missile_target: Node2D = null
var slot_cannons: Array = []  # slot index -> manned cannon (or null)


func kind_key() -> String:
	return "fort"


func producer_key() -> String:
	return "fort"


## Tower mount points in WORLD px for this fort's art variant.
func cannon_slots() -> Array:
	var tex: String = ContentDB.building_def(building_id).tex \
		if ContentDB.building_def(building_id) != null else "fort_front"
	var art: Array = SLOTS_BACK if tex == "fort_back" else SLOTS_FRONT
	var origin: Vector2 = art_world_rect().position
	var out: Array = []
	for off in art:
		out.append(origin + Vector2(off))
	return out


func _ready() -> void:
	super()
	slot_cannons.resize(cannon_slots().size())


## Free mount slots, counting cannons already mounted and cannons still
## in the production queue.
func free_cannon_slots() -> int:
	var slots := cannon_slots()
	var free := slots.size()
	for i in slot_cannons.size():
		var mounted = slot_cannons[i]
		if mounted == null:
			continue
		if is_instance_valid(mounted) and mounted.alive \
				and mounted.global_position.distance_to(slots[i]) < 48.0:
			free -= 1
		else:
			slot_cannons[i] = null  # died or moved off: mount is free again
	for item in queue.items:
		if String(item).begins_with("cannon:"):
			free -= 1
	return maxi(free, 0)


func queue_unit(item: String, silent := false) -> bool:
	if item.begins_with("cannon:") and free_cannon_slots() == 0:
		if not silent:
			Fx.cap_denied()  # every tower mount is taken or queued
		return false
	return super(item, silent)


func spawn_produced(item: String) -> void:
	var parts := item.split(":")
	if parts.size() == 2 and parts[0] == "cannon":
		var slots := cannon_slots()
		for i in slots.size():
			var mounted = slot_cannons[i] if i < slot_cannons.size() else null
			if mounted != null and is_instance_valid(mounted) and mounted.alive:
				continue
			slot_cannons[i] = Spawner.spawn(get_parent(), "cannon", parts[1],
				owner_team, slots[i], true)
			if owner_team == MatchState.player_team:
				Fx.announce("gun_manufactured")
			return
	super(item)  # no free mount after all: fall back to spawning beside


## The fort falling kills its tower guns with it.
func _death_visuals() -> void:
	super()
	for i in slot_cannons.size():
		var mounted = slot_cannons[i]
		slot_cannons[i] = null
		if mounted != null and is_instance_valid(mounted) and mounted.alive:
			mounted.take_damage(1000000)




## A robot walks in: hide it, it fights (and hides) from inside.
func garrison_robot(robot: Unit2D) -> bool:
	if team == 0 or team != robot.team or garrison.size() >= GARRISON_CAP:
		return false
	garrison.append(robot)
	robot.carried = true
	robot.set_selected(false)
	robot.visible = false
	robot.velocity = Vector2.ZERO
	robot.move_target = Vector2.ZERO
	robot.waypoints = PackedVector2Array()
	robot.remove_from_group("selectable")
	robot.remove_from_group("units")
	SelectionManager.current.drop_from_selection(robot)
	return true


func _process(delta: float) -> void:
	if not alive:
		return  # ruins produce nothing and fire nothing
	tick_production(delta)
	if team != 0 and not garrison.is_empty():
		_garrison_fire(delta)


## The fort's own missile battery: fires while crewed (garrisoned) at
## the nearest enemy in reach.
func _garrison_fire(delta: float) -> void:
	_missile_timer = maxf(0.0, _missile_timer - delta)
	if _missile_timer > 0.0:
		return
	var best: Node2D = null
	var best_d := GARRISON_MISSILE_RANGE * GARRISON_MISSILE_RANGE
	for u in get_tree().get_nodes_in_group("units"):
		if u is Node2D and u is Unit2D and u.alive and not u.carried \
				and u.team != 0 and u.team != team \
				and visual_center().distance_squared_to(u.global_position) < best_d:
			best_d = visual_center().distance_squared_to(u.global_position)
			best = u
	if best == null:
		return
	_missile_timer = GARRISON_MISSILE_COOLDOWN
	_missile_target = best
	Fx.gunfire("MOBIMIS")
	var from := visual_center() + Vector2(0, -10)
	var impact: Vector2 = best.global_position
	Fx.shell(from, impact, GARRISON_MISSILE,
			func():
				# ONE roll with falloff (combat.gd rule) — a direct hit
				# plus splash double-charged the primary target
				Combat.area_damage(impact, 40.0, 167, team, true))  # map_item_turrent_damage 50/240, x0.08


## The fort falling kills everyone inside.
func kill_garrison() -> void:
	for robot in garrison:
		if is_instance_valid(robot):
			robot.carried = false
			robot.die()
	garrison.clear()
