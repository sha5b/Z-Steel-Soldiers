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
		"tex": "radar", "solid": true},
	3: {"name": "repair", "size": Vector2i(2, 2), "script": preload("res://scripts/entities/building.gd"),
		"tex": "repair", "solid": true},
	4: {"name": "robot_factory", "size": Vector2i(3, 3), "script": preload("res://scripts/entities/robot_factory.gd"),
		"tex": "robot", "solid": true},
	5: {"name": "vehicle_factory", "size": Vector2i(4, 3), "script": preload("res://scripts/entities/vehicle_factory.gd"),
		"tex": "vehicle", "solid": true},
	6: {"name": "bridge_vert", "size": Vector2i(2, 8), "script": preload("res://scripts/entities/building.gd"),
		"tex": "bridge", "solid": false, "bridge_span": Vector2i(2, 8)},
	7: {"name": "bridge_horz", "size": Vector2i(8, 2), "script": preload("res://scripts/entities/building.gd"),
		"tex": "bridge", "solid": false, "bridge_span": Vector2i(8, 2)},
}


static func for_id(id: int) -> Dictionary:
	return BY_ID.get(id, {})
