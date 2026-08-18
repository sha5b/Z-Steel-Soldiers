class_name EffectPlayer
extends Node2D
## One-shot visual effect. Plays sprite frames from assets/z/effects/<name>/
## when they exist, otherwise a native CPUParticles2D burst configured from
## the effect def. Frees itself when finished. Spawn via Fx.play(...).

var _def: Dictionary = {}


func setup(def: Dictionary) -> void:
	_def = def


func _ready() -> void:
	z_index = 6  # above units and projectiles
	var fx_name := String(_def.get("_name", "fx"))
	var frames := AnimLibrary.effect_frames(String(_def.get("dir", "")), fx_name,
		float(_def.get("fps", 10.0)))
	var scale_factor := float(_def.get("scale", 1.0))
	if frames != null and frames.has_animation("fx"):
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = frames
		sprite.scale = Vector2(2.0, 2.0) * scale_factor
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
		sprite.animation_finished.connect(queue_free)
		sprite.play("fx")
		return
	# particle fallback: a short radial burst in the def's colour
	var burst := CPUParticles2D.new()
	burst.emitting = true
	burst.one_shot = true
	burst.amount = 18
	burst.lifetime = 0.45
	burst.explosiveness = 0.95
	burst.direction = Vector2.UP
	burst.spread = 180.0
	burst.gravity = Vector2(0, 240)
	burst.initial_velocity_min = 60.0 * scale_factor
	burst.initial_velocity_max = 160.0 * scale_factor
	burst.scale_amount_min = 1.5 * scale_factor
	burst.scale_amount_max = 3.0 * scale_factor
	burst.color = _def.get("color", Color(1.0, 0.8, 0.4))
	add_child(burst)
	var timer := Timer.new()
	timer.wait_time = burst.lifetime + 0.2
	timer.one_shot = true
	add_child(timer)
	timer.timeout.connect(queue_free)
	timer.start()
