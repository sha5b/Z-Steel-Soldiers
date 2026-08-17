class_name MapLoader
extends Node
## Builds a Zod-format map (JSON from tools/zod/map_to_json.py):
## TileMapLayer terrain from the planet tileset, zones, robots, buildings.

const TILE := 16
const PLANET_TILESETS := {
	"desert": "res://assets/z/planets/desert.png",
	"volcanic": "res://assets/z/planets/volcanic.png",
	"arctic": "res://assets/z/planets/arctic.png",
	"city": "res://assets/z/planets/city.png",
	"jungle": "res://assets/z/planets/jungle.png",
}
const BUILDING_COLORS := {
	"fort_front": Color(0.55, 0.45, 0.3), "fort_back": Color(0.55, 0.45, 0.3),
	"radar": Color(0.3, 0.5, 0.55), "repair": Color(0.4, 0.55, 0.35),
	"robot_factory": Color(0.6, 0.6, 0.35), "vehicle_factory": Color(0.6, 0.5, 0.3),
}
const BUILDING_SIZES := {
	"fort_front": Vector2i(5, 4), "fort_back": Vector2i(5, 4), "radar": Vector2i(2, 2),
	"repair": Vector2i(2, 2), "robot_factory": Vector2i(3, 3), "vehicle_factory": Vector2i(4, 3),
}


static func load_map(parent: Node, json_path: String) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if data == null:
		push_error("map load failed: " + json_path)
		return {}

	# terrain
	var tilemap := TileMapLayer.new()
	tilemap.name = "Terrain"
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)
	var source := TileSetAtlasSource.new()
	source.texture = load(PLANET_TILESETS.get(String(data.terrain), PLANET_TILESETS.desert))
	source.texture_region_size = Vector2i(TILE, TILE)
	for index in 20 * 24:
		source.create_tile(Vector2i(index % 20, index / 20))
	tileset.add_source(source)
	tilemap.tile_set = tileset
	parent.add_child(tilemap)
	var w := int(data.width)
	var h := int(data.height)
	for y in h:
		for x in w:
			var index: int = data.tiles[y * w + x]  # row-major (GetTile: y=index/width)
			tilemap.set_cell(Vector2i(x, y), 0, Vector2i(index % 20, index / 20))

	# navigation grid from tileinfo passability + building footprints
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

	# rock scenery layer: one tile per rock item from the planet's rock
	# sheet (sheet layout from zod orock.cpp: 6x6 grid of 16px pieces;
	# (3,3) is the standalone rock, (1,1) the mid-cluster top)
	var rock_cells := {}
	for o in data.objects:
		if String(o.type) == "map_item" and int(o.id) == 1:
			rock_cells[Vector2i(int(o.x), int(o.y))] = true
	if not rock_cells.is_empty():
		var rocks_layer := TileMapLayer.new()
		rocks_layer.name = "Rocks"
		rocks_layer.z_index = 1
		var rock_set := TileSet.new()
		rock_set.tile_size = Vector2i(TILE, TILE)
		var rock_src := TileSetAtlasSource.new()
		rock_src.texture = load("res://assets/z/planets/rocks_%s.png" % String(data.terrain))
		rock_src.texture_region_size = Vector2i(TILE, TILE)
		for index in 36:
			rock_src.create_tile(Vector2i(index % 6, index / 6))
		rock_set.add_source(rock_src)
		rocks_layer.tile_set = rock_set
		parent.add_child(rocks_layer)
		for cell in rock_cells:
			var alone := true
			for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if rock_cells.has(cell + n):
					alone = false
					break
			rocks_layer.set_cell(cell, 0, Vector2i(3, 3) if alone else Vector2i(1, 1))
			if grid != null:
				grid.set_point_solid(cell, true)

	# zones
	for z in data.zones:
		var zone := Zone.new()
		zone.zone_rect = Rect2i(int(z.x), int(z.y), int(z.w), int(z.h))
		zone.owner_team = 0
		parent.add_child(zone)

	# objects
	for o in data.objects:
		var pos := Vector2(int(o.x) * TILE + 8, int(o.y) * TILE + 8)
		match String(o.type):
			"robot":
				var rnames := ["grunt", "psycho", "sniper", "tough", "pyro", "laser"]
				var rtype: String = rnames[int(o.id)] if int(o.id) < rnames.size() else "grunt"
				var unit: Node = load("res://scenes/unit.tscn").instantiate()
				unit.unit_name = rtype
				unit.team = int(o.owner)
				unit.position = pos
				parent.add_child(unit)
			"vehicle":
				var vnames := ["jeep", "light", "medium", "heavy", "apc", "missile_launcher", "crane"]
				var vtype: String = vnames[int(o.id)] if int(o.id) < vnames.size() else "jeep"
				if Vehicle2D.dir_exists("vehicle", vtype):
					var veh: Node = load("res://scenes/vehicle.tscn").instantiate()
					veh.setup_vehicle("vehicle", vtype, int(o.owner))
					veh.position = pos
					parent.add_child(veh)
			"cannon":
				var cnames := ["gatling", "gun", "howitzer", "missile_cannon"]
				var ctype: String = cnames[int(o.id)] if int(o.id) < cnames.size() else "gatling"
				if Vehicle2D.dir_exists("cannon", ctype):
					var cannon: Node = load("res://scenes/vehicle.tscn").instantiate()
					cannon.setup_vehicle("cannon", ctype, int(o.owner))
					cannon.position = pos
					parent.add_child(cannon)
			"building":
				var id := int(o.id)
				var planet := String(data.terrain)
				var node: Building2D
				if id == 0 or id == 1:  # fort_front / fort_back
					var fort := FortBuilding.new()
					fort.setup(id, int(o.owner), planet)
					node = fort
				elif id == 6 or id == 7:  # bridge_vert / bridge_horz
					var bridge := Building2D.new()
					bridge.setup(id, 0, planet)
					node = bridge
					# bridges are walkable across water
					var span := Vector2i(2, 8) if id == 6 else Vector2i(8, 2)
					var lo := Vector2i(int(o.x) - span.x / 2, int(o.y) - span.y / 2)
					for bx in span.x:
						for by in span.y:
							var cell := lo + Vector2i(bx, by)
							if grid != null and grid.region.has_point(cell):
								grid.set_point_solid(cell, false)
				elif id == 4:  # robot_factory
					var f := RobotFactory.new()
					f.setup(id, int(o.owner), planet)
					node = f
				elif id == 5:  # vehicle_factory
					var vf := VehicleFactory.new()
					vf.setup(id, int(o.owner), planet)
					node = vf
				else:
					node = Building2D.new()
					node.setup(id, int(o.owner), planet)
				node.position = pos
				node.name = "Building_T%d_%d" % [int(o.owner), id]
				parent.add_child(node)
				if node is FortBuilding:
					# forts block movement
					var fp := node.world_footprint()
					var lo := Vector2i((fp.position / TILE).floor())
					var hi := Vector2i(((fp.position + fp.size) / TILE).ceil())
					for bx in range(maxi(lo.x, 0), mini(hi.x, w)):
						for by in range(maxi(lo.y, 0), mini(hi.y, h)):
							grid.set_point_solid(Vector2i(bx, by), true)
	# one CPU brain per non-player team that owns a fort
	var ai_teams := {}
	for o in data.objects:
		if String(o.type) == "building" and int(o.id) in [0, 1] and int(o.owner) != 0:
			ai_teams[int(o.owner)] = true
	for t in ai_teams:
		if t != GameState.player_team:
			var ai := CpuAi.new(t)
			ai.name = "CpuAi_T%d" % t
			parent.add_child(ai)
	return data
