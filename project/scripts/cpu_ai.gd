class_name CpuAi
extends Node
## Simple Z-flavoured opponent: spreads idle units to capture zones, then
## pushes for the enemy fort once strong. Busy units are never re-ordered
## (that made them wander frantically).

const THINK_SECONDS := [6.0, 4.0, 2.5]   # by difficulty
const ATTACK_UNITS := [12, 7, 5]

var team := 2
var _accum := 0.0
var _zone_claims: Dictionary = {}  # zone node -> unit assigned


func _init(cpu_team: int = 2) -> void:
	team = cpu_team


func _process(delta: float) -> void:
	if GameState.over:
		return
	_accum += delta
	if _accum < THINK_SECONDS[clampi(GameState.ai_difficulty, 0, 2)]:
		return
	_accum = 0.0
	_think()


func _think() -> void:
	var units := _own_units()
	if units.is_empty():
		return
	_prune_claims()
	var zones := GameState.zones
	var not_ours: Array[Node] = []
	var ours := 0
	for z in zones:
		if z.owner_team == team:
			ours += 1
		else:
			not_ours.append(z)

	# strong enough (or map half taken): everyone who is idle rushes the fort
	if units.size() >= ATTACK_UNITS[clampi(GameState.ai_difficulty, 0, 2)] or ours >= zones.size() - 1:
		var fort := _enemy_fort()
		if fort:
			var center := fort.visual_center()
			var idle := units.filter(func(u): return u.move_target == Vector2.ZERO and u.enter_target == null)
			var ring := int(sqrt(float(idle.size())))
			for i in idle.size():
				var u: Node2D = idle[i]
				u.move_to(center + Vector2(
					((i % ring) - (ring - 1) * 0.5) * 18.0,
					((i / ring) - (ring - 1) * 0.5) * 18.0))
			return

	# otherwise: each idle unit without a live claim walks to the nearest
	# unclaimed zone we don't own, and stays until it flips
	var idle2 := units.filter(func(u): return u.move_target == Vector2.ZERO and u.enter_target == null)
	for u in idle2:
		if _zone_claims.values().has(u):
			continue
		var best_zone: Node = null
		var best_d := INF
		for z in not_ours:
			if _zone_claims.has(z):
				continue
			var zc := _zone_center(z)
			var d: float = u.global_position.distance_squared_to(zc)
			if d < best_d:
				best_d = d
				best_zone = z
		if best_zone:
			_zone_claims[best_zone] = u
			u.move_to(_zone_center(best_zone))


func _prune_claims() -> void:
	for z in _zone_claims.keys():
		var u = _zone_claims[z]  # untyped: may hold a freed instance
		var stale: bool = (not is_instance_valid(u)) or (not u.alive) \
			or z.owner_team == team  # captured — release the claim
		if stale:
			_zone_claims.erase(z)


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
