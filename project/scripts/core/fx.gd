extends Node
## Autoload: gameplay effects — explosions, impacts, projectiles, weapon
## and combat sounds (all from the original GOG release; see
## tools/gog/convert_assets.py). Everything spawns as world-space children
## of this node with a z_index above the Y-sorted map, so effects never
## need to know about the map scene. Add new visual effects by dropping
## frames into assets/z/effects/<name>/ (docs/ASSET_CONVENTIONS.md).

const SOUNDS_DIR := "res://assets/z/sounds"

## Sound sets: each key picks a random variant. Explosion variants are
## the original EXP1/EXP2 (+ OBJDEST3 for hardware/buildings blowing up).
const SOUNDS := {
	"explosion": ["EXP1", "EXP2"],
	"destroyed": ["OBJDEST3", "EXP2"],
	"impact": ["RICOCH1"],
	"pickup": ["GRENADE"],
	"click": ["CLICK1L", "CLICK5L", "CLICK6L"],
}
const GUNSHOT_VOLUME_DB := -10.0
const GATE_SECONDS := 0.07  # per-sound minimum interval — no cacophony

var _gates := {}  # sound name -> ticks_usec when it may play again


## Sprite-or-particles one-shot effect at a world position.
func play(effect_name: String, world_pos: Vector2, scale := 1.0) -> void:
	var def: Dictionary = ContentDB.effect_def(effect_name).duplicate()
	def["_name"] = effect_name
	def["scale"] = float(def.get("scale", 1.0)) * scale
	var player := EffectPlayer.new()
	player.setup(def)
	player.position = world_pos
	add_child(player)
	if String(def.get("sound", "")) != "":
		_play_set(String(def.sound))


func explosion(world_pos: Vector2, big := false) -> void:
	play("explosion_big" if big else "explosion", world_pos)


## Destruction of a manned unit / building — big boom, flying debris and
## a staggered secondary blast.
func destroyed(world_pos: Vector2) -> void:
	play("explosion_big", world_pos)
	play("debris", world_pos + Vector2(0, -6))
	_play_set("destroyed")
	var timer := get_tree().create_timer(0.22)
	timer.timeout.connect(func():
		if is_instance_valid(self):
			play("explosion", world_pos + Vector2(
				randf_range(-14.0, 14.0), randf_range(-10.0, 6.0))))


func impact(world_pos: Vector2) -> void:
	play("impact", world_pos)


## Robot small-arms fire: instant hit, visual tracer only.
func bullet(from: Vector2, to: Vector2) -> void:
	var line := Line2D.new()
	line.points = PackedVector2Array([from, to])
	line.width = 1.5
	line.default_color = Color(1.0, 0.9, 0.4, 0.9)
	line.z_index = 5
	add_child(line)
	var tween := line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.12)
	tween.tween_callback(line.queue_free)


## Vehicle/cannon shell: damage lands when the shot arrives (dodgeable,
## Z-style) via `on_hit` — bind target validation into the callback.
func shell(from: Vector2, to: Vector2, opts: Dictionary, on_hit: Callable) -> void:
	var shot := Projectile.new()
	shot.speed = float(opts.get("speed", 260.0))
	shot.impact_effect = String(opts.get("impact", "impact"))
	shot.sprite_name = String(opts.get("sprite", ""))
	shot.texture_path = String(opts.get("texture", ""))
	shot.setup(from, to, on_hit)
	add_child(shot)


## Weapon fire sound from a unit def's `sound` key (GOG RAW conversions).
func gunfire(sound_name: String) -> void:
	if sound_name == "":
		return
	_play_wav(sound_name, GUNSHOT_VOLUME_DB)


## Unit cap reached — denial feedback (original UI beep).
func cap_denied() -> void:
	_play_wav("BEEP3L", -4.0)


func ui_click() -> void:
	_play_set("click", -6.0)


func _play_set(set_name: String, volume_db := 0.0) -> void:
	var names: Array = SOUNDS.get(set_name, [])
	if names.is_empty():
		return
	_play_wav(String(names[randi() % names.size()]), volume_db)


func _play_wav(name: String, volume_db: float) -> void:
	if not _gate_allows(name):
		return
	var path := "%s/%s.wav" % [SOUNDS_DIR, name]
	if not ResourceLoader.exists(path):
		return
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _gate_allows(name: String) -> bool:
	var now := Time.get_ticks_usec()
	if int(_gates.get(name, 0)) > now:
		return false
	_gates[name] = now + int(GATE_SECONDS * 1000000.0)
	return true
