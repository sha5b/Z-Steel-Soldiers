class_name MapLoader
extends Node
## Builds a Zod-format map (JSON from tools/zod/map_to_json.py): terrain,
## zones, scenery, units, buildings and the nav grids. What gets spawned
## for each object id is defined by the content tables
## (scripts/content/*.gd) — this file only knows the map format.

const TILE := 16
const PLANET_TILESETS := {
	"desert": "res://assets/z/planets/desert.png",
	"volcanic": "res://assets/z/planets/volcanic.png",
	"arctic": "res://assets/z/planets/arctic.png",
	"city": "res://assets/z/planets/city.png",
	"jungle": "res://assets/z/planets/jungle.png",
}


static func load_map(parent: Node, map_path: String) -> Dictionary:
	# decals (tracks/craters) and ambient animals anchor to the match root
	MatchState.map_root = parent
	if map_path.ends_with(".tscn"):
		return load_map_scene(parent, map_path)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(map_path))
	if data == null:
		push_error("map load failed: " + map_path)
		return {}
	var w := int(data.width)
	var h := int(data.height)
	var planet := String(data.terrain)

	_build_terrain(parent, data, planet, w, h)
	var grid := _build_nav_grid(data, w, h)
	_build_rocks(parent, data, planet, grid)
	var vgrid := _build_vehicle_grid(grid, data, w, h)
	_build_zones(parent, data)
	# objects (scenery, pickups, units, buildings) in map order so the
	# Y-sorted parent keeps a stable draw order
	for o in data.objects:
		var pos := Vector2(int(o.x) * TILE + 8, int(o.y) * TILE + 8)
		match String(o.type):
			"map_item":
				_spawn_map_item(parent, o, pos, planet)
			"robot", "vehicle", "cannon":
				_spawn_unit(parent, o, String(o.type), pos)
			"building":
				_spawn_building(parent, o, pos, planet, grid, vgrid, w, h)
	# one CPU brain per non-player team that owns a fort
	var ai_teams := {}
	for o in data.objects:
		var fort_def := ContentDB.building_def(int(o.id))
		if String(o.type) == "building" and fort_def != null and fort_def.is_fort \
				and int(o.owner) != 0:
			ai_teams[int(o.owner)] = true
	_init_zone_owners(parent)
	# every fort team gets a ledger entry (income + spend work for all)
	for t in ai_teams:
		MatchState.grant_ledger(t)
	for t in ai_teams:
		if t != MatchState.player_team:
			var ai := CpuAi.new(t)
			ai.name = "CpuAi_T%d" % t
			parent.add_child(ai)
	return data


static func _build_terrain(parent: Node, data: Dictionary, planet: String, w: int, h: int) -> void:
	var tilemap := TileMapLayer.new()
	tilemap.name = "Terrain"
	tilemap.z_index = -2  # ground: under the decal layer (-1), under the world
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)
	var source := TileSetAtlasSource.new()
	source.texture = load(PLANET_TILESETS.get(planet, PLANET_TILESETS.desert))
	source.texture_region_size = Vector2i(TILE, TILE)
	for index in 20 * 24:
		source.create_tile(Vector2i(index % 20, index / 20))
	tileset.add_source(source)
	tilemap.tile_set = tileset
	parent.add_child(tilemap)
	for y in h:
		for x in w:
			var index: int = data.tiles[y * w + x]  # row-major (GetTile: y=index/width)
			tilemap.set_cell(Vector2i(x, y), 0, Vector2i(index % 20, index / 20))


static func _build_nav_grid(data: Dictionary, w: int, h: int) -> AStarGrid2D:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, w, h)
	grid.cell_size = Vector2(TILE, TILE)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE
	grid.update()
	for y in h:
		for x in w:
			if data.passable != null and not bool(data.passable[y * w + x]):
				grid.set_point_solid(Vector2i(x, y), true)
	NavWorld.current.nav_grid = grid
	NavWorld.current.map_rect = Rect2(0.0, 0.0, float(w) * TILE, float(h) * TILE)
	return grid


## Rock scenery: one sprite per rock item from the planet's rock sheet
## (sheet layout from zod orock.cpp: 6x6 grid of 16px pieces; (3,3) is the
## standalone rock, (1,1) the mid-cluster top). Individual sprites (not a
## TileMapLayer) so each rock Y-sorts against units on the sorted parent —
## a rock correctly covers a unit standing behind it.
static func _build_rocks(parent: Node, data: Dictionary, planet: String, grid: AStarGrid2D) -> void:
	var rock_cells := {}
	for o in data.objects:
		if String(o.type) == "map_item" and int(o.id) == 1:
			rock_cells[Vector2i(int(o.x), int(o.y))] = true
	if rock_cells.is_empty():
		return
	var rock_sheet: Texture2D = load("res://assets/z/planets/rocks_%s.png" % planet)
	for cell in rock_cells:
		var alone := true
		for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if rock_cells.has(cell + n):
				alone = false
				break
		var atlas := AtlasTexture.new()
		atlas.atlas = rock_sheet
		atlas.region = Rect2(Vector2(Vector2i(3, 3) if alone else Vector2i(1, 1)) * TILE, Vector2(TILE, TILE))
		var rock := Sprite2D.new()
		rock.name = "Rock_%d_%d" % [cell.x, cell.y]
		rock.texture = atlas
		rock.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rock.position = Vector2(cell) * TILE + Vector2(8, 8)
		parent.add_child(rock)
		rock.add_to_group("rocks")
		grid.set_point_solid(cell, true)


## Vehicle grid: same as robots but water is impassable (zod PF_WATER).
## Built after rocks so rock cells block wheels too.
static func _build_vehicle_grid(grid: AStarGrid2D, data: Dictionary, w: int, h: int) -> AStarGrid2D:
	var vgrid := AStarGrid2D.new()
	vgrid.region = grid.region
	vgrid.cell_size = grid.cell_size
	vgrid.diagonal_mode = grid.diagonal_mode
	vgrid.update()
	for y in h:
		for x in w:
			var solid: bool = grid.is_point_solid(Vector2i(x, y)) \
					or (data.water != null and bool(data.water[y * w + x]))
			if solid:
				vgrid.set_point_solid(Vector2i(x, y), true)
	NavWorld.current.vehicle_grid = vgrid
	return vgrid


static func _build_zones(parent: Node, data: Dictionary) -> void:
	for z in data.zones:
		var zone := Zone.new()
		zone.zone_rect = Rect2i(int(z.x), int(z.y), int(z.w), int(z.h))
		zone.owner_team = 0
		parent.add_child(zone)


## map_item objects: pickups (PickupDefs) and decoration (SceneryDefs —
## huts, map objects), rendered as Y-sorted sprites.
static func _spawn_map_item(parent: Node, o: Dictionary, pos: Vector2, planet: String) -> void:
	var id := int(o.id)
	if ZodIds.MAP_PICKUP_IDS.has(id):
		var pickup := Pickup.new()
		pickup.pickup_type = String(ZodIds.MAP_PICKUP_IDS[id])
		pickup.position = pos
		parent.add_child(pickup)
		return
	if id == 1:
		return  # rocks handled with the nav grid
	var info: Dictionary = SceneryDefs.for_id(id, planet)
	if info.is_empty():
		return
	var sprite := Sprite2D.new()
	sprite.name = "Scenery_%d_%d" % [int(o.x), int(o.y)]
	sprite.texture = load(String(info.texture))
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# zod OMapObject::DoRender: clutter draws at NATIVE art size with its
	# bottom edge on the object tile — 2x turned barrels into giant smears
	# over the zone markers
	sprite.position = pos + Vector2(
		sprite.texture.get_size().x - 16, 16 - sprite.texture.get_size().y) * 0.5
	parent.add_child(sprite)


## Robots spawn straight from the scene; vehicles/cannons only when their
## sprite folder exists (ContentDB.has_sprites).
static func _spawn_unit(parent: Node, o: Dictionary, kind: String, pos: Vector2) -> void:
	var type_name := ContentDB.map_unit_name(kind, int(o.id))
	if type_name == "":
		return
	if kind != "robot" and not ContentDB.has_sprites(kind, type_name):
		return
	Spawner.spawn(parent, kind, type_name, int(o.owner), pos)


## Buildings instantiate the script class from their BuildingDefs entry;
## solid ones block both nav grids, bridges clear their span on both.
static func _spawn_building(parent: Node, o: Dictionary, pos: Vector2, planet: String,
		grid: AStarGrid2D, vgrid: AStarGrid2D, w: int, h: int) -> void:
	var id := int(o.id)
	var def := ContentDB.building_def(id)
	if def == null:
		return
	var node: Building2D
	var scene_path := "res://scenes/buildings/%s.tscn" % def.bname
	if ResourceLoader.exists(scene_path):
		node = load(scene_path).instantiate() as Building2D
		node.setup(id, int(o.owner), planet, int(o.get("level", 0)))
	else:
		node = def.behaviour.new()
		node.setup(id, int(o.owner), planet, int(o.get("level", 0)))
	node.position = pos
	node.name = "Building_T%d_%d" % [int(o.owner), id]
	parent.add_child(node)
	if def.bridge_span != Vector2i.ZERO:
		var span: Vector2i = def.bridge_span
		# same MAP ANCHOR CONTRACT as building art: the object tile is the
		# span's TOP-LEFT (zod loc semantics), not its centre
		var lo := Vector2i(int(o.x), int(o.y))
		for bx in span.x:
			for by in span.y:
				var cell := lo + Vector2i(bx, by)
				if grid.region.has_point(cell):
					grid.set_point_solid(cell, false)
				if vgrid.region.has_point(cell):
					vgrid.set_point_solid(cell, false)
				node.bridge_cells.append(cell)  # remembered for blow-up/repair
	else:
		# solid buildings block movement on both grids (def-driven cell
		# patterns from the original engine — see Building2D.footprint_cells)
		node.apply_impassables(grid, vgrid)


## ---------------------------------------------------------------------------
## Scene maps (.tscn under assets/maps_scenes/, generated by
## tools/build_map_resources.gd and hand-editable in the Godot editor).
## Navigation derives from the PAINTED terrain tiles via the tileinfo
## tables, so editing terrain in the editor updates passability and water
## automatically. Everything else (zones, buildings, units) is already in
## the scene and wires itself up on _ready.
## ---------------------------------------------------------------------------

const TILEINFO_DIR := "res://assets/tilesets"


static func load_map_scene(parent: Node, scene_path: String) -> Dictionary:
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("map scene load failed: " + scene_path)
		return {}
	var map: Node2D = packed.instantiate()
	parent.add_child(map)
	var planet: String = str(map.get("planet"))
	var terrain: TileMapLayer = map.get_node_or_null("Terrain")
	if terrain == null:
		push_error("map scene has no Terrain layer: " + scene_path)
		return {}

	# bounds from the painted cells (empty cells outside count as solid)
	var used: Array = terrain.get_used_cells()
	var min_c := Vector2i(1 << 30, 1 << 30)
	var max_c := Vector2i(-(1 << 30), -(1 << 30))
	for cell in used:
		min_c = min_c.min(cell)
		max_c = max_c.max(cell)
	var w := max_c.x - min_c.x + 1
	var h := max_c.y - min_c.y + 1
	var map_rect := Rect2(Vector2(min_c) * TILE, Vector2(w, h) * TILE)

	# tiles array (row-major atlas indexes) for the minimap
	var tiles := PackedInt32Array()
	tiles.resize(w * h)
	var painted := {}
	for cell in used:
		var atlas: Vector2i = terrain.get_cell_atlas_coords(cell)
		var index: int = atlas.y * 20 + atlas.x
		tiles[(cell.y - min_c.y) * w + (cell.x - min_c.x)] = index
		painted[cell] = index

	# nav grids from tileinfo: terrain decides passability and water
	var info: Dictionary = _tileinfo(planet)
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(min_c, Vector2i(w, h))
	grid.cell_size = Vector2(TILE, TILE)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE
	grid.update()
	for y in h:
		for x in w:
			var cell := min_c + Vector2i(x, y)
			if not painted.has(cell) or not bool(info.get(str(painted[cell]), [true, false])[1]):
				grid.set_point_solid(cell, true)

	# rocks block movement (they are plain sprites in the scene)
	for rock in _tree_children(parent, "rocks"):
		grid.set_point_solid(Vector2i((rock.global_position / TILE).floor()), true)

	var vgrid := _build_vehicle_grid(grid,
		{"water": _water_array(planet, painted, min_c, w, h)}, w, h)
	NavWorld.current.nav_grid = grid
	NavWorld.current.vehicle_grid = vgrid
	NavWorld.current.map_rect = map_rect

	# solid building footprints / bridge spans / CPU brains — same rules
	# as the JSON path
	var ai_teams := {}
	for child in map.get_children():
		if child is Building2D:
			var def := ContentDB.building_def(child.building_id)
			if def == null:
				# loud, never silent: an undef'd building means walls with
				# no nav solids — units wedge inside what they path through
				push_error("map scene building '%s' has unknown building_id %d"
					% [child.name, child.building_id])
				continue
			if def.bridge_span != Vector2i.ZERO:
				_clear_bridge(child, def, grid, vgrid)
			else:
				child.apply_impassables(grid, vgrid)
			if def.is_fort and child.team != 0:
				ai_teams[child.team] = true
	_init_zone_owners(parent)
	# every fort team gets a ledger entry (income + spend work for all)
	for t in ai_teams:
		MatchState.grant_ledger(t)
	for t in ai_teams:
		if t != MatchState.player_team:
			var ai := CpuAi.new(t)
			ai.name = "CpuAi_T%d" % t
			parent.add_child(ai)

	return {
		"width": w, "height": h, "terrain": planet, "tiles": tiles,
		"zones": MatchState.zones.size(),
		"objects": map.get_child_count(),
	}


## Original ZServer::InitZones: every FORT claims the zone it stands in
## for its owner, and every other building in that zone follows the
## fort's team — both sides start with their home territory (income and
## working home factories) instead of a fully neutral map.
static func _init_zone_owners(root: Node) -> void:
	var buildings: Array = []
	for b in root.get_tree().get_nodes_in_group("all_buildings"):
		if root.is_ancestor_of(b) and b is Building2D and b.alive:
			buildings.append(b)
	for fort in buildings:
		if not fort.is_fort or fort.team == 0:
			continue
		for z in MatchState.zones:
			if not z.world_rect().has_point(fort.visual_center()):
				continue
			z.set_owner_team(fort.team)
			for b in buildings:
				if b != fort and not b.is_bridge() \
						and z.world_rect().has_point(b.visual_center()):
					b.owner_team = fort.team
					b.team = fort.team
			break


static func _clear_bridge(bridge: Building2D, def: BuildingDef,
		grid: AStarGrid2D, vgrid: AStarGrid2D) -> void:
	var tile := Vector2i(((bridge.global_position - Vector2(8, 8)) / TILE).floor())
	var span: Vector2i = def.bridge_span
	# object tile = span TOP-LEFT (zod loc semantics — same as the JSON path)
	var lo := tile
	for bx in span.x:
		for by in span.y:
			var cell := lo + Vector2i(bx, by)
			if grid.region.has_point(cell):
				grid.set_point_solid(cell, false)
			if vgrid.region.has_point(cell):
				vgrid.set_point_solid(cell, false)
			bridge.bridge_cells.append(cell)


static func _tileinfo(planet: String) -> Dictionary:
	var path := "%s/tileinfo_%s.json" % [TILEINFO_DIR, planet]
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Water mask in the JSON-loader's array format, derived from tileinfo.
static func _water_array(planet: String, painted: Dictionary,
		min_c: Vector2i, w: int, h: int) -> Array:
	var info := _tileinfo(planet)
	var out := []
	out.resize(w * h)
	for i in w * h:
		out[i] = 0
	for cell in painted:
		var entry: Array = info.get(str(painted[cell]), [true, true])
		if bool(entry[0]):
			out[(cell.y - min_c.y) * w + (cell.x - min_c.x)] = 1
	return out


## All nodes in a group, searched from the match root (scene maps nest
## one level deeper than JSON-spawned content).
static func _tree_children(root: Node, group: String) -> Array:
	var out := []
	for node in root.get_tree().get_nodes_in_group(group):
		if root.is_ancestor_of(node):
			out.append(node)
	return out
