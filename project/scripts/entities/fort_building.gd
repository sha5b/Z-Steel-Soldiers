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
const SLOTS_FRONT := [Vector2(38, 80), Vector2(122, 80),
	Vector2(10, 26), Vector2(150, 26)]
const SLOTS_BACK := [Vector2(40, 64), Vector2(120, 64),
	Vector2(10, 14), Vector2(150, 14)]

var slot_cannons: Array = []  # slot index -> manned cannon (or null)


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




func _tick_behaviours(delta: float) -> void:
	tick_production(delta)
