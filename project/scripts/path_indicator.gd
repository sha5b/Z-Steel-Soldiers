class_name PathIndicator
extends Node2D
## Red-dotted route shown briefly when the player issues a move order,
## like the original Z. Fades and frees itself.

const DOT_SPACING := 12.0
const DOT_COLOR := Color(0.95, 0.15, 0.1, 0.9)
const FADE_AFTER := 1.6
const FADE_TIME := 0.9


static func show_path(parent: Node, waypoints: PackedVector2Array) -> void:
	if parent == null or waypoints.is_empty():
		return
	var p := PathIndicator.new()
	for i in waypoints.size() - 1:
		p._dots.append_array(_segment(waypoints[i], waypoints[i + 1]))
	p._dots.append(waypoints[waypoints.size() - 1])
	parent.add_child(p)
	p.z_index = 50
	var tween := p.create_tween()
	tween.tween_interval(FADE_AFTER)
	tween.tween_property(p, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(p.queue_free)


static func _segment(from: Vector2, to: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var dir := (to - from)
	var len := dir.length()
	if len < 1.0:
		return out
	dir /= len
	var d := 0.0
	while d < len:
		out.append(from + dir * d)
		d += DOT_SPACING
	return out


var _dots := PackedVector2Array()


func _draw() -> void:
	for dot in _dots:
		draw_circle(dot, 2.4, DOT_COLOR)
	draw_circle(_dots[_dots.size() - 1], 4.0, Color(1, 1, 1, 0.8))
