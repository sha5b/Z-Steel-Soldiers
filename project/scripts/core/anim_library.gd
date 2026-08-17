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
const IDLE_FLAVORS := ["beer", "cigarette", "pope", "look_around", "head_stretch", "beat_ground"]
const DEATH_VARIANTS := ["die1", "die2", "die3", "die4", "die5"]


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
## type: vehicles have `base_*`, the gun cannon uses `equiped_*` single
## frames, gatling/howitzer have none and show their fire cycle instead.
## Some types have no directional empty art — only a plain
## `empty.png` / `empty_<team>.png` — which is then used for every facing.
static func vehicle_frames(asset_dir: String, team: int) -> SpriteFrames:
	var tn := team_name(team)
	var frames := SpriteFrames.new()
	for anim in ["empty", "base", "fire"]:
		var found := false
		for d in DIRECTIONS:
			var deg := d * 45
			var name := "%s_%d" % [anim, d]
			frames.add_animation(name)
			frames.set_animation_speed(name, 6.0 if anim == "base" else 10.0)
			frames.set_animation_loop(name, true)
			var frame := 0
			while true:
				var path := _vehicle_anim_path(asset_dir, anim, tn, deg, frame)
				if not ResourceLoader.exists(path):
					break
				frames.add_frame(name, load(path))
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
## `_play("empty", dir)` works unchanged.
static func _add_plain_empty(frames: SpriteFrames, asset_dir: String, tn: String) -> void:
	var plain := "%s/empty_%s.png" % [asset_dir, tn]
	if not ResourceLoader.exists(plain):
		plain = "%s/empty_null.png" % asset_dir  # neutral grey (unmanned)
	if not ResourceLoader.exists(plain):
		plain = "%s/empty.png" % asset_dir
	if not ResourceLoader.exists(plain):
		return
	var texture := load(plain)
	for d in DIRECTIONS:
		var name := "empty_%d" % d
		frames.add_animation(name)
		frames.set_animation_speed(name, 1.0)
		frames.set_animation_loop(name, true)
		frames.add_frame(name, texture)


static func _vehicle_anim_path(asset_dir: String, anim: String, tn: String, deg: int, frame: int) -> String:
	match anim:
		"empty":
			return "%s/empty_r%03d.png" % [asset_dir, deg]
		"base":
			var base_path := "%s/base_%s_r%03d_n%02d.png" % [asset_dir, tn, deg, frame]
			if ResourceLoader.exists(base_path):
				return base_path
			# the gun cannon's manned idle is a single `equiped` frame
			var equiped := "%s/equiped_%s_r%03d.png" % [asset_dir, tn, deg]
			if ResourceLoader.exists(equiped) and frame == 0:
				return equiped
			return base_path  # nonexistent -> caller stops scanning
		"fire":
			var team_path := "%s/fire_%s_r%03d_n%02d.png" % [asset_dir, tn, deg, frame]
			if ResourceLoader.exists(team_path):
				return team_path
			return "%s/fire_r%03d_n%02d.png" % [asset_dir, deg, frame]
	return ""


## Jeep wheels live in separate `under_*` sprites beneath the body.
static func jeep_wheel_frames(asset_dir: String, team: int) -> SpriteFrames:
	var tn := team_name(team)
	var frames := SpriteFrames.new()
	var found := false
	for d in DIRECTIONS:
		var name := "wheels_%d" % d
		frames.add_animation(name)
		frames.set_animation_speed(name, 12.0)
		frames.set_animation_loop(name, true)
		var frame := 0
		while true:
			var path := "%s/under_%s_r%03d_n%02d.png" % [asset_dir, tn, d * 45, frame]
			if not ResourceLoader.exists(path):
				break
			frames.add_frame(name, load(path))
			frame += 1
		if frame == 0:
			frames.remove_animation(name)
		else:
			found = true
	return frames if found else null


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
