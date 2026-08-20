class_name EffectPlayer
extends Node2D
## One-shot visual effect driven by an EffectDef resource. Plays sprite
## frames from the def's art folder when they exist, otherwise a native
## CPUParticles2D burst. Frees itself when finished. Spawn via Fx.play().
## Scale multiplies the native art size; `grounded` effects are
## bottom-anchored so explosions rise from the spawn point (the original
## frames are tight-cropped to varying heights — centering them wobbles).

var _def: EffectDef
var _extra_scale := 1.0


func setup(def: EffectDef, extra_scale := 1.0) -> void:
	_def = def
	_extra_scale = extra_scale


func _ready() -> void:
	z_index = 6  # above units and projectiles
	# frames are named after the art FOLDER (impact -> spark_nXX.png),
	# except when the folder carries the DEF's own frames — fire0/fire1
	# share the `fire` folder but own separate frame sets
	var art := _def.art_name if _def.art_name != "" else _def.id
	var prefix := _def.id if ResourceLoader.exists(
		"res://assets/z/effects/%s/%s_n00.png" % [art, _def.id]) else art
	var frames := AnimLibrary.effect_frames(
		"res://assets/z/effects/%s" % art, prefix, _def.fps)
	var scale_factor := _def.scale * _extra_scale
	if frames != null and frames.has_animation("fx"):
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = frames
		sprite.scale = Vector2.ONE * scale_factor  # native art scale
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
		if _def.grounded:
			# keep the frame's bottom edge on the spawn point as the
			# tight-cropped frame heights change: a centred frame spans
			# -h/2..h/2, so the anchor must LIFT by half the height —
			# a positive offset would drop the frame below the ground
			var anchor := func() -> void:
				if sprite.sprite_frames == null:
					return
				var tex: Texture2D = sprite.sprite_frames.get_frame_texture(
					"fx", sprite.frame)
				if tex:
					sprite.offset = Vector2(0, -tex.get_height() * 0.5)
			sprite.frame_changed.connect(anchor)
			sprite.animation_finished.connect(queue_free)
			sprite.play("fx")
			anchor.call()  # frame_changed never fires for frame 0
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
	burst.gravity = Vector2(0, 120)
	burst.initial_velocity_min = 20.0 * scale_factor
	burst.initial_velocity_max = 55.0 * scale_factor
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
