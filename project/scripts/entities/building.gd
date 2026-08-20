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

var hp := 500
var max_hp := 500
var alive := true
var owner_team := 0  # factories: follows zone owner
var rally_point := Vector2.INF  # produced units gather here when set
var queue := ProductionQueue.new()  # production queue ("kind:name" items)

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
# its BuildingDef's build_lists[level] — items are "kind:name". Robots
# spawn crewed; vehicles and cannons spawn empty beside the building for
# a robot to man (Z-style).

func producer_key() -> String:
	return ""  # not a producer


## Build time for a "kind:name" queue item: the unit def's ORIGINAL
## build time (zsettings.cpp SetDefaults — the original's economy is
## time, not money), trimmed by the producer's level. fast_build is the
## self-test lever.
func produce_seconds(item := "") -> float:
	if MatchState.fast_build:
		return 2.0
	if item == "" and not queue.items.is_empty():
		item = queue.items[0]
	if item == "":
		return 8.0 * build_time_mult()
	var parts: PackedStringArray = item.split(":")
	if parts.size() == 2 and ContentDB.has_unit(parts[0], parts[1]):
		return ContentDB.def_for(parts[0], parts[1]).build_time * build_time_mult()
	return 8.0 * build_time_mult()


## Original BuildTimeModified (zbuilding.cpp): production speeds up with
## the share of the map's zones the owner holds (up to -50% at full
## control) and slows while the building is damaged (up to +125% near
## death). Building LEVEL only gates the roster, exactly like the
## original — it never sped builds up.
func build_time_mult() -> float:
	var owner := team if team != 0 else owner_team
	var owned := 0
	for z in MatchState.zones:
		if z.owner_team == owner:
			owned += 1
	var ownage := float(owned) / float(maxi(MatchState.zones.size(), 1))
	var damage_penalty := 1.0 + 1.25 * (1.0 - float(hp) / float(max_hp))
	return maxf((1.0 - 0.5 * ownage) * damage_penalty, 0.1)


func build_options() -> Array:
	var def := ContentDB.producer_def(producer_key())
	if def == null:
		return []
	return def.build_lists.get(level, [])


func queue_items() -> Array[String]:
	return queue.items


func progress() -> float:
	if owner_team == 0 or queue.items.is_empty():
		return 0.0
	return queue.progress(produce_seconds(queue.items[0] if not queue.items.is_empty() else ""))


func queue_unit(item: String, silent := false) -> bool:
	var parts := item.split(":")
	if parts.size() != 2:
		return false
	var kind := parts[0]
	var type_name := parts[1]
	if not ContentDB.has_unit(kind, type_name):
		return false
	if kind != "robot" and not ContentDB.has_sprites(kind, type_name):
		return false
	var stats := ContentDB.def_for(kind, type_name)
	if not _pop_allows(kind, stats, silent):
		return false
	if not MatchState.spend(owner_team, stats.cost):
		return false
	if not queue.enqueue(item):
		MatchState.money[owner_team] += stats.cost  # queue full: refund
		MatchState.money_changed.emit(owner_team, MatchState.money[owner_team])
		return false
	if owner_team == MatchState.player_team and queue.items.size() == 1:
		Fx.announce("starting_manufacture")
	return true


func cancel_at(index: int) -> void:
	var item := queue.cancel_at(index)
	if item == "" or owner_team == 0:
		return
	if owner_team == MatchState.player_team:
		Fx.announce("manufacturing_canceled")
	var stats := ContentDB.def_for(item.split(":")[0], item.split(":")[1])
	MatchState.money[owner_team] += stats.cost
	MatchState.money_changed.emit(owner_team, MatchState.money[owner_team])


## A capture scraps the old owner's queue — payment is upfront and
## cancellation refunds, so the outgoing team gets its money back too.
func _refund_queue() -> void:
	if team == 0 or queue.items.is_empty():
		return
	for item in queue.items:
		var parts: PackedStringArray = item.split(":")
		MatchState.money[team] += ContentDB.def_for(parts[0], parts[1]).cost
	MatchState.money_changed.emit(team, MatchState.money[team])


## Cap gate: alive + queued + this unit must fit under the team cap.
## `silent` suppresses the denial beep for CPU-initiated production.
func _pop_allows(kind: String, stats: UnitDef, silent := false) -> bool:
	var team_id := team if team != 0 else owner_team
	var queued := 0
	for item in queue.items:
		var parts: PackedStringArray = item.split(":")
		queued += ContentDB.def_for(parts[0], parts[1]).pop
	var cost := stats.pop
	if MatchState.unit_pop(team_id) + queued + cost > MatchState.unit_cap(team_id):
		if not silent:
			Fx.cap_denied()
		return false
	return true


func tick_production(delta: float) -> void:
	if owner_team == 0:
		return
	var done := queue.tick(delta, produce_seconds(queue.items[0] if not queue.items.is_empty() else ""))
	if done != "":
		spawn_produced(done)


func spawn_produced(item: String) -> void:
	var parts := item.split(":")
	var kind := parts[0]
	var type_name := parts[1]
	if owner_team == MatchState.player_team:
		Fx.announce("robot_manufactured" if kind == "robot"
			else "vehicle_manufactured" if kind == "vehicle"
			else "gun_manufactured")
	# spawn just BELOW the solid footprint — never inside it
	var fp := world_footprint()
	var spawn_pos := Vector2(fp.get_center().x, fp.end.y + 14.0)
	if kind == "robot":
		var unit: Unit2D = Spawner.spawn(get_parent(), kind, type_name,
			owner_team, spawn_pos) as Unit2D
		if unit and rally_point != Vector2.INF:
			unit.move_to(rally_point)
	elif ContentDB.has_sprites(kind, type_name):
		# vehicles and cannons spawn UNMANNED beside the building for a
		# robot to man (Z-style)
		var vehicle := Spawner.spawn(get_parent(), kind, type_name, 0, spawn_pos)
		if vehicle and rally_point != Vector2.INF:
			vehicle.move_to(rally_point)



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
	add_to_group("all_buildings")
	if is_fort:
		add_to_group("buildings")
	# producers register for the facility quick bar
	var bdef := ContentDB.building_def(building_id)
	if (bdef != null and bdef.produces) or is_fort:
		add_to_group("facilities")
	if not is_bridge():
		set_solid_body(true, footprint_cells())


func _build_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = load(_texture_path(false))
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_art_size = _sprite.texture.get_size() if _sprite.texture else Vector2.ZERO
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

		# ONE flag per ZONE marks territory; the only building that flies
		# its own is the FORT (radar/repair/factories show ownership through
		# their zone's flag — the original never gave every building one)
		if is_fort and not is_bridge():
			_flag = AnimatedSprite2D.new()
			# x: the fort art's horizontal centre; y: just above the art's
			# top edge (fort node sits at the art top, others at the middle)
			_flag.position = Vector2(-8.0 + ts.x * 0.5,
				-12.0 if is_fort else -ts.y * 0.5 - 4.0)
			_flag.scale = Vector2.ONE  # native art scale, matching the fort art
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


## Mark this building's cells solid on both navigation grids — called by
## the map loader, the ONE place grids are mutated for buildings.
func apply_impassables(grid: AStarGrid2D, vgrid: AStarGrid2D) -> void:
	if is_bridge():
		return
	var def := ContentDB.building_def(building_id)
	if def == null or not def.solid:
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


## Texture location comes from the building def's `tex` key — new building
## types only add art + a content/buildings entry.
func _texture_path(destroyed: bool) -> String:
	if ContentDB.building_def(building_id) == null:
		return ""
	match ContentDB.building_def(building_id).tex:
		"fort_front":
			return "res://assets/z/buildings/fort/fort_%s_front%s.png" % [
				planet, "_destroyed" if destroyed else ""]
		"fort_back":
			return "res://assets/z/buildings/fort/fort_%s_back%s.png" % [
				planet, "_destroyed" if destroyed else ""]
		"bridge":
			return "res://assets/z/planets/bridge_%s.png" % planet
		var kind:
			if destroyed:
				return "res://assets/z/buildings/%s/base_destroyed_%s.png" % [kind, planet]
			return "res://assets/z/buildings/%s/base_%s.png" % [kind, planet]


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
		"rally_x": rally_point.x if rally_point != Vector2.INF else 0.0,
		"rally_y": rally_point.y if rally_point != Vector2.INF else 0.0,
		"has_rally": rally_point != Vector2.INF,
		"queue": queue.items.duplicate(),
	}


func apply_dict(d: Dictionary) -> void:
	if d.has("level"):
		level = clampi(int(d.level), level, 5)
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
		_rally_flag.scale = Vector2.ONE
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
	if Engine.is_editor_hint() or not alive:
		return
	if is_fort:
		return
	# non-fort buildings (radar, repair) follow their zone's owner so the
	# flag recolors on capture; factories override with their own loop
	var center := world_footprint().get_center()
	for z in MatchState.zones:
		if z.world_rect().has_point(center):
			if z.owner_team != owner_team:
				var was_player := owner_team == MatchState.player_team
				owner_team = z.owner_team
				team = owner_team
				update_flag(owner_team)
				if not was_player and owner_team == MatchState.player_team \
						and building_id == 2:
					Fx.announce("radar_activated")
			break
	_repair_tick(delta)


func is_bridge() -> bool:
	return building_id == 6 or building_id == 7


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
	if owner_team == MatchState.player_team:
		Fx.announce("starting_repair")
	unit.visible = false
	unit.velocity = Vector2.ZERO
	unit.move_target = Vector2.ZERO
	unit.waypoints = PackedVector2Array()
	unit.remove_from_group("selectable")
	unit.remove_from_group("units")
	# out of the world while inside (same contract as APC/garrison
	# cargo): not targetable through the shop walls, holds no territory
	unit.carried = true
	SelectionManager.drop_from_selection(unit)
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
		if owner_team == MatchState.player_team:
			Fx.announce("vehicle_repaired")
		done.visible = true
		done.carried = false
		done.add_to_group("selectable")
		done.add_to_group("units")
		done.global_position = world_footprint().get_center() + Vector2(0, 44)
		done.move_to(done.global_position + Vector2(0, 34))


func take_damage(amount: int) -> void:
	if not alive:
		return
	if is_bridge():
		_bridge_damage(amount)
		return
	hp -= amount
	if is_fort and team == MatchState.player_team:
		Fx.announce("fort_under_attack")  # forts only — factories have
		# their own distinct original voice lines
	# rapid-fire attackers restart this every hit — only start a new
	# flash when the previous one has fully faded, or the building
	# strobes white permanently
	if _sprite and _sprite.modulate == Color.WHITE:
		_sprite.modulate = Color(3, 3, 3)
		var tween := create_tween()
		tween.tween_property(_sprite, "modulate", Color.WHITE, 0.15)
	if _hp_bar:
		_hp_bar.region_rect.size.x = maxf(6.0,
			62.0 * clampf(float(hp) / float(max_hp), 0.0, 1.0))
		_hp_bar.visible = true
	if is_fort and team == MatchState.player_team and hp > 0 \
			and float(hp) / float(max_hp) < 0.35:
		Fx.announce("youre_losing")
	if hp <= 0:
		alive = false
		_death_visuals()
		if is_fort:
			GameState.report_fort_destroyed(team)


## Ruin look + bookkeeping shared by battle death and the elimination
## cascade: destroyed texture, overlays/flag/HP bar away, deselect.
func _death_visuals() -> void:
	died.emit()
	remove_from_group("buildings")
	remove_from_group("facilities")
	SelectionManager.drop_from_selection(self)
	if has_method("kill_garrison"):
		call("kill_garrison")
	Fx.destroyed(visual_center())
	if _sprite:
		_sprite.texture = load(_texture_path(true))
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


func _bridge_damage(amount: int) -> void:
	hp -= amount
	if _sprite:
		_sprite.modulate = Color(3, 3, 3)
		var tween := create_tween()
		tween.tween_property(_sprite, "modulate", Color(0.35, 0.35, 0.35), 0.3)
	if hp > 0:
		return
	hp = 0
	Fx.destroyed(world_footprint().get_center())
	for cell in bridge_cells:
		if NavWorld.nav_grid:
			NavWorld.nav_grid.set_point_solid(cell, true)
		if NavWorld.vehicle_grid:
			NavWorld.vehicle_grid.set_point_solid(cell, true)
	set_solid_body(true, bridge_cells)
	_sprite.modulate = Color(0.35, 0.35, 0.35)


## Crane repair: restores a destroyed bridge (or patches a damaged one).
func repair_by(amount: int) -> void:
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
			if NavWorld.nav_grid:
				NavWorld.nav_grid.set_point_solid(cell, false)
			if NavWorld.vehicle_grid:
				NavWorld.vehicle_grid.set_point_solid(cell, false)
		# the rubble physics wall must go with the nav solids — grids
		# saying "walkable" while move_and_slide still hits invisible
		# rubble jams every unit sent across
		set_solid_body(false)
		_sprite.modulate = Color.WHITE
		Fx.play("spark", world_footprint().get_center())
