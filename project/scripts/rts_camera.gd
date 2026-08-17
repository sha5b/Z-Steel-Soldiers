class_name RtsCamera
extends Node3D
## RTS camera rig: yaw pivot + boom + Camera3D.
## Edge pan, WASD/arrow pan, wheel zoom, optional Q/E rotation.

const PAN_SPEED := 60.0
const EDGE_MARGIN := 24.0
const EDGE_SPEED := 900.0
const ZOOM_MIN := 20.0
const ZOOM_MAX := 220.0
const ZOOM_STEP := 18.0

@export var bounds := Rect2(0.0, 0.0, 256.0, 256.0)
@export var enable_edge_pan := true

var _zoom := 90.0
var _yaw := 0.0

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(ZOOM_MIN, _zoom - ZOOM_STEP)
			_apply()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(ZOOM_MAX, _zoom + ZOOM_STEP)
			_apply()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_Q:
			_yaw -= TAU / 12.0
			_apply()
		elif event.keycode == KEY_E:
			_yaw += TAU / 12.0
			_apply()


func _process(delta: float) -> void:
	var dir := Input.get_vector("cam_left", "cam_right", "cam_forward", "cam_back")
	var move := Vector3(dir.x, 0.0, dir.y) * PAN_SPEED * delta * (_zoom / 90.0)
	if enable_edge_pan:
		var vp := get_viewport().get_visible_rect()
		var m := get_viewport().get_mouse_position()
		if m.x < EDGE_MARGIN:
			move.x -= EDGE_SPEED * delta * (_zoom / 90.0)
		elif m.x > vp.size.x - EDGE_MARGIN:
			move.x += EDGE_SPEED * delta * (_zoom / 90.0)
		if m.y < EDGE_MARGIN:
			move.z -= EDGE_SPEED * delta * (_zoom / 90.0)
		elif m.y > vp.size.y - EDGE_MARGIN:
			move.z += EDGE_SPEED * delta * (_zoom / 90.0)
	if move != Vector3.ZERO:
		# pan in yaw space so screen-relative keys stay intuitive
		var t := transform
		t.origin += (t.basis * move)
		t.origin.x = clampf(t.origin.x, bounds.position.x, bounds.end.x)
		t.origin.z = clampf(t.origin.z, bounds.position.y, bounds.end.y)
		transform = t


func _apply() -> void:
	rotation.y = _yaw
	camera.position = Vector3(0.0, _zoom * 0.85, _zoom * 0.55)
	camera.look_at(global_position + Vector3(0.0, -0.1, 0.2), Vector3.UP)
