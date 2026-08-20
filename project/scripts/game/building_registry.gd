class_name BuildingRegistry
extends Node
## The typed "what stands where" database — the building half of
## UnitRegistry. Buildings register at _ready and drop out on
## _exit_tree; every query that used to walk the ALL_BUILDINGS group
## walks this one list instead (unit targeting and splash damage ran
## that scan per unit per combat tick and per explosion).
## A CHILD OF THE MATCH SCENE (not an autoload): each match owns its
## roster and dies with it — same locator pattern as UnitRegistry.
##
## Every query is STATIC and goes through all(): the map-resource build
## tool instantiates buildings with no match around them, so a missing
## registry falls back to the group scan instead of crashing.

## The active match's roster (set on _ready, cleared on exit).
static var current: BuildingRegistry

var _all: Array[Building2D] = []
var _next_net_id := 1  # buildings ready in MAP order on every peer


func _ready() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


## Stable per-match id for multiplayer intents (queue, rally, crane and
## repair targets address buildings by net id exactly like units do).
## Buildings ready in map order on every peer, so a plain counter agrees
## across the wire.
func next_net_id() -> int:
	var id := _next_net_id
	_next_net_id += 1
	return id


## Called from Building2D._ready — every spawn path is covered.
func track(b: Building2D) -> void:
	if not _all.has(b):
		_all.append(b)


## Structural removal from Building2D._exit_tree. Dead buildings STAY
## registered (they keep their ruin sprite and the elimination cascade
## still walks them); only leaving the tree drops an entry.
func forget(b: Building2D) -> void:
	_all.erase(b)


## Every registered building, forts through bridges, alive or ruined.
## Callers must never see a freed instance ('is' on one is a hard
## error), so dangling refs are dropped lazily here.
static func all() -> Array:
	if current != null:
		current._all = current._all.filter(func(b): return is_instance_valid(b))
		return current._all
	var loop := Engine.get_main_loop()
	if loop == null or loop.root == null:
		return []
	return loop.root.get_tree().get_nodes_in_group(Groups.ALL_BUILDINGS)


static func by_net_id(id: int) -> Building2D:
	for b in all():
		if b is Building2D and b.net_id == id:
			return b
	return null


## Alive structures of a team (owner_team, which is what the zone
## economy and the elimination cascade key off).
static func owned_by(team: int) -> Array[Building2D]:
	var out: Array[Building2D] = []
	for b in all():
		if b is Building2D and b.alive and b.owner_team == team:
			out.append(b)
	return out


## Does this team still hold a standing fort? (Original
## CheckNoUnitsDestroyFort and the win check both ask exactly this.)
static func has_alive_fort(team: int) -> bool:
	for b in all():
		if b is Building2D and b.alive and b.is_fort and b.team == team:
			return true
	return false


## Any standing fort NOT held by these teams — "somebody else is still
## fighting" for the win check.
static func has_fort_outside(teams: Array) -> bool:
	for b in all():
		if b is Building2D and b.alive and b.is_fort and b.team != 0 \
				and not teams.has(b.team):
			return true
	return false


## Nearest shootable enemy structure. Bridges are neutral road surface
## and never targeted; team 0 is derelict and units must not wander off
## to shoot it.
static func nearest_enemy(pos: Vector2, max_range: float, my_team: int) -> Building2D:
	var best: Building2D = null
	var best_d := max_range
	for b in all():
		if not (b is Building2D) or not b.alive or b.is_bridge():
			continue
		if b.team == 0 or b.team == my_team:
			continue
		var d: float = pos.distance_to(b.visual_center())
		if d < best_d:
			best_d = d
			best = b
	return best


## Structures inside a blast, each with the point of its footprint that
## was actually hit: distance measures to the RECT, not the centre, so a
## shell bursting on a big factory's wall does not measure to the
## building middle. Team 0 IS included — see Combat.area_damage.
static func blast_targets(pos: Vector2, radius: float, shooter_team: int) -> Array:
	var out: Array = []
	for b in all():
		if not (b is Building2D) or not b.alive or b.team == shooter_team:
			continue
		var fp: Rect2 = b.world_footprint()
		var cp := pos.clamp(fp.position, fp.position + fp.size)
		if cp.distance_to(pos) <= radius:
			out.append({"building": b, "at": cp})
	return out


## The standing building whose ART rect covers a point (clicks, cursor).
static func at_point(world: Vector2) -> Building2D:
	for b in all():
		if b is Building2D and b.alive and b.art_world_rect().has_point(world):
			return b
	return null
