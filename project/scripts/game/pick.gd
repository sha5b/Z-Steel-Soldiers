class_name Pick
extends Object
## What is under a world point — ONE priority definition for the context
## cursor, click selection and order targeting. The cursor and the match
## coordinator used to carry separate copies of this logic that could
## silently disagree (a cursor showing ATTACK where a click selects a
## factory is exactly the bug class this file exists to prevent).


## PHYSICS BROADPHASE for the unit scans. The engine's C++ tree narrows
## "every unit on the map" to the few bodies near the query area, and
## the exact origin-distance / rect filters at the call sites stay
## byte-identical to the old full group walks — same results, at
## O(candidates) instead of O(units). The headless harness steps units
## by hand (TestLevers.direct_step) with no physics ticks, so it gets
## the whole group as candidates and the call-site filters do all the
## work — identical results, no dependency on server sync.
static func _bodies_near(center: Vector2, radius: float) -> Array:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return []
	if TestLevers.direct_step:
		return _whole_group(tree)
	var space := tree.root.get_world_2d().direct_space_state
	if space == null:
		return []
	var params := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	params.shape = circle
	params.transform = Transform2D(0.0, center)
	params.collision_mask = 1  # units; buildings sit on layer 2
	params.collide_with_bodies = true
	params.collide_with_areas = false
	return space.intersect_shape(params, 64)


## Same broadphase for rect queries (box select, select-same-type).
static func _bodies_in_rect(rect: Rect2) -> Array:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return []
	if TestLevers.direct_step:
		return _whole_group(tree)
	var space := tree.root.get_world_2d().direct_space_state
	if space == null:
		return []
	var params := PhysicsShapeQueryParameters2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	params.shape = box
	params.transform = Transform2D(0.0, rect.get_center())
	params.collision_mask = 1
	params.collide_with_bodies = true
	params.collide_with_areas = false
	return space.intersect_shape(params, 256)


## Harness fallback: every selectable as a query-shaped hit.
static func _whole_group(tree: SceneTree) -> Array:
	var all: Array = []
	for u in tree.get_nodes_in_group(Groups.SELECTABLE):
		all.append({"collider": u})
	return all


## CLICK TOLERANCE = THE ART BOX (zod ZObject::UnderCursor and
## WithinSelection both test the object's rendered box, not a pinhead
## radius around its origin). Half-extents follow the hull art: robots
## ~24x28, hardware 32x32. A flat 8px origin circle here is why clicks
## on a tank's hull or a walking robot's edge fell through to a plain
## move — the unit "just rolls" instead of attacking.
const PICK_BOX := {
	"robot": Vector2(12.0, 14.0),
	"vehicle": Vector2(16.0, 16.0),
	"cannon": Vector2(16.0, 16.0),
}


static func in_pick_box(u: Node2D, world: Vector2) -> bool:
	var half: Vector2 = PICK_BOX.get(String(u.get("kind")), Vector2(8.0, 8.0))
	var d: Vector2 = world - u.global_position
	return absf(d.x) <= half.x and absf(d.y) <= half.y


## Cursor/targeting priority: closest live unit under the click (art
## box), then pickups, then building art rects.
static func at(world: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for hit in _bodies_near(world, 32.0):
		var u = hit.get("collider")
		if u is Unit2D and u.alive and not u.carried:
			var d: float = (world - u.global_position).length_squared()
			if in_pick_box(u, world) and d < best_d:
				best_d = d
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
	for hit in _bodies_near(world, 32.0):
		var unit = hit.get("collider")
		if unit is Unit2D and unit.alive and not unit.carried \
				and unit.team == player_team \
				and in_pick_box(unit, world):
			if best == null or unit.global_position.distance_squared_to(world) \
					< best.global_position.distance_squared_to(world):
				best = unit
	return best if best != null else null


## The candidate set for box selection: the player's own live, uncarried
## units whose ORIGIN is inside the rect (exact semantics of the group
## walk this replaces; the physics query only narrows the field).
static func box_candidates(world_rect: Rect2, player_team: int) -> Array:
	var out: Array = []
	for hit in _bodies_in_rect(world_rect.grow(16.0)):
		var unit = hit.get("collider")
		if unit is Unit2D and unit.alive and not unit.carried \
				and unit.team == player_team \
				and world_rect.has_point(unit.global_position):
			out.append(unit)
	return out
