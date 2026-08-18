class_name MiniMap
extends Control
## Radar minimap, fully generated from the map data: one Image with a
## pixel per tile (ground/water/zone-tint colours baked in), redrawn only
## when a zone changes owner. Blips and the camera box are drawn on top
## each frame. Left-click/drag moves the camera, right-click issues a
## move order (see test_map_2d wiring).

signal move_order(world_position: Vector2)

const GROUND := Color(0.16, 0.20, 0.13)
const WATER := Color(0.05, 0.10, 0.22)
const PANEL_BG := Color(0.05, 0.06, 0.05, 0.9)
const PANEL_EDGE := Color(0.35, 0.38, 0.3)
const ZONE_TINT_WEIGHT := 0.4
const PAD := 2.0  # panel edge inset
const ZONE_SYNC_SECONDS := 0.5

var map_size := Vector2i(64, 86)

var _texture: ImageTexture
var _image: Image
var _water: PackedByteArray
var _map_rect := Rect2()      # panel-space rect the map texture draws into
var _owners: Array = []       # last-baked zone owners (change detection)
var _sync_accum := 0.0


func build(data: Dictionary, _tileset: Texture2D) -> void:
	map_size = Vector2i(int(data.width), int(data.height))
	_water = _water_mask(data)
	_owners = []
	_rebuild_image()
	_recompute_map_rect()


func _water_mask(data: Dictionary) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(map_size.x * map_size.y)
	if not data.has("tiles"):
		return out
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/tilesets/tileinfo_%s.json" % String(data.get("terrain", "desert"))))
	var info: Dictionary = parsed if parsed is Dictionary else {}
	for i in map_size.x * map_size.y:
		var entry: Array = info.get(str(data.tiles[i]), [false, true])
		out[i] = 1 if bool(entry[0]) else 0
	return out


## Zone ownership tint, baked into the texture pixels.
func _bake_zone_tints() -> void:
	for z in MatchState.zones:
		var zone: Zone = z as Zone
		if zone == null:
			continue
		var r: Rect2i = zone.zone_rect.intersection(Rect2i(Vector2i.ZERO, map_size))
		var tint: Color = Teams.minimap_color(zone.owner_team)
		for y in r.size.y:
			for x in r.size.x:
				var p := r.position + Vector2i(x, y)
				_image.set_pixel(p.x, p.y, _image.get_pixel(p.x, p.y).lerp(tint, ZONE_TINT_WEIGHT))


func _refresh_owners() -> void:
	var owners := []
	for z in MatchState.zones:
		owners.append(z.owner_team)
	if owners == _owners:
		return
	_owners = owners
	_rebuild_image()


func _rebuild_image() -> void:
	_image = Image.create(map_size.x, map_size.y, false, Image.FORMAT_RGBA8)
	for y in map_size.y:
		for x in map_size.x:
			_image.set_pixel(x, y, WATER if _water[y * map_size.x + x] else GROUND)
	_bake_zone_tints()
	if _texture:
		_texture.update(_image)
	else:
		_texture = ImageTexture.create_from_image(_image)


func _recompute_map_rect() -> void:
	var inner := Rect2(Vector2(PAD, PAD), size - Vector2(PAD, PAD) * 2.0)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	var aspect := float(map_size.x) / float(map_size.y)
	var map_size_px := inner.size
	if map_size_px.x / map_size_px.y > aspect:
		map_size_px.x = map_size_px.y * aspect
	else:
		map_size_px.y = map_size_px.x / aspect
	_map_rect = Rect2(inner.position + (inner.size - map_size_px) * 0.5, map_size_px)


func _process(delta: float) -> void:
	_sync_accum += delta
	if _sync_accum >= ZONE_SYNC_SECONDS:
		_sync_accum = 0.0
		_refresh_owners()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PANEL_BG)
	draw_rect(Rect2(Vector2.ZERO, size), PANEL_EDGE, false, 1.0)
	if _texture == null or _map_rect.size == Vector2.ZERO:
		return
	draw_texture_rect(_texture, _map_rect, false)
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is Node2D and b.alive:
			_blip(b.global_position, Teams.minimap_color(b.team), 3.0)
	# enemy intel needs a radar station (original Z) — own units always show
	var radar = _player_has_radar()
	for u in UnitRegistry.world_units():
		if u.team != MatchState.player_team and not radar:
			continue
		_blip(u.global_position, Teams.minimap_color(u.team), 2.0)
	# camera viewport in world space (works under stretch + zoom)
	var xform: Transform2D = get_viewport().get_canvas_transform()
	var world_rect: Rect2 = xform.affine_inverse() * get_viewport().get_visible_rect()
	var r := Rect2(_to_panel(world_rect.position),
		world_rect.size / (Vector2(map_size) * 16.0) * _map_rect.size)
	draw_rect(r, Color(1, 1, 1, 0.85), false, 1.0)


func _player_has_radar() -> bool:
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is Building2D and b.alive and b.building_id == 2 \
				and b.owner_team == MatchState.player_team:
			return true
	return false


func _to_panel(world: Vector2) -> Vector2:
	return _map_rect.position + world / (Vector2(map_size) * 16.0) * _map_rect.size


func _to_world(panel_pos: Vector2) -> Vector2:
	var local: Vector2 = (panel_pos - _map_rect.position) / _map_rect.size
	return local.clamp(Vector2.ZERO, Vector2.ONE) * Vector2(map_size) * 16.0


func _blip(world_pos: Vector2, color: Color, size_px: float) -> void:
	var p := _to_panel(world_pos)
	if not _map_rect.grow(2.0).has_point(p):
		return
	draw_rect(Rect2(p - Vector2(size_px, size_px) * 0.5, Vector2(size_px, size_px)), color)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_move_camera(_to_world(mb.position))
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			move_order.emit(_to_world(mb.position))
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_move_camera(_to_world((event as InputEventMouseMotion).position))


func _move_camera(world: Vector2) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera is RtsCamera2D:
		(camera as RtsCamera2D).pan_to(world)
	elif camera:
		camera.position = world
