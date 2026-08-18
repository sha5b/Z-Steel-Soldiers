extends Control
## Production panel: shown when the player selects one of their factories.
## Robot factories (and the fort) offer every buildable robot from
## ContentDB; vehicle factories offer buildable vehicles — new unit types
## appear here automatically. Built from the original UI art: the GOG box
## panel, zod `object_button` chrome, factory labels and entry-bar
## progress. Payment is upfront.

signal queue_requested(type_name: String)

const LABELS := {
	"fort": "res://assets/z/ui/production/fort_factory_label.png",
	"robot_factory": "res://assets/z/ui/production/fort_factory_label.png",
	"vehicle_factory": "res://assets/z/ui/production/building_label.png",
}

var _wired: Node = null
var _title: TextureRect
var _box: GridContainer
var _queue_row: HBoxContainer
var _progress: ProgressBar
var _built_for := ""
var _queue_cache: Array = []


func _ready() -> void:
	UiTheme.apply(self)
	# bottom-center, on the narrow 384x256 original panel
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	OriginalPanel.attach(self, true)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 72)
	margin.add_theme_constant_override("margin_right", 72)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(col)
	_title = TextureRect.new()
	_title.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_title.custom_minimum_size = Vector2(0, 20)
	col.add_child(_title)
	_box = GridContainer.new()
	(_box as GridContainer).columns = 4
	_box.add_theme_constant_override("h_separation", 4)
	_box.add_theme_constant_override("v_separation", 4)
	col.add_child(_box)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(180, 16)
	_progress.show_percentage = false
	_progress.visible = false
	_progress.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_entry_bar_chrome(_progress)
	col.add_child(_progress)
	_queue_row = HBoxContainer.new()
	_queue_row.add_theme_constant_override("separation", 4)
	_queue_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_queue_row)
	hide()


func _process(_delta: float) -> void:
	var factory := _selected_factory()
	visible = factory != null
	if factory != _wired:
		if _wired and queue_requested.is_connected(_wired.queue_unit):
			queue_requested.disconnect(_wired.queue_unit)
		_wired = factory
		_queue_cache.clear()
		if factory:
			queue_requested.connect(factory.queue_unit)
	if factory:
		# rebuild the button row when the producer (or its level) changes:
		# the roster unlocks as the building levels up
		if _built_for != "%s:%d" % [factory.kind_key(), factory.level]:
			_build_buttons(factory)
		_update_queue(factory)


func _update_queue(factory: Node) -> void:
	var q: Array = factory.queue_items()
	if q != _queue_cache:
		_queue_cache = q.duplicate()
		for c in _queue_row.get_children():
			c.queue_free()
		for idx in q.size():
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(40, 44)
			btn.tooltip_text = "Right-click to cancel"
			var parts: PackedStringArray = String(q[idx]).split(":")
			var icon_path := _icon_path(parts[0], parts[1])
			if ResourceLoader.exists(icon_path):
				btn.icon = load(icon_path)
				btn.expand_icon = true
			var i := idx
			btn.gui_input.connect(func(ev):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
					factory.cancel_at(i))
			_queue_row.add_child(btn)
	var prog: float = factory.progress()
	_progress.visible = not q.is_empty() and prog > 0.0
	_progress.value = prog * 100.0


func _selected_factory() -> Node:
	for node in SelectionManager.selected:
		if not is_instance_valid(node) or not node.alive:
			continue
		if node is RobotFactory and node.owner_team == GameState.player_team:
			return node
		if node is VehicleFactory and node.owner_team == GameState.player_team:
			return node
		if node is FortBuilding and node.team == GameState.player_team:
			return node
	return null


func _build_buttons(factory: Node) -> void:
	_built_for = "%s:%d" % [factory.kind_key(), factory.level]
	var label_path: String = LABELS.get(factory.kind_key(), "")
	_title.texture = load(label_path) if ResourceLoader.exists(label_path) else null
	for c in _box.get_children():
		c.queue_free()
	# the level-gated roster from the original build lists — mixed
	# kinds: "robot:grunt", "vehicle:jeep", "cannon:gatling"...
	for item in factory.build_options():
		var parts: PackedStringArray = String(item).split(":")
		var kind := parts[0]
		var type_name := parts[1]
		var stats: Dictionary = ContentDB.def_for(kind, type_name)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(56, 60)
		btn.tooltip_text = "%s (%s) L%d\nHP %d  DMG %d\n$%d" % [
			type_name.capitalize(), kind, factory.level,
			stats.hp, stats.damage, stats.cost]
		btn.text = "%d" % stats.cost
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		_object_button_chrome(btn)
		var icon_path := _icon_path(kind, type_name)
		if ResourceLoader.exists(icon_path):
			btn.icon = load(icon_path)
			btn.expand_icon = true
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
func _object_button_chrome(btn: Button) -> void:
	var path := "res://assets/z/ui/production/object_button.png"
	if not ResourceLoader.exists(path):
		return
	var box := StyleBoxTexture.new()
	box.texture = load(path)
	box.texture_margin_left = 6
	box.texture_margin_right = 6
	box.texture_margin_top = 6
	box.texture_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", box)
	var pressed := StyleBoxTexture.new()
	var ppath := "res://assets/z/ui/production/object_button_pressed.png"
	pressed.texture = load(ppath) if ResourceLoader.exists(ppath) else load(path)
	pressed.texture_margin_left = 6
	pressed.texture_margin_right = 6
	pressed.texture_margin_top = 6
	pressed.texture_margin_bottom = 6
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("hover", box.duplicate())
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


static func _icon_path(kind: String, type_name: String) -> String:
	# original HUD icons exist for every type and team
	var hud := "res://assets/z/ui/hud/icon_%s_red.png" % type_name
	if ResourceLoader.exists(hud):
		return hud
	if kind == "robot":
		return "res://assets/z/robots_%s/fire_red_r180_n00.png" % type_name
	# not every vehicle ships empty_r180 — walk the fallbacks
	var dir := String(ContentDB.def_for(kind, type_name).get("dir", ""))
	for probe in ["%s/empty_r180.png" % dir, "%s/empty_null.png" % dir, "%s/empty.png" % dir]:
		if ResourceLoader.exists(probe):
			return probe
	return ""
