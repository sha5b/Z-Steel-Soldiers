class_name PathIndicator
extends Node2D
## Waypoint route shown when the player issues an order — the ORIGINAL
## way (zod ZObject::DoRenderWaypoints / RenderWaypointLine): near-white
## 2x2 squares every 4px that MARCH along the travel direction (10 Hz,
## 0.1s per step), and an animated NEUTRAL cursor marker sitting on the
## final waypoint. Fades and frees.
##
## The marker names the ORDER: the pack ships eight of them (placed,
## attacked, entered, cannoned, repaired, grabbed, grenaded, exited) and
## only `placed` was ever converted, so every order — attack, board,
## crane work — confirmed with the plain move marker.

const DOT_STEP := 4.0       # zod: dots laid every 4 px
const DOT_SIZE := 2.0       # zod: 2x2 fillrect
const DOT_COLOR := Color(170.0 / 255.0, 170.0 / 255.0, 170.0 / 255.0, 0.9)
const STEP_SECONDS := 0.1   # zod next_waypoint_time cadence
const FADE_AFTER := 1.6
const FADE_TIME := 0.9
const MARKER_FPS := 5.0     # zod cursor frames run 4 x 0.2s

static var _marker_cache := {}  # marker name -> SpriteFrames


var _segments := []  # [{from, to, dir}] — dots march per segment
var _end := Vector2.ZERO
var _marker := "placed"
var _t := 0.0


static func show_path(parent: Node, waypoints: PackedVector2Array,
		marker := "placed") -> void:
	if parent == null or waypoints.is_empty():
		return
	var p := PathIndicator.new()
	p._marker = marker
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
	var marker := _marker_frames(_marker)
	if marker:
		var frame := int(_t * MARKER_FPS) % marker.get_frame_count("fx")
		draw_texture(marker.get_frame_texture("fx", frame),
			_end - marker.get_frame_texture("fx", frame).get_size() * 0.5)


## Just the marker, no route: the dismount action has no path to draw.
static func show_marker(parent: Node, world_pos: Vector2, marker: String) -> void:
	if parent == null or _marker_frames(marker) == null:
		return
	var p := PathIndicator.new()
	p._marker = marker
	p._end = world_pos
	parent.add_child(p)
	p.z_index = 50
	var tween := p.create_tween()
	tween.tween_interval(FADE_AFTER * 0.5)
	tween.tween_property(p, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(p.queue_free)


## Frames for one neutral marker set, cached. Falls back to `placed` so
## an unconverted set still confirms the order.
static func _marker_frames(marker: String) -> SpriteFrames:
	if _marker_cache.has(marker):
		return _marker_cache[marker]
	var frames := SpriteFrames.new()
	frames.add_animation("fx")
	frames.set_animation_speed("fx", MARKER_FPS)
	var n := 0
	while true:
		var path := "res://assets/z/ui/cursor/%s_n%02d.png" % [marker, n]
		if not ResourceLoader.exists(path):
			break
		frames.add_frame("fx", load(path))
		n += 1
	var out: SpriteFrames = frames if n > 0 else null
	if out == null and marker != "placed":
		out = _marker_frames("placed")
	_marker_cache[marker] = out
	return out
