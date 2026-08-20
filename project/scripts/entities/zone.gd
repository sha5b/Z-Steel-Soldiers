@tool
class_name Zone
extends Node2D
## Territory sector (from Zod map zone rects): flag at center, capture by
## presence, feeds GameState income. Territory look is the ORIGINAL's:
## a lattice of small team-coloured marker stamps, one per passable tile
## (zone_marker_<team>.png), water tiles getting the bobbing water
## variant — no borders, no fill. The zone node sits at (0,0) so y-sort
## draws every marker UNDER units and buildings.

signal captured(new_team: int)

var _capture_seconds := 2.0
const MARKER_SCALE := 1.0  # native 8x4 stamps, centred in their 16px tile (zod DoZoneEffects)
const BOB_SECONDS := 0.45  # water marker redraw cadence

@export var zone_rect := Rect2i()
@export var owner_team := 0
## The map's own flag tile for this zone (map_item id 0). Vector2i.MAX
## means "none authored" — then the flag falls back to the derived
## centre spot. The original ships one such marker per non-fort zone and
## the loader used to drop every one of them, so every flag on every map
## stood at a computed position instead of where it was placed.
@export var flag_tile := Vector2i.MAX

var _capturing_team := 0
var _capture_progress := 0.0
var _flag: AnimatedSprite2D
var _cells: Array[Vector2i] = []      # passable land tiles -> land marker
var _water_cells: Array[Vector2i] = []  # water tiles -> bobbing water marker
var _bob_frame := 0  # synchronized bob step (advances once per redraw)
var _bob_timer := 0.0

static var _marker_cache := {}  # "<team>_<water>" -> Texture2D


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	MatchState.current.register_zone(self)
	_build_visuals()


var _flag_pending := true  # buildings spawn after zones — decide once

func _build_visuals() -> void:
	_rebuild_marker_cells()
	queue_redraw()


## An alive fort of the CURRENT owner inside the zone: its garrison
## holds the territory — the zone flips only when the fort falls (same
## intersection test as the flag placement).
func _held_by_fort() -> bool:
	if owner_team == 0:
		return false
	var r := world_rect()
	for b in get_tree().get_nodes_in_group(Groups.BUILDINGS):
		if b is FortBuilding and is_instance_valid(b) and b.alive \
				and b.team == owner_team \
				and b.art_world_rect().intersection(r).get_area() > 0:
			return true
	return false


## Flag placement (deferred one tick, when buildings exist): a zone
## holding a FORT flies no flag of its own — the fort's flag marks the
## territory; every other zone's flag sits on a free cell near the
## centre, nudged off buildings and rocks.
func _place_flag() -> void:
	_flag_pending = false
	var r := world_rect()
	for b in get_tree().get_nodes_in_group(Groups.BUILDINGS):
		if b is FortBuilding and is_instance_valid(b) 				and b.art_world_rect().intersection(r).get_area() > 0:
			return  # the fort flies the territory's flag
	_flag = AnimatedSprite2D.new()
	_flag.sprite_frames = AnimLibrary.flag_frames(owner_team)
	_flag.position = _authored_flag_spot(r)
	_flag.scale = AnimLibrary.FLAG_SCALE  # the art is a 2x redraw
	add_child(_flag)
	if _flag.sprite_frames and _flag.sprite_frames.has_animation("wave"):
		_flag.play("wave")


## The map's flag tile when it authored one and the tile is usable,
## otherwise the derived centre spot.
func _authored_flag_spot(r: Rect2) -> Vector2:
	if flag_tile != Vector2i.MAX and NavWorld.current.nav_grid != null \
			and NavWorld.current.nav_grid.region.has_point(flag_tile) \
			and not NavWorld.current.nav_grid.is_point_solid(flag_tile):
		return NavWorld.cell_center(flag_tile)
	return _flag_spot(r)


## Load-time ownership: set the starting owner WITHOUT the capture
## announcements and signals set_owner_team fires (a match that begins
## with pre-owned territory must not open by shouting "territory lost").
func set_initial_owner(team: int) -> void:
	owner_team = team
	queue_redraw()


## Centre cell, nudged to the nearest passable cell inside the zone.
func _flag_spot(r: Rect2) -> Vector2:
	var c := Vector2i((r.get_center() / 16.0).floor())
	for radius in range(0, 12):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var cell := c + Vector2i(dx, dy)
				if r.has_point(Vector2(cell * 16 + Vector2i(8, 8))) 						and NavWorld.current.nav_grid.region.has_point(cell) 						and not NavWorld.current.nav_grid.is_point_solid(cell):
					return Vector2(cell * 16 + Vector2i(8, 8))
	return r.get_center()


## Which tiles carry a marker: the zone's PERIMETER (zod
## SetupZoneEffects — side columns include the corners, the top/bottom
## rows skip them), passable tiles only (rocks and buildings are
## skipped), water tiles flagged for the bobbing variant.
func _rebuild_marker_cells() -> void:
	_cells.clear()
	_water_cells.clear()
	var edge: Array[Vector2i] = []
	for y in zone_rect.size.y:  # side columns, corners included
		edge.append(zone_rect.position + Vector2i(0, y))
		edge.append(zone_rect.position + Vector2i(zone_rect.size.x - 1, y))
	for x in range(1, zone_rect.size.x - 1):  # top/bottom rows, no corners
		edge.append(zone_rect.position + Vector2i(x, 0))
		edge.append(zone_rect.position + Vector2i(x, zone_rect.size.y - 1))
	for c in edge:
		if NavWorld.current.nav_grid == null:
			_cells.append(c)
			continue
		if not NavWorld.current.nav_grid.region.has_point(c) \
				or NavWorld.current.nav_grid.is_point_solid(c):
			continue
		if NavWorld.current.vehicle_grid != null \
				and NavWorld.current.vehicle_grid.region.has_point(c) \
				and NavWorld.current.vehicle_grid.is_point_solid(c):
			_water_cells.append(c)
		else:
			_cells.append(c)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _flag_pending:
		_place_flag()
	var occupying := 0
	var contested := false
	for u in UnitRegistry.current.world_units():
		# neutral hardware (empty vehicles) does not hold territory
		if u.team != 0 and world_rect().has_point(u.global_position):
			if occupying == 0:
				occupying = u.team
			elif u.team != occupying:
				contested = true
				break
	if contested:
		_capturing_team = 0  # enemies present: nobody captures
		_capture_progress = 0.0
	elif occupying != 0 and occupying != owner_team:
		if _held_by_fort():
			# a live fort holds its ground: territory only changes hands
			# when the fort falls (GameState.report_fort_destroyed
			# neutralizes its zones) — the fort IS the win objective
			_capturing_team = 0
			_capture_progress = 0.0
		else:
			if _capturing_team != occupying:
				_capturing_team = occupying
				_capture_progress = 0.0
			_capture_progress += delta
			if _capture_progress >= ContentDB.rules.capture_seconds:
				set_owner_team(occupying)
				_capturing_team = 0
				_capture_progress = 0.0
	elif occupying == 0 or occupying == owner_team:
		_capture_progress = 0.0
		_capturing_team = 0
	# only the water markers animate: redraw on a slow bob cadence, one
	# synchronized bob step per redraw (per-cell random phases redraw as
	# unsynchronized noise — read as a flickering border texture)
	if not _water_cells.is_empty():
		_bob_timer += delta
		if _bob_timer >= BOB_SECONDS:
			_bob_timer = 0.0
			_bob_frame = (_bob_frame + 1) % 2
			queue_redraw()


func world_rect() -> Rect2:
	return Rect2(zone_rect.position * 16, zone_rect.size * 16)


func _draw() -> void:
	if Engine.is_editor_hint():
		var r := world_rect()
		draw_rect(r, Color(1, 1, 1, 0.08))
		draw_rect(r, Color(1, 1, 1, 0.4), false, 1.0)
		return
	var land := _marker_tex(owner_team, false)
	var water := _marker_tex(owner_team, true)
	# stamp sizes come from the TEXTURE: team stamps are 8x4 but the
	# neutral one is 4x4 — a fixed 8x4 source rect smeared the neutral
	# art sideways
	if land:
		var src := Rect2(Vector2(), land.get_size())
		var dst_size := land.get_size() * MARKER_SCALE
		var off := (Vector2(16, 16) - dst_size) * 0.5
		var dst := Rect2(off, dst_size)
		for c in _cells:
			dst.position = Vector2(c) * 16.0 + off
			draw_texture_rect_region(land, dst, src)
	if water:
		var wsrc := Rect2(Vector2(), water.get_size())
		var wdst_size := water.get_size() * MARKER_SCALE
		var woff := (Vector2(16, 16) - wdst_size) * 0.5 \
				+ Vector2(0, float(_bob_frame))
		var wdst := Rect2(woff, wdst_size)
		for c in _water_cells:
			wdst.position = Vector2(c) * 16.0 + woff
			draw_texture_rect_region(water, wdst, wsrc)


static func _marker_tex(owner: int, water: bool) -> Texture2D:
	var key := "%s_%s" % [AnimLibrary.team_name(owner), water]
	if _marker_cache.has(key):
		return _marker_cache[key]
	var path := "res://assets/z/planets/zone_marker_%s%s.png" % [
		AnimLibrary.team_name(owner), "_water" if water else ""]
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_marker_cache[key] = tex
	return tex


func set_owner_team(team: int) -> void:
	if owner_team == MatchState.current.player_team and team != MatchState.current.player_team:
		Fx.announce("territory_lost", world_rect().get_center())
	owner_team = team
	captured.emit(team)
	MatchState.current.notify_zone_captured(team)
	if _flag:
		_flag.sprite_frames = AnimLibrary.flag_frames(team)
		if _flag.sprite_frames and _flag.sprite_frames.has_animation("wave"):
			_flag.play("wave")
	queue_redraw()  # swap the whole marker lattice to the new colour
