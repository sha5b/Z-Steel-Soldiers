class_name Producer
extends RefCounted
## Production component, extracted from Building2D: the standing
## production LINE, money/pop gates, original build-time math, capture
## handover and product spawning. Every producer (fort, robot factory,
## vehicle factory) has one; items are "kind:name" strings from the
## BuildingDef's build_lists[level].
##
## THERE IS NO QUEUE — see ProductionLine. A producer is pointed at one
## type and turns it out indefinitely. This component owns the three
## things the line itself does not: WHO PAYS (each unit is charged as it
## starts, so a stalled line costs nothing), WHAT MAY START (population
## cap, funds, and a fort's four cannon mounts), and the DEFAULT (a
## producer that has never been given an order starts on the first entry
## of its own build list).


var b: Building2D  # the producing building (set by Building2D._ready)
var line := ProductionLine.new()
## Has this producer ever had a selection? The default is applied ONCE,
## on first activation — after that an empty line means somebody stopped
## it on purpose (the panel's Cancel), and refilling it would make that
## button do nothing.
var _defaulted := false


## Build time for a "kind:name" queue item: the unit def's ORIGINAL
## build time (zsettings.cpp SetDefaults — the original's economy is
## time, not money), trimmed by the producer's level. fast_build is the
## self-test lever.
func produce_seconds(item := "") -> float:
	if TestLevers.fast_build:
		return 2.0
	if item == "":
		item = line.selected
	if item == "":
		return 8.0 * build_time_mult()
	var parts: PackedStringArray = item.split(":")
	if parts.size() == 2 and ContentDB.has_unit(parts[0], parts[1]):
		return ContentDB.def_for(parts[0], parts[1]).build_time * build_time_mult()
	return 8.0 * build_time_mult()


## Original BuildTimeModified (zbuilding.cpp): production speeds up with
## the share of the map's zones the owner holds (up to -50% at full
## control) and slows while the building is damaged (up to +125% near
## death). Building LEVEL only gates the roster, exactly like the
## original — it never sped builds up. Zone ownership comes from the
## MatchState census (rebuilt once per capture), not a fresh walk — this
## runs per producer PER FRAME.
func build_time_mult() -> float:
	var team_id := b.team if b.team != 0 else b.owner_team
	var ownage := float(MatchState.current.zones_owned_by(team_id)) \
		/ float(maxi(MatchState.current.zones.size(), 1))
	var damage_penalty := 1.0 + 1.25 * (1.0 - float(b.hp) / float(b.max_hp))
	return maxf((1.0 - 0.5 * ownage) * damage_penalty, 0.1)


func build_options() -> Array:
	var def := ContentDB.producer_def(b.producer_key())
	if def == null:
		return []
	return def.build_lists.get(b.level, {})


## The line's contents as a list, for the UI and the AI: at most one
## entry. (Kept list-shaped because "what is this building making?" reads
## the same whether the answer is a line or a queue.)
func queue_items() -> Array[String]:
	var out: Array[String] = []
	if line.selected != "":
		out.append(line.selected)
	return out


## What is on the line ("" = stopped). THE accessor for callers that want
## the single answer rather than a list.
func selected() -> String:
	return line.selected


func progress() -> float:
	if b.owner_team == 0 or line.selected == "":
		return 0.0
	return line.progress(produce_seconds(line.selected))


## POINT THE LINE AT A TYPE. The one intake for players (the panel's
## roster), the AI and the tests — nothing else writes the selection.
##
## No money changes hands here: a unit is charged as it STARTS (see
## tick), so selecting a type you cannot yet afford is legal and simply
## stalls until you can. What this does check is whether the type is
## real, has art, and is on this producer's own build list — a selection
## the building could never honour is refused outright.
##
## Switching away from a part-built unit REFUNDS it and keeps the clock
## (ProductionLine.select), so the money stays straight either way.
func select(item: String, silent := false) -> bool:
	var parts := item.split(":")
	if parts.size() != 2:
		return false
	if not ContentDB.has_unit(parts[0], parts[1]):
		return false
	if parts[0] != "robot" and not ContentDB.has_sprites(parts[0], parts[1]):
		return false
	if not build_options().has(item):
		if not silent:
			Fx.cap_denied()  # not on this building's roster at this level
		return false
	if line.selected == item:
		return true
	_refund_in_progress()
	line.select(item)
	_defaulted = true
	if b.owner_team == MatchState.current.player_team:
		Fx.announce("starting_manufacture")
	return true


## Compatibility intake, kept because "queue this" is what every existing
## caller says. There is no queue — this points the line.
func queue_unit(item: String, silent := false) -> bool:
	return select(item, silent)


## STOP. The factory goes idle and STAYS idle: the default is only ever
## applied once, on first activation, so cancelling really does stop
## production instead of being papered over on the next tick.
func stop_line() -> void:
	if line.selected == "" and not line.paid:
		return
	_refund_in_progress()
	line.stop()
	_defaulted = true  # stopped ON PURPOSE — do not re-default
	if b.owner_team == MatchState.current.player_team:
		Fx.announce("manufacturing_canceled")


## Compatibility shim for the old queue API: any index means "the thing
## on the line", and cancelling it stops the line.
func cancel_at(_index: int) -> void:
	stop_line()


## Hand back the money for a unit that was charged for but never
## finished. Called when the line is re-pointed or stopped.
func _refund_in_progress() -> void:
	if not line.paid or b.owner_team == 0:
		return
	line.paid = false
	var parts: PackedStringArray = line.selected.split(":")
	if parts.size() == 2 and ContentDB.has_unit(parts[0], parts[1]):
		MatchState.current.deposit(b.owner_team,
			ContentDB.def_for(parts[0], parts[1]).cost)


## A CAPTURE HANDS THE UNIT ON THE LINE TO WHOEVER TOOK THE SECTOR.
##
## This is one of the original's real tactical hooks: "capture a sector
## just before the clock completes and you become the beneficiary of
## whatever it was producing" — so WHEN you attack matters as much as
## what you attack.
##
## With a line rather than a queue there is nothing to scrap: the unit in
## progress keeps its clock and changes hands, and the line keeps
## pointing at that type. If the new owner's roster does not carry it
## (different building level, different tier), `tick` falls the line back
## to their own default on the next pass. The part-built unit was already
## paid for by the LOSING team, so `paid` stays set — the captor gets it
## for nothing, which is exactly the hook.
func scrap_queue() -> void:
	_defaulted = true  # the inherited selection counts as an order


## Cap gate: this unit must fit under the team cap. With a line there is
## never more than ONE unit in flight, so there is nothing queued to add
## in — the old version summed the whole FIFO here.
## `silent` suppresses the denial beep for CPU-initiated production.
func _pop_allows(_kind: String, stats: UnitDef, silent := false) -> bool:
	var team_id := b.team if b.team != 0 else b.owner_team
	if MatchState.current.unit_pop(team_id) + stats.pop \
			> MatchState.current.unit_cap(team_id):
		if not silent:
			Fx.cap_denied()
		return false
	return true


## MAY THIS UNIT START? Everything that can stall a line, in one place:
## the type must still be on the roster, the population cap must have
## room, and a fort building cannons must have a free tower mount (that
## last one is why a fort stops turning out turrets until one of its four
## is destroyed). Money is checked separately, because spending is not a
## query.
func _may_start(item: String) -> bool:
	if not build_options().has(item):
		return false
	var parts: PackedStringArray = item.split(":")
	if parts.size() != 2 or not ContentDB.has_unit(parts[0], parts[1]):
		return false
	if not _pop_allows(parts[0], ContentDB.def_for(parts[0], parts[1]), true):
		return false
	return b.accepts_product(parts[0], parts[1])


## ONE PASS OF THE LINE: default it if it has never been ordered, fall it
## back if the selection has become impossible, pay for the unit in
## progress, then advance the clock. A line that cannot start banks NO
## time and spends NO money — it simply waits, which is what a fort with
## four live tower guns does when told to build a fifth.
func tick(delta: float) -> void:
	if b.owner_team == 0:
		return
	_ensure_default()
	if line.selected == "":
		return
	# the selection stopped being buildable here (captured by a team whose
	# roster lacks it, or the level changed): take this producer's default
	if not build_options().has(line.selected):
		_refund_in_progress()
		line.select(_default_item())
		if line.selected == "":
			return
	if not line.paid:
		if not _may_start(line.selected):
			return  # stalled: no clock, no charge
		var parts: PackedStringArray = line.selected.split(":")
		var stats := ContentDB.def_for(parts[0], parts[1])
		if not MatchState.current.spend(b.owner_team, stats.cost):
			return  # broke: stalled, try again next pass
		line.paid = true
	var done := line.tick(delta, produce_seconds(line.selected))
	if done != "":
		spawn_produced(done)


## The first entry of this producer's own build list — what a factory
## nobody has given an order to turns out.
func _default_item() -> String:
	var options := build_options()
	return String(options[0]) if not options.is_empty() else ""


## EVERY PRODUCER STARTS WORKING BY ITSELF. A newly owned factory begins
## on the first unit of its list rather than sitting idle until somebody
## clicks it — which also means a captured factory immediately earns its
## keep. Applied once: after that, an empty line is a deliberate stop.
func _ensure_default() -> void:
	if _defaulted or line.selected != "":
		return
	_defaulted = true
	var first := _default_item()
	if first != "":
		line.select(first)


func spawn_produced(item: String) -> void:
	var parts := item.split(":")
	var kind := parts[0]
	var type_name := parts[1]
	if b.owner_team == MatchState.current.player_team:
		Fx.announce("robot_manufactured" if kind == "robot"
			else "vehicle_manufactured" if kind == "vehicle"
			else "gun_manufactured")
	if b.mount_product(kind, type_name):
		return  # mounted somewhere (fort tower cannon)
	# spawn just BELOW the solid footprint — never inside it (validated
	# for the product's body box; the +14 nudge alone could still clip a
	# neighbouring wall or waterline)
	var fp := b.world_footprint()
	var raw_spawn := Vector2(fp.get_center().x, fp.end.y + 14.0)
	var spawn_pos := NavWorld.current.find_free_spot(raw_spawn, kind)
	if spawn_pos == Vector2.INF:
		spawn_pos = raw_spawn  # boxed-in apron: better clipped than eaten
	if kind == "robot":
		var unit: Unit2D = Spawner.spawn(b.get_parent(), kind, type_name,
			b.owner_team, spawn_pos) as Unit2D
		if unit and b.rally_point != Vector2.INF:
			unit.move_to(b.rally_point)
	elif ContentDB.has_sprites(kind, type_name):
		# vehicles and cannons spawn UNMANNED beside the building for a
		# robot to man (Z-style). Empty hardware ignores rally points —
		# it stays on the apron until a crew boards (the AI's far rally
		# once made every produced vehicle drive itself to the enemy HQ).
		Spawner.spawn(b.get_parent(), kind, type_name, 0, spawn_pos)
