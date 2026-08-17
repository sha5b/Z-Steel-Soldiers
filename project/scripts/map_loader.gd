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
				var unit: Node = load("res://scenes/unit.tscn").instantiate()
				unit.unit_name = ["grunt", "psycho", "sniper", "tough", "pyro", "laser"][int(o.id)]
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
				elif id == 4:  # robot_factory
					var f := RobotFactory.new()
					f.setup(id, int(o.owner), planet)
					node = f
				else:
					node = Building2D.new()
					node.setup(id, int(o.owner), planet)
				node.position = pos
				node.name = "Building_T%d_%d" % [int(o.owner), id]
				parent.add_child(node)
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
