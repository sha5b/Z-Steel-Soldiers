class_name MatchRelay
extends Object
## Routes one replicated multiplayer intent to its single intake
## (Net owns transport; this is the application side). Entities are
## addressed by per-match net id — instance ids differ across peers.


static func apply(intent: Dictionary) -> void:
	match str(intent.get("kind", "")):
		"order":
			var u := _unit(int(intent.get("unit", 0)))
			if u == null or not u.alive:
				return
			u.issue_order(_order(intent))
		"queue":
			var f := _building(int(intent.get("fac", 0)))
			if f != null and f.alive and f.owner_team == int(intent.get("team", 0)):
				f.queue_unit(String(intent.get("item", "")), false)
		"rally":
			var f := _building(int(intent.get("fac", 0)))
			if f != null and f.alive and f.owner_team == int(intent.get("team", 0)):
				f.set_rally(Vector2(float(intent.get("x", 0.0)), float(intent.get("y", 0.0))))


static func _order(intent: Dictionary) -> Order:
	var o := Order.new()
	o.type = int(intent.get("otype", 0)) as Order.Type
	o.position = Vector2(float(intent.get("x", 0.0)), float(intent.get("y", 0.0)))
	o.run = bool(intent.get("run", false))
	var tid := int(intent.get("target", 0))
	if tid != 0:
		o.target = _entity(tid)
	return o


static func _unit(id: int) -> Unit2D:
	return UnitRegistry.current.by_net_id(id) if UnitRegistry.current else null


static func _building(id: int) -> Building2D:
	if Engine.get_main_loop().root == null:
		return null
	for b in Engine.get_main_loop().root.get_tree().get_nodes_in_group(Groups.ALL_BUILDINGS):
		if b is Building2D and b.net_id == id:
			return b
	return null


static func _entity(id: int) -> Node2D:
	var u := _unit(id)
	if u != null:
		return u
	return _building(id)
