class_name CpuAi
extends Node
## Simple Z-flavoured opponent: spread units to capture zones, then push
## for the enemy fort once strong. Thinks on a fixed interval.

const THINK_SECONDS := 2.5
const ATTACK_UNITS := 7

var team := 2
var _accum := 0.0


func _init(cpu_team: int = 2) -> void:
	team = cpu_team


func _process(delta: float) -> void:
	if GameState.over:
		return
	_accum += delta
	if _accum < THINK_SECONDS:
		return
	_accum = 0.0
	_think()


func _think() -> void:
	var units := _own_units()
	if units.is_empty():
		return
	var zones := GameState.zones
	var not_ours: Array[Node] = []
	var ours := 0
	for z in zones:
		if z.owner_team == team:
			ours += 1
		else:
			not_ours.append(z)

	# strong enough (or map half taken): rush the enemy fort
	if units.size() >= ATTACK_UNITS or ours >= zones.size() - 1:
		var fort := _enemy_fort()
		if fort:
			var center := fort.global_position + fort.size * 0.5
			var ring := int(sqrt(float(units.size())))
			for i in units.size():
				var u: Node2D = units[i]
				u.move_target = center + Vector2(
					((i % ring) - (ring - 1) * 0.5) * 18.0,
					((i / ring) - (ring - 1) * 0.5) * 18.0)
			return

	# otherwise: send each idle-ish unit to the nearest zone we don't own
	var assignable := units.duplicate()
	assignable.shuffle()
	for z in not_ours:
		if assignable.is_empty():
			break
		var zc := _zone_center(z)
		var nearest: Node2D = assignable[0]
		for u2 in assignable:
			if u2.global_position.distance_squared_to(zc) < nearest.global_position.distance_squared_to(zc):
				nearest = u2
		assignable.erase(nearest)
		nearest.move_target = zc + Vector2(randf_range(-40, 40), randf_range(-40, 40))


func _own_units() -> Array[Node]:
	var out: Array[Node] = []
	for u in get_tree().get_nodes_in_group("units"):
		if u is Node2D and u.alive and u.team == team and u.kind == "robot":
			out.append(u)
	return out


func _enemy_fort() -> FortBuilding:
	var best: FortBuilding = null
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is FortBuilding and b.alive and b.team != team and b.team != 0:
			best = b
	return best


static func _zone_center(z: Node) -> Vector2:
	return z.position + z.world_rect().get_center()
