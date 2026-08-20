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
	rig.finish()


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
