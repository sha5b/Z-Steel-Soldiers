@tool
class_name Building2D
extends Node2D
signal died
## Original-sprite building (forts, factories, radar, repair). Loads the
## per-planet texture, shows an ownership flag, and derives its solid
## footprint from the content def's tile patterns for clicks, zone
## ownership and targeting (art renders 1:1, like every world sprite). The flag waves in the owner's
## own shipped art variant; the building body itself is neutral.

@export var building_id := 2
@export var team := 0
@export var planet := "desert"
@export var level := 0  # 0..5: unlocks the build list roster, speeds builds
var is_fort := false
var selected := false
var net_id := 0  # stable per-match identity for multiplayer intents

var hp := 500
var max_hp := 500
var alive := true
var owner_team := 0  # factories: follows zone owner
var rally_point := Vector2.INF  # produced units gather here when set

var _sprite: Sprite2D
var _rally_flag: Sprite2D
var _flag: AnimatedSprite2D
var _flag_team := -1  # team the flag currently shows
var _hp_bar: Sprite2D
var _hp_bar_max_w := 64.0
var _art_size := Vector2.ZERO  # FULL art size (never the cropped/rotated view)


func setup(id: int, owner_team_value: int, planet_name: String, building_level := 0) -> void:
	building_id = id
	team = owner_team_value
	owner_team = owner_team_value
	planet = planet_name
	level = clampi(building_level, 0, 5)
	is_fort = id == 0 or id == 1
	if is_fort:
		max_hp = FORT_HP  # fort_building_health 10000/240 (zsettings), x0.08
		hp = FORT_HP
	if id == 6 or id == 7:
		max_hp = BRIDGE_HP
		hp = BRIDGE_HP
	elif not is_fort:
		max_hp = BUILDING_HP  # zod: robot/vehicle/radar/repair 2000/240
		hp = BUILDING_HP


# ----------------------- shared production -----------------------
# Every producer (fort, robot factory, vehicle factory) builds from
# its BuildingDef's build_lists[level] — items are "kind:name". The
# logic lives in the Producer component (entities/producer.gd); these
# delegates keep the UI's duck-typed producer contract unchanged.

var _producer := Producer.new()


var producer: Producer:
	get:
		if _producer.b == null:
			_producer.b = self  # lazy: fixtures call production pre-tree
		return _producer

## External contract (production panel, AI, fort garrison, tests) reads
## `building.queue` — pass-through to the component's queue.
var queue: ProductionQueue:
	get:
		return producer.queue


func producer_key() -> String:
	return ""  # not a producer


func produce_seconds(item := "") -> float:
	return producer.produce_seconds(item)


func build_time_mult() -> float:
	return producer.build_time_mult()


func build_options() -> Array:
	return producer.build_options()


func queue_items() -> Array[String]:
	return producer.queue_items()


func progress() -> float:
	return producer.progress()


func queue_unit(item: String, silent := false) -> bool:
	return producer.queue_unit(item, silent)


func cancel_at(index: int) -> void:
	producer.cancel_at(index)


func tick_production(delta: float) -> void:
	producer.tick(delta)


## Products that mount somewhere return true (fort tower cannons take
## their slot); the default product spawns beside the footprint.
func mount_product(kind: String, type_name: String) -> bool:
	return false





func _ready() -> void:
	# works with setup() (JSON loader) or straight @export values (map scenes)
	if not is_fort:
		is_fort = building_id == 0 or building_id == 1
	if owner_team == 0 and team != 0:
		owner_team = team
	_build_sprite()
	if Engine.is_editor_hint():
		return
	# every building registers here: the elimination cascade and the
	# no-units rule need forts AND factories/radar/repair alike
	add_to_group(Groups.ALL_BUILDINGS)
	# the typed roster every building query walks (the group stays for
	# scene-level tooling and for the no-registry fallback)
	if BuildingRegistry.current:
		BuildingRegistry.current.track(self)
		if net_id == 0:
			net_id = BuildingRegistry.current.next_net_id()
	if is_fort:
		add_to_group(Groups.BUILDINGS)
	# producers register for the facility quick bar
	var bdef := ContentDB.building_def(building_id)
	if (bdef != null and bdef.produces) or is_fort:
		add_to_group(Groups.FACILITIES)
		MatchState.current.register_facility(self)
	if not is_bridge():
		apply_footprint()
	_max_burn = _roll_max_burn()


func _exit_tree() -> void:
	# guarded like Unit2D._exit_tree: on scene teardown the match-scoped
	# MatchState can already be gone, and an unguarded call crashes the
	# match change instead of just skipping the bookkeeping
	if MatchState.current:
		MatchState.current.unregister_facility(self)
	if BuildingRegistry.current:
		BuildingRegistry.current.forget(self)


## BRIDGE ART IS A TWO-FRAME SHEET. `bridge_<planet>.png` is 64x256 —
## 4 tiles wide by 16 long — and that is TWO stacked 4x8-tile sprites:
## the INTACT bridge on top, the WRECKED one underneath (verified per
## planet: the lower half carries 1.5-2.6x as many water-coloured pixels
## across its middle, i.e. the deck is gone and the river shows through).
## The code used to hand the whole sheet to the sprite, so every bridge
## on every map drew the intact bridge with its own wreck stacked below
## it — an 8-tile bridge rendered as a 16-tile double. The wrecked state
## then had no art to swap to and faked it by dimming the whole sprite.
const BRIDGE_FRAME := Vector2(64.0, 128.0)
## A bridge's own span in TILES, from the map data. The retail campaign
## stores it per bridge — always 4 tiles ACROSS, 3 to 12 long (verified
## against the 44 bridges that have a zod twin: every record 4 wide is a
## vertical bridge, every record 4 tall a horizontal one, no exceptions).
## The zod maps carry no size at all, so they fall back to the def.
@export var bridge_span_override := Vector2i.ZERO


func bridge_span() -> Vector2i:
	if bridge_span_override != Vector2i.ZERO:
		return bridge_span_override
	var def := ContentDB.building_def(building_id)
	return def.bridge_span if def != null else Vector2i.ZERO


## The frame region for a bridge of this span: the sheet holds ONE
## 4x8-tile frame per state, so a shorter bridge shows only its own
## tiles (it must not paint cells it does not own) and a longer one
## shows the 8 the art has. KNOWN LIMIT: 6 of the 65 retail bridges are
## longer than the frame and 8 are shorter, so those lose art at the far
## end — the frame's internal layout (where the ramps stop and the deck
## begins) is not established, and slicing it on a guess would be worse.
static func bridge_region(destroyed: bool, length_tiles := 8) -> Rect2:
	var rows: float = clampf(float(length_tiles), 1.0, BRIDGE_FRAME.y / 16.0)
	return Rect2(Vector2(0.0, BRIDGE_FRAME.y if destroyed else 0.0),
		Vector2(BRIDGE_FRAME.x, rows * 16.0))


func _build_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = load(_texture_path(false))
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_art_size = _sprite.texture.get_size() if _sprite.texture else Vector2.ZERO
	if is_bridge() and _art_size.y >= BRIDGE_FRAME.y * 2.0:
		var span := bridge_span()
		# the LENGTH runs along the frame's y; the horizontal bridge is
		# the same frame rotated, so its length is the span's x
		var length: int = span.y if building_id == 6 else span.x
		if length <= 0:
			length = int(BRIDGE_FRAME.y / 16.0)
		_sprite.region_enabled = true
		_sprite.region_rect = bridge_region(false, length)
		# the ART is the frame (capped at 8 tiles); the FOOTPRINT is the
		# span the map gave us, which clicks and targeting must use
		_art_size = Vector2(BRIDGE_FRAME.x, float(length) * 16.0)
	var ts: Vector2 = _art_size
	_sprite.centered = false
	# MAP ANCHOR CONTRACT (zod): the map object's tile (x,y) is the ART
	# TOP-LEFT — the node arrives at that tile's centre (x*16+8, y*16+8),
	# so the art's top-left sits exactly on the map cell. Verified
	# against all shipped maps: with this anchor forts stand on their
	# designed ground (the old centre-anchored math put them ~5 tiles
	# too high, painting their platforms over open roads).
	_sprite.position = Vector2(-8.0, -8.0)
	if building_id == 7:  # horizontal bridge: rotate the vertical strip
		_sprite.rotation_degrees = 90
		# the rotated quad spans [-h,0]x[0,w] around its origin, so the
		# origin moves to the art top-left + (art height, 0)
		_sprite.position = Vector2(-8.0 + ts.y, -8.0)
	add_child(_sprite)
	if not is_bridge():
		# Y-SORT CONTRACT: lift the node to the art's vertical MIDDLE —
		# the wall base, where the structure meets its ground platform.
		# Units south of that line stand IN FRONT and draw over the
		# wall's lower pixels and the platform apron; units north of it
		# are behind and get overlaid by the structure. The whole art
		# (platform included) stays ONE sprite — nothing can shear,
		# shift or desync again.
		# FORTS ARE THE EXCEPTION: zod BFort::DoRender PERM-STAMPS the
		# fort base into the map's GROUND layer, so in the original
		# nothing is ever occluded by a fort and tower-mounted guns
		# draw over the platform — sort a fort at its art's TOP edge
		# (every unit stands at y >= that line) for the same effect.
		var lift := -8.0 if is_fort else ts.y * 0.5 - 8.0
		position.y += lift
		_sprite.position.y -= lift
		if is_fort:
			# THE WHOLE FORT GOES ON THE GROUND LAYER, which is what the
			# original does (BFort::DoRender stamps the base into the map's
			# ground so nothing is ever occluded by a fort and tower guns
			# draw over the platform). Sorting it at the art's TOP edge was
			# an approximation of that, and it broke for the units the
			# original cares about most: anything standing NORTH of the top
			# edge sorts BEFORE the fort, so the fort painted over it —
			# apron pixels and all. That is the artefact behind the HQ.
			_sprite.z_index = GROUND_Z
		else:
			_split_ground_layer(ts)

		# ONE flag per ZONE marks territory; the only building that flies
		# its own is the FORT (radar/repair/factories show ownership through
		# their zone's flag — the original never gave every building one)
		if is_fort and not is_bridge():
			_flag = AnimatedSprite2D.new()
			# x: the fort art's horizontal centre; y: just above the art's
			# top edge (fort node sits at the art top, others at the middle)
			_flag.position = Vector2(-8.0 + ts.x * 0.5,
				-12.0 if is_fort else -ts.y * 0.5 - 4.0)
			_flag.scale = AnimLibrary.FLAG_SCALE  # the art is a 2x redraw
			add_child(_flag)
			set_flag_team(team)

	_build_overlays()

	if is_fort:
		# the ORIGINAL team-coloured bar art, cropped right-to-left as
		# health depletes (never recoloured; scaled to the fort's full
		# art width — the one sanctioned world-art resample)
		_hp_bar = Sprite2D.new()
		_hp_bar.centered = false
		_hp_bar.texture = _bar_texture(team)
		# tight to the building: full ART width, left edge on the art's
		# left (a fort's node is at the art top, other buildings at the
		# vertical middle)
		var bar_w := ts.x
		_hp_bar.scale = Vector2(bar_w / 62.0, 6.0 / 16.0)
		_hp_bar.region_enabled = true
		_hp_bar.region_rect = Rect2(0, 0, 62, 16)
		_hp_bar_max_w = bar_w
		# above the waving flag, clear of its pole (the flag spans
		# y -24..0 at the art top edge) — the only world art resampled
		# to fit the fort's full width, at 6px height
		_hp_bar.position = Vector2(-8.0, -30.0 if is_fort else -ts.y * 0.5 - 10)
		_hp_bar.visible = false  # shown while selected or damaged
		add_child(_hp_bar)


## The building's LEVEL, readable. Levels 0-5 are fully implemented (they
## gate the build roster and the build speed) and the number was shown
## NOWHERE — the original stamps it on the structure with the 6x7 digit
## glyphs the pack ships as `level_1..6`. Producers only: a bridge or a
## radar has no roster to unlock.
## Level is a PANEL readout, not a world sprite. We used to stamp
## `ui/hud/level_<n>.bmp` at the art's bottom-left, which put an
## unlabelled yellow digit on bare ground beside every producer. The
## original draws no such thing: `BFort::DoRender`/`DoAfterEffects`
## stamp the base surface, the production `show_time_img` and the team
## flag, and nothing else — `level_img` is HUD art (which is why it
## lives under `ui/hud/`), and the production panel already shows level
## as one of its two vertical gauges.
func set_level(new_level: int) -> void:
	level = clampi(new_level, 0, 5)


## GROUND/STRUCTURE SPLIT. A building's art is one image that also
## contains its ground: the apron in front, the cast shadow, and (on the
## repair shop and radar) actual painted terrain along the right edge.
## As a single Y-sorted sprite the whole block sorted at the wall base,
## so a unit standing north of that line was covered by GROUND pixels —
## it looked cut in half by a patch of dirt.
##
## The art below the sort line is ground by construction (that is why the
## line is there), so it moves to its own sprite on the decal z layer,
## where z_index ordering puts it under every unit regardless of y. The
## structure above the line keeps the normal Y-sort, so walking BEHIND a
## factory still hides the unit — which is correct.
const GROUND_Z := -1  # the decal layer: under units, over terrain
var _ground: Sprite2D = null


## Where the STRUCTURE ends and the ground band begins, in art-local
## pixels from the art's top edge.
##
## This used to be a flat 50% of the art height, which is not where the
## boundary is on any building we ship: the factories' solid block is
## their whole 80px art, the radar's is its whole 48px, and the fort's is
## the top 144 of 176. A half-height cut therefore moved a big slab of
## STRUCTURE onto the under-units layer, so units walked over factory
## walls instead of behind them.
##
## `solid_tiles` already records the answer per building, in cells from
## the art's top-left (footprint_cells reads it the same way), so the
## boundary comes out of the data instead of a magic number.
func _ground_cut(art_size: Vector2) -> int:
	var def := ContentDB.building_def(building_id) if not Engine.is_editor_hint() else null
	if def != null and def.solid_tiles.size.y > 0:
		return (def.solid_tiles.position.y + def.solid_tiles.size.y) * 16
	return int(round(art_size.y * 0.5))


func _split_ground_layer(art_size: Vector2) -> void:
	var cut := _ground_cut(art_size)
	# cut at or past the art's bottom edge = no ground band at all: the
	# whole thing is structure and stays Y-sorted
	if cut <= 0 or cut >= int(art_size.y) or _sprite.texture == null:
		return
	_ground = Sprite2D.new()
	_ground.name = "GroundLayer"
	_ground.texture = _sprite.texture
	_ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ground.centered = false
	_ground.region_enabled = true
	_ground.region_rect = Rect2(0, cut, art_size.x, art_size.y - cut)
	_ground.position = _sprite.position + Vector2(0, cut)
	_ground.z_index = GROUND_Z
	add_child(_ground)
	# the structure keeps only the upper band
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(0, 0, art_size.x, cut)


## Both layers follow the texture (ruins swap the whole sheet). A bridge
## keeps ONE sheet and moves its region to the wreck frame instead.
func _set_building_texture(path: String) -> void:
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if is_bridge():
		set_bridge_wrecked(not alive or hp <= 0)
		return
	if _sprite:
		_sprite.texture = tex
	if _ground:
		_ground.texture = tex


## Swap a bridge between its intact and wrecked frames (the sheet's two
## halves). Crane repair swaps back.
func set_bridge_wrecked(wrecked: bool) -> void:
	if _sprite == null or not is_bridge() or not _sprite.region_enabled:
		return
	_sprite.region_rect = bridge_region(wrecked,
		int(_sprite.region_rect.size.y / 16.0))


## The art's on-screen rect in world pixels (art renders 1:1): top-left
## anchored on the map cell (see _build_sprite). This — not a half-size
## derivation — is the truth for clicks, targeting and the impassable
## cells.
func art_world_rect() -> Rect2:
	if _sprite == null or _art_size == Vector2.ZERO:
		return Rect2(global_position - Vector2(8, 8), Vector2(16, 16))
	if building_id == 7:  # rotated horizontal bridge
		return Rect2(global_position + Vector2(-8, -8),
			Vector2(_art_size.y, _art_size.x))
	# the sprite's own offset IS the anchor truth: forts sit at the art
	# top (zod ground-stamp behaviour, offset (-8, 0)), every other
	# building at its vertical middle (offset (-8, -art/2))
	return Rect2(global_position + _sprite.position, _art_size)


## World tiles this building makes impassable: the def's solid_tiles
## rect (default: the whole art) minus its open_tiles — the original
## engine's SetMapImpassables patterns, so units path around forts but
## can still climb their side platforms and gate. Cell coordinates are
## relative to the art's top-left tile. Bridges are skipped (the map
## loader owns their walkable span).
func footprint_cells() -> Array[Vector2i]:
	var def := ContentDB.building_def(building_id) if not Engine.is_editor_hint() else null
	var origin := Vector2i((art_world_rect().position / 16.0).floor())
	var rect := Rect2i(origin, Vector2i((_art_size / 16.0).ceil()))
	var open: PackedVector2Array = []
	if def != null:
		if def.solid_tiles.size.x > 0 and def.solid_tiles.size.y > 0:
			rect = Rect2i(origin + def.solid_tiles.position, def.solid_tiles.size)
		open = def.open_tiles
	var cells: Array[Vector2i] = []
	for x in rect.size.x:
		for y in rect.size.y:
			if not open.has(Vector2i(x, y) + (rect.position - origin)):
				cells.append(rect.position + Vector2i(x, y))
	return cells


## Physics wall for REAL collision (units move_and_slide against it):
## one 16x16 shape per SOLID CELL on a dedicated layer — physics and the
## A* grids block exactly the same squares, so the fort's walkable gate
## and side platforms stay walkable while nothing cuts through walls.
## Bridges start WITHOUT a body (their span is a road); blowing one up
## drops rubble physics onto the span, repair lifts it again.
var _body: StaticBody2D = null

func set_solid_body(on: bool, cells: Array[Vector2i] = []) -> void:
	if not on:
		if _body:
			_body.queue_free()
			_body = null
		return
	if _body:
		return
	_body = StaticBody2D.new()
	_body.collision_layer = 2  # dedicated building layer
	_body.collision_mask = 0
	# merge consecutive cells in a row into single wide rectangles — a
	# fort is ~8 shapes instead of ~74, same exact coverage
	var by_row := {}
	for cell in cells:
		by_row[cell.y] = (by_row.get(cell.y, []) as Array)
		by_row[cell.y].append(cell.x)
	for y in by_row:
		var xs: Array = by_row[y]
		xs.sort()
		var run_start: int = xs[0]
		var prev: int = xs[0]
		for x in xs + [999999]:
			if x != prev + 1:
				var width := prev - run_start + 1
				var shape := CollisionShape2D.new()
				var rect := RectangleShape2D.new()
				rect.size = Vector2(width * 16.0, 16.0)
				shape.shape = rect
				shape.position = Vector2(run_start * 16.0 + width * 8.0,
					y * 16.0 + 8.0) - global_position
				_body.add_child(shape)
				run_start = x
			prev = x
	add_child(_body)


## Single front door for the static footprint: physics walls AND nav
## solids, always in agreement. Walls-without-solids (buildings spawned
## outside the loaders, or a silent def==null skip) is exactly how
## units ended up wedged inside walls they pathed straight through.
## _ready() calls this — nav solids paint only when the grids already
## exist; the map loaders complete the pair via apply_impassables()
## for buildings whose _ready ran before the grids were built.
## Idempotent: re-painting the same cells is a no-op.
func apply_footprint() -> void:
	if is_bridge():
		return
	var def := ContentDB.building_def(building_id)
	if def == null:
		assert(false, "building_id %d has no BuildingDef — footprint cannot be derived (add content/buildings def or fix the id)" % building_id)
		return
	if not def.solid:
		set_solid_body(false)
		return
	var cells := footprint_cells()
	set_solid_body(true, cells)
	for grid in [NavWorld.current.nav_grid, NavWorld.current.vehicle_grid]:
		if grid != null:
			for cell in cells:
				if grid.region.has_point(cell):
					grid.set_point_solid(cell, true)


## Loader hook: paint nav solids for buildings whose _ready() ran before
## the grids existed (scene maps instantiate their children first).
## Walls are already up from _ready(); this completes the pair.
func apply_impassables(grid: AStarGrid2D, vgrid: AStarGrid2D) -> void:
	if is_bridge():
		return
	var def := ContentDB.building_def(building_id)
	if def == null:
		assert(false, "building_id %d has no BuildingDef — nav solids cannot be painted (add content/buildings def or fix the id)" % building_id)
		return
	if not def.solid:
		return
	for cell in footprint_cells():
		if grid.region.has_point(cell):
			grid.set_point_solid(cell, true)
		if vgrid.region.has_point(cell):
			vgrid.set_point_solid(cell, true)


## Ownership flag: the owning team's own flag frames — neutral team 0
## shows the grey flag set. Swapping teams is a frame swap, no disk
## rescan beyond the four wave frames.
func set_flag_team(for_team: int) -> void:
	if _flag == null or for_team == _flag_team:
		return
	_flag_team = for_team
	_flag.sprite_frames = AnimLibrary.flag_frames(for_team)
	if _flag.sprite_frames and _flag.sprite_frames.has_animation("wave"):
		_flag.play("wave")


static var _bar_cache := {}


## Team-coloured health bar art (shared with the unit selection ring).
static func _bar_texture(team: int) -> Texture2D:
	if not _bar_cache.has(team):
		var path := "res://assets/z/ui/hud/unit_amount_bar_%s.png" 			% AnimLibrary.team_name(team)
		_bar_cache[team] = load(path) if ResourceLoader.exists(path) else null
	return _bar_cache[team]


## Texture location comes from the building def's `tex` key — resolved
## by the ONE shared mapping in ContentDB.building_art_path (the art
## audit uses it too). New building types only add art + a
## content/buildings entry.
func _texture_path(destroyed: bool) -> String:
	if ContentDB.building_def(building_id) == null:
		return ""
	return ContentDB.building_art_path(
		ContentDB.building_def(building_id).tex, planet, destroyed)


## Animated overlay layers from the def's `anims` (radar dish, factory
## spinner, repair smoke stack...): numbered frames `<prefix>_<i>.png`
## played as a loop over the base sprite.
func _build_overlays() -> void:
	var bdef := ContentDB.building_def(building_id)
	if bdef == null:
		return
	for anim in bdef.anims:
		var frame := 0
		var paths: Array[String] = []
		while true:
			var path := "res://assets/z/buildings/%s/%s_%d.png" % [
				bdef.tex, anim.prefix, frame]
			if not ResourceLoader.exists(path):
				break
			paths.append(path)
			frame += 1
		if paths.is_empty():
			continue
		var frames := SpriteFrames.new()
		frames.add_animation("loop")
		frames.set_animation_speed("loop", anim.fps)
		frames.set_animation_loop("loop", true)
		for tex in _overlay_frames(paths):
			frames.add_frame("loop", tex)
		var overlay := AnimatedSprite2D.new()
		overlay.name = "Overlay_%s" % anim.prefix
		overlay.sprite_frames = frames
		overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		overlay.centered = false
		overlay.position = anim.offset - Vector2(8, 8)  # small overlay sprites anchor near their centre
		add_child(overlay)
		overlay.play("loop")


## Overlay frame set. Sets that ship tight-cropped to MIXED canvases
## (the radar dish: 32/24/16 px wide) get padded onto one common canvas,
## content-centred across and foot-aligned — with plain top-left
## anchoring the dish slid ~13px sideways as it spun. Uniform sets pass
## through untouched.
static func _overlay_frames(paths: Array[String]) -> Array[Texture2D]:
	var size := Vector2i.ZERO
	for path in paths:
		var tex: Texture2D = load(path)
		size = size.max(Vector2i(tex.get_width(), tex.get_height()))
	var mixed := false
	for path in paths:
		var tex: Texture2D = load(path)
		if Vector2i(tex.get_width(), tex.get_height()) != size:
			mixed = true
			break
	var out: Array[Texture2D] = []
	for path in paths:
		var tex: Texture2D = load(path)
		if not mixed:
			out.append(tex)
			continue
		var img := tex.get_image()
		var bb := img.get_used_rect()
		var padded := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
		padded.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
			Vector2i((size.x - bb.size.x) / 2 - bb.position.x,
				size.y - img.get_height()))
		out.append(ImageTexture.create_from_image(padded))
	return out


## ---- save contract: dynamic producer state ----

func to_dict() -> Dictionary:
	if not produces_anything():
		return {}
	return {
		"id": building_id, "team": owner_team, "level": level,
		"net": net_id, "hp": hp, "alive": alive,
		"rally_x": rally_point.x if rally_point != Vector2.INF else 0.0,
		"rally_y": rally_point.y if rally_point != Vector2.INF else 0.0,
		"has_rally": rally_point != Vector2.INF,
		"queue": queue.items.duplicate(),
	}


func apply_dict(d: Dictionary) -> void:
	if d.has("level"):
		set_level(maxi(int(d.level), level))  # keeps the level plate honest
	if bool(d.get("has_rally", false)):
		set_rally(Vector2(float(d.get("rally_x", 0.0)), float(d.get("rally_y", 0.0))))
	for item in d.get("queue", []):
		queue_unit(String(item), true)  # silent: no cap beeps on restore


func produces_anything() -> bool:
	var def := ContentDB.producer_def(producer_key())
	return def != null or is_fort


## Ground area the building occupies (world px) — the SOLID cell rect
## for regular buildings (what blocks movement is what you click and
## target), the art/2 rect for bridges. The node itself sits at the
## art's vertical middle for y-sorting, so undo that offset here.
var _fp_cache := Rect2()  # buildings never move — compute once

func world_footprint() -> Rect2:
	# HOT PATH (targeting, splash, AI, garrison): buildings never move,
	# so the solid-cell union is computed exactly once
	if _fp_cache != Rect2():
		return _fp_cache
	if not is_bridge() and ContentDB.building_def(building_id) != null \
			and not Engine.is_editor_hint():
		var cells := footprint_cells()
		if cells.is_empty():
			_fp_cache = art_world_rect()
			return _fp_cache
		var area := Rect2(cells[0] * 16, Vector2(16, 16))
		for cell in cells:
			area = area.expand(Vector2(cell * 16))
			area = area.expand(Vector2(cell * 16 + Vector2i.ONE * 16))
		_fp_cache = area
		return _fp_cache
	# bridges: the art span from its anchor tile (top-left contract) —
	# art_world_rect already swaps w/h for the rotated horizontal bridge.
	# The old art/4 rect centred on the node predates that anchor.
	_fp_cache = art_world_rect()
	return _fp_cache


func visual_center() -> Vector2:
	return world_footprint().get_center()


func set_rally(world_position: Vector2) -> void:
	rally_point = world_position
	if _rally_flag == null:
		_rally_flag = Sprite2D.new()
		_rally_flag.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_rally_flag.scale = AnimLibrary.FLAG_SCALE
		add_child(_rally_flag)
	# the flag frame swaps with the owning team (native art variants)
	_rally_flag.texture = load("res://assets/z/flags/flag_%s_n00.png"
		% AnimLibrary.team_name(team if team != 0 else owner_team))
	_rally_flag.position = rally_point - global_position
	_rally_flag.visible = selected


func set_selected(value: bool) -> void:
	selected = value
	if _rally_flag:
		_rally_flag.visible = value and rally_point != Vector2.INF
	if _hp_bar:
		_hp_bar.visible = selected or hp < max_hp
	queue_redraw()  # corner brackets (the original selection look)


## Selection indicator (zod draw_selection_box): four corner brackets
## in the owner's team colour around the art rect — the same treatment
## the original gave every selected object, buildings included.
func _draw() -> void:
	if Engine.is_editor_hint() or not selected or _art_size == Vector2.ZERO:
		return
	var col: Color = {
		0: Color("737373"), 1: Color("df0000"), 2: Color("1337fb"),
		3: Color("178f13"), 4: Color("cb632f"),
	}.get(owner_team if team == 0 else team, Color.WHITE)
	var r := Rect2(Vector2(-8.0, 0.0 if is_fort else -_art_size.y * 0.5),
		_art_size)
	var arm := 6.0
	var pad := 4.0
	for corner in [r.position, Vector2(r.end.x, r.position.y),
			Vector2(r.position.x, r.end.y), r.end]:
		var dx := 1.0 if corner.x >= r.get_center().x else -1.0
		var dy := 1.0 if corner.y >= r.get_center().y else -1.0
		var base: Vector2 = corner + Vector2(pad * dx, pad * dy)
		draw_line(base, base + Vector2(arm * dx, 0), col, 1.5)
		draw_line(base, base + Vector2(0, arm * dy), col, 1.5)


func update_flag(for_team: int) -> void:
	set_flag_team(for_team)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# the burn population runs DESTROYED too: the original's loop has no
	# IsDestroyed check, which is why a Z ruin goes on burning
	_burn_fx()
	if not alive:
		return  # a ruin produces nothing but fire
	_follow_zone_owner()
	_tick_behaviours(delta)


## Zone-follow, ONE implementation: whichever zone contains the
## footprint center owns the building (flag recolors on capture, a
## capture scraps + refunds the outgoing producer's queue). The two
## factories used to carry byte-identical copies of this loop and the
## base a drifted third. Forts hold their zone; they are not held by it.
func _follow_zone_owner() -> void:
	if is_fort:
		return
	var center := world_footprint().get_center()
	for z in MatchState.current.zones:
		if z.world_rect().has_point(center):
			owner_team = z.owner_team
			break
	if owner_team == team:
		return
	team = owner_team
	update_flag(owner_team)
	if produces_anything():
		# the unit on the line changes hands; the rest of the queue is
		# refunded to the team that just lost the sector
		producer.scrap_queue()


	if team == MatchState.current.player_team and building_id == 2:
		Fx.announce("radar_activated")


## Per-type ticking after zone-follow — subclasses override instead of
## re-listing the loop (base: producers + repair shop; fort: garrison).
func _tick_behaviours(delta: float) -> void:
	if produces_anything():
		tick_production(delta)
	_repair_tick(delta)


func is_bridge() -> bool:
	return building_id == 6 or building_id == 7


## Capability query: does this building accept an order-driven
## interaction from `u` (damaged hardware -> its repair shop; a crane
## -> a damaged building/bridge)? Commands asks the TARGET instead of
## sniffing classes — new interactable buildings only implement this.
func accepts_order_from(u: Unit2D) -> bool:
	if not (u is Vehicle2D) or u.speed <= 0.0:
		return false
	if is_repair_shop() and owner_team == u.team and u.hp < u.max_hp:
		return true
	# bridges are communal infrastructure: any team's crane rebuilds them
	return u.can_service_buildings() and hp < max_hp \
			and (team == u.team or is_bridge())


func is_repair_shop() -> bool:
	return building_id == 3


# ----------------------- repair shop -----------------------
# One damaged vehicle at a time drives in, heals under the smoke stack
# and rolls out again (original: UnitEnterRepairBuilding + repair anim).

var repair_unit: Node2D = null
var _repair_time := 0.0
const REPAIR_SECONDS := 4.0


func try_start_repair(unit: Node2D) -> bool:
	if not is_repair_shop() or owner_team == 0 or repair_unit != null:
		return false
	if unit.team != owner_team or not (unit is Vehicle2D) or unit.kind != "vehicle":
		return false
	if unit.hp >= unit.max_hp:
		return false
	repair_unit = unit
	_repair_time = 0.0
	if owner_team == MatchState.current.player_team:
		Fx.announce("starting_repair")
	unit.visible = false
	unit.velocity = Vector2.ZERO
	unit.clear_move_target()
	unit.waypoints = PackedVector2Array()
	unit.remove_from_group(Groups.SELECTABLE)
	unit.remove_from_group(Groups.UNITS)
	# out of the world while inside (same contract as APC/garrison
	# cargo): not targetable through the shop walls, holds no territory
	unit.carried = true
	SelectionManager.current.drop_from_selection(unit)
	return true


func _repair_tick(delta: float) -> void:
	if repair_unit == null:
		return
	if not is_instance_valid(repair_unit) or not repair_unit.alive:
		repair_unit = null
		return
	_repair_time += delta
	repair_unit.hp = mini(repair_unit.max_hp,
		int(round(repair_unit.hp + repair_unit.max_hp * delta / REPAIR_SECONDS)))
	if _repair_time >= REPAIR_SECONDS or repair_unit.hp >= repair_unit.max_hp:
		var done: Node2D = repair_unit
		repair_unit = null
		done.hp = done.max_hp
		if owner_team == MatchState.current.player_team:
			Fx.announce("vehicle_repaired")
		done.visible = true
		done.carried = false
		done.add_to_group(Groups.SELECTABLE)
		done.add_to_group(Groups.UNITS)
		# validated exit: the fixed +44 nudge half-spawned 16px vehicle
		# boxes back inside the shop's own wall
		var exit_spot := NavWorld.current.find_free_spot(
			world_footprint().get_center() + Vector2(0, 44), done.kind)
		if exit_spot != Vector2.INF:
			done.global_position = exit_spot
		done.move_to(done.global_position + Vector2(0, 34))


# ----------------------- burning -----------------------
# ZBuilding::ProcessBuildingsEffects, ported. A hurt structure holds a
# POPULATION of burn effects, not a spawn rate:
#
#     should_effects = max_effects * (1 - health / max_health)
#
# topped up whenever it is short, each new effect placed at a uniform
# random point inside a per-type `effects_box` in art-local pixels. The
# loop has NO destroyed check, which is why a Z ruin keeps burning: at
# zero health the population sits at max_effects for good.
#
# The box and the cap are verbatim from the Zod Engine constructors
# (bfort/brobot/bvehicle/brepair/bradar; ZBuilding is the fallback) —
# see docs/RESEARCH.md. `rand()` ranges are kept, so two forts on one
# map burn at slightly different intensities like they do in the
# original.
const BURN_BOX_DEFAULT := Rect2(16.0, 16.0, 32.0, 32.0)  # ZBuilding
const BURN_BOX_FORT := Rect2(18.0, 18.0, 136.0, 118.0)   # BFort
const BURN_BOX_RADAR := Rect2(1.0, 6.0, 44.0, 30.0)      # BRadar
var _burn_effects: Array[Node] = []
var _max_burn := 0


## The original's per-type cap, rolled once per building like the
## constructors do.
func _roll_max_burn() -> int:
	if is_bridge():
		return 0  # zod bridges carry no effects_box
	if is_fort:
		return 20 + (randi() % 8)      # BFort
	match building_id:
		2:
			return 6 + (randi() % 3)   # BRadar
		3:
			return 6 + (randi() % 4)   # BRepair
		4, 5:
			return 8 + (randi() % 4)   # BRobot / BVehicle
	return 8                           # ZBuilding default


## `effects_box` in art-local px. The factories and the repair shop
## derive it from their own art (`8, 8, w - 24, h - 24`); the fort and
## the radar carry literal boxes.
func _burn_box() -> Rect2:
	if is_fort:
		return BURN_BOX_FORT
	if building_id == 2:
		return BURN_BOX_RADAR
	if building_id in [3, 4, 5] and _art_size != Vector2.ZERO:
		return Rect2(8.0, 8.0,
			maxf(_art_size.x - 24.0, 8.0), maxf(_art_size.y - 24.0, 8.0))
	return BURN_BOX_DEFAULT


## Top the burn population up to what the current damage calls for.
## Cheap: the loop body only runs on the frames the count is short.
func _burn_fx() -> void:
	if _max_burn == 0 or _art_size == Vector2.ZERO:
		return
	var want := int(_max_burn * (1.0 - clampf(
		float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)))
	_burn_effects = _burn_effects.filter(func(fx): return is_instance_valid(fx))
	# DEVIATION, deliberate: the original never shrinks `extra_effects`,
	# so a repaired building burns for the rest of the match. We repair
	# buildings (crane + repair shop), so the fires have to go back out.
	while _burn_effects.size() > want:
		var done: Node = _burn_effects.pop_back()
		if is_instance_valid(done):
			done.queue_free()
	if _burn_effects.size() >= want:
		return
	var box := _burn_box()
	var art_origin := art_world_rect().position - global_position
	while _burn_effects.size() < want:
		var fx: AnimatedSprite2D = Fx.burn_effect()
		if fx == null:
			_max_burn = 0  # art missing: stop asking every frame
			return
		fx.position = art_origin + box.position + Vector2(
			randf() * box.size.x, randf() * box.size.y)
		fx.z_index = 2  # over the structure, under the flag and the plate
		add_child(fx)
		_burn_effects.append(fx)


## `at` is the impact point in world px when the caller knows it (every
## weapon does) — see _hit_flash for why that matters.
func take_damage(amount: int, at := Vector2.INF) -> void:
	if not alive:
		return
	if is_bridge():
		_bridge_damage(amount, at)
		return
	hp -= amount
	if is_fort and team == MatchState.current.player_team:
		Fx.announce("fort_under_attack", global_position)  # forts only — factories have
		# their own distinct original voice lines
	elif team == MatchState.current.player_team:
		# A FACTORY UNDER FIRE HAS NO VOICE LINE, so losing one off-screen
		# used to be completely silent. Ping the radar instead (throttled
		# per area by Fx) — the A button then jumps there.
		Fx.ping(visual_center())
	_hit_flash(at)
	if _hp_bar:
		_hp_bar.region_rect.size.x = maxf(6.0,
			62.0 * clampf(float(hp) / float(max_hp), 0.0, 1.0))
		_hp_bar.visible = true
	if is_fort and team == MatchState.current.player_team and hp > 0 \
			and float(hp) / float(max_hp) < 0.35:
		Fx.announce("youre_losing", global_position)
	if hp <= 0:
		alive = false
		_death_visuals()
		if is_fort:
			GameState.report_fort_destroyed(team)


## Damage feedback WITHOUT tinting the sprite. A building's art is one
## image that includes its GROUND PLATFORM — the fort's whole sandy apron
## lives in `fort_<planet>_front.png` — so `modulate = Color(3,3,3)` blew
## the terrain white along with the walls, and a fort under sustained
## fire strobed its entire tile footprint. There is no separate platform
## layer in the shipped art to exclude (zod stamps the fort base into the
## ground layer instead), so the flash is now a LOCAL spark at the hit
## point: it reads as "this structure is being hit here", and no ground
## pixel changes colour. Falls back to a random point on the solid
## footprint when the caller has no impact position.
func _hit_flash(at: Vector2) -> void:
	var spot := at
	if spot == Vector2.INF or not spot.is_finite():
		var fp := world_footprint()
		spot = Vector2(randf_range(fp.position.x, fp.end.x),
			randf_range(fp.position.y, fp.end.y))
	Fx.impact(spot)


## Ruin look + bookkeeping shared by battle death and the elimination
## cascade: destroyed texture, overlays/flag/HP bar away, deselect.
func _death_visuals() -> void:
	died.emit()
	remove_from_group(Groups.BUILDINGS)
	remove_from_group(Groups.FACILITIES)
	SelectionManager.current.drop_from_selection(self)
	if has_method("kill_garrison"):
		call("kill_garrison")
	Fx.destroyed(visual_center())
	# the structure throws pieces of ITSELF (the pack's death_effects
	# art, which nothing referenced): the fort's five pieces, two
	# generic ones for everything else
	Fx.building_debris(visual_center(), is_fort,
		maxf(_art_size.x, 32.0) * 0.5, world_footprint())
	# the ruin goes on burning by itself: hp is 0, so _burn_fx tops the
	# population up to max_effects and never takes it down again
	if _sprite:
		_set_building_texture(_texture_path(true))
		for child in get_children():
			if child.name.begins_with("Overlay_"):
				child.visible = false
	if _hp_bar:
		_hp_bar.visible = false
	if _flag:
		_flag.visible = false


## Team-elimination cascade (original CheckDestroyedFort destroys every
## object of the falling team): same ruin visuals as battle death, but
## never re-reports — the cascade owns the elimination.
func kill() -> void:
	if not alive:
		return
	alive = false
	hp = 0
	_death_visuals()


# ----------------------- bridges -----------------------
# Bridges can be blown up (they become impassable rubble) and rebuilt
# by a manned crane (original: CheckDestroyedBridge + crane repair).

const BRIDGE_HP := 6667  # bridge_building_health 2000/240 (zsettings), x0.08
const BUILDING_HP := 6667  # radar/repair/factory health, same zsettings row
const FORT_HP := 33333  # fort_building_health 10000/240 (zsettings), x0.08
var bridge_cells: Array[Vector2i] = []  # filled by the map loader


func _bridge_damage(amount: int, at := Vector2.INF) -> void:
	hp -= amount
	# a bridge's art IS its road surface — tinting it flashed the ground
	# units are standing on (same rule as _hit_flash)
	_hit_flash(at)
	if hp > 0:
		return
	hp = 0
	Fx.destroyed(world_footprint().get_center())
	# the span's own rubble, in the planet's colours: a few pieces along
	# the deck instead of one puff at the middle
	for i in mini(bridge_cells.size(), 4):
		var piece: Vector2i = bridge_cells[
			(i * maxi(bridge_cells.size() / 4, 1)) % bridge_cells.size()]
		Fx.bridge_debris(Vector2(piece) * 16.0 + Vector2(8, 8))
	for cell in bridge_cells:
		if NavWorld.current.nav_grid:
			NavWorld.current.nav_grid.set_point_solid(cell, true)
		if NavWorld.current.vehicle_grid:
			NavWorld.current.vehicle_grid.set_point_solid(cell, true)
	set_solid_body(true, bridge_cells)
	set_bridge_wrecked(true)  # the sheet's own wreck frame, not a tint


## Crane repair: restores a destroyed bridge (or patches a damaged one).
## Forts are never crane-repairable (original Z: cranes fix bridges, not
## HQs — 1,750 HP/s of crane healing made forts practically unkillable
## while the AI kept one on station).
func repair_by(amount: int) -> void:
	if is_fort:
		return
	if not is_bridge():
		hp = mini(hp + amount, max_hp)
		# the bar must grow back with the hull (and vanish at full
		# health per the "selected or damaged" visibility rule)
		if _hp_bar:
			_hp_bar.region_rect.size.x = maxf(6.0,
				62.0 * clampf(float(hp) / float(max_hp), 0.0, 1.0))
			_hp_bar.visible = selected or hp < max_hp
		return
	if hp >= BRIDGE_HP:
		return
	hp = mini(hp + amount, BRIDGE_HP)
	if hp >= BRIDGE_HP:
		for cell in bridge_cells:
			if NavWorld.current.nav_grid:
				NavWorld.current.nav_grid.set_point_solid(cell, false)
			if NavWorld.current.vehicle_grid:
				NavWorld.current.vehicle_grid.set_point_solid(cell, false)
		# the rubble physics wall must go with the nav solids — grids
		# saying "walkable" while move_and_slide still hits invisible
		# rubble jams every unit sent across
		set_solid_body(false)
		set_bridge_wrecked(false)  # deck back: the sheet's intact frame
		Fx.play("spark", world_footprint().get_center())
