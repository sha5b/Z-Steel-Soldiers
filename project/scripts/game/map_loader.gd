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


static func load_map(parent: Node, json_path: String) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if data == null:
		push_error("map load failed: " + json_path)
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
		if String(o.type) == "building" and ContentDB.building_def(int(o.id)).get("fort", false) \
				and int(o.owner) != 0:
			ai_teams[int(o.owner)] = true
	for t in ai_teams:
		if t != GameState.player_team:
			var ai := CpuAi.new(t)
			ai.name = "CpuAi_T%d" % t
			parent.add_child(ai)
	return data


static func _build_terrain(parent: Node, data: Dictionary, planet: String, w: int, h: int) -> void:
	var tilemap := TileMapLayer.new()
	tilemap.name = "Terrain"
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
	GameState.nav_grid = grid
	GameState.map_rect = Rect2(0.0, 0.0, float(w) * TILE, float(h) * TILE)
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
	GameState.vehicle_grid = vgrid
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
	if PickupDefs.MAP_IDS.has(id):
		var pickup := Pickup.new()
		pickup.pickup_type = String(PickupDefs.MAP_IDS[id])
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
	sprite.scale = Vector2(2, 2)
	sprite.position = pos
	parent.add_child(sprite)


## Robots spawn straight from the scene; vehicles/cannons only when their
## sprite folder exists (ContentDB.has_sprites).
static func _spawn_unit(parent: Node, o: Dictionary, kind: String, pos: Vector2) -> void:
	var type_name := ContentDB.map_unit_name(kind, int(o.id))
	if type_name == "":
		return
	if kind == "robot":
		var unit: Node = load("res://scenes/unit.tscn").instantiate()
		unit.unit_name = type_name
		unit.team = int(o.owner)
		unit.position = pos
		parent.add_child(unit)
	elif ContentDB.has_sprites(kind, type_name):
		var scene_path := "res://scenes/vehicle.tscn"
		var veh: Node = load(scene_path).instantiate()
		veh.setup_vehicle(kind, type_name, int(o.owner))
		veh.position = pos
		parent.add_child(veh)


## Buildings instantiate the script class from their BuildingDefs entry;
## solid ones block both nav grids, bridges clear their span on both.
static func _spawn_building(parent: Node, o: Dictionary, pos: Vector2, planet: String,
		grid: AStarGrid2D, vgrid: AStarGrid2D, w: int, h: int) -> void:
	var id := int(o.id)
	var def: Dictionary = ContentDB.building_def(id)
	if def.is_empty():
		return
	var node: Building2D = def.script.new()
	node.setup(id, int(o.owner), planet)
	node.position = pos
	node.name = "Building_T%d_%d" % [int(o.owner), id]
	parent.add_child(node)
	if def.get("bridge_span", Vector2i.ZERO) != Vector2i.ZERO:
		var span: Vector2i = def.bridge_span
		var lo := Vector2i(int(o.x) - span.x / 2, int(o.y) - span.y / 2)
		for bx in span.x:
			for by in span.y:
				var cell := lo + Vector2i(bx, by)
				if grid.region.has_point(cell):
					grid.set_point_solid(cell, false)
				if vgrid.region.has_point(cell):
					vgrid.set_point_solid(cell, false)
	elif def.get("solid", false):
		# solid buildings block movement on both grids — vehicles otherwise
		# drive straight over fort/factory sprites
		var fp := node.world_footprint()
		var lo := Vector2i((fp.position / TILE).floor())
		var hi := Vector2i(((fp.position + fp.size) / TILE).ceil())
		for bx in range(maxi(lo.x, 0), mini(hi.x, w)):
			for by in range(maxi(lo.y, 0), mini(hi.y, h)):
				var cell := Vector2i(bx, by)
				grid.set_point_solid(cell, true)
				vgrid.set_point_solid(cell, true)
