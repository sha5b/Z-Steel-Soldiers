class_name MiniMap
extends Control
## Radar minimap (bottom-left): downscaled terrain with zone ownership
## tint, live unit/building blips, camera viewport box. Left-click/drag
## moves the camera, right-click issues a move order there.

signal move_order(world_position: Vector2)

const MINI_SCALE := 3.0  # minimap pixels per map tile
const TEAM_MINI_COLORS := {
	1: Color(1.0, 0.30, 0.25), 2: Color(0.35, 0.55, 1.0),
	3: Color(0.35, 0.85, 0.35), 4: Color(1.0, 0.9, 0.3),
}

var map_size := Vector2i(64, 86)
var terrain_image: Image
var _terrain_tex: ImageTexture


func build(data: Dictionary, tileset: Texture2D) -> void:
	map_size = Vector2i(int(data.width), int(data.height))
	custom_minimum_size = Vector2(map_size) * MINI_SCALE
	terrain_image = Image.create(map_size.x, map_size.y, false, Image.FORMAT_RGBA8)
	var palette: Image = tileset.get_image()
	for y in map_size.y:
		for x in map_size.x:
			var index: int = data.tiles[y * map_size.x + x]
			var pc := (index % 20) * 16 + 8
			var pr := (index / 20) * 16 + 8
			terrain_image.set_pixel(x, y, palette.get_pixel(pc, pr))
	_terrain_tex = ImageTexture.create_from_image(terrain_image)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _terrain_tex == null:
		return
	draw_texture_rect(_terrain_tex, Rect2(Vector2.ZERO, Vector2(map_size) * MINI_SCALE), false)
	# zone ownership tint
	for z in GameState.zones:
		var color := Color(0.8, 0.8, 0.8, 0.12)
		if z.owner_team != 0:
			color = TEAM_MINI_COLORS.get(z.owner_team, color)
			color.a = 0.22
		var zr: Rect2 = z.world_rect()
		draw_rect(Rect2(zr.position / 16.0 * MINI_SCALE, zr.size / 16.0 * MINI_SCALE), color)
	# buildings
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is Node2D and b.alive:
			_blip(b.global_position, TEAM_MINI_COLORS.get(b.team, Color.GRAY), 2.0)
	# units
	for u in get_tree().get_nodes_in_group("units"):
		if u is Node2D and u.alive:
			_blip(u.global_position, TEAM_MINI_COLORS.get(u.team, Color(0.6, 0.6, 0.6)), 1.5)
	# camera viewport
	var vp := get_viewport()
	if vp:
		var world_rect: Rect2 = SelectionManager.screen_to_world_rect(vp.get_visible_rect())
		var r := Rect2(world_rect.position / 16.0 * MINI_SCALE, world_rect.size / 16.0 * MINI_SCALE)
		r = r.intersection(Rect2(Vector2.ZERO, Vector2(map_size) * MINI_SCALE))
		draw_rect(r, Color(1, 1, 1, 0.8), false, 1.5)


func _blip(world_pos: Vector2, color: Color, size_px: float) -> void:
	var p := world_pos / 16.0 * MINI_SCALE
	draw_rect(Rect2(p - Vector2(size_px, size_px) * 0.5, Vector2(size_px, size_px)), color)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			var world: Vector2 = (mb.position / MINI_SCALE) * 16.0
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_move_camera(world)
			elif mb.pressed:
				move_order.emit(world)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mm := event as InputEventMouseMotion
		_move_camera((mm.position / MINI_SCALE) * 16.0)


func _move_camera(world: Vector2) -> void:
	var vp := get_viewport()
	if vp:
		var camera := vp.get_camera_2d()
		if camera:
			camera.position = world
