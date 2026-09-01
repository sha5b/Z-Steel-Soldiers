class_name FortBuilding
extends Building2D
## The fort: fixed team (the map owner), the win objective, and a full
## producer (robots/vehicles/cannons per its level).
##
## NOTHING GOES INSIDE A FORT. There was a garrison here — robots ordered
## onto their own fort walked in, vanished from the world and crewed a
## missile battery from within. It is gone, deliberately: a unit that
## disappears into a building is a unit the player cannot see, select or
## count, and no amount of badge art on the roof fixes that. A fort
## defends itself with its TOWER GUNS (see the mount slots below), which
## are real cannons standing on real cells that can be shot off it.


# Cannon mount slots, in fort-ART pixels from the art's top-left (each
# variant's two inner towers flanking the gate + the two outer corner
# towers). Manufactured guns MOUNT here, one per slot — no unlimited
# turret spam (the original's tower guns; zod stores max 4 built cannons
# per producer). Slot guns spawn MANNED: tower cells are solid, a robot
# could never walk up to crew them.
# MEASURED OFF THE ART (fort_desert_front/back.png at 3x): the four
# octagonal tower platforms centre at these art pixels — identical on
# both variants; only the gate ramp below differs. The old table put
# the outer pair at the art EDGES (x 10/150, between the towers and
# thin air), which is why tower guns rendered floating beside the fort.
const TOWER_SLOTS := [Vector2(26, 63), Vector2(134, 63),
	Vector2(25, 16), Vector2(135, 16)]

## Elevation pays in reach: a gun on a fort tower outranges its
## ground-level twin, or it could not even cover its own fort's apron —
## the fort art is 160px across and a stock gatling reaches 120, so a
## tower gun measured from the far tower could not touch an enemy AT
## THE GATE ("the range is wrong, it never hits anything").
const TOWER_RANGE_SCALE := 1.8
## Map forts start with this many tower guns manned (the rest are built).
const STARTING_TOWER_GUNS := 1

var slot_cannons: Array = []  # slot index -> manned cannon (or null)


func kind_key() -> String:
	return "fort"


func producer_key() -> String:
	return "fort"


## Tower mount points in WORLD px (same platform layout on both art
## variants — only the gate ramp below the towers differs).
func cannon_slots() -> Array:
	var origin: Vector2 = art_world_rect().position
	var out: Array = []
	for off in TOWER_SLOTS:
		out.append(origin + Vector2(off))
	return out


func _ready() -> void:
	super()
	slot_cannons.resize(cannon_slots().size())
	# MAP FORTS STAND ARMED — but not fully. The original's starting
	# fort shoots back from minute one, so an undefended fort died to a
	# 4-unit opening rush; four free gatlings, though, made the opening
	# game a siege. ONE manned tower gun now (STARTING_TOWER_GUNS); the
	# other towers are the build-up. A gun destroyed or sniped frees its
	# slot exactly like a built one.
	if Engine.is_editor_hint() or owner_team == 0:
		return
	# DEFERRED: on a .tscn map this _ready runs while the packed scene is
	# still setting up its children, and get_parent().add_child() (inside
	# Spawner.spawn) fails there — the orphan gun would then hold slot 0
	# forever without ever entering the world
	_arm_starting_guns.call_deferred()


func _arm_starting_guns() -> void:
	if not is_inside_tree() or not alive:
		return
	for i in STARTING_TOWER_GUNS:
		if not mount_product("cannon", "gatling"):
			break


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


## Free mount slots — how many of the four towers have no live gun on
## them. There is no queue to discount any more: with a production LINE
## at most one cannon is ever in flight, and it takes its mount at the
## moment it is built (mount_product).
func free_cannon_slots() -> int:
	var slots := cannon_slots()
	var free := slots.size()
	for i in slots.size():
		if _slot_taken(i, slots):
			free -= 1
	return maxi(free, 0)


## THE FORT'S FOUR TOWER MOUNTS ARE THE CANNON CAP. A fort turning out
## cannons stops when all four are occupied and starts again the moment
## one is destroyed — the mounts free themselves in _slot_taken, so this
## needs no bookkeeping. Unlike the old refusal, the SELECTION survives
## the stall: the fort remembers it was building turrets and resumes by
## itself when a gun dies, instead of quietly dropping the order.
func accepts_product(kind: String, _type_name: String) -> bool:
	return kind != "cannon" or free_cannon_slots() > 0


## Selecting cannons with every mount already full is allowed — the line
## simply waits — but say so once, or a fort that appears to be building
## nothing looks broken.
func queue_unit(item: String, silent := false) -> bool:
	var ok := super(item, silent)
	if ok and not silent and item.begins_with("cannon:") \
			and free_cannon_slots() == 0:
		Fx.cap_denied()  # every tower mount is taken: it will wait
	return ok


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
		var gun := Spawner.spawn(get_parent(), "cannon", type_name,
			owner_team, slots[i], true)
		if gun is Unit2D:
			(gun as Unit2D).range_px *= TOWER_RANGE_SCALE  # elevation bonus
		slot_cannons[i] = gun
		return true
	return false  # no free mount: the producer spawns it beside


## AFTER A SAVE RESTORE the roster is respawned from scratch, so
## slot_cannons holds freed references and the restored guns standing
## on the towers are unlinked — free_cannon_slots() then over-reports
## and a new cannon could be mounted stacked on an occupied tower. The
## elevation bonus is also re-applied here: range_px is not in the save
## contract, so a restored tower gun came back at stock reach.
func relink_tower_guns() -> void:
	var slots := cannon_slots()
	slot_cannons.resize(slots.size())
	for i in slots.size():
		slot_cannons[i] = null
		for u in UnitRegistry.current.world_units():
			if u is Vehicle2D and u.kind == "cannon" and u.alive \
					and not u.is_queued_for_deletion() \
					and u.global_position.distance_to(slots[i]) < 16.0:
				var def := ContentDB.def_for("cannon", u.unit_name)
				if def != null:
					u.range_px = def.range_px * TOWER_RANGE_SCALE
				slot_cannons[i] = u
				break


## The fort falling kills its tower guns with it.
func _death_visuals() -> void:
	super()
	for i in slot_cannons.size():
		var mounted = slot_cannons[i]
		slot_cannons[i] = null
		if mounted != null and is_instance_valid(mounted) and mounted.alive:
			mounted.take_damage(1000000)




func _tick_behaviours(delta: float) -> void:
	tick_production(delta)
