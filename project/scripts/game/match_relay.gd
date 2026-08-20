class_name MatchRelay
extends Object
## Routes one replicated multiplayer intent to its single intake
## (Net owns transport; this is the application side). Entities are
## addressed by per-match net id — instance ids differ across peers.


static func apply(intent: Dictionary) -> void:
	match str(intent.get("kind", "")):
		"order":
			var u := _unit(int(intent.get("unit", 0)))
			if u == null or not u.alive:
				return
			u.issue_order(_order(intent))
		"queue":
			var f := _building(int(intent.get("fac", 0)))
			if f != null and f.alive and f.owner_team == int(intent.get("team", 0)):
				f.queue_unit(String(intent.get("item", "")), false)
		"rally":
			var f := _building(int(intent.get("fac", 0)))
			if f != null and f.alive and f.owner_team == int(intent.get("team", 0)):
				f.set_rally(Vector2(float(intent.get("x", 0.0)), float(intent.get("y", 0.0))))


## Apply a host economy snapshot: money, zone ownership (matched by
## rect like the save contract), facility levels (only rise — captured
## factories keep tech). The bounded drift correction for long matches.
static func apply_state(state: Dictionary) -> void:
	var ms := MatchState.current
	if ms == null:
		return
	for team in state.get("money", {}):
		ms.set_money(int(team), int(state.money[team]))
	for entry in state.get("zones", []):
		for z in ms.zones:
			if int(entry.get("x", -1)) == z.zone_rect.position.x \
					and int(entry.get("y", -1)) == z.zone_rect.position.y:
				z.set_owner_team(int(entry.get("team", 0)))
				break
	for f in state.get("facilities", []):
		for b in ms._facilities:
			if is_instance_valid(b) and b.alive \
					and b.building_id == int(f.get("id", -1)) \
					and b.owner_team == int(f.get("team", 0)):
				b.level = maxi(b.level, int(f.get("level", 0)))
				break
	ms.zone_captured.emit(ms.player_team)  # minimap/top bar refresh


## ---------------------------------------------------------------------
## FULL-ENTITY RESYNC. Peers apply the same intents to their own float
## physics, so positions drift; the host is authority and corrects the
## drift on a cadence. This is a RECONCILE, not a reload: units are
## matched by net id and nudged, so nothing pops unless it is genuinely
## wrong (missing, dead, or too far out). The snapshot shape is the SAVE
## CONTRACT (to_dict/apply_dict) plus the net id it matches on, so a
## late joiner can hand the very same dictionary to the map loader.
## ---------------------------------------------------------------------

## Positional error a peer is allowed to keep. Below it the peer's own
## simulation stays in charge (snapping every unit every push looks like
## stuttering); above it the host wins.
const SNAP_DISTANCE := 24.0


static func apply_entities(state: Dictionary) -> Dictionary:
	var report := {"corrected": 0, "spawned": 0, "removed": 0, "buildings": 0}
	if UnitRegistry.current == null or MatchState.current == null:
		return report
	var mine := {}
	for u in UnitRegistry.current.all_units():
		if u.net_id != 0:
			mine[u.net_id] = u
	var seen := {}
	for entry in state.get("units", []):
		var id := int(entry.get("net", 0))
		if id == 0:
			continue
		seen[id] = true
		var pos := Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)))
		var u: Unit2D = mine.get(id, null)
		if u == null or not is_instance_valid(u):
			# the host has a unit this peer never made (or wrongly killed)
			var spawned := Spawner.spawn(MatchState.current.map_root,
				String(entry.get("kind", "robot")), String(entry.get("type", "grunt")),
				int(entry.get("team", 0)), pos,
				bool(entry.get("manned", false))) as Unit2D
			if spawned != null:
				UnitRegistry.current.adopt(spawned, id)
				spawned.apply_dict(entry)
				report.spawned += 1
			continue
		if not u.alive:
			continue
		u.hp = int(entry.get("hp", u.hp))
		if u.global_position.distance_to(pos) > SNAP_DISTANCE:
			u.global_position = pos
			report.corrected += 1
	# units the host does not have any more died there: catch up
	for id in mine:
		if seen.has(id):
			continue
		var stale: Unit2D = mine[id]
		if is_instance_valid(stale) and stale.alive and not stale.carried:
			stale.die()
			report.removed += 1
	for entry in state.get("buildings", []):
		var b := _building(int(entry.get("net", 0)))
		if b == null:
			continue
		report.buildings += 1
		b.hp = int(entry.get("hp", b.hp))
		b.set_level(maxi(b.level, int(entry.get("level", 0))))
		var team := int(entry.get("team", b.owner_team))
		if team != b.owner_team:
			b.owner_team = team
			b.set_flag_team(team)
		if b.is_bridge():
			b.set_bridge_wrecked(b.hp <= 0)
	return report


## The host's authoritative picture of the world, in save-contract shape.
static func entity_snapshot() -> Dictionary:
	var units := []
	if UnitRegistry.current != null:
		for u in UnitRegistry.current.all_units():
			if u.alive:
				units.append(u.to_dict())
	var buildings := []
	for b in BuildingRegistry.all():
		if b is Building2D:
			buildings.append({"net": b.net_id, "hp": b.hp, "alive": b.alive,
				"team": b.owner_team, "level": b.level})
	return {"units": units, "buildings": buildings}


static func _order(intent: Dictionary) -> Order:
	var o := Order.new()
	o.type = int(intent.get("otype", 0)) as Order.Type
	o.position = Vector2(float(intent.get("x", 0.0)), float(intent.get("y", 0.0)))
	o.run = bool(intent.get("run", false))
	var tid := int(intent.get("target", 0))
	if tid != 0:
		o.target = _entity(tid)
	return o


static func _unit(id: int) -> Unit2D:
	return UnitRegistry.current.by_net_id(id) if UnitRegistry.current else null


static func _building(id: int) -> Building2D:
	return BuildingRegistry.by_net_id(id)


static func _entity(id: int) -> Node2D:
	var u := _unit(id)
	if u != null:
		return u
	return _building(id)
