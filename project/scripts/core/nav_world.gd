extends Node
## Autoload (NavWorld): the navigable world — pathing grids for robots
## and vehicles, the map bounds, path requests with endpoint nudging.
## MapLoader fills the grids; bridges, repairs and rock-clearing blasts
## mutate them through here.

var nav_grid: AStarGrid2D          # robots: tileinfo passability + rocks
var vehicle_grid: AStarGrid2D      # vehicles: additionally no water
var map_rect := Rect2(0.0, 0.0, 1024.0, 1376.0)


func reset() -> void:
	nav_grid = null
	vehicle_grid = null


func walkable(cell: Vector2i, vehicle: bool) -> bool:
	var grid := vehicle_grid if vehicle else nav_grid
	return grid != null and not grid.is_point_solid(cell)


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
