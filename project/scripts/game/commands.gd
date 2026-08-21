class_name Commands
extends Object
## Order dispatch for the current selection: formation move orders, and
## the Z-style special targets — ordering robots onto an empty
## vehicle/cannon mans it once they walk up; onto a friendly manned APC
## loads them as passengers. `queued` (ctrl+right-click) appends the
## order to each unit's chain instead of replacing what it is doing.
## stop()/hold() are the two commands the game had no way to give.


static func dispatch(world_position: Vector2, queued := false) -> void:
	# a selected producing building: right-click sets its rally point
	var selected := SelectionManager.current.selected
	if selected.size() == 1 and is_instance_valid(selected[0]) 			and selected[0] is Building2D and selected[0].alive 			and (selected[0].is_fort or selected[0] is RobotFactory or selected[0] is VehicleFactory) 			and selected[0].owner_team == MatchState.current.player_team:
		selected[0].set_rally(world_position)
		Net.relay_rally(selected[0], world_position)
		Fx.ui_click()
		return
	var foe := _find_enemy(world_position)
	var empty_vehicle := _find_empty_vehicle(world_position)
	var apc := _find_apc(world_position)
	var target_building := _find_interactable_building(world_position)
	var own_fort := _find_own_fort(world_position)
	var crate := _find_pickup(world_position)
	var movers: Array[Node] = []
	for u in SelectionManager.current.selected:
		if is_instance_valid(u) and u is Unit2D and u.alive:
			movers.append(u)
	# the player's robots bark an acknowledgement — once per dispatch
	if movers.size() > 0:
		Fx.acknowledge()
	# the stance (the D/Z plates and their hotkeys) decides what a move
	# order does; shift sprints the order (the entity never reads Input
	# itself)
	var stance: SelectionManager.OrderStance = SelectionManager.current.order_stance
	var sprint := Input.is_key_pressed(KEY_SHIFT)
	# deterministic order (instance ids) so formations don't reshuffle
	movers.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	for i in movers.size():
		var u: Node2D = movers[i]
		if u.kind == "robot" and own_fort and is_instance_valid(own_fort) \
				and own_fort.team == u.team and own_fort.alive:
			# garrison: man the fort missiles
			_order(u, Order.for_target(own_fort, sprint), queued)
			continue
		if u.kind == "robot":
			if empty_vehicle and is_instance_valid(empty_vehicle):
				_order(u, Order.for_target(empty_vehicle, sprint), queued)
				continue
			if apc and is_instance_valid(apc) and u.team == apc.team:
				_order(u, Order.for_target(apc, sprint), queued)
				continue
		elif target_building and is_instance_valid(target_building) \
				and _wants_building_order(u, target_building):
			# vehicles act on buildings: damaged hardware drives into the
			# repair shop, cranes set up on wrecked buildings/bridges
			_order(u, Order.for_target(target_building, sprint), queued)
			continue
		# an ENEMY under the cursor is an ATTACK order, not a move to that
		# spot. The cursor has always shown "attack" here while the
		# dispatch fell through to a plain move, so the unit walked to
		# where the enemy stood at click time and stopped.
		if foe != null and is_instance_valid(foe) and u.kind != "cannon":
			_order(u, Order.attack(foe, sprint), queued)
			continue
		var ring := maxi(int(sqrt(float(movers.size()))), 1)
		var offset := Vector2((i % ring) - (ring - 1) * 0.5, (i / ring) - (ring - 1) * 0.5) * 20.0
		var dest := world_position + offset
		var move_order: Order = null
		match stance:
			SelectionManager.OrderStance.ATTACK_MOVE:
				move_order = Order.move_attack(dest, sprint)
			SelectionManager.OrderStance.DEFEND:
				move_order = Order.move_defend(dest, sprint)
			_:
				move_order = Order.move(dest, sprint)
		# clicking a CRATE is still a move (walking over it picks it up),
		# but the confirmation says what the click meant
		if u.kind == "robot" and crate != null and is_instance_valid(crate):
			move_order.confirm = "grabbed"
		_order(u, move_order, queued)


## THE dismount action (X, or the panel's EXIT button): hand back
## whatever the current selection is holding. Until this existed a unit
## that entered anything was gone for the match — a garrisoned robot went
## invisible and degrouped with no way out, a crewed vehicle could never
## be un-crewed, and an APC squad only came out by arriving somewhere.
## Returns how many bodies stepped out, so callers can beep on a no-op.
static func eject() -> int:
	var out := 0
	for node in SelectionManager.current.selected.duplicate():
		if not is_instance_valid(node):
			continue
		var gave := 0
		if node is FortBuilding and node.team == MatchState.current.player_team:
			gave = (node as FortBuilding).release_garrison()
		elif node is Vehicle2D and node.team == MatchState.current.player_team:
			var v := node as Vehicle2D
			if v.is_apc() and not v.cargo.is_empty():
				gave = v.cargo.size()
				v.unload()  # passengers first: the driver keeps the hull
			elif v.manned:
				gave = 1
				v.eject_driver()
		out += gave
		if gave > 0 and node is Node2D:
			# the original's EXITED marker, on the thing that gave them back
			PathIndicator.show_marker(MatchState.current.map_root,
				(node as Node2D).global_position, "exited")
	if out == 0:
		Fx.cap_denied()  # nothing to give back — say so instead of nothing
	return out


## Issue + relay: the single place a player order enters the game AND
## the network (no-op offline — Net guards in_match itself).
static func _order(u: Node2D, o: Order, queued := false) -> void:
	o.queued = queued
	u.issue_order(o)
	Net.relay_order(u, o)


## STOP (S): cancel whatever the selection is doing and hold ground.
## Returns how many units were called off, so the caller can beep on a
## selection with nothing to cancel.
static func stop() -> int:
	var called_off := 0
	for node in SelectionManager.current.selected:
		if is_instance_valid(node) and node is Unit2D and node.alive \
				and not (node as Unit2D).carried:
			_order(node, Order.stop())
			called_off += 1
	if called_off == 0:
		Fx.cap_denied()
	else:
		Fx.ui_click()
	return called_off


## HOLD POSITION (H): every selected unit takes the ground it stands on
## as a DEFEND post — it fights from there and walks back if shoved off,
## instead of chasing whatever wandered past.
static func hold() -> int:
	var held := 0
	for node in SelectionManager.current.selected:
		if is_instance_valid(node) and node is Unit2D and node.alive \
				and not (node as Unit2D).carried:
			_order(node, Order.hold((node as Unit2D).global_position))
			held += 1
	if held == 0:
		Fx.cap_denied()
	else:
		Fx.ui_click()
	return held



## A crate under the click point (crates are collected by walking over
## them — this only decides which confirmation art the order shows).
static func _find_pickup(world_position: Vector2) -> Node2D:
	for p in Engine.get_main_loop().root.get_tree().get_nodes_in_group(Groups.PICKUPS):
		if p is Node2D and p.global_position.distance_to(world_position) < 12.0:
			return p
	return null


static func _find_apc(world_position: Vector2) -> Vehicle2D:
	for v in Engine.get_main_loop().root.get_tree().get_nodes_in_group(Groups.UNITS):
		if v is Vehicle2D and v.is_apc() and v.manned and v.alive and v.team != 0 \
				and v.global_position.distance_to(world_position) < 24.0:
			return v
	return null


static func _find_empty_vehicle(world_position: Vector2) -> Node2D:
	for v in Engine.get_main_loop().root.get_tree().get_nodes_in_group(Groups.UNITS):
		if v is Vehicle2D and not v.manned and v.alive \
				and v.global_position.distance_to(world_position) < 24.0:
			return v
	return null


## Buildings units can be ordered onto: own repair shop (damaged
## vehicles heal there) and own damaged buildings/bridges (crane work).
static func _find_interactable_building(world_position: Vector2) -> Building2D:
	# EVERY building, not just the narrower groups — the repair shop sits
	# in none of them and scanning "buildings"/"facilities" never found it
	return BuildingRegistry.at_point(world_position)


## An ENEMY unit or building under the click point (the same Pick
## priority the cursor uses, so what you see is what you get). Neutral
## team-0 hardware is NOT a foe — clicking it means "go man it".
static func _find_enemy(world_position: Vector2) -> Node2D:
	var hit := Pick.at(world_position)
	if hit == null or not is_instance_valid(hit):
		return null
	# Pick.at also answers with PICKUPS (a crate is a click target for
	# the cursor), and a crate has no `team` at all — `int(null)` is a
	# hard crash, which is what right-clicking a crate used to do.
	# Anything with no team is not a combatant.
	var team_value = hit.get("team")
	if team_value == null:
		return null
	var team := int(team_value)
	if team == 0 or team == MatchState.current.player_team:
		return null
	if hit is Building2D:
		return hit if (hit as Building2D).alive and not (hit as Building2D).is_bridge() else null
	return hit if hit is Unit2D and (hit as Unit2D).alive else null


## A fort under the click point belonging to the selected robots' team.
static func _find_own_fort(world_position: Vector2) -> FortBuilding:
	for b in Engine.get_main_loop().root.get_tree().get_nodes_in_group(Groups.BUILDINGS):
		if b is FortBuilding and b.alive and b.team != 0 \
				and b.art_world_rect().has_point(world_position):
			return b
	return null


static func _wants_building_order(u: Node2D, b: Building2D) -> bool:
	return b.accepts_order_from(u)  # the target answers (capability query)
