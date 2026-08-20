class_name MiniMap
extends Control
## Radar minimap, fully generated from the map data: one Image with a
## pixel per tile in the planet sheet's own terrain colours (shared with
## the menu previews — see MapPreview), zone-tint ownership baked in,
## redrawn only when a zone changes owner. Blips and the camera box are
## drawn on top each frame. Left-click/drag moves the camera, right-click
## issues a move order (see match.gd wiring).

signal move_order(world_position: Vector2)

const PANEL_BG := Color(0.05, 0.06, 0.05, 0.9)
const PANEL_EDGE := Color(0.35, 0.38, 0.3)
const ZONE_TINT_WEIGHT := 0.4
const PAD := 2.0  # panel edge inset

var map_size := Vector2i(64, 86)

var _texture: ImageTexture
var _image: Image
var _base: Image               # terrain colours straight from the sheet
var _map_rect := Rect2()      # panel-space rect the map texture draws into
var _owners: Array = []       # last-baked zone owners (change detection)


func build(data: Dictionary, _tileset: Texture2D) -> void:
	map_size = Vector2i(int(data.width), int(data.height))
	_base = MapPreview.base_image(data)
	_owners = []
	_rebuild_image()
	_recompute_map_rect()
	# zone tints rebake on the capture signal — this used to poll every
	# 0.5s to detect ownership changes
	# zone_captured carries the capturing team; _refresh_owners re-bakes
	# the whole overlay and does not need it. Connecting the 0-arg method
	# to a 1-arg signal made EVERY capture throw
	# "Method expected 0 argument(s), but called with 1" instead of
	# refreshing, so the minimap's ownership tint never updated in play.
	MatchState.current.zone_captured.connect(func(_team): _refresh_owners())


## Zone ownership tint, baked into the texture pixels.
func _bake_zone_tints() -> void:
	for z in MatchState.current.zones:
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
	for z in MatchState.current.zones:
		owners.append(z.owner_team)
	if owners == _owners:
		return
	_owners = owners
	_rebuild_image()


func _rebuild_image() -> void:
	_image = _base.duplicate()
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


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PANEL_BG)
	draw_rect(Rect2(Vector2.ZERO, size), PANEL_EDGE, false, 1.0)
	if _texture == null or _map_rect.size == Vector2.ZERO:
		return
	draw_texture_rect(_texture, _map_rect, false)
	for b in get_tree().get_nodes_in_group(Groups.BUILDINGS):
		if b is Node2D and b.alive:
			# the fort node sits at the art's TOP edge (Y-sort lift) —
			# blip the visual centre, which is where the structure is
			_blip(b.visual_center(), Teams.minimap_color(b.team), 3.0)
	# enemy intel needs a radar station (original Z) — own units always show
	var radar = _player_has_radar()
	for u in UnitRegistry.current.world_units():
		if u.team != MatchState.current.player_team and not radar:
			continue
		_blip(u.global_position, Teams.minimap_color(u.team), 2.0)
	# camera viewport in world space (works under stretch + zoom)
	var xform: Transform2D = get_viewport().get_canvas_transform()
	var world_rect: Rect2 = xform.affine_inverse() * get_viewport().get_visible_rect()
	var r := Rect2(_to_panel(world_rect.position),
		world_rect.size / (Vector2(map_size) * 16.0) * _map_rect.size)
	draw_rect(r, Color(1, 1, 1, 0.85), false, 1.0)


func _player_has_radar() -> bool:
	# EVERY building: radar sits in none of the narrower groups
	for b in BuildingRegistry.owned_by(MatchState.current.player_team):
		if b.building_id == 2:
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
