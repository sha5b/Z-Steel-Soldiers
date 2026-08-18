class_name AnimLibrary
extends Object
## Builds SpriteFrames from the zod asset-folder naming conventions. All
## sprite scanning lives here so new content only needs correctly named
## PNGs on disk — see docs/ASSET_CONVENTIONS.md for the patterns.
##
## Shared robot art:   robots/<anim>_<team>_r<deg>[_n<frame>].png
## Robot weapon art:   robots_<type>/fire_<team>_r<deg>_n<frame>.png
## Vehicles/cannons:   <dir>/<anim>[_<team>]_r<deg>[_n<frame>].png
## Effects:            effects/<name>/<name>_n<frame>.png

const DIRECTIONS := 8
const TEAM_NAMES := {1: "red", 2: "blue", 3: "green", 4: "yellow"}
const ROBOTS_DIR := "res://assets/z/robots"
const IDLE_FLAVORS := ["beer", "cigarette", "pope", "look_around", "head_stretch",
	"beat_ground", "confused", "full_area_scan", "praise_the_lord"]
const DEATH_VARIANTS := ["die1", "die2", "die3", "die4", "die5", "melt"]
## One-shot contextual gestures (directional where the art is):
## point = order acknowledgement, pickup-* = crate collection,
## enter_apc = boarding hardware, throw/dodge available for combat flavor.
const GESTURES := ["point", "pickup-up", "pickup-down", "enter_apc", "throw", "dodge"]


static func team_name(team: int) -> String:
	return TEAM_NAMES.get(team, "red")


## Full frame set for a robot type: stand/walk (shared art), fire (type
## art), a random death variant, idle humor flavors and the victory
## celebration. Missing art is skipped silently.
static func robot_frames(unit_type: String, team: int) -> SpriteFrames:
	var tn := team_name(team)
	var frames := SpriteFrames.new()
	# stand/walk from the shared folder
	for anim in ["stand", "walk"]:
		for d in DIRECTIONS:
			var deg := d * 45
			var name := "%s_%d" % [anim, d]
			frames.add_animation(name)
			frames.set_animation_speed(name, 8.0 if anim == "walk" else 1.0)
			frames.set_animation_loop(name, true)
			var frame := 0
			while true:
				var suffix := "_n%02d" % frame if anim == "walk" else ""
				var path := "%s/%s_%s_r%03d%s.png" % [ROBOTS_DIR, anim, tn, deg, suffix]
				if not ResourceLoader.exists(path):
					break
				frames.add_frame(name, load(path))
				frame += 1
				if anim == "stand":
					break
			if frame == 0:
				frames.remove_animation(name)
	# per-type fire animation
	var type_dir := "res://assets/z/robots_%s" % unit_type
	for d in DIRECTIONS:
		var deg := d * 45
		var name := "fire_%d" % d
		frames.add_animation(name)
		frames.set_animation_speed(name, 10.0)
		frames.set_animation_loop(name, true)
		var frame := 0
		while true:
			var path := "%s/fire_%s_r%03d_n%02d.png" % [type_dir, tn, deg, frame]
			if not ResourceLoader.exists(path):
				break
			frames.add_frame(name, load(path))
			frame += 1
		if frame == 0:
			frames.remove_animation(name)
	# one random death variant per unit (original ships five)
	_add_numbered(frames, DEATH_VARIANTS.pick_random(), tn, "die", 8.0, false)
	# idle humor flavors: some have directional art, some are plain
	for flavor in IDLE_FLAVORS:
		_add_directional_or_numbered(frames, flavor, tn)
	# contextual gestures
	for gesture in GESTURES:
		_add_directional_or_numbered(frames, gesture, tn)
	# victory celebration
	_add_numbered(frames, "celebrate", tn, "celebrate", 6.0, true)
	return frames


## Tries `<anim>_<team>_r<deg>_n<frame>` per direction (registered as
## `<anim>_<d>`), falling back to plain numbered art under `<anim>_0`.
static func _add_directional_or_numbered(frames: SpriteFrames, anim: String, tn: String) -> void:
	for d in DIRECTIONS:
		var alias := "%s_%d" % [anim, d]
		if frames.has_animation(alias):
			continue
		frames.add_animation(alias)
		frames.set_animation_speed(alias, 6.0)
		frames.set_animation_loop(alias, false)
		var frame := 0
		while true:
			var path := "%s/%s_%s_r%03d_n%02d.png" % [ROBOTS_DIR, anim, tn, d * 45, frame]
			if not ResourceLoader.exists(path):
				break
			frames.add_frame(alias, load(path))
			frame += 1
		if frame == 0:
			frames.remove_animation(alias)
	_add_numbered(frames, anim, tn, "%s_0" % anim, 6.0, false)


## Non-directional anims shared by robots: `<anim>_<team>_n<frame>.png`,
## registered under `alias`. Directional fallback also tried (some flavors
## have r-facing art only).
static func _add_numbered(frames: SpriteFrames, anim: String, tn: String,
		alias: String, fps: float, loop: bool) -> void:
	if frames.has_animation(alias):
		return
	frames.add_animation(alias)
	frames.set_animation_speed(alias, fps)
	frames.set_animation_loop(alias, loop)
	var frame := 0
	while true:
		var path := "%s/%s_%s_n%02d.png" % [ROBOTS_DIR, anim, tn, frame]
		if not ResourceLoader.exists(path):
			break
		frames.add_frame(alias, load(path))
		frame += 1
	if frame == 0:
		frames.remove_animation(alias)


## Frame set for vehicles and cannons: empty / base / fire cycles per
## direction plus the `wasted` wreck sprite. Manned-idle art varies by
## type: vehicles have `base_*` (or `base_damaged_*` when `damaged`),
## the gun cannon uses `equiped_*` single frames, gatling/howitzer have
## none and show their fire cycle instead. Some types have no
## directional empty art — only a plain `empty.png` / `empty_null.png` —
## which is then used for every facing (never a team colour: unmanned
## hardware is neutral).
static func vehicle_frames(asset_dir: String, team: int, damaged := false) -> SpriteFrames:
	var tn := team_name(team)
	var frames := SpriteFrames.new()
	for anim in ["empty", "base", "fire"]:
		var found := false
		for d in DIRECTIONS:
			var deg := d * 45
			var name := "%s_%d" % [anim, d]
			frames.add_animation(name)
			frames.set_animation_speed(name, 6.0 if anim == "base" else 10.0)
			# the gunner `place` install animation runs once and HOLDS its
			# last frame (the manned idle pose)
			frames.set_animation_loop(name, not (anim == "base"
					and _is_place_path(asset_dir, tn, deg)))
			var frame := 0
			while true:
				var tex: Texture2D = _vehicle_anim_texture(
					asset_dir, anim, tn, deg, frame, damaged)
				if tex == null:
					break
				frames.add_frame(name, tex)
				frame += 1
				if anim == "empty":
					break
			if frame == 0:
				frames.remove_animation(name)  # missing direction
			else:
				found = true
		if anim == "empty" and not found:
			_add_plain_empty(frames, asset_dir, tn)
	frames.add_animation("wasted")
	frames.set_animation_loop("wasted", false)
	var wasted := "%s/wasted.png" % asset_dir
	if ResourceLoader.exists(wasted):
		frames.add_frame("wasted", load(wasted))
	else:
		frames.remove_animation("wasted")
	_alias_fire_as_base(frames)
	return frames


## Turret layer for tanks (`top_*` art): aims independently of the hull.
## Idle `top_r<deg>` (team-coloured on some types), firing `topf_r<deg>`
## where it exists, plus the `top_pop` destruction animation. Returns
## {"frames": SpriteFrames, "offsets": per-direction Vector2} or null.
## Offsets align the turret canvas' top-left with the hull canvas'
## top-left — the original sprites share that anchor.
static func turret_set(asset_dir: String, team: int) -> Dictionary:
	var tn := team_name(team)
	var frames := SpriteFrames.new()
	var found := false
	var offsets := PackedVector2Array()
	offsets.resize(DIRECTIONS)
	for d in DIRECTIONS:
		var deg := d * 45
		var idle := _first_existing([
			"%s/top_%s_r%03d.png" % [asset_dir, tn, deg],
			"%s/top_r%03d.png" % [asset_dir, deg],
			"%s/top_%s_r%03d.png" % [asset_dir, tn, mirrored_dir(d) * 45],
			"%s/top_r%03d.png" % [asset_dir, mirrored_dir(d) * 45]])
		if idle == "":
			continue
		var art_deg := _deg_of(idle)
		for anim in ["turret", "turretfire"]:
			var path := idle
			if anim == "turretfire":
				path = _first_existing([
					"%s/topf_%s_r%03d.png" % [asset_dir, tn, deg],
					"%s/topf_r%03d.png" % [asset_dir, deg],
					"%s/topf_%s_r%03d.png" % [asset_dir, tn, mirrored_dir(d) * 45],
					"%s/topf_r%03d.png" % [asset_dir, mirrored_dir(d) * 45],
					idle])
			var tex: Texture2D = _top_texture(path, art_deg, d)
			var name := "%s_%d" % [anim, d]
			frames.add_animation(name)
			frames.set_animation_speed(name, 1.0)
			frames.set_animation_loop(name, true)
			frames.add_frame(name, tex)
			found = true
		# offsets pair the turret with the hull canvas of the same
		# (possibly mirrored) direction art
		var hull := _first_existing([
			"%s/base_%s_r%03d_n00.png" % [asset_dir, tn, art_deg],
			"%s/base_%s_r%03d_n00.png" % [asset_dir, tn, deg]])
		offsets[d] = _layer_offset(
			_canvas_size(hull), _canvas_size(idle))
	if not found:
		return {}
	# turret blowing off on destruction
	frames.add_animation("pop")
	frames.set_animation_speed("pop", 8.0)
	frames.set_animation_loop("pop", false)
	var pop := 0
	while true:
		var pop_path := "%s/top_pop_n%02d.png" % [asset_dir, pop]
		if not ResourceLoader.exists(pop_path):
			break
		frames.add_frame("pop", load(pop_path))
		pop += 1
	if pop == 0:
		frames.remove_animation("pop")
	return {"frames": frames, "offsets": offsets}


## Offset that makes a centered layer sprite share the base canvas'
## top-left corner (the original sprites' common anchor).
static func _layer_offset(base_size: Vector2i, layer_size: Vector2i) -> Vector2:
	return (Vector2(layer_size) - Vector2(base_size)) * 0.5


static func _canvas_size(path: String) -> Vector2i:
	if not ResourceLoader.exists(path):
		return Vector2i.ZERO
	var tex: Texture2D = load(path)
	return Vector2i(tex.get_width(), tex.get_height())


static func _first_existing(paths: Array) -> String:
	for path in paths:
		if ResourceLoader.exists(String(path)):
			return String(path)
	return ""


## Direction index mirrored horizontally (r000<->r180, r045<->r135...).
## The original art ships only the right-facing half; the engine drew
## left-facing sprites as horizontal flips.
static func mirrored_dir(d: int) -> int:
	return wrapi(4 - d, 0, DIRECTIONS)


## Load the texture for direction `deg` from a path format; when the
## art only exists for the mirrored direction, return a flipped copy.
static func _dir_texture(path_fmt: String, deg: int) -> Texture2D:
	var direct := path_fmt % deg
	if ResourceLoader.exists(direct):
		return load(direct)
	var mirror := path_fmt % (mirrored_dir(deg_to_dir(deg)) * 45)
	if ResourceLoader.exists(mirror):
		var img: Image = (load(mirror) as Texture2D).get_image()
		img.flip_x()
		return ImageTexture.create_from_image(img)
	return null


static func deg_to_dir(deg: int) -> int:
	return wrapi(int(round(deg / 45.0)), 0, DIRECTIONS)


## Types without dedicated manned-idle art (gatling, howitzer) show their
## fire cycle as the manned look.
static func _alias_fire_as_base(frames: SpriteFrames) -> void:
	for d in DIRECTIONS:
		var fire := "fire_%d" % d
		var base := "base_%d" % d
		if not frames.has_animation(fire) or frames.has_animation(base):
			continue
		frames.add_animation(base)
		frames.set_animation_speed(base, 6.0)
		frames.set_animation_loop(base, true)
		for i in frames.get_frame_count(fire):
			frames.add_frame(base, frames.get_frame_texture(fire, i))


## Plain (non-directional) empty art registered under every facing so
## `_play("empty", dir)` works unchanged. Always neutral: `empty_null.png`
## first, then `empty.png`; the team-coloured variant is a last resort.
static func _add_plain_empty(frames: SpriteFrames, asset_dir: String, tn: String) -> void:
	var plain := plain_empty_path(asset_dir, tn)
	if plain == "":
		return
	var texture := load(plain)
	for d in DIRECTIONS:
		var name := "empty_%d" % d
		frames.add_animation(name)
		frames.set_animation_speed(name, 1.0)
		frames.set_animation_loop(name, true)
		frames.add_frame(name, texture)


## Resolved neutral empty-state texture (exposed for the texture audit
## test): never a team-coloured file for unmanned hardware.
static func plain_empty_path(asset_dir: String, _tn: String) -> String:
	return _first_existing([
		"%s/empty_null.png" % asset_dir,
		"%s/empty.png" % asset_dir,
		""])


static func _is_place_path(asset_dir: String, tn: String, deg: int) -> bool:
	# base art only exists as `place` (gunner install) for this direction?
	if ResourceLoader.exists("%s/base_%s_r%03d_n00.png" % [asset_dir, tn, deg]):
		return false
	if ResourceLoader.exists("%s/equiped_%s_r%03d.png" % [asset_dir, tn, deg]):
		return false
	return ResourceLoader.exists("%s/place_%s_n00.png" % [asset_dir, tn])


## Texture for a vehicle anim frame: the direct file, or a horizontally
## flipped copy of the mirrored direction (the original engine mirrored
## the right-facing half of the art for left facings).
static func _vehicle_anim_texture(asset_dir: String, anim: String, tn: String,
		deg: int, frame: int, damaged: bool) -> Texture2D:
	var path := _vehicle_anim_path(asset_dir, anim, tn, deg, frame, damaged)
	if ResourceLoader.exists(path):
		return load(path)
	if anim == "base":
		# place/equiped are direction-bound; mirrored base resolves below
		# through the plain pattern only when it exists for the mirror
		var mdeg := mirrored_dir(deg_to_dir(deg)) * 45
		var mirror_dmg := _vehicle_anim_path(asset_dir, anim, tn, mdeg, frame, damaged)
		if ResourceLoader.exists(mirror_dmg):
			return _flipped(mirror_dmg)
		# gunner `place` art is not directional — try it directly
		var place := "%s/place_%s_n%02d.png" % [asset_dir, tn, frame]
		if ResourceLoader.exists(place):
			return load(place)
		return null
	var mdeg2 := mirrored_dir(deg_to_dir(deg)) * 45
	var mirror := _vehicle_anim_path(asset_dir, anim, tn, mdeg2, frame, false)
	if ResourceLoader.exists(mirror):
		return _flipped(mirror)
	return null


## Degrees encoded in an `..._r<deg>...` filename.
static func _deg_of(path: String) -> int:
	var marker := path.rfind("_r")
	if marker < 0:
		return 0
	return int(path.substr(marker + 2, 3))


## Loads a `top*` texture, flipped when its art direction is the mirror
## of the direction we need.
static func _top_texture(path: String, art_deg: int, want_dir: int) -> Texture2D:
	if deg_to_dir(art_deg) == want_dir:
		return load(path)
	return _flipped(path)


static func _flipped(path: String) -> Texture2D:
	var img: Image = (load(path) as Texture2D).get_image()
	img.flip_x()
	return ImageTexture.create_from_image(img)


static func _vehicle_anim_path(asset_dir: String, anim: String, tn: String, deg: int, frame: int, damaged := false) -> String:
	match anim:
		"empty":
			return "%s/empty_r%03d.png" % [asset_dir, deg]
		"base":
			if damaged:
				var dmg := "%s/base_damaged_%s_r%03d_n%02d.png" % [asset_dir, tn, deg, frame]
				if ResourceLoader.exists(dmg):
					return dmg
			var base_path := "%s/base_%s_r%03d_n%02d.png" % [asset_dir, tn, deg, frame]
			if ResourceLoader.exists(base_path):
				return base_path
			# the gun cannon's manned idle is a single `equiped` frame
			var equiped := "%s/equiped_%s_r%03d.png" % [asset_dir, tn, deg]
			if ResourceLoader.exists(equiped) and frame == 0:
				return equiped
			# gatling/howitzer idle WITH the gunner figure (`place` art)
			var place := "%s/place_%s_n%02d.png" % [asset_dir, tn, frame]
			if ResourceLoader.exists(place):
				return place
			return base_path  # nonexistent -> caller stops scanning
		"fire":
			var team_path := "%s/fire_%s_r%03d_n%02d.png" % [asset_dir, tn, deg, frame]
			if ResourceLoader.exists(team_path):
				return team_path
			return "%s/fire_r%03d_n%02d.png" % [asset_dir, deg, frame]
	return ""


## Jeep wheels: separate `under_*` sprites (shared art, no team prefix).
## Returns {"frames", "offsets"} aligned to the body canvas like turrets,
## or {} when the type has no wheel art.
static func jeep_wheel_set(asset_dir: String, team: int) -> Dictionary:
	var tn := team_name(team)
	var frames := SpriteFrames.new()
	var found := false
	var offsets := PackedVector2Array()
	offsets.resize(DIRECTIONS)
	for d in DIRECTIONS:
		var name := "wheels_%d" % d
		frames.add_animation(name)
		frames.set_animation_speed(name, 12.0)
		frames.set_animation_loop(name, true)
		var frame := 0
		while true:
			var path := "%s/under_r%03d_n%02d.png" % [asset_dir, d * 45, frame]
			if not ResourceLoader.exists(path):
				break
			frames.add_frame(name, load(path))
			frame += 1
		if frame == 0:
			frames.remove_animation(name)
		else:
			found = true
			var body := _first_existing([
				"%s/base_%s_r%03d_n00.png" % [asset_dir, tn, d * 45],
				"%s/empty_r%03d.png" % [asset_dir, d * 45]])
			if body != "":
				offsets[d] = _layer_offset(_canvas_size(body),
					_canvas_size("%s/under_r%03d_n00.png" % [asset_dir, d * 45]))
	if not found:
		return {}
	return {"frames": frames, "offsets": offsets}


## Generic numbered-frame scan for effect folders:
## `<dir>/<name>_n00.png` ... Returns an empty-framed result when no art
## exists (caller decides on a fallback).
static func effect_frames(dir: String, name: String, fps: float) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.add_animation("fx")
	frames.set_animation_speed("fx", fps)
	frames.set_animation_loop("fx", false)
	var frame := 0
	while true:
		var path := "%s/%s_n%02d.png" % [dir, name, frame]
		if not ResourceLoader.exists(path):
			break
		frames.add_frame("fx", load(path))
		frame += 1
	if frame == 0:
		frames.remove_animation("fx")
	return frames
