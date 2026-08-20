class_name Pick
extends Object
## What is under a world point — ONE priority definition for the context
## cursor, click selection and order targeting. The cursor and the match
## coordinator used to carry separate copies of this logic that could
## silently disagree (a cursor showing ATTACK where a click selects a
## factory is exactly the bug class this file exists to prevent).


## Cursor/targeting priority: closest live unit (8px), then pickups,
## then building art rects.
static func at(world: Vector2) -> Node2D:
	var best: Node2D = null
	for u in Engine.get_main_loop().root.get_tree().get_nodes_in_group(Groups.UNITS):
		if u is Unit2D and u.alive and not u.carried \
				and (world - u.global_position).length() < 8.0:
			if best == null or (world - u.global_position).length() \
					< (world - best.global_position).length():
				best = u
	if best != null:
		return best
	for p in Engine.get_main_loop().root.get_tree().get_nodes_in_group(Groups.PICKUPS):
		if p is Node2D and (world - p.global_position).length() < 8.0:
			return p
	return BuildingRegistry.at_point(world)


## Selection priority: the player's producers and fort FIRST (selecting
## them opens the production panel), then the player's closest unit.
## Returns null when nothing selectable is under the point.
static func selectable_at(world: Vector2, player_team: int) -> Node2D:
	var tree: SceneTree = Engine.get_main_loop()
	for c in tree.get_nodes_in_group(Groups.FACILITIES):
		if (c is RobotFactory or c is VehicleFactory) and c.owner_team == player_team \
				and c.art_world_rect().has_point(world):
			return c
	for c in tree.get_nodes_in_group(Groups.BUILDINGS):
		if c is FortBuilding and c.team == player_team \
				and c.art_world_rect().has_point(world):
			return c
	var best: Node2D = null
	for unit in tree.get_nodes_in_group(Groups.SELECTABLE):
		if unit is Unit2D and unit.alive and not unit.carried \
				and unit.team == player_team \
				and unit.global_position.distance_to(world) < 8.0:
			if best == null or unit.global_position.distance_squared_to(world) \
					< best.global_position.distance_squared_to(world):
				best = unit
	return best if best != null else null
