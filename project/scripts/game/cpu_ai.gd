class_name CpuAi
extends Node
## THE CPU OPPONENT, in three layers.
##
##   STRATEGY  AiMap reads the map — a zone graph with adjacency, depth
##             from our own fort, per-sector strength on both sides and
##             per-sector value. `strategy()` turns that read into ONE
##             stance for the whole team (turtle / consolidate / expand /
##             press) and a budget: how much of the army defends, how
##             much attacks, and what it attacks.
##   OPERATIONS AiSquad holds a body of troops with one job. It forms up
##             behind the line, refuses to commit until it is together
##             and strong enough, advances as a body with laggards
##             closing up, and breaks off when it has lost the fight.
##   TACTICS   the per-unit passes below (produce, defend, crew, repair,
##             hold the crossings) plus the ZBot mutual-nearest
##             assignment, which now only sees the units no squad claimed.
##
## THE LAYER THAT WAS MISSING WAS THE MIDDLE ONE. The brain commanded
## individuals: every pass it re-derived "the idle units" and handed each
## the objective nearest it. So the army had no shape — units trickled at
## a target one at a time, arrived alone, died alone, and the next
## trickle walked over them. That reads as "it just storms", and no
## amount of tuning the per-unit pass fixes it, because the problem is
## that there is nothing between the unit and the map.
##
## Every think pass still runs the full OODA loop:
##
## - PRODUCE from every owned facility (money- and pop-gated queues,
##   robots first while the army is small, hardware once a bank buffer
##   exists — cannons round out defences)
## - DEFEND home: enemies inside owned zones or near the fort draw the
##   nearest idle units, who ATTACK-MOVE so they actually fight back
## - MAN empty hardware (vehicles and cannons — the biggest firepower
##   upgrade on any Z map); cranes repair, damaged vehicles visit the
##   repair shop
## - COMMAND THE SQUADS: hold our threatened sectors, take the sectors
##   worth taking, and assault what the stance says to assault
## - ASSIGN the rest (the ZBot Stage1AI_3 port, see "assignment" below):
##   read a POSTURE off how much of the map we hold, collect targets in
##   the original's priority order, and match units to them by MUTUAL
##   NEAREST — so the army spreads over objectives instead of swarming
##   one point, and only a fraction of it is re-tasked per cycle
## - ATTACK in force once the army fits the MAP (small maps push early,
##   large maps build up first) or the AI clearly outnumbers its foes;
##   fresh units stream to the push through factory rally points
##
## Difficulty scales think cadence, attack threshold, manning radius,
## defender count and the money buffer before hardware production.

## Difficulty tuning lives in content/ai/{easy,normal,hard}.tres
## (ContentDB.ai_profile) — THINK cadence, attack size, banking, man
## radius and claims are per-profile now.
const DEFEND_RADIUS := 210.0
const BLACKLIST_MS := 20000
const RETAKE_MS := 45000  # a lost zone stays a priority target this long

var team := 2
var _profile: AiProfileDef
## Starts FULL so the first think fires on the first frame — a fresh
## brain used to sit through one whole think interval (4-6s) before its
## opening move, which read as "the AI does nothing for a long time".
var _accum := 3600.0
## THE BRAIN'S OWN DICE, seeded per match+team. The global randi made
## every brain share one stream AND made headless sims unreproducible;
## a seeded stream plays the same map + seat the same way twice, which
## is what tuning and the tactic lanes need. Only the host runs brains
## and every decision replays over the wire, so the host's stream is
## the only one that matters.
var rng := RandomNumberGenerator.new()
var _zone_blacklist: Dictionary = {}   # zone node -> msec until skipped
var _retake_at: Dictionary = {}        # zone node -> msec lost at
var _owned_snapshot: Dictionary = {}   # zone node -> true (last think)
var _attack_mode := false
var _attack_focus := Vector2.INF
## GAME-TIME CLOCK, in milliseconds, accumulated from the frame delta.
##
## Every cadence in this brain used to read clock_ms — WALL
## clock. That is wrong in three separate ways. Pause the game for two
## minutes and the wall clock runs on, so the first frame after unpause
## fires every timer at once: the assignment re-tasks the whole army, the
## 25s line stickiness evaporates, and every zone blacklist and retake
## window expires together. `Engine.time_scale` desynchronises the same
## way. And a headless sim that hand-steps a hundred think passes in a
## tenth of a second advances no cadence at all, which is why the tactics
## lane was unreproducible.
##
## A brain's sense of time has to be the GAME's sense of time.
var clock_ms := 0
## The strategic read and the squads that act on it (see AiMap/AiSquad).
var _map: AiMap = null
var _squads: Array[AiSquad] = []
var _stance := "consolidate"


func _init(cpu_team: int = 2) -> void:
	team = cpu_team
	# GameState.current_map is set before the loader spawns brains
	rng.seed = hash("zai:%d:%s" % [team, GameState.current_map])


# ---- the relay seam ----------------------------------------------------
# The AI is a COMMANDER, so its intents must travel the same wire a
# player's do. They used to call issue_order/queue_unit/set_rally
# directly, which bypassed Net entirely; combined with every peer running
# its own CpuAi (unseeded randi/randf), the peers' rosters and net-id
# sequences diverged the moment the first CPU unit rolled out, and a
# human's order for "unit 7" hit a different unit on the host. Now only
# the HOST runs a brain (map_loader) and these three funnels replicate
# what it decides.

func _order(u: Node2D, o: Order) -> void:
	u.issue_order(o)
	Net.relay_order(u, o)


func _select(f: Node, item: String) -> bool:
	if not f.select_product(item, true):
		return false
	Net.relay_line(f, item)
	return true


func _rally(f: Node, world_position: Vector2) -> void:
	f.set_rally(world_position)
	Net.relay_rally(f, world_position)


## The difficulty profile (cached once — difficulty is fixed per match).
func _p() -> AiProfileDef:
	if _profile == null:
		_profile = ContentDB.ai_profile(MatchState.current.ai_difficulty)
	return _profile


func _process(delta: float) -> void:
	advance(delta)


## Give the brain `delta` seconds of GAME time: moves its clock and runs a
## think pass when one is due. `_process` is nothing but this, so a test
## can drive the brain exactly the way the engine does.
func advance(delta: float) -> void:
	if GameState.over:
		return
	clock_ms += int(round(delta * 1000.0))
	_accum += delta
	if _accum < _p().think_seconds:
		return
	_accum = 0.0
	_think()


## THE ROSTER, BY ROLE — not by art category.
##
## A CANNON IS A Vehicle2D. That one implementation detail was quietly
## wrong in every pass below, because `vehicles` is the list this brain
## hands to everything that MOVES things: the crossing guards, the squads,
## the push, the ZBot assignment, even the repair-shop run. A cannon has
## speed 0. It cannot walk to a bridge, cannot muster, cannot advance, and
## cannot capture anything, ever.
##
## So a turret drafted as a bridge guard sat wherever it was built holding
## a post it could never reach, while still consuming a guard slot against
## CHOKE_ARMY_SHARE. Drafted into a squad it was worse: AiMap.power_of
## counts it (it is armed), so it inflated the squad's strength, and
## AiSquad.centre() is the mean of its members — so the squad's own centre
## was dragged onto the immobile gun and `_march` told everyone to "close
## up on the squad", i.e. to walk back to the turret. THAT is a whole army
## parked on one bridge around a gun.
##
## The fix is to stop asking what a unit IS and start asking what it can
## DO. `mobile` is everything with speed; `emplacements` are the guns that
## hold the ground they stand on and take no manoeuvre order at all.
func _roster() -> Dictionary:
	var out := {
		"robots": [] as Array[Node],      # own infantry: crews, capturers
		"mobile": [] as Array[Node],      # own hardware that can actually move
		"emplacements": [] as Array[Node],# own guns: speed 0, hold what they see
		"empty": [] as Array[Node],       # unmanned hulls anyone may crew
		"enemy_army": 0,
	}
	for u in UnitRegistry.current.world_units():
		if not (u is Unit2D) or not u.alive or u.carried:
			continue
		if u is Vehicle2D:
			if u.team == team:
				if u.speed > 0.0:
					(out.mobile as Array[Node]).append(u)
				else:
					(out.emplacements as Array[Node]).append(u)
			elif not u.manned:
				(out.empty as Array[Node]).append(u)
			elif u.team != 0:
				out.enemy_army = int(out.enemy_army) + 1
		elif u.kind == "robot":
			if u.team == team:
				(out.robots as Array[Node]).append(u)
			elif u.team != 0:
				out.enemy_army = int(out.enemy_army) + 1
	return out


func _think() -> void:
	var roster := _roster()
	var robots: Array[Node] = roster.robots
	# EVERY pass below gets `mobile`, never the emplacements — see _roster
	var vehicles: Array[Node] = roster.mobile
	var empty_hardware: Array[Node] = roster.empty
	var enemy_army: int = int(roster.enemy_army)
	if robots.is_empty() and vehicles.is_empty() \
			and (roster.emplacements as Array).is_empty():
		return
	if _map == null:
		_map = AiMap.new(team)
	_map.refresh()  # ONE read of the map per pass; every layer below uses it
	_track_lost_zones()
	_produce()
	_defend(robots, vehicles)
	_man_hardware(robots, empty_hardware)
	_maintenance(vehicles)
	_hold_chokepoints(robots, vehicles)
	# the operational layer: squads first, so the per-unit passes below
	# only ever see the units no squad claimed
	_command_squads(robots, vehicles)
	_attack(robots, vehicles, enemy_army)
	_assign(robots, vehicles)
	_update_rallies()


## SORT BY MARCH, NOT BY CROW-FLIGHT — the one "nearest" this brain
## allows. `walk_distance` measures over the nav grid, so a unit across
## the river or behind the fort ranks where its BOOTS put it, not where
## a ruler does, and a unit that cannot legally arrive at all ranks
## last instead of first. Ties break by straight line. `dists` is
## computed once: A* inside a sort comparator would be quadratic.
func _sort_by_walk(units: Array, anchor: Vector2) -> void:
	var dists := {}
	for u in units:
		if is_instance_valid(u):
			dists[u] = _map.walk_distance(anchor, u.global_position)
	units.sort_custom(func(a, b):
		var da: float = float(dists.get(a, INF))
		var db: float = float(dists.get(b, INF))
		if da == db:
			return anchor.distance_squared_to((a as Node2D).global_position) \
				< anchor.distance_squared_to((b as Node2D).global_position)
		return da < db)


# ------------------------- holding ground -------------------------

## A Z map's real chokepoints are its BRIDGES. Infantry fords a river,
## armour does not, so a bridge is the only place tanks cross — whoever
## sits on one decides where the other side's armour can go at all. They
## are explicit map objects, so this needs no terrain analysis and cannot
## be wrong about the map. A destroyed bridge drops out of the list,
## which is right: there is nothing left to hold.
const CHOKE_REFRESH_MS := 8000
## How close a chokepoint has to be to ground we hold to count as ours to
## defend, and how close an enemy/neutral zone has to be for it to be a
## FRONTIER rather than a quiet interior crossing.
const CHOKE_OWN_RANGE := 420.0
const CHOKE_FRONTIER_RANGE := 520.0
## Never tie up more than this share of the army on static defence, or
## the brain stops attacking and just squats.
const CHOKE_ARMY_SHARE := 0.34

var _choke_cache: Array[Vector2] = []
var _choke_stamp := -CHOKE_REFRESH_MS
var _choke_claims: Dictionary = {}   # spot (Vector2) -> guard unit


func _chokepoints() -> Array[Vector2]:
	var now := clock_ms
	if now - _choke_stamp < CHOKE_REFRESH_MS and not _choke_cache.is_empty():
		return _choke_cache
	_choke_stamp = now
	var found: Array[Vector2] = []
	for b in get_tree().get_nodes_in_group(Groups.ALL_BUILDINGS):
		if b is Building2D and b.alive and (b as Building2D).is_bridge():
			found.append((b as Building2D).visual_center())
	_choke_cache = found
	return _choke_cache


## The crossings on the seam between our ground and theirs — the only
## ones worth standing on. An interior bridge deep in our own territory
## needs no guard, and one deep in theirs is an attack, not a hold.
func _frontier_chokepoints() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for spot in _chokepoints():
		var mine := false
		var theirs := false
		for z in MatchState.current.zones:
			var d: float = _zone_center(z).distance_to(spot)
			if z.owner_team == team and d < CHOKE_OWN_RANGE:
				mine = true
			elif z.owner_team != team and d < CHOKE_FRONTIER_RANGE:
				theirs = true
		if mine and theirs:
			out.append(spot)
	return out


## Every unit currently posted on a chokepoint. The push and the zone
## grab both skip these — a guard that gets swept into the next attack
## was never a guard.
func guard_units() -> Dictionary:
	var held := {}
	for spot in _choke_claims:
		var u = _choke_claims[spot]
		if is_instance_valid(u) and u.alive:
			held[u] = true
	return held


func _prune_choke_claims() -> void:
	for spot in _choke_claims.keys():
		var u = _choke_claims[spot]  # untyped: may hold a freed instance
		var stale: bool = (not is_instance_valid(u)) or (not u.alive) or u.carried
		if not stale and u.is_idle() and u.defend_post == Vector2.INF:
			stale = true  # lost its post (re-ordered elsewhere)
		if stale:
			_choke_claims.erase(spot)


## Post a standing guard on each frontier crossing, on DEFEND so it holds
## the spot instead of chasing the first thing that shoots at it.
##
## Without this the brain had nowhere to BE: every unit was either
## answering a named threat, walking to a named zone, or in the push. So
## the moment a push left, the ground behind it was empty and the map
## changed hands behind the army's back — which is what "it just swarms
## your HQ" looks like from the other side.
func _hold_chokepoints(robots: Array[Node], vehicles: Array[Node]) -> void:
	_prune_choke_claims()
	var spots := _frontier_chokepoints()
	if spots.is_empty():
		return
	var army := robots.size() + vehicles.size()
	var cap := int(floor(float(army) * CHOKE_ARMY_SHARE))
	if cap <= 0:
		return
	var per_spot := 1 + clampi(MatchState.current.ai_difficulty, 0, 2) / 2
	var posted := guard_units().size()
	var already := {}
	for u in guard_units():
		already[u] = true
	var in_squads := squad_units()
	var free_units: Array[Node] = []
	for u in _idle_of(robots) + _idle_of(vehicles):
		if not already.has(u) and not in_squads.has(u):
			free_units.append(u)
	for spot in spots:
		if posted >= cap or free_units.is_empty():
			return
		var here := 0
		for other in _choke_claims:
			if other == spot:
				here += 1
		if here >= per_spot:
			continue
		_sort_by_walk(free_units, spot)
		var guard: Node = free_units.pop_front()
		if not is_instance_valid(guard):
			continue
		# DEFEND, not move: the unit walks there and re-holds the post if
		# it gets shoved off, which is the whole point of a guard
		_order(guard, Order.move_defend(spot
			+ Vector2(rng.randf_range(-18.0, 18.0), rng.randf_range(-18.0, 18.0))))
		_choke_claims[spot] = guard
		posted += 1


## Which of our facilities sits closest to ground we do NOT hold. Cannons
## cannot be moved once built (speed 0 by design, like the original's
## emplaced guns), so the ONLY way the brain can choose where its static
## defence ends up is to choose which building makes it. Building a gun
## at the safe factory in the back was pure waste.
func _frontier_facility() -> Node:
	var target := Vector2.INF
	var best_d := INF
	for z in MatchState.current.zones:
		if z.owner_team == team:
			continue
		var c: Vector2 = _zone_center(z)
		for other in MatchState.current.zones:
			if other.owner_team != team:
				continue
			var d: float = _zone_center(other).distance_squared_to(c)
			if d < best_d:
				best_d = d
				target = c
	if target == Vector2.INF:
		return null
	var pick: Node = null
	var pick_d := INF
	for f in get_tree().get_nodes_in_group(Groups.FACILITIES):
		if not f.alive or f.team != team:
			continue
		var d: float = _map.walk_distance(target,
			(f as Node2D).global_position)
		if d < pick_d:
			pick_d = d
			pick = f
	return pick


# ------------------------- production -------------------------

## POINT EVERY FACILITY AT SOMETHING AND LEAVE IT ALONE.
##
## There is no queue to stuff (see ProductionLine): a facility is aimed at
## ONE type and turns it out until it is re-aimed. So this pass is no
## longer "spend money on four things"; it is "is this building making the
## right thing, and if not, what should it make instead".
##
## THE LINE IS STICKY ON PURPOSE. Re-rolling the weighted pick every think
## pass would re-aim every factory every second or two, and with switching
## keeping the clock that means a factory whose choice keeps changing never
## finishes anything recognisable — it would emit a random unit each time
## the timer happened to land. So a line is only re-aimed when it is
## genuinely wrong (idle, off-roster, or a cannon at a building that must
## not make cannons) or when RELINE_MS has passed since the last change
## AND the stance has moved on.
const RELINE_MS := 25000
## HARDWARE ROLLS OFF THE LINE UNMANNED. A vehicle or a cannon is a hull
## until a robot walks over and gets in (Producer.spawn_produced spawns
## them team 0), so infantry is not one option among several — it is the
## thing that makes every other option work. A brain that fills its
## factories with tanks while it owns no robots builds a car park.
##
## So production keeps a CREW RESERVE: this many spare robots on top of
## one for every empty hull already standing near home. Below that, every
## facility that can make robots makes robots, and the stickiness above
## does not get to hold a hardware line in place.
const CREW_RESERVE := 3
## How far from home an empty hull counts as ours to crew.
const CREW_LOOK := 700.0

var _line_stamp: Dictionary = {}   # facility -> msec of its last re-aim
var _line_stance: Dictionary = {}  # facility -> stance it was aimed under


func _produce() -> void:
	var diff := clampi(MatchState.current.ai_difficulty, 0, 2)
	var army_pop := MatchState.current.unit_pop(team)
	var frontier := _frontier_facility()
	var now := clock_ms
	var short_of_crew := crew_shortfall()
	# THE TOOL NEEDS ARE A SHOPPING LIST, NOT A PREDICATE. _utility_need
	# answers "does the war want one of these?" — a GLOBAL question — and
	# it used to be asked once per facility, so every factory that could
	# build an APC aimed at one on the same pass. Three vehicle factories
	# and the fort all turning out APCs is not a transport policy, it is
	# the same decision made four times. Build the list once and let each
	# facility CLAIM from it.
	var needs: Array = [] if short_of_crew > 0 else _utility_needs()
	for f in get_tree().get_nodes_in_group(Groups.FACILITIES):
		if not f.alive or f.team == 0 or f.team != team:
			continue
		var options: Array = f.build_options()
		if options.is_empty():
			continue
		# AN IDLE FACILITY IS FIXED FIRST, BEFORE ANY OTHER REASONING.
		# Every branch below can `continue` — the stickiness gate, the tool
		# claim, an empty choice list after filtering — and any of them
		# leaving the line empty means a factory the brain owns produces
		# nothing at all for the rest of the match. That is strictly worse
		# than any choice it could have made, so it gets the first entry of
		# its own list up front (the same default Producer._ensure_default
		# uses) and the reasoning below then refines it. Making the
		# invariant structural beats hunting the one path that broke it.
		if f.selected_product() == "":
			_select(f, String(options[0]))
		# FIRST SIGHTING COUNTS AS A DECISION. Without this an unstamped
		# facility reads as instantly stale (now - (-RELINE_MS) is already
		# a full window), so the very first think pass after a factory is
		# captured — or after Producer._ensure_default aims it at the first
		# entry of its own list — threw that line away and re-rolled it.
		# The default is a decision; record it as one.
		if not _line_stamp.has(f):
			_line_stamp[f] = now
			_line_stance[f] = _stance
		# a CANNON is immobile once built, so where it appears is decided
		# entirely by which building makes it: only the facility nearest
		# the frontier may hold a cannon line, and anywhere else re-aims
		# at something that can walk to the fight
		var current: String = f.selected_product()  # after the default above
		var cannon_ok: bool = f == frontier
		var makes_robots: bool = false
		for o in options:
			if String(o).begins_with("robot:"):
				makes_robots = true
				break
		# NO CREW, NO HARDWARE. A hardware line while we are short of
		# infantry is wrong however recently it was chosen, so this
		# preempts the stickiness below — that is the difference between
		# "the brain prefers robots" and "the brain understands that a
		# tank without a driver is scrap".
		var crew_short: bool = short_of_crew > 0
		var wrong: bool = current == "" or not options.has(current) \
			or (current.begins_with("cannon:") and not cannon_ok) \
			or (crew_short and makes_robots and not current.begins_with("robot:"))
		var stale: bool = now - int(_line_stamp.get(f, -RELINE_MS)) >= RELINE_MS \
			and String(_line_stance.get(f, "")) != _stance
		if not wrong and not stale:
			continue
		var choices: Array = options
		if not cannon_ok:
			choices = options.filter(
				func(i): return not String(i).begins_with("cannon:"))
		# UNARMED UNITS ARE NOT A PRODUCTION LINE. An APC and a crane both
		# have damage 0, and under a queue the brain could afford to order
		# one now and then. A LINE is forever: parking a vehicle factory on
		# APCs means that factory never contributes another gun to the war
		# for the rest of the match. So utility hulls are off the ordinary
		# choice entirely, and built only when something actually needs
		# one — see _utility_need below.
		# claim a tool this facility can actually build
		var need := ""
		for want in needs:
			if choices.has(want):
				need = String(want)
				break
		if need != "":
			if need == current or _select(f, need):
				needs.erase(need)  # claimed: nobody else builds this one
				_line_stamp[f] = now
				_line_stance[f] = _stance
				continue
		choices = choices.filter(func(i):
			var p: PackedStringArray = String(i).split(":")
			return p.size() == 2 and ContentDB.def_for(p[0], p[1]).damage > 0)
		if crew_short and makes_robots:
			var infantry: Array = choices.filter(
				func(i): return String(i).begins_with("robot:"))
			if not infantry.is_empty():
				choices = infantry
		# THE BANK STILL MEANS SOMETHING, it just means something else.
		# Money used to be spent when an item was queued, so the profile's
		# reserve gated the enqueue. A line pays per unit as it starts, so
		# the reserve now gates the CHOICE: a poor team does not park its
		# factory on a unit it cannot keep paying for, because a stalled
		# line produces nothing at all while a robot line keeps delivering.
		if int(MatchState.current.money.get(team, 0)) < _p().bank_before_vehicle:
			var cheap: Array = choices.filter(
				func(i): return not String(i).begins_with("vehicle:"))
			if not cheap.is_empty():
				choices = cheap
		if choices.is_empty():
			continue
		# STAMP THE DECISION, NOT THE CHANGE. This used to record the
		# timestamp only when the re-roll actually moved the line, so a
		# stale facility whose weighted pick happened to land on what it
		# was already building stayed stale — and rolled again, every
		# single pass, until the dice finally differed. The observable
		# effect was one or two factories quietly reshuffling their line
		# forever while the rest held. Reassessing IS the decision.
		var pick := String(_weighted_pick(choices, army_pop, diff))
		_line_stamp[f] = now
		_line_stance[f] = _stance
		if pick != current:
			_select(f, pick)  # a refusal leaves the default set above


## HOW MANY ROBOTS ARE WE SHORT OF? Positive means every hull we could
## build would sit empty — one crew per empty hull already standing near
## home, plus CREW_RESERVE spare so the next tank has a driver waiting.
## Empty hulls are counted near HOME only: the derelicts scattered across
## the far side of a Z map are not ours to crew and must not talk the
## brain out of ever building hardware.
func crew_shortfall() -> int:
	var robots := 0
	var empty_near := 0
	var home: Vector2 = _map.home if _map != null else Vector2.INF
	for u in UnitRegistry.current.world_units():
		if not u.alive or u.carried:
			continue
		if u is Vehicle2D:
			if not u.manned and u.team == 0 and home != Vector2.INF \
					and u.global_position.distance_to(home) < CREW_LOOK:
				empty_near += 1
		elif u.team == team and u.kind == "robot":
			robots += 1
	return (empty_near + CREW_RESERVE) - robots


## WHAT TOOLS DOES THE WAR WANT RIGHT NOW? The two unarmed hulls earn a
## factory slot only against a concrete need, and the list is capped at
## what is actually wanted — one entry per hull we are missing, claimed by
## the first facility that can build it (see _produce).
##
##   CRANE  something of ours is broken (or a bridge is down) and we own
##          no crane to fix it. _maintenance already knows what to do with
##          one; it just never had one to work with.
##   APC    we hold ground far from the fighting and have infantry to move.
##          Deliberately conservative: one is plenty, and a second is a
##          factory not making guns.
func _utility_needs() -> Array:
	var have_crane := 0
	var have_apc := 0
	for u in UnitRegistry.current.world_units():
		if u.team != team or not u.alive:
			continue
		if u.unit_name == "crane":
			have_crane += 1
		elif u.unit_name == "apc":
			have_apc += 1
	var out: Array = []
	if have_crane == 0:
		for b in BuildingRegistry.all():
			if not (b is Building2D) or not b.alive:
				continue
			var bld := b as Building2D
			if bld.hp < bld.max_hp and (bld.is_bridge() or bld.team == team):
				out.append("vehicle:crane")
				break
	if have_apc == 0 and _map != null and _map.zones_held >= 3:
		out.append("vehicle:apc")
	return out


## Robots while the army is small, hardware once it stands — and fresh
## options (vehicles, cannons) get a boost so the AI uses its roster.
##
## THE STANCE TILTS IT. A brain that is turtling wants emplaced guns and
## bodies to hold ground with; a brain that is pressing wants armour,
## because a fort is not coming down to rifles. Building the same mix
## whatever the situation is the production half of "it has no strategy".
func _weighted_pick(options: Array, army_pop: int, _diff: int) -> String:
	var weights: Array = []
	for item in options:
		var kind := String(item).split(":")[0]
		var w := 3
		if kind == "robot":
			w = 8 if army_pop < 10 else 5
		elif kind == "cannon":
			w = 4
		match _stance:
			"turtle":
				if kind == "cannon":
					w += 4
				elif kind == "robot":
					w += 2
			"press":
				if kind == "vehicle":
					w += 4
				elif kind == "cannon":
					w = maxi(w - 2, 1)
			"expand":
				# GROUND IS TAKEN BY THINGS THAT MOVE. A jeep crosses a Z
				# map at 73px/s against a grunt's 60 and survives being
				# shot at on the way, so expanding wants wheels as much as
				# bodies — and a cannon can never take a sector at all.
				if kind == "robot":
					w += 1
				elif kind == "vehicle":
					w += 3
				elif kind == "cannon":
					w = maxi(w - 2, 1)
		weights.append(w)
	var total := 0
	for w in weights:
		total += int(w)
	var roll := rng.randi() % total
	for i in options.size():
		roll -= int(weights[i])
		if roll < 0:
			return String(options[i])
	return String(options[0])


# ------------------------- defense -------------------------

## Enemy units near our fort or standing in an owned zone draw the
## closest idle defenders, who ATTACK-MOVE so they engage on the way —
## the AI never ignores its own territory.
func _defend(robots: Array[Node], vehicles: Array[Node]) -> void:
	var fort := _own_fort()
	var threats: Array[Node] = []
	for u in UnitRegistry.current.world_units():
		if u is Node2D and u.alive and u.team != 0 and u.team != team and not u.carried:
			if fort and u.global_position.distance_to(fort.visual_center()) < DEFEND_RADIUS:
				threats.append(u)
				continue
			for z in MatchState.current.zones:
				if z.owner_team == team and z.world_rect().has_point(u.global_position):
					threats.append(u)
					break
	if threats.is_empty():
		return
	var responders := 1 + clampi(MatchState.current.ai_difficulty, 0, 2)
	# A UNIT UNDER SQUAD ORDERS IS NOT SPARE. This pass used to grab any
	# idle unit, squad members included, so a strike squad that paused for
	# a breath was picked apart by the reactive layer and the assault
	# dissolved. The DEFEND squads answer sector incursions now; this pass
	# is the reflex for whatever is loose.
	var committed := _committed()
	var defenders: Array[Node] = []
	for u in _idle_of(robots) + _idle_of(vehicles):
		if not committed.has(u):
			defenders.append(u)
	for threat in threats:
		if defenders.is_empty() or not is_instance_valid(threat):
			continue
		_sort_by_walk(defenders, threat.global_position)
		for i in mini(responders, defenders.size()):
			var d: Node = defenders.pop_front()
			if is_instance_valid(d):
				_order(d, Order.move_attack(threat.global_position
					+ Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-14.0, 14.0))))


# ------------------------- manning hardware -------------------------

## Idle robots walk to the best unmanned vehicle/cannon in range —
## combat hardware first, transports last, cranes only as a fallback.
func _man_hardware(robots: Array[Node], empty_hardware: Array[Node]) -> void:
	if empty_hardware.is_empty():
		return
	var radius: float = _p().man_radius
	for r in robots:
		if r.enter_target != null and is_instance_valid(r.enter_target):
			empty_hardware.erase(r.enter_target)  # already walking to it
	var idle := _idle_of(robots)
	idle.sort_custom(func(a, b): return a.hp > b.hp)  # healthy troops crew guns
	for r in idle:
		if empty_hardware.is_empty():
			return
		var best: Node = null
		var best_score := INF
		for hw in empty_hardware:
			if not is_instance_valid(hw) or not hw.alive or hw.manned:
				continue
			var dist: float = _map.walk_distance(
				r.global_position, hw.global_position)
			if dist > radius:
				continue
			var score := dist + int(_p().man_priority.get(hw.unit_name, 5)) * 30.0
			if score < best_score:
				best_score = score
				best = hw
		if best != null:
			empty_hardware.erase(best)
			_order(r, Order.for_target(best))


# ------------------------- maintenance -------------------------

## Damaged vehicles head for the repair shop; cranes set up on the
## nearest wrecked building or bridge (original: the bot's
## repair_building_list orders).
func _maintenance(vehicles: Array[Node]) -> void:
	var repair_shop: Building2D = null
	var damaged_buildings: Array[Node] = []
	# "all_buildings": the repair shop and the bridges sit in none of the
	# narrower groups — scanning "facilities"/"buildings" never found them
	for b in get_tree().get_nodes_in_group(Groups.ALL_BUILDINGS):
		if not (b is Building2D) or not b.alive:
			continue
		if b.is_bridge():
			# bridges are communal: any crane rebuilds the rubble
			if b.hp < b.max_hp:
				damaged_buildings.append(b)
		elif b.team == team:
			if b.is_repair_shop():
				repair_shop = b
			elif b.hp < b.max_hp and not b.is_fort:
				# forts are not crane-repairable — sending cranes to park
				# on a damaged fort healed it faster than any assault
				damaged_buildings.append(b)
	for v in vehicles:
		if v.enter_target != null:
			continue  # already tasked
		if v.unit_name == "crane" and not damaged_buildings.is_empty():
			var best_b: Node = null
			var best_d := INF
			for b in damaged_buildings:
				var d: float = _map.walk_distance(v.global_position,
					b.world_footprint().get_center())
				if d < best_d:
					best_d = d
					best_b = b
			if best_b != null:
				damaged_buildings.erase(best_b)
				_order(v, Order.for_target(best_b))
		elif repair_shop != null and v.hp < v.max_hp * 0.5 \
				and v.kind == "vehicle":
			_order(v, Order.for_target(repair_shop))


# ------------------------- zone capture -------------------------

## Remember zones that flipped away from us — they stay juicy targets.
func _track_lost_zones() -> void:
	var now_owned: Dictionary = {}
	for z in MatchState.current.zones:
		if z.owner_team == team:
			now_owned[z] = true
	for z in _owned_snapshot:
		if not now_owned.has(z):
			_retake_at[z] = clock_ms + RETAKE_MS
	for z in _retake_at.keys():
		if clock_ms > int(_retake_at[z]) or now_owned.has(z):
			_retake_at.erase(z)
	_owned_snapshot = now_owned


# ------------------------- strategy & squads -------------------------
#
# The two layers the brain did not have. `strategy()` is the WHOLE-TEAM
# decision, taken once per pass off the AiMap read; `_command_squads`
# turns it into standing bodies of troops with jobs, and keeps them
# staffed. Everything below the squads (the ZBot assignment, the push)
# only ever sees units no squad claimed — that separation is the point.
# Two layers both commanding the same unit is worse than either alone:
# it is what made units stop mid-path and turn around every second.

## STANCES. Read as: how much of the army holds ground, how many
## simultaneous strike squads to run, and whether a strike is allowed to
## go for STRUCTURES (factories, then the fort) rather than just ground.
##
##   turtle       losing the power fight, or our own home is under
##                pressure: nearly everything defends, nothing attacks
##   consolidate  even fight: hold the worst front, take one cheap sector
##   expand       we out-power them but do not hold the map: two strike
##                squads on the sectors worth the least resistance
##   press        ahead on power AND on ground: strike squads go for
##                their production and then their fort
const STANCES := {
	"turtle":      {"defend": 0.75, "strikes": 0, "structures": false, "commit": 1.5},
	"consolidate": {"defend": 0.45, "strikes": 1, "structures": false, "commit": 1.3},
	"expand":      {"defend": 0.30, "strikes": 2, "structures": false, "commit": 1.15},
	"press":       {"defend": 0.22, "strikes": 2, "structures": true,  "commit": 1.0},
}
## A zone this many hops from our fort or closer is HOME: pressure there
## is an emergency, pressure further out is just the front moving.
const HOME_DEPTH := 1
## Never tie up more than this share of the army in squads — the crews,
## the crate runs and the crossing guards need bodies too.
const SQUAD_ARMY_SHARE := 0.8
## Squad sizes. A squad below MIN_SQUAD is not a squad, it is a casualty
## report; above MAX_SQUAD it cannot keep formation on a Z map's roads.
const MIN_SQUAD := 3
const MAX_SQUAD := 8
## Floor on what a strike squad must weigh before it commits, so an
## undefended sector does not get taken by one grunt who then dies to the
## first counter-attack.
const MIN_COMMIT_POWER := 120.0


## THE WHOLE-TEAM DECISION, off the map read. Power ratio says whether we
## can win a fight; map share says whether we need to. Home pressure
## overrides both — a brain attacking while its fort burns is the failure
## mode every "the AI ignores its own base" report describes.
func strategy() -> Dictionary:
	if _map == null:
		_map = AiMap.new(team)
		_map.refresh()
	var ratio: float = _map.power_ratio()
	var share: float = _map.share_held()
	var home_pressure := 0.0
	for t in _map.threatened_zones():
		var entry: Dictionary = _map.entry_of(t.zone)
		if int(entry.get("depth", AiMap.UNREACHABLE_DEPTH)) <= HOME_DEPTH:
			home_pressure = maxf(home_pressure, float(t.raw))
	var name := "consolidate"
	# home pressure has to be a REAL force, not one scout that wandered
	# in: a brain that turtles at the sight of a single enemy robot never
	# leaves its base at all
	if home_pressure > maxf(_map.own_power * 0.35, MIN_COMMIT_POWER) \
			or ratio < 0.65:
		name = "turtle"
	elif ratio >= 1.35 and share >= 0.4:
		name = "press"
	elif ratio >= 0.95:
		name = "expand"
	_stance = name
	var out: Dictionary = (STANCES[name] as Dictionary).duplicate()
	out["name"] = name
	out["ratio"] = ratio
	out["share"] = share
	out["home_pressure"] = home_pressure
	return out


## Every unit currently spoken for by a squad — the pool the tactical
## passes must NOT touch.
func squad_units() -> Dictionary:
	var out := {}
	for sq in _squads:
		for u in sq.members:
			if is_instance_valid(u):
				out[u] = true
	return out


## Guards plus squad members: everything already under orders from a
## layer above the per-unit one.
func _committed() -> Dictionary:
	var out := guard_units()
	for u in squad_units():
		out[u] = true
	return out


## Raise, staff, retire. One pass:
##   1. tick the squads that exist (they issue their own orders)
##   2. retire the ones whose job is done or who are gone
##   3. work out which sectors need a squad and which are worth one
##   4. reinforce what exists before raising anything new
func _command_squads(robots: Array[Node], vehicles: Array[Node]) -> void:
	var plan := strategy()
	# 1+2. run and retire. A stance that has stopped allowing strikes
	# RECALLS the ones in flight instead of letting them finish a plan the
	# team can no longer afford — that is the whole point of having a
	# stance: an attack launched while we were ahead is a liability once
	# our own home is under pressure.
	var recall: bool = int(plan.strikes) <= 0
	var live: Array[AiSquad] = []
	for sq in _squads:
		if recall and sq.mission != AiSquad.Mission.DEFEND \
				and sq.phase != AiSquad.Phase.FALLING_BACK:
			sq.phase = AiSquad.Phase.FALLING_BACK
		sq.tick(_order, clock_ms)
		if sq.done or sq.size() == 0:
			sq.disband()  # survivors fall back into the free pool
			continue
		live.append(sq)
	_squads = live
	# 3. the free pool: not guarding a crossing, not already in a squad,
	# not walking into a hull or a repair shop (those errands are worth
	# more than one more rifle in a line)
	var claimed := _committed()
	var pool: Array[Node] = []
	for u in robots + vehicles:
		if not is_instance_valid(u) or not u.alive or u.carried:
			continue
		if claimed.has(u) or u.enter_target != null:
			continue
		if AiMap.power_of(u) <= 0.0:
			continue  # cranes and empty transports are not line troops
		pool.append(u)
	var army_power: float = _map.own_power
	var in_squads: float = 0.0
	for sq in _squads:
		in_squads += sq.strength()
	var budget: float = army_power * SQUAD_ARMY_SHARE - in_squads
	# 4. the jobs, defence first: ground already ours is cheaper to hold
	# than to retake, and a fort lost is the match
	var jobs: Array = _defence_jobs(plan) + _strike_jobs(plan)
	for job in jobs:
		if pool.is_empty():
			break
		var existing: AiSquad = _squad_for(job)
		if existing != null:
			budget -= _reinforce(existing, job, pool, budget)
			continue
		if budget <= 0.0:
			break
		budget -= _raise_squad(job, pool, budget)


## Which of OUR sectors need holding, worst first. Only sectors under
## real pressure or on the seam get a squad — parking on quiet interior
## ground is how a brain talks itself out of ever attacking.
func _defence_jobs(plan: Dictionary) -> Array:
	var out: Array = []
	var allowance: float = _map.own_power * float(plan.defend)
	var spent := 0.0
	for t in _map.threatened_zones():
		if spent >= allowance:
			break
		# A QUIET FRONT NEEDS NO SQUAD. threatened_zones lists our border
		# sectors whether or not anything is actually pressing on them,
		# and raising a standing squad for every quiet seam parks the
		# whole army on empty ground — the crossing guards already cover
		# the seam, and a squad that is not needed is an attack that does
		# not happen.
		if float(t.raw) <= 0.0:
			continue
		var entry: Dictionary = _map.entry_of(t.zone)
		var need: float = maxf(float(t.raw) * 1.2, MIN_COMMIT_POWER * 0.6)
		out.append({
			"kind": "defend", "zone": t.zone, "at": t.at, "node": null,
			"need": need, "commit": 0.0,
			"staging": t.at, "fallback": _fallback_near(t.at),
			"home": int(entry.get("depth", 9)) <= HOME_DEPTH,
		})
		spent += need
	return out


## What is worth going after, best first: the sectors whose value beats
## their resistance and their march, and — when the stance allows it —
## the structures inside them.
func _strike_jobs(plan: Dictionary) -> Array:
	var out: Array = []
	var wanted := int(plan.strikes)
	if wanted <= 0:
		return out
	if bool(plan.structures):
		for b in _strike_structures():
			if out.size() >= wanted:
				break
			out.append({
				"kind": "assault", "zone": _map.zone_at(b.visual_center()),
				"at": b.visual_center(), "node": b,
				"need": maxf(_map.foe_power * 0.35, MIN_COMMIT_POWER),
				"commit": float(plan.commit),
				"staging": _staging_toward(b.visual_center()),
				"fallback": _fallback_near(b.visual_center()), "home": false,
			})
	for t in _map.target_zones():
		if out.size() >= wanted:
			break
		if _blacklisted(t.zone):
			continue
		# AN EMPTY NEUTRAL FLAG IS NOT A SQUAD JOB. Walking onto ground
		# nobody is standing on takes one unit, and the mutual-nearest
		# assignment below already spreads single units over exactly this
		# kind of target. Forming a squad for it costs the early
		# expansion that decides a Z map — squads are for ground that is
		# HELD, and for structures.
		if bool(t.neutral) and float(t.foe) <= 0.0:
			continue
		out.append({
			"kind": "capture", "zone": t.zone, "at": t.at, "node": null,
			"need": maxf(float(t.foe) * 1.4, MIN_COMMIT_POWER),
			"commit": float(plan.commit),
			"staging": _staging_toward(t.at),
			"fallback": _fallback_near(t.at), "home": false,
		})
	return out


## Enemy structures worth a squad, production before the fort: a factory
## denied is an army that never arrives, and the original bot lists
## buildings above units for the same reason. The fort comes last because
## it is the hardest target on the map, not because it matters least.
func _strike_structures() -> Array:
	var producers: Array = []
	var forts: Array = []
	for b in BuildingRegistry.all():
		if not (b is Building2D) or not b.alive or (b as Building2D).is_bridge():
			continue
		var bld := b as Building2D
		if bld.team == 0 or bld.team == team:
			continue
		if bld.is_fort:
			forts.append(bld)
		elif bld.produces_anything():
			producers.append(bld)
	# march order from home, not crow-flight: the fort across the river
	# is the LAST thing this brain wants, however close it looks
	var from: Vector2 = _map.home if _map.home != Vector2.INF else Vector2.ZERO
	for list in [producers, forts]:
		var dists := {}
		for b in list:
			dists[b] = _map.walk_distance(from, b.visual_center())
		list.sort_custom(func(a, b):
			var da: float = float(dists.get(a, INF))
			var db: float = float(dists.get(b, INF))
			if da == db:
				return from.distance_squared_to(a.visual_center()) \
					< from.distance_squared_to(b.visual_center())
			return da < db)
	return producers + forts


## The squad already doing this job, if any. Jobs are keyed by their
## OBJECT (a structure) or their SECTOR, so the commander cannot raise
## two squads for one flag every time it thinks.
func _squad_for(job: Dictionary) -> AiSquad:
	for sq in _squads:
		if job.node != null and sq.objective_node == job.node:
			return sq
		if job.node == null and job.zone != null and sq.zone == job.zone \
				and sq.mission == _mission_of(job):
			return sq
	return null


static func _mission_of(job: Dictionary) -> AiSquad.Mission:
	match String(job.kind):
		"defend":
			return AiSquad.Mission.DEFEND
		"assault":
			return AiSquad.Mission.ASSAULT
		_:
			return AiSquad.Mission.CAPTURE


## Staff a new squad from the pool: the units nearest its staging point,
## up to the weight the job asks for. Returns the power committed.
func _raise_squad(job: Dictionary, pool: Array[Node], budget: float) -> float:
	var want: float = minf(float(job.need), budget)
	var sq := AiSquad.new(team, _mission_of(job))
	sq.zone = job.zone
	sq.objective = job.at
	sq.objective_node = job.node
	sq.staging = job.staging
	sq.fallback = job.fallback
	sq.commit_power = float(job.need) * float(job.commit)
	var taken := _draft(sq, pool, want, job)
	if sq.size() < MIN_SQUAD and not bool(job.home):
		# not enough bodies for a real squad and not an emergency: put
		# them back rather than send three men at a defended sector
		for u in sq.disband():
			pool.append(u)
		return 0.0
	_squads.append(sq)
	return taken


## Top an existing squad back up to its job's weight — a squad that has
## taken losses gets replacements instead of being disbanded and re-raised
## somewhere else, which is what made objectives change hands every pass.
func _reinforce(sq: AiSquad, job: Dictionary, pool: Array[Node],
		budget: float) -> float:
	sq.objective = job.at
	sq.objective_node = job.node
	sq.fallback = job.fallback
	var short: float = float(job.need) - sq.strength()
	if short <= 0.0 or sq.size() >= MAX_SQUAD or budget <= 0.0:
		return 0.0
	return _draft(sq, pool, minf(short, budget), job)


## Pull the nearest suitable units out of the pool until the squad has
## the weight it needs (or the size cap stops it). Returns the power
## actually taken.
func _draft(sq: AiSquad, pool: Array[Node], want: float,
		job: Dictionary) -> float:
	var anchor: Vector2 = job.staging if job.staging != Vector2.INF else job.at
	_sort_by_walk(pool, anchor)
	var taken := 0.0
	while not pool.is_empty() and sq.size() < MAX_SQUAD and taken < want:
		var u: Node = pool.pop_front()
		if not is_instance_valid(u):
			continue
		sq.add(u)
		taken += AiMap.power_of(u)
	return taken


## Where a squad forms up before going at `target`: the centre of our own
## sector nearest it. Massing on friendly ground and then walking in as a
## body is the whole difference between an assault and a trickle.
func _staging_toward(target: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for z in MatchState.current.zones:
		var entry: Dictionary = _map.entry_of(z)
		if entry.is_empty() or int(entry.owner) != team:
			continue
		var d: float = _map.walk_distance(target, entry.at)
		if d < best_d:
			best_d = d
			best = entry.at
	if best == Vector2.INF:
		return _map.home
	# stand off the target rather than in our sector's dead centre
	return best.lerp(target, 0.25)


## Where a beaten squad runs to: our quietest ground near it, else the
## fort. A squad with nowhere to fall back to fights where it stands,
## which is correct — there is nothing left behind it.
func _fallback_near(from: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for r in _map.rally_zones():
		var d: float = _map.walk_distance(from, r.at)
		if d < best_d:
			best_d = d
			best = r.at
	return best if best != Vector2.INF else _map.home


# ------------------------- assignment (ZBot Stage1AI_3) -------------------------
# The original bot does NOT pick one focus and send everyone at it. Per
# order cycle it:
#   1. reads a POSTURE off how much of the map it holds (GoAllOut_3),
#      which sets what FRACTION of the idle army is re-tasked and how
#      long until the next cycle;
#   2. collects TARGETS in a fixed priority order (CollectOurTargets_3):
#      map items, then buildings, then empty hardware, and enemy UNITS
#      only once it is "all out";
#   3. matches units to targets by MUTUAL NEAREST (MatchTargets_3 +
#      GiveOutOrders_3) — a pair is ordered only when the unit is that
#      target's nearest candidate AND that target is the unit's nearest.
#      A unit with no mutual partner is LEFT ALONE this cycle.
#
# Step 3 is what stops the swarm. Our old _capture_zones handed one unit
# per zone by nearest-first and _attack walked every remaining idle unit
# to a single ring, so the army pinballed between objectives and the
# ground behind it emptied.

## POSTURE, from ZBot::GoAllOut_3. `share` is our fraction of the map's
## zones; `fair` is 1/teams. Read the table the right way round: holding
## MORE than a fair share does not mean throwing everything forward — it
## means the map is already ours, so the bot commits a SMALL slice on a
## SLOW cadence and instead WIDENS what it will shoot at (`all_out` adds
## enemy units and robots to the target list). Falling behind means
## re-tasking a third of the army every few seconds.
const POSTURE_ALL_OUT := {"commit": 0.15, "delay": 12.0, "all_out": true}
const POSTURE_HOLDING := {"commit": 0.25, "delay": 5.0, "all_out": false}
const POSTURE_LOSING := {"commit": 0.35, "delay": 4.0, "all_out": false}
## How many units may pile onto ONE target in a cycle. Buildings soak a
## squad (this is the focus fire we had none of); everything else takes
## one, so the army fans out.
const SLOTS_BUILDING := 4
## A unit under this share of its HP breaks off and heads for a repair
## shop instead of taking an objective — the original lists its own
## repair stations as valid targets for exactly this.
const RETREAT_AT := 0.4

var _next_assign_ms := 0


func posture() -> Dictionary:
	var teams := {}
	var held := 0
	for z in MatchState.current.zones:
		if z.owner_team != 0:
			teams[z.owner_team] = true
		if z.owner_team == team:
			held += 1
	var total: int = maxi(MatchState.current.zones.size(), 1)
	var fair := 1.0 / float(maxi(teams.size(), 2))
	var share := float(held) / float(total)
	if share >= fair:
		return POSTURE_ALL_OUT
	if share >= fair * 0.25:
		return POSTURE_HOLDING
	return POSTURE_LOSING


## Everything worth walking to, in the original's priority order. Each
## entry is {at, node, kind, slots} — `node` is null for a zone flag
## (a place, not a thing). Priority is the ORDER of the list; the
## matching then decides who goes where.
func _collect_targets(all_out: bool) -> Array:
	var out: Array = []
	# 1. MAP ITEMS: the zone flags we do not own, and loose crates.
	#    Zone scoring survives from the old grab — a flag next to
	#    buildings, on the frontier, or one we just lost is worth a
	#    longer walk, expressed as a distance BIAS on the match.
	var flags: Array = []
	for z in MatchState.current.zones:
		if z.owner_team == team or _blacklisted(z):
			continue
		# A HELD ENEMY FLAG IS NOT A ONE-ROBOT ERRAND. The assignment used
		# to offer every flag we do not own, so on first think the whole
		# starting squad marched INTO the nearest enemy's home sector —
		# arriving by the half minute and dying on their fort's guns (or
		# worse: razing a defenceless owner and ending the match at
		# t=16s). Held ground is SQUAD work (see _strike_jobs); single
		# units grab neutral flags, until the posture goes all out.
		if z.owner_team != 0 and not all_out:
			continue
		var bias := 1.0
		if _zone_has_building(z):
			bias *= 0.4
		if _zone_touches_owned(z):
			bias *= 0.7
		if _retake_at.has(z):
			bias *= 0.5
		if z.owner_team != 0:
			bias *= 1.5  # neutral land before a fight
		flags.append({"at": _zone_center(z), "node": null, "kind": "flag",
			"slots": 1, "bias": bias, "zone": z})
	# the profile's max_claims keeps its old meaning — how many zone
	# grabs may be in flight — as a cap on the FLAG targets offered per
	# cycle, best-biased first (an easy brain spreads itself thinner)
	flags.sort_custom(func(a, b): return float(a.bias) < float(b.bias))
	out.append_array(flags.slice(0, _p().max_claims))
	for c in get_tree().get_nodes_in_group(Groups.PICKUPS):
		if c is Node2D:
			out.append({"at": (c as Node2D).global_position, "node": c,
				"kind": "crate", "slots": 1, "bias": 0.8})
	# 2. BUILDINGS: enemy structures, and OUR repair shop as a fallback
	#    for anything limping (the retreat leg).
	for b in get_tree().get_nodes_in_group(Groups.ALL_BUILDINGS):
		if not (b is Building2D) or not b.alive or (b as Building2D).is_bridge():
			continue
		var bld := b as Building2D
		if bld.team == team:
			continue  # _maintenance owns our own repair traffic
		if bld.team == 0:
			continue
		# a factory denies production, a fort ends the game
		out.append({"at": bld.visual_center(), "node": bld, "kind": "building",
			"slots": SLOTS_BUILDING, "bias": 0.6 if bld.produces_anything() else 0.9})
	# 3+4. ENEMY UNITS, only when the posture says all out.
	if all_out:
		for u in UnitRegistry.current.world_units():
			if not (u is Unit2D) or not u.alive or u.carried:
				continue
			if u.team == team or u.team == 0:
				continue
			out.append({"at": u.global_position, "node": u, "kind": "unit",
				"slots": 1, "bias": 1.0})
	return out


## Can this unit take this target at all? The original filters the same
## way before matching (robots enter hardware, cranes repair, and so on).
func _can_take(u: Node, t: Dictionary) -> bool:
	var kind := String(t.kind)
	# A limping tank is NOT re-tasked onto a fresh objective — it is left
	# for _maintenance to walk into the repair shop. Without this the
	# assignment kept overwriting the retreat with the next attack.
	if float(u.hp) / float(maxi(u.max_hp, 1)) < RETREAT_AT and u is Vehicle2D:
		return false
	match kind:
		"crate":
			return u.kind == "robot"
		"unit":
			return u.damage > 0
		"building":
			return u.damage > 0
		_:
			return true


## MUTUAL-NEAREST matching. Build each unit's candidate list and each
## target's, then keep ordering the pairs that are each other's nearest
## until no mutual pair is left. Returns how many orders went out.
func _match_and_order(units: Array[Node], targets: Array) -> int:
	if units.is_empty() or targets.is_empty():
		return 0
	# candidate lists, capability- and reach-filtered
	var cands: Array = []  # per unit: array of target indices
	for u in units:
		var mine: Array = []
		for ti in targets.size():
			if _can_take(u, targets[ti]):
				mine.append(ti)
		cands.append(mine)
	var slots: Array = []
	for t in targets:
		slots.append(int(t.slots))
	var taken: Array = []  # unit index -> ordered?
	taken.resize(units.size())
	taken.fill(false)
	var orders := 0
	# each pass orders every MUTUAL nearest pair it finds; a pass that
	# finds none is the end (no infinite loop even with odd geometry)
	while true:
		# unit -> its nearest live candidate
		var pick: Array = []
		pick.resize(units.size())
		pick.fill(-1)
		for ui in units.size():
			if taken[ui]:
				continue
			var best := -1
			var best_d := INF
			for ti in cands[ui]:
				if int(slots[ti]) <= 0:
					continue
				var d: float = units[ui].global_position.distance_to(
					targets[ti].at) * float(targets[ti].bias)
				if d < best_d:
					best_d = d
					best = ti
			pick[ui] = best
		# target -> its nearest suitor among the units that picked it
		var claimed: Dictionary = {}  # target index -> unit index
		for ui in units.size():
			if taken[ui] or pick[ui] < 0:
				continue
			var ti: int = pick[ui]
			if not claimed.has(ti):
				claimed[ti] = ui
				continue
			var rival: int = int(claimed[ti])
			var d_new: float = units[ui].global_position.distance_to(targets[ti].at)
			var d_old: float = units[rival].global_position.distance_to(targets[ti].at)
			if d_new < d_old:
				claimed[ti] = ui
		if claimed.is_empty():
			break
		for ti in claimed:
			var ui: int = int(claimed[ti])
			_issue(units[ui], targets[ti])
			taken[ui] = true
			slots[ti] = int(slots[ti]) - 1
			orders += 1
		if orders >= units.size():
			break
	return orders


## Turn a matched target into the right ORDER for its kind.
func _issue(u: Node, t: Dictionary) -> void:
	match String(t.kind):
		"crate":
			_order(u, Order.move(Vector2(t.at)))  # walking over it picks it up
		"unit":
			_order(u, Order.attack(t.node))
		"building":
			_order(u, Order.attack(t.node))
		_:
			_order(u, Order.move_attack(Vector2(t.at)))
			if String(t.kind) == "flag" and u.waypoints.is_empty():
				# no route (island/enclosed): park this zone for a while
				_zone_blacklist[t.zone] = clock_ms + BLACKLIST_MS


## One assignment cycle, gated by the posture's own order delay.
func _assign(robots: Array[Node], vehicles: Array[Node]) -> void:
	var now := clock_ms
	if now < _next_assign_ms:
		return
	var post := posture()
	# difficulty rides the CADENCE, not the original's fractions: an easy
	# brain re-tasks less often, a hard one at the source's own rate
	var diff := clampi(MatchState.current.ai_difficulty, 0, 2)
	_next_assign_ms = now + int(float(post.delay) * 1000.0
		* (1.3 - 0.15 * float(diff)))
	# guards hold their crossing, squads keep their mission, and units
	# walking into hardware keep going: this pass only ever sees what is
	# genuinely loose
	var committed := _committed()
	var free: Array[Node] = []
	for u in _idle_of(robots) + _idle_of(vehicles):
		if committed.has(u) or u.enter_target != null:
			continue
		free.append(u)
	if free.is_empty():
		return
	# commit only the posture's slice, chosen at random like
	# ReduceUnitsToPercent does (nearest-first would always send the same
	# front rank and leave the back rank idle forever)
	free.shuffle()
	var commit := maxi(1, int(round(float(post.commit) * free.size())))
	free = free.slice(0, commit)
	_match_and_order(free, _collect_targets(bool(post.all_out)))


# ------------------------- attacking -------------------------

## Push when the army fits the MAP (small maps demand early pushes,
## huge maps reward build-up) or when we clearly outnumber the enemy.
## Idle units stream in continuously as reinforcements; everyone
## attack-moves, so the push fights its way in instead of marching
## past every defender.
func _attack(robots: Array[Node], vehicles: Array[Node], enemy_army: int) -> void:
	var diff := clampi(MatchState.current.ai_difficulty, 0, 2)
	var army := robots.size() + vehicles.size()
	var zones_left := 0
	for z in MatchState.current.zones:
		if z.owner_team != team:
			zones_left += 1
	if not _attack_mode:
		# threshold scales with map size: 8 zones -> 3 units, 24+ -> full
		var threshold: int = clampi(
			int(float(_p().attack_units) * MatchState.current.zones.size() / 24.0),
			3, _p().attack_units)
		var outnumber := army >= enemy_army + 4
		if army < threshold and zones_left > 1 and not outnumber:
			return
		_attack_mode = true
	_attack_focus = _refresh_attack_focus(_attack_focus)
	if _attack_focus == Vector2.INF:
		_attack_mode = false
		return
	# a guard swept into the push was never a guard: the crossings have to
	# still be held when the army walks away from them — and a squad on a
	# mission is not spare either (the push used to strip strike squads of
	# their members the moment one went briefly idle)
	var committed := _committed()
	var idle: Array[Node] = []
	for u in _idle_of(robots) + _idle_of(vehicles):
		if not committed.has(u):
			idle.append(u)
	var ring := maxi(int(sqrt(float(idle.size()))), 1)
	for i in idle.size():
		var u: Node = idle[i]
		if not is_instance_valid(u):
			continue
		# units already at the push are fighting — don't reshuffle them
		if u.global_position.distance_to(_attack_focus) < 80.0:
			continue
		var offset := Vector2((i % ring) - (ring - 1) * 0.5,
			(i / ring) * 0.5) * 22.0
		_order(u, Order.move_attack(_attack_focus + offset))


## Keep the current focus while its building lives; pick a fresh
## destination when it doesn't (or when none was set yet).
func _refresh_attack_focus(focus: Vector2) -> Vector2:
	if focus != Vector2.INF:
		# ALL_BUILDINGS, like _attack_destination below: "buildings" is
		# forts only, so a focus on an enemy FACTORY could never be
		# confirmed alive and was re-picked every single think pass —
		# the brain never committed to the factory it chose.
		for b in get_tree().get_nodes_in_group(Groups.ALL_BUILDINGS):
			if b is Node2D and b.alive and b.team != 0 and b.team != team \
					and b.visual_center().distance_to(focus) < 96.0:
				return focus
	return _attack_destination()


## Where to strike: enemy factories deny production and pay for
## themselves; the fort ends the game. Harder AIs mix both more often.
func _attack_destination() -> Vector2:
	var diff := clampi(MatchState.current.ai_difficulty, 0, 2)
	var fort := _own_fort()
	var from: Vector2 = fort.visual_center() if fort else Vector2.ZERO
	var want_factory := rng.randf() < 0.5 + 0.15 * diff
	var best := Vector2.INF
	var best_d := INF
	# "buildings" carries forts only — factories are in "all_buildings"
	for b in get_tree().get_nodes_in_group(Groups.ALL_BUILDINGS):
		if not (b is Node2D) or not b.alive or b.team == 0 or b.team == team:
			continue
		if not b.is_fort and not (b is RobotFactory or b is VehicleFactory):
			continue
		if b.is_fort and want_factory:
			continue  # this push prefers factories
		var d: float = from.distance_squared_to(b.visual_center())
		if d < best_d:
			best_d = d
			best = b.visual_center()
	if best == Vector2.INF:
		for b in get_tree().get_nodes_in_group(Groups.ALL_BUILDINGS):
			if b is Node2D and b.alive and b.is_fort and b.team != 0 and b.team != team:
				return b.visual_center()
	return best


# ------------------------- rallies -------------------------

## Fresh units stream toward the current objective instead of idling at
## the factory door. Priority: a squad that is still FORMING UP near this
## factory (reinforcements walk to the muster, which is what makes a
## build-up a build-up), then the push, then the nearest zone worth
## taking. Each facility answers for itself — a factory in the rear and
## one on the frontier should not feed the same spot.
func _update_rallies() -> void:
	for f in get_tree().get_nodes_in_group(Groups.FACILITIES):
		if not (f is Building2D) or not f.alive or f.team != team:
			continue
		var objective := _muster_near(f.visual_center())
		if objective == Vector2.INF and _attack_mode:
			objective = _attack_focus
		if objective == Vector2.INF:
			objective = _nearest_takeable(f.visual_center())
		if objective == Vector2.INF:
			continue
		_rally(f, objective)


## The staging point of the nearest squad still gathering — where a fresh
## unit is worth more than anywhere else on the map.
func _muster_near(from: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for sq in _squads:
		if sq.phase != AiSquad.Phase.GATHERING or sq.staging == Vector2.INF:
			continue
		var d: float = sq.staging.distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = sq.staging
	return best


func _nearest_takeable(from: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for z in MatchState.current.zones:
		if z.owner_team == team or _blacklisted(z):
			continue
		var d: float = from.distance_squared_to(_zone_center(z))
		if d < best_d:
			best_d = d
			best = _zone_center(z)
	return best


# ------------------------- helpers -------------------------

func _idle_of(units: Array[Node]) -> Array[Node]:
	var out: Array[Node] = []
	for u in units:
		if is_instance_valid(u) and u.is_idle():
			out.append(u)
	return out


func _own_fort() -> Node2D:
	for b in get_tree().get_nodes_in_group(Groups.BUILDINGS):
		if b is Node2D and b.alive and b.is_fort and b.team == team:
			return b
	return null


func _blacklisted(z: Node) -> bool:
	if not _zone_blacklist.has(z):
		return false
	if clock_ms > int(_zone_blacklist[z]):
		_zone_blacklist.erase(z)
		return false
	return true


func _zone_has_building(z: Node) -> bool:
	for f in get_tree().get_nodes_in_group(Groups.FACILITIES):
		if f is Node2D and z.world_rect().has_point(f.visual_center()):
			return true
	return false


## Frontier test: the zone's rect (grown a little) touches one we own.
func _zone_touches_owned(z: Node) -> bool:
	var grown: Rect2 = z.world_rect().grow(32.0)
	for other in MatchState.current.zones:
		if other != z and other.owner_team == team \
				and grown.intersects(other.world_rect()):
			return true
	return false


static func _zone_center(z: Node) -> Vector2:
	return z.world_rect().get_center()
