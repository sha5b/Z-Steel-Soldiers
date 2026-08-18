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
	# GRENADE.wav was never converted from the GOG dump — fall back to
	# the grenade-launcher shot so pickups aren't silent
	"pickup": ["GRENADE", "GRENLOBX"],
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
		_play_set(def.sound_set)


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
	glow.width = 5.0
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


## Vehicle/cannon shell: damage lands when the shot arrives (dodgeable,
## Z-style) via `on_hit` — bind target validation into the callback.
func shell(from: Vector2, to: Vector2, proj: ProjectileDef, on_hit: Callable) -> void:
	var shot := Projectile.new()
	shot.speed = proj.speed
	shot.impact_effect = proj.impact
	shot.texture = proj.texture
	shot.setup(from, to, on_hit)
	add_child(shot)


## Explosion splash (original: damage_missile with radius): hits every
## enemy unit and fort/bridge around the impact, and crumbles rocks the
## blast reaches. Friendly fire is off — the shooter's team is spared.
func area_damage(world_pos: Vector2, radius: float, amount: int, shooter_team: int) -> void:
	var r2 := radius * radius
	for u in get_tree().get_nodes_in_group("units"):
		if u is Node2D and u is Unit2D and u.alive and not u.carried \
				and u.team != shooter_team and u.team != 0:
			if u.global_position.distance_squared_to(world_pos) <= r2:
				u.take_damage(amount)
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is Node2D and b is Building2D and b.alive \
				and (b.is_bridge() or (b.is_fort and b.team != shooter_team and b.team != 0)):
			if b.world_footprint().get_center().distance_squared_to(world_pos) <= r2:
				b.take_damage(amount)
	for rock in get_tree().get_nodes_in_group("rocks"):
		if rock is Node2D and rock.global_position.distance_squared_to(world_pos) <= r2:
			var cell := Vector2i(((rock.global_position - Vector2(8, 8)) / 16.0).floor())
			if GameState.nav_grid and GameState.nav_grid.is_point_solid(cell):
				GameState.nav_grid.set_point_solid(cell, false)
			if GameState.vehicle_grid and GameState.vehicle_grid.is_point_solid(cell):
				GameState.vehicle_grid.set_point_solid(cell, false)
			play("debris", rock.global_position)
			rock.queue_free()


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


## The commander's voice (original comp_* lines): announcement events
## for the PLAYER only, throttled so a firefight doesn't spam them.
const ANNOUNCE_THROTTLE := {"fort_under_attack": 20000, "territory_lost": 15000,
	"robot_manufactured": 8000, "vehicle_manufactured": 8000,
	"gun_manufactured": 8000}
var _announce_gates := {}


func announce(event: String) -> void:
	if event == "":
		return
	var until := int(_announce_gates.get(event, 0))
	if until > Time.get_ticks_msec():
		return
	_announce_gates[event] = Time.get_ticks_msec() + int(ANNOUNCE_THROTTLE.get(event, 10000))
	_play_wav("comp_%s" % event, -2.0)


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
