class_name Producer
extends RefCounted
## Production component, extracted from Building2D: the FIFO queue,
## money/pop gates, original build-time math, capture refunds and
## product spawning. The building keeps thin delegates on its public
## surface (queue_unit/cancel_at/build_options/progress/queue_items)
## so the UI's duck-typed producer contract is unchanged. Every
## producer (fort, robot factory, vehicle factory) has one; items are
## "kind:name" strings from the BuildingDef's build_lists[level].


var b: Building2D  # the producing building (set by Building2D._ready)
var queue := ProductionQueue.new()


## Build time for a "kind:name" queue item: the unit def's ORIGINAL
## build time (zsettings.cpp SetDefaults — the original's economy is
## time, not money), trimmed by the producer's level. fast_build is the
## self-test lever.
func produce_seconds(item := "") -> float:
	if TestLevers.fast_build:
		return 2.0
	if item == "" and not queue.items.is_empty():
		item = queue.items[0]
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
## original — it never sped builds up.
func build_time_mult() -> float:
	var team_id := b.team if b.team != 0 else b.owner_team
	var owned := 0
	for z in MatchState.current.zones:
		if z.owner_team == team_id:
			owned += 1
	var ownage := float(owned) / float(maxi(MatchState.current.zones.size(), 1))
	var damage_penalty := 1.0 + 1.25 * (1.0 - float(b.hp) / float(b.max_hp))
	return maxf((1.0 - 0.5 * ownage) * damage_penalty, 0.1)


func build_options() -> Array:
	var def := ContentDB.producer_def(b.producer_key())
	if def == null:
		return []
	return def.build_lists.get(b.level, {})


func queue_items() -> Array[String]:
	return queue.items


func progress() -> float:
	if b.owner_team == 0 or queue.items.is_empty():
		return 0.0
	return queue.progress(produce_seconds(queue.items[0]))


func queue_unit(item: String, silent := false) -> bool:
	var parts := item.split(":")
	if parts.size() != 2:
		return false
	var kind := parts[0]
	var type_name := parts[1]
	if not ContentDB.has_unit(kind, type_name):
		return false
	if kind != "robot" and not ContentDB.has_sprites(kind, type_name):
		return false
	var stats := ContentDB.def_for(kind, type_name)
	if not _pop_allows(kind, stats, silent):
		return false
	if not MatchState.current.spend(b.owner_team, stats.cost):
		return false
	if not queue.enqueue(item):
		MatchState.current.deposit(b.owner_team, stats.cost)  # queue full: refund
		return false
	if b.owner_team == MatchState.current.player_team and queue.items.size() == 1:
		Fx.announce("starting_manufacture")
	return true


func cancel_at(index: int) -> void:
	var item := queue.cancel_at(index)
	if item == "" or b.owner_team == 0:
		return
	if b.owner_team == MatchState.current.player_team:
		Fx.announce("manufacturing_canceled")
	var stats := ContentDB.def_for(item.split(":")[0], item.split(":")[1])
	MatchState.current.deposit(b.owner_team, stats.cost)


## A capture scraps the old owner's queue — payment is upfront and
## cancellation refunds, so the outgoing team gets its money back too.
func scrap_queue() -> void:
	if b.team != 0 and not queue.items.is_empty():
		for item in queue.items:
			var parts: PackedStringArray = item.split(":")
			MatchState.current.deposit(b.team,
				ContentDB.def_for(parts[0], parts[1]).cost)
	queue.clear()


## Cap gate: alive + queued + this unit must fit under the team cap.
## `silent` suppresses the denial beep for CPU-initiated production.
func _pop_allows(kind: String, stats: UnitDef, silent := false) -> bool:
	var team_id := b.team if b.team != 0 else b.owner_team
	var queued := 0
	for item in queue.items:
		var parts: PackedStringArray = item.split(":")
		queued += ContentDB.def_for(parts[0], parts[1]).pop
	var cost := stats.pop
	if MatchState.current.unit_pop(team_id) + queued + cost > MatchState.current.unit_cap(team_id):
		if not silent:
			Fx.cap_denied()
		return false
	return true


func tick(delta: float) -> void:
	if b.owner_team == 0:
		return
	var done := queue.tick(delta, produce_seconds(queue.items[0] if not queue.items.is_empty() else ""))
	if done != "":
		spawn_produced(done)


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
