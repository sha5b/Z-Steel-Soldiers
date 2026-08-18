extends Node
## Headless project tool: builds the reusable planet TileSet resources and
## converts every JSON map into an editable Godot scene (.tscn) under
## assets/maps_scenes/. Run:
##
##   godot --headless --path project res://tools/build_map_resources.tscn
##
## (Scene maps are generated data like the JSONs — keep them gitignored.)
## Runs as a tool SCENE, not `godot -s`, so autoloads are available and
## entity scripts compile normally.

const TILE := 16
const PLANETS := ["desert", "volcanic", "arctic", "city", "jungle"]

const BUILDING_SCRIPTS := {
	0: preload("res://scripts/entities/fort_building.gd"),
	1: preload("res://scripts/entities/fort_building.gd"),
	2: preload("res://scripts/entities/building.gd"),
	3: preload("res://scripts/entities/building.gd"),
	4: preload("res://scripts/entities/robot_factory.gd"),
	5: preload("res://scripts/entities/vehicle_factory.gd"),
	6: preload("res://scripts/entities/building.gd"),
	7: preload("res://scripts/entities/building.gd"),
}
const MAP_ROBOT_IDS := ["grunt", "psycho", "sniper", "tough", "pyro", "laser"]
const MAP_VEHICLE_IDS := ["jeep", "light", "medium", "heavy", "apc", "missile_launcher", "crane"]
const MAP_CANNON_IDS := ["gatling", "gun", "howitzer", "missile_cannon"]

var _tilesets := {}


func _ready() -> void:
	_make_tilesets()
	var maps := _convert_all_maps()
	print("DONE: %d tilesets, %d map scenes" % [_tilesets.size(), maps])
	get_tree().quit(0)


func _make_tilesets() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/tilesets")
	for planet in PLANETS:
		var path := "res://assets/z/planets/%s.png" % planet
		if not ResourceLoader.exists(path):
			push_error("no tileset texture: " + path)
			continue
		var tileset := TileSet.new()
		tileset.tile_size = Vector2i(TILE, TILE)
		var source := TileSetAtlasSource.new()
		source.texture = load(path)
		source.texture_region_size = Vector2i(TILE, TILE)
		for index in 20 * 24:
			source.create_tile(Vector2i(index % 20, index / 20))
		tileset.add_source(source)
		var out := "res://assets/tilesets/%s.tres" % planet
		var err := ResourceSaver.save(tileset, out)
		if err == OK:
			_tilesets[planet] = load(out)
			print("tileset: " + out)


func _convert_all_maps() -> int:
	DirAccess.make_dir_recursive_absolute("res://assets/maps_scenes")
	var converted := 0
	for f in DirAccess.get_files_at("res://assets/maps"):
		if not String(f).ends_with(".json"):
			continue
		var data: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://assets/maps/" + f))
		if data.is_empty():
			push_error("unreadable map: " + f)
			continue
		var out := "res://assets/maps_scenes/%s.tscn" % String(f).get_basename()
		if ResourceSaver.save(_build_scene(data), out) == OK:
			converted += 1
	return converted


## Builds the map as a node tree: Terrain TileMapLayer (paintable in the
## editor), Zone / building / unit / scenery nodes. Mirrors what the JSON
## loader spawns so both paths produce identical matches.
func _build_scene(data: Dictionary) -> PackedScene:
	var planet := String(data.terrain)
	var root := Node2D.new()
	root.name = String(data.get("name", "map"))
	root.set_script(load("res://scripts/game/map_scene.gd"))
	root.set("planet", planet)
	root.set("map_size", Vector2i(int(data.width), int(data.height)))
	root.y_sort_enabled = true

	var terrain := TileMapLayer.new()
	terrain.name = "Terrain"
	terrain.tile_set = _tilesets.get(planet, _tilesets.desert)
	root.add_child(terrain)
	terrain.owner = root
	var w := int(data.width)
	for y in int(data.height):
		for x in w:
			var index: int = data.tiles[y * w + x]
			terrain.set_cell(Vector2i(x, y), 0, Vector2i(index % 20, index / 20))

	for z in data.zones:
		var zone := Zone.new()
		zone.zone_rect = Rect2i(int(z.x), int(z.y), int(z.w), int(z.h))
		root.add_child(zone)
		zone.owner = root

	var rock_cells := {}
	for o in data.objects:
		var kind := String(o.type)
		var id := int(o.id)
		var pos := Vector2(int(o.x) * TILE + 8, int(o.y) * TILE + 8)
		if kind == "map_item" and id == 1:
			rock_cells[Vector2i(int(o.x), int(o.y))] = true
			continue
		var node: Node2D = _object_node(kind, id, int(o.owner), pos, planet)
		if node:
			# unique sibling names (PackedScene anonymizes duplicates)
			node.name = "%s_%d_%d" % [node.name, int(o.x), int(o.y)]
			root.add_child(node)
			node.owner = root
	# rocks last, as Y-sorted sprites from the planet sheet
	if not rock_cells.is_empty():
		var sheet: Texture2D = load("res://assets/z/planets/rocks_%s.png" % planet)
		for cell in rock_cells:
			var alone := true
			for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if rock_cells.has(cell + n):
					alone = false
					break
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(
				Vector2(Vector2i(3, 3) if alone else Vector2i(1, 1)) * TILE, Vector2(TILE, TILE))
			var rock := Sprite2D.new()
			rock.name = "Rock_%d_%d" % [cell.x, cell.y]
			rock.texture = atlas
			rock.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			rock.position = Vector2(cell) * TILE + Vector2(8, 8)
			rock.add_to_group("rocks")
			root.add_child(rock)
			rock.owner = root

	var packed := PackedScene.new()
	packed.pack(root)
	return packed


func _object_node(kind: String, id: int, owner_team: int, pos: Vector2,
		planet: String) -> Node2D:
	match kind:
		"robot":
			var type: String = MAP_ROBOT_IDS[id] if id < MAP_ROBOT_IDS.size() else "grunt"
			var unit: Node2D = load("res://scenes/unit.tscn").instantiate()
			unit.set("unit_name", type)
			unit.set("team", owner_team)
			unit.position = pos
			unit.name = "Robot_%s_T%d" % [type, owner_team]
			# name uniquified by caller with tile coords
			return unit
		"vehicle", "cannon":
			var ids: Array = MAP_VEHICLE_IDS if kind == "vehicle" else MAP_CANNON_IDS
			var type2 := String(ids[id]) if id < ids.size() else ""
			if not _has_art(kind, type2):
				return null
			var veh: Node2D = load("res://scenes/vehicle.tscn").instantiate()
			veh.set("kind", kind)
			veh.set("unit_name", type2)
			veh.set("team", 0 if owner_team == 0 else owner_team)
			veh.set("manned", owner_team != 0)
			veh.position = pos
			veh.name = "%s_%s_T%d" % [kind, type2, owner_team]
			return veh
		"building":
			var script: GDScript = BUILDING_SCRIPTS.get(id)
			if script == null:
				return null
			var building: Node2D = script.new()
			building.set("building_id", id)
			building.set("team", 0 if id == 6 or id == 7 else owner_team)
			building.set("planet", planet)
			building.position = pos
			building.name = "Building_T%d_%d" % [owner_team, id]
			return building
		"map_item":
			if id == 2 or id == 3:
				var pickup := Pickup.new()
				pickup.pickup_type = "grenades" if id == 2 else "rockets"
				pickup.position = pos
				return pickup
			return _scenery_node(id, pos, planet)
	return null


func _scenery_node(id: int, pos: Vector2, planet: String) -> Node2D:
	var info := SceneryDefs.for_id(id, planet)
	if info.is_empty():
		return null
	var sprite := Sprite2D.new()
	sprite.name = "Scenery_%d_%d" % [int(pos.x / TILE), int(pos.y / TILE)]
	sprite.texture = load(String(info.texture))
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(2, 2)
	sprite.position = pos
	return sprite


func _has_art(kind: String, type_name: String) -> bool:
	if type_name == "":
		return false
	var prefix := "vehicles_" if kind == "vehicle" else "cannons_"
	var dir := DirAccess.open("res://assets/z")
	if dir == null:
		return false
	var path := "res://assets/z/%s%s" % [prefix, type_name]
	var probe := DirAccess.open(path)
	if probe == null:
		return false
	probe.list_dir_begin()
	var f := probe.get_next()
	while f != "":
		if f.get_extension() == "png":
			probe.list_dir_end()
			return true
		f = probe.get_next()
	probe.list_dir_end()
	return false
