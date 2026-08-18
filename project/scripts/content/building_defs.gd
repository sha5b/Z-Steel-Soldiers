class_name BuildingDefs
extends RefCounted
## Building content, keyed by zod map object id. To add a building type:
## write a script extending Building2D (or a Producer), add base art under
## `assets/z/buildings/<kind>/base_<planet>.png` (+ `_destroyed`), then add
## an entry here. `tex` is the texture pattern key resolved by Building2D.
##
## Fields: name, size (tiles), script (instantiated by the map loader),
## tex (texture pattern key), fort (is the win objective), solid (blocks
## movement), bridge_span (walkable tiles when a bridge).

const BY_ID := {
	0: {"name": "fort_front", "size": Vector2i(5, 4), "script": preload("res://scripts/entities/fort_building.gd"),
		"tex": "fort_front", "fort": true, "solid": true},
	1: {"name": "fort_back", "size": Vector2i(5, 4), "script": preload("res://scripts/entities/fort_building.gd"),
		"tex": "fort_back", "fort": true, "solid": true},
	2: {"name": "radar", "size": Vector2i(2, 2), "script": preload("res://scripts/entities/building.gd"),
		"tex": "radar", "solid": true,
		"anims": [{"prefix": "dish", "fps": 5.0, "offset": Vector2(0, -6)}]},
	3: {"name": "repair", "size": Vector2i(2, 2), "script": preload("res://scripts/entities/building.gd"),
		"tex": "repair", "solid": true,
		"anims": [{"prefix": "smoke_stack", "fps": 5.0, "offset": Vector2(-10, -14)}]},
	4: {"name": "robot_factory", "size": Vector2i(3, 3), "script": preload("res://scripts/entities/robot_factory.gd"),
		"tex": "robot", "solid": true, "produces": true,
		"anims": [{"prefix": "spin", "fps": 7.0, "offset": Vector2(0, -8)}]},
	5: {"name": "vehicle_factory", "size": Vector2i(4, 3), "script": preload("res://scripts/entities/vehicle_factory.gd"),
		"tex": "vehicle", "solid": true, "produces": true,
		"anims": [{"prefix": "spin", "fps": 7.0, "offset": Vector2(0, -8)}]},
	6: {"name": "bridge_vert", "size": Vector2i(2, 8), "script": preload("res://scripts/entities/building.gd"),
		"tex": "bridge", "solid": false, "bridge_span": Vector2i(2, 8)},
	7: {"name": "bridge_horz", "size": Vector2i(8, 2), "script": preload("res://scripts/entities/building.gd"),
		"tex": "bridge", "solid": false, "bridge_span": Vector2i(8, 2)},
}


static func for_id(id: int) -> Dictionary:
	return BY_ID.get(id, {})


## What each producer may build, by building LEVEL 0..5 (the map `level`
## field). Entries are "kind:name". Transcribed from the original engine's
## zbuildlist.cpp — the roster unlocks as the building levels up, and the
## fort builds a bit of everything. Higher levels also build faster
## (Building2D.build_time_mult).
const BUILD_LISTS := {
	"fort": {
		0: ["robot:grunt", "vehicle:jeep", "vehicle:crane", "cannon:gatling"],
		1: ["robot:grunt", "robot:psycho", "vehicle:jeep", "vehicle:light",
			"vehicle:crane", "cannon:gatling", "cannon:gun"],
		2: ["robot:grunt", "robot:psycho", "robot:sniper", "robot:tough",
			"vehicle:jeep", "vehicle:light", "vehicle:medium", "vehicle:crane",
			"cannon:gatling", "cannon:gun", "cannon:howitzer"],
		3: ["robot:grunt", "robot:psycho", "robot:sniper", "robot:tough",
			"robot:pyro", "vehicle:jeep", "vehicle:light", "vehicle:medium",
			"vehicle:apc", "vehicle:crane", "cannon:gatling", "cannon:gun",
			"cannon:howitzer"],
		4: ["robot:grunt", "robot:psycho", "robot:sniper", "robot:tough",
			"robot:pyro", "robot:laser", "vehicle:jeep", "vehicle:light",
			"vehicle:medium", "vehicle:heavy", "vehicle:apc", "vehicle:crane",
			"cannon:gatling", "cannon:gun", "cannon:howitzer", "cannon:missile_cannon"],
		5: ["robot:grunt", "robot:psycho", "robot:sniper", "robot:tough",
			"robot:pyro", "robot:laser", "vehicle:jeep", "vehicle:light",
			"vehicle:medium", "vehicle:heavy", "vehicle:apc",
			"vehicle:missile_launcher", "vehicle:crane",
			"cannon:gatling", "cannon:gun", "cannon:howitzer", "cannon:missile_cannon"],
	},
	"robot_factory": {
		0: ["robot:grunt", "cannon:gatling"],
		1: ["robot:grunt", "robot:psycho", "cannon:gatling"],
		2: ["robot:grunt", "robot:psycho", "robot:sniper", "robot:tough",
			"cannon:gatling", "cannon:gun"],
		3: ["robot:grunt", "robot:psycho", "robot:sniper", "robot:tough",
			"robot:pyro", "cannon:gatling", "cannon:gun", "cannon:howitzer"],
		4: ["robot:grunt", "robot:psycho", "robot:sniper", "robot:tough",
			"robot:pyro", "robot:laser", "cannon:gatling", "cannon:gun",
			"cannon:howitzer"],
		5: ["robot:grunt", "robot:psycho", "robot:sniper", "robot:tough",
			"robot:pyro", "robot:laser", "cannon:gatling", "cannon:gun",
			"cannon:howitzer", "cannon:missile_cannon"],
	},
	"vehicle_factory": {
		0: ["vehicle:jeep", "cannon:gatling"],
		1: ["vehicle:jeep", "vehicle:light", "cannon:gatling", "cannon:gun"],
		2: ["vehicle:jeep", "vehicle:light", "vehicle:medium",
			"cannon:gatling", "cannon:gun"],
		3: ["vehicle:jeep", "vehicle:light", "vehicle:medium", "vehicle:apc",
			"cannon:gatling", "cannon:gun", "cannon:howitzer"],
		4: ["vehicle:jeep", "vehicle:light", "vehicle:medium", "vehicle:heavy",
			"vehicle:apc", "cannon:gatling", "cannon:gun", "cannon:howitzer"],
		5: ["vehicle:jeep", "vehicle:light", "vehicle:medium", "vehicle:heavy",
			"vehicle:apc", "vehicle:missile_launcher",
			"cannon:gatling", "cannon:gun", "cannon:howitzer", "cannon:missile_cannon"],
	},
}
