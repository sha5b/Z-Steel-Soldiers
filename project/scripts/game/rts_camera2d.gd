class_name RtsCamera2D
extends Camera2D
## RTS camera: edge pan, WASD/arrow pan, wheel zoom. Pixel-friendly.

const PAN_SPEED := 420.0
const EDGE_MARGIN := 24.0
const ZOOM_MIN := 0.35
const ZOOM_MAX := 2.5
const ZOOM_STEP := 1.15

@export var bounds := Rect2(0.0, 0.0, 1280.0, 1536.0)
@export var enable_edge_pan := true


func _ready() -> void:
	zoom = Vector2(0.7, 0.7)
	position_smoothing_enabled = true
	make_current()


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
	var move := Vector2(dir.x, dir.y) * PAN_SPEED * delta / zoom.x
	if enable_edge_pan:
		var vp := get_viewport().get_visible_rect()
		var m := get_viewport().get_mouse_position()
		if m.x < EDGE_MARGIN:
			move.x -= PAN_SPEED * delta / zoom.x
		elif m.x > vp.size.x - EDGE_MARGIN:
			move.x += PAN_SPEED * delta / zoom.x
		if m.y < EDGE_MARGIN:
			move.y -= PAN_SPEED * delta / zoom.x
		elif m.y > vp.size.y - EDGE_MARGIN:
			move.y += PAN_SPEED * delta / zoom.x
	position = Vector2(
		clampf(position.x + move.x, bounds.position.x, bounds.end.x),
		clampf(position.y + move.y, bounds.position.y, bounds.end.y))
