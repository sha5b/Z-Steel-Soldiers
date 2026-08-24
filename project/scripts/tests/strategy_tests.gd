class_name StrategyTests
extends Object
## Strategic/operational domain of the headless harness: the two AI
## layers above the per-unit passes (AiMap and AiSquad), plus the rule
## that keeps them from fighting each other.
##
## Runs inside the `--tactics-test` lane, beside the ZBot assignment
## checks that were already there — the whole CPU brain is one lane.
##
## The failures these were written for:
##  1. no map read at all. The brain reasoned off "every zone I do not
##     own" with no notion of which sector was the front, what a target
##     was worth or whether it could be walked to.
##  2. no grouping between the unit and the map. Units were commanded
##     individually, so they trickled at objectives one at a time and
##     died one at a time — which is what "it just storms" is.
##  3. TWO layers commanding one unit. The reactive defence, the push and
##     the assignment all drafted from "the idle units", so a squad that
##     paused for a breath was picked apart and the assault dissolved.


# ---- 1. the map read ---------------------------------------------------

static func map_read(ctx: Node, rig: TestRig, team: int) -> void:
	var map := AiMap.new(team)
	map.refresh()
	rig.check(map.zones_total == MatchState.current.zones.size(),
		"AiMap saw %d of %d zones" % [map.zones_total,
			MatchState.current.zones.size()])
	if map.zones_total == 0:
		rig.check(false, "loaded map has no zones — nothing to read")
		return
	# THE GRAPH. Adjacency is a symmetric relation or it is not adjacency:
	# a one-way edge makes the depth walk below silently wrong.
	var edges := 0
	var asymmetric := 0
	var self_linked := 0
	for z in map.graph:
		for nb in (map.graph[z] as Array):
			edges += 1
			if nb == z:
				self_linked += 1
			if not (map.graph.get(nb, []) as Array).has(z):
				asymmetric += 1
	rig.check(edges > 0, "the zone graph has no edges at all on a %d-zone map"
		% map.zones_total)
	rig.check(asymmetric == 0, "%d of %d zone-graph edges are one-way"
		% [asymmetric, edges])
	rig.check(self_linked == 0, "%d zones are their own neighbour" % self_linked)
	# DEPTH. Hops from our own ground: the sector we start in is 0, and
	# most of a connected map has to be reachable — a read where
	# everything is UNREACHABLE cannot rank a single target.
	rig.check(map.home != Vector2.INF, "AiMap found no home at all for team %d"
		% team)
	var reachable := 0
	var at_zero := 0
	for z in map.info:
		var depth: int = int((map.info[z] as Dictionary).depth)
		if depth < AiMap.UNREACHABLE_DEPTH:
			reachable += 1
		if depth == 0:
			at_zero += 1
	rig.check(at_zero == 1, "%d zones sit at depth 0 (want exactly one: home)"
		% at_zero)
	rig.check(reachable > map.zones_total / 2,
		"only %d of %d zones are reachable through the graph — the depth "
		% [reachable, map.zones_total] + "walk is not connecting the map")
	# VALUE. A sector holding a fort must outrank bare ground, or the
	# target ranking is blind to what is actually on the map.
	var fort_value := 0.0
	var bare_value := 0.0
	for z in map.info:
		var entry: Dictionary = map.info[z]
		if int(entry.buildings) > 0:
			fort_value = maxf(fort_value, float(entry.value))
		else:
			bare_value = maxf(bare_value, float(entry.value))
	rig.check(fort_value > bare_value or fort_value == 0.0,
		"a sector with buildings scores %.1f, bare ground %.1f"
		% [fort_value, bare_value])
	# THE CURRENCY. power_of has to price a unit, not count it, and it
	# must read zero for anything that cannot fight — a brain that thinks
	# three cranes hold a bridge loses the bridge.
	var grunt: Unit2D = Spawner.spawn(ctx, "robot", "grunt", team,
		map.home if map.home != Vector2.INF else Vector2(600, 600)) as Unit2D
	var crane: Unit2D = Spawner.spawn(ctx, "vehicle", "crane", team,
		grunt.global_position + Vector2(40, 0)) as Unit2D
	if is_instance_valid(grunt) and is_instance_valid(crane):
		rig.check(AiMap.power_of(grunt) > 0.0, "a grunt is worth no power")
		rig.check(AiMap.power_of(crane) == 0.0,
			"a crane is worth %.1f power — it cannot fight"
			% AiMap.power_of(crane))
		var full := AiMap.power_of(grunt)
		grunt.hp = maxi(grunt.max_hp / 4, 1)
		rig.check(AiMap.power_of(grunt) < full,
			"a grunt at quarter health is worth as much as a fresh one")
		rig.check(AiMap.power_of_all([grunt, crane])
				== AiMap.power_of(grunt) + AiMap.power_of(crane),
			"power_of_all does not agree with power_of")
	if is_instance_valid(grunt):
		grunt.queue_free()
	if is_instance_valid(crane):
		crane.queue_free()


# ---- 2. the stance table ----------------------------------------------

## strategy() must FOLLOW the read, not sit on one setting. Each row is a
## map situation and the stance it has to produce.
static func stance_table(ctx: Node, rig: TestRig, ai: CpuAi) -> void:
	var saved: AiMap = ai._map
	var zones: Array = MatchState.current.zones
	# behind on power: hold what we have
	rig.check(_stance_for(ai, 60.0, 300.0, 1, 10, null) == "turtle",
		"outgunned 1:5 and the brain does not turtle")
	# even fight, little ground: consolidate
	rig.check(_stance_for(ai, 80.0, 100.0, 1, 10, null) == "consolidate",
		"an even fight on little ground is not consolidate")
	# ahead on power but not on ground: expand
	rig.check(_stance_for(ai, 150.0, 140.0, 1, 10, null) == "expand",
		"ahead on power with 1 of 10 sectors is not expand")
	# ahead on both: press
	rig.check(_stance_for(ai, 400.0, 100.0, 8, 10, null) == "press",
		"ahead on power AND ground is not press")
	# HOME PRESSURE OVERRIDES EVERYTHING. A brain that keeps pressing
	# while its own fort sector is being taken is the failure behind
	# every "the AI ignores its base" report.
	if not zones.is_empty():
		rig.check(_stance_for(ai, 400.0, 100.0, 8, 10, zones[0]) == "turtle",
			"the brain kept pressing with its home sector under attack")
	ai._map = saved


## Hand-build a map read and ask for the stance. `threat_zone` (or null)
## is a sector of ours, at depth 0, with an enemy force standing in it.
static func _stance_for(ai: CpuAi, own: float, foe: float, held: int,
		total: int, threat_zone) -> String:
	var map := AiMap.new(ai.team)
	map.own_power = own
	map.foe_power = foe
	map.zones_held = held
	map.zones_total = total
	map.home = Vector2(600, 600)
	if threat_zone != null:
		map.info[threat_zone] = {
			"owner": ai.team, "at": Vector2(600, 600),
			"rect": threat_zone.world_rect(), "own": 0.0, "foe": own * 0.9,
			"value": 8.0, "buildings": 1, "depth": 0, "front": true,
			"producers": 1,
		}
	ai._map = map
	return String(ai.strategy().name)


# ---- 3. the squad ------------------------------------------------------

## A squad has to ASSEMBLE before it commits, arrive as a body, and break
## off when it has lost — the three things a lone unit cannot do, and the
## reason an army of individuals trickles.
static func squad_lifecycle(ctx: Node, rig: TestRig, team: int) -> void:
	var muster := Vector2(600, 600)
	var spot := NavWorld.current.find_free_spot(muster, "robot")
	if spot == Vector2.INF:
		print("SQUAD: no clear ground near %s (skipped)" % muster)
		return
	var sq := AiSquad.new(team, AiSquad.Mission.CAPTURE)
	sq.staging = spot
	sq.objective = spot + Vector2(600, 0)
	sq.fallback = spot
	var troops: Array[Unit2D] = []
	# four together at the muster, one a long way off: the squad must
	# WAIT for the straggler instead of advancing with what turned up
	for i in 5:
		var away: Vector2 = spot + (Vector2(500, 0) if i == 4
			else Vector2(float(i) * 20.0, 0))
		var at := NavWorld.current.find_free_spot(away, "robot")
		if at == Vector2.INF:
			continue
		var u: Unit2D = Spawner.spawn(ctx, "robot", "grunt", team, at) as Unit2D
		u.hp = 100000000
		u.max_hp = 100000000
		troops.append(u)
		sq.add(u)
	rig.check(sq.size() >= 3, "only staffed %d of 5 troops" % sq.size())
	if sq.size() < 3:
		for u in troops:
			if is_instance_valid(u):
				u.queue_free()
		return
	# commit weight it cannot reach yet: the squad must stay GATHERING
	sq.commit_power = sq.strength() * 4.0
	var orders: Array = []
	# the real intake, not a recorder: _needs_order asks the unit whether
	# it is idle, so an order that is only logged leaves every member idle
	# and the throttle below can never be exercised
	var issue := func(u, o):
		orders.append({"u": u, "o": o})
		u.issue_order(o)
	sq.tick(issue)
	rig.check(sq.phase == AiSquad.Phase.GATHERING,
		"a squad below its commit weight advanced anyway (phase %s)"
		% AiSquad.Phase.keys()[sq.phase])
	rig.check(not orders.is_empty(),
		"a gathering squad issued no orders at all")
	var toward_muster := 0
	for entry in orders:
		if (entry.o as Order).position.distance_to(spot) < AiSquad.LAG_RADIUS:
			toward_muster += 1
	rig.check(toward_muster > 0,
		"a gathering squad sent nobody toward its staging point")
	# ORDERS ARE INTERRUPTIONS: a second tick with nothing changed must
	# not re-order everybody. Re-sending the same destination every pass
	# resets each unit's route and its stuck budget, which is what made
	# an army stutter and never arrive.
	orders.clear()
	sq.tick(issue)
	rig.check(orders.size() < sq.size(),
		"the squad re-ordered %d of %d members with nothing changed"
		% [orders.size(), sq.size()])
	# formed up and up to weight: it commits
	sq.commit_power = 0.0
	for u in sq.members:
		(u as Node2D).global_position = NavWorld.current.find_free_spot(
			spot + Vector2(randf_range(-30.0, 30.0), randf_range(-30.0, 30.0)),
			"robot")
	sq.tick(issue)
	rig.check(sq.phase != AiSquad.Phase.GATHERING,
		"a formed squad at full weight never left the muster")
	# BEATEN IS BEATEN. Down to one member from five, it falls back
	# instead of feeding the last body in.
	var doomed: Array = sq.members.duplicate()
	for i in range(1, doomed.size()):
		(doomed[i] as Unit2D).alive = false
	sq.tick(issue)
	rig.check(sq.phase == AiSquad.Phase.FALLING_BACK or sq.done,
		"a squad reduced to one member of %d kept attacking (phase %s)"
		% [doomed.size(), AiSquad.Phase.keys()[sq.phase]])
	for u in troops:
		if is_instance_valid(u):
			u.queue_free()


## ARRIVES AS A BODY, NOT AS A TRICKLE — the property the whole squad
## layer exists for, measured.
##
## Six troops scattered over 400px are given one objective 700px away.
## Commanded individually (what the brain used to do) they reach it in
## the order they happen to finish walking, so the first arrival stands
## alone in front of the objective for as long as it takes the last one
## to cross the map, and dies there. As a squad they muster first and
## cross together, so the spread AT CONTACT stays inside a squad's own
## frontage.
static func squad_arrives_together(ctx: Node, rig: TestRig, team: int) -> void:
	var levers_was: bool = TestLevers.direct_step
	var idle_was: bool = GameSettings.auto_idle
	TestLevers.direct_step = true   # logic-only: this tests ORDERING, not physics
	GameSettings.auto_idle = false
	GameState.over = true
	var muster := NavWorld.current.find_free_spot(Vector2(600, 900), "robot")
	var goal := NavWorld.current.find_free_spot(Vector2(600, 1600), "robot")
	if muster == Vector2.INF or goal == Vector2.INF \
			or NavWorld.current.request_path(muster, goal, "robot").is_empty():
		print("SQUADMARCH: no routable pair near the muster (skipped)")
		TestLevers.direct_step = levers_was
		GameSettings.auto_idle = idle_was
		return
	var sq := AiSquad.new(team, AiSquad.Mission.CAPTURE)
	sq.staging = muster
	sq.objective = goal
	sq.fallback = muster
	sq.commit_power = 0.0
	var troops: Array[Unit2D] = []
	var scatter: Array[Vector2] = [Vector2(0, 0), Vector2(-180, -90),
		Vector2(200, -140), Vector2(-260, 120), Vector2(240, 160),
		Vector2(-60, 300)]
	for off in scatter:
		var at := NavWorld.current.find_free_spot(muster + off, "robot")
		if at == Vector2.INF:
			continue
		var u: Unit2D = Spawner.spawn(ctx, "robot", "grunt", team, at) as Unit2D
		u.hp = 100000000
		u.max_hp = 100000000
		troops.append(u)
		sq.add(u)
	if sq.size() < 4:
		print("SQUADMARCH: only %d troops placed (skipped)" % sq.size())
		for u in troops:
			if is_instance_valid(u):
				u.queue_free()
		TestLevers.direct_step = levers_was
		GameSettings.auto_idle = idle_was
		return
	var start_spread: float = sq.spread()
	rig.check(start_spread > AiSquad.COHESION_RADIUS,
		"the fixture did not scatter the squad (spread %.0fpx)" % start_spread)
	var issue := func(u, o): u.issue_order(o)
	var contact_spread := -1.0
	var think := 0.0
	for i in 4000:
		# one command cycle per simulated second, like a think pass
		think += 0.05
		if think >= 1.0:
			think = 0.0
			sq.tick(issue)
			if sq.done:
				break
		for u in sq.members:
			u._process(0.05)
			u._physics_process(0.05)
		if sq.phase == AiSquad.Phase.ENGAGED and contact_spread < 0.0:
			contact_spread = sq.spread()
			break
	rig.check(contact_spread >= 0.0,
		"the squad never reached its objective in 200 simulated seconds "
		+ "(phase %s, %.0fpx short)" % [AiSquad.Phase.keys()[sq.phase],
			sq.centre().distance_to(goal) if sq.centre() != Vector2.INF else -1.0])
	if contact_spread >= 0.0:
		# THE MEASUREMENT. Arriving together means the squad's frontage at
		# contact is a squad's frontage — not the length of the march.
		rig.check(contact_spread <= AiSquad.COHESION_RADIUS * 2.0,
			"at contact the squad was spread %.0fpx (cap %.0f) — it arrived "
			% [contact_spread, AiSquad.COHESION_RADIUS * 2.0]
			+ "in ones, which is the trickle this layer exists to stop")
		var in_contact := 0
		for u in sq.members:
			if (u as Node2D).global_position.distance_to(goal) \
					<= AiSquad.ENGAGE_RADIUS * 2.0:
				in_contact += 1
		rig.check(in_contact >= int(ceil(float(sq.size()) * 0.6)),
			"only %d of %d made contact together" % [in_contact, sq.size()])
	for u in troops:
		if is_instance_valid(u):
			u.queue_free()
	TestLevers.direct_step = levers_was
	GameSettings.auto_idle = idle_was
	rig.check(true, "")
	print("SQUADMARCH: start_spread=%.0f contact_spread=%.0f" % [
		start_spread, contact_spread])


## THE ENEMY KNOWS HOW TO BUILD. Z has no build queue — a factory is
## pointed at ONE type and turns it out indefinitely — so the brain's job
## is not "spend money on things", it is "keep every facility aimed at the
## right thing and then LEAVE IT ALONE".
##
## Both halves are asserted, because each fails in its own way:
##
##   AIMED    a facility with no selection produces nothing at all, so an
##            idle factory is the AI doing nothing with its economy.
##   STICKY   re-rolling the choice every think pass is worse than not
##            choosing. Switching carries the build clock over, so a line
##            that changes every second emits whatever it happened to be
##            pointing at when the timer landed — a random unit stream,
##            and never the unit the stance actually wanted.
static func builds_and_commits(ctx: Node, rig: TestRig, ai: CpuAi) -> void:
	# TWO SOURCES, AND THEY MUST AGREE. The brain iterates the FACILITIES
	# group; `produces_anything()` is what the rest of the game calls a
	# producer. Group membership is decided ONCE in Building2D._ready, so
	# a producer that missed it is invisible to the brain for the whole
	# match — it would never be aimed at anything and would never build a
	# thing, which is a different and worse bug than an idle line.
	# Asserted separately so the two cannot be confused.
	var mine: Array[Building2D] = []
	var unseen: Array[String] = []
	for b in BuildingRegistry.all():
		if not (b is Building2D) or not b.alive or not b.produces_anything():
			continue
		if (b as Building2D).team != ai.team:
			continue
		if not b.is_in_group(Groups.FACILITIES):
			unseen.append("%s(id=%d)" % [b.kind_key(), b.building_id])
			continue
		mine.append(b)
	rig.check(unseen.is_empty(),
		"%d producer(s) of the brain's are NOT in the FACILITIES group, so "
		% unseen.size() + "it can never aim them: %s" % ", ".join(unseen))
	if mine.is_empty():
		print("AIBUILD: the brain owns no facilities (skipped)")
		return
	# THINK FIRST. This used to count idle lines straight off the end of
	# the simulation, where a factory captured on the final frame has
	# legitimately not been aimed yet — the brain aims it on its next
	# pass, which is exactly what is being asserted. Measuring before that
	# pass made the check fail about one run in six for a brain that was
	# behaving correctly.
	ai._produce()
	var idle := 0
	var off_roster := 0
	for b in mine:
		var sel := b.selected_product()
		if sel == "":
			idle += 1
		elif not b.build_options().has(sel):
			off_roster += 1
	rig.check(idle == 0,
		"%d of %d AI facilities are making nothing — an unaimed line is an "
		% [idle, mine.size()] + "economy the brain is not using")
	rig.check(off_roster == 0,
		"%d AI facilities are aimed at something not on their own roster"
		% off_roster)
	# STICKY: think repeatedly with nothing about the map changed. The
	# pass above already settled every line, so from here the brain must
	# be absolutely still.
	var before: Array[String] = []
	for b in mine:
		before.append(b.selected_product())
	for i in 6:
		ai._produce()
	var churn := 0
	for i in mine.size():
		if mine[i].selected_product() != before[i]:
			churn += 1
	rig.check(churn == 0,
		"%d of %d lines changed across 6 back-to-back think passes with "
		% [churn, mine.size()] + "nothing changed — the brain is thrashing "
		+ "its factories instead of committing")
	var rows: Array[String] = []
	for b in mine:
		rows.append("%s=%s" % [b.kind_key(), b.selected_product()])
	print("AIBUILD: %s" % ", ".join(rows))


## AN EMPLACEMENT IS NOT A MANOEUVRE UNIT. Cannons are Vehicle2D with
## speed 0 — they cannot walk to a post, cannot muster with a squad and
## cannot capture a sector. Every allocation pass in the brain drafts from
## one list of "vehicles", so until that list was split by ROLE a turret
## could be posted on a bridge it could never reach (holding a guard slot
## against the static-defence cap while guarding nothing) and, worse, be
## drafted into a squad: it is armed, so it counted toward the squad's
## strength, and a squad's centre is the mean of its members — so the
## squad's own rally point was dragged onto the immobile gun and every
## member was told to close up on it. An army parked around one turret on
## one bridge is what that looks like in play.
static func emplacements_never_manoeuvre(ctx: Node, rig: TestRig,
		ai: CpuAi) -> void:
	var guns: Array[Node] = []
	for u in UnitRegistry.current.world_units():
		if u is Vehicle2D and u.alive and u.team == ai.team and u.speed <= 0.0:
			guns.append(u)
	# the roster must classify them, whether or not any exist right now
	var roster: Dictionary = ai._roster()
	rig.check((roster.emplacements as Array).size() == guns.size(),
		"the roster sorted %d of %d immobile guns as emplacements"
		% [(roster.emplacements as Array).size(), guns.size()])
	for g in guns:
		rig.check(not (roster.mobile as Array).has(g),
			"an immobile gun is in the brain's MOBILE list — every pass "
			+ "that moves things will draft it")
	if guns.is_empty():
		print("EMPLACE: the brain owns no guns yet (classification asserted)")
		return
	# and nothing that moves units may be holding one
	var in_squads := ai.squad_units()
	var guards := ai.guard_units()
	var drafted := 0
	var posted := 0
	for g in guns:
		if in_squads.has(g):
			drafted += 1
		if guards.has(g):
			posted += 1
	rig.check(drafted == 0,
		"%d immobile gun(s) are in a squad — the squad will wait at a "
		% drafted + "muster they can never reach")
	rig.check(posted == 0,
		"%d immobile gun(s) are posted on a crossing they cannot walk to"
		% posted)
	print("EMPLACE: %d gun(s), none drafted or posted" % guns.size())


# ---- 4. one owner per unit -------------------------------------------

## THE RULE THAT KEEPS THE LAYERS APART. A unit may be spoken for by
## exactly one thing: a squad, a crossing guard, or the per-unit
## assignment. Two layers commanding one unit is worse than either alone
## — the unit stops mid-path every time the other layer changes its mind.
static func single_owner(ctx: Node, rig: TestRig, ai: CpuAi) -> void:
	var in_squads := ai.squad_units()
	var guards := ai.guard_units()
	var both := 0
	for u in in_squads:
		if guards.has(u):
			both += 1
	rig.check(both == 0,
		"%d units are in a squad AND posted on a crossing" % both)
	var twice := 0
	var seen := {}
	for sq in ai._squads:
		for u in sq.members:
			if seen.has(u):
				twice += 1
			seen[u] = true
	rig.check(twice == 0, "%d units belong to two squads at once" % twice)
	# and every squad member is a unit that can actually fight — a squad
	# staffed with cranes is a squad that loses
	var useless := 0
	for u in in_squads:
		if AiMap.power_of(u) <= 0.0 and is_instance_valid(u) and u.alive:
			useless += 1
	rig.check(useless == 0,
		"%d squad members carry no fight (cranes/empty transports)" % useless)
	# the committed set must be exactly the union, or the tactical passes
	# below are filtering against the wrong list
	var committed := ai._committed()
	var missing := 0
	for u in in_squads:
		if not committed.has(u):
			missing += 1
	for u in guards:
		if not committed.has(u):
			missing += 1
	rig.check(missing == 0,
		"%d committed units are absent from the committed set" % missing)
	# AND THE ARMY IS NOT ALL IN SQUADS. Crews for the hardware lying
	# around, crate runs and the crossing guards need bodies too: a
	# commander that draws every rifle into a line stops doing all the
	# things that make a Z army stronger than its head count.
	var in_squad_power := 0.0
	for sq in ai._squads:
		in_squad_power += sq.strength()
	if ai._map != null and ai._map.own_power > 0.0:
		var share: float = in_squad_power / ai._map.own_power
		rig.check(share <= CpuAi.SQUAD_ARMY_SHARE + 0.15,
			"%.0f%% of the army is tied up in squads (cap %.0f%%)"
			% [share * 100.0, CpuAi.SQUAD_ARMY_SHARE * 100.0])
