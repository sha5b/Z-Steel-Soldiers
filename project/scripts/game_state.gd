extends Node
## Autoload: match state — team money, zone income ticking, player team.

signal money_changed(team: int, amount: int)
signal game_over(winning_team: int)

const INCOME_PER_ZONE := 5.0   # money per owned zone per tick
const TICK_SECONDS := 1.0

var player_team := 1
var money := {1: 200, 2: 200, 3: 200, 4: 200}
var zones: Array[Node] = []
var nav_grid: AStarGrid2D
var over := false
var _accum := 0.0


func _process(delta: float) -> void:
	_accum += delta
	while _accum >= TICK_SECONDS:
		_accum -= TICK_SECONDS
		for team in money:
			var income := 0
			for z in zones:
				if z.owner_team == team:
					income += INCOME_PER_ZONE
			money[team] += income
			money_changed.emit(team, money[team])


func register_zone(zone: Node) -> void:
	zones.append(zone)


func player_money() -> int:
	return money.get(player_team, 0)


func spend(team: int, amount: int) -> bool:
	if money.get(team, 0) < amount:
		return false
	money[team] -= amount
	money_changed.emit(team, money[team])
	return true


## World-space path between two points; solid endpoints are nudged to the
## nearest open cell. Returns just [to] when no grid exists.
func request_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	if nav_grid == null:
		return PackedVector2Array([to])
	var cs: Vector2 = nav_grid.cell_size
	var a := _open_cell(Vector2i((from / cs).floor()))
	var b := _open_cell(Vector2i((to / cs).floor()))
	if a.x < 0 or b.x < 0:
		return PackedVector2Array([to])
	var path := nav_grid.get_point_path(a, b)
	if path.is_empty():
		return PackedVector2Array([to])
	# get_point_path already returns world coordinates (cell * cell_size)
	var world_path := path.duplicate()
	# land exactly on the clicked point, unless it sits inside a solid cell
	if not nav_grid.is_point_solid(Vector2i((to / cs).floor())):
		world_path[world_path.size() - 1] = to
	return world_path


func _open_cell(cell: Vector2i) -> Vector2i:
	var r := nav_grid.region
	cell = cell.clamp(r.position, r.position + r.size - Vector2i.ONE)
	if not nav_grid.is_point_solid(cell):
		return cell
	for radius in range(1, 10):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var c := cell + Vector2i(dx, dy)
				if r.has_point(c) and not nav_grid.is_point_solid(c):
					return c
	return Vector2i(-1, -1)


func report_fort_destroyed(losing_team: int) -> void:
	if over:
		return
	over = true
	var winner := player_team if losing_team != player_team else 2
	if losing_team == player_team:
		for t in money:
			if t != losing_team:
				winner = t
				break
	game_over.emit(winner)
