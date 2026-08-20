class_name NavWorld
extends Node
## The navigable world — pathing grids for robots and vehicles, the map
## bounds, path requests with endpoint nudging, and the body-clearance
## placement contract. A CHILD OF THE MATCH SCENE (not an autoload):
## each match owns its grids and dies with them, and two matches can
## coexist in one tree (the in-process MP loopback needs that).
## Call sites reach the active instance through `NavWorld.current`.
##
## THE CELL CONTRACT (one rule, everything else follows):
## a cell id `c` covers world pixels [c*CELL, (c+1)*CELL) and its
## CENTRE is `c*CELL + CELL/2`. World position -> cell is
## `floor(pos/CELL)`; cell -> position is always the CENTRE.
## `make_grid()` is the only place an AStarGrid2D is built, and it sets
## `offset = CELL/2` so `get_point_path` returns cell CENTRES. With the
## engine default (offset 0) every waypoint landed on the 4-cell corner
## junction — a half-cell up-left of the cell it stood for — so routes
## through 1-2 cell gaps (the fort gate) aimed AT the wall line and
## units jammed there until the stuck watchdog cancelled the order.

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

## The one tile size. Grid cell_size, the cell contract above and every
## `/ CELL` conversion in this file read it — no bare 16.0 literals.
const CELL := 16.0

## Body half-extents by kind, for the 9-point box probe in body_clear().
## Physics bodies are 12x12 (robots) and 16x16 (vehicles/cannons); these
## are the NAV clearances, and they MUST stay under CELL/2 so that the
## centre of any open cell is a legal standing spot — the placement
## contract and A*'s cell-centre waypoints have to agree. Vehicles used
## to carry 9.0 (their true half-extent + 1px), which is wider than a
## half cell: every cell touching a wall then probed dirty, so no
## vehicle could legally stand, spawn, eject or park anywhere along a
## building — find_free_spot pushed them a full cell clear of every
## wall. Physics (move_and_slide vs. the building body) is what resolves
## real contact; nav only has to agree with itself.
const BODY_HALF := {"robot": 7.0, "vehicle": 7.5, "cannon": 7.5}


## THE grid factory — region + the cell contract in one place. Both
## loader paths (JSON maps and scene maps) and the vehicle grid build
## through here, so a grid can never ship with the wrong origin.
static func make_grid(region: Rect2i) -> AStarGrid2D:
	var grid := AStarGrid2D.new()
	grid.region = region
	grid.cell_size = Vector2(CELL, CELL)
	grid.offset = grid.cell_size * 0.5  # get_point_path -> cell CENTRES
	# ONLY_IF_NO_OBSTACLES, not AT_LEAST_ONE_WALKABLE: the permissive mode
	# lets a route step diagonally past a wall corner, and the straight
	# leg between those two cell centres passes exactly THROUGH the
	# corner point — the last source of solid-cell grazing after the
	# cell-centre fix (1/145 walker samples). Units have a 12-16px body
	# box, so a gap only a corner wide was never really passable anyway;
	# refusing the cut costs one extra cell of detour and clips nothing.
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	return grid


## World position -> cell id (the contract's only conversion).
static func cell_at(pos: Vector2) -> Vector2i:
	return Vector2i((pos / CELL).floor())


## Cell id -> its world CENTRE (never its corner).
static func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * CELL + Vector2(CELL, CELL) * 0.5


func reset() -> void:
	nav_grid = null
	vehicle_grid = null


## The grid a kind walks on — robots use the base grid, everything with
## wheels or tracks uses the vehicle grid (same, plus water).
func grid_for(for_kind: String) -> AStarGrid2D:
	return nav_grid if for_kind == "robot" else vehicle_grid


func walkable(cell: Vector2i, vehicle: bool) -> bool:
	var grid := vehicle_grid if vehicle else nav_grid
	return grid != null and not blocked(grid, cell)


## True when `pos` sits in a solid cell of the kind's grid (out of
## region counts as solid — never walk off the terrain).
func solid_at(pos: Vector2, for_kind := "robot") -> bool:
	var grid := grid_for(for_kind)
	if grid == null:
		return false
	return blocked(grid, cell_at(pos))


## A blast clears the rock at `rock_pos` — its cell opens on BOTH grids.
## Navigation mutation stays behind this API (combat used to reach into
## the grids directly).
func clear_rock(rock_pos: Vector2) -> void:
	var cell := cell_at(rock_pos)
	for grid in [nav_grid, vehicle_grid]:
		if grid != null and grid.region.has_point(cell) \
				and grid.is_point_solid(cell):
			grid.set_point_solid(cell, false)


## The 9-point body box: centre, edge midpoints and corners at `pad`.
const BOX_PROBES: Array[Vector2] = [
	Vector2(0, 0), Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1),
	Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1),
]


## Blocked = solid OR outside the grid region. AStarGrid2D errors out on
## an out-of-region query, so every probe in this file goes through here
## — off the terrain counts as wall, which is what every caller wants.
static func blocked(grid: AStarGrid2D, cell: Vector2i) -> bool:
	return not grid.region.has_point(cell) or grid.is_point_solid(cell)


## True when a body of half-extent `pad` centred at `pos` touches only
## open cells of the kind's grid. Center-cell-only checks are how units
## ended up inside walls.
func body_clear(pos: Vector2, pad: float, for_kind := "robot") -> bool:
	var grid := grid_for(for_kind)
	if grid == null:
		return true
	for probe in BOX_PROBES:
		if blocked(grid, cell_at(pos + probe * pad)):
			return false
	return true


## Nearest validated position to `near` for a body of the kind's
## half-extent: `near` itself when clear, else a ring search over
## neighbouring cell centres. Returns Vector2.INF when no clear spot
## exists within 6 cells — callers then keep their previous position.
## Every instant placement (eject, unload, dodge, production spawn,
## save restore) goes through here — never raw position writes gated
## by center-cell checks.
func find_free_spot(near: Vector2, for_kind := "robot", pad := -1.0) -> Vector2:
	if pad < 0.0:
		pad = BODY_HALF.get(for_kind, 7.0)
	if body_clear(near, pad, for_kind):
		return near
	var grid := grid_for(for_kind)
	if grid == null:
		return near
	for cell in _ring_cells(cell_at(near), 6, grid):
		var spot := cell_center(cell)
		if body_clear(spot, pad, for_kind):
			return spot
	return Vector2.INF


## Cells around `origin` in growing rings (the ring perimeter only, so
## a radius-6 search visits 168 cells instead of re-walking 169 every
## step), clipped to the grid region. Shared by find_free_spot and
## _open_cell — the two used to carry the same triple-nested loop.
static func _ring_cells(origin: Vector2i, max_radius: int,
		grid: AStarGrid2D) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for radius in range(1, max_radius + 1):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var cell := origin + Vector2i(dx, dy)
				if grid.region.has_point(cell):
					out.append(cell)
	return out


## A route from `from` to `to` as world-space breadcrumbs — cell
## CENTRES (see the cell contract), so every waypoint of an open cell
## is body-clear by construction for any kind whose BODY_HALF is under
## a half cell. Empty means "no route for this kind": the caller must
## treat that as a refused order, not as a beeline.
func request_path(from: Vector2, to: Vector2, for_kind := "robot") -> PackedVector2Array:
	var grid := grid_for(for_kind)
	if grid == null:
		return PackedVector2Array([to])
	var r := grid.region
	# clamp the goal into the map — never path (or walk) off the terrain
	to = to.clamp(Vector2(r.position) * CELL,
		Vector2(r.position + r.size) * CELL - Vector2(CELL, CELL) * 0.5)
	var a := _open_cell(cell_at(from), grid)
	var b := _open_cell(cell_at(to), grid)
	if a.x < 0 or b.x < 0:
		return PackedVector2Array()  # unreachable for this kind: refuse
	var path := grid.get_point_path(a, b)
	if path.is_empty():
		return PackedVector2Array()  # no route for this kind: refuse
	# land exactly on the clicked point instead of the last cell centre,
	# but only when that final approach is itself clear — a beeline from
	# the last breadcrumb through a solid cell was the last
	# corner-clipping source (the arrival radius resolves the residual)
	if not blocked(grid, cell_at(to)) \
			and segment_clear(path[path.size() - 1], to, for_kind):
		path[path.size() - 1] = to
	return path


## Center-cell march along a segment — the same criterion the walker
## audits itself with, so the contract and its test agree.
func segment_clear(a: Vector2, b: Vector2, for_kind := "robot") -> bool:
	var grid := grid_for(for_kind)
	if grid == null:
		return true
	var steps := int(a.distance_to(b) / 4.0) + 1
	for i in range(1, steps + 1):
		if blocked(grid, cell_at(a.lerp(b, float(i) / float(steps)))):
			return false
	return true


## Nearest open cell to `cell` (itself when open), or (-1,-1) when the
## kind has no open cell within 9 rings.
func _open_cell(cell: Vector2i, grid: AStarGrid2D) -> Vector2i:
	var r := grid.region
	cell = cell.clamp(r.position, r.position + r.size - Vector2i.ONE)
	if not grid.is_point_solid(cell):
		return cell
	for candidate in _ring_cells(cell, 9, grid):
		if not grid.is_point_solid(candidate):
			return candidate
	return Vector2i(-1, -1)
