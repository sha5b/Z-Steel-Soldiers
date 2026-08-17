extends PanelContainer
## Production panel: shown when the player selects one of their factories.
## Robot factories offer the 6 robots; vehicle factories offer vehicles.
## Buttons use the original sprites as icons; payment is upfront.

signal queue_requested(type_name: String)

const ROBOT_ORDER := ["grunt", "psycho", "sniper", "tough", "pyro", "laser"]
const VEHICLE_ORDER := ["jeep", "light", "medium", "heavy", "apc"]

var _wired: Node = null
var _box: HBoxContainer
var _built_for := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	position.y -= size.y
	_box = HBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	add_child(_box)
	hide()


func _process(_delta: float) -> void:
	var factory := _selected_factory()
	visible = factory != null
	if factory != _wired:
		if _wired and queue_requested.is_connected(_wired.queue_unit):
			queue_requested.disconnect(_wired.queue_unit)
		_wired = factory
		if factory:
			queue_requested.connect(factory.queue_unit)
	if factory and _built_for != factory.kind_key():
		_build_buttons(factory)


func _selected_factory() -> Node:
	for node in SelectionManager.selected:
		if node is RobotFactory and node.owner_team == GameState.player_team:
			return node
		if node is VehicleFactory and node.owner_team == GameState.player_team:
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
