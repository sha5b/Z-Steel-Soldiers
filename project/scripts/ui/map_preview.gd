class_name MapPreview
extends Object
## Real map thumbnails for menus AND the in-game minimap base: one pixel
## per tile, sampled from the planet tile sheet — the same art the match
## itself renders, so the preview IS the map (not a generic planet
## picture). Menu previews also mark each team's fort in its colour so
## start positions read at a glance.

const TILE := 16
const SHEET_COLS := 20  # planet sheets are 20x24 cells of 16px art
const FORT_IDS := [0, 1]  # fort_front + fort_back halves
const FALLBACK_GROUND := Color(0.16, 0.20, 0.13)

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
			if FORT_IDS.has(int(o.get("id", -1))) \
					and String(o.get("type", "")) == "building" \
					and int(o.get("owner", 0)) != 0:
				_mark_fort(img, Vector2i(int(o.x), int(o.y)),
					Teams.minimap_color(int(o.owner)))
		out = ImageTexture.create_from_image(img)
	_cache[map_name] = out
	return out


## True when the map data carries a tiles array we can sample.
static func can_render(data: Dictionary) -> bool:
	var w := int(data.width)
	var h := int(data.height)
	return w > 0 and h > 0 and data.has("tiles") \
			and (data.tiles as Array).size() >= w * h


## Terrain-only image, one pixel per tile in the planet sheet's own
## colours (water tiles are blue because the SHEET tiles are). Falls
## back to a flat ground fill when there is nothing to sample.
static func base_image(data: Dictionary) -> Image:
	var w := int(data.width)
	var h := int(data.height)
	var img := Image.create(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGBA8)
	var sheet := _sheet(String(data.get("terrain", "desert")))
	if sheet == null or not can_render(data):
		img.fill(FALLBACK_GROUND)
		return img
	for i in w * h:
		var index: int = data.tiles[i]
		var cell := Vector2i((index % SHEET_COLS) * TILE + 8,
			(index / SHEET_COLS) * TILE + 8)
		img.set_pixel(i % w, i / w, sheet.get_pixel(cell.x, cell.y))
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


static func _mark_fort(img: Image, cell: Vector2i, color: Color) -> void:
	for dy in 2:
		for dx in 2:
			var p := cell + Vector2i(dx, dy)
			if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
				img.set_pixel(p.x, p.y, color)
