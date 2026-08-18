class_name CpuAi
extends Node
## Tactical CPU opponent (Z-flavoured, original-inspired):
## - produces a mixed army from every factory it owns (robots AND
##   vehicles, money- and cap-gated through the factory queues)
## - sends robots to man nearby unmanned vehicles/cannons (the biggest
##   firepower upgrade on any Z map)
## - spreads units over neutral/enemy zones, preferring zones with
##   buildings (factories flip ownership and income)
## - defends its own fort and contested zones
## - attacks in force: enemy factories or the enemy fort — never a
##   single-file rush at one target
##
## Difficulty scales think cadence, attack threshold, hardware greed and
## how much money it banks before producing vehicles.

const THINK_SECONDS := [7.0, 4.5, 3.0]      # by difficulty 0/1/2
const ATTACK_UNITS := [14, 10, 8]           # army size before the push
const BANK_BEFORE_VEHICLE := [260, 200, 150]
const MAN_RADIUS := [220.0, 320.0, 420.0]  # how far a robot walks to man
const DEFEND_RADIUS := 210.0
const MAX_CLAIMS := [4, 6, 8]
const BLACKLIST_MS := 20000
## Hardware manning priority (firepower first).
const MAN_PRIORITY := {
	"heavy": 0, "missile_launcher": 1, "missile_cannon": 2, "medium": 3,
	"howitzer": 4, "light": 5, "gun": 6, "gatling": 7, "jeep": 8, "apc": 9,
	"crane": 10,
}

var team := 2
var _accum := 0.0
var _zone_claims: Dictionary = {}     # zone node -> unit assigned
var _zone_blacklist: Dictionary = {}  # zone node -> msec until which it is skipped
var _attack_mode := false
var _attack_focus := Vector2.INF


func _init(cpu_team: int = 2) -> void:
	team = cpu_team


func _process(delta: float) -> void:
	if GameState.over:
		return
	_accum += delta
	if _accum < THINK_SECONDS[clampi(GameState.ai_difficulty, 0, 2)]:
		return
	_accum = 0.0
	_think()


func _think() -> void:
	var robots: Array[Node] = []
	var vehicles: Array[Node] = []       # own manned vehicles
	var empty_hardware: Array[Node] = [] # unmanned vehicles/cannons
	for u in get_tree().get_nodes_in_group("units"):
		if not (u is Unit2D) or not u.alive or u.carried:
			continue
		if u is Vehicle2D:
			if u.team == team:
				vehicles.append(u)
			elif not u.manned:
				empty_hardware.append(u)
		elif u.team == team and u.kind == "robot":
			robots.append(u)
	if robots.is_empty() and vehicles.is_empty():
		return
	_prune_claims()
	_produce()
	_defend(robots, vehicles)
	_man_hardware(robots, empty_hardware)
	_maintenance(vehicles)
	_capture_zones(robots)
	_attack(robots, vehicles)


# ------------------------- production -------------------------

## Produce from every owned facility using its level-gated build list
## (robots AND vehicles AND the cannons the roster allows). Robots keep
## the army growing; vehicles wait for a bank buffer; cannons round out
## defences when cash is flowing.
func _produce() -> void:
	var diff := clampi(GameState.ai_difficulty, 0, 2)
	var money := int(GameState.money.get(team, 0))
	for f in get_tree().get_nodes_in_group("facilities"):
		if not f.alive or f.team == 0 or f.team != team:
			continue
		if f.queue.items.size() >= 3:
			continue
		var options: Array = []
		for item in f.build_options():
			var parts: PackedStringArray = String(item).split(":")
			if parts[0] == "vehicle" \
					and money - int(ContentDB.def_for("vehicle", parts[1]).cost) \
					< BANK_BEFORE_VEHICLE[diff] - 150:
				continue  # keep a reserve before committing to vehicles
			options.append(item)
		if options.is_empty():
			continue
		var pick := String(_weighted_pick(options, diff))
		var parts: PackedStringArray = pick.split(":")
		var cost := int(ContentDB.def_for(parts[0], parts[1]).cost)
		if money >= cost and f.queue_unit(pick, true):
			money -= cost


## Robots a little more often than hardware; fresh options (vehicles,
## cannons) get a boost so the AI actually uses its roster.
func _weighted_pick(options: Array, _diff: int) -> String:
	var weights: Array = []
	for item in options:
		var kind := String(item).split(":")[0]
		weights.append(5 if kind == "robot" else 3)
	var total := 0
	for w in weights:
		total += int(w)
	var roll := randi() % total
	for i in options.size():
		roll -= int(weights[i])
		if roll < 0:
			return String(options[i])
	return String(options[0])


## Bigger tanks when rich, jeeps and lights when scraping by.
func _vehicle_pick(spare: int) -> String:
	if spare >= 320:
		return ["heavy", "medium"].pick_random()
	if spare >= 200:
		return ["medium", "light"].pick_random()
	return ["light", "jeep"].pick_random()


# ------------------------- defense -------------------------

## Enemy units near our fort or standing in an owned zone draw the
## closest idle defenders — the AI no longer ignores its own territory.
func _defend(robots: Array[Node], vehicles: Array[Node]) -> void:
	var fort := _own_fort()
	var threats: Array[Node] = []
	for u in get_tree().get_nodes_in_group("units"):
		if u is Node2D and u.alive and u.team != 0 and u.team != team and not u.carried:
			if fort and u.global_position.distance_to(fort.visual_center()) < DEFEND_RADIUS:
				threats.append(u)
				continue
			for z in GameState.zones:
				if z.owner_team == team and z.world_rect().has_point(u.global_position):
					threats.append(u)
					break
	if threats.is_empty():
		return
	var defenders := _idle_of(robots) + _idle_of(vehicles)
	for threat in threats:
		if defenders.is_empty() or not is_instance_valid(threat):
			continue
		defenders.sort_custom(func(a, b):
			return a.global_position.distance_squared_to(threat.global_position) \
				< b.global_position.distance_squared_to(threat.global_position))
		for i in mini(2, defenders.size()):
			var d: Node = defenders.pop_front()
			if is_instance_valid(d):
				d.move_to(threat.global_position
					+ Vector2(randf_range(-14.0, 14.0), randf_range(-14.0, 14.0)))


# ------------------------- manning hardware -------------------------

## Idle robots walk to the best unmanned vehicle/cannon in range —
## combat hardware first, transports last, cranes only as a fallback.
func _man_hardware(robots: Array[Node], empty_hardware: Array[Node]) -> void:
	if empty_hardware.is_empty():
		return
	var radius: float = MAN_RADIUS[clampi(GameState.ai_difficulty, 0, 2)]
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
			var score := dist + int(MAN_PRIORITY.get(hw.unit_name, 5)) * 30.0
			if score < best_score:
				best_score = score
				best = hw
		if best != null:
			empty_hardware.erase(best)
			r.move_to(best.global_position)
			r.enter_target = best


# ------------------------- maintenance -------------------------

## Damaged vehicles head for the repair shop; cranes set up on the
## nearest wrecked building or bridge (original: the bot's
## repair_building_list orders).
func _maintenance(vehicles: Array[Node]) -> void:
	var repair_shop: Building2D = null
	var damaged_buildings: Array[Node] = []
	for f in get_tree().get_nodes_in_group("facilities"):
		if f is Building2D and f.alive and f.team == team:
			if f.is_repair_shop():
				repair_shop = f
			elif f.hp < f.max_hp:
				damaged_buildings.append(f)
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is Building2D and b.alive and b.team == team \
				and b.is_bridge() and b.hp < b.max_hp:
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
				v.move_to(best_b.world_footprint().get_center())
				v.enter_target = best_b
		elif repair_shop != null and v.hp < v.max_hp * 0.5 \
				and v.kind == "vehicle":
			v.move_to(repair_shop.world_footprint().get_center())
			v.enter_target = repair_shop


# ------------------------- zone capture -------------------------

func _capture_zones(robots: Array[Node]) -> void:
	if _attack_mode:
		return  # the push supersedes spreading
	var not_ours: Array[Node] = []
	for z in GameState.zones:
		if z.owner_team != team:
			not_ours.append(z)
	if not_ours.is_empty():
		return
	var max_claims: int = MAX_CLAIMS[clampi(GameState.ai_difficulty, 0, 2)]
	for r in _idle_of(robots):
		if _zone_claims.size() >= max_claims:
			return
		if r.enter_target != null:
			continue
		var best_zone: Node = null
		var best_d := INF
		for z in not_ours:
			if _zone_claims.has(z) or _blacklisted(z):
				continue
			var d: float = r.global_position.distance_squared_to(_zone_center(z))
			# zones that hold buildings are worth a much longer walk
			if _zone_has_building(z):
				d *= 0.4
			if d < best_d:
				best_d = d
				best_zone = z
		if best_zone == null:
			return
		r.move_to(_zone_center(best_zone))
		if r.waypoints.is_empty():
			# no route (island/enclosed): skip this zone for a while
			_zone_blacklist[best_zone] = Time.get_ticks_msec() + BLACKLIST_MS
		else:
			_zone_claims[best_zone] = r


# ------------------------- attacking -------------------------

## Push when the army is strong (or the map is nearly taken): enemy
## factories or the enemy fort. Idle units stream in continuously as
## reinforcements instead of one doomed wave.
func _attack(robots: Array[Node], vehicles: Array[Node]) -> void:
	var diff := clampi(GameState.ai_difficulty, 0, 2)
	var army := robots.size() + vehicles.size()
	var zones_left := 0
	for z in GameState.zones:
		if z.owner_team != team:
			zones_left += 1
	if not _attack_mode:
		if army < ATTACK_UNITS[diff] and zones_left > 1:
			return
		_attack_mode = true
		_zone_claims.clear()
	_attack_focus = _refresh_attack_focus(_attack_focus)
	if _attack_focus == Vector2.INF:
		_attack_mode = false
		return
	var idle := _idle_of(robots) + _idle_of(vehicles)
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
		u.move_to(_attack_focus + offset)


## Keep the current focus while its building lives; pick a fresh
## destination when it doesn't (or when none was set yet).
func _refresh_attack_focus(focus: Vector2) -> Vector2:
	if focus != Vector2.INF:
		for b in get_tree().get_nodes_in_group("buildings"):
			if b is Node2D and b.alive and b.team != 0 and b.team != team \
					and b.visual_center().distance_to(focus) < 96.0:
				return focus
	return _attack_destination()


## Where to strike: enemy factories deny production and pay for
## themselves; the fort ends the game. Harder AIs mix both more often.
func _attack_destination() -> Vector2:
	var diff := clampi(GameState.ai_difficulty, 0, 2)
	var fort := _own_fort()
	var from: Vector2 = fort.visual_center() if fort else Vector2.ZERO
	var want_factory := randf() < 0.5 + 0.15 * diff
	var best := Vector2.INF
	var best_d := INF
	for b in get_tree().get_nodes_in_group("buildings"):
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
		for b in get_tree().get_nodes_in_group("buildings"):
			if b is Node2D and b.alive and b.is_fort and b.team != 0 and b.team != team:
				return b.visual_center()
	return best


# ------------------------- helpers -------------------------

func _idle_of(units: Array[Node]) -> Array[Node]:
	var out: Array[Node] = []
	for u in units:
		if is_instance_valid(u) and u.alive and u.move_target == Vector2.ZERO \
				and (u.enter_target == null or not is_instance_valid(u.enter_target)):
			out.append(u)
	return out


func _own_fort() -> Node2D:
	for b in get_tree().get_nodes_in_group("buildings"):
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
		if not stale and u.move_target == Vector2.ZERO \
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
	for b in get_tree().get_nodes_in_group("facilities"):
		if b is Node2D and z.world_rect().has_point(b.visual_center()):
			return true
	return false


static func _zone_center(z: Node) -> Vector2:
	return z.position + z.world_rect().get_center()
