class_name AiSquad
extends RefCounted
## A BODY OF TROOPS WITH ONE JOB — the unit of manoeuvre the CPU never
## had.
##
## The old brain commanded individuals. Every think pass it re-derived
## "the idle units" and handed each one the objective nearest to it, so
## an army had no shape: units trickled at a target one at a time, in the
## order they happened to finish walking, arrived alone, died alone, and
## the next trickle walked over their bodies. That is what "it just
## storms" is — not aggression, the ABSENCE of any grouping between the
## unit and the map.
##
## A squad fixes that by owning four things a single unit cannot have:
##
##   ASSEMBLY   it gathers at a staging point behind the line and does
##              not commit until it is both together and strong enough
##              for the job it was given
##   COHESION   it advances as one: laggards are told to catch up to the
##              squad instead of to the objective, so it arrives as a
##              body
##   PERSISTENCE it keeps its mission across think passes. The commander
##              does not re-decide every unit every second, so units stop
##              pinballing between objectives
##   WITHDRAWAL  it knows when it has lost. Below a fraction of its peak
##              strength it breaks off for friendly ground instead of
##              feeding the rest of itself in one at a time
##
## The squad issues orders through a callable the commander hands it, so
## every AI intent still travels the same relay seam (CpuAi._order ->
## Net) — a squad cannot smuggle an order past multiplayer.

enum Mission {
	DEFEND,    # hold a sector of our own ground
	CAPTURE,   # take a flag we do not own
	ASSAULT,   # kill a specific structure
	WITHDRAW,  # break contact and fall back
}

enum Phase {
	GATHERING,   # forming up at the staging point
	ADVANCING,   # moving on the objective as a body
	ENGAGED,     # in contact: the per-unit combat layer has it
	FALLING_BACK,
}

## How close to the staging point counts as formed up, and how spread a
## squad may be before it is told to close up rather than advance.
const GATHER_RADIUS := 96.0
const COHESION_RADIUS := 150.0
## A member further than this from the squad centre is a laggard: it is
## sent to the squad, not to the objective.
const LAG_RADIUS := 200.0
## Squad centre within this of the objective = in contact.
const ENGAGE_RADIUS := 120.0
## Falls back below this share of its PEAK strength. A squad that has
## lost two thirds of what it had is not going to win the fight it is in.
const BREAK_FRACTION := 0.4
## Give up on forming up after this long and go with what turned up — a
## squad waiting for a reinforcement that died on the road waits forever.
const GATHER_TIMEOUT_MS := 20000
## An order is only re-issued when the intent MOVED this far, or when the
## unit has gone idle. Re-issuing the same destination every pass is what
## made units stutter and never finish a path.
const REISSUE_PX := 64.0
## Formation spacing around the objective.
const FILE_SPACING := 26.0

var team := 2
var mission: Mission = Mission.CAPTURE
var phase: Phase = Phase.GATHERING
var members: Array[Node] = []
## What we are going for: a place always, a node when the mission is
## about a specific structure.
var objective := Vector2.INF
var objective_node: Node2D = null
## The sector this squad answers for (DEFEND/CAPTURE) — the commander
## keys its roster off it so it does not raise two squads for one job.
var zone: Node = null
## Where it forms up before committing, and where it runs to when beaten.
var staging := Vector2.INF
var fallback := Vector2.INF
## Power it must reach before it will advance (0 = go as soon as formed).
var commit_power := 0.0
var peak_power := 0.0
var done := false            # the commander disbands it and pools the units
var _formed_at := -1         # game-time ms the gather started (-1 = unstamped)
## The commander's GAME-time clock, handed in on every tick. Never
## Time.get_ticks_msec(): a squad that measures its muster against the
## wall clock gives up on forming the instant the game is unpaused (see
## CpuAi.clock_ms).
var now_ms := 0
var _intent: Dictionary = {} # unit -> the destination we last sent it to
var _label := ""


func _init(for_team: int = 2, for_mission: Mission = Mission.CAPTURE) -> void:
	team = for_team
	mission = for_mission
	_formed_at = -1  # stamped on the first tick, from the commander's clock


# ---- roster ------------------------------------------------------------

func size() -> int:
	return members.size()


func holds(u: Node) -> bool:
	return members.has(u)


func add(u: Node) -> void:
	if u == null or members.has(u):
		return
	members.append(u)
	peak_power = maxf(peak_power, strength())


## Drop the dead, the boarded and anything that left the world. Returns
## true while the squad still has somebody in it.
func prune() -> bool:
	var live: Array[Node] = []
	for u in members:
		if is_instance_valid(u) and u.alive and not u.carried:
			live.append(u)
		else:
			_intent.erase(u)
	members = live
	return not members.is_empty()


func strength() -> float:
	return AiMap.power_of_all(members)


func centre() -> Vector2:
	if members.is_empty():
		return Vector2.INF
	var sum := Vector2.ZERO
	for u in members:
		sum += (u as Node2D).global_position
	return sum / float(members.size())


## Spread of the squad: how far its furthest member is from its centre.
func spread() -> float:
	var c := centre()
	if c == Vector2.INF:
		return 0.0
	var worst := 0.0
	for u in members:
		worst = maxf(worst, c.distance_to((u as Node2D).global_position))
	return worst


## Every member released back to the commander's pool.
func disband() -> Array[Node]:
	var out := members.duplicate()
	members.clear()
	_intent.clear()
	done = true
	return out


func describe() -> String:
	if _label != "":
		return _label
	return "%s/%s n=%d" % [Mission.keys()[mission], Phase.keys()[phase],
		members.size()]


# ---- the tick ----------------------------------------------------------

## One command cycle. `issue` is CpuAi._order — the relay seam, so squad
## orders reach multiplayer peers like every other AI intent.
func tick(issue: Callable, clock_ms := 0) -> void:
	now_ms = clock_ms
	if _formed_at < 0:
		_formed_at = now_ms
	if not prune():
		done = true
		return
	peak_power = maxf(peak_power, strength())
	if _objective_gone():
		done = true
		return
	# BEATEN IS BEATEN, in any phase. This is checked before the phase
	# machine so a squad being wiped out mid-advance turns around instead
	# of walking the rest of the way in.
	if phase != Phase.FALLING_BACK and peak_power > 0.0 \
			and strength() < peak_power * BREAK_FRACTION \
			and fallback != Vector2.INF:
		phase = Phase.FALLING_BACK
		_intent.clear()
	match phase:
		Phase.GATHERING:
			_gather(issue)
		Phase.ADVANCING:
			_advance(issue)
		Phase.ENGAGED:
			_engage(issue)
		Phase.FALLING_BACK:
			_fall_back(issue)


## The thing we came for is gone: a razed building, a flag that is now
## ours (CAPTURE) or no longer ours to defend (DEFEND).
func _objective_gone() -> bool:
	if objective_node != null and (not is_instance_valid(objective_node) \
			or not objective_node.get("alive")):
		return true
	if zone == null or not is_instance_valid(zone):
		return false
	match mission:
		Mission.CAPTURE:
			return int(zone.owner_team) == team
		Mission.DEFEND:
			return int(zone.owner_team) != team
		_:
			return false


## FORM UP. Members walk to the staging point; the squad commits once it
## is together AND up to weight — or once it has waited long enough that
## the reinforcement it is waiting for is clearly not coming.
func _gather(issue: Callable) -> void:
	var where: Vector2 = staging if staging != Vector2.INF else objective
	if where == Vector2.INF:
		done = true
		return
	var waited: int = now_ms - _formed_at
	var formed: bool = spread() <= COHESION_RADIUS \
			and centre().distance_to(where) <= GATHER_RADIUS
	if (formed and strength() >= commit_power) or waited > GATHER_TIMEOUT_MS:
		phase = Phase.ADVANCING
		_intent.clear()
		_advance(issue)
		return
	_march(issue, where, false)


## ADVANCE AS A BODY. Members inside the squad move on the objective in a
## loose file; a laggard is sent to the squad centre instead, which is
## what keeps the shape on a long march.
func _advance(issue: Callable) -> void:
	if objective == Vector2.INF:
		done = true
		return
	if centre().distance_to(objective) <= ENGAGE_RADIUS:
		phase = Phase.ENGAGED
		_intent.clear()
		_engage(issue)
		return
	_march(issue, objective, true)


## IN CONTACT. The per-unit combat layer does the shooting; the squad's
## only job here is to keep anybody who has gone idle pointed at the
## objective, and to notice when the job is done.
func _engage(issue: Callable) -> void:
	if mission == Mission.ASSAULT and objective_node != null:
		for u in members:
			if u.is_idle():
				issue.call(u, Order.attack(objective_node))
		return
	var hostile := UnitRegistry.current.nearest_enemy(objective, 260.0, team)
	for i in members.size():
		var u: Node = members[i]
		if not u.is_idle():
			continue
		if hostile != null and is_instance_valid(hostile):
			issue.call(u, Order.attack(hostile))
		elif mission == Mission.DEFEND:
			issue.call(u, Order.move_defend(objective + _slot(i)))
		else:
			issue.call(u, Order.move_attack(objective + _slot(i)))


## BREAK CONTACT. Everyone runs for friendly ground; the squad dissolves
## when it gets there and its survivors go back in the pool.
func _fall_back(issue: Callable) -> void:
	if fallback == Vector2.INF:
		done = true
		return
	if centre().distance_to(fallback) <= GATHER_RADIUS:
		done = true
		return
	_march(issue, fallback, false)


## Send the squad at a point, keeping its shape: everyone gets a slot in
## the formation, except laggards, who are told to close up on the squad
## first. `agro` picks attack-move (fight your way there) over move.
func _march(issue: Callable, where: Vector2, agro: bool) -> void:
	var c := centre()
	for i in members.size():
		var u: Node = members[i]
		var at: Vector2 = (u as Node2D).global_position
		var want: Vector2 = where + _slot(i)
		if c != Vector2.INF and at.distance_to(c) > LAG_RADIUS:
			want = c  # close up on the squad, not on the objective
		if not _needs_order(u, want):
			continue
		_intent[u] = want
		issue.call(u, Order.move_attack(want) if agro else Order.move(want))


## Formation slot for member `i` — a shallow block, so a squad arrives on
## a front rather than in a column and does not pile onto one cell.
func _slot(i: int) -> Vector2:
	var per_row: int = maxi(int(ceil(sqrt(float(maxi(members.size(), 1))))), 1)
	var col: int = i % per_row
	var row: int = i / per_row
	return Vector2(float(col) - float(per_row - 1) * 0.5, float(row)) * FILE_SPACING


## AN ORDER IS AN INTERRUPTION. Re-sending the same destination every
## think pass resets the unit's route and its stuck budget, which shows
## up as a squad that stutters and never arrives. So order a unit only
## when it has nothing to do, or when the squad genuinely wants it
## somewhere else.
func _needs_order(u: Node, want: Vector2) -> bool:
	if u.is_idle():
		return true
	var before: Vector2 = _intent.get(u, Vector2.INF)
	return before == Vector2.INF or before.distance_to(want) > REISSUE_PX
