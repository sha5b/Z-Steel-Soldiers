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
##
## Direction numbering (verified against the zod engine's
## DirectionFromLoc + ROTATION and the sprite pixels themselves):
## the 8 facings r000..r315 run COUNTER-clockwise on screen —
##   r000 = east, r045 = north-east, r090 = north (up),
##   r135 = north-west, r180 = west, r225 = south-west,
##   r270 = south (down), r315 = south-east.
## Tank hulls ship only the right-hand half (r000/r045/r090/r315); the
## left-hand facings render as horizontal flips of their mirror partner
## (0<->4, 1<->3, 2<->2, 5<->7) with the move animation reversed.
## The crane arm is the exception: its files use the INVERTED rotation
## table (arm facing d is stored in r{(d+4)%8*45}) — the arm trails
## opposite the direction of travel.

const DIRECTIONS := 8
const ROBOTS_DIR := "res://assets/z/robots"
const CANNONS_COMMON := "res://assets/z/cannons_common"
const FLAGS_DIR := "res://assets/z/flags"
const IDLE_FLAVORS := ["beer", "cigarette", "pope", "look_around", "head_stretch",
	"beat_ground", "confused", "full_area_scan", "praise_the_lord"]
const DEATH_VARIANTS := ["die1", "die2", "die3", "die4", "die5", "melt"]
## One-shot contextual gestures (directional where the art is):
## point = order acknowledgement, pickup-* = crate collection,
## enter_apc = boarding hardware, throw/dodge available for combat flavor.
## `escape_tank` is the crew bailing out of a hull (played by the
## survivor a sniper or a dismount order puts back on the ground) and
## the four `jump-*` leaps are what a dodge picks from by direction —
## 176 frames of shipped art that no code path could reach.
const GESTURES := ["point", "pickup-up", "pickup-down", "enter_apc", "throw", "dodge",
	"escape_tank", "jump-up", "jump-down", "jump-left", "jump-right"]

## The CREW of a manned hull, seen through the open hatch while the gun
## fires (`tank_fire`: 8 directions, shared robot art — the pose is the
## same whichever robot type drives). This is the other half of the
## original's visible-crew mechanic: the hatch that opens here is the
## same one a sniper shoots through (Vehicle2D.lid_open).
static var _crew_cache := {}

static func crew_frames(team: int) -> SpriteFrames:
	var tn := team_name(team)
	if _crew_cache.has(tn):
		return _crew_cache[tn]
	var frames := SpriteFrames.new()
	for d in DIRECTIONS:
		var name := "tank_fire_%d" % d
		frames.add_animation(name)
		frames.set_animation_speed(name, 8.0)
		frames.set_animation_loop(name, true)
		var frame := 0
		while true:
			var path := "%s/tank_fire_%s_r%03d_n%02d.png" % [ROBOTS_DIR, tn, d * 45, frame]
			if not ResourceLoader.exists(path):
				break
			frames.add_frame(name, load(path))
			frame += 1
		if frame == 0:
			frames.remove_animation(name)
	_crew_cache[tn] = frames
	return frames

## Convention folder for a unit type (robots_<t>/vehicles_<t>/cannons_<t>).
## Used where the ContentDB autoload isn't running (editor scene previews);
## at runtime defs stay the source of truth.
static func asset_dir_for(kind: String, unit_name: String) -> String:
	var folder: String = {"robot": "robots", "vehicle": "vehicles", "cannon": "cannons"}.get(kind, "")
	if folder == "":
		return ""
	var dir := "res://assets/z/%s_%s" % [folder, unit_name]
	return dir if DirAccess.dir_exists_absolute(dir) else ""


## Crane arm + hook offsets (hook hangs at hull + arm + hook offsets).
const CRANE_TABLES := {
	"arm": [Vector2(-6, -6), Vector2(-3, -4), Vector2(0, -5), Vector2(3, -4),
		Vector2(6, -6), Vector2(1, -8), Vector2(0, -9), Vector2(-2, -8)],
	"hook": [Vector2(0, 14), Vector2(4, 20), Vector2(14, 23), Vector2(23, 20),
		Vector2(25, 14), Vector2(21, 8), Vector2(14, 5), Vector2(5, 8)],
}


## Team art token for sprite paths. The original engine shipped its own
## recoloured variant of every team-painted sprite (`stand_blue_r000`,
## `base_green_r000_n00`, `flag_yellow_n00`... — verified pure colour
## swaps of the red set, neutral pixels untouched), so teams load their
## own files and NOTHING recolours at runtime. Team 0 / unknown ids map
## to the neutral "null" art; neutral-only anims (`empty_*`, plain
## `wasted.png`) never carry the token and stay team-free.
static func team_name(team: int) -> String:
	# Teams.palette cycles 8-team maps through the four shipped colour
	# sets — never "null" for a real team
	return Teams.display_name(team)


## HOW BIG A FLAG DRAWS. The flag art in the working set is a 32x24
## redraw of the pack's 16x16 sprite — twice the size the original draws
## a territory flag at — so every flag in the game came out double.
## Halving it here keeps the cleaner art and restores the original
## footprint; it is one constant because THREE sprites use these frames
## (zone flags, building flags, rally markers) and they were each
## carrying their own "native scale" comment while all three were wrong.
const FLAG_SCALE := Vector2(0.5, 0.5)


## Territory flag wave: the owning team's own frames — the neutral grey
## set for team 0.
static func flag_frames(team := 0) -> SpriteFrames:
	var key := team_name(team)
	if _flag_cache.has(key):
		return _flag_cache[key]
	var frames := SpriteFrames.new()
	frames.add_animation("wave")
	frames.set_animation_loop("wave", true)
	frames.set_animation_speed("wave", 6.0)
	for i in 4:
		var path := "%s/flag_%s_n%02d.png" % [FLAGS_DIR, key, i]
		if ResourceLoader.exists(path):
			frames.add_frame("wave", load(path))
	_flag_cache[key] = frames
	return frames


static var _flag_cache := {}


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
	# per-type fire animation: a one-shot — the muzzle flash must never
	# loop or hold (the unit returns to stand when it finishes)
	var type_dir := "res://assets/z/robots_%s" % unit_type
	for d in DIRECTIONS:
		var deg := d * 45
		var name := "fire_%d" % d
		frames.add_animation(name)
		frames.set_animation_speed(name, 10.0)
		frames.set_animation_loop(name, false)
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
## `<anim>_<d>`), then the SINGLE-FRAME directional shape
## `<anim>_<team>_r<deg>` — `point` is stored that way, exactly like
## `stand`, so the order-acknowledgement gesture resolved to nothing at
## all and play_gesture("point") was a silent no-op. Falls back to plain
## numbered art under `<anim>_0`.
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
			var single := "%s/%s_%s_r%03d.png" % [ROBOTS_DIR, anim, tn, d * 45]
			if ResourceLoader.exists(single):
				frames.add_frame(alias, load(single))
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
## direction plus the wreck sprite. Semantics per the original engine:
## - `empty` (directional or plain `empty_null`/`empty`) is shown while
##   unmanned AND as the passive look of manned gatling/howitzer (their
##   gunner only appears in the fire frames).
## - `base` is the manned hull/vehicle idle (`equiped` single frames for
##   the gun cannon, `place` install art holds its last frame).
## - `fire` is a short muzzle FLASH (plays once, holds the last frame).
## - `wasted[_<team>]` is the wreck; tanks have none — they explode.
static func vehicle_frames(asset_dir: String, team: int, damaged := false) -> SpriteFrames:
	var tn := team_name(team)
	var frames := SpriteFrames.new()
	for anim in ["empty", "base", "fire"]:
		if anim == "fire" and _fire_art_is_overlay(asset_dir, tn):
			# the jeep's `fire_*` frames are the GUNNER OVERLAY (16x14 on
			# a 32x31 hull) — the turret layer already renders them (aim =
			# n00, flash = n01); hull fire anims would swap the whole body
			# for the tiny overlay on every shot and strobe it away
			continue
		var found := false
		for d in DIRECTIONS:
			var deg := d * 45
			var name := "%s_%d" % [anim, d]
			frames.add_animation(name)
			frames.set_animation_speed(name, 6.0 if anim == "base" else 10.0)
			# the fire flash and the install animation run once and hold
			# their last frame
			frames.set_animation_loop(name, anim != "fire")
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
	# gunner install: shared init-place frames followed by the team's
	# place frames — plays once when a robot mans the hardware. CANNONS
	# ONLY: it exists iff the type ships its own place art. Vehicles
	# have none (manning is instant) — leaking the shared cannon frames
	# onto a tank hull would replace it with gunner art for the install
	var place_frames: Array = []
	var place_frame := 0
	while true:
		var place := "%s/place_%s_n%02d.png" % [asset_dir, tn, place_frame]
		if not ResourceLoader.exists(place):
			break
		place_frames.append(load(place))
		place_frame += 1
	var install: Array = cannon_install_frames() if not place_frames.is_empty() else []
	install.append_array(place_frames)
	if not install.is_empty():
		for d in DIRECTIONS:
			var name := "install_%d" % d
			frames.add_animation(name)
			frames.set_animation_speed(name, 8.0)
			frames.set_animation_loop(name, false)
			for tex in install:
				frames.add_frame(name, tex)
	# gatling/howitzer manned steady look: the seated gunner (LAST install
	# frame); the passive empty art is the fallback when there is no
	# place art at all
	for d in DIRECTIONS:
		var base := "base_%d" % d
		var empty := "empty_%d" % d
		if frames.has_animation(base) or install.is_empty():
			continue
		frames.add_animation(base)
		frames.set_animation_speed(base, 1.0)
		frames.set_animation_loop(base, true)
		if frames.has_animation("install_%d" % d) \
				and frames.get_frame_count("install_%d" % d) > 0:
			frames.add_frame(base, frames.get_frame_texture(
				"install_%d" % d, frames.get_frame_count("install_%d" % d) - 1))
		elif frames.has_animation(empty):
			for i in frames.get_frame_count(empty):
				frames.add_frame(base, frames.get_frame_texture(empty, i))
	frames.add_animation("wasted")
	frames.set_animation_loop("wasted", false)
	var wasted := _first_existing([
		"%s/wasted_%s.png" % [asset_dir, tn],
		"%s/wasted.png" % asset_dir])
	if wasted != "":
		frames.add_frame("wasted", load(wasted))
	else:
		frames.remove_animation("wasted")
	return frames


## Shared cannon install animation (`cannons_common/init-place_n00..02`)
## played before the per-type `place_*` frames. Returns [""] when absent.
static func cannon_install_frames() -> Array:
	var out: Array = []
	var frame := 0
	while true:
		var path := "%s/init-place_n%02d.png" % [CANNONS_COMMON, frame]
		if not ResourceLoader.exists(path):
			break
		out.append(load(path))
		frame += 1
	return out


## APC unload: `open_<team>_r<deg>_n00..01` door animation per facing.
## The open art shares the hull canvas, so no extra offsets are needed.
## Returns {"frames": SpriteFrames} or {}.
static func apc_open_set(asset_dir: String, team: int) -> Dictionary:
	var tn := team_name(team)
	var frames := SpriteFrames.new()
	var found := false
	for d in DIRECTIONS:
		var name := "open_%d" % d
		frames.add_animation(name)
		frames.set_animation_speed(name, 6.0)
		frames.set_animation_loop(name, false)
		var frame := 0
		while true:
			var path := "%s/open_%s_r%03d_n%02d.png" % [asset_dir, tn, d * 45, frame]
			if not ResourceLoader.exists(path):
				break
			frames.add_frame(name, load(path))
			frame += 1
		if frame == 0:
			frames.remove_animation(name)
		else:
			found = true
	if not found:
		return {}
	return {"frames": frames}


## Turret/gun layer for a unit type. Idle and fire art per the original
## engine: light/apc use neutral `top_r<deg>`, medium uses `topf_r<deg>`
## for BOTH idle and fire, heavy/missile_launcher use `top_<team>_r<deg>`.
## Returns {"frames", "canvas_off": per-hull-dir alignment, "hull_off",
## "aim_off", "scans"} or {} when the type has no layer.
static func turret_set(unit_name: String, asset_dir: String, team: int) -> Dictionary:
	var tn := team_name(team)
	var frames := SpriteFrames.new()
	var found := false
	var canvas_off := PackedVector2Array()
	canvas_off.resize(DIRECTIONS)
	for d in DIRECTIONS:
		var deg := d * 45
		# jeep gun layer: the gunner aim/fire art doubles as the layer
		# (aim = fire n00, flash = fire n01). The red master fallback keeps
		# the rig built for neutral hardware (team 0 has no `top_null`
		# art) — the layer stays invisible while unmanned, so the master
		# paint is never shown
		var idle := _first_existing([
			"%s/topf_r%03d.png" % [asset_dir, deg],          # medium (both states)
			"%s/top_%s_r%03d.png" % [asset_dir, tn, deg],    # heavy / missile launcher
			"%s/top_red_r%03d.png" % [asset_dir, deg],       # master fallback (team 0)
			"%s/top_r%03d.png" % [asset_dir, deg],           # light / apc
			"%s/fire_r%03d_n00.png" % [asset_dir, deg]])     # jeep
		if idle == "":
			continue
		for anim in ["turret", "turretfire"]:
			var path := idle
			if anim == "turretfire":
				path = _first_existing([
					"%s/fire_r%03d_n01.png" % [asset_dir, deg],   # jeep flash
					"%s/topf_%s_r%03d.png" % [asset_dir, tn, deg],
					"%s/topf_red_r%03d.png" % [asset_dir, deg],
					"%s/topf_r%03d.png" % [asset_dir, deg],
					idle])
			var name := "%s_%d" % [anim, d]
			frames.add_animation(name)
			frames.set_animation_speed(name, 1.0)
			frames.set_animation_loop(name, true)
			frames.add_frame(name, load(path))
			found = true
		var hull := _first_existing([
			"%s/base_%s_r%03d_n00.png" % [asset_dir, tn, deg],
			"%s/base_%s_r%03d_n00.png" % [asset_dir, tn, hull_source(d).dir * 45],
			"%s/empty_r%03d.png" % [asset_dir, deg],
			"%s/empty_r%03d.png" % [asset_dir, hull_source(d).dir * 45]])
		canvas_off[d] = _layer_offset(_canvas_size(hull), _canvas_size(idle))
	if not found:
		return {}
	# turret blowing off on destruction (`top_pop[_<team>]_n00..`)
	frames.add_animation("pop")
	frames.set_animation_speed("pop", 8.0)
	frames.set_animation_loop("pop", false)
	var pop_paths: Array = []
	for prefix in ["top_pop_%s" % tn, "top_pop"]:
		var pop := 0
		pop_paths = []
		while true:
			var path := "%s/%s_n%02d.png" % [asset_dir, prefix, pop]
			if not ResourceLoader.exists(path):
				break
			pop_paths.append(load(path))
			pop += 1
		if not pop_paths.is_empty():
			break
	if pop_paths.is_empty():
		frames.remove_animation("pop")
	else:
		for tex in pop_paths:
			frames.add_frame("pop", tex)
	# hull/aim offsets live on the per-type scenes (exported DoRender
	# tables) — only the art-derived canvas alignment is computed here
	return {"frames": frames, "canvas_off": canvas_off}


## Crane: arm layer (INVERTED rotation numbering — facing d lives in
## r{(d+4)%8*45}) plus the 16-frame hook. Never aims; arm follows the
## hull facing, hook swings on the same anchor.
static func crane_set(asset_dir: String) -> Dictionary:
	var frames := SpriteFrames.new()
	var canvas_off := PackedVector2Array()
	canvas_off.resize(DIRECTIONS)
	var found := false
	for d in DIRECTIONS:
		var art_deg: int = ROTATION_INVERTED_DEG[d]
		var arm := "%s/crane_r%03d.png" % [asset_dir, art_deg]
		if not ResourceLoader.exists(arm):
			continue
		var name := "arm_%d" % d
		frames.add_animation(name)
		frames.set_animation_speed(name, 1.0)
		frames.set_animation_loop(name, true)
		frames.add_frame(name, load(arm))
		found = true
		var hull := _first_existing([
			"%s/base_red_r%03d_n00.png" % [asset_dir, d * 45],
			"%s/base_red_r%03d_n00.png" % [asset_dir, mirrored_dir(d) * 45]])
		canvas_off[d] = _layer_offset(_canvas_size(hull), _canvas_size(arm))
	if not found:
		return {}
	frames.add_animation("hook")
	frames.set_animation_speed("hook", 10.0)
	frames.set_animation_loop("hook", true)
	var hook := 0
	while true:
		var path := "%s/hook_n%02d.png" % [asset_dir, hook]
		if not ResourceLoader.exists(path):
			break
		frames.add_frame("hook", load(path))
		hook += 1
	if hook == 0:
		frames.remove_animation("hook")
	return {"frames": frames, "canvas_off": canvas_off,
		"arm_off": PackedVector2Array(CRANE_TABLES.arm),
		"hook_off": PackedVector2Array(CRANE_TABLES.hook)}


const ROTATION_INVERTED_DEG := [180, 225, 270, 315, 0, 45, 90, 135]


## Offset that makes a centered layer sprite share the base canvas'
## top-left corner (the original sprites' common anchor).
static func _layer_offset(base_size: Vector2i, layer_size: Vector2i) -> Vector2:
	return (Vector2(layer_size) - Vector2(base_size)) * 0.5


static func _canvas_size(path: String) -> Vector2i:
	if path == "" or not ResourceLoader.exists(path):
		return Vector2i.ZERO
	var tex: Texture2D = load(path)
	return Vector2i(tex.get_width(), tex.get_height())


static func _first_existing(paths: Array) -> String:
	for path in paths:
		if ResourceLoader.exists(String(path)):
			return String(path)
	return ""


## Direction index mirrored horizontally (r000<->r180, r045<->r135...).
## The original art ships only the right-facing half; left-facing
## sprites render as horizontal flips of their mirror partner.
## EXCEPTION: the north/south pair — facing south derives from the
## north art with a VERTICAL flip (a horizontal flip of r090 is still
## r090-facing), see hull_source().
static func mirrored_dir(d: int) -> int:
	return wrapi(4 - d, 0, DIRECTIONS)


## Where the hull art for facing `d` really lives: the shipped half
## stores {E, NE, N, SE}; W/NW/SW are horizontal flips of their
## partners and SOUTH is NORTH rotated 180° (flip_x + flip_y — a pure
## vertical mirror is a reflection: left/right hull detail ends up on
## the wrong side). The tanks ship no r270 hulls at all (only the
## turret), so south is always synthesized — see _flipped for the
## shadow-band restore that keeps the art's bottom-lit convention.
## Returns {dir, flip_x, flip_y}.
static func hull_source(d: int) -> Dictionary:
	match d:
		4: return {"dir": 0, "flip_x": true, "flip_y": false}
		3: return {"dir": 1, "flip_x": true, "flip_y": false}
		5: return {"dir": 7, "flip_x": true, "flip_y": false}
		6: return {"dir": 2, "flip_x": true, "flip_y": true}
		_: return {"dir": d, "flip_x": false, "flip_y": false}


## Load the texture for direction `deg` from a path format; when the
## art only exists for the mirrored direction, return a flipped copy.
## PUBLIC: the shipped art covers {E, NE, N, SE} for hulls, turrets AND
## ground decals, so every consumer of a per-facing path needs this.
static func dir_texture(path_fmt: String, deg: int) -> Texture2D:
	var direct := path_fmt % deg
	if ResourceLoader.exists(direct):
		return load(direct)
	var mirror := path_fmt % (mirrored_dir(deg_to_dir(deg)) * 45)
	if ResourceLoader.exists(mirror):
		# get_image() is the texture's shared cache — flip a copy
		var img: Image = (load(mirror) as Texture2D).get_image().duplicate()
		img.flip_x()
		return ImageTexture.create_from_image(img)
	return null


static func deg_to_dir(deg: int) -> int:
	return wrapi(int(round(deg / 45.0)), 0, DIRECTIONS)


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


## Texture for a vehicle anim frame: the direct file, or a flipped copy
## of the shipped half's art (horizontal flip for W/NW/SW, vertical for
## S — see hull_source).
static func _vehicle_anim_texture(asset_dir: String, anim: String, tn: String,
		deg: int, frame: int, damaged: bool) -> Texture2D:
	var path := _vehicle_anim_path(asset_dir, anim, tn, deg, frame, damaged)
	if ResourceLoader.exists(path):
		return load(path)
	var src := hull_source(deg_to_dir(deg))
	var sdeg: int = src.dir * 45
	if anim == "base":
		var mirror_dmg := _vehicle_anim_path(asset_dir, anim, tn, sdeg, frame, damaged)
		if ResourceLoader.exists(mirror_dmg):
			return _flipped(mirror_dmg, src.flip_x, src.flip_y)
		# the gun/missile cannon's manned idle is a single `equiped` frame
		var equiped := "%s/equiped_%s_r%03d.png" % [asset_dir, tn, sdeg]
		if ResourceLoader.exists(equiped) and frame == 0:
			return _flipped(equiped, src.flip_x, src.flip_y)
		return null
	var mirror := _vehicle_anim_path(asset_dir, anim, tn, sdeg, frame, false)
	if ResourceLoader.exists(mirror):
		return _flipped(mirror, src.flip_x, src.flip_y)
	return null


## Degrees encoded in an `..._r<deg>...` filename.
static func _deg_of(path: String) -> int:
	var marker := path.rfind("_r")
	if marker < 0:
		return 0
	return int(path.substr(marker + 2, 3))


static func _flipped(path: String, flip_x := true, flip_y := false) -> Texture2D:
	# get_image() is the texture's shared cache — flip a copy, never the
	# original or a second flip request would double-flip the art
	var img: Image = (load(path) as Texture2D).get_image().duplicate()
	if flip_x:
		img.flip_x()
	if flip_y:
		img.flip_y()
		_restore_south_lighting(img, path, flip_x)
	return ImageTexture.create_from_image(img)


## Every shipped hull facing is lit "shadow along the canvas bottom"
## (verified across the heavy's facings and the APC/crane/jeep/ML sets,
## which DO ship genuine r270 art drawn that way). A flipped south hull
## puts that dark band on TOP, which reads as an upside-down body.
## Recolor the bottom rows with the original's shadow band and the top
## row with its bright rim — but only where BOTH the band pixel and the
## flipped hull are opaque: recolouring must never change the silhouette
## (pasting the wide band over a tapered front punched visible notches
## into the south light tank).
static func _restore_south_lighting(img: Image, path: String, mirror_x: bool) -> void:
	var src: Image = (load(path) as Texture2D).get_image()
	var h := img.get_height()
	var w := img.get_width()
	# how many bottom rows of the original are near-flat dark (the band)
	var band := 0
	for k in range(1, mini(7, h)):
		if _row_mean(src, h - k) >= 60.0 / 255.0:
			break
		band = k
	if band == 0:
		return
	for k in range(band):
		for x in w:
			var sx := w - 1 - x if mirror_x else x
			var c := src.get_pixel(sx, h - 1 - k)
			if c.a > 0.23 and img.get_pixel(x, h - 1 - k).a > 0.23:
				img.set_pixel(x, h - 1 - k, c)
	for x in w:
		var sx := w - 1 - x if mirror_x else x
		var c := src.get_pixel(sx, 0)
		if c.a > 0.23 and img.get_pixel(x, 0).a > 0.23:
			img.set_pixel(x, 0, c)


static func _row_mean(img: Image, y: int) -> float:
	var sum := 0.0
	var n := 0
	for x in img.get_width():
		var c := img.get_pixel(x, y)
		if c.a > 0.23:
			sum += (c.r + c.g + c.b) / 3.0
			n += 1
	return sum / n if n > 0 else 999.0


static func _vehicle_anim_path(asset_dir: String, anim: String, tn: String, deg: int, frame: int, damaged := false) -> String:
	match anim:
		"empty":
			var directional := "%s/empty_r%03d.png" % [asset_dir, deg]
			if ResourceLoader.exists(directional):
				return directional
			# A MANNED gun's PASSIVE look is this same `empty` set (its
			# gunner only shows in the fire frames), so for a real team it
			# has to stay DIRECTIONAL. Preferring the plain neutral frame
			# unconditionally gave all eight facings one fixed sprite:
			# the gun sat pointing one way, snapped to its aim for the
			# few frames of muzzle flash, then snapped back. That is the
			# "turrets flip direction when they shoot" spasm, and it hit
			# every type named `empty_<team>_r<deg>` (the missile cannon
			# and the vehicle hulls) while gatling and howitzer — which
			# ship team-less `empty_r<deg>` — were always fine.
			var team_dir := "%s/empty_%s_r%03d.png" % [asset_dir, tn, deg]
			if tn != "null" and ResourceLoader.exists(team_dir):
				return team_dir
			# unmanned hardware is never team-coloured: with no team
			# (tn == "null") the plain neutral frame still wins
			var plain := plain_empty_path(asset_dir, tn)
			if plain != "":
				return plain
			return team_dir  # last resort
		"base":
			if damaged:
				var dmg := "%s/base_damaged_%s_r%03d_n%02d.png" % [asset_dir, tn, deg, frame]
				if ResourceLoader.exists(dmg):
					return dmg
			var base_path := "%s/base_%s_r%03d_n%02d.png" % [asset_dir, tn, deg, frame]
			if ResourceLoader.exists(base_path):
				return base_path
			# the gun/missile cannon's manned idle is a single `equiped` frame
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


## True when the `fire_*` art lives on a different canvas than the hull —
## overlay art the turret layer owns (the jeep gunner), not a hull flash.
## Gatling/howitzer fire frames share the hull canvas exactly, so their
## legitimate one-shot hull flash keeps building.
static func _fire_art_is_overlay(asset_dir: String, tn: String) -> bool:
	var hull := _first_existing([
		"%s/base_%s_r000_n00.png" % [asset_dir, tn],
		"%s/equiped_%s_r000.png" % [asset_dir, tn],
		"%s/empty_r000.png" % [asset_dir]])
	var flash := _first_existing([
		"%s/fire_%s_r000_n00.png" % [asset_dir, tn],
		"%s/fire_r000_n00.png" % [asset_dir]])
	if hull == "" or flash == "":
		return false
	return _canvas_size(hull) != _canvas_size(flash)


## Jeep wheels: separate `under_*` sprites (shared art, no team prefix).
## The original ships no wheel art for the vertical facings (r090/r270) —
## the wheels are hidden behind the body — so those directions simply
## have no animation. Returns {"frames", "offsets"} or {}.
static func jeep_wheel_set(asset_dir: String, team: int, manned: bool) -> Dictionary:
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
			# align against the body canvas actually shown: the empty
			# hull while unmanned, the team base while crewed
			var body := _first_existing([
				"%s/empty_r%03d.png" % [asset_dir, d * 45] if not manned else "",
				"%s/base_%s_r%03d_n00.png" % [asset_dir, tn, d * 45],
				"%s/base_%s_r%03d_n00.png" % [asset_dir, tn, mirrored_dir(d) * 45],
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


## Directional effect frames (vehicle smoke/dust): `<dir>/<name>_r<deg>_n<frame>.png`.
static func dir_effect_frames(dir: String, name: String, d: int, fps: float) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.add_animation("fx")
	frames.set_animation_speed("fx", fps)
	frames.set_animation_loop("fx", true)
	var frame := 0
	while true:
		var path := "%s/%s_r%03d_n%02d.png" % [dir, name, d * 45, frame]
		if not ResourceLoader.exists(path):
			break
		frames.add_frame("fx", load(path))
		frame += 1
	if frame == 0:
		frames.remove_animation("fx")
	return frames
