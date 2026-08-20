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
# Units, buildings and ids all resolve through ContentDB — this tool has
# no content tables of its own

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
	root.set_script(load("res://scripts/game/z_map.gd"))
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

	var zones: Array[Zone] = []
	for z in data.zones:
		var zone := Zone.new()
		zone.zone_rect = Rect2i(int(z.x), int(z.y), int(z.w), int(z.h))
		root.add_child(zone)
		zone.owner = root
		zones.append(zone)

	var rock_cells := {}
	for o in data.objects:
		var kind := String(o.type)
		var id := int(o.id)
		var pos := Vector2(int(o.x) * TILE + 8, int(o.y) * TILE + 8)
		if kind == "map_item" and id == 1:
			rock_cells[Vector2i(int(o.x), int(o.y))] = true
			continue
		if kind == "map_item" and id == MapLoader.ZONE_FLAG_ID:
			# map_item 0 is the ZONE FLAG marker: the tile the designer
			# put the flag on plus the zone's STARTING OWNER. The JSON
			# loader applies it (MapLoader._apply_zone_flag); the scene
			# builder used to drop it, so every scene map opened fully
			# neutral with its flags at derived centre spots.
			_apply_zone_flag(zones, o)
			continue
		var node: Node2D = _object_node(kind, id, int(o.owner), pos, planet,
			Vector2i(int(o.get("span_w", 0)), int(o.get("span_h", 0))))
		if node:
			# unique sibling names (PackedScene anonymizes duplicates)
			node.name = "%s_%d_%d" % [node.name, int(o.x), int(o.y)]
			root.add_child(node)
			node.owner = root
	# rocks last, as Y-sorted sprites from the planet sheet. The PIECE
	# comes from the 4-neighbour mask through the one mapping the JSON
	# loader uses (MapLoader._rock_piece) — this tool used to stamp the
	# plateau INTERIOR fill on every clustered rock, which is the flat
	# pale slab bug all over again, in the scene maps only.
	if not rock_cells.is_empty():
		var sheet: Texture2D = load("res://assets/z/planets/rocks_%s.png" % planet)
		for cell in rock_cells:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(
				Vector2(MapLoader._rock_piece(cell, rock_cells)) * TILE,
				Vector2(TILE, TILE))
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


## Zone flag marker -> the zone that contains it (see
## MapLoader._apply_zone_flag, the same rule on the JSON path).
func _apply_zone_flag(zones: Array[Zone], o: Dictionary) -> void:
	var cell := Vector2i(int(o.x), int(o.y))
	for zone in zones:
		if not zone.zone_rect.has_point(cell):
			continue
		zone.flag_tile = cell
		var owner_team := int(o.get("owner", 0))
		if owner_team != 0:
			zone.owner_team = owner_team
		return


## `span` is the map's own bridge span in tiles (retail campaign only —
## the zod maps carry no size and fall back to the def).
func _object_node(kind: String, id: int, owner_team: int, pos: Vector2,
		planet: String, span := Vector2i.ZERO) -> Node2D:
	match kind:
		"robot", "vehicle", "cannon":
			var type_name := ContentDB.map_unit_name(kind, id)
			if type_name == "":
				return null
			if kind != "robot" and not ContentDB.has_sprites(kind, type_name):
				return null
			# per-type scenes (scenes/<kind-plural>/<name>.tscn) so maps
			# are editable unit by unit; base scenes as the fallback
			var scene := ContentDB.scene_for(kind, type_name)
			if scene == null:
				return null
			var unit: Node2D = scene.instantiate()
			unit.set("unit_name", type_name)
			unit.set("team", owner_team)
			if kind != "robot":
				unit.set("kind", kind)
				unit.set("manned", owner_team != 0)
			unit.position = pos
			unit.name = "%s_%s_T%d" % [{"robot": "Robot"}.get(kind, kind),
				type_name, owner_team]
			# name uniquified by caller with tile coords
			return unit
		"building":
			var def := ContentDB.building_def(id)
			if def == null:
				return null
			var scene_path := "res://scenes/buildings/%s.tscn" % def.bname
			var building: Node2D
			if ResourceLoader.exists(scene_path):
				building = (load(scene_path) as PackedScene).instantiate()
			else:
				building = def.behaviour.new()
			building.set("building_id", id)
			building.set("team", 0 if id == 6 or id == 7 else owner_team)
			if span != Vector2i.ZERO:
				building.set("bridge_span_override", span)
			building.set("planet", planet)
			building.position = pos
			building.name = "Building_T%d_%d" % [owner_team, id]
			return building
		"map_item":
			if ZodIds.MAP_PICKUP_IDS.has(id):
				var pickup := Pickup.new()
				pickup.pickup_type = String(ZodIds.MAP_PICKUP_IDS[id])
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
	# keep in lockstep with MapLoader._spawn_map_item: native art size,
	# bottom edge on the object tile (zod OMapObject::DoRender)
	sprite.position = pos + Vector2(
		sprite.texture.get_size().x - 16, 16 - sprite.texture.get_size().y) * 0.5
	return sprite

