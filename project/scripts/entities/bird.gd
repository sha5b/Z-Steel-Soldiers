class_name Bird
extends Node2D
## Ambient bird (original per-planet bird art: 5 flap frames x 2 facings
## x 5 planets). Purely cosmetic and never targetable: a bird crosses the
## map high above everything, calls now and then, and frees itself on the
## far side. 228 frames of this shipped in the pack with nothing
## referencing them — and the bird CALL wavs were converted and unused
## for the same reason.

const BIRDS_DIR := "res://assets/z/entities/birds"
const FLY_SPEED := 62.0
const COUNT_PER_MAP := 3
const FLAP_FPS := 9.0
const BIRD_Z := 40  # above every ground sprite: they are FLYING

## The planet's own bird call (GOG sfx names). Planets with none stay
## silent — the flight is still shown.
const CALLS := {
	"desert": "DESBIRD", "jungle": "JNGBIRD1", "volcanic": "VBIRD1",
	"arctic": "PINGU1", "city": "CROW2",
}
const CALL_CHANCE := 0.25  # per crossing

var planet := "desert"
var _sprite: AnimatedSprite2D
var _heading := Vector2.RIGHT
var _frames := {}  # facing -> SpriteFrames


## True when this planet ships bird art (all five do — checked, not
## assumed, so a partial asset copy degrades quietly).
static func art_exists(planet_name: String) -> bool:
	return ResourceLoader.exists("%s/bird_%s_r000_n00.png"
		% [BIRDS_DIR, planet_name])


## A bird entering from one edge, aimed across the map.
static func spawn(parent: Node, planet_name: String) -> Bird:
	if parent == null or not art_exists(planet_name):
		return null
	var rect: Rect2 = NavWorld.current.map_rect
	var bird := Bird.new()
	bird.planet = planet_name
	var vertical := randf() < 0.4
	if vertical:
		var down := randf() < 0.5
		bird.position = Vector2(randf_range(rect.position.x, rect.end.x),
			rect.position.y - 24.0 if down else rect.end.y + 24.0)
		bird._heading = Vector2(randf_range(-0.3, 0.3), 1.0 if down else -1.0)
	else:
		var east := randf() < 0.5
		bird.position = Vector2(rect.position.x - 24.0 if east else rect.end.x + 24.0,
			randf_range(rect.position.y, rect.end.y))
		bird._heading = Vector2(1.0 if east else -1.0, randf_range(-0.3, 0.3))
	bird._heading = bird._heading.normalized()
	parent.add_child(bird)
	if randf() < CALL_CHANCE:
		Fx.gunfire(String(CALLS.get(planet_name, "")))  # one-shot wav, gated
	return bird


func _ready() -> void:
	z_index = BIRD_Z
	_sprite = AnimatedSprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2.ONE  # native art scale
	add_child(_sprite)
	_play()


func _process(delta: float) -> void:
	position += _heading * FLY_SPEED * delta
	_play()
	# gone over the far edge: no bird lives forever
	var rect: Rect2 = NavWorld.current.map_rect.grow(64.0)
	if not rect.has_point(position):
		queue_free()


func _play() -> void:
	# the art ships a side view (r000) and a vertical one (r090); the side
	# view mirrors for westward flight, exactly like the animals
	var vertical := absf(_heading.y) > absf(_heading.x)
	var flip := _heading.x < 0.0 and not vertical
	var key := "%d_%s" % [90 if vertical else 0, flip]
	if not _frames.has(key):
		var frames := SpriteFrames.new()
		frames.add_animation("fly")
		frames.set_animation_speed("fly", FLAP_FPS)
		frames.set_animation_loop("fly", true)
		var i := 0
		while true:
			var path := "%s/bird_%s_r%03d_n%02d.png" % [BIRDS_DIR, planet,
				90 if vertical else 0, i]
			if not ResourceLoader.exists(path):
				break
			frames.add_frame("fly", load(path))
			i += 1
		if i == 0:
			return
		_frames[key] = frames
	if _sprite.sprite_frames != _frames[key]:
		_sprite.sprite_frames = _frames[key]
		_sprite.play("fly")
	_sprite.flip_h = flip
