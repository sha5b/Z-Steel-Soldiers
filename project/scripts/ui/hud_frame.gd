class_name HudFrame
extends Control
## The original's in-game HUD: a FIXED chrome, not floating panels.
##
## A 100px sidebar down the right edge and a 36px bar along the bottom,
## with the world drawn in what is left (548x448 at the original's
## 648x484). Every offset below was measured out of the frame art itself
## — the plates the art draws empty are the slots the engine fills, and
## the lettered buttons it draws in place gave their own positions away
## by matching the loose button plates against it (exact, 0.00 error):
##
##   sidebar   A (8,8)   portrait (8,44) 86x74   name plate (9,125) 84x16
##             equipment (6,144) 88x63          health (14,210) 74x14
##             weapon plate (0,226) 100x18      T/D/Z (8|38|68, 264)
##             radar (6,298) 94x98
##   bottom    R/V/B/G (8|38|68|98, 10)   count window (130,8) 66x24
##             bar track = the centre piece   Menu (right+64, 10)
##
## The frame art is one fixed size, so a window WIDER or TALLER than the
## original gets the pack's own `side_filler`/`bottom_filler` tiles in
## the gap rather than a stretched panel.
##
## `view_rect()` is the screen area the chrome leaves for the world. The
## camera clamps its pan to it and the match ignores clicks outside it,
## so nothing is ever selected or ordered underneath the sidebar.

const HUD_DIR := "res://assets/z/ui/hud"
const SIDE_W := 100.0
const BAR_H := 36.0
const DESIGN := Vector2(648.0, 484.0)

# --- sidebar slots (local to the sidebar's top-left) --------------------
const A_BUTTON := Rect2(8, 8, 24, 20)
const CLOCK := Rect2(34, 8, 62, 20)
const PORTRAIT := Rect2(8, 44, 86, 74)
const NAME_PLATE := Rect2(2, 124, 96, 18)
const EQUIPMENT := Rect2(6, 144, 88, 63)
const GRENADE := Rect2(10, 180, 28, 24)
const GRENADE_COUNT := Rect2(42, 182, 48, 20)
const HEALTH := Rect2(14, 210, 74, 14)
const WEAPON_PLATE := Rect2(2, 226, 96, 18)
const MODE_BUTTONS := [Vector2(8, 264), Vector2(38, 264), Vector2(68, 264)]
const BUTTON_SIZE := Vector2(24, 20)
const RADAR := Rect2(6, 298, 94, 98)

# --- bottom bar slots (local to the bar's top-left) ---------------------
const BAR_LEFT_W := 206.0
const BAR_CENTRE_W := 212.0
const BAR_RIGHT_W := 130.0
const BAR_BUTTONS := [Vector2(8, 10), Vector2(38, 10), Vector2(68, 10),
	Vector2(98, 10)]
const MENU_BUTTON := Vector2(64, 10)
const MENU_SIZE := Vector2(56, 20)
## The black window in the left piece is the first team's count; the
## grey track across the centre piece is where the amount bars draw.
const COUNT_WINDOW := Rect2(130, 8, 66, 24)
const TRACK_TOP := 8.0
const TRACK_H := 24.0

## The live frame, for the camera and the match input (both need the
## world's screen rect and neither should hunt the scene tree for it).
static var current: HudFrame

var _side: Control
var _bottom: Control
var _clock: Label


func _ready() -> void:
	current = self
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_side = _make_panel()
	_bottom = _make_panel()
	add_child(_side)
	add_child(_bottom)
	_build_side()
	_build_bottom()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _exit_tree() -> void:
	if current == self:
		current = null


## The world's screen rect: everything the chrome does not cover.
static func view_rect() -> Rect2:
	var vp: Vector2 = Vector2(Engine.get_main_loop().root.get_visible_rect().size)
	if current == null:
		return Rect2(Vector2.ZERO, vp)
	return Rect2(0.0, 0.0, maxf(vp.x - SIDE_W, 1.0), maxf(vp.y - BAR_H, 1.0))


func _make_panel() -> Control:
	var panel := Control.new()
	# the chrome EATS clicks: a drag that ends on the sidebar used to
	# select the world behind it
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.clip_contents = true
	return panel


func _layout() -> void:
	var vp := Vector2(get_viewport().get_visible_rect().size)
	_side.position = Vector2(vp.x - SIDE_W, 0.0)
	_side.size = Vector2(SIDE_W, vp.y)
	_bottom.position = Vector2(0.0, vp.y - BAR_H)
	_bottom.size = Vector2(vp.x - SIDE_W, BAR_H)
	_tile_side(vp.y)
	_tile_bottom(vp.x - SIDE_W)


# ---- chrome -----------------------------------------------------------

## Sidebar art anchored to the TOP (the clock, portrait and weapon panel
## have to stay where the player expects them); any height beyond the
## art's 484 gets filler tiles below it.
func _tile_side(height: float) -> void:
	var art := _side.get_node_or_null("Art") as TextureRect
	if art == null:
		return
	var team_art := _team_side_path()
	art.texture = _tex(team_art)
	var art_h: float = art.texture.get_height() if art.texture else DESIGN.y
	art.position = Vector2.ZERO
	art.size = Vector2(SIDE_W, art_h)
	var filler := _tex("%s/side_filler.png" % HUD_DIR)
	_fill(_side, "SideFill", filler, Rect2(0.0, art_h, SIDE_W,
			maxf(height - art_h, 0.0)), true)


## Bottom bar: left cap, centre track, right cap (Menu), with filler
## tiles taking up the slack so the centre stays centred.
func _tile_bottom(width: float) -> void:
	var slack: float = maxf(width - BAR_LEFT_W - BAR_CENTRE_W - BAR_RIGHT_W, 0.0)
	var left_pad := floorf(slack * 0.5)
	var pieces := {
		"BarLeft": [Vector2(0.0, 0.0), BAR_LEFT_W, "main_hud_bottom_left"],
		"BarCentre": [Vector2(BAR_LEFT_W + left_pad, 0.0), BAR_CENTRE_W,
			"main_hud_bottom_center"],
		"BarRight": [Vector2(width - BAR_RIGHT_W, 0.0), BAR_RIGHT_W,
			"main_hud_bottom_right"],
	}
	for name in pieces:
		var piece: TextureRect = _bottom.get_node_or_null(name)
		if piece == null:
			continue
		piece.texture = _tex("%s/%s.png" % [HUD_DIR, String(pieces[name][2])])
		piece.position = pieces[name][0]
		piece.size = Vector2(float(pieces[name][1]), BAR_H)
	var filler := _tex("%s/bottom_filler.png" % HUD_DIR)
	_fill(_bottom, "BarFillLeft", filler,
			Rect2(BAR_LEFT_W, 0.0, left_pad, BAR_H), false)
	var centre_end := BAR_LEFT_W + left_pad + BAR_CENTRE_W
	_fill(_bottom, "BarFillRight", filler,
			Rect2(centre_end, 0.0, maxf(width - BAR_RIGHT_W - centre_end, 0.0),
			BAR_H), false)
	var menu: Control = _bottom.get_node_or_null("Menu")
	if menu:
		menu.position = Vector2(width - BAR_RIGHT_W, 0.0) + MENU_BUTTON
	_sync_army_bars()


## A tiled region of `filler`, as one TextureRect in TILE stretch mode.
func _fill(parent: Control, name: String, filler: Texture2D, at: Rect2,
		vertical: bool) -> void:
	var rect: TextureRect = parent.get_node_or_null(name)
	if rect == null:
		rect = TextureRect.new()
		rect.name = name
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.stretch_mode = TextureRect.STRETCH_TILE
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(rect)
		# under the widgets, over nothing
		parent.move_child(rect, 0)
	rect.texture = filler
	rect.position = at.position
	rect.size = at.size
	rect.visible = filler != null and at.size.x > 0.0 and at.size.y > 0.0
	if vertical:
		rect.size.x = SIDE_W


func _team_side_path() -> String:
	var team: int = MatchState.current.player_team if MatchState.current else 1
	var path := "%s/main_hud_side_%s.png" % [HUD_DIR, AnimLibrary.team_name(team)]
	return path if ResourceLoader.exists(path) else "%s/main_hud_side.png" % HUD_DIR


# ---- sidebar widgets --------------------------------------------------

func _build_side() -> void:
	var art := TextureRect.new()
	art.name = "Art"
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side.add_child(art)

	# A: the alert lamp beside the clock. The original's meaning for this
	# button is not recorded anywhere we can check, so ours jumps the
	# camera to whatever the commander last shouted about.
	var alert := HudButton.make("a", A_BUTTON.position, BUTTON_SIZE,
			"Jump to the last alert")
	alert.pressed.connect(_jump_to_alert)
	_side.add_child(alert)

	_clock = Label.new()
	_clock.name = "Clock"
	_clock.position = CLOCK.position
	_clock.size = CLOCK.size
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_hud_font(_clock, 16)
	_side.add_child(_clock)

	var portrait := HudPortrait.new()
	portrait.name = "Portrait"
	portrait.position = PORTRAIT.position
	portrait.size = PORTRAIT.size
	_side.add_child(portrait)

	var unit_panel := UnitPanel.new()
	unit_panel.name = "UnitPanel"
	unit_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	unit_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side.add_child(unit_panel)

	# T/D/Z. The frame draws these three INACTIVE, which is what a mode
	# toggle looks like before you press it — so that is what ours are:
	# T smart idle, D defend-and-hold, Z attack-move. Neither D nor Z
	# held down is the plain move stance.
	var modes := [
		["t", "Smart idle (T): idle robots man hardware\nand walk onto capturable flags"],
		["d", "Defend (D): ordered units hold the post"],
		["z", "Attack move (Z): engage on the way"],
	]
	for i in modes.size():
		var spec: Array = modes[i]
		var btn := HudButton.make(String(spec[0]), MODE_BUTTONS[i], BUTTON_SIZE,
				String(spec[1]))
		btn.toggle_mode = true
		btn.name = "Mode%s" % String(spec[0]).to_upper()
		_side.add_child(btn)
	(_side.get_node("ModeT") as Button).toggled.connect(func(on: bool):
		GameSettings.set_auto_idle(on)
		Fx.ui_click())
	(_side.get_node("ModeD") as Button).toggled.connect(func(on: bool):
		SelectionManager.current.set_stance(SelectionManager.OrderStance.DEFEND \
				if on else SelectionManager.OrderStance.MOVE)
		Fx.ui_click())
	(_side.get_node("ModeZ") as Button).toggled.connect(func(on: bool):
		SelectionManager.current.set_stance(SelectionManager.OrderStance.ATTACK_MOVE \
				if on else SelectionManager.OrderStance.MOVE)
		Fx.ui_click())
	SelectionManager.current.stance_changed.connect(_sync_modes)
	GameSettings.auto_idle_changed.connect(func(_on: bool): _sync_modes())
	_sync_modes()


## The mode buttons mirror the state, whether it moved from the button or
## from the keyboard.
func _sync_modes() -> void:
	var stance: int = SelectionManager.current.order_stance
	var t := _side.get_node_or_null("ModeT") as Button
	var d := _side.get_node_or_null("ModeD") as Button
	var z := _side.get_node_or_null("ModeZ") as Button
	if t:
		t.set_pressed_no_signal(GameSettings.auto_idle)
		HudButton.set_state(t, GameSettings.auto_idle)
	if d:
		var on := stance == SelectionManager.OrderStance.DEFEND
		d.set_pressed_no_signal(on)
		HudButton.set_state(d, on)
	if z:
		var on := stance == SelectionManager.OrderStance.ATTACK_MOVE
		z.set_pressed_no_signal(on)
		HudButton.set_state(z, on)


func _jump_to_alert() -> void:
	Fx.ui_click()
	var at: Vector2 = Fx.last_alert_at
	if at == Vector2.INF:
		Fx.cap_denied()
		return
	var cam: Camera2D = Engine.get_main_loop().root.get_viewport().get_camera_2d()
	if cam is RtsCamera2D:
		(cam as RtsCamera2D).pan_to(at)


# ---- bottom bar widgets ----------------------------------------------

func _build_bottom() -> void:
	for name in ["BarLeft", "BarCentre", "BarRight"]:
		var piece := TextureRect.new()
		piece.name = name
		piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bottom.add_child(piece)

	# R/V/B/G. The frame draws these ACTIVE — one-shot actions, not modes.
	var actions := [
		["r", "Select every robot (R)", "robot"],
		["v", "Select every vehicle (V)", "vehicle"],
		["b", "Cycle your production buildings (B)", "building"],
		["g", "Cycle your control groups (G)", "group"],
	]
	for i in actions.size():
		var spec: Array = actions[i]
		var btn := HudButton.make(String(spec[0]), BAR_BUTTONS[i], BUTTON_SIZE,
				String(spec[1]), true)
		var what := String(spec[2])
		btn.pressed.connect(func(): SelectionFilters.activate(what))
		_bottom.add_child(btn)

	var bars := ArmyBars.new()
	bars.name = "ArmyBars"
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_child(bars)

	var menu := HudButton.make("menu", MENU_BUTTON, MENU_SIZE,
			"Menu (Esc)", true)
	menu.name = "Menu"
	menu.pressed.connect(func():
		Fx.ui_click()
		var pause: Node = Engine.get_main_loop().root.get_node_or_null(
				"Main/CanvasLayer/PauseMenu")
		if pause and not GameState.over:
			pause.toggle())
	_bottom.add_child(menu)


func _sync_army_bars() -> void:
	var bars := _bottom.get_node_or_null("ArmyBars") as ArmyBars
	if bars:
		bars.lay_out(Rect2(COUNT_WINDOW.position,
				Vector2(_bottom.size.x - COUNT_WINDOW.position.x - BAR_RIGHT_W,
				TRACK_H)))


func _process(_delta: float) -> void:
	if _clock == null or MatchState.current == null:
		return
	# the SIM clock, in the original's h:mm:ss — the same value that
	# drives the tech ladder, never a UI-side accumulator
	var t: int = int(MatchState.current.match_time)
	_clock.text = "%d:%02d:%02d" % [t / 3600, (t / 60) % 60, t % 60]


static func _tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


static func _apply_hud_font(label: Label, size: int) -> void:
	var font := UiTheme.hud_font()
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color.WHITE)
