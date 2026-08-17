class_name SceneryDefs
extends RefCounted
## Non-interactive map decoration (zod map_item ids). Rocks (id 1) are
## special-cased by the map loader (planet rock sheets + nav blocking);
## pickups (2, 3) live in PickupDefs. Everything else renders here:
## id 4 is the planet-tinted hut, ids 5..26 are `map_object0..21.png`.
## To add scenery art: drop PNGs into `assets/z/map_items/` and extend
## `for_id`.

const HUT_ID := 4
const OBJECT_BASE_ID := 5  # id 5 -> map_object0.png, id 26 -> map_object21.png


static func for_id(id: int, planet: String) -> Dictionary:
	if id == HUT_ID:
		var hut := "res://assets/z/map_items/hut_%s.png" % planet
		if ResourceLoader.exists(hut):
			return {"texture": hut}
	elif id >= OBJECT_BASE_ID:
		var obj := "res://assets/z/map_items/map_object%d.png" % (id - OBJECT_BASE_ID)
		if ResourceLoader.exists(obj):
			return {"texture": obj}
	return {}  # id 0 and unknown ids have no art — skipped
