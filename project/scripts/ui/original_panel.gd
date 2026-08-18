class_name OriginalPanel
extends Object
## Original GOG HUD panel art, displayed at its natural size so nothing
## distorts: BoxLeft/BoxRight caps (64px each) with BoxCentre between —
## wide = 640x256, narrow = 384x256. Attach to a plain Control (never a
## container — containers override the slice anchors) whose size matches
## PANEL_WIDE / PANEL_NARROW. Falls back silently when art is missing.

const UI_DIR := "res://assets/z/ui"
const PANEL_WIDE := Vector2(640, 256)
const PANEL_NARROW := Vector2(384, 256)
const CAP_WIDTH := 64.0


static func attach(panel: Control, narrow := false) -> void:
	var left := _tex("BoxLeft.png")
	var right := _tex("BoxRight.png")
	var centre := _tex("BoxCentreNarrow.png" if narrow else "BoxCentreWide.png")
	if left == null or right == null or centre == null:
		return
	panel.custom_minimum_size = PANEL_NARROW if narrow else PANEL_WIDE
	_slice(panel, left, centre, right)


static func _tex(file: String) -> Texture2D:
	var path := "%s/%s" % [UI_DIR, file]
	return load(path) if ResourceLoader.exists(path) else null


static func _slice(panel: Control, left: Texture2D, centre: Texture2D, right: Texture2D) -> void:
	var l := TextureRect.new()
	l.texture = left
	l.stretch_mode = TextureRect.STRETCH_SCALE
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.anchor_bottom = 1.0
	l.offset_right = CAP_WIDTH
	_place_bottom(panel, l)

	var c := TextureRect.new()
	c.texture = centre
	c.stretch_mode = TextureRect.STRETCH_SCALE
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = CAP_WIDTH
	c.offset_right = -CAP_WIDTH
	_place_bottom(panel, c)

	var r := TextureRect.new()
	r.texture = right
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = 1.0
	r.anchor_bottom = 1.0
	r.offset_left = -CAP_WIDTH
	_place_bottom(panel, r)


static func _place_bottom(panel: Control, rect: TextureRect) -> void:
	panel.add_child(rect)
	panel.move_child(rect, 0)
