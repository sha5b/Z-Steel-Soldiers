class_name UnitRegistry
extends Node
## The typed "who exists" database. Units register at _ready and remove
## on death; queries replace the old per-frame group scans (targeting,
## separation, zone capture, AI, minimap, pop counts). Carried robots
## (inside an APC) stay registered but are excluded from world queries.
## A CHILD OF THE MATCH SCENE (not an autoload): each match owns its
## roster and dies with it — see NavWorld for the locator pattern.

## The active match's roster (set on _ready, cleared on exit).
static var current: UnitRegistry


func _ready() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


signal unit_spawned(unit: Unit2D)
signal unit_died(unit: Unit2D)

var _all: Array[Unit2D] = []


## Called from Unit2D._ready — every spawn path is covered.
func track(unit: Unit2D) -> void:
	if not _all.has(unit):
		_all.append(unit)
		unit_spawned.emit(unit)


## Called from Unit2D.die — also compacts freed entries (units can be
## freed without dying, e.g. the save-restore roster swap). Every death
## re-checks the original's no-units rule: a team whose last robot,
## vehicle or cannon fell loses its forts.
func untrack(unit: Unit2D) -> void:
	_all.erase(unit)
	_all = _all.filter(func(u): return is_instance_valid(u))
	unit_died.emit(unit)
	GameState.check_no_units(unit.team)


## Structural removal from Unit2D._exit_tree — silent (NO elimination
## check: freeing without dying, like the save-restore roster swap,
## must not eliminate a team) and guarantees the roster never holds a
## freed instance regardless of how the unit left the tree.
func forget(unit: Unit2D) -> void:
	_all.erase(unit)


func all_units() -> Array[Unit2D]:
	# lazily drop dangling refs (units freed without die()) — callers
	# must never see a freed instance ('is' on one is a hard error)
	_all = _all.filter(func(u): return is_instance_valid(u))
	return _all


## Units currently in the world (alive, not carried in an APC).
func world_units() -> Array[Unit2D]:
	var out: Array[Unit2D] = []
	for u in _all:
		if is_instance_valid(u) and u.alive and not u.carried:
			out.append(u)
	return out


func of_team(team: int) -> Array[Unit2D]:
	var out: Array[Unit2D] = []
	for u in _all:
		if is_instance_valid(u) and u.alive and not u.carried and u.team == team:
			out.append(u)
	return out


## Alive units of a team INCLUDING carried ones — the no-units rule
## counts defenders garrisoned in a fort or riding an APC as existing.
func alive_of_team(team: int) -> Array[Unit2D]:
	var out: Array[Unit2D] = []
	for u in _all:
		if is_instance_valid(u) and u.alive and u.team == team:
			out.append(u)
	return out


## Nearest living enemy unit (team != mine, neutral 0 never counts).
func nearest_enemy(pos: Vector2, max_range: float, my_team: int) -> Unit2D:
	var best: Unit2D = null
	var best_d := max_range * max_range
	for u in _all:
		if is_instance_valid(u) and u.alive and not u.carried \
				and u.team != 0 and u.team != my_team:
			var d: float = pos.distance_squared_to(u.global_position)
			if d < best_d:
				best_d = d
				best = u
	return best


func in_radius(pos: Vector2, radius: float) -> Array[Unit2D]:
	var out: Array[Unit2D] = []
	var r2 := radius * radius
	for u in _all:
		if is_instance_valid(u) and u.alive and not u.carried \
				and pos.distance_squared_to(u.global_position) <= r2:
			out.append(u)
	return out
