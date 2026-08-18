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

var garrison: Array[Node] = []
var _missile_timer := 0.0
var _missile_target: Node2D = null


func kind_key() -> String:
	return "fort"


func producer_key() -> String:
	return "fort"


func produce_seconds() -> float:
	return PRODUCE_SECONDS * build_time_mult()


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
	SelectionManager.drop_from_selection(robot)
	return true


func _process(delta: float) -> void:
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
	var tid := best.get_instance_id()
	var impact: Vector2 = best.global_position
	Fx.shell(from, impact, GARRISON_MISSILE,
		func():
			var hit: Node2D = instance_from_id(tid) as Node2D
			if hit and hit.alive:
				hit.take_damage(20)
			Fx.area_damage(impact, 40.0, 10, team))


## The fort falling kills everyone inside.
func kill_garrison() -> void:
	for robot in garrison:
		if is_instance_valid(robot):
			robot.carried = false
			robot.die()
	garrison.clear()
