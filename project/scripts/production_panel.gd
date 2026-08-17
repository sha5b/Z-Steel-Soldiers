extends PanelContainer
## Production panel: shown when the player selects one of their factories.
## Robot factories offer the 6 robots; vehicle factories offer vehicles.
## Buttons use the original sprites as icons; payment is upfront.

signal queue_requested(type_name: String)

const ROBOT_ORDER := ["grunt", "psycho", "sniper", "tough", "pyro", "laser"]
const VEHICLE_ORDER := ["jeep", "light", "medium", "heavy", "apc"]

var _wired: Node = null
var _box: HBoxContainer
var _queue_row: HBoxContainer
var _progress: ProgressBar
var _built_for := ""
var _queue_cache: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	position.y -= size.y
	var col := VBoxContainer.new()
	add_child(col)
	_box = HBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	col.add_child(_box)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(200, 12)
	_progress.show_percentage = false
	_progress.visible = false
	col.add_child(_progress)
	_queue_row = HBoxContainer.new()
	_queue_row.add_theme_constant_override("separation", 2)
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
		if _built_for != factory.kind_key():
			_build_buttons(factory)
		_update_queue(factory)


func _update_queue(factory: Node) -> void:
	var q: Array = factory.queue
	if q != _queue_cache:
		_queue_cache = q.duplicate()
		for c in _queue_row.get_children():
			c.queue_free()
		for idx in q.size():
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(26, 26)
			btn.tooltip_text = "Right-click to cancel"
			var icon_path := _icon_path(String(q[idx]))
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
		if node is RobotFactory and node.owner_team == GameState.player_team:
			return node
		if node is VehicleFactory and node.owner_team == GameState.player_team:
			return node
		if node is FortBuilding and node.team == GameState.player_team:
			return node
	return null


func _build_buttons(factory: Node) -> void:
	_built_for = factory.kind_key()
	for c in _box.get_children():
		c.queue_free()
	var kinds: Array = ROBOT_ORDER if factory is RobotFactory else VEHICLE_ORDER
	var stats_table: Dictionary = UnitData.ROBOTS if factory is RobotFactory else UnitData.VEHICLES
	for type_name in kinds:
		var stats: Dictionary = stats_table[type_name]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(88, 64)
		btn.tooltip_text = "%s\nHP %d  DMG %d\n$%d" % [
			type_name.capitalize(), stats.hp, stats.damage, stats.cost]
		btn.text = "%s  $%d" % [type_name.capitalize(), stats.cost]
		var icon_path := _icon_path(String(type_name))
		if ResourceLoader.exists(icon_path):
			btn.icon = load(icon_path)
			btn.expand_icon = true
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		btn.pressed.connect(func(): queue_requested.emit(String(type_name)))
		_box.add_child(btn)


static func _icon_path(type_name: String) -> String:
	match type_name:
		"grunt", "psycho", "sniper", "tough", "pyro", "laser":
			return "res://assets/z/robots_%s/fire_red_r180_n00.png" % type_name
		"apc":
			return "res://assets/z/vehicles_apc/empty_r180.png"
		_:
			return "res://assets/z/vehicles_%s/empty_r180.png" % type_name
