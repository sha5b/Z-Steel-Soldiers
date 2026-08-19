class_name StanceBar
extends HBoxContainer
## Order-stance selector beside the minimap: what a right-click order
## DOES (W move without attacking, A attack-move, D defend-and-hold)
## plus the smart-idle toggle (grab hand — idle robots auto-man nearby
## hardware and walk to capturable flags). Original zod cursor art; the
## active state tints, hotkeys A/D/W mirror the buttons.

const CURSOR_DIR := "res://assets/z/ui/cursor"
const BUTTON := 30.0

var _buttons: Array[Button] = []
var _toggle: Button = null


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var defs := [
		["cursor_red_n00", "Move without attacking (W)", MatchState.OrderStance.MOVE],
		["attack_red_n00", "Attack move (A)", MatchState.OrderStance.ATTACK_MOVE],
		["place_red_n00", "Defend position (D)", MatchState.OrderStance.DEFEND],
	]
	for d in defs:
		var btn := _make_button(String(d[0]), String(d[1]))
		var stance: int = d[2]
		btn.pressed.connect(func():
			MatchState.order_stance = stance
			Fx.ui_click())
		_buttons.append(btn)
		add_child(btn)
	_toggle = _make_button("grab_red_n00", "Smart idle: robots auto-man\nhardware and capture flags")
	_toggle.toggle_mode = true
	_toggle.button_pressed = MatchState.auto_idle
	_toggle.toggled.connect(func(on: bool):
		MatchState.auto_idle = on
		Fx.ui_click())
	add_child(_toggle)


func _process(_delta: float) -> void:
	# hotkeys change the stance outside the bar — keep visuals honest
	var active := _buttons[MatchState.order_stance]
	for i in _buttons.size():
		var selected: bool = _buttons[i] == active
		_buttons[i].modulate = Color.WHITE if selected else Color(0.55, 0.55, 0.55)
	if _toggle.button_pressed != MatchState.auto_idle:
		_toggle.set_pressed_no_signal(MatchState.auto_idle)


func _make_button(icon: String, tooltip: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(BUTTON, BUTTON)
	btn.tooltip_text = tooltip
	btn.focus_mode = Control.FOCUS_NONE
	var path := "%s/%s.png" % [CURSOR_DIR, icon]
	if ResourceLoader.exists(path):
		btn.icon = load(path)
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return btn
