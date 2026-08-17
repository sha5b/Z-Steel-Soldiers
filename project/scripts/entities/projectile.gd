class_name Projectile
extends Node2D
## A travelling shot (shell, missile...). Flies from `from` to `to`, shows
## an animated sprite when the named effect has frames on disk, otherwise
## draws a short tracer line. On arrival it plays the impact effect and
## calls `on_hit` — damage application is the caller's business.
## Spawn through Fx.shell(...).

var speed := 260.0
var impact_effect := "impact"

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _dir := Vector2.RIGHT
var _travelled := 0.0
var _length := 0.0
var _on_hit: Callable
var sprite_name := ""


func setup(from: Vector2, to: Vector2, on_hit: Callable) -> void:
	_from = from
	_to = to
	_on_hit = on_hit
	_dir = (to - from).normalized()
	_length = from.distance_to(to)
	global_position = from
	rotation = _dir.angle()


func _ready() -> void:
	z_index = 5  # above units, below explosions
	if sprite_name != "":
		var def: Dictionary = ContentDB.effect_def(sprite_name)
		var frames := AnimLibrary.effect_frames(String(def.get("dir", "")), sprite_name, 12.0)
		if frames != null and frames.has_animation("fx"):
			var sprite := AnimatedSprite2D.new()
			sprite.sprite_frames = frames
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			add_child(sprite)
			sprite.play("fx")


func _process(delta: float) -> void:
	_travelled += speed * delta
	if _travelled >= _length:
		global_position = _to
		Fx.play(impact_effect, _to)
		_on_hit.call_deferred()
		queue_free()
	else:
		global_position = _from + _dir * _travelled
	queue_redraw()


func _draw() -> void:
	# tracer fallback when no sprite frames exist
	draw_line(Vector2(-7, 0), Vector2.ZERO, Color(1.0, 0.9, 0.5, 0.9), 1.5)
	draw_circle(Vector2.ZERO, 1.5, Color(1.0, 1.0, 0.8))
