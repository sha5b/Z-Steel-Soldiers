class_name ProductionPanel
extends Control
## Production panel: shown when the player selects one of their factories.
## Robot factories (and the fort) offer every buildable robot from
## ContentDB; vehicle factories offer buildable vehicles — new unit types
## appear here automatically. Built from the original UI art: the GOG box
## panel, zod `object_button` chrome, factory labels and entry-bar
## progress. Payment is upfront.

signal queue_requested(type_name: String)

## Button footprints. The original HUD unit icons are landscape (roughly
## 2:1 after cropping), so both slots are WIDER than tall — a square slot
## letterboxes the icon down to a few pixels of height. The queue row
## holds ProductionQueue.MAX_ITEMS of these across the panel's 240px of
## inner width.
const QUEUE_SLOT := Vector2(46, 30)
const ROSTER_SLOT := Vector2(56, 60)
const TAB_SLOT := Vector2(24, 24)
## The 384x256 panel art minus these insets is the whole layout budget.
## Everything below has to FIT: title + tabs + two roster rows + the
## progress bar + the queue row. It used to come to 245 of 240 available,
## so the VBox overran its bottom margin and the queue row sat on the
## panel's bottom bevel, flush with the screen edge.
const PANEL_INSET_X := 72
const PANEL_INSET_Y := 8
const TITLE_HEIGHT := 16
const PROGRESS_SIZE := Vector2(180, 14)
const ROW_SEPARATION := 4


var _wired: Node = null
var _title: TextureRect
var _box: GridContainer
var _queue_row: HBoxContainer
var _progress: ProgressBar
var _built_for := ""
var _queue_cache: Array = []
var _page := "robot"  # active R/V/G roster page
var _tabs := {}       # kind token -> tab Button


func _ready() -> void:
	UiTheme.apply(self)
	# bottom-center, on the narrow 384x256 original panel
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	OriginalPanel.attach(self, true)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", PANEL_INSET_X)
	margin.add_theme_constant_override("margin_right", PANEL_INSET_X)
	margin.add_theme_constant_override("margin_top", PANEL_INSET_Y)
	margin.add_theme_constant_override("margin_bottom", PANEL_INSET_Y)
	add_child(margin)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", ROW_SEPARATION)
	margin.add_child(col)
	_title = TextureRect.new()
	_title.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_title.custom_minimum_size = Vector2(0, TITLE_HEIGHT)
	col.add_child(_title)
	# the ORIGINAL's R/V/G roster pages: a level-5 fort carries 18 items
	# — one unfiltered grid overflows the 384x256 panel. Tabs filter the
	# roster to robots / vehicles / guns (empty tabs hide, and the page
	# auto-falls back when the roster drops its kind)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(tabs)
	for spec in [["R", "robot", "Robots"], ["V", "vehicle", "Vehicles"],
			["G", "cannon", "Guns"]]:
		var tab := Button.new()
		tab.text = String(spec[0])
		tab.tooltip_text = String(spec[2])
		tab.toggle_mode = true
		tab.custom_minimum_size = TAB_SLOT
		# slim plate: the default theme chrome adds 6px of content margin
		# top AND bottom, which pushed a 24px tab out to 35 and blew the
		# panel's height budget
		_object_button_chrome(tab, 1.0)
		var kind_token: String = String(spec[1])
		tab.toggled.connect(func(on):
			tab.modulate = Color(1.0, 0.85, 0.45) if on else Color.WHITE
			if on:
				_page = kind_token
				for k in _tabs:
					_tabs[k].button_pressed = _tabs[k] == tab
				if _wired:
					_build_buttons(_wired))
		_tabs[String(spec[1])] = tab
		tabs.add_child(tab)
	_box = GridContainer.new()
	(_box as GridContainer).columns = 4
	_box.add_theme_constant_override("h_separation", ROW_SEPARATION)
	_box.add_theme_constant_override("v_separation", ROW_SEPARATION)
	col.add_child(_box)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = PROGRESS_SIZE
	_progress.show_percentage = false
	_progress.visible = false
	_progress.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_entry_bar_chrome(_progress)
	col.add_child(_progress)
	_queue_row = HBoxContainer.new()
	_queue_row.add_theme_constant_override("separation", ROW_SEPARATION)
	_queue_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_queue_row)
	SelectionManager.current.selection_changed.connect(_on_selection_changed)
	MatchState.current.zone_captured.connect(func(_t): _check_roster())
	MatchState.current.tech_level_changed.connect(_check_roster)
	hide()


## Factory wiring follows the selection; the queue row follows the
## producer's queue.changed signal — nothing polls.
func _on_selection_changed(_units: Array) -> void:
	var factory := _selected_factory()
	visible = factory != null
	if factory != _wired:
		if _wired:
			if queue_requested.is_connected(_on_queue_requested):
				queue_requested.disconnect(_on_queue_requested)
			# the queue row follows the producer — unwind the old wire or
			# captured factories keep invoking _check_roster forever
			if _wired.queue.changed.is_connected(_on_queue_changed):
				_wired.queue.changed.disconnect(_on_queue_changed)
		_wired = factory
		_queue_cache.clear()
		if factory:
			queue_requested.connect(_on_queue_requested)
			# ONE handler for enqueue/cancel/complete: the roster AND the
			# queue row must both refresh (the row used to miss pure
			# enqueues — the queue showed nothing until reselecting)
			factory.queue.changed.connect(_on_queue_changed)
			_check_roster()
	if factory:
		_update_queue(factory)


func _on_queue_changed() -> void:
	_check_roster()
	if _wired and is_instance_valid(_wired):
		_update_queue(_wired)


## Button row rebuild: on selection change and whenever the producer's
## queue or level may have moved the roster.
func _check_roster() -> void:
	if _wired and _built_for != "%s:%d:%s" % [
			_wired.kind_key(), _wired.level, _page]:
		_build_buttons(_wired)
		if _wired:
			_update_queue(_wired)


## Only the progress bar animates per frame.
func _process(_delta: float) -> void:
	if _wired == null or not visible:
		return
	var prog: float = _wired.progress()
	var q: Array = _wired.queue_items()
	_progress.visible = not q.is_empty() and prog > 0.0
	_progress.value = prog * 100.0


func _update_queue(factory: Node) -> void:
	var q: Array = factory.queue_items()
	if q != _queue_cache:
		_queue_cache = q.duplicate()
		for c in _queue_row.get_children():
			c.queue_free()
		for idx in q.size():
			var btn := Button.new()
			# WIDE slots (the icon art is ~2:1) with slim content margins:
			# the default theme plate eats 10px each side, which is what
			# starved the icon down to a sliver in the old 40x44 square
			btn.custom_minimum_size = QUEUE_SLOT
			btn.tooltip_text = "%s — right-click to cancel" % [
				String(q[idx]).split(":")[-1].capitalize()]
			_object_button_chrome(btn, 2.0)
			var parts: PackedStringArray = String(q[idx]).split(":")
			btn.icon = icon_for(parts[0], parts[1], MatchState.current.player_team)
			btn.expand_icon = btn.icon != null
			var i := idx
			btn.gui_input.connect(func(ev):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
					factory.cancel_at(i))
			_queue_row.add_child(btn)



## Build request: apply locally AND relay (no-op offline). One seam —
## the direct factory.queue_unit wire used to bypass the network.
func _on_queue_requested(item: String) -> void:
	if _wired != null and is_instance_valid(_wired):
		_wired.queue_unit(item)
		Net.relay_queue(_wired, item)


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


func _build_buttons(factory: Node) -> void:
	_built_for = "%s:%d:%s" % [factory.kind_key(), factory.level, _page]
	var label_path: String = FactoryLabels.LABELS.get(factory.kind_key(), "")
	_title.texture = load(label_path) if ResourceLoader.exists(label_path) else null
	# tab availability from the FULL roster (tabs hide when this level
	# carries none of that kind); switch pages when ours emptied out
	var full: Array = factory.build_options()
	for kind_token in _tabs:
		var tab: Button = _tabs[kind_token]
		tab.visible = full.any(func(i): return String(i).begins_with(kind_token + ":"))
		if tab.visible and _page == kind_token:
			tab.button_pressed = true
			tab.modulate = Color(1.0, 0.85, 0.45)
	if not _tabs.get(_page, null) or not _tabs[_page].visible:
		for kind_token in ["robot", "vehicle", "cannon"]:
			if _tabs[kind_token].visible:
				_page = kind_token
				_tabs[kind_token].button_pressed = true
				break
	for c in _box.get_children():
		c.queue_free()
	# the level-gated roster from the original build lists — mixed
	# kinds: "robot:grunt", "vehicle:jeep", "cannon:gatling"...
	for item in full:
		if not String(item).begins_with(_page + ":"):
			continue
		var parts: PackedStringArray = String(item).split(":")
		var kind := parts[0]
		var type_name := parts[1]
		var stats := ContentDB.def_for(kind, type_name)
		var btn := Button.new()
		btn.custom_minimum_size = ROSTER_SLOT
		btn.tooltip_text = "%s (%s) L%d\nHP %d  DMG %d\n$%d" % [
			type_name.capitalize(), kind, factory.level,
			stats.hp, stats.damage, stats.cost]
		btn.text = "%d" % stats.cost
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		_object_button_chrome(btn)
		btn.icon = icon_for(kind, type_name, MatchState.current.player_team)
		btn.expand_icon = btn.icon != null
		btn.pressed.connect(func(): queue_requested.emit(String(item)))
		_box.add_child(btn)


## zod `entry_bar` art (102x12 at 2x) as the progress bar chrome.
func _entry_bar_chrome(bar: ProgressBar) -> void:
	var grey := "res://assets/z/ui/production/entry_bar_grey.png"
	var green := "res://assets/z/ui/production/entry_bar_green.png"
	if not ResourceLoader.exists(grey):
		return
	var bg := StyleBoxTexture.new()
	bg.texture = load(grey)
	bg.texture_margin_left = 4
	bg.texture_margin_right = 4
	bar.add_theme_stylebox_override("background", bg)
	if ResourceLoader.exists(green):
		var fill := StyleBoxTexture.new()
		fill.texture = load(green)
		fill.texture_margin_left = 4
		fill.texture_margin_right = 4
		bar.add_theme_stylebox_override("fill", fill)


## zod `object_button` chrome (45x51 at 2x) behind each unit button.
## `pad` is the CONTENT inset: the frame art still draws at its 6px
## corners, but the icon gets nearly the whole plate. Without an explicit
## content margin a StyleBoxTexture inherits its texture margins, so the
## small queue slots lost 12 of their 48 pixels to invisible padding.
func _object_button_chrome(btn: Button, pad := 6.0) -> void:
	var path := "res://assets/z/ui/production/object_button.png"
	if not ResourceLoader.exists(path):
		return
	var ppath := "res://assets/z/ui/production/object_button_pressed.png"
	var normal := _plate(path, pad)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", _plate(path, pad))
	btn.add_theme_stylebox_override("pressed",
		_plate(ppath if ResourceLoader.exists(ppath) else path, pad))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


static func _plate(path: String, pad: float) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = load(path)
	for side in ["left", "right", "top", "bottom"]:
		box.set("texture_margin_%s" % side, 6)
		box.set("content_margin_%s" % side, pad)
	return box


## THE unit icon for every producer surface (roster grid, queue row,
## facility quick bar). The original HUD icons ship on a fixed 96px-wide
## canvas with the unit drawn small and off-centre inside it, so the raw
## texture in an `expand_icon` Button scaled to the CANVAS: a grunt came
## out ~20x7px, an unreadable smear — the "queue shows no icons" bug.
## Cropping to the opaque region first (UiTheme.trimmed, the same fix
## the menu art needed) recovers 2-3x the linear size. Cached per path.
static func icon_for(kind: String, type_name: String, team := 1) -> Texture2D:
	var path := _icon_path(kind, type_name, team)
	if path == "" or not ResourceLoader.exists(path):
		return null
	return UiTheme.trimmed(path)


static func _icon_path(kind: String, type_name: String, team := 1) -> String:
	# original HUD icons exist for every type and team
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
## ship any one of them, so every caller has to walk the list. Shared by
## the production icons and Unit2D.portrait_path (which probed a single
## `empty_r270` and came up blank for 8 types).
static func hardware_art(kind: String, type_name: String) -> String:
	var dir := ContentDB.def_for(kind, type_name).asset_dir
	for probe in ["%s/empty_r270.png" % dir, "%s/empty_r180.png" % dir,
			"%s/empty_null.png" % dir, "%s/empty.png" % dir]:
		if ResourceLoader.exists(probe):
			return probe
	# team-painted hulls: any facing beats a blank slot
	for tn in ["red", "blue", "green", "yellow", "null"]:
		for probe in ["%s/empty_%s_r270.png" % [dir, tn],
				"%s/empty_%s_r180.png" % [dir, tn], "%s/empty_%s.png" % [dir, tn]]:
			if ResourceLoader.exists(probe):
				return probe
	return ""
