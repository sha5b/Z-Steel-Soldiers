class_name EffectPlayer
extends Node2D
## One-shot visual effect driven by an EffectDef resource. Plays sprite
## frames from the def's art folder when they exist, otherwise a native
## CPUParticles2D burst. Frees itself when finished. Spawn via Fx.play().
## Scale is relative to the 2x unit baseline; `grounded` effects are
## bottom-anchored so explosions rise from the spawn point (the original
## frames are tight-cropped to varying heights — centering them wobbles).

var _def: EffectDef
var _extra_scale := 1.0


func setup(def: EffectDef, extra_scale := 1.0) -> void:
	_def = def
	_extra_scale = extra_scale


func _ready() -> void:
	z_index = 6  # above units and projectiles
	# frames are named after the art FOLDER (impact -> spark_nXX.png)
	var art := _def.art_name if _def.art_name != "" else _def.id
	var frames := AnimLibrary.effect_frames(
		"res://assets/z/effects/%s" % art, art, _def.fps)
	var scale_factor := _def.scale * _extra_scale
	if frames != null and frames.has_animation("fx"):
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = frames
		sprite.scale = Vector2(2.0, 2.0) * scale_factor
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
		if _def.grounded:
			# keep the frame's bottom edge on the spawn point as the
			# tight-cropped frame heights change
			sprite.frame_changed.connect(func():
				if sprite.sprite_frames == null:
					return
				var tex: Texture2D = sprite.sprite_frames.get_frame_texture(
					"fx", sprite.frame)
				if tex:
					sprite.offset = Vector2(0, tex.get_height() * 0.5))
		sprite.animation_finished.connect(queue_free)
		sprite.play("fx")
		return
	# particle fallback: a short, restrained radial burst in the def colour
	var burst := CPUParticles2D.new()
	burst.emitting = true
	burst.one_shot = true
	burst.amount = 10
	burst.lifetime = 0.35
	burst.explosiveness = 0.95
	burst.direction = Vector2.UP
	burst.spread = 180.0
	burst.gravity = Vector2(0, 240)
	burst.initial_velocity_min = 40.0 * scale_factor
	burst.initial_velocity_max = 110.0 * scale_factor
	burst.scale_amount_min = 1.2 * scale_factor
	burst.scale_amount_max = 2.4 * scale_factor
	burst.color = _def.fallback_color
	add_child(burst)
	var timer := Timer.new()
	timer.wait_time = burst.lifetime + 0.2
	timer.one_shot = true
	add_child(timer)
	timer.timeout.connect(queue_free)
	timer.start()
