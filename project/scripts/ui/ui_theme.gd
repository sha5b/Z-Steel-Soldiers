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
	root.theme = theme


static func font() -> FontFile:
	if _font == null and ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
		# the bitmap set has no $ ( ) & # — route those to the engine font
		if _font != null and _font.fallbacks.is_empty():
			_font.fallbacks = [ThemeDB.fallback_font]
	return _font


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


## Compose <dir>/<prefix>_<part>.png into one scaled texture; part layout
## is derived from the pieces' real sizes. Corners stay crisp.
static func _nine_piece(dir: String, prefix: String, s: int) -> StyleBoxTexture:
	var cache_key := "%s/%s/%d" % [dir, prefix, s]
	if _cache.has(cache_key):
		return _cache[cache_key]
	var pieces := {}
	for part in ["top_left", "top", "top_right", "left", "center", "right",
			"bottom_left", "bottom", "bottom_right"]:
		var path := "%s/%s_%s.png" % [dir, prefix, part]
		if ResourceLoader.exists(path):
			var img: Image = (load(path) as Texture2D).get_image()
			img.convert(Image.FORMAT_RGBA8)
			img.resize(img.get_width() * s, img.get_height() * s,
				Image.INTERPOLATE_NEAREST)
			pieces[part] = img
	if pieces.is_empty():
		var empty := StyleBoxTexture.new()
		return empty
	var lw := 0
	var rw := 0
	var th := 0
	var bh := 0
	if pieces.has("left"):
		lw = (pieces["left"] as Image).get_width()
	if pieces.has("right"):
		rw = (pieces["right"] as Image).get_width()
	if pieces.has("top"):
		th = (pieces["top"] as Image).get_height()
	if pieces.has("bottom"):
		bh = (pieces["bottom"] as Image).get_height()
	var cw := 29 * s
	var ch := 11 * s
	if pieces.has("center"):
		cw = (pieces["center"] as Image).get_width()
		ch = (pieces["center"] as Image).get_height()
	var composed := Image.create(lw + cw + rw, th + ch + bh, false,
		Image.FORMAT_RGBA8)
	for part in pieces:
		var img: Image = pieces[part]
		var pos := Vector2i(
			lw if part.ends_with("left") or part == "top" or part == "center" else 0,
			th if part.begins_with("bottom") or part == "left" or part == "center" else 0)
		if part == "top_right" or part == "right" or part == "bottom_right":
			pos.x = composed.get_width() - img.get_width()
		if part.ends_with("bottom"):
			pos.y = composed.get_height() - img.get_height()
		composed.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), pos)
	var box := StyleBoxTexture.new()
	box.texture = ImageTexture.create_from_image(composed)
	box.texture_margin_left = lw
	box.texture_margin_right = rw
	box.texture_margin_top = th
	box.texture_margin_bottom = bh
	_cache[cache_key] = box
	return box


static func list_panel() -> StyleBoxTexture:
	return _nine_piece(LIST_DIR, "list", 2)


static func list_entry() -> StyleBoxTexture:
	return _nine_piece(LIST_DIR, "list_entry_pressed", 2)
