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
	for x in w:
		for y in h:
			var index: int = data.tiles[x * h + y]  # column-major
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
			"building":
				var b := ColorRect.new()
				var bname: String = BUILDING_COLORS.keys()[int(o.id)] if int(o.id) < BUILDING_COLORS.size() else "radar"
				var bsize: Vector2i = BUILDING_SIZES.get(bname, Vector2i(2, 2))
				b.color = BUILDING_COLORS.get(bname, Color(0.5, 0.5, 0.5))
				b.position = pos - Vector2(bsize) * TILE * 0.5
				b.size = Vector2(bsize) * TILE
				b.mouse_filter = Control.MOUSE_FILTER_IGNORE
				b.name = "Building_%s" % bname
				parent.add_child(b)
	return data
