class_name PickupDef
extends Resource
## One collectible crate — .tres files under content/pickups/. The
## effect is data: `upgrade_key` grants that team upgrade (damage
## multipliers etc.), `grenades` arms the collecting robot with throwables.

@export var id := "grenades"
@export var texture: Texture2D = null
@export var sound_set := ""  # Fx sound-set key ("" = default pickup click)
@export var upgrade_key := ""  # MatchState.current.grant_upgrade key ("" = none)
@export var grenades := 0  # throwable grenades given to the collector
## Comma-separated unit kinds that can USE this crate ("" = anyone). A
## crate used to be consumed by whatever touched it first, so a tank
## rolling over a grenade box destroyed it and armed nobody.
@export var takers := ""


## Can `kind` ("robot" | "vehicle" | "cannon") make use of this crate?
func usable_by(kind: String) -> bool:
	return takers == "" or kind in takers.split(",")
