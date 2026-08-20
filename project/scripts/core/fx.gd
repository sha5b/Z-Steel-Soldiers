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
	# GRENADE.wav was never converted from the GOG dump — the
	# grenade-launcher shot stands in so pickups aren't silent
	"pickup": ["GRENLOBX"],
	"click": ["CLICK1L", "CLICK5L", "CLICK6L"],
}
const GUNSHOT_VOLUME_DB := -10.0
const GATE_SECONDS := 0.07  # per-sound minimum interval — no cacophony

var _gates := {}  # sound name -> ticks_usec when it may play again


## Sprite-or-particles one-shot effect at a world position.
func play(effect_name: String, world_pos: Vector2, extra_scale := 1.0) -> void:
	var def := ContentDB.effect_def(effect_name)
	var player := EffectPlayer.new()
	player.setup(def, extra_scale)
	player.position = world_pos
	add_child(player)
	if def.sound_set != "":
		play_set(def.sound_set)


func explosion(world_pos: Vector2, big := false) -> void:
	play("explosion_big" if big else "explosion", world_pos)


## Destruction of a manned unit / building — big boom, flying debris and
## a staggered secondary blast.
func destroyed(world_pos: Vector2) -> void:
	play("explosion_big", world_pos)
	play("debris", world_pos + Vector2(0, -6))
	play_set("destroyed")
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


## Laser fire: instant hit, thick beam flash (no tracer art in the
## original — the beam itself is the weapon sprite).
func laser(from: Vector2, to: Vector2) -> void:
	var line := Line2D.new()
	line.points = PackedVector2Array([from, to])
	line.width = 2.5
	line.default_color = Color(0.45, 1.0, 0.95, 0.95)
	line.z_index = 5
	add_child(line)
	var glow := Line2D.new()
	glow.points = PackedVector2Array([from, to])
	glow.width = 2.5
	glow.default_color = Color(0.3, 0.8, 1.0, 0.35)
	glow.z_index = 4
	add_child(glow)
	var tween := line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.16)
	tween.tween_callback(line.queue_free)
	var tween2 := glow.create_tween()
	tween2.tween_property(glow, "modulate:a", 0.0, 0.22)
	tween2.tween_callback(glow.queue_free)


## Damaged-vehicle smoke (original ETankSmoke): a puff of `track_dust`
## art for the current facing drifting upward; badly damaged vehicles
## spark as well (track_spark art).
func vehicle_smoke(world_pos: Vector2, dir: int, heavy := false) -> void:
	var frames: SpriteFrames = AnimLibrary.dir_effect_frames(
		"res://assets/z/effects/track_dust", "track_dust", dir, 8.0)
	if frames != null and frames.has_animation("fx"):
		_spawn_drifting(frames, world_pos + Vector2(randf_range(-3, 3), 0),
			randf_range(10.0, 16.0), 0.9)
	if heavy and randf() < 0.5:
		var spark: SpriteFrames = AnimLibrary.dir_effect_frames(
			"res://assets/z/effects/track_spark", "track_spark", dir, 12.0)
		if spark != null and spark.has_animation("fx"):
			_spawn_drifting(spark, world_pos + Vector2(randf_range(-4, 4), 2),
				randf_range(6.0, 10.0), 0.5)


func _spawn_drifting(frames: SpriteFrames, world_pos: Vector2,
		rise_speed: float, lifetime: float) -> void:
	var puff := AnimatedSprite2D.new()
	puff.sprite_frames = frames
	puff.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	puff.z_index = 6
	puff.position = world_pos
	add_child(puff)
	puff.play("fx")
	var tween := puff.create_tween()
	tween.set_parallel(true)
	tween.tween_property(puff, "position:y",
		world_pos.y - rise_speed * lifetime, lifetime)
	tween.tween_property(puff, "modulate:a", 0.0, lifetime).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(puff.queue_free)


## Vehicle/cannon shell visual — PURE PRESENTATION. Damage timing is
## simulation and lives in ShellSolver.deliver (it used to ride in this
## sprite's on_hit callback, so presentation owned gameplay timing).
func shell(from: Vector2, to: Vector2, proj: ProjectileDef) -> void:
	var shot := Projectile.new()
	shot.speed = proj.speed
	shot.impact_effect = proj.impact
	shot.texture = proj.texture
	shot.setup(from, to)
	add_child(shot)


## Weapon fire sound from a unit def's `sound` key (GOG RAW conversions).
## Robot order acknowledgement (the original's ROB barks) — one voice
## per DISPATCH (Commands calls it once per click), voice-capped like
## every other speech.
func acknowledge() -> void:
	_play_wav("acknowledge_%02d" % (randi() % 10), -4.0)


func gunfire(sound_name: String) -> void:
	if sound_name == "":
		return
	_play_wav(sound_name, GUNSHOT_VOLUME_DB)


## Unit cap reached — denial feedback (original UI beep).
func cap_denied() -> void:
	_play_wav("BEEP3L", -4.0)


func ui_click() -> void:
	play_set("click", -6.0)


## The commander's voice (original comp_* lines): announcement events
## for the PLAYER only, throttled so a firefight doesn't spam them.
const ANNOUNCE_THROTTLE := {"fort_under_attack": 20000, "territory_lost": 15000,
	"robot_manufactured": 8000, "vehicle_manufactured": 8000,
	"gun_manufactured": 8000, "starting_manufacture": 8000,
	"manufacturing_canceled": 8000, "starting_repair": 10000,
	"vehicle_repaired": 10000, "radar_activated": 20000, "youre_losing": 30000}
const MAX_VOICES := 12  # simultaneous one-shot players (audio slot cap)
var _announce_gates := {}


func announce(event: String) -> void:
	if event == "":
		return
	var until := int(_announce_gates.get(event, 0))
	if until > Time.get_ticks_msec():
		return
	_announce_gates[event] = Time.get_ticks_msec() + int(ANNOUNCE_THROTTLE.get(event, 10000))
	if event == "youre_losing":
		_play_wav("comp_youre_losing_%02d" % (randi() % 10), -2.0)
		return
	_play_wav("comp_%s" % event, -2.0)


func play_set(set_name: String, volume_db := 0.0) -> void:
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
	_enforce_voice_cap()
	var player := AudioStreamPlayer.new()
	player.bus = GameSettings.SFX_BUS  # volume slider lives on the bus
	player.stream = load(path)
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

## Too many simultaneous one-shots exhausts the audio server's slots
## (the rare `slot >= slot_max` error under big firefights) — stop the
## oldest voices beyond the cap.
func _enforce_voice_cap() -> void:
	var players: Array[AudioStreamPlayer] = []
	for c in get_children():
		if c is AudioStreamPlayer and c.playing:
			players.append(c)
	while players.size() >= MAX_VOICES:
		players.pop_front().stop()


func _gate_allows(name: String) -> bool:
	var now := Time.get_ticks_usec()
	if int(_gates.get(name, 0)) > now:
		return false
	_gates[name] = now + int(GATE_SECONDS * 1000000.0)
	return true
