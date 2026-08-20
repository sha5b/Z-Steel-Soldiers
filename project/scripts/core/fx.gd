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


## Rubble in the PLANET's own colours. The pack ships a debris set per
## planet and per rubble size (256 frames); every planet used to share
## one generic grey `debris` burst. Falls back to that burst for a
## planet whose sets are not converted.
const ROCK_DEBRIS_SIZES := ["large0", "large1", "mid0", "mid1", "small"]
var _debris_pools := {}  # "<prefix>_<planet>" -> Array[effect id]


func rock_debris(world_pos: Vector2) -> void:
	play(_debris_pick("rock_debris", ROCK_DEBRIS_SIZES), world_pos)


## A blown bridge sheds its own rubble (one set per planet).
func bridge_debris(world_pos: Vector2) -> void:
	play(_debris_pick("bridge_debris", [""]), world_pos)


func _debris_pick(prefix: String, sizes: Array) -> String:
	var planet: String = MatchState.current.planet if MatchState.current else "desert"
	var key := "%s_%s" % [prefix, planet]
	if not _debris_pools.has(key):
		var pool: Array = []
		for size in sizes:
			var id := key if size == "" else "%s_%s" % [key, size]
			if DirAccess.dir_exists_absolute("res://assets/z/effects/%s" % id):
				pool.append(id)
		_debris_pools[key] = pool
	var pool: Array = _debris_pools[key]
	return String(pool.pick_random()) if not pool.is_empty() else "debris"


## A FALLING BUILDING throws pieces of itself. The pack ships 84 frames
## of this — 5 tumbling fort pieces and 2 generic ones, 12 frames each —
## referenced by nothing; vehicles already burn, buildings just vanished
## into a puff. Each piece flies out on a ballistic arc, tumbling through
## its own frames, and fades where it lands.
const DEBRIS_DIR := "res://assets/z/buildings/death_effects"
const DEBRIS_FLIGHT := 0.9
const DEBRIS_FADE := 1.6


## `from_rect` is the falling structure's FOOTPRINT. Every piece used to
## leave the exact same point — the visual centre — so a 96px fort threw
## its rubble out of one pixel like a firework, and a small hut threw
## the identical amount. Given a rect, each piece starts somewhere on the
## structure (upper two thirds, where the walls are) and the count scales
## with its area. Called with no rect, the old fixed counts stand.
func building_debris(world_pos: Vector2, fort: bool, spread := 40.0,
		from_rect := Rect2()) -> int:
	var pieces := 5 if fort else 2
	var count := 7 if fort else 4
	var area := from_rect.size.x * from_rect.size.y
	if area > 0.0:
		count = clampi(int(area / 1024.0), 4, 12)  # 1 piece per ~2x2 tiles
	var thrown := 0
	for i in count:
		var frames := AnimLibrary.effect_frames(DEBRIS_DIR,
			"%spiece%d" % ["fort_" if fort else "", i % pieces], 10.0)
		if frames == null or not frames.has_animation("fx"):
			continue
		frames.set_animation_loop("fx", true)
		var piece := AnimatedSprite2D.new()
		piece.sprite_frames = frames
		piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		piece.scale = Vector2.ONE  # native art scale
		piece.z_index = 7  # above the ruin, like the explosion
		var origin := world_pos
		if area > 0.0:
			origin = Vector2(
				randf_range(from_rect.position.x, from_rect.end.x),
				randf_range(from_rect.position.y,
					from_rect.position.y + from_rect.size.y * 0.66))
		piece.position = origin
		add_child(piece)
		piece.play("fx")
		thrown += 1
		# out and down: a tween on the position plus a lifted arc, so the
		# piece reads as thrown rather than sliding
		var away := Vector2.from_angle(randf() * TAU) \
			* randf_range(spread * 0.4, spread * 1.6)
		var lift := randf_range(10.0, 26.0)
		var tween := piece.create_tween()
		tween.set_parallel(true)
		tween.tween_property(piece, "position",
			origin + away, DEBRIS_FLIGHT).set_ease(Tween.EASE_OUT)
		tween.tween_property(piece, "offset", Vector2(0.0, -lift),
			DEBRIS_FLIGHT * 0.45).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(piece, "offset", Vector2.ZERO,
			DEBRIS_FLIGHT * 0.55).set_ease(Tween.EASE_IN)
		tween.chain().tween_property(piece, "modulate:a", 0.0, DEBRIS_FADE)
		tween.chain().tween_callback(piece.queue_free)
	return thrown


## A HURT OR BURNING STRUCTURE. The pack ships the original's whole
## burn set (`death_effects/`: little_smoke/smoke/big_smoke and
## little_fire/small_fire_smoke) and only vehicles ever used it — a fort
## one shot from collapse looked exactly like an untouched one, and its
## ruin then sat there clean forever. `severity` is 0..1 and picks the
## size of the plume; `with_fire` puts a flame at its foot. Returns
## false when none of the art resolves (so a test can tell).
const STRUCTURE_SMOKE := ["little_smoke", "smoke", "big_smoke"]
const STRUCTURE_FIRE := ["little_fire", "small_fire_smoke"]
var _loop_frames := {}  # effect folder -> SpriteFrames (built once, shared)


func structure_smoke(world_pos: Vector2, severity: float,
		with_fire := false) -> bool:
	var sizes: Array = STRUCTURE_SMOKE
	var pick: String = sizes[clampi(int(clampf(severity, 0.0, 0.999)
		* sizes.size()), 0, sizes.size() - 1)]
	var frames := _looping_effect(pick, 8.0)
	if frames != null:
		_spawn_drifting(frames, world_pos + Vector2(randf_range(-3.0, 3.0), 0.0),
			randf_range(9.0, 18.0), randf_range(1.0, 1.7))
	if with_fire:
		# the flame sits low and lives briefly; the plume above it is
		# what carries the eye
		var flame := _looping_effect(
			String(STRUCTURE_FIRE[randi() % STRUCTURE_FIRE.size()]), 10.0)
		if flame != null:
			_spawn_drifting(flame, world_pos + Vector2(randf_range(-4.0, 4.0), 3.0),
				randf_range(2.0, 5.0), randf_range(0.5, 0.9))
	return frames != null


## Looping frames for a named effect folder, built ONCE. A burning fort
## emits a puff a second for the rest of the match; rebuilding the
## SpriteFrames per puff walked the directory every time.
func _looping_effect(name: String, fps: float) -> SpriteFrames:
	if _loop_frames.has(name):
		return _loop_frames[name]
	var frames := AnimLibrary.effect_frames(
		"res://assets/z/effects/%s" % name, name, fps)
	if frames == null or not frames.has_animation("fx"):
		_loop_frames[name] = null
		return null
	frames.set_animation_loop("fx", true)
	_loop_frames[name] = frames
	return frames


## The UNLABELLED half of the robot voice bank (bark_23..75 = the pack's
## ROB23-75; ROB01-22 are the selected_*/acknowledge_* lines, matched by
## content hash). Nothing in the pack documents what these 53 lines say,
## so they play as ambient chatter and are NEVER used as a semantic cue.
const CHATTER_FIRST := 23
const CHATTER_LAST := 75


func chatter() -> void:
	_bark("bark_%02d" % (randi_range(CHATTER_FIRST, CHATTER_LAST)), -9.0)


## A robot SPEAKING, with how long the line runs. The HUD portrait wires
## itself to this and moves the head's mouth for exactly that long — the
## original's faces talk when their robot does, and only the sound site
## knows the clip length.
signal barked(seconds: float)


func _bark(name: String, volume_db: float) -> void:
	var stream: AudioStream = _play_wav(name, volume_db)
	if stream != null:
		barked.emit(stream.get_length())


## The distress calls the original barks when a unit is being shot at
## ("we're under attack", "help", "they're all over us"). WHICH of the
## unlabelled lines those are is still unknown (see docs/RESEARCH.md
## 2e), so this draws from the same pool as idle chatter — what it adds
## is the CUE: a unit under fire now speaks up instead of staying silent.
func distress() -> void:
	_bark("bark_%02d" % (randi_range(CHATTER_FIRST, CHATTER_LAST)), -6.0)


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
	_bark("acknowledge_%02d" % (randi() % 10), -4.0)


## The reporting-in line a unit gives when you SELECT it (the original's
## selected_* set, distinct from the order acknowledgement).
func selected_bark() -> void:
	_bark("selected_%02d" % (randi() % 12), -4.0)


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


## Fires for every announcement that passes the throttle — the HUD
## plaque (AnnouncePlaque) shows the original's printed message for the
## events that ship one.
signal announced(event: String)


## Events worth flying the camera to — what the sidebar's A button jumps
## at. A "robot manufactured" is news, not an emergency.
const ALERTS := ["fort_under_attack", "territory_lost", "youre_losing"]

## Where the last ALERT happened, Vector2.INF until one does.
var last_alert_at := Vector2.INF


func announce(event: String, at := Vector2.INF) -> void:
	if event == "":
		return
	var until := int(_announce_gates.get(event, 0))
	if until > Time.get_ticks_msec():
		return
	if at != Vector2.INF and ALERTS.has(event):
		last_alert_at = at
	_announce_gates[event] = Time.get_ticks_msec() + int(ANNOUNCE_THROTTLE.get(event, 10000))
	announced.emit(event)
	if event == "youre_losing":
		_play_wav("comp_youre_losing_%02d" % (randi() % 10), -2.0)
		return
	_play_wav("comp_%s" % event, -2.0)


func play_set(set_name: String, volume_db := 0.0) -> void:
	var names: Array = SOUNDS.get(set_name, [])
	if names.is_empty():
		return
	_play_wav(String(names[randi() % names.size()]), volume_db)


## Returns the stream that started playing (null when the sound was
## gated, missing or muted) so a caller that has to match the CLIP LENGTH
## — the talking portrait — can ask for it here instead of guessing.
func _play_wav(name: String, volume_db: float) -> AudioStream:
	if not _gate_allows(name):
		return null
	var path := "%s/%s.wav" % [SOUNDS_DIR, name]
	if not ResourceLoader.exists(path):
		return null
	_enforce_voice_cap()
	var player := AudioStreamPlayer.new()
	player.bus = GameSettings.SFX_BUS  # volume slider lives on the bus
	player.stream = load(path)
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	return player.stream

## Too many simultaneous one-shots exhausts the audio server's slots
## (the rare `slot >= slot_max` error under big firefights) — stop the
## oldest voices beyond the cap.
func _enforce_voice_cap() -> void:
	var players: Array[AudioStreamPlayer] = []
	for c in get_children():
		if c is AudioStreamPlayer and c.playing:
			players.append(c)
	while players.size() >= MAX_VOICES:
		# stop() does NOT emit `finished`, so the queue_free hook wired at
		# the play site never fired for a capped voice and the stopped
		# AudioStreamPlayer children piled up for the whole match
		var oldest: AudioStreamPlayer = players.pop_front()
		oldest.stop()
		oldest.queue_free()


func _gate_allows(name: String) -> bool:
	var now := Time.get_ticks_usec()
	if int(_gates.get(name, 0)) > now:
		return false
	_gates[name] = now + int(GATE_SECONDS * 1000000.0)
	return true
