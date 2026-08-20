class_name UiTheme
extends Object
## Original Z look applied as a Control theme: the GOG `Buttons.png` metal
## plate chrome for every button, the zod yellow_menu bitmap font (the
## classic gold Z menu typeface) as the default font, and the zod list art
## for ItemList / OptionButton popups. Art renders at its natural pixel
## size — corners are protected by stylebox margins so plates stretch
## cleanly to any button rect.

const UI_DIR := "res://assets/z/ui"
const BUTTON_DIR := "res://assets/z/ui/buttons"
const LIST_DIR := "res://assets/z/ui/buttons_list"
const FONT_PATH := "res://assets/z/ui/font/z_menu_yellow.fnt"

## Buttons.png is a 2x3 grid of 32x32 blank button faces (six subtle
## gradient variants of the same plate); cells double as hover/pressed.
const FACE_CELL := Vector2i(32, 32)
const FACE_MARGIN := 8  # rounded-corner + bevel inset of one face

static var _cache := {}  # key -> StyleBoxTexture
static var _font: FontFile
static var _trimmed := {}  # path -> Texture2D (art cropped to its opaque region)


## Give a screen the original look. Safe to call repeatedly.
static func apply(root: Control) -> void:
	var theme := Theme.new()
	if font() != null:
		theme.default_font = font()
		theme.default_font_size = 16

	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := button(state)
		if sb != null:
			theme.set_stylebox(state, "Button", sb)
			theme.set_stylebox(state, "OptionButton", sb)
	theme.set_stylebox("normal", "PopupMenu", list_panel())
	theme.set_stylebox("panel", "ItemList", list_panel())
	theme.set_stylebox("panel", "PopupMenu", list_panel())
	theme.set_stylebox("selected", "ItemList", list_entry())
	theme.set_stylebox("selected_focus", "ItemList", list_entry())
	theme.set_stylebox("hover", "PopupMenu", list_entry())

	# glyphs ship pre-coloured (gold with dark outline) — never tint them
	for state in ["", "_hover", "_pressed", "_disabled", "_focus"]:
		theme.set_color("font%s_color" % state, "Button", Color.WHITE)
		theme.set_color("font%s_color" % state, "OptionButton", Color.WHITE)
	theme.set_color("font_color", "ItemList", Color.WHITE)
	theme.set_color("font_selected_color", "ItemList", Color.WHITE)
	theme.set_color("font_color", "PopupMenu", Color.WHITE)
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	theme.set_color("font_color", "Label", Color(1.0, 0.95, 0.8))
	theme.set_color("font_color", "LineEdit", Color.WHITE)
	theme.set_stylebox("panel", "PanelContainer", StyleBoxEmpty.new())
	_theme_slider(theme)
	_theme_scrollbar(theme)
	root.theme = theme


## The in-game HUD's own typeface — the chunky white bitmap set the
## original prints the clock and the army counts in. The gold menu font
## is for menus; on a 20px HUD slot it reads as decoration.
const HUD_FONT_PATH := "res://assets/z/ui/font/z_big_white.fnt"
static var _hud_font: FontFile


static func hud_font() -> FontFile:
	if _hud_font == null and ResourceLoader.exists(HUD_FONT_PATH):
		_hud_font = load(HUD_FONT_PATH)
		if _hud_font != null and _hud_font.fallbacks.is_empty():
			_hud_font.fallbacks = [ThemeDB.fallback_font]
	return _hud_font


static func font() -> FontFile:
	if _font == null and ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
		# the bitmap set has no $ ( ) & # — route those to the engine font
		if _font != null and _font.fallbacks.is_empty():
			_font.fallbacks = [ThemeDB.fallback_font]
	return _font


## Several zod menu art files are 512x512 canvases with the actual art
## in a smaller opaque region (Background/splash: 480x320) — the padding
## would render as window-clear-colour bands. This crops to the art.
static func trimmed(path: String) -> Texture2D:
	if _trimmed.has(path):
		return _trimmed[path]
	var out: Texture2D = null
	if ResourceLoader.exists(path):
		var base := load(path) as Texture2D
		var used: Rect2i = base.get_image().get_used_rect()
		if used.size.x > 0 and used.size.y > 0 \
				and used.size != base.get_image().get_size():
			var crop := AtlasTexture.new()
			crop.atlas = base
			crop.region = Rect2(used)
			out = crop
		else:
			out = base
	_trimmed[path] = out
	return out


## Sliders from the GOG plate art: dark track, metal knob cut from the
## plate face so volume rows match the button chrome.
static func _theme_slider(theme: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.05, 0.06, 0.05, 0.85)
	track.set_corner_radius_all(2)
	track.content_margin_top = 3.0
	track.content_margin_bottom = 3.0
	var filled := StyleBoxFlat.new()
	filled.bg_color = Color(0.45, 0.38, 0.18)
	filled.set_corner_radius_all(2)
	filled.content_margin_top = 3.0
	filled.content_margin_bottom = 3.0
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", filled)
	var knob := _knob()
	if knob != null:
		theme.set_icon("grabber_icon", "HSlider", knob)
		theme.set_icon("grabber_highlight_icon", "HSlider", knob)


## Scrollbars from the zod list art. The list frame's RIGHT column is
## 15px wide precisely because it is the original's scroll gutter
## (`list_right`/`list_top_right`/`list_bottom_right` are all 15 wide),
## and the set ships `list_scroller` plus up/down arrow buttons. None of
## it was wired, so every scrolling list drew Godot's default grey
## scrollbar inside Z's gutter.
static func _theme_scrollbar(theme: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.06, 0.06, 0.07, 0.7)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(0.62, 0.55, 0.30)
	grabber.set_corner_radius_all(1)
	var grabber_hi := grabber.duplicate() as StyleBoxFlat
	grabber_hi.bg_color = Color(0.80, 0.72, 0.40)
	var scroller := _tex("%s/list_scroller.png" % LIST_DIR)
	for kind in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", kind, track)
		theme.set_stylebox("scroll_focus", kind, track)
		theme.set_stylebox("grabber", kind, grabber)
		theme.set_stylebox("grabber_highlight", kind, grabber_hi)
		theme.set_stylebox("grabber_pressed", kind, grabber_hi)
		if scroller != null:
			# the grabber cap art, drawn at both ends of the thumb
			theme.set_icon("grabber_icon", kind, scroller)
	var up := _tex("%s/list_button_up_normal.png" % LIST_DIR)
	var down := _tex("%s/list_button_down_normal.png" % LIST_DIR)
	if up != null and down != null:
		theme.set_icon("decrement", "VScrollBar", up)
		theme.set_icon("increment", "VScrollBar", down)
		theme.set_icon("decrement_highlight", "VScrollBar", up)
		theme.set_icon("increment_highlight", "VScrollBar", down)
		theme.set_icon("decrement_pressed", "VScrollBar",
			_tex("%s/list_button_up_pressed.png" % LIST_DIR))
		theme.set_icon("increment_pressed", "VScrollBar",
			_tex("%s/list_button_down_pressed.png" % LIST_DIR))


static func _tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


static func _knob() -> AtlasTexture:
	if _cache.has("knob"):
		return _cache["knob"]
	var faces := load("%s/Buttons.png" % UI_DIR) as Texture2D
	if faces == null:
		return null
	# a 14x14 metal square out of the resting plate face
	var knob := AtlasTexture.new()
	knob.atlas = faces
	knob.region = Rect2i(Vector2i(9, 9), Vector2i(14, 14))
	_cache["knob"] = knob
	return knob


## One button stylebox per state from the GOG plate art. Falls back to the
## zod nine-piece chrome when Buttons.png is missing.
static func button(state: String) -> StyleBoxTexture:
	if _cache.has("face_" + state):
		return _cache["face_" + state]
	if state == "focus":
		return null  # no focus ring — the plate art is its own indicator
	var faces := load("%s/Buttons.png" % UI_DIR) as Texture2D
	if faces == null:
		return _zod_button(state)
	# plate variants out of the six available: row 0 col 0 rest, row 0 col 1
	# hover, row 1 col 0 pressed — the six faces are near-identical gradient
	# renders of the same chrome, so any assignment reads as the same button
	var cell: Vector2i = {
		"normal": Vector2i(0, 0), "hover": Vector2i(32, 0),
		"pressed": Vector2i(0, 32), "disabled": Vector2i(0, 0),
	}.get(state, Vector2i(0, 0))
	var face := AtlasTexture.new()
	face.atlas = faces
	face.region = Rect2i(cell, FACE_CELL)
	var box := StyleBoxTexture.new()
	box.texture = face
	box.texture_margin_left = FACE_MARGIN
	box.texture_margin_right = FACE_MARGIN
	box.texture_margin_top = FACE_MARGIN
	box.texture_margin_bottom = FACE_MARGIN
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 6.0
	match state:
		"hover":
			box.modulate_color = Color(1.15, 1.12, 1.0)
		"pressed":
			box.modulate_color = Color(0.78, 0.78, 0.78)
			box.content_margin_top = 8.0  # text rides down with the plate
			box.content_margin_bottom = 4.0
		"disabled":
			box.modulate_color = Color(0.55, 0.55, 0.55)
	_cache["face_" + state] = box
	return box


## The zod nine-piece 2x chrome, kept as the fallback button skin.
static func _zod_button(state: String) -> StyleBoxTexture:
	var prefix := "generic_button_pressed" if state == "pressed" else "generic_button_normal"
	return _nine_piece(BUTTON_DIR, prefix, 2)


## Compose <dir>/<prefix>_<part>.png into ONE nine-patch texture.
##
## The old placement table was wrong for 6 of the 9 pieces:
## `part.ends_with("left")` is also true for "top_left" and
## "bottom_left", so the left column and both left corners were blended
## at x = left_width instead of 0; `right` landed at y = 0 instead of the
## middle row; and only the bare "bottom" piece matched
## `ends_with("bottom")`, so both bottom corners sat in the middle row.
## The composed atlas was scrambled, which is what made the map list's
## right-hand scroll gutter render as a stack of mismatched colour
## blocks. Placement is now an explicit (col, row) table.
##
## The margins come from the CORNERS, not the edge strips. This art is
## not a uniform frame — zod's list ships 3px top/left edges but 17px
## corners, because the right column is the 15px-wide scrollbar gutter.
## Slicing at the edge heights cut straight through the corner art. The
## thin edge strips are TILED to fill their row/column so nothing is
## left transparent.
const NINE_LAYOUT := {
	"top_left": Vector2i(0, 0), "top": Vector2i(1, 0), "top_right": Vector2i(2, 0),
	"left": Vector2i(0, 1), "center": Vector2i(1, 1), "right": Vector2i(2, 1),
	"bottom_left": Vector2i(0, 2), "bottom": Vector2i(1, 2),
	"bottom_right": Vector2i(2, 2),
}


static func _nine_piece(dir: String, prefix: String, s: int) -> StyleBoxTexture:
	var cache_key := "%s/%s/%d" % [dir, prefix, s]
	if _cache.has(cache_key):
		return _cache[cache_key]
	var pieces := {}
	for part in NINE_LAYOUT:
		var path := "%s/%s_%s.png" % [dir, prefix, part]
		if ResourceLoader.exists(path):
			var img: Image = (load(path) as Texture2D).get_image()
			img.convert(Image.FORMAT_RGBA8)
			img.resize(img.get_width() * s, img.get_height() * s,
				Image.INTERPOLATE_NEAREST)
			pieces[part] = img
	if pieces.is_empty():
		return StyleBoxTexture.new()
	# column widths / row heights = the widest (tallest) piece in each
	# band, so a corner is never sliced through
	var cols := [0, 0, 0]
	var rows := [0, 0, 0]
	for part in pieces:
		var at: Vector2i = NINE_LAYOUT[part]
		var img: Image = pieces[part]
		if at.x != 1:
			cols[at.x] = maxi(cols[at.x], img.get_width())
		if at.y != 1:
			rows[at.y] = maxi(rows[at.y], img.get_height())
	# the stretchable middle band: the center piece when there is one,
	# else the edge strips' own run length
	cols[1] = _band(pieces, ["center", "top", "bottom"], true, 29 * s)
	rows[1] = _band(pieces, ["center", "left", "right"], false, 11 * s)
	var composed := Image.create(cols[0] + cols[1] + cols[2],
		rows[0] + rows[1] + rows[2], false, Image.FORMAT_RGBA8)
	for part in pieces:
		var at: Vector2i = NINE_LAYOUT[part]
		var origin := Vector2i(
			0 if at.x == 0 else (cols[0] if at.x == 1 else cols[0] + cols[1]),
			0 if at.y == 0 else (rows[0] if at.y == 1 else rows[0] + rows[1]))
		_tile_into(composed, pieces[part], origin,
			Vector2i(cols[at.x], rows[at.y]))
	var box := StyleBoxTexture.new()
	box.texture = ImageTexture.create_from_image(composed)
	box.texture_margin_left = cols[0]
	box.texture_margin_right = cols[2]
	box.texture_margin_top = rows[0]
	box.texture_margin_bottom = rows[2]
	_cache[cache_key] = box
	return box


## Middle-band size: the first present piece's extent along `horizontal`.
static func _band(pieces: Dictionary, order: Array, horizontal: bool,
		fallback: int) -> int:
	for part in order:
		if pieces.has(part):
			var img: Image = pieces[part]
			return img.get_width() if horizontal else img.get_height()
	return fallback


## Repeat `img` over a `size` region at `origin` (clipped). A 3px edge
## strip has to fill a 17px-tall corner band without leaving a hole.
static func _tile_into(dst: Image, img: Image, origin: Vector2i,
		size: Vector2i) -> void:
	var y := 0
	while y < size.y:
		var x := 0
		while x < size.x:
			var w: int = mini(img.get_width(), size.x - x)
			var h: int = mini(img.get_height(), size.y - y)
			dst.blend_rect(img, Rect2i(Vector2i.ZERO, Vector2i(w, h)),
				origin + Vector2i(x, y))
			x += img.get_width()
		y += img.get_height()


static func list_panel() -> StyleBoxTexture:
	return _nine_piece(LIST_DIR, "list", 2)


static func list_entry() -> StyleBoxTexture:
	return _nine_piece(LIST_DIR, "list_entry_pressed", 2)
