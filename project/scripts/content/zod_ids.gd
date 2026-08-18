class_name ZodIds
extends RefCounted
## Zod map object-id mappings (tools/zod/map_to_json.py writes the ids;
## the arrays are index-ordered). Kept as code: they are engine constants
## of the original data format, not authorable content.

const MAP_ROBOT_IDS := ["grunt", "psycho", "sniper", "tough", "pyro", "laser"]
const MAP_VEHICLE_IDS := ["jeep", "light", "medium", "heavy", "apc",
	"missile_launcher", "crane"]
const MAP_CANNON_IDS := ["gatling", "gun", "howitzer", "missile_cannon"]

## Zod map_item ids that are pickups (2 grenades, 3 rockets).
const MAP_PICKUP_IDS := {2: "grenades", 3: "rockets"}


static func unit_name(kind: String, id: int) -> String:
	var ids: Array = MAP_ROBOT_IDS if kind == "robot" \
			else MAP_VEHICLE_IDS if kind == "vehicle" \
			else MAP_CANNON_IDS
	return ids[id] if id >= 0 and id < ids.size() else ""
