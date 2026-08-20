class_name HudButton
extends Object
## The HUD's lettered buttons, drawn from the original's own three-state
## plates: `btn_<letter>_{inactive,active,pressed}.png` (24x20, Menu
## 56x20).
##
## The frame art already draws a plate in every slot, so a button here is
## a bare hit-box carrying the state art — no theme chrome, no border, or
## it would double-frame what the panel behind it already drew.

const HUD_DIR := "res://assets/z/ui/hud"


## `lit` starts the button on its ACTIVE plate — which is how the frame
## art draws the bottom bar's action buttons (R/V/B/G/Menu), while the
## sidebar's mode toggles (A/T/D/Z) are drawn inactive.
static func make(letter: String, at: Vector2, size: Vector2, tooltip: String,
		lit := false) -> Button:
	var btn := Button.new()
	btn.position = at
	btn.size = size
	btn.custom_minimum_size = size
	btn.tooltip_text = tooltip
	btn.focus_mode = Control.FOCUS_NONE
	btn.flat = true
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var art := TextureRect.new()
	art.name = "Plate"
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.add_child(art)
	btn.set_meta("letter", letter)
	btn.set_meta("lit", lit)
	set_state(btn, lit)
	# held-down feedback, then back to whatever the button's state is
	btn.button_down.connect(func(): _plate(btn, "pressed"))
	btn.button_up.connect(func(): set_state(btn, bool(btn.get_meta("lit", false))))
	return btn


## Latch the button on or off (the sidebar's mode toggles use this; the
## bottom bar's actions stay latched on).
static func set_state(btn: Button, on: bool) -> void:
	btn.set_meta("lit", on)
	_plate(btn, "active" if on else "inactive")


static func _plate(btn: Button, state: String) -> void:
	var art := btn.get_node_or_null("Plate") as TextureRect
	if art == null:
		return
	var path := "%s/btn_%s_%s.png" % [HUD_DIR, String(btn.get_meta("letter", "")),
			state]
	art.texture = load(path) if ResourceLoader.exists(path) else null
