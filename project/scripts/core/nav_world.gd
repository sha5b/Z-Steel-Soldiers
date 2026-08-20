class_name NavWorld
extends Node
## The navigable world — pathing grids for robots and vehicles, the map
## bounds, path requests with endpoint nudging, and the body-clearance
## placement contract. A CHILD OF THE MATCH SCENE (not an autoload):
## each match owns its grids and dies with them, and two matches can
## coexist in one tree (the in-process MP loopback needs that).
## Call sites reach the active instance through `NavWorld.current`.

## The active match's navigation (set on _ready, cleared on exit — the
## locator that keeps per-instance state behind the familiar name).
static var current: NavWorld


func _ready() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


var nav_grid: AStarGrid2D          # robots: tileinfo passability + rocks
var vehicle_grid: AStarGrid2D      # vehicles: additionally no water
var map_rect := Rect2(0.0, 0.0, 1024.0, 1376.0)

## Body half-extents by kind — the physics boxes are 12x12 for robots,
## 16x16 for vehicles/cannons; +1px breathing margin. Used by
## body_clear()/find_free_spot() so placements probe the FULL box, not
## just the center pixel.
const BODY_HALF := {"robot": 7.0, "vehicle": 9.0, "cannon": 9.0}


func reset() -> void:
	nav_grid = null
	vehicle_grid = null


func walkable(cell: Vector2i, vehicle: bool) -> bool:
	var grid := vehicle_grid if vehicle else nav_grid
	return grid != null and not grid.is_point_solid(cell)


## True when a body of half-extent `pad` centred at `pos` touches only
## open cells of the kind's grid: center, edge midpoints and corners.
## Center-cell-only checks are how units ended up inside walls.
func body_clear(pos: Vector2, pad: float, for_kind := "robot") -> bool:
	var grid := nav_grid if for_kind == "robot" else vehicle_grid
	if grid == null:
		return true
	for offset in [Vector2.ZERO,
			Vector2(-pad, 0), Vector2(pad, 0), Vector2(0, -pad), Vector2(0, pad),
			Vector2(-pad, -pad), Vector2(pad, -pad), Vector2(-pad, pad), Vector2(pad, pad)]:
		if grid.is_point_solid(Vector2i(((pos + offset) / 16.0).floor())):
			return false
	return true


## Nearest validated position to `near` for a body of the kind's
## half-extent: `near` itself when clear, else a ring search over
## neighbouring cell centers. Returns Vector2.INF when no clear spot
## exists within 6 cells — callers then keep their previous position.
## Every instant placement (eject, unload, dodge, production spawn,
## save restore) goes through here — never raw position writes gated
## by center-cell checks.
func find_free_spot(near: Vector2, for_kind := "robot", pad := -1.0) -> Vector2:
	if pad < 0.0:
		pad = BODY_HALF.get(for_kind, 7.0)
	if body_clear(near, pad, for_kind):
		return near
	var grid := nav_grid if for_kind == "robot" else vehicle_grid
	if grid == null:
		return near
	var cs: float = grid.cell_size.x
	var cell := Vector2i((near / cs).floor())
	for radius in range(1, 7):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var spot := Vector2(cell + Vector2i(dx, dy)) * cs + Vector2(cs * 0.5, cs * 0.5)
				if body_clear(spot, pad, for_kind):
					return spot
	return Vector2.INF


func request_path(from: Vector2, to: Vector2, for_kind := "robot") -> PackedVector2Array:
	var grid := nav_grid if for_kind == "robot" else vehicle_grid
	if grid == null:
		return PackedVector2Array([to])
	var cs: Vector2 = grid.cell_size
	var r := grid.region
	# clamp the goal into the map — never path (or walk) off the terrain
	var max_px := Vector2(r.position + r.size) * cs
	to = to.clamp(Vector2(r.position) * cs, max_px - cs * 0.5)
	var a := _open_cell(Vector2i((from / cs).floor()), grid)
	var b := _open_cell(Vector2i((to / cs).floor()), grid)
	if a.x < 0:
		return PackedVector2Array()
	if b.x < 0:
		return PackedVector2Array()  # unreachable for this unit kind: refuse
	var path := grid.get_point_path(a, b)
	if path.is_empty():
		return PackedVector2Array()  # no route for this unit kind: refuse
	# get_point_path already returns world coordinates (cell * cell_size)
	var world_path := path.duplicate()
	# breadcrumbs must FIT THE BODY: a waypoint tucked into a wall corner
	# is unreachable at contact distance and units stall pressing into it
	# for good — nudge each onto a body-clear spot (same contract as
	# find_free_spot). The final leg keeps the exact clicked point.
	var pad: float = BODY_HALF.get(for_kind, 7.0)
	for i in world_path.size() - 1:
		if not body_clear(world_path[i], pad, for_kind):
			var nudged := find_free_spot(world_path[i], for_kind, pad)
			if nudged != Vector2.INF:
				world_path[i] = nudged
	# land exactly on the clicked point, unless it sits inside a solid cell
	if not grid.is_point_solid(Vector2i((to / cs).floor())):
		world_path[world_path.size() - 1] = to
	return world_path


func _open_cell(cell: Vector2i, grid: AStarGrid2D) -> Vector2i:
	var r := grid.region
	cell = cell.clamp(r.position, r.position + r.size - Vector2i.ONE)
	if not grid.is_point_solid(cell):
		return cell
	for radius in range(1, 10):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var c := cell + Vector2i(dx, dy)
				if r.has_point(c) and not grid.is_point_solid(c):
					return c
	return Vector2i(-1, -1)
