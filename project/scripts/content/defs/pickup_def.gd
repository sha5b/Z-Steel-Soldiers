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
