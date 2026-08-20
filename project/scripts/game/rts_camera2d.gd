class_name RtsCamera2D
extends Camera2D
## RTS camera: edge pan, WASD/arrow pan, wheel zoom. Pixel-friendly:
## the position always lands on whole SCREEN pixels — with NEAREST
## filtering and a fractional zoom, un-snapped positions resample the
## terrain differently every frame and the ground shimmers/flickers
## while panning (the classic Camera2D caveat: project-level
## snap_2d_transforms_to_pixel does NOT snap the canvas transform).

const PAN_SPEED := 420.0
const EDGE_MARGIN := 24.0
const ZOOM_MIN := 0.35
const ZOOM_MAX := 2.5
const ZOOM_STEP := 1.15

@export var bounds := Rect2(0.0, 0.0, 1280.0, 1536.0)
@export var enable_edge_pan := true


func _ready() -> void:
	# 640x480 base viewport: 1.4 keeps the same world view the old
	# 1280x720 canvas had at 0.7
	zoom = Vector2(1.4, 1.4)
	make_current()
	_sync_view_offset()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(1.0 / ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(ZOOM_STEP)


func _zoom_by(factor: float) -> void:
	var z: float = clampf(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(z, z)


func _process(delta: float) -> void:
	var dir := Input.get_vector("cam_left", "cam_right", "cam_forward", "cam_back")
	var move := dir * PAN_SPEED * delta / zoom.x
	if enable_edge_pan:
		# the WORLD's edge, not the window's: with the HUD chrome down the
		# right side and along the bottom, a cursor heading for the
		# sidebar or the Menu button used to shove the camera the moment
		# it crossed the window margin
		var view := HudFrame.view_rect()
		var m := get_viewport().get_mouse_position()
		if view.has_point(m):
			if m.x < view.position.x + EDGE_MARGIN:
				move.x -= PAN_SPEED * delta / zoom.x
			elif m.x > view.end.x - EDGE_MARGIN:
				move.x += PAN_SPEED * delta / zoom.x
			if m.y < view.position.y + EDGE_MARGIN:
				move.y -= PAN_SPEED * delta / zoom.x
			elif m.y > view.end.y - EDGE_MARGIN:
				move.y += PAN_SPEED * delta / zoom.x
	_sync_view_offset()
	_clamp_move(move)


## Jump (e.g. from the minimap) — same bounds as free panning.
func pan_to(world: Vector2) -> void:
	_clamp_move(world - position)


## Clamp the camera CENTER so the whole VIEW stays inside bounds; maps
## smaller than the view just centre themselves.
func _clamp_move(move: Vector2) -> void:
	var view := HudFrame.view_rect().size / zoom
	var half := view * 0.5
	var target := position + move
	var center := bounds.get_center()
	for axis in [Vector2.AXIS_X, Vector2.AXIS_Y]:
		var lo := bounds.position[axis] + half[axis]
		var hi := bounds.end[axis] - half[axis]
		if lo > hi:  # view larger than the map on this axis: centre it
			target[axis] = center[axis]
		else:
			target[axis] = clampf(target[axis], lo, hi)
	position = _snapped(target)


## The HUD chrome covers the right and bottom edges, so `position` — which
## Godot puts at the WINDOW's centre — would sit right of and below the
## middle of what the player can actually see. Offsetting by half the
## covered width/height re-centres the camera on the WORLD view, which is
## what "the screen centres on the unit you select" has to mean.
func _sync_view_offset() -> void:
	var vp := Vector2(get_viewport().get_visible_rect().size)
	var view := HudFrame.view_rect()
	offset = Vector2(vp.x - view.size.x, vp.y - view.size.y) * 0.5 / zoom


## Whole-SCREEN-pixel position: the same world texel always maps to the
## same screen pixel, so NEAREST sampling is stable frame to frame.
func _snapped(world: Vector2) -> Vector2:
	var s := zoom.x
	return Vector2(roundf(world.x * s) / s, roundf(world.y * s) / s)
