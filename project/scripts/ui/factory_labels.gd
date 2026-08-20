class_name FactoryLabels
extends Object
## Producer title plates — the production panel and the facility quick
## bar share ONE table (they had drifted into two copies).

## The original's own plates, one per producer. `robot_factory_label` and
## `vehicle_factory_label` were never copied out of the zod pack, so both
## factories used to borrow another plate — the robot factory showed the
## FORT's. tools/zod/copy_art.py brings them across; `building_label` is
## the generic fallback for a producer with no plate of its own.
const LABELS := {
	"fort": "res://assets/z/ui/production/fort_factory_label.png",
	"fort_factory": "res://assets/z/ui/production/fort_factory_label.png",
	"robot_factory": "res://assets/z/ui/production/robot_factory_label.png",
	"vehicle_factory": "res://assets/z/ui/production/vehicle_factory_label.png",
}
const FALLBACK := "res://assets/z/ui/production/building_label.png"


## Plate texture path for a producer key — never "" for a real producer,
## so a missing plate degrades to the generic one instead of a blank slot.
static func path_for(producer_key: String) -> String:
	var path: String = LABELS.get(producer_key, "")
	if path != "" and ResourceLoader.exists(path):
		return path
	return FALLBACK if ResourceLoader.exists(FALLBACK) else ""
