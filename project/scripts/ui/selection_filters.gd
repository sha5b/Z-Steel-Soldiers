class_name SelectionFilters
extends Object
## What the bottom bar's R / V / B / G buttons do.
##
## The original's meaning for these four letters is not recorded in
## anything shipped in the release, so these are OUR bindings — the
## obvious reading of the letters, wired to selection work the player
## otherwise has to do by hand: Robots, Vehicles, Buildings, Groups.
##
## R and V take the whole army of that kind. B and G CYCLE, so pressing
## the same letter walks through your factories or your control groups one
## at a time and the camera follows.

static var _cycle := {}  # "building" / "group" -> next index


static func activate(what: String) -> void:
	match what:
		"robot":
			_select_kind("robot")
		"vehicle":
			# hardware in one press: vehicles AND emplaced guns
			_select_kind("vehicle", "cannon")
		"building":
			_cycle_buildings()
		"group":
			_cycle_groups()


## Every living unit of these kinds on the player's team.
static func _select_kind(kind_a: String, kind_b := "") -> void:
	var team: int = MatchState.current.player_team
	var picked: Array[Node] = []
	for u in UnitRegistry.current.world_units():
		if not is_instance_valid(u) or not u.alive or u.team != team or u.carried:
			continue
		if u.kind == kind_a or (kind_b != "" and u.kind == kind_b):
			picked.append(u)
	_apply(picked)


## Round-robin through the player's producers, centring on each.
static func _cycle_buildings() -> void:
	var mine: Array[Node] = []
	for b in Engine.get_main_loop().root.get_tree().get_nodes_in_group(
			Groups.BUILDINGS):
		if not is_instance_valid(b) or not b.alive:
			continue
		if b.owner_team != MatchState.current.player_team:
			continue
		if b.is_fort or b is RobotFactory or b is VehicleFactory:
			mine.append(b)
	if mine.is_empty():
		Fx.cap_denied()
		return
	# deterministic order, so the cycle does not reshuffle between presses
	mine.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	var i: int = int(_cycle.get("building", 0)) % mine.size()
	_cycle["building"] = i + 1
	SelectionManager.current.select_single(mine[i])
	_centre_on(mine[i])
	Fx.ui_click()


static func _cycle_groups() -> void:
	var sel := SelectionManager.current
	for step in SelectionManager.GROUP_COUNT:
		var slot: int = (int(_cycle.get("group", 0)) + step) \
				% SelectionManager.GROUP_COUNT
		if sel.group_members(slot).is_empty():
			continue
		_cycle["group"] = slot + 1
		sel.select_group(slot)
		var centre := sel.group_center(slot)
		if centre != Vector2.INF:
			_pan(centre)
		Fx.ui_click()
		return
	Fx.cap_denied()  # no group has survivors


static func _apply(picked: Array[Node]) -> void:
	var sel := SelectionManager.current
	sel.clear_selection()
	if picked.is_empty():
		Fx.cap_denied()
		return
	picked.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	for u in picked:
		sel.selected.append(u)
	sel.commit()
	Fx.ui_click()


static func _centre_on(node: Node) -> void:
	if node is Node2D:
		_pan((node as Node2D).global_position)


static func _pan(world: Vector2) -> void:
	var cam: Camera2D = Engine.get_main_loop().root.get_viewport().get_camera_2d()
	if cam is RtsCamera2D:
		(cam as RtsCamera2D).pan_to(world)
