class_name Teams
extends Object
## Single source of truth for team identity: display name, UI/minimap/zone
## colors and the verified 16-shade paint ramps used by the palette-swap
## shader. All game art ships as ONE master set (the red files); every
## other team is the master art + a team_palette material — see
## shaders/team_palette.gdshader.
##
## The ramps below are the original engine's hand-tuned team palettes
## (global palette indices 16-31 per team, verified pixel-exact against
## the shipped red/blue/green/yellow sprite variants). Add a team by
## adding a ramp + entry here; everything (sprites, flags, icons,
## minimap, UI accents) follows automatically.

const MASTER_TEAM := 1  # the red set is the master art on disk
const MASTER_SUFFIX := "red"

const RAMP_RED := [
	Color("2b0000"), Color("430000"), Color("5f0000"), Color("780000"),
	Color("8f0000"), Color("ab0000"), Color("c70000"), Color("df0000"),
	Color("df1313"), Color("e72f2f"), Color("eb4747"), Color("f06363"),
	Color("f07f7f"), Color("f09f9f"), Color("f7bbbb"), Color("fbdbdb"),
]
const RAMP_BLUE := [
	Color("00002b"), Color("000043"), Color("00036f"), Color("00078f"),
	Color("000faf"), Color("001bd7"), Color("0027fb"), Color("1337fb"),
	Color("2f4bfb"), Color("4b5ffb"), Color("6373fb"), Color("7f87fb"),
	Color("9b9ffb"), Color("afb7fb"), Color("cfcffb"), Color("ebebfb"),
]
const RAMP_GREEN := [
	Color("000b03"), Color("001f07"), Color("00330b"), Color("00470b"),
	Color("035b0b"), Color("036f07"), Color("0f7f07"), Color("178f13"),
	Color("279b2b"), Color("3cab43"), Color("4fb75f"), Color("6bbf7b"),
	Color("7fcf97"), Color("9fdfaf"), Color("bfebcf"), Color("e7fbf0"),
]
const RAMP_YELLOW := [
	Color("2b0000"), Color("430300"), Color("5b0b00"), Color("781700"),
	Color("8f2b00"), Color("ab3f00"), Color("bf5b00"), Color("cb632f"),
	Color("d76f3c"), Color("df7b47"), Color("e78f4f"), Color("eb9f5b"),
	Color("f0b763"), Color("f0cb6f"), Color("f7df78"), Color("fbf07f"),
]

## team id -> {name, ui accent, minimap blip/zone tint}
const TEAMS := {
	1: {"name": "red", "ui": Color(1.0, 0.25, 0.2), "mini": Color(1.0, 0.30, 0.25)},
	2: {"name": "blue", "ui": Color(0.25, 0.5, 1.0), "mini": Color(0.35, 0.55, 1.0)},
	3: {"name": "green", "ui": Color(0.3, 0.9, 0.3), "mini": Color(0.35, 0.85, 0.35)},
	4: {"name": "yellow", "ui": Color(1.0, 0.9, 0.2), "mini": Color(1.0, 0.9, 0.3)},
}
const RAMP_SHADES := 16

const NEUTRAL_ZONE_COLOR := Color(0.85, 0.85, 0.85, 0.9)

static var _lut: ImageTexture
static var _materials := {}


static func exists(team: int) -> bool:
	return TEAMS.has(team)


static func display_name(team: int) -> String:
	var info: Dictionary = TEAMS.get(team, {})
	return String(info.get("name", "null"))


static func ui_color(team: int) -> Color:
	var info: Dictionary = TEAMS.get(team, {})
	return info.get("ui", Color(0.8, 0.8, 0.8)) as Color


static func minimap_color(team: int) -> Color:
	var info: Dictionary = TEAMS.get(team, {})
	return info.get("mini", Color(0.6, 0.6, 0.6)) as Color


static func zone_color(team: int) -> Color:
	return minimap_color(team) if team != 0 else NEUTRAL_ZONE_COLOR


static func ramp(team: int) -> Array:
	if team == MASTER_TEAM:
		return RAMP_RED
	return {
		2: RAMP_BLUE, 3: RAMP_GREEN, 4: RAMP_YELLOW,
	}.get(team, RAMP_RED)


## 16 x N lookup texture: row 0 = master (red) ramp, row t = team t's
## ramp. The shader matches fragment colours against row 0 and replaces
## them with the target row — anything not in the master ramp passes
## through untouched, so the material is safe on neutral art too.
static func lut_texture() -> ImageTexture:
	if _lut != null:
		return _lut
	var img := Image.create(RAMP_SHADES, TEAMS.size() + 1, false, Image.FORMAT_RGBA8)
	for i in RAMP_SHADES:
		img.set_pixel(i, 0, RAMP_RED[i])
	for team in TEAMS:
		var shades := ramp(team)
		for i in RAMP_SHADES:
			img.set_pixel(i, team, shades[i])
	_lut = ImageTexture.create_from_image(img)
	return _lut


## Team tint material for team-painted sprites. Returns null when no
## recolour is needed: neutral hardware (team 0) and the master team
## itself (the art is already correct — avoids any shader rounding).
static func material_for(team: int) -> ShaderMaterial:
	if team == 0 or team == MASTER_TEAM or not TEAMS.has(team):
		return null
	if _materials.has(team):
		return _materials[team]
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/team_palette.gdshader")
	mat.set_shader_parameter("lut", lut_texture())
	mat.set_shader_parameter("team_row", team)
	_materials[team] = mat
	return mat


## Convenience: assign (or clear) the tint on any canvas item.
static func apply(node: CanvasItem, team: int) -> void:
	if node == null:
		return
	node.material = material_for(team)


static var _tint_cache := {}


## Master-ramp pixel swap for art that can't take a node material (Button
## icons, anything drawn inside shared controls). Returns a cached
## recoloured copy of `texture` for `team` — the master team and neutral
## team 0 get the original back untouched.
static func tinted_texture(texture: Texture2D, team: int) -> Texture2D:
	if texture == null or team == 0 or team == MASTER_TEAM or not TEAMS.has(team):
		return texture
	var key := "%d_%d" % [texture.get_instance_id(), team]
	if _tint_cache.has(key):
		return _tint_cache[key]
	# get_image() returns the texture's SHARED cached image — never mutate
	# it in place or the original art is corrupted for everyone
	var img: Image = texture.get_image().duplicate()
	var shades := ramp(team)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			for i in RAMP_SHADES:
				if absf(c.r - RAMP_RED[i].r) <= _EPS \
						and absf(c.g - RAMP_RED[i].g) <= _EPS \
						and absf(c.b - RAMP_RED[i].b) <= _EPS:
					img.set_pixel(x, y, Color(shades[i], c.a))
					break
	var out := ImageTexture.create_from_image(img)
	_tint_cache[key] = out
	return out


const _EPS := 2.0 / 255.0
