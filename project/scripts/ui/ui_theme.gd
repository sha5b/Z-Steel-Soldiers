class_name UiTheme
extends Object
## Original Z UI styling: the 1996 nine-piece button art (zod
## main_menu_gui) composed into Godot styleboxes, applied as a Control
## theme so every Button/ItemList on a screen picks it up. Art is 1x
## pixel art, composed at 2x to match the 16x16-sprites-at-2x world.

const BUTTON_DIR := "res://assets/z/ui/buttons"
const DISPLAY_SCALE := 2

static var _button_cache := {}  # prefix -> StyleBoxTexture


## Give a screen the original look: gold text, original button chrome.
static func apply(root: Control) -> void:
	var theme := Theme.new()
	theme.set_stylebox("normal", "Button", button("generic_button_normal"))
	theme.set_stylebox("hover", "Button", button("generic_button_normal"))
	theme.set_stylebox("pressed", "Button", button("generic_button_pressed"))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", Color(1.0, 0.95, 0.75))
	theme.set_color("font_pressed_color", "Button", Color(1.0, 1.0, 0.9))
	theme.set_color("font_hover_color", "Button", Color(1.0, 1.0, 0.85))
	theme.set_font_size("font_size", "Button", 16)
	theme.set_stylebox("panel", "PanelContainer", StyleBoxFlat.new())
	root.theme = theme


## Compose the nine pieces `<prefix>_<part>.png` into one scaled texture
## with matching margins — corners stay crisp, the middle stretches.
static func button(prefix: String) -> StyleBoxTexture:
	if _button_cache.has(prefix):
		return _button_cache[prefix]
	var pieces := {
		"top_left": Vector2i(2, 2), "top": Vector2i(93, 2), "top_right": Vector2i(2, 2),
		"left": Vector2i(2, 11), "center": Vector2i(29, 11), "right": Vector2i(2, 11),
		"bottom_left": Vector2i(2, 2), "bottom": Vector2i(93, 2), "bottom_right": Vector2i(2, 2),
	}
	var s := DISPLAY_SCALE
	var composed := Image.create(97 * s, 15 * s, false, Image.FORMAT_RGBA8)
	for part in pieces:
		var path := "%s/%s_%s.png" % [BUTTON_DIR, prefix, part]
		if not ResourceLoader.exists(path):
			continue
		var img: Image = (load(path) as Texture2D).get_image()
		img.convert(Image.FORMAT_RGBA8)  # pieces load as mixed RGB/RGBA
		img.resize(pieces[part].x * s, pieces[part].y * s, Image.INTERPOLATE_NEAREST)
		var pos: Vector2i = {
			"top_left": Vector2i(0, 0), "top": Vector2i(2 * s, 0), "top_right": Vector2i(95 * s, 0),
			"left": Vector2i(0, 2 * s), "center": Vector2i(2 * s, 2 * s), "right": Vector2i(95 * s, 2 * s),
			"bottom_left": Vector2i(0, 13 * s), "bottom": Vector2i(2 * s, 13 * s), "bottom_right": Vector2i(95 * s, 13 * s),
		}[part]
		composed.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), pos)
	var box := StyleBoxTexture.new()
	box.texture = ImageTexture.create_from_image(composed)
	box.texture_margin_left = 2 * s
	box.texture_margin_right = 2 * s
	box.texture_margin_top = 2 * s
	box.texture_margin_bottom = 2 * s
	_button_cache[prefix] = box
	return box
