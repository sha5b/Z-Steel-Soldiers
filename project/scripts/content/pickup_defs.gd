class_name PickupDefs
extends RefCounted
## Pickup crate content. To add a new drop: add art under
## `assets/z/map_items/`, then an entry — `grants` names the upgrade key
## (GameState.grant_upgrade) plus optional damage-multiplier wiring in
## GameState. Sound is optional.

const TYPES := {
	"grenades": {
		"texture": "res://assets/z/map_items/grenades.png",
		"sound": "res://assets/z/sounds/GRENADE.wav",
		"grants": "grenades",
	},
	"rockets": {
		"texture": "res://assets/z/map_items/rockets.png",
		"sound": "",
		"grants": "rockets",
	},
}

## Zod map_item ids that are pickups (2 grenades, 3 rockets).
const MAP_IDS := {2: "grenades", 3: "rockets"}
