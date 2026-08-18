class_name Commands
extends Object
## Order dispatch for the current selection: formation move orders, and
## the Z-style special targets — ordering robots onto an empty
## vehicle/cannon mans it once they walk up; onto a friendly manned APC
## loads them as passengers.


static func dispatch(world_position: Vector2) -> void:
	# a selected producing building: right-click sets its rally point
	var selected := SelectionManager.selected
	if selected.size() == 1 and is_instance_valid(selected[0]) 			and selected[0] is Building2D and selected[0].alive 			and (selected[0].is_fort or selected[0] is RobotFactory or selected[0] is VehicleFactory) 			and selected[0].owner_team == GameState.player_team:
		selected[0].set_rally(world_position)
		Fx.ui_click()
		return
	var empty_vehicle := _find_empty_vehicle(world_position)
	var apc := _find_apc(world_position)
	var movers: Array[Node] = []
	for u in SelectionManager.selected:
		if is_instance_valid(u) and u is Unit2D and u.alive:
			movers.append(u)
	# deterministic order (instance ids) so formations don't reshuffle
	movers.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	for i in movers.size():
		var u: Node2D = movers[i]
		if u.kind == "robot":
			if empty_vehicle and is_instance_valid(empty_vehicle):
				u.move_to(empty_vehicle.global_position)
				u.enter_target = empty_vehicle
				continue
			if apc and is_instance_valid(apc) and u.team == apc.team:
				u.move_to(apc.global_position)
				u.enter_target = apc
				continue
		var ring := maxi(int(sqrt(float(movers.size()))), 1)
		var offset := Vector2((i % ring) - (ring - 1) * 0.5, (i / ring) - (ring - 1) * 0.5) * 20.0
		u.move_to(world_position + offset)


static func _find_apc(world_position: Vector2) -> Vehicle2D:
	for v in Engine.get_main_loop().root.get_tree().get_nodes_in_group("units"):
		if v is Vehicle2D and v.is_apc() and v.manned and v.alive and v.team != 0 \
				and v.global_position.distance_to(world_position) < 24.0:
			return v
	return null


static func _find_empty_vehicle(world_position: Vector2) -> Node2D:
	for v in Engine.get_main_loop().root.get_tree().get_nodes_in_group("units"):
		if v is Vehicle2D and not v.manned and v.alive \
				and v.global_position.distance_to(world_position) < 24.0:
			return v
	return null
