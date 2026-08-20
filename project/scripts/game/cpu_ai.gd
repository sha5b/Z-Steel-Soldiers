class_name CpuAi
extends Node
## Tactical CPU opponent (Z-flavoured, original-inspired). One brain per
## non-player fort team; every think pass runs the full OODA loop:
##
## - PRODUCE from every owned facility (money- and pop-gated queues,
##   robots first while the army is small, hardware once a bank buffer
##   exists — cannons round out defences)
## - DEFEND home: enemies inside owned zones or near the fort draw the
##   nearest idle units, who ATTACK-MOVE so they actually fight back
## - MAN empty hardware (vehicles and cannons — the biggest firepower
##   upgrade on any Z map); cranes repair, damaged vehicles visit the
##   repair shop
## - EXPAND continuously: idle robots AND vehicles claim neutral and
##   enemy zones — frontier zones, zones with buildings and zones the
##   team recently lost score higher; unreachable zones are blacklisted
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
var _accum := 0.0
var _zone_claims: Dictionary = {}      # zone node -> unit assigned
var _zone_blacklist: Dictionary = {}   # zone node -> msec until skipped
var _retake_at: Dictionary = {}        # zone node -> msec lost at
var _owned_snapshot: Dictionary = {}   # zone node -> true (last think)
var _attack_mode := false
var _attack_focus := Vector2.INF


func _init(cpu_team: int = 2) -> void:
	team = cpu_team


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


func _queue(f: Node, item: String) -> bool:
	if not f.queue_unit(item, true):
		return false
	Net.relay_queue(f, item)
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
	if GameState.over:
		return
	_accum += delta
	if _accum < _p().think_seconds:
		return
	_accum = 0.0
	_think()


func _think() -> void:
	var robots: Array[Node] = []
	var vehicles: Array[Node] = []       # own manned vehicles
	var empty_hardware: Array[Node] = [] # unmanned vehicles/cannons
	var enemy_army := 0
	for u in UnitRegistry.current.world_units():
		if not (u is Unit2D) or not u.alive or u.carried:
			continue
		if u is Vehicle2D:
			if u.team == team:
				vehicles.append(u)
			elif not u.manned:
				empty_hardware.append(u)
			elif u.team != 0:
				enemy_army += 1
		elif u.kind == "robot":
			if u.team == team:
				robots.append(u)
			elif u.team != 0:
				enemy_army += 1
	if robots.is_empty() and vehicles.is_empty():
		return
	_track_lost_zones()
	_prune_claims()
	_produce()
	_defend(robots, vehicles)
	_man_hardware(robots, empty_hardware)
	_maintenance(vehicles)
	_capture_zones(robots, vehicles)
	_hold_chokepoints(robots, vehicles)
	_attack(robots, vehicles, enemy_army)
	_update_rallies()


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
	var now := Time.get_ticks_msec()
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
	var free_units: Array[Node] = []
	for u in _idle_of(robots) + _idle_of(vehicles):
		if not already.has(u):
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
		free_units.sort_custom(func(a, b):
			return a.global_position.distance_squared_to(spot) \
				< b.global_position.distance_squared_to(spot))
		var guard: Node = free_units.pop_front()
		if not is_instance_valid(guard):
			continue
		# DEFEND, not move: the unit walks there and re-holds the post if
		# it gets shoved off, which is the whole point of a guard
		_order(guard, Order.move_defend(spot
			+ Vector2(randf_range(-18.0, 18.0), randf_range(-18.0, 18.0))))
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
		var d: float = (f as Node2D).global_position.distance_squared_to(target)
		if d < pick_d:
			pick_d = d
			pick = f
	return pick


# ------------------------- production -------------------------

## Produce from every owned facility using its level-gated build list
## (robots AND vehicles AND the cannons the roster allows). Robots keep
## the army growing; vehicles wait for a bank buffer; cannons round out
## defences when cash is flowing.
func _produce() -> void:
	var diff := clampi(MatchState.current.ai_difficulty, 0, 2)
	var money := int(MatchState.current.money.get(team, 0))
	var army_pop := MatchState.current.unit_pop(team)
	var frontier := _frontier_facility()
	for f in get_tree().get_nodes_in_group(Groups.FACILITIES):
		if not f.alive or f.team == 0 or f.team != team:
			continue
		if f.queue.items.size() >= 4:
			continue
		var options: Array = []
		for item in f.build_options():
			var parts: PackedStringArray = String(item).split(":")
			if parts[0] == "vehicle" \
					and money - ContentDB.def_for("vehicle", parts[1]).cost \
					< _p().bank_before_vehicle - 150:
				continue  # keep a reserve before committing to vehicles
			options.append(item)
		if options.is_empty():
			continue
		var pick := String(_weighted_pick(options, army_pop, diff))
		var parts: PackedStringArray = pick.split(":")
		# a CANNON is immobile once built, so where it appears is decided
		# entirely by which building makes it: only the facility nearest
		# the frontier may build one, and anywhere else re-picks something
		# that can walk to the fight
		if parts[0] == "cannon" and f != frontier:
			var mobile: Array = options.filter(
				func(i): return not String(i).begins_with("cannon:"))
			if mobile.is_empty():
				continue
			pick = String(_weighted_pick(mobile, army_pop, diff))
			parts = pick.split(":")
		var cost := ContentDB.def_for(parts[0], parts[1]).cost
		if money >= cost and _queue(f, pick):
			money -= cost


## Robots while the army is small, hardware once it stands — and fresh
## options (vehicles, cannons) get a boost so the AI uses its roster.
func _weighted_pick(options: Array, army_pop: int, _diff: int) -> String:
	var weights: Array = []
	for item in options:
		var kind := String(item).split(":")[0]
		var w := 3
		if kind == "robot":
			w = 8 if army_pop < 10 else 5
		elif kind == "cannon":
			w = 4
		weights.append(w)
	var total := 0
	for w in weights:
		total += int(w)
	var roll := randi() % total
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
	var defenders := _idle_of(robots) + _idle_of(vehicles)
	for threat in threats:
		if defenders.is_empty() or not is_instance_valid(threat):
			continue
		defenders.sort_custom(func(a, b):
			return a.global_position.distance_squared_to(threat.global_position) \
				< b.global_position.distance_squared_to(threat.global_position))
		for i in mini(responders, defenders.size()):
			var d: Node = defenders.pop_front()
			if is_instance_valid(d):
				_order(d, Order.move_attack(threat.global_position
					+ Vector2(randf_range(-14.0, 14.0), randf_range(-14.0, 14.0))))


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
			var dist: float = r.global_position.distance_to(hw.global_position)
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
				var d: float = v.global_position.distance_squared_to(
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

## Idle robots AND vehicles spread over neutral/enemy zones. Scoring
## favours the frontier (zones touching our territory), zones with
## buildings (they flip income AND production) and zones lost recently.
func _capture_zones(robots: Array[Node], vehicles: Array[Node]) -> void:
	if _attack_mode:
		return  # the push supersedes spreading
	var not_ours: Array[Node] = []
	for z in MatchState.current.zones:
		if z.owner_team != team:
			not_ours.append(z)
	if not_ours.is_empty():
		return
	var diff := clampi(MatchState.current.ai_difficulty, 0, 2)
	# more claims on bigger maps, fewer on easy
	var max_claims: int = clampi(MatchState.current.zones.size() / 3, 2, _p().max_claims)
	var idle := _idle_of(robots) + _idle_of(vehicles)
	for u in idle:
		if _zone_claims.size() >= max_claims:
			return
		if u.enter_target != null:
			continue
		var best_zone: Node = null
		var best_d := INF
		for z in not_ours:
			if _zone_claims.has(z) or _blacklisted(z):
				continue
			var d: float = u.global_position.distance_squared_to(_zone_center(z))
			# zones that hold buildings are worth a much longer walk
			if _zone_has_building(z):
				d *= 0.4
			# frontier: touching our territory — easy to take, easy to keep
			if _zone_touches_owned(z):
				d *= 0.7
			# a zone we just lost is a priority retake
			if _retake_at.has(z):
				d *= 0.5
			# neutral land before a fight
			if z.owner_team != 0:
				d *= 1.5
			if d < best_d:
				best_d = d
				best_zone = z
		if best_zone == null:
			return
		_order(u, Order.move_attack(_zone_center(best_zone)))
		if u.waypoints.is_empty():
			# no route (island/enclosed): skip this zone for a while
			_zone_blacklist[best_zone] = Time.get_ticks_msec() + BLACKLIST_MS
		else:
			_zone_claims[best_zone] = u


## Remember zones that flipped away from us — they stay juicy targets.
func _track_lost_zones() -> void:
	var now_owned: Dictionary = {}
	for z in MatchState.current.zones:
		if z.owner_team == team:
			now_owned[z] = true
	for z in _owned_snapshot:
		if not now_owned.has(z):
			_retake_at[z] = Time.get_ticks_msec() + RETAKE_MS
	for z in _retake_at.keys():
		if Time.get_ticks_msec() > int(_retake_at[z]) or now_owned.has(z):
			_retake_at.erase(z)
	_owned_snapshot = now_owned


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
		_zone_claims.clear()
	_attack_focus = _refresh_attack_focus(_attack_focus)
	if _attack_focus == Vector2.INF:
		_attack_mode = false
		return
	# a guard swept into the push was never a guard: the crossings have to
	# still be held when the army walks away from them
	var guards := guard_units()
	var idle: Array[Node] = []
	for u in _idle_of(robots) + _idle_of(vehicles):
		if not guards.has(u):
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
		for b in get_tree().get_nodes_in_group(Groups.BUILDINGS):
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
	var want_factory := randf() < 0.5 + 0.15 * diff
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
## the factory door: the attack focus during a push, else the nearest
## zone worth taking.
func _update_rallies() -> void:
	var objective := _attack_focus if _attack_mode else Vector2.INF
	for f in get_tree().get_nodes_in_group(Groups.FACILITIES):
		if not (f is Building2D) or not f.alive or f.team != team:
			continue
		if objective == Vector2.INF:
			objective = _nearest_takeable(f.visual_center())
			if objective == Vector2.INF:
				return
		_rally(f, objective)


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


func _prune_claims() -> void:
	for z in _zone_claims.keys():
		var u = _zone_claims[z]  # untyped: may hold a freed instance
		var stale: bool = (not is_instance_valid(u)) or (not u.alive) \
			or z.owner_team == team  # captured — release the claim
		if not stale and u.carried:
			stale = true  # riding an APC: not holding anything
		if not stale and not u.has_move_target() \
				and u.global_position.distance_to(_zone_center(z)) > 48.0:
			stale = true  # idle but never got there — order failed
		if stale:
			_zone_claims.erase(z)


func _blacklisted(z: Node) -> bool:
	if not _zone_blacklist.has(z):
		return false
	if Time.get_ticks_msec() > int(_zone_blacklist[z]):
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
