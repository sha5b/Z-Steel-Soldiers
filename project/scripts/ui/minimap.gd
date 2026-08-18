class_name MiniMap
extends Control
## Radar minimap (bottom-left), original Z style: everything is GENERATED
## by us — no pre-rendered terrain image. Solid ground vs water from the
## tileinfo tables, zone sectors tinted by owner, live blips, camera box —
## all scaled to fit inside the original per-planet backdrop frame.
## Left-click/drag moves the camera, right-click issues a move order.

signal move_order(world_position: Vector2)

const TEAM_MINI_COLORS := {
	1: Color(1.0, 0.30, 0.25), 2: Color(0.35, 0.55, 1.0),
	3: Color(0.35, 0.85, 0.35), 4: Color(1.0, 0.9, 0.3),
}
const GROUND := Color(0.16, 0.20, 0.13)
const WATER := Color(0.05, 0.10, 0.22)
const FRAME_PAD := 14.0  # inset inside the backdrop art

var map_size := Vector2i(64, 86)
var _water: PackedByteArray  # per-tile water mask, row-major
var _terrain := "desert"
var _backdrop: Texture2D
var _radar_rect := Rect2()


func build(data: Dictionary, _tileset: Texture2D) -> void:
	map_size = Vector2i(int(data.width), int(data.height))
	_terrain = String(data.get("terrain", "desert"))
	_water = _water_mask(data)
	var bd := "res://assets/z/ui/hud/backdrop_%s.png" % _terrain
	if not ResourceLoader.exists(bd):
		bd = "res://assets/z/ui/hud/backdrop_desert.png"
	if ResourceLoader.exists(bd):
		_backdrop = load(bd)
	_layout()


func _water_mask(data: Dictionary) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(map_size.x * map_size.y)
	if not data.has("tiles"):
		return out
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/tilesets/tileinfo_%s.json" % _terrain))
	var info: Dictionary = parsed if parsed is Dictionary else {}
	for i in map_size.x * map_size.y:
		var index: int = data.tiles[i]
		var entry: Array = info.get(str(index), [false, true])
		out[i] = 1 if bool(entry[0]) else 0
	return out


## Radar area = our rect minus the backdrop padding, aspect-preserving.
func _layout() -> void:
	var inner := Rect2(Vector2(FRAME_PAD, FRAME_PAD),
		size - Vector2(FRAME_PAD, FRAME_PAD) * 2.0)
	if _backdrop:
		# backdrop art at its natural 1x size on the 640x480 canvas
		var bs: Vector2 = _backdrop.get_size()
		size = bs
		var pad := FRAME_PAD
		inner = Rect2(Vector2(pad, pad), bs - Vector2(pad, pad) * 2.0)
	var aspect := float(map_size.x) / float(map_size.y)
	var radar := inner.size
	if radar.x / radar.y > aspect:
		radar.x = radar.y * aspect
	else:
		radar.y = radar.x / aspect
	_radar_rect = Rect2(inner.position + (inner.size - radar) * 0.5, radar)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _backdrop:
		draw_texture_rect(_backdrop, Rect2(Vector2.ZERO, size), false)
	elif _radar_rect.size == Vector2.ZERO:
		return
	# generated ground/water image, redrawn only when ownership changes is
	# overkill — draw solid ground then water cells as 1px rects
	draw_rect(_radar_rect, GROUND)
	var s := _radar_rect.size / Vector2(map_size)
	for y in map_size.y:
		var row := y * map_size.x
		var x := 0
		while x < map_size.x:
			if _water[row + x]:
				var run := x
				while run < map_size.x and _water[row + run]:
					run += 1
				draw_rect(Rect2(_radar_rect.position + Vector2(x, y) * s,
					Vector2(run - x, 1) * s), WATER)
				x = run
			else:
				x += 1
	# zone ownership tint
	for z in GameState.zones:
		var color := Color(0.8, 0.8, 0.8, 0.15)
		if z.owner_team != 0:
			color = Color(TEAM_MINI_COLORS.get(z.owner_team, color))
			color.a = 0.22
		var zr: Rect2 = z.world_rect()
		draw_rect(Rect2(_to_radar(zr.position), zr.size / Vector2(map_size) * _radar_rect.size), color)
	# buildings
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is Node2D and b.alive:
			_blip(b.global_position, TEAM_MINI_COLORS.get(b.team, Color.GRAY), 3.0)
	# units
	for u in get_tree().get_nodes_in_group("units"):
		if u is Node2D and u.alive:
			_blip(u.global_position, TEAM_MINI_COLORS.get(u.team, Color(0.6, 0.6, 0.6)), 2.0)
	# camera viewport
	var vp := get_viewport()
	if vp:
		var world_rect: Rect2 = SelectionManager.screen_to_world_rect(vp.get_visible_rect())
		var r := Rect2(_to_radar(world_rect.position),
			world_rect.size / Vector2(map_size) * _radar_rect.size)
		r = r.intersection(_radar_rect.grow(1.0))
		draw_rect(r, Color(1, 1, 1, 0.8), false, 1.5)


func _to_radar(world: Vector2) -> Vector2:
	return _radar_rect.position + world / (Vector2(map_size) * 16.0) * _radar_rect.size


func _blip(world_pos: Vector2, color: Color, size_px: float) -> void:
	var p := _to_radar(world_pos)
	draw_rect(Rect2(p - Vector2(size_px, size_px) * 0.5, Vector2(size_px, size_px)), color)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			var world: Vector2 = _to_world(mb.position)
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_move_camera(world)
			elif mb.pressed:
				move_order.emit(world)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mm := event as InputEventMouseMotion
		_move_camera(_to_world(mm.position))


func _to_world(radar_pos: Vector2) -> Vector2:
	var local: Vector2 = (radar_pos - _radar_rect.position) / _radar_rect.size
	return local.clamp(Vector2.ZERO, Vector2.ONE) * Vector2(map_size) * 16.0


func _move_camera(world: Vector2) -> void:
	var vp := get_viewport()
	if vp:
		var camera := vp.get_camera_2d()
		if camera:
			camera.position = world
