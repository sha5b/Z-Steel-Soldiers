class_name TerrainTests
extends Object
## Animated terrain (--terrain-test): the tileinfo effect rings and the
## live TerrainAnimator. This closed "terrain animation is impossible"
## as a bug — the rings were in the data all along, both converters
## dropped them — so the test guards BOTH halves: the converted tables
## and the tilemap actually changing.

const TILEINFO_DIR := "res://assets/tilesets"

## Counted straight out of the original .tileinfo binaries.
const ANIMATED_TILES := {
	"desert": 50, "city": 40, "arctic": 25, "volcanic": 18, "jungle": 0,
}
## Not every animated tile sits ON a ring. A few are LEAD-IN frames: they
## feed a ring (volcanic 376 -> the 377<->378 flicker) or, once, walk out
## of the effect set into a static tile and settle there (arctic
## 399 -> 426, still water). No shipped map paints any of those 10 cells,
## so the difference is unobservable in play; the counts are asserted to
## pin the shape of the data the animator walks.
const LEAD_IN_TILES := {
	"desert": 0, "city": 0, "arctic": 7, "volcanic": 3, "jungle": 0,
}
const TILES_PER_PLANET := 480


static func run(ctx: Node, rig: TestRig) -> void:
	_tables(rig)
	_live(ctx, rig)
	_map_planets(rig)
	rig.finish()


## EVERY shipped map must agree with its planet's tileinfo: a robot,
## vehicle or cannon the level designer placed always stands on walkable,
## non-water ground. This is the invariant that caught the swapped
## city/jungle planet ids — 21 of 58 maps drew with the wrong tileset AND
## took their nav grids from the wrong table, so up to 35 units per map
## spawned in what the game read as water or wall. Buildings are excluded
## on purpose: ~160 of them are bridges, anchored over water by design.
## (tools/zod/verify_map_planets.py is the same check outside the engine.)
static func _map_planets(rig: TestRig) -> void:
	var checked := 0
	var misplaced := 0
	var worst := ""
	var bridge_cells := 0
	var wet_bridge_cells := 0
	for entry in MapCatalog.entries():
		if not bool(entry.get("json", false)):
			continue
		var path := "res://assets/maps/%s.json" % String(entry.name)
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary):
			continue
		var data: Dictionary = parsed
		var w := int(data.width)
		var h := int(data.height)
		if data.get("passable", null) == null or data.get("water", null) == null:
			continue
		checked += 1
		var bad := 0
		for o in data.objects:
			var kind := String(o.type)
			if kind != "robot" and kind != "vehicle" and kind != "cannon":
				continue
			var x := int(o.x)
			var y := int(o.y)
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			var i := y * w + x
			if int(data.water[i]) != 0 or int(data.passable[i]) == 0:
				bad += 1
		# BRIDGE SPANS: the designers leave a DRY corridor where a bridge
		# stands (the river stops either side of it), so not one cell of
		# a bridge's span is water — 7,520 cells across the shipped set.
		# That pins the span exactly: swapping the two orientations puts
		# 1,747 cells in the river, and making it 5 tiles wide, 491.
		for o in data.objects:
			if String(o.type) != "building":
				continue
			var bdef := ContentDB.building_def(int(o.id))
			if bdef == null or bdef.bridge_span == Vector2i.ZERO:
				continue
			# the retail campaign gives every bridge its OWN span
			# (4 across, 3-12 long); the zod maps carry none
			var span := bdef.bridge_span
			if int(o.get("span_w", 0)) > 0 and int(o.get("span_h", 0)) > 0:
				span = Vector2i(int(o.span_w), int(o.span_h))
			for bx in span.x:
				for by in span.y:
					var cx := int(o.x) + bx
					var cy := int(o.y) + by
					if cx < 0 or cy < 0 or cx >= w or cy >= h:
						continue
					bridge_cells += 1
					if int(data.water[cy * w + cx]) != 0:
						wet_bridge_cells += 1
		if bad > 0:
			misplaced += bad
			worst = "%s (%d)" % [String(entry.name), bad]
	rig.check(checked > 0, "no JSON maps to audit")
	rig.check(misplaced == 0,
		"%d units spawn in water or in a wall across %d maps — worst %s "
		% [misplaced, checked, worst]
		+ "(planet tag vs tileinfo mismatch: run tools/zod/verify_map_planets.py)")
	rig.check(bridge_cells > 0, "no bridge spans audited")
	rig.check(wet_bridge_cells == 0,
		"%d of %d bridge span cells sit in water — the span does not match "
		% [wet_bridge_cells, bridge_cells]
		+ "the crossing (check bridge_span vs the bridge art frame)")
	print("TERRAIN: audited %d maps, %d misplaced units, %d bridge cells (%d wet)"
		% [checked, misplaced, bridge_cells, wet_bridge_cells])


## The converted tables: [water, passable, is_effect, next_tile], and
## every effect chain closes into a ring inside the 480-tile sheet.
static func _tables(rig: TestRig) -> void:
	for planet in ANIMATED_TILES:
		var path := "%s/tileinfo_%s.json" % [TILEINFO_DIR, planet]
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary):
			rig.check(false, "tileinfo table missing: %s" % path)
			continue
		var info: Dictionary = parsed
		rig.check(info.size() == TILES_PER_PLANET,
			"%s: %d tiles want %d" % [planet, info.size(), TILES_PER_PLANET])
		var next := {}
		var short_entries := 0
		for key in info:
			var entry: Array = info[key]
			if entry.size() < 4:
				short_entries += 1
				continue
			if bool(entry[2]):
				next[int(key)] = int(entry[3])
		rig.check(short_entries == 0,
			"%s: %d entries carry no effect fields (stale converter output)"
			% [planet, short_entries])
		rig.check(next.size() == ANIMATED_TILES[planet],
			"%s: %d animated tiles want %d"
			% [planet, next.size(), ANIMATED_TILES[planet]])
		var lead_ins := 0
		for tile in next:
			rig.check(int(next[tile]) >= 0 and int(next[tile]) < TILES_PER_PLANET,
				"%s: tile %d -> %d outside the sheet"
				% [planet, tile, int(next[tile])])
			# on a ring, following the chain comes back to this frame;
			# a lead-in frame runs into a ring (or a static tile) instead
			var cur: int = tile
			var steps := 0
			while steps < 8:
				cur = int(next.get(cur, -1))
				steps += 1
				if cur == tile or cur == -1:
					break
			if cur != tile:
				lead_ins += 1
		rig.check(lead_ins == LEAD_IN_TILES[planet],
			"%s: %d lead-in frames, want %d"
			% [planet, lead_ins, LEAD_IN_TILES[planet]])


## The live map: the animator exists for a planet that has rings, holds
## cells, and stepping it REPAINTS them (the whole point).
static func _live(ctx: Node, rig: TestRig) -> void:
	var planet: String = MatchState.current.planet
	var anim: TerrainAnimator = null
	for c in ctx.get_children():
		if c is TerrainAnimator:
			anim = c
			break
	if int(ANIMATED_TILES.get(planet, 0)) == 0:
		rig.check(anim == null,
			"%s has no effect tiles but an animator was built" % planet)
		return
	rig.check(anim != null, "%s map has no TerrainAnimator" % planet)
	if anim == null:
		return
	var layer: TileMapLayer = anim.layer()
	rig.check(layer != null, "no Terrain layer to animate")
	rig.check(anim.animated_cell_count() > 0,
		"%s map registered no animated cells" % planet)
	if layer == null or anim.animated_cell_count() == 0:
		return
	var sample: Array[Vector2i] = []
	var before: Array[Vector2i] = []
	for i in mini(anim.animated_cell_count(), 32):
		sample.append(anim._cells[i])
		before.append(layer.get_cell_atlas_coords(anim._cells[i]))
	anim.step()
	var changed := 0
	for i in sample.size():
		if layer.get_cell_atlas_coords(sample[i]) != before[i]:
			changed += 1
	rig.check(changed == sample.size(),
		"stepping repainted %d of %d animated cells" % [changed, sample.size()])
	# and the map's own phase offsets survive: shipped maps paint several
	# frames of the same ring side by side, which is what makes water
	# read as flowing instead of blinking in lockstep
	var phases := {}
	for i in anim.animated_cell_count():
		phases[anim._phase[i]] = true
	print("TERRAIN: planet=%s animated_cells=%d distinct_frames=%d" % [
		planet, anim.animated_cell_count(), phases.size()])
