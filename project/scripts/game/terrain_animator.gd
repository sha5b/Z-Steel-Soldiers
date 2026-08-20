class_name TerrainAnimator
extends Node
## Animated terrain — flowing water, lava, city grates, ice floes.
##
## The original stores it per TILE, not per map: a planet's
## `.tileinfo` record carries `is_effect` and `next_tile_in_effect`, and
## the successors form CLOSED RINGS of 2-6 tiles (desert 50 animated
## tiles, city 40, arctic 25, volcanic 18, jungle none). Every frame of
## a ring is already a distinct image in the planet sheet we ship, so a
## ring is a ready-made flip-book: a cell showing ring frame N shows
## frame N+1 next tick. The converters used to drop both fields, which
## is why this was written off as "single-frame tile art, nothing to
## animate from".
##
## The map's OWN phase is kept: shipped maps paint 18-30 different frames
## of the same rings side by side, and that phase offset is what makes a
## river read as flowing instead of blinking in lockstep. So each cell
## advances along its own chain rather than sharing one global frame.
##
## Cost: the busiest shipped map has ~1900 animated cells (median 231),
## stepped 5x a second.

const ATLAS_COLUMNS := 20  # planet sheets are 20x24 tiles of 16px

## UNVERIFIED against the original engine (which ties tile effects to its
## own frame clock): chosen so a 4-frame water ring reads as a slow
## current rather than a strobe.
const FRAME_SECONDS := 0.2

var _layer: TileMapLayer
var _next := {}                 # tile index -> the index that follows it
var _cells: Array[Vector2i] = []  # animated cells, parallel to _phase
var _phase := PackedInt32Array()  # the tile index each cell shows NOW
var _clock := 0.0


## `info` is a tileinfo table (assets/tilesets/tileinfo_<planet>.json):
## "<tile index>" -> [water, passable, is_effect, next_tile_in_effect].
func setup(layer: TileMapLayer, info: Dictionary) -> void:
	_layer = layer
	for key in info:
		var entry: Array = info[key]
		# tables written before the effect fields existed are 2 long —
		# such a planet simply has no animation
		if entry.size() >= 4 and bool(entry[2]):
			_next[int(key)] = int(entry[3])


## The tilemap being animated (scene maps nest theirs one level deeper
## than the JSON loader's, so callers ask rather than search).
func layer() -> TileMapLayer:
	return _layer


## True when this planet has animated tiles at all (jungle has none).
func has_effects() -> bool:
	return not _next.is_empty()


## Register a painted cell. Cells whose tile is not part of a ring are
## ignored, so callers can hand over the whole map.
func register(cell: Vector2i, tile_index: int) -> void:
	if _next.has(tile_index):
		_cells.append(cell)
		_phase.append(tile_index)


func animated_cell_count() -> int:
	return _cells.size()


func _process(delta: float) -> void:
	if _cells.is_empty() or _layer == null:
		return
	_clock += delta
	if _clock < FRAME_SECONDS:
		return
	_clock = 0.0
	step()


## One frame for every animated cell — public so a headless test can
## drive it without waiting on the clock.
func step() -> void:
	for i in _cells.size():
		var nxt: int = _next.get(_phase[i], _phase[i])
		# a ring that leaves the sheet would paint garbage; ignore it
		if nxt < 0 or nxt >= ATLAS_COLUMNS * 24:
			continue
		_phase[i] = nxt
		_layer.set_cell(_cells[i], 0,
			Vector2i(nxt % ATLAS_COLUMNS, nxt / ATLAS_COLUMNS))
