extends Node
## Autoload: match state — team money, zone income ticking, player team.

signal money_changed(team: int, amount: int)
signal game_over(winning_team: int)

const INCOME_PER_ZONE := 5.0   # money per owned zone per tick
const TICK_SECONDS := 1.0

var player_team := 1
var money := {1: 200, 2: 200, 3: 200, 4: 200}
var zones: Array[Node] = []
var nav_grid: AStarGrid2D          # robots: tileinfo passability + rocks
var vehicle_grid: AStarGrid2D      # vehicles: additionally no water
var map_rect := Rect2(0.0, 0.0, 1024.0, 1376.0)
var over := false
var next_map := ""
var upgrades := {}  # team -> {grenades: bool, rockets: bool}
var _accum := 0.0


func reset_for_new_map() -> void:
	zones.clear()
	nav_grid = null
	vehicle_grid = null
	over = false
	_accum = 0.0
	money = {1: 200, 2: 200, 3: 200, 4: 200}
	upgrades = {}


func grant_upgrade(team: int, kind: String) -> void:
	if not upgrades.has(team):
		upgrades[team] = {}
	upgrades[team][kind] = true


func has_upgrade(team: int, kind: String) -> bool:
	return upgrades.get(team, {}).get(kind, false)


## Grenades buff robots, rockets buff vehicles (simple Z-style tiers).
func robot_damage_mult(team: int) -> float:
	return 1.4 if has_upgrade(team, "grenades") else 1.0


func vehicle_damage_mult(team: int) -> float:
	return 1.6 if has_upgrade(team, "rockets") else 1.0


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
## nearest open cell. Robots use nav_grid; vehicles use vehicle_grid (no
## water crossings, zod's PF_WATER rule).
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
