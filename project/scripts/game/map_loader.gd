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
	MatchState.current.map_root = parent
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
	# every wall is stamped by now: cost the ring around them so routes
	# keep their distance from buildings (NavWorld.paint_wall_margins)
	NavWorld.current.paint_wall_margins()
	_init_zone_owners(parent)
	_grant_starting_squads(parent)
	# every fort team gets a ledger entry (income + spend work for all)
	for t in ai_teams:
		MatchState.current.grant_ledger(t)
	for t in ai_teams:
		# seats held by HUMAN players act over the network — no stand-in.
		# And only ONE peer may think for the CPU seats (the host), or
		# every peer runs a separate brain and the sims fork.
		if t != MatchState.current.player_team and not Net.human_teams().has(t) \
				and Net.owns_ai():
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
	var animator := _terrain_animator(parent, tilemap, planet)
	for y in h:
		for x in w:
			var index: int = data.tiles[y * w + x]  # row-major (GetTile: y=index/width)
			tilemap.set_cell(Vector2i(x, y), 0, Vector2i(index % 20, index / 20))
			if animator != null:
				animator.register(Vector2i(x, y), index)


static func _build_nav_grid(data: Dictionary, w: int, h: int) -> AStarGrid2D:
	var grid := NavWorld.make_grid(Rect2i(0, 0, w, h))
	# terrain passability: the stored mask when the map ships one, the
	# per-planet tileinfo tables otherwise. The zod multiplayer set
	# (bb_orig/p03/p04/p08) ships NEITHER array, and the old code read a
	# missing mask as "everything walkable" — every unit in skirmish
	# strolled across cliffs and rivers as open ground.
	var info := _tileinfo(String(data.get("terrain", "")))
	var passable: Array = data.passable if _mask_ok(data.passable, w, h) \
			else []
	for y in h:
		for x in w:
			var i := y * w + x
			var walkable := true
			if not passable.is_empty():
				walkable = bool(passable[i])
			elif not info.is_empty():
				walkable = bool(info.get(str(int(data.tiles[i])), [true, true])[1])
			if not walkable:
				grid.set_point_solid(Vector2i(x, y), true)
	NavWorld.current.nav_grid = grid
	NavWorld.current.map_rect = Rect2(0.0, 0.0, float(w) * TILE, float(h) * TILE)
	return grid


## A stored mask only counts when it covers every cell (a partial or
## absent array must fall back to derivation, not to "no terrain").
static func _mask_ok(mask, w: int, h: int) -> bool:
	return mask != null and (mask as Array).size() == w * h


## Rock scenery: CLIFF COLUMNS, a faithful port of zod's ORock. The map
## stores one object per 16px rock column; each renders up to three
## tiles — a TOP piece picked by the four-neighbour rule over the whole
## rock list (16 shapes: centre, corners, edges, vertical/horizontal
## runs), then up to two UNDER pieces wherever no rock continues below,
## plus a cast SHADOW drawn one tile EAST as a ground prerender (under
## every unit, like the original blitting shadows into the map). Only
## the BASE tile is impassable: a cliff overhangs, units walk behind the
## face and the Y-sort covers them. Blasting a column leaves a permanent
## rubble stamp on its base tile (zod PermStamp of rock_destroyed).
##
## The old assembly inferred a piece per CELL from left/right/depth —
## there is no such rule in the original, and it showed: blobby pillars
## with no shadows and wrong faces.
##
## Piece atlas coords are zod ORock::Init, verbatim.
const ROCK_PIECES := {
	"center": Vector2i(1, 1),
	"up_left": Vector2i(0, 0), "up_right": Vector2i(2, 0),
	"down_right": Vector2i(2, 2), "down_left": Vector2i(0, 2),
	"up": Vector2i(1, 0), "down": Vector2i(1, 2),
	"right": Vector2i(2, 1), "left": Vector2i(0, 1),
	"vert_up": Vector2i(3, 0), "vert_mid": Vector2i(3, 1),
	"vert_down": Vector2i(3, 2),
	"horz_left": Vector2i(0, 5), "horz_mid": Vector2i(1, 5),
	"horz_right": Vector2i(2, 5),
	"left_mid": Vector2i(0, 3), "left_bottom": Vector2i(0, 4),
	"mid_mid": Vector2i(1, 3), "mid_bottom": Vector2i(1, 4),
	"right_mid": Vector2i(2, 3), "right_bottom": Vector2i(2, 4),
	"single_mid": Vector2i(3, 3), "single_bottom": Vector2i(3, 4),
	"up_shadow": Vector2i(4, 2), "mid_shadow": Vector2i(4, 3),
	"bottom_shadow": Vector2i(4, 4),
	"mid_mid_shadow": Vector2i(5, 0), "mid_bottom_shadow": Vector2i(5, 1),
	"right_mid_shadow": Vector2i(4, 0), "right_bottom_shadow": Vector2i(4, 1),
}


static func _build_rocks(parent: Node, data: Dictionary, planet: String, grid: AStarGrid2D) -> void:
	var rock_cells := {}
	for o in data.objects:
		if String(o.type) == "map_item" and int(o.id) == 1:
			rock_cells[Vector2i(int(o.x), int(o.y))] = true
	if rock_cells.is_empty():
		return
	var sheet: Texture2D = load("res://assets/z/planets/rocks_%s.png" % planet)
	var map_w: int = int(data.width)
	var map_h: int = int(data.height)
	var ground := _ground_decal_layer(parent)
	for cell: Vector2i in rock_cells:
		var built := _rock_column_pieces(cell, rock_cells, map_w, map_h)
		var rock := Node2D.new()
		rock.name = "Rock_%d_%d" % [cell.x, cell.y]
		# the node anchors at the column's TOP edge — zod sorts objects by
		# loc.y, so a unit on the plateau draws in front of the rim and a
		# unit behind the cliff is covered by the face
		rock.position = Vector2(cell) * TILE
		for piece: Vector2i in built.body:
			rock.add_child(_rock_sprite(sheet, piece,
				Vector2(0, rock.get_child_count() * TILE)))
		parent.add_child(rock)
		rock.add_to_group(Groups.ROCKS)
		# ONLY the base blocks movement (ORock::SetMapImpassables)
		var base := cell + Vector2i(0, 2)
		if grid.region.has_point(base):
			grid.set_point_solid(base, true)
		rock.set_meta("base_cell", base)
		for i in built.shadows.size():
			ground.add_child(_rock_sprite(sheet, built.shadows[i],
				Vector2(cell.x * TILE + TILE, cell.y * TILE + i * TILE)))


static func _rock_sprite(sheet: Texture2D, piece: Vector2i, offset: Vector2) -> Sprite2D:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(Vector2(piece) * TILE, Vector2(TILE, TILE))
	var sprite := Sprite2D.new()
	sprite.texture = atlas
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = false
	sprite.position = offset
	return sprite


## The GroundDecals layer: z-index -1 under every unit and building.
static func _ground_decal_layer(parent: Node) -> Node2D:
	var layer := parent.get_node_or_null("GroundDecals") as Node2D
	if layer == null:
		layer = Node2D.new()
		layer.name = "GroundDecals"
		layer.z_index = -1
		parent.add_child(layer)
	return layer


## ORock::SetupRockRender, line for line. Returns the column's BODY
## pieces (top, optional mid-under, optional bottom-under) and its EAST
## SHADOW pieces, both as atlas cells; a NULL under piece in zod is
## simply absent here (the next column's top renders there instead).
static func _rock_column_pieces(cell: Vector2i, rock_cells: Dictionary,
		map_w: int, map_h: int) -> Dictionary:
	var tx := cell.x
	var ty := cell.y
	var has := func(c: Vector2i) -> bool: return rock_cells.has(c)
	var r: bool = tx == map_w - 1 or has.call(cell + Vector2i(1, 0))
	var l: bool = tx == 0 or has.call(cell + Vector2i(-1, 0))
	var up: bool = ty == 0 or has.call(cell + Vector2i(0, -1))
	var dn: bool = ty == map_h - 1 or has.call(cell + Vector2i(0, 1))
	var dl: bool = tx != 0 and ty != map_h - 1 and has.call(cell + Vector2i(-1, 1))
	var ddn: bool = ty >= map_h - 2 or has.call(cell + Vector2i(0, 2))
	var uup: bool = ty < 2 or has.call(cell + Vector2i(0, -2))
	var uur: bool = ty >= 2 and tx < map_w - 1 and has.call(cell + Vector2i(1, -2))
	var ur: bool = ty >= 1 and tx < map_w - 1 and has.call(cell + Vector2i(1, -1))
	var dr: bool = ty < map_h - 1 and tx < map_w - 1 and has.call(cell + Vector2i(1, 1))
	var ddr: bool = ty < map_h - 2 and tx < map_w - 1 and has.call(cell + Vector2i(1, 2))

	# the top piece: the exact if-chain from SetupRockRender
	var top := "vert_down"
	if r and l and up and dn: top = "center"
	elif r and not l and not up and dn: top = "up_left"
	elif not r and l and not up and dn: top = "up_right"
	elif not r and l and up and not dn: top = "down_right"
	elif r and not l and up and not dn: top = "down_left"
	elif r and l and not up and dn: top = "up"
	elif r and l and up and not dn: top = "down"
	elif not r and l and up and dn: top = "right"
	elif r and not l and up and dn: top = "left"
	elif not r and not l and not up and dn: top = "vert_up"
	elif not r and not l and up and dn: top = "vert_mid"
	elif not r and not l and up and not dn: top = "vert_down"
	elif r and not l and not up and not dn: top = "horz_left"
	elif r and l and not up and not dn: top = "horz_mid"
	elif not r and l and not up and not dn: top = "horz_right"

	var body: Array = [ROCK_PIECES[top]]
	# the mid under: suppressed when rock continues below; shadow variants
	# when a rock sits down-left (it casts INTO this tile)
	if ty + 1 < map_h:
		if dn:
			pass
		elif dl:
			body.append(ROCK_PIECES["mid_mid_shadow" if r else "right_mid_shadow"])
		elif r and l: body.append(ROCK_PIECES["mid_mid"])
		elif r: body.append(ROCK_PIECES["left_mid"])
		elif l: body.append(ROCK_PIECES["right_mid"])
		else: body.append(ROCK_PIECES["single_mid"])
	# the bottom under
	if ty + 2 < map_h:
		if ddn or dn:
			pass
		elif dl:
			body.append(ROCK_PIECES["mid_bottom_shadow" if r else "right_bottom_shadow"])
		elif r and l: body.append(ROCK_PIECES["mid_bottom"])
		elif r: body.append(ROCK_PIECES["left_bottom"])
		elif l: body.append(ROCK_PIECES["right_bottom"])
		else: body.append(ROCK_PIECES["single_bottom"])

	# extra shadows: cast one tile east of the column
	var shadows: Array = []
	if tx < map_w - 1:
		if not (uur or ur or r):
			if up and not uup:
				shadows.append(ROCK_PIECES["up_shadow"])
			elif up or uup:
				shadows.append(ROCK_PIECES["mid_shadow"])
		if not dn and not (ur or r or dr):
			shadows.append(ROCK_PIECES["up_shadow" if not up else "mid_shadow"])
		if not dn and not ddn and not (r or dr or ddr):
			shadows.append(ROCK_PIECES["bottom_shadow"])
	return {"body": body, "shadows": shadows}


## Vehicle grid: same as robots but water is impassable (zod PF_WATER).
## Built after rocks so rock cells block wheels too. The water mask is
## indexed in LOCAL row-major order while cell ids are absolute — scene
## maps whose painted area does not start at (0,0) need the region
## origin added back (the old loop used the local index as the cell id,
## which silently shifted every water cell on such a map).
static func _build_vehicle_grid(grid: AStarGrid2D, data: Dictionary, w: int, h: int) -> AStarGrid2D:
	var vgrid := NavWorld.make_grid(grid.region)
	var origin: Vector2i = grid.region.position
	# water: stored mask, else the tileinfo tables — same fallback as the
	# robot grid above. Without it the skirmish set had NO water at all
	# and tanks forded every river.
	var info := _tileinfo(String(data.get("terrain", "")))
	var water: Array = data.water if _mask_ok(data.water, w, h) else []
	var tiles: Array = data.get("tiles", [])
	for y in h:
		for x in w:
			var i := y * w + x
			var cell := origin + Vector2i(x, y)
			var is_water := false
			if not water.is_empty():
				is_water = bool(water[i])
			elif not info.is_empty() and i < tiles.size():
				is_water = bool(info.get(str(int(tiles[i])), [true, true])[0])
			if grid.is_point_solid(cell) or is_water:
				vgrid.set_point_solid(cell, true)
	NavWorld.current.vehicle_grid = vgrid
	return vgrid


## map_item id 0 is the ZONE FLAG marker, not scenery: the tile the
## designer put the flag on, plus the zone's STARTING OWNER in its
## `owner` byte. SceneryDefs has no art for id 0, so the loader dropped
## all of them — verified across the shipped maps: 956 markers, exactly
## one inside each of the 956 non-fort zones (the other 162 zones hold a
## fort, which flies the territory's flag itself), and 330 of them carry
## a non-zero owner. Dropping them meant every flag stood at a derived
## centre spot and every map opened fully neutral.
const ZONE_FLAG_ID := 0


static func _apply_zone_flag(o: Dictionary) -> void:
	var cell := Vector2i(int(o.x), int(o.y))
	for z in MatchState.current.zones:
		if not z.zone_rect.has_point(cell):
			continue
		z.flag_tile = cell
		var owner := int(o.get("owner", 0))
		if owner != 0:
			z.set_initial_owner(owner)
		return


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
	if id == ZONE_FLAG_ID:
		_apply_zone_flag(o)
		return
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
	# the RETAIL campaign gives every bridge its own span (4 across,
	# 3-12 long); set it before _ready so the art matches the span
	if int(o.get("span_w", 0)) > 0 and int(o.get("span_h", 0)) > 0:
		node.bridge_span_override = Vector2i(int(o.span_w), int(o.span_h))
	parent.add_child(node)
	if def.bridge_span != Vector2i.ZERO:
		var span: Vector2i = node.bridge_span()
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
	var animator := _terrain_animator(parent, terrain, planet)
	for cell in used:
		var atlas: Vector2i = terrain.get_cell_atlas_coords(cell)
		var index: int = atlas.y * 20 + atlas.x
		tiles[(cell.y - min_c.y) * w + (cell.x - min_c.x)] = index
		painted[cell] = index
		if animator != null:
			animator.register(cell, index)

	# nav grids from tileinfo: terrain decides passability and water
	var info: Dictionary = _tileinfo(planet)
	var grid := NavWorld.make_grid(Rect2i(min_c, Vector2i(w, h)))
	for y in h:
		for x in w:
			var cell := min_c + Vector2i(x, y)
			if not painted.has(cell) or not bool(info.get(str(painted[cell]), [true, false])[1]):
				grid.set_point_solid(cell, true)

	# rocks block movement (they are plain sprites in the scene)
	for rock in _tree_children(parent, "rocks"):
		var rock_cell := NavWorld.cell_at(rock.global_position)
		if grid.region.has_point(rock_cell):
			grid.set_point_solid(rock_cell, true)

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
	# every wall is stamped by now: cost the ring around them so routes
	# keep their distance from buildings (NavWorld.paint_wall_margins)
	NavWorld.current.paint_wall_margins()
	_init_zone_owners(parent)
	_grant_starting_squads(parent)
	# every fort team gets a ledger entry (income + spend work for all)
	for t in ai_teams:
		MatchState.current.grant_ledger(t)
	for t in ai_teams:
		# seats held by HUMAN players act over the network — no stand-in.
		# And only ONE peer may think for the CPU seats (the host), or
		# every peer runs a separate brain and the sims fork.
		if t != MatchState.current.player_team and not Net.human_teams().has(t) \
				and Net.owns_ai():
			var ai := CpuAi.new(t)
			ai.name = "CpuAi_T%d" % t
			parent.add_child(ai)

	return {
		"width": w, "height": h, "terrain": planet, "tiles": tiles,
		"zones": MatchState.current.zones.size(),
		"objects": map.get_child_count(),
	}


## A fort team that owns NO units gets a small squad at its fort.
##
## The retail campaign levels keep their starting armies in
## `preset1.wal` / `preset2.wal`, and neither file ships in the release —
## so a converted campaign map has forts, factories and derelict
## hardware, but nobody standing on it. That is not just thin: the
## original no-units rule destroys a team's forts the moment its last
## unit dies, so the first lost robot would end the mission. Teams that
## bring their own roster (every zod map) are left untouched.
static func _grant_starting_squads(parent: Node) -> void:
	var count: int = ContentDB.rules.starting_squad
	if count <= 0 or UnitRegistry.current == null:
		return
	var forts := {}  # team -> a fort of theirs
	for b in BuildingRegistry.all():
		if b is Building2D and b.alive and b.is_fort and b.team != 0 \
				and not forts.has(b.team):
			forts[b.team] = b
	for team in forts:
		if not UnitRegistry.current.alive_of_team(team).is_empty():
			continue
		var anchor: Vector2 = (forts[team] as Building2D).world_footprint().get_center()
		for i in count:
			var spot := NavWorld.current.find_free_spot(
				anchor + Vector2(0, 96.0) + Vector2(24.0 * (i - count * 0.5), 0.0),
				"robot")
			if spot == Vector2.INF:
				continue
			Spawner.spawn(parent, "robot", "grunt", team, spot)


## Original ZServer::InitZones: every FORT claims the zone it stands in
## for its owner, and every other building in that zone follows the
## fort's team — both sides start with their home territory (income and
## working home factories) instead of a fully neutral map.
static func _init_zone_owners(root: Node) -> void:
	var buildings: Array = []
	for b in root.get_tree().get_nodes_in_group(Groups.ALL_BUILDINGS):
		if root.is_ancestor_of(b) and b is Building2D and b.alive:
			buildings.append(b)
	for fort in buildings:
		if not fort.is_fort or fort.team == 0:
			continue
		for z in MatchState.current.zones:
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
	var span: Vector2i = bridge.bridge_span()
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


## Animated terrain for a planet that has any: water/lava/grate tiles
## step along the effect rings in the tileinfo table (TerrainAnimator).
## Returns null for a planet with no animated tiles (jungle) so the
## caller's per-cell registration costs nothing.
static func _terrain_animator(parent: Node, layer: TileMapLayer,
		planet: String) -> TerrainAnimator:
	var anim := TerrainAnimator.new()
	anim.name = "TerrainAnimator"
	anim.setup(layer, _tileinfo(planet))
	if not anim.has_effects():
		anim.free()
		return null
	parent.add_child(anim)
	return anim


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
