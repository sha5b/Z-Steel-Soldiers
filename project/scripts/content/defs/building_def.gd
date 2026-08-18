class_name BuildingDef
extends Resource
## One building type, keyed by the zod map object id — the .tres files
## under content/buildings/ are the editable source of truth. `script`
## instantiates the behaviour class (map loader); producers carry their
## level rosters in build_lists (entries are "kind:name" strings,
## transcribed from the original zbuildlist.cpp).

@export var id := 0  # zod map object id
@export var bname := "radar"  # unique name (fort keys build lists by it)
@export var producer := ""  # producer key when it builds units ("fort",
	# "robot_factory", "vehicle_factory"); both fort ids share "fort"
@export var size := Vector2i(2, 2)  # footprint in tiles
@export var behaviour: Script = null  # Building2D subclass (map loader)
@export var tex := ""  # texture pattern key resolved by Building2D
@export var is_fort := false  # win objective
@export var solid := true  # blocks movement
@export var produces := false  # registers on the facility bar
@export var bridge_span := Vector2i.ZERO  # walkable tiles when a bridge
@export var anims: Array[BuildingAnim] = []
@export var build_lists: Dictionary = {}  # level (0..5) -> Array["kind:name"]
