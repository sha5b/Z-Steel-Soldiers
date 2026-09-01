class_name PerfOverlay
extends Label
## F3 debug readout — the engine's OWN numbers, no custom timing code:
## frame rate, per-frame callback cost, object/node counts, draw calls.
## Hidden until F3; updates 4x a second so an open overlay costs almost
## nothing and a closed one costs nothing at all. Tuning fodder for the
## performance-sensitive systems (sprite caches, polyphonic audio, RVO,
## the AI's walk distances): measure before and after.

const UPDATE_SECONDS := 0.25

var _accum := 0.0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(8.0, 8.0)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed \
			and (event as InputEventKey).keycode == KEY_F3:
		visible = not visible


func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum < UPDATE_SECONDS:
		return
	_accum = 0.0
	text = "\n".join([
		"fps %d" % Engine.get_frames_per_second(),
		"process %.2f ms   physics %.2f ms" % [
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0],
		"objects %d   nodes %d" % [
			int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))],
		"draw calls %d   primitives %d" % [
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))],
	])
