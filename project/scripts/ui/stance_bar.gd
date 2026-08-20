class_name StanceBar
extends HBoxContainer
## Order-stance selector beside the minimap: what a right-click order
## DOES (R move without attacking, Q attack-move, E defend-and-hold)
## plus the smart-idle toggle (grab hand, T — idle robots auto-man
## nearby hardware and walk to capturable flags). Original zod cursor
## art; the active state tints, hotkeys Q/E/R/T mirror the buttons.
## Compact panel chrome — the full-size button plates would dwarf a
## 24px icon button.

const CURSOR_DIR := "res://assets/z/ui/cursor"
const BUTTON := 24.0

var _buttons: Array[Button] = []
var _toggle: Button = null


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var defs := [
		["cursor_red_n00", "Move without attacking (R)", SelectionManager.OrderStance.MOVE],
		["attack_red_n00", "Attack move (Q)", SelectionManager.OrderStance.ATTACK_MOVE],
		["place_red_n00", "Defend position (E)", SelectionManager.OrderStance.DEFEND],
	]
	for d in defs:
		var btn := _make_button(String(d[0]), String(d[1]))
		var stance: int = d[2]
		btn.pressed.connect(func():
			SelectionManager.current.set_stance(stance)
			Fx.ui_click())
		_buttons.append(btn)
		add_child(btn)
	_toggle = _make_button("grab_red_n00", "Smart idle (T): robots auto-man\nhardware and capture flags")
	_toggle.toggle_mode = true
	_toggle.button_pressed = GameSettings.auto_idle
	_toggle.toggled.connect(func(on: bool):
		GameSettings.set_auto_idle(on)
		Fx.ui_click())
	add_child(_toggle)
	# hotkeys change stance/idle outside the bar — signals keep the
	# visuals honest (this used to poll every frame)
	SelectionManager.current.stance_changed.connect(_sync_visuals)
	GameSettings.auto_idle_changed.connect(func(on: bool):
		_toggle.set_pressed_no_signal(on))
	_sync_visuals()


func _sync_visuals() -> void:
	var active := _buttons[SelectionManager.current.order_stance]
	for i in _buttons.size():
		var selected: bool = _buttons[i] == active
		_buttons[i].modulate = Color.WHITE if selected else Color(0.55, 0.55, 0.55)


func _make_button(icon: String, tooltip: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(BUTTON, BUTTON)
	btn.tooltip_text = tooltip
	btn.focus_mode = Control.FOCUS_NONE
	var path := "%s/%s.png" % [CURSOR_DIR, icon]
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		if icon == "cursor_red_n00":
			tex = _centred(tex)  # the arrow's hotspot is top-left — nudge it
		btn.icon = tex
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	for state in ["normal", "hover", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(state, _chrome(state))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return btn


## Mini panel-style chrome matching the minimap frame next to the bar.
func _chrome(state: String) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.06, 0.05, 0.9)
	box.border_color = Color(0.35, 0.38, 0.3)
	box.set_border_width_all(1)
	box.set_corner_radius_all(2)
	if state == "hover":
		box.bg_color = Color(0.12, 0.13, 0.1, 0.95)
	elif state == "pressed":
		box.bg_color = Color(0.02, 0.03, 0.02, 0.95)
	return box


## The plain cursor art draws its arrow around the (0,0) hotspot, so a
## centred button face shows it off-centre — copy the canvas shifted so
## the CONTENT sits mid-frame.
static func _centred(tex: Texture2D) -> Texture2D:
	var img: Image = tex.get_image().duplicate()
	var moved := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	moved.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(2, 2))
	return ImageTexture.create_from_image(moved)
