class_name ProductionPanel
extends Control
## The factory window, rebuilt on the original's own 112x80 `base_image`
## chrome instead of the 384x256 menu panel we had been borrowing.
##
## Slots measured out of that art (see the screenshots: "Robot Factory
## 100%", the object window with its name bar, then Building / Time 2:10
## / Cancel / Ok stacked down the right):
##
##   title plate (4,2) 64x10     health gauge (74,6) 34x9
##   object window (7,18) 42x40  object name (6,59) 45x13
##   status (66,18) 42x12        time (66,32) 42x12
##   Cancel (68,46) 40x14        Ok (68,62) 40x15
##
## THE TIME READOUT IS THE POINT. Z has no resource to spend — time is
## the currency, so "2:10 until this rolls out" is the single number the
## player is actually budgeting, and our old panel showed a bare progress
## bar with no figure on it at all.
##
##
## Choosing WHAT to build is the roster flyout: click the object window
## and the level-gated build list opens above it, on the original's
## `object_button` plates. The original scrolls a list in the same slot;
## a flyout shows a level-5 fort's whole roster at once instead of
## paging it.

signal queue_requested(type_name: String)

const PROD_DIR := "res://assets/z/ui/production"
## NATIVE scale, like the rest of the HUD. At 2x this window covered a
## quarter of the screen width where the original's covers a sixth, which
## is what "the build menu is too big" meant.
const SCALE := 1.0
## The readouts use the original's 8px menu font, not the 16px display
## font — a 16px line does not fit a 12px slot, which is why the value
## printed over the plate's own lettering and out of its box.
const READOUT_FONT := 8
const WINDOW := Vector2(112.0, 80.0)
const TITLE_PLATE := Rect2(4, 2, 64, 10)
const HEALTH_GAUGE := Rect2(74, 6, 34, 9)
const OBJECT_WINDOW := Rect2(7, 18, 42, 40)
const OBJECT_NAME := Rect2(6, 59, 45, 13)
## The narrow strip between the object window and the right column: the
## original draws two vertical gauges there (build level and progress),
## which we were leaving as bare plate.
const LEVEL_BAR := Rect2(52, 19, 5, 38)
const PROGRESS_BAR := Rect2(59, 19, 5, 38)
const STATUS_PLATE := Rect2(66, 17, 47, 12)
## The window art PRINTS the word "Time" itself, at x 71..86 — so the
## value belongs in the 21px to its right, not centred over the whole
## slot (which is how it came out as "ime1:08").
const TIME_SLOT := Rect2(87, 32, 21, 12)
const CANCEL_BUTTON := Rect2(68, 46, 40, 14)
const OK_BUTTON := Rect2(68, 62, 40, 15)
## Roster flyout: object_button plates, four to a row, above the window.
const ROSTER_SLOT := Vector2(45, 51)
const ROSTER_COLUMNS := 4
const ROSTER_GAP := 2.0

var _wired: Node = null
var _title: TextureRect
var _health: TextureRect
var _object: TextureRect
var _object_name: TextureRect
var _status: TextureRect
var _time: Label
var _health_pct: Label
var _level_fill: ColorRect
var _progress_fill: ColorRect
var _queue_count: Label
var _exit: Button
var _roster: Control
var _roster_open := false
var _built_for := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = WINDOW * SCALE
	size = WINDOW * SCALE
	var frame := TextureRect.new()
	frame.texture = _tex("base_image")
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(frame)

	_title = _plate(TITLE_PLATE)
	# the health gauge is the fort HP bar art, cropped to what is left
	_health = _plate(HEALTH_GAUGE)
	_health.stretch_mode = TextureRect.STRETCH_KEEP
	_health.clip_contents = true
	_object = _plate(OBJECT_WINDOW)
	_object_name = _plate(OBJECT_NAME)
	_status = _plate(STATUS_PLATE)
	# vertical gauges: filled from the BOTTOM, so they need their own
	# backing plus a fill rect that grows upward
	_level_fill = _bar(LEVEL_BAR, Color(0.95, 0.86, 0.25))
	_progress_fill = _bar(PROGRESS_BAR, Color(0.35, 0.9, 0.35))

	# RIGHT-aligned: the window art already draws the word "Time" at the
	# left of this slot, so a centred value printed straight over it
	_time = _label(TIME_SLOT, HORIZONTAL_ALIGNMENT_RIGHT)
	# the building's condition, printed on its gauge like the original's
	_health_pct = _label(Rect2(HEALTH_GAUGE.position.x, HEALTH_GAUGE.position.y - 1.0,
			HEALTH_GAUGE.size.x, HEALTH_GAUGE.size.y + 2.0),
			HORIZONTAL_ALIGNMENT_CENTER)
	_queue_count = _label(Rect2(OBJECT_NAME.position.x, 2,
			OBJECT_NAME.size.x, 10), HORIZONTAL_ALIGNMENT_LEFT)

	# the object window is the picker: clicking it opens the roster
	var pick := Button.new()
	pick.position = OBJECT_WINDOW.position * SCALE
	pick.size = OBJECT_WINDOW.size * SCALE
	# NO tooltip: a Godot tooltip on a native-scale window is wider than
	# the window and printed straight across its readouts
	pick.focus_mode = Control.FOCUS_NONE
	pick.flat = true
	for state in ["normal", "hover", "pressed", "focus"]:
		pick.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	pick.pressed.connect(_toggle_roster)
	add_child(pick)

	_art_button(CANCEL_BUTTON, "cancel_button",
			"Cancel the unit on the line").pressed.connect(_on_cancel)
	_art_button(OK_BUTTON, "ok_button",
			"Close").pressed.connect(func():
		Fx.ui_click()
		SelectionManager.current.clear_selection())

	# GARRISON EXIT. Robots ordered onto their own fort walk inside and
	# vanish; the only way back out was the X hotkey, and nothing on
	# screen said either that they were in there or how to get them out.
	# The original has no garrison at all, so this button cannot live in
	# its window art — it sits just under it.
	_exit = Button.new()
	_exit.position = Vector2(0.0, WINDOW.y * SCALE + 2.0)
	_exit.size = Vector2(56.0, 14.0)
	_exit.focus_mode = Control.FOCUS_NONE
	_exit.visible = false
	_object_button_chrome(_exit, 2.0)
	if UiTheme.font() != null:
		_exit.add_theme_font_override("font", UiTheme.font())
		_exit.add_theme_font_size_override("font_size", READOUT_FONT)
	_exit.pressed.connect(func():
		Fx.ui_click()
		Commands.eject())
	add_child(_exit)

	_roster = Control.new()
	_roster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roster.visible = false
	add_child(_roster)

	SelectionManager.current.selection_changed.connect(_on_selection_changed)
	MatchState.current.zone_captured.connect(func(_t): _check_roster())
	MatchState.current.tech_level_changed.connect(_check_roster)
	hide()


# ---- pieces -----------------------------------------------------------

func _plate(at: Rect2) -> TextureRect:
	var r := TextureRect.new()
	r.position = at.position * SCALE
	r.size = at.size * SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# IGNORE_SIZE or the rect cannot be smaller than its texture: a
	# TextureRect's minimum size is the art's size, so at native scale
	# every plate silently grew to its own art and spilled out of the
	# window (a 100x18 name plate in a 45x13 slot).
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _label(at: Rect2, align: int, font_size := READOUT_FONT) -> Label:
	var l := Label.new()
	l.position = at.position * SCALE
	l.size = at.size * SCALE
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font_size <= 10 and UiTheme.font() != null:
		l.add_theme_font_override("font", UiTheme.font())
		l.add_theme_font_size_override("font_size", font_size)
		l.add_theme_color_override("font_color", Color.WHITE)
	else:
		HudFrame._apply_hud_font(l, font_size)
	add_child(l)
	return l


## A bottom-filling vertical gauge on a dark backing.
func _bar(at: Rect2, fill: Color) -> ColorRect:
	var back := ColorRect.new()
	back.position = at.position * SCALE
	back.size = at.size * SCALE
	back.color = Color(0.06, 0.05, 0.04)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	var bar := ColorRect.new()
	bar.color = fill
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(bar)
	return bar


## A button whose whole face is the original's plate art.
func _art_button(at: Rect2, art: String, tooltip: String) -> Button:
	var btn := Button.new()
	btn.position = at.position * SCALE
	btn.size = at.size * SCALE
	btn.tooltip_text = tooltip
	btn.focus_mode = Control.FOCUS_NONE
	btn.flat = true
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var face := TextureRect.new()
	face.texture = _tex(art)
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.add_child(face)
	var pressed := _tex("%s_pressed" % art)
	if pressed != null:
		btn.button_down.connect(func(): face.texture = pressed)
		btn.button_up.connect(func(): face.texture = _tex(art))
	add_child(btn)
	return btn


# ---- wiring -----------------------------------------------------------

func _on_selection_changed(_units: Array) -> void:
	var factory := _selected_factory()
	visible = factory != null
	if factory != _wired:
		if _wired and is_instance_valid(_wired) \
				and _wired.queue.changed.is_connected(_on_queue_changed):
			_wired.queue.changed.disconnect(_on_queue_changed)
		_wired = factory
		_roster_open = false
		if factory:
			factory.queue.changed.connect(_on_queue_changed)
			_check_roster()
	if factory:
		_place_over(factory)
		_sync_readouts()


## The window opens ON the factory, like the original's, and is nudged
## back inside the world view so the sidebar never clips it.
func _place_over(factory: Node) -> void:
	if not (factory is Node2D):
		return
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	var screen: Vector2 = canvas * (factory as Node2D).global_position
	var view := HudFrame.view_rect()
	var want := screen + Vector2(-size.x * 0.5, -size.y - 24.0)
	position = Vector2(
		clampf(want.x, view.position.x + 4.0, view.end.x - size.x - 4.0),
		clampf(want.y, view.position.y + 4.0, view.end.y - size.y - 4.0))


func _on_queue_changed() -> void:
	_check_roster()
	_sync_readouts()


func _check_roster() -> void:
	if _wired and _built_for != "%s:%d" % [_wired.kind_key(), _wired.level]:
		_build_roster(_wired)


func _process(_delta: float) -> void:
	if _wired == null or not visible:
		return
	_place_over(_wired)
	_sync_readouts()
	# ONE writer for the flyout. It used to be set from three places
	# (_ready, the rebuild, the toggle) and a rebuild that landed after a
	# selection change left it on screen with nobody having opened it.
	_roster.visible = _roster_open and _roster.get_child_count() > 0
	if _roster.visible:
		_keep_roster_on_screen()


## The flyout sits above the window, which puts it off the top of the
## screen for a factory in the upper part of the map — flip it below in
## that case, and clamp sideways so a wide roster never runs under the
## sidebar.
func _keep_roster_on_screen() -> void:
	var view := HudFrame.view_rect()
	var above: float = -_roster.size.y - 2.0
	var below: float = size.y + 2.0
	var y: float = above if position.y + above >= view.position.y else below
	var max_x: float = view.end.x - _roster.size.x - 2.0 - position.x
	_roster.position = Vector2(minf(0.0, max_x), y)


func _sync_readouts() -> void:
	if _wired == null or not is_instance_valid(_wired):
		return
	_title.texture = _load(FactoryLabels.path_for(_wired.kind_key()))
	_sync_health()
	var q: Array = _wired.queue_items()
	var head: String = String(q[0]) if not q.is_empty() else ""
	# the object window shows WHAT is on the line (or the next thing the
	# factory will take, when it is idle)
	if head != "":
		var parts: PackedStringArray = head.split(":")
		_object.texture = object_art(parts[0], parts[1],
				MatchState.current.player_team)
		# the red bar in the window art is the unit NAME plate ("Grunt"),
		# not the weapon plate — those are two different slots
		_object_name.texture = _load(SelectedObject.plate_path(parts[1],
				MatchState.current.player_team))
	else:
		_object.texture = null
		_object_name.texture = null
	_status.texture = _tex("building_label" if head != "" else "buildingless_label")
	_time.text = _time_left(head)
	_sync_gauges(head)
	_sync_exit()
	_queue_count.text = "" if q.size() < 2 else "+%d" % (q.size() - 1)


## The garrison has no signal of its own (robots walk in by themselves),
## so the window's own tick follows it.
func _sync_exit() -> void:
	var held := 0
	if _wired is FortBuilding:
		for member in (_wired as FortBuilding).garrison:
			if is_instance_valid(member) and member.alive:
				held += 1
	_exit.visible = held > 0
	if held > 0:
		_exit.text = "EXIT %d" % held
		_exit.tooltip_text = "Send the %d robot(s) inside back out (X)" % held


## Level out of 5 and the current item's progress, both bottom-filling.
func _sync_gauges(head: String) -> void:
	var level_frac := clampf(float(_wired.level) / 5.0, 0.0, 1.0)
	var prog: float = _wired.progress() if head != "" else 0.0
	for pair in [[_level_fill, level_frac], [_progress_fill, prog]]:
		var bar: ColorRect = pair[0]
		var frac: float = clampf(pair[1], 0.0, 1.0)
		var full: float = (bar.get_parent() as ColorRect).size.y
		bar.size = Vector2((bar.get_parent() as ColorRect).size.x,
				roundf(full * frac))
		bar.position = Vector2(0.0, full - bar.size.y)


## Seconds remaining on the unit being built, as m:ss — the original's
## "Time 2:10". Empty while nothing is on the line.
func _time_left(head: String) -> String:
	if head == "":
		return ""
	var total: float = _wired.produce_seconds(head)
	var left: int = int(ceilf(maxf(total * (1.0 - _wired.progress()), 0.0)))
	return "%d:%02d" % [left / 60, left % 60]


## Building condition, in the top-right gauge — the original prints the
## factory's health beside its name, and a factory being shelled while
## you queue units is exactly when you want to know.
func _sync_health() -> void:
	var art := "res://assets/z/ui/hud/unit_amount_bar_%s.png" % AnimLibrary.team_name(
			_wired.owner_team)
	_health.texture = _load(art)
	var frac := clampf(float(_wired.hp) / float(maxi(_wired.max_hp, 1)), 0.0, 1.0)
	_health.size.x = maxf(roundf(HEALTH_GAUGE.size.x * SCALE * frac), 1.0)
	_health_pct.text = "%d%%" % roundi(frac * 100.0)


func _on_cancel() -> void:
	Fx.ui_click()
	if _wired and is_instance_valid(_wired) and not _wired.queue_items().is_empty():
		_wired.cancel_at(0)
	else:
		Fx.cap_denied()


func _selected_factory() -> Node:
	for node in SelectionManager.current.selected:
		if not is_instance_valid(node) or not node.alive:
			continue
		if node is RobotFactory and node.owner_team == MatchState.current.player_team:
			return node
		if node is VehicleFactory and node.owner_team == MatchState.current.player_team:
			return node
		if node is FortBuilding and node.team == MatchState.current.player_team:
			return node
	return null


# ---- the roster flyout ------------------------------------------------

func _toggle_roster() -> void:
	Fx.ui_click()
	_roster_open = not _roster_open


func _build_roster(factory: Node) -> void:
	_built_for = "%s:%d" % [factory.kind_key(), factory.level]
	for c in _roster.get_children():
		c.queue_free()
	var items: Array = factory.build_options()
	var rows: int = maxi(int(ceilf(float(items.size()) / float(ROSTER_COLUMNS))), 1)
	_roster.size = Vector2(
		float(ROSTER_COLUMNS) * (ROSTER_SLOT.x + ROSTER_GAP),
		float(rows) * (ROSTER_SLOT.y + ROSTER_GAP))
	_roster.position = Vector2(0.0, -_roster.size.y - 2.0)
	for i in items.size():
		var item := String(items[i])
		var parts: PackedStringArray = item.split(":")
		var stats := ContentDB.def_for(parts[0], parts[1])
		var btn := Button.new()
		btn.position = Vector2(float(i % ROSTER_COLUMNS) * (ROSTER_SLOT.x + ROSTER_GAP),
				float(i / ROSTER_COLUMNS) * (ROSTER_SLOT.y + ROSTER_GAP))
		btn.size = ROSTER_SLOT
		btn.tooltip_text = "%s — %d s, HP %d, DMG %d\nshift-click fills the line" % [
			parts[1].capitalize(), int(stats.build_time), stats.hp, stats.damage]
		btn.focus_mode = Control.FOCUS_NONE
		_object_button_chrome(btn)
		btn.icon = icon_for(parts[0], parts[1], MatchState.current.player_team)
		btn.expand_icon = btn.icon != null
		btn.pressed.connect(func(): _queue(item))
		_roster.add_child(btn)


## One roster press. SHIFT FILLS THE LINE (up to ProductionQueue's cap)
## instead of asking for one unit and reopening the flyout five times —
## the queue existed from the start and there was no way to fill it in
## one action. Each unit is queued through the same intake, so pop caps,
## money and the network see five separate requests, and the first one
## that is refused stops the run.
func _queue(item: String) -> void:
	if _wired == null or not is_instance_valid(_wired):
		return
	var want: int = ProductionQueue.MAX_ITEMS if Input.is_key_pressed(KEY_SHIFT) else 1
	for i in want:
		if not _wired.queue_unit(item):
			break
		queue_requested.emit(item)
		Net.relay_queue(_wired, item)
	_roster_open = false


## zod `object_button` plate behind each roster entry.
static func _object_button_chrome(btn: Button, pad := 4.0) -> void:
	var path := "%s/object_button.png" % PROD_DIR
	if not ResourceLoader.exists(path):
		return
	var pressed := "%s/object_button_pressed.png" % PROD_DIR
	btn.add_theme_stylebox_override("normal", _stylebox(path, pad))
	btn.add_theme_stylebox_override("hover", _stylebox(path, pad))
	btn.add_theme_stylebox_override("pressed",
		_stylebox(pressed if ResourceLoader.exists(pressed) else path, pad))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


static func _stylebox(path: String, pad: float) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = load(path)
	for side in ["left", "right", "top", "bottom"]:
		box.set("texture_margin_%s" % side, 6)
		box.set("content_margin_%s" % side, pad)
	return box


static func _tex(name: String) -> Texture2D:
	return _load("%s/%s.png" % [PROD_DIR, name])


static func _load(path: String) -> Texture2D:
	return load(path) if path != "" and ResourceLoader.exists(path) else null


## What the object window shows: a ROBOT's own head — the same baked
## portrait the sidebar animates — because that is what the original puts
## in this slot. Hardware has no head, so it falls back to the icon.
static func object_art(kind: String, type_name: String, team := 1) -> Texture2D:
	if kind == "robot":
		var face := "res://assets/z/ui/portraits/%s_%s/base.png" % [
				type_name, AnimLibrary.team_name(team if team > 0 else 1)]
		if ResourceLoader.exists(face):
			return load(face)
	return icon_for(kind, type_name, team)


## THE unit icon for every producer surface. The original HUD icons ship
## on a fixed 96px canvas with the unit drawn small and off-centre, so a
## raw texture in an `expand_icon` Button scales to the CANVAS and comes
## out an unreadable smear — crop to the opaque region first (cached per
## path by UiTheme.trimmed).
static func icon_for(kind: String, type_name: String, team := 1) -> Texture2D:
	var path := _icon_path(kind, type_name, team)
	if path == "" or not ResourceLoader.exists(path):
		return null
	return UiTheme.trimmed(path)


static func _icon_path(kind: String, type_name: String, team := 1) -> String:
	var tn := AnimLibrary.team_name(team)
	var hud := "res://assets/z/ui/hud/icon_%s_%s.png" % [type_name, tn]
	if ResourceLoader.exists(hud):
		return hud
	if kind == "robot":
		return "res://assets/z/robots_%s/fire_%s_r180_n00.png" % [type_name, tn]
	return hardware_art(kind, type_name)


## First existing UNMANNED hull image for a vehicle/cannon type. The
## original names this art three different ways — `empty_<team>_r###`,
## `empty_<team>`, plain `empty` — and only 3 of the 11 hardware types
## ship any one of them, so every caller has to walk the list. Shared
## with Unit2D.portrait_path.
static func hardware_art(kind: String, type_name: String) -> String:
	var dir := ContentDB.def_for(kind, type_name).asset_dir
	for probe in ["%s/empty_r270.png" % dir, "%s/empty_r180.png" % dir,
			"%s/empty_null.png" % dir, "%s/empty.png" % dir]:
		if ResourceLoader.exists(probe):
			return probe
	for tn in ["red", "blue", "green", "yellow", "null"]:
		for probe in ["%s/empty_%s_r270.png" % [dir, tn],
				"%s/empty_%s_r180.png" % [dir, tn], "%s/empty_%s.png" % [dir, tn]]:
			if ResourceLoader.exists(probe):
				return probe
	return ""
