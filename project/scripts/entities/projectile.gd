class_name Projectile
extends Node2D
## A travelling shot visual (shell, missile...). PURE PRESENTATION: flies
## from `from` to `to`, shows an animated sprite when the named effect has
## frames on disk, otherwise draws a short tracer line, and plays the
## impact effect on arrival. Damage timing belongs to ShellSolver —
## spawn the visual through Fx.shell(...).

var speed := 260.0
var impact_effect := "impact"
var texture: Texture2D = null  # single static sprite (e.g. the tank shell)

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _dir := Vector2.RIGHT
var _travelled := 0.0
var _length := 0.0


func setup(from: Vector2, to: Vector2) -> void:
	_from = from
	_to = to
	_dir = (to - from).normalized()
	_length = from.distance_to(to)
	global_position = from
	rotation = _dir.angle()


func _ready() -> void:
	z_index = 5  # above units, below explosions
	if texture != null:
		var shell := Sprite2D.new()
		shell.texture = texture
		shell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(shell)


func _process(delta: float) -> void:
	_travelled += speed * delta
	if _travelled >= _length:
		global_position = _to
		Fx.play(impact_effect, _to)
		queue_free()
	else:
		global_position = _from + _dir * _travelled
	queue_redraw()


func _draw() -> void:
	# tracer fallback when no sprite frames exist
	draw_line(Vector2(-7, 0), Vector2.ZERO, Color(1.0, 0.9, 0.5, 0.9), 1.5)
	draw_circle(Vector2.ZERO, 1.5, Color(1.0, 1.0, 0.8))
