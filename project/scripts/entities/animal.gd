class_name Animal
extends Node2D
## Ambient critter (original hut_animals art: per-planet rabbits, foxes,
## raptors, penguins...). Purely cosmetic: wanders between nearby spots,
## stops to look around, plays its dead art when caught in a blast.
## The art ships side (r000) and vertical (r090) facings — the side art
## mirrors for westward movement.

const ANIMALS_DIR := "res://assets/z/entities/animals"
const WALK_SPEED := 26.0
const COUNT_PER_MAP := 5

## Species pools per planet (art availability checked at runtime).
const PLANET_SPECIES := {
	"desert": ["desert_rabit", "ostrich", "raptor", "turtle", "rat"],
	"arctic": ["arctic_rabit", "penguin", "white_wolf"],
	"jungle": ["green_eyed_fox", "green_lizard", "green_snake",
		"pig_dino", "mini_raptor"],
	"volcanic": ["red_worm", "raptor", "rat"],
	"city": ["rat", "yellow_worm", "turtle"],
}

var species := "desert_rabit"
var _sprite: AnimatedSprite2D
var _state := "idle"  # idle | walking | dead
var _timer := 0.0
var _target := Vector2.ZERO
var _frames := {}  # anim name -> SpriteFrames (per facing, lazily built)


static func random_species(planet: String) -> String:
	var pool: Array = PLANET_SPECIES.get(planet, PLANET_SPECIES.desert)
	var candidates := []
	for s in pool:
		if ResourceLoader.exists("%s/%s_look_r000_n00.png" % [ANIMALS_DIR, s]):
			candidates.append(s)
	return String(candidates.pick_random()) if not candidates.is_empty() else ""


func _ready() -> void:
	add_to_group(Groups.ANIMALS)
	_sprite = AnimatedSprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2.ONE  # native art scale
	add_child(_sprite)
	_play("look", 0, false)
	_timer = randf_range(1.5, 5.0)


func _process(delta: float) -> void:
	if _state == "dead" or MatchState.current.map_root == null:
		return
	_timer -= delta
	if _state == "idle":
		if _timer <= 0.0:
			_begin_walk()
		return
	var offset := _target - position
	if offset.length() <= 4.0:
		_state = "idle"
		_timer = randf_range(1.5, 5.0)
		_play("look", 0, false)
		return
	position += offset.normalized() * WALK_SPEED * delta
	var vertical := absf(offset.y) > absf(offset.x)
	_play("walk", 90 if vertical else 0, offset.x < 0.0 and not vertical)
	position = position.clamp(NavWorld.current.map_rect.position + Vector2(16, 16),
		NavWorld.current.map_rect.end - Vector2(16, 16))


func _begin_walk() -> void:
	_target = position + Vector2.from_angle(randf() * TAU) \
		* randf_range(90.0, 220.0)
	_state = "walking"


func _play(anim: String, deg: int, flip: bool) -> void:
	if _sprite == null:
		return
	var key := "%s_%d_%s" % [anim, deg, flip]
	if not _frames.has(key):
		var frames := SpriteFrames.new()
		frames.add_animation(anim)
		frames.set_animation_speed(anim, 6.0)
		frames.set_animation_loop(anim, anim == "walk")
		var i := 0
		while true:
			var path := "%s/%s_%s_r%03d_n%02d.png" % [ANIMALS_DIR,
				species, anim, deg, i]
			if not ResourceLoader.exists(path):
				break
			frames.add_frame(anim, load(path))
			i += 1
		if i == 0:
			return
		_frames[key] = frames
	_sprite.sprite_frames = _frames[key]
	_sprite.flip_h = flip
	_sprite.play(anim)


## Caught in a blast: play the dead art, fade out, leave the world.
func kill() -> void:
	if _state == "dead":
		return
	_state = "dead"
	var frames := SpriteFrames.new()
	frames.add_animation("dead")
	frames.set_animation_speed("dead", 1.0)
	frames.set_animation_loop("dead", false)
	var variant := "dead_down" if randf() < 0.5 else "dead_up"
	var path := "%s/%s_%s.png" % [ANIMALS_DIR, species, variant]
	if ResourceLoader.exists(path):
		frames.add_frame("dead", load(path))
		_sprite.sprite_frames = frames
		_sprite.flip_h = false
		_sprite.play("dead")
	var tween := create_tween()
	tween.tween_interval(12.0)
	tween.tween_property(self, "modulate:a", 0.0, 3.0)
	tween.tween_callback(queue_free)
