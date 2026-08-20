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
## Solid cells in ART tiles, relative to the art's top-left tile (art
## renders 1:1, one art tile = one 16px world tile). (0,0,0,0) = the
## whole art rect. Values transcribed from the original engine's
## SetMapImpassables (bfort.cpp/bradar.cpp) — forts leave their side
## platforms and gate walkable, the radar its entrance cell.
@export var solid_tiles := Rect2i()
## Cells INSIDE solid_tiles left walkable (art-tile coords).
@export var open_tiles: PackedVector2Array = PackedVector2Array()
@export var produces := false  # registers on the facility bar
@export var bridge_span := Vector2i.ZERO  # walkable tiles when a bridge
## Fort garrison battery (the missile towers) — fort defs only.
@export var garrison_missile_range := 180.0
@export var garrison_missile_cooldown := 3.0
@export var garrison_cap := 5
@export var anims: Array[BuildingAnim] = []
@export var build_lists: Dictionary = {}  # level (0..5) -> Array["kind:name"]
