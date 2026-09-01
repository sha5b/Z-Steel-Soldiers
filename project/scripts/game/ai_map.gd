class_name AiMap
extends RefCounted
## THE CPU'S PICTURE OF THE MAP — the layer the brain had none of.
##
## CpuAi used to reason straight off node scans: "every zone I do not
## own", "every enemy building", "the nearest idle unit". A list of
## objectives with distances is not an understanding of a map, and it
## shows in the way the old brain played — it had no idea which of its
## zones was the FRONT and which was safe rear, no idea whether a target
## was defended, and no idea that taking zone A opens the road to B.
##
## So this builds, once per think pass, the thing a human player carries
## in their head:
##
##   * a ZONE GRAPH — which sectors border which (zones are rects, so
##     adjacency is a rect test, and it never changes during a match:
##     built once, cached for the match)
##   * per-zone STRENGTH, ours and theirs, in the game's own currency
##     (unit cost scaled by health — see power_of)
##   * per-zone VALUE — what standing there is worth: a fort, factories,
##     a repair shop, bare ground
##   * DEPTH — hops through the graph from our own fort, so "home",
##     "front" and "deep in their territory" are answerable questions
##   * FRONT and TARGET lists — our border sectors ordered by threat,
##     and their border sectors ordered by what they are worth against
##     what they cost to take
##
## Everything here is READ-ONLY analysis. It issues no orders and holds
## no units; AiSquad and CpuAi do that. Keeping the read separate from
## the decision is what makes the decision testable.

## Zone value weights: what standing in a sector is worth. A fort ends
## the game, a factory pays for itself in denied production, the support
## buildings are worth a detour, bare ground is worth the flag alone.
const VALUE_FLAG := 1.0
const VALUE_SUPPORT := 2.0
const VALUE_FACTORY := 4.0
const VALUE_FORT := 8.0
## How far outside a zone rect a unit still counts as contesting it —
## a squad massing on the border is a threat to that sector.
const CONTEST_MARGIN := 48.0
## ADJACENCY TOLERANCE, as a fraction of a sector's own size. Two sectors
## are neighbours when the gap between their rects is under
## `median_extent * ADJACENCY_FRACTION`.
##
## THIS CANNOT BE A FIXED PIXEL CONSTANT. Zod maps do not tile their
## sectors edge to edge — the shipped 256x256 map is an 8x8 grid of
## ~480px sectors with a 160px SEAM down the middle of both axes (the
## river/road corridor). A flat 40px tolerance bridged the 0px joins
## inside each quadrant and none of the seams, so the graph came out as
## four disconnected 4x4 islands: three quarters of the map read as
## UNREACHABLE and the brain would not rank a target on any of it.
## Scaling with sector size makes the rule "sectors within half a
## sector's width of each other are neighbours", which is a statement
## about the map's own geometry rather than about one map's pixels.
const ADJACENCY_FRACTION := 0.5
const ADJACENCY_MIN := 48.0
const ADJACENCY_MAX := 400.0
## Depth for a zone the graph cannot reach from our fort (another
## landmass, or we have no fort left).
const UNREACHABLE_DEPTH := 999

var team := 2
## zone node -> Array[Node] of neighbouring zone nodes. Zones never
## move, so this is built once and reused for the whole match.
var graph: Dictionary = {}
## zone node -> Dictionary(owner, at, own, foe, value, depth, front,
## buildings). Rebuilt every refresh().
var info: Dictionary = {}
var home := Vector2.INF     # our fort, or our centre of mass without one
var own_power := 0.0        # our whole army, in cost-weighted power
var foe_power := 0.0        # everyone else's, added together
## The STRONGEST SINGLE opponent. On a four-team map "everyone else" is
## three armies, so comparing ourselves to the total says we are losing
## from the first minute of every match — and a brain that thinks it is
## losing turtles, never expands, and hands the map to whoever does. A
## player compares themselves to their biggest rival; so does this.
var rival_power := 0.0
var foe_by_team: Dictionary = {}  # team -> power
var zones_held := 0
var zones_total := 0
var _graph_for := 0         # zone count the graph was built for


func _init(for_team: int = 2) -> void:
	team = for_team


# ---- the currency ------------------------------------------------------

## WHAT A UNIT IS WORTH IN A FIGHT, in the game's own units of account.
##
## Not head count: a tank and a grunt are not one apiece. Not `damage`
## either — that field is per-shot and explosives carry a flat scale, so
## a missile launcher reads 670 against a grunt's 1 and any sum over it
## is meaningless. COST is the design's own valuation of a unit, and it
## already prices HP, range, damage and speed together. Scaled by
## current health, because a tank at 10% is not a tank.
##
## Cranes and empty transports carry no fight (damage 0) and count zero —
## a brain that thinks three cranes can hold a bridge loses the bridge.
static func power_of(u: Node) -> float:
	if u == null or not is_instance_valid(u) or not u.alive or u.carried:
		return 0.0
	if int(u.damage) <= 0:
		return 0.0
	var def := ContentDB.def_for(String(u.kind), String(u.unit_name))
	var worth: float = float(def.cost) if def != null else 40.0
	return worth * clampf(float(u.hp) / float(maxi(int(u.max_hp), 1)), 0.05, 1.0)


## Combined power of a unit list — the one place squads and zones agree
## on how strong a body of troops is.
static func power_of_all(units: Array) -> float:
	var total := 0.0
	for u in units:
		total += power_of(u)
	return total


# ---- the read ----------------------------------------------------------

## Rebuild the dynamic picture. Called once per think pass; the graph
## behind it is built on the first call and kept.
func refresh() -> void:
	_dist_cache.clear()  # walk distances are a per-pass memo
	var zones: Array = MatchState.current.zones
	if zones.size() != _graph_for:
		graph = _build_graph(zones)
		_graph_for = zones.size()
	zones_total = zones.size()
	zones_held = 0
	own_power = 0.0
	foe_power = 0.0
	rival_power = 0.0
	foe_by_team.clear()
	home = Vector2.INF  # re-derived every pass: forts fall, armies move
	info.clear()
	for z in zones:
		if z.owner_team == team:
			zones_held += 1
		info[z] = {
			"owner": int(z.owner_team), "at": _centre(z), "rect": z.world_rect(),
			"own": 0.0, "foe": 0.0, "value": VALUE_FLAG, "buildings": 0,
			"depth": UNREACHABLE_DEPTH, "front": false, "producers": 0,
		}
	_read_buildings(zones)
	_read_units(zones)
	_read_depth(zones)
	_read_fronts(zones)


func _read_buildings(zones: Array) -> void:
	var fort_at := Vector2.INF
	for b in BuildingRegistry.all():
		if not (b is Building2D) or not b.alive or (b as Building2D).is_bridge():
			continue
		var bld := b as Building2D
		var at := bld.visual_center()
		if bld.is_fort and bld.team == team:
			fort_at = at
		for z in zones:
			var entry: Dictionary = info[z]
			if not (entry.rect as Rect2).has_point(at):
				continue
			entry.buildings = int(entry.buildings) + 1
			var worth := VALUE_SUPPORT
			if bld.is_fort:
				worth = VALUE_FORT
			elif bld.produces_anything():
				worth = VALUE_FACTORY
				entry.producers = int(entry.producers) + 1
			entry.value = maxf(float(entry.value), worth)
			break
	if fort_at != Vector2.INF:
		home = fort_at


## Bucket every fighting unit into the sector it stands in (or is
## pressing on — CONTEST_MARGIN), as power, not head count.
func _read_units(zones: Array) -> void:
	var own_sum := Vector2.ZERO
	var own_n := 0
	for u in UnitRegistry.current.world_units():
		var power := power_of(u)
		if power <= 0.0:
			continue
		if u.team == team:
			own_power += power
			own_sum += u.global_position
			own_n += 1
		elif u.team != 0:
			foe_power += power
			var by: float = float(foe_by_team.get(u.team, 0.0)) + power
			foe_by_team[u.team] = by
			rival_power = maxf(rival_power, by)
		else:
			continue  # derelict hardware belongs to nobody
		for z in zones:
			var entry: Dictionary = info[z]
			if not (entry.rect as Rect2).grow(CONTEST_MARGIN).has_point(
					u.global_position):
				continue
			if u.team == team:
				entry.own = float(entry.own) + power
			else:
				entry.foe = float(entry.foe) + power
			break
	if home == Vector2.INF and own_n > 0:
		home = own_sum / float(own_n)


## Hops from the sector our fort stands in, through the zone graph. This
## is what makes "rear", "front" and "their half" answerable without any
## terrain analysis: a zone two hops out is reachable by land, a zone
## with no depth at all is on ground we cannot walk to.
func _read_depth(zones: Array) -> void:
	if home == Vector2.INF or zones.is_empty():
		return
	var start: Node = zone_at(home)
	if start == null:
		# no zone covers the fort: seed from the nearest one instead
		var best_d := INF
		for z in zones:
			var d: float = _centre(z).distance_squared_to(home)
			if d < best_d:
				best_d = d
				start = z
	if start == null:
		return
	(info[start] as Dictionary).depth = 0
	var frontier: Array = [start]
	while not frontier.is_empty():
		var current: Node = frontier.pop_front()
		var here: int = int((info[current] as Dictionary).depth)
		for nb in (graph.get(current, []) as Array):
			if not info.has(nb):
				continue
			var entry: Dictionary = info[nb]
			if int(entry.depth) <= here + 1:
				continue
			entry.depth = here + 1
			frontier.append(nb)


## A zone we hold that borders one we do not is a FRONT. Marking it on
## both sides of the seam is deliberate: the defender needs to know
## which of its sectors is exposed, and the attacker which of theirs is
## takeable without a march.
func _read_fronts(zones: Array) -> void:
	for z in zones:
		var entry: Dictionary = info[z]
		for nb in (graph.get(z, []) as Array):
			if not info.has(nb):
				continue
			if int((info[nb] as Dictionary).owner) != int(entry.owner):
				entry.front = true
				break


# ---- terrain distance ---------------------------------------------------

## WALK DISTANCE, not line distance. Every "who is nearest" the brain
## asks used to be answered by straight-line range — across a river,
## through a fort wall — and then the unit walked the long way round
## while the brain believed the short one, arriving minutes after a
## "further" squadmate. This measures over the robot nav grid (water,
## walls and buildings respected), memoized per cell pair per think
## pass; one A* hop count x CELL is the march length. Unreachable
## targets answer INF, and every sort below ranks INF LAST: a squad
## never again drafts the unit that cannot legally arrive. Positions
## in solid cells (a zone centre in the river) snap to the nearest
## open cell first.
var _dist_cache := {}  # "ax,ay>bx,by" -> walk px (this pass)


func walk_distance(from: Vector2, to: Vector2) -> float:
	if from == Vector2.INF or to == Vector2.INF:
		return INF
	var grid: AStarGrid2D = NavWorld.current.nav_grid \
		if NavWorld.current != null else null
	if grid == null or home == Vector2.INF:
		return from.distance_to(to)  # no grid / no fort: the old metric
	var a := _open_cell_near(grid, NavWorld.cell_at(from))
	var b := _open_cell_near(grid, NavWorld.cell_at(to))
	if a.x < 0 or b.x < 0:
		return INF
	var key := "%d,%d>%d,%d" % [a.x, a.y, b.x, b.y]
	if _dist_cache.has(key):
		return float(_dist_cache[key])
	var hops: Array[Vector2i] = grid.get_id_path(a, b, false)
	var d := INF
	if not hops.is_empty():
		d = float(hops.size()) * NavWorld.CELL
	_dist_cache[key] = d
	return d


## The cell itself, or the nearest walkable within 3 cells (INF cell on
## failure). Positions the brain measures with are zone centres and unit
## feet — the odd solid one is a centre in the river, not a wall.
func _open_cell_near(grid: AStarGrid2D, cell: Vector2i) -> Vector2i:
	if not grid.region.has_point(cell):
		return Vector2i(-1, -1)
	if not grid.is_point_solid(cell):
		return cell
	for r in range(1, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := cell + Vector2i(dx, dy)
				if grid.region.has_point(c) and not grid.is_point_solid(c):
					return c
	return Vector2i(-1, -1)


# ---- questions the commander asks -------------------------------------

## The sector covering a world point (null when none does).
func zone_at(pos: Vector2) -> Node:
	for z in MatchState.current.zones:
		if info.has(z) and ((info[z] as Dictionary).rect as Rect2).has_point(pos):
			return z
	return null


func entry_of(z: Node) -> Dictionary:
	return info.get(z, {}) as Dictionary


## OUR border sectors, worst threat first. The threat number is enemy
## power present minus ours, biased up by what the sector is worth — a
## front factory under pressure outranks a bare flag under the same
## pressure.
func threatened_zones() -> Array:
	var out: Array = []
	for z in MatchState.current.zones:
		var entry: Dictionary = info.get(z, {})
		if entry.is_empty() or int(entry.owner) != team:
			continue
		var threat: float = float(entry.foe) - float(entry.own)
		if threat <= 0.0 and not bool(entry.front):
			continue
		out.append({"zone": z, "at": entry.at,
			"threat": threat * float(entry.value), "raw": threat,
			"value": float(entry.value)})
	out.sort_custom(func(a, b): return float(a.threat) > float(b.threat))
	return out


## THEIR sectors worth taking, best first. "Best" is value per unit of
## resistance and distance: a lightly-held factory sector next door beats
## a fortified flag across the map, which is the judgement the old
## nearest-first grab could not make. `reachable_only` drops zones the
## graph cannot reach from home (islands), which the old brain kept
## re-sending units at until a blacklist timer caught up.
func target_zones(reachable_only := true) -> Array:
	var out: Array = []
	for z in MatchState.current.zones:
		var entry: Dictionary = info.get(z, {})
		if entry.is_empty() or int(entry.owner) == team:
			continue
		var depth: int = int(entry.depth)
		if reachable_only and depth >= UNREACHABLE_DEPTH:
			continue
		# resistance: what is standing there, floored so a defended
		# sector never divides by nothing
		var resistance: float = maxf(float(entry.foe), 40.0)
		var march: float = 1.0 + float(mini(depth, 12)) * 0.35
		out.append({"zone": z, "at": entry.at, "depth": depth,
			"value": float(entry.value), "foe": float(entry.foe),
			"score": float(entry.value) / (resistance * march),
			"neutral": int(entry.owner) == 0})
	out.sort_custom(func(a, b): return float(a.score) > float(b.score))
	return out


## Our own rear sectors, deepest first — where a beaten squad falls back
## to and where reinforcements gather.
func rally_zones() -> Array:
	var out: Array = []
	for z in MatchState.current.zones:
		var entry: Dictionary = info.get(z, {})
		if entry.is_empty() or int(entry.owner) != team or bool(entry.front):
			continue
		out.append({"zone": z, "at": entry.at, "depth": int(entry.depth)})
	out.sort_custom(func(a, b): return int(a.depth) < int(b.depth))
	return out


## Are we ahead, level or behind? One number the strategy reads, in power
## rather than head count, and measured against our BIGGEST RIVAL rather
## than against every other team added together — see rival_power.
func power_ratio() -> float:
	var against: float = rival_power if rival_power > 0.0 else foe_power
	return own_power / maxf(against, 1.0)


func share_held() -> float:
	return float(zones_held) / float(maxi(zones_total, 1))


# ---- the graph ---------------------------------------------------------

static func _centre(z: Node) -> Vector2:
	return (z.world_rect() as Rect2).get_center()


## Adjacency by rect proximity, with the tolerance read off the sectors
## themselves (see ADJACENCY_FRACTION). Nothing here depends on
## ownership, unit positions or terrain, which is why it can be built
## once per match and reused.
static func _build_graph(zones: Array) -> Dictionary:
	var out: Dictionary = {}
	var rects: Array = []
	var extents: Array = []
	for z in zones:
		out[z] = []
		var r: Rect2 = z.world_rect()
		rects.append(r)
		extents.append(minf(r.size.x, r.size.y))
	var tolerance := ADJACENCY_MIN
	if not extents.is_empty():
		extents.sort()
		var median: float = float(extents[extents.size() / 2])
		tolerance = clampf(median * ADJACENCY_FRACTION,
			ADJACENCY_MIN, ADJACENCY_MAX)
	for i in zones.size():
		for j in range(i + 1, zones.size()):
			if _rect_gap(rects[i], rects[j]) > tolerance:
				continue
			(out[zones[i]] as Array).append(zones[j])
			(out[zones[j]] as Array).append(zones[i])
	return out


## Shortest distance between two rects (0 when they touch or overlap).
static func _rect_gap(a: Rect2, b: Rect2) -> float:
	var dx: float = maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dy: float = maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	return Vector2(dx, dy).length()
