class_name Commands
extends Object
## Order dispatch for the current selection: formation move orders, and
## the Z-style special targets — ordering robots onto an empty
## vehicle/cannon mans it once they walk up; onto a friendly manned APC
## loads them as passengers.


static func dispatch(world_position: Vector2) -> void:
	# a selected producing building: right-click sets its rally point
	var selected := SelectionManager.selected
	if selected.size() == 1 and is_instance_valid(selected[0]) 			and selected[0] is Building2D and selected[0].alive 			and (selected[0].is_fort or selected[0] is RobotFactory or selected[0] is VehicleFactory) 			and selected[0].owner_team == MatchState.player_team:
		selected[0].set_rally(world_position)
		Fx.ui_click()
		return
	var empty_vehicle := _find_empty_vehicle(world_position)
	var apc := _find_apc(world_position)
	var target_building := _find_interactable_building(world_position)
	var own_fort := _find_own_fort(world_position)
	var movers: Array[Node] = []
	for u in SelectionManager.selected:
		if is_instance_valid(u) and u is Unit2D and u.alive:
			movers.append(u)
	# the stance (A/D/W hotkeys or the stance bar) decides what a move
	# order does; shift sprints the order (the entity never reads Input
	# itself)
	var stance: MatchState.OrderStance = MatchState.order_stance
	var sprint := Input.is_key_pressed(KEY_SHIFT)
	# deterministic order (instance ids) so formations don't reshuffle
	movers.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	for i in movers.size():
		var u: Node2D = movers[i]
		if u.kind == "robot" and own_fort and is_instance_valid(own_fort) \
				and own_fort.team == u.team and own_fort.alive:
			# garrison: man the fort missiles
			u.issue_order(Order.for_target(own_fort, sprint))
			continue
		if u.kind == "robot":
			if empty_vehicle and is_instance_valid(empty_vehicle):
				u.issue_order(Order.for_target(empty_vehicle, sprint))
				continue
			if apc and is_instance_valid(apc) and u.team == apc.team:
				u.issue_order(Order.for_target(apc, sprint))
				continue
		elif target_building and is_instance_valid(target_building) \
				and _wants_building_order(u, target_building):
			# vehicles act on buildings: damaged hardware drives into the
			# repair shop, cranes set up on wrecked buildings/bridges
			u.issue_order(Order.for_target(target_building, sprint))
			continue
		var ring := maxi(int(sqrt(float(movers.size()))), 1)
		var offset := Vector2((i % ring) - (ring - 1) * 0.5, (i / ring) - (ring - 1) * 0.5) * 20.0
		var dest := world_position + offset
		match stance:
			MatchState.OrderStance.ATTACK_MOVE:
				u.issue_order(Order.move_attack(dest, sprint))
			MatchState.OrderStance.DEFEND:
				u.issue_order(Order.move_defend(dest, sprint))
			_:
				u.issue_order(Order.move(dest, sprint))


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


## Buildings units can be ordered onto: own repair shop (damaged
## vehicles heal there) and own damaged buildings/bridges (crane work).
static func _find_interactable_building(world_position: Vector2) -> Building2D:
	for group in ["buildings", "facilities"]:
		for b in Engine.get_main_loop().root.get_tree().get_nodes_in_group(group):
			if b is Building2D and b.alive \
					and b.art_world_rect().has_point(world_position):
				return b
	return null


## A fort under the click point belonging to the selected robots' team.
static func _find_own_fort(world_position: Vector2) -> FortBuilding:
	for b in Engine.get_main_loop().root.get_tree().get_nodes_in_group("buildings"):
		if b is FortBuilding and b.alive and b.team != 0 \
				and b.art_world_rect().has_point(world_position):
			return b
	return null


static func _wants_building_order(u: Node2D, b: Building2D) -> bool:
	if not (u is Vehicle2D) or u.kind != "vehicle" or u.speed <= 0.0:
		return false
	if b.is_repair_shop() and b.owner_team == u.team and u.hp < u.max_hp:
		return true
	if u.unit_name == "crane" and b.team == u.team and b.hp < b.max_hp:
		return true
	return false
