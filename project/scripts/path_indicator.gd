class_name PathIndicator
extends Node2D
## Waypoint route shown when the player issues an order — the ORIGINAL
## way (zod ZObject::DoRenderWaypoints / RenderWaypointLine): near-white
## 2x2 squares every 4px that MARCH along the travel direction (10 Hz,
## 0.1s per step), and the animated `placed` cursor art (the neutral
## PLACED_C marker) sitting on the final waypoint. Fades and frees.

const DOT_STEP := 4.0       # zod: dots laid every 4 px
const DOT_SIZE := 2.0       # zod: 2x2 fillrect
const DOT_COLOR := Color(170.0 / 255.0, 170.0 / 255.0, 170.0 / 255.0, 0.9)
const STEP_SECONDS := 0.1   # zod next_waypoint_time cadence
const FADE_AFTER := 1.6
const FADE_TIME := 0.9
const MARKER_FPS := 5.0     # zod cursor frames run 4 x 0.2s

static var _marker_cache := {}  # team -> SpriteFrames


var _segments := []  # [{from, to, dir}] — dots march per segment
var _end := Vector2.ZERO
var _t := 0.0


static func show_path(parent: Node, waypoints: PackedVector2Array) -> void:
	if parent == null or waypoints.is_empty():
		return
	var p := PathIndicator.new()
	var prev := Vector2(waypoints[0])
	for i in range(1, waypoints.size()):
		var to := Vector2(waypoints[i])
		var seg := to - prev
		if seg.length() >= 1.0:
			p._segments.append({"from": prev, "to": to,
				"dir": seg.normalized()})
		prev = to
	p._end = prev
	parent.add_child(p)
	p.z_index = 50
	var tween := p.create_tween()
	tween.tween_interval(FADE_AFTER)
	tween.tween_property(p, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(p.queue_free)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var phase := int(_t / STEP_SECONDS) % int(DOT_STEP)
	for seg in _segments:
		var d := 0.0 + phase
		var dist: float = (seg.to - seg.from).length()
		while d < dist:
			draw_rect(Rect2(seg.from + seg.dir * d
					- Vector2(DOT_SIZE, DOT_SIZE) * 0.5,
					Vector2(DOT_SIZE, DOT_SIZE)), DOT_COLOR)
			d += DOT_STEP
	var marker := _marker_frames()
	if marker:
		var frame := int(_t * MARKER_FPS) % marker.get_frame_count("placed")
		draw_texture(marker.get_frame_texture("placed", frame),
			_end - marker.get_frame_texture("placed", frame).get_size() * 0.5)


static func _marker_frames() -> SpriteFrames:
	if _marker_cache.has("placed"):
		return _marker_cache["placed"]
	var frames := SpriteFrames.new()
	frames.add_animation("placed")
	frames.set_animation_speed("placed", MARKER_FPS)
	var n := 0
	while true:
		var path := "res://assets/z/ui/cursor/placed_n%02d.png" % n
		if not ResourceLoader.exists(path):
			break
		frames.add_frame("placed", load(path))
		n += 1
	if n == 0:
		frames = null
	_marker_cache["placed"] = frames
	return frames
