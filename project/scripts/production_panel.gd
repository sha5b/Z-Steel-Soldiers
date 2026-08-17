extends PanelContainer
## Production panel: shown when the player selects one of their robot
## factories. Buttons queue robots (paid upfront), factory builds in order.

signal queue_requested(type_name: String)

const ROBOT_ORDER := ["grunt", "psycho", "sniper", "tough", "pyro", "laser"]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	position.y -= size.y
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	for type_name in ROBOT_ORDER:
		var stats: Dictionary = UnitData.ROBOTS[type_name]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(84, 72)
		btn.tooltip_text = "%s\nHP %d  DMG %d\n$%d" % [
			type_name.capitalize(), stats.hp, stats.damage, stats.cost]
		var icon_path := "res://assets/z/robots/stand_red_r180.png"
		if ResourceLoader.exists(icon_path):
			var tex: Texture2D = load(icon_path)
			var icon := TextureRect.new()
			icon.texture = tex
			icon.custom_minimum_size = Vector2(16, 16)
			icon.scale = Vector2(2, 2)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			btn.add_child(icon)
		var label := Label.new()
		label.text = "%s\n$%d" % [type_name.capitalize(), stats.cost]
		label.position = Vector2(8, 32)
		btn.add_child(label)
		btn.pressed.connect(func(): queue_requested.emit(type_name))
		box.add_child(btn)
	hide()


var _wired: RobotFactory = null


func _process(_delta: float) -> void:
	var factory := _selected_factory()
	visible = factory != null
	if factory != _wired:
		if _wired and queue_requested.is_connected(_wired.queue_unit):
			queue_requested.disconnect(_wired.queue_unit)
		_wired = factory
		if factory:
			queue_requested.connect(factory.queue_unit)


func _selected_factory() -> RobotFactory:
	for node in SelectionManager.selected:
		if node is RobotFactory and node.owner_team == GameState.player_team:
			return node
	return null
