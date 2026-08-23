class_name FortBuilding
extends Building2D
## The fort: fixed team (the map owner), the win objective, a full
## producer (robots/vehicles/cannons per its level) — and a garrison:
## robots ordered inside man the fort's own missile launcher (original:
## ENTER_FORT_WP + fort turret missiles), just like the original game's
## screaming fort defenses.

const GARRISON_MISSILE: ProjectileDef = preload(
	"res://content/projectiles/garrison_missile.tres")


# Cannon mount slots, in fort-ART pixels from the art's top-left (each
# variant's two inner towers flanking the gate + the two outer corner
# towers). Manufactured guns MOUNT here, one per slot — no unlimited
# turret spam (the original's tower guns; zod stores max 4 built cannons
# per producer). Slot guns spawn MANNED: tower cells are solid, a robot
# could never walk up to crew them.
const SLOTS_FRONT := [Vector2(38, 80), Vector2(122, 80),
	Vector2(10, 26), Vector2(150, 26)]
const SLOTS_BACK := [Vector2(40, 64), Vector2(120, 64),
	Vector2(10, 14), Vector2(150, 14)]

var garrison: Array[Node] = []
var _missile_timer := 0.0
var _missile_target: Node2D = null
var slot_cannons: Array = []  # slot index -> manned cannon (or null)
## Crew badge: one standing-robot sprite per defender inside, above the
## fort's HP bar. See _sync_crew_badge.
var _crew_pips: Array[Sprite2D] = []
var _crew_shown := -1


func kind_key() -> String:
	return "fort"


func producer_key() -> String:
	return "fort"


## Tower mount points in WORLD px for this fort's art variant.
func cannon_slots() -> Array:
	var tex: String = ContentDB.building_def(building_id).tex \
		if ContentDB.building_def(building_id) != null else "fort_front"
	var art: Array = SLOTS_BACK if tex == "fort_back" else SLOTS_FRONT
	var origin: Vector2 = art_world_rect().position
	var out: Array = []
	for off in art:
		out.append(origin + Vector2(off))
	return out


func _ready() -> void:
	super()
	slot_cannons.resize(cannon_slots().size())


## Is tower mount `i` taken? A gun that DIED or was towed off frees its
## mount; one that merely lost its crew (sniped) still physically sits
## there and keeps the slot — a robot ordered onto it re-crews it
## (Unit2D._try_enter boards stranded hardware from arm's length, since
## tower cells are solid and cannot be stood on). ONE predicate for the
## build gate and mount_product — the two carried different rules, so
## the gate could refuse a cannon that mount_product would have placed.
func _slot_taken(i: int, slots: Array) -> bool:
	if i >= slot_cannons.size():
		return false
	var mounted = slot_cannons[i]
	if mounted == null:
		return false
	if is_instance_valid(mounted) and mounted.alive \
			and mounted.global_position.distance_to(slots[i]) < 48.0:
		return true
	slot_cannons[i] = null  # died or moved off: mount is free again
	return false


## Free mount slots, counting cannons already mounted and cannons still
## in the production queue.
func free_cannon_slots() -> int:
	var slots := cannon_slots()
	var free := slots.size()
	for i in slots.size():
		if _slot_taken(i, slots):
			free -= 1
	for item in queue.items:
		if String(item).begins_with("cannon:"):
			free -= 1
	return maxi(free, 0)


func queue_unit(item: String, silent := false) -> bool:
	if item.begins_with("cannon:") and free_cannon_slots() == 0:
		if not silent:
			Fx.cap_denied()  # every tower mount is taken or queued
		return false
	return super(item, silent)


## Fort products try the tower mounts first: a cannon takes a free slot
## (manned) instead of spawning beside the footprint.
func mount_product(kind: String, type_name: String) -> bool:
	if kind != "cannon":
		return false
	var slots := cannon_slots()
	if slot_cannons.size() < slots.size():
		slot_cannons.resize(slots.size())
	for i in slots.size():
		if _slot_taken(i, slots):
			continue
		slot_cannons[i] = Spawner.spawn(get_parent(), "cannon", type_name,
			owner_team, slots[i], true)
		return true
	return false  # no free mount: the producer spawns it beside


## The fort falling kills its tower guns with it.
func _death_visuals() -> void:
	super()
	for i in slot_cannons.size():
		var mounted = slot_cannons[i]
		slot_cannons[i] = null
		if mounted != null and is_instance_valid(mounted) and mounted.alive:
			mounted.take_damage(1000000)




## HOW MANY DEFENDERS ARE ACTUALLY INSIDE. The list can hold entries that
## died some other way, so every caller that shows or acts on the
## garrison counts through here — the badge, the panel's EXIT button and
## the cursor used to each carry their own loop over `garrison`.
func crew_count() -> int:
	var live := 0
	var stale := false
	for member in garrison:
		if _is_crew(member):
			live += 1
		else:
			stale = true
	if stale:
		# a dead entry that stays in the list is a ghost defender: it ate
		# a garrison_cap slot for the rest of the match and kept the
		# missile battery firing with nobody left to crew it
		garrison = garrison.filter(_is_crew)
	return live


## A garrison entry is a live robot that is still INSIDE — `carried` is
## what "inside" means everywhere else in the game (APC cargo, vehicle
## crew), and release_garrison clears it on the way out.
static func _is_crew(member) -> bool:
	return is_instance_valid(member) and member.alive and member.carried


## THE CREW BADGE — the affordance the garrison never had.
##
## A robot ordered onto its own fort walks in and vanishes: no sprite, no
## selection ring, out of the unit groups. Nothing on screen said it was
## in there, so from the player's side a robot sent to man the missiles
## was a robot thrown away, and the way to get it back (select the fort,
## press X or the panel's EXIT) is undiscoverable if you cannot tell
## there is anything to get back.
##
## So the fort WEARS its crew: one standing-robot sprite per defender,
## in the owner's team colour, in a row above the HP bar. It is the
## robots' own `stand_<team>_r270` art (facing the camera), so a crewed
## fort reads at a glance and an ENEMY crewed fort does too — which is
## real information, since a crewed fort is the one firing missiles.
const CREW_ART := "res://assets/z/robots/stand_%s_r270.png"
const CREW_PIP := 16.0     # the art is 16x16
const CREW_ROW_Y := -46.0  # just above the fort HP bar (which spans -30..-24)


func _sync_crew_badge() -> void:
	var live := crew_count()
	if live == _crew_shown:
		return
	_crew_shown = live
	var tex: Texture2D = null
	if live > 0:
		var path: String = CREW_ART % AnimLibrary.team_name(team if team > 0 else 1)
		tex = load(path) if ResourceLoader.exists(path) else null
	while _crew_pips.size() < live:
		var pip := Sprite2D.new()
		pip.centered = false
		pip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(pip)
		_crew_pips.append(pip)
	# the row is centred on the fort art, like the flag above it
	var row_w: float = float(live) * CREW_PIP
	var left: float = -8.0 + (art_world_rect().size.x - row_w) * 0.5
	for i in _crew_pips.size():
		var pip: Sprite2D = _crew_pips[i]
		pip.visible = i < live and tex != null
		if not pip.visible:
			continue
		pip.texture = tex
		pip.position = Vector2(left + float(i) * CREW_PIP, CREW_ROW_Y)


## A robot walks in: hide it, it fights (and hides) from inside.
func garrison_robot(robot: Unit2D) -> bool:
	if team == 0 or team != robot.team \
			or crew_count() >= ContentDB.building_def(building_id).garrison_cap:
		return false
	garrison.append(robot)
	robot.carried = true
	robot.set_selected(false)
	robot.visible = false
	robot.velocity = Vector2.ZERO
	robot.clear_move_target()
	robot.waypoints = PackedVector2Array()
	robot.remove_from_group(Groups.SELECTABLE)
	robot.remove_from_group(Groups.UNITS)
	SelectionManager.current.drop_from_selection(robot)
	_sync_crew_badge()
	return true


func _tick_behaviours(delta: float) -> void:
	tick_production(delta)
	if team != 0 and crew_count() > 0:
		_garrison_fire(delta)
	# the garrison has no signal of its own (robots walk in by themselves,
	# and a defender can die with the fort or to splash), so the badge
	# follows the count — _sync_crew_badge returns immediately unless it
	# actually changed
	if not garrison.is_empty() or _crew_shown > 0:
		_sync_crew_badge()


## The fort's own missile battery: fires while crewed (garrisoned) at
## the nearest enemy in reach.
func _garrison_fire(delta: float) -> void:
	_missile_timer = maxf(0.0, _missile_timer - delta)
	if _missile_timer > 0.0:
		return
	var best: Node2D = null
	var _range: float = ContentDB.building_def(building_id).garrison_missile_range
	var best_d := _range * _range
	for u in get_tree().get_nodes_in_group(Groups.UNITS):
		if u is Node2D and u is Unit2D and u.alive and not u.carried \
				and u.team != 0 and u.team != team \
				and visual_center().distance_squared_to(u.global_position) < best_d:
			best_d = visual_center().distance_squared_to(u.global_position)
			best = u
	if best == null:
		return
	_missile_timer = ContentDB.building_def(building_id).garrison_missile_cooldown
	_missile_target = best
	# MOBIMISS, not MOBIMIS: no such wav ships, so the fort's missile
	# battery fired in complete silence
	Fx.gunfire("MOBIMISS")
	var from := visual_center() + Vector2(0, -10)
	var impact: Vector2 = best.global_position
	ShellSolver.deliver(self, from, impact, GARRISON_MISSILE,
			func():
				# ONE roll with falloff (combat.gd rule) — a direct hit
				# plus splash double-charged the primary target
				Combat.area_damage(impact, 40.0, 167, team, true))  # map_item_turrent_damage 50/240, x0.08


## Send the garrison back out. The original never gave you a way to do
## this, and neither did we — a robot ordered into a fort simply left the
## world: invisible, degrouped, unselectable, gone for the rest of the
## match with no affordance to explain it. The defenders are real nodes
## (they used to be queue_free'd here), so releasing them is just the
## reverse of garrison_robot: validated placement outside the walls,
## groups and visibility back. Returns how many actually stepped out.
func release_garrison() -> int:
	var out := 0
	var apron := world_footprint()
	for member in garrison:
		if not is_instance_valid(member) or not member.alive:
			continue
		# Fan them along the south apron, each spot body-validated. TRY
		# EVERY SIDE before giving up: with only the south apron and the
		# centre to aim at, a fort backed against rock or water could
		# refuse to give its garrison back at all, and a robot that
		# cannot come out is a robot lost for the match.
		var spot := Vector2.INF
		for candidate in [
				Vector2(apron.get_center().x + (out - 2) * 18.0, apron.end.y + 14.0),
				Vector2(apron.get_center().x, apron.end.y + 14.0),
				Vector2(apron.get_center().x, apron.position.y - 14.0),
				Vector2(apron.position.x - 14.0, apron.get_center().y),
				Vector2(apron.end.x + 14.0, apron.get_center().y),
				apron.get_center()]:
			spot = NavWorld.current.find_free_spot(candidate, member.kind)
			if spot != Vector2.INF:
				break
		if spot == Vector2.INF:
			continue  # genuinely walled in: keep this one inside
		member.global_position = spot
		member.carried = false
		member.visible = true
		member.add_to_group(Groups.SELECTABLE)
		member.add_to_group(Groups.UNITS)
		out += 1
	garrison = garrison.filter(func(m): return is_instance_valid(m) and m.carried)
	_sync_crew_badge()
	if out > 0 and team == MatchState.current.player_team:
		Fx.ui_click()
	return out


## The fort falling kills everyone inside.
func kill_garrison() -> void:
	for robot in garrison:
		if is_instance_valid(robot):
			robot.carried = false
			robot.die()
	garrison.clear()
	_sync_crew_badge()
