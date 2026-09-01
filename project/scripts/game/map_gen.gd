class_name MapGen
extends Object
## GENERATED SKIRMISH MAPS. Emits the exact JSON dictionary the shipped
## maps use (see map_loader.gd), so the loader, the minimap, the AI and
## the save system treat a generated map like any other — the only new
## code is this generator and the skirmish screen's settings row.
##
## What a generated map contains, and why:
## - a flat ground sheet from the planet's plain-ground tiles (ids 0..4
##   are open ground on every planet's tileinfo table);
## - ROCK FORMATIONS as `map_item id 1` columns — the one terrain
##   feature whose assembly (the ported ORock autotiler) looks right
##   from any blob shape. No water: water needs shore transition tiles
##   this generator cannot author, and no water means no bridges and no
##   unreachable wheels.
## - one FORT per player on an ellipse around the centre, with a robot
##   and a vehicle factory beside it (the AI's production pass and the
##   win rules both key off the fort; starting squads come from the
##   loader's no-units grant);
## - ZONES tiling the whole map in a near-square grid — zones are the
##   income unit and the CPU brain's entire world model, and AiMap's
##   adjacency graph needs roughly uniform rects;
## - a neutral flag (`map_item id 0`) in every zone that has no fort.
##
## CONNECTIVITY IS GUARANTEED, not hoped for: rocks never spawn inside
## the corridors between any two forts (a widened line segment), nor on
## the fort/factory aprons, so every fort can always reach every other.

const SIZES := {"small": 96, "medium": 128, "large": 176}
const PLANETS := ["desert", "volcanic", "arctic", "jungle", "city"]
const OUT_PATH := "user://generated_map.json"

const FORT_W := 10
const FORT_H := 9
const FACTORY_W := 4
const FACTORY_H := 5
## Half-width (tiles) of the kept-clear corridor between fort centres.
const CORRIDOR_HALF := 4.0
## Kept-clear ring around a fort centre (tiles).
const HOME_CLEAR := 13.0


## The whole map as one dictionary in the shipped JSON schema.
## `players` 2..8, `size_key` in SIZES, `planet` in PLANETS (or
## "random"), `seed_v` -1 for a fresh roll.
static func generate(players: int, size_key: String, planet: String,
		seed_v := -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v if seed_v >= 0 else randi()
	players = clampi(players, 2, 8)
	var w: int = int(SIZES.get(size_key, 128))
	var h: int = w
	if planet == "random" or not PLANETS.has(planet):
		planet = PLANETS[rng.randi_range(0, PLANETS.size() - 1)]

	# --- ground sheet: plain-ground tiles, mostly the base id ----------
	var tiles := PackedInt32Array()
	tiles.resize(w * h)
	for i in w * h:
		tiles[i] = 0 if rng.randf() < 0.72 else rng.randi_range(1, 4)

	# --- forts on an ellipse around the centre --------------------------
	var centre := Vector2(w, h) * 0.5
	var radius := minf(w, h) * 0.36
	var angle0 := rng.randf() * TAU
	var fort_centres: Array[Vector2] = []
	var objects: Array = []
	for p in players:
		var team := p + 1
		var ang := angle0 + TAU * float(p) / float(players)
		var fc := centre + Vector2(cos(ang), sin(ang)) * radius
		fc.x = clampf(fc.x, FORT_W * 0.5 + 6.0, w - FORT_W * 0.5 - 6.0)
		fc.y = clampf(fc.y, FORT_H * 0.5 + 6.0, h - FORT_H * 0.5 - 6.0)
		fort_centres.append(fc)
		var fx := int(roundf(fc.x - FORT_W * 0.5))
		var fy := int(roundf(fc.y - FORT_H * 0.5))
		# fort_front (id 0) faces down — use it in the top half so every
		# fort faces the middle of the map, like the shipped layouts
		var fort_id := 0 if fc.y < centre.y else 1
		objects.append(_obj(fx, fy, team, "building", fort_id))
		# a factory on each side of the fort, dropped inward when the
		# map edge is too close; owner set explicitly so home facilities
		# never depend on the zone-ownership pass
		for side in [-1, 1]:
			var bx := fx - FACTORY_W - 2 if side < 0 else fx + FORT_W + 2
			var by := fy + 2
			if bx < 2 or bx + FACTORY_W > w - 2:
				bx = clampi(fx + (2 if side < 0 else FORT_W - FACTORY_W - 2), 2,
					w - FACTORY_W - 2)
				by = fy + FORT_H + 2 if fc.y < centre.y else fy - FACTORY_H - 2
			by = clampi(by, 2, h - FACTORY_H - 2)
			objects.append(_obj(bx, by, team, "building", 4 if side < 0 else 5))

	# --- the kept-clear mask: homes and every fort-to-fort corridor -----
	var protected := {}
	for fc in fort_centres:
		_mark_disc(protected, fc, HOME_CLEAR, w, h)
	for i in fort_centres.size():
		for j in range(i + 1, fort_centres.size()):
			_mark_corridor(protected, fort_centres[i], fort_centres[j], w, h)

	# --- rock formations: random-walk blobs of column objects -----------
	var rock_cells := {}
	var blobs: int = maxi(6, (w * h) / 1100)
	for b in blobs:
		var at := Vector2i(rng.randi_range(4, w - 5), rng.randi_range(6, h - 5))
		var steps := rng.randi_range(10, 46)
		for s in steps:
			if at.x >= 3 and at.x < w - 3 and at.y >= 4 and at.y < h - 4 \
					and not protected.has(at):
				rock_cells[at] = true
			var dir: Vector2i = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP,
				Vector2i.DOWN][rng.randi_range(0, 3)]
			# drift sideways more than vertically: broad ridges read
			# better than tall stalks and block less north-south travel
			if rng.randf() < 0.3:
				dir = Vector2i.LEFT if rng.randf() < 0.5 else Vector2i.RIGHT
			at += dir
	for cell: Vector2i in rock_cells:
		# a rock object anchors at the TOP of its up-to-3-tile column and
		# blocks at base = y+2, so the blob cell is the BASE we want solid
		objects.append(_obj(cell.x, cell.y - 2, 0, "map_item", 1))

	# --- zones tiling the map, one flag per fortless zone ----------------
	var zones: Array = []
	var grid := clampi(int(roundf(float(w) / 30.0)), 3, 8)
	var fort_zone_hits := {}
	for zy in grid:
		for zx in grid:
			var x0 := zx * w / grid
			var y0 := zy * h / grid
			var zone := {"x": x0, "y": y0,
				"w": (zx + 1) * w / grid - x0, "h": (zy + 1) * h / grid - y0}
			zones.append(zone)
			var rect := Rect2(zone.x, zone.y, zone.w, zone.h)
			for fc in fort_centres:
				if rect.has_point(fc):
					fort_zone_hits[zones.size() - 1] = true
	for zi in zones.size():
		if fort_zone_hits.has(zi):
			continue
		var z: Dictionary = zones[zi]
		var flag := _open_spot(Vector2i(z.x + z.w / 2, z.y + z.h / 2),
			rock_cells, w, h)
		objects.append(_obj(flag.x, flag.y, 0, "map_item", 0))

	return {
		"name": "generated", "width": w, "height": h, "terrain": planet,
		"player_count": players, "zones": zones, "objects": objects,
		"tiles": Array(tiles), "passable": null, "water": null,
	}


## Write the map where the loader can read it; returns the path.
static func write(data: Dictionary) -> String:
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	return OUT_PATH


static func _obj(x: int, y: int, owner: int, type: String, id: int) -> Dictionary:
	return {"x": x, "y": y, "owner": owner, "type": type, "id": id,
		"level": 0, "health": 100}


static func _mark_disc(mask: Dictionary, at: Vector2, r: float,
		w: int, h: int) -> void:
	for dy in range(-int(r), int(r) + 1):
		for dx in range(-int(r), int(r) + 1):
			if Vector2(dx, dy).length() > r:
				continue
			var c := Vector2i(int(at.x) + dx, int(at.y) + dy)
			if c.x >= 0 and c.x < w and c.y >= 0 and c.y < h:
				mask[c] = true


static func _mark_corridor(mask: Dictionary, a: Vector2, b: Vector2,
		w: int, h: int) -> void:
	var steps := int(a.distance_to(b)) + 1
	for i in steps + 1:
		_mark_disc(mask, a.lerp(b, float(i) / float(steps)), CORRIDOR_HALF, w, h)


## Nearest cell to `near` that is not a rock base (spiral out; the map
## is mostly open so this ends within a ring or two).
static func _open_spot(near: Vector2i, rocks: Dictionary, w: int, h: int) -> Vector2i:
	for r in 8:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := near + Vector2i(dx, dy)
				if c.x < 1 or c.x >= w - 1 or c.y < 1 or c.y >= h - 1:
					continue
				if not rocks.has(c) and not rocks.has(c + Vector2i(0, -2)):
					return c
	return near
