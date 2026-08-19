class_name MapPreview
extends Object
## Real map thumbnails for menus AND the in-game minimap base: one pixel
## per tile, sampled from the planet tile sheet — the same art the match
## itself renders, so the preview IS the map (not a generic planet
## picture). Each tile averages its centre + four EDGE midpoints, because
## Z's roads run along tile borders — a centre-only sample makes road
## tiles read as bare ground (the 'looks like just a tilemap' bug). Menu
## previews then stamp every building's real footprint in its team
## colour, so forts, factories, radars and bridges read at a glance.

const TILE := 16
const SHEET_COLS := 20  # planet sheets are 20x24 cells of 16px art
const FALLBACK_GROUND := Color(0.16, 0.20, 0.13)
const NEUTRAL_MARK := Color(0.82, 0.82, 0.82)

static var _cache := {}   # map_name -> ImageTexture
static var _sheets := {}  # planet -> Image (shared, read-only — never mutate)


static func texture(map_name: String) -> ImageTexture:
	if _cache.has(map_name):
		return _cache[map_name]
	var out: ImageTexture = null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/maps/%s.json" % map_name))
	if parsed is Dictionary and can_render(parsed):
		var img := base_image(parsed)
		for o in parsed.objects:
			if String(o.get("type", "")) != "building":
				continue
			_mark_building(img, o)
		out = ImageTexture.create_from_image(img)
	_cache[map_name] = out
	return out


## True when the map data carries a tiles array we can sample.
static func can_render(data: Dictionary) -> bool:
	var w := int(data.width)
	var h := int(data.height)
	return w > 0 and h > 0 and data.has("tiles") \
			and (data.tiles as Array).size() >= w * h


## Terrain image, one pixel per tile in the planet sheet's own colours
## (water tiles are blue because the SHEET tiles are). Falls back to a
## flat ground fill when there is nothing to sample.
static func base_image(data: Dictionary) -> Image:
	var w := int(data.width)
	var h := int(data.height)
	var img := Image.create(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGBA8)
	var sheet := _sheet(String(data.get("terrain", "desert")))
	if sheet == null or not can_render(data):
		img.fill(FALLBACK_GROUND)
		return img
	# centre + the four edge midpoints: road art lives on the borders
	var probes := PackedVector2Array([Vector2(8, 8), Vector2(8, 0),
		Vector2(8, 15), Vector2(0, 8), Vector2(15, 8)])
	for i in w * h:
		var index: int = data.tiles[i]
		var base := Vector2i((index % SHEET_COLS) * TILE, (index / SHEET_COLS) * TILE)
		var c := Color(0, 0, 0)
		for p in probes:
			c += sheet.get_pixel(base.x + int(p.x), base.y + int(p.y))
		c /= probes.size()
		img.set_pixel(i % w, i / w, c)
	return img


## get_image() hands out its cached instance — keep it read-only.
static func _sheet(planet: String) -> Image:
	if _sheets.has(planet):
		return _sheets[planet]
	var path: String = MapLoader.PLANET_TILESETS.get(planet, MapLoader.PLANET_TILESETS.desert)
	var img: Image = null
	if ResourceLoader.exists(String(path)):
		img = (load(String(path)) as Texture2D).get_image()
	_sheets[planet] = img
	return img


## A building's footprint: the def's solid-tiles rect when it has one,
## else the object's 2x2 area. Owned buildings stamp in their team's
## minimap colour, neutral ones in light grey.
static func _mark_building(img: Image, o: Dictionary) -> void:
	var owner := int(o.get("owner", 0))
	var cell := Vector2i(int(o.x), int(o.y))
	var size := Vector2i(2, 2)
	var def := ContentDB.building_def(int(o.get("id", -1)))
	if def != null and def.solid_tiles.size.x > 0 and def.solid_tiles.size.y > 0:
		size = def.solid_tiles.size
		cell += def.solid_tiles.position
	elif def != null and def.bridge_span != Vector2i.ZERO:
		size = def.bridge_span
	_fill_rect(img, cell, size,
		Teams.minimap_color(owner) if owner != 0 else NEUTRAL_MARK)
	# forts get a bright core so start positions pop
	if def != null and def.is_fort and owner != 0:
		_fill_rect(img, cell + Vector2i.ONE * maxi(size.x / 4, 1),
			Vector2i.ONE * maxi(mini(size.x, size.y) / 2, 1), Color.WHITE)


static func _fill_rect(img: Image, cell: Vector2i, size: Vector2i, color: Color) -> void:
	for y in size.y:
		for x in size.x:
			var p := cell + Vector2i(x, y)
			if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
				img.set_pixel(p.x, p.y, color)
