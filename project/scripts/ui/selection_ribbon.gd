class_name SelectionRibbon
extends Control
## The original selection strip shown in tutorial pages 5 and 6: one
## compact object medallion per selected unit/building, just above the
## bottom HUD. Clicking a medallion narrows the selection to that object
## and centres the camera on it.

## Tutorial page 5 measures these at roughly 44px across in the original
## 640x480 view. A 32px slot made both hardware and buildings read as dots.
const SLOT := Vector2(44.0, 44.0)
const GAP := 4.0

var _row: HBoxContainer
var _selection: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row = HBoxContainer.new()
	_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_row.add_theme_constant_override("separation", int(GAP))
	_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_row)
	SelectionManager.current.selection_changed.connect(_rebuild)
	resized.connect(func(): _rebuild(_selection))
	_rebuild(SelectionManager.current.selected)


func _rebuild(selected: Array) -> void:
	_selection = selected.duplicate()
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	var valid: Array[Node] = []
	for entity in selected:
		if is_instance_valid(entity) and bool(entity.get("alive")):
			valid.append(entity)
	visible = not valid.is_empty()
	if not visible:
		return
	var capacity := maxi(int((size.x + GAP) / (SLOT.x + GAP)), 1)
	var shown := mini(valid.size(), capacity)
	if valid.size() > capacity:
		shown = maxi(capacity - 1, 0)
	for i in shown:
		_row.add_child(_button_for(valid[i]))
	if shown < valid.size():
		var more := Label.new()
		more.custom_minimum_size = SLOT
		more.text = "+%d" % (valid.size() - shown)
		more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		more.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		more.mouse_filter = Control.MOUSE_FILTER_IGNORE
		HudFrame._apply_hud_font(more, 12)
		_row.add_child(more)


func _button_for(entity: Node) -> Button:
	var button := Button.new()
	button.custom_minimum_size = SLOT
	button.focus_mode = Control.FOCUS_NONE
	button.expand_icon = true
	button.icon = _icon(entity)
	button.tooltip_text = _name(entity)
	var team := int(entity.get("team"))
	if entity is Building2D:
		team = int(entity.owner_team)
	var colour := Teams.minimap_color(team if team > 0 else 1)
	button.add_theme_stylebox_override("normal", _medallion(colour, false))
	button.add_theme_stylebox_override("hover", _medallion(colour, true))
	button.add_theme_stylebox_override("pressed", _medallion(colour, true))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(_choose.bind(entity))
	return button


func _medallion(colour: Color, bright: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.08, 0.94)
	style.border_color = colour.lightened(0.25) if bright else colour.darkened(0.15)
	style.set_border_width_all(2)
	style.set_corner_radius_all(22)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _icon(entity: Node) -> Texture2D:
	if entity is Unit2D:
		return ProductionPanel.icon_for(entity.kind, entity.unit_name, entity.team)
	if entity is Building2D:
		var def := ContentDB.building_def(entity.building_id)
		if def != null:
			var path := ContentDB.building_art_path(def.tex, entity.planet, false)
			if ResourceLoader.exists(path):
				return UiTheme.trimmed(path)
	return null


func _name(entity: Node) -> String:
	if entity is Unit2D:
		return entity.unit_name.capitalize()
	if entity is Building2D:
		var def := ContentDB.building_def(entity.building_id)
		return def.bname.replace("_", " ").capitalize() if def != null else "Building"
	return "Selected object"


func _choose(entity: Node) -> void:
	if not is_instance_valid(entity) or not bool(entity.get("alive")):
		return
	SelectionManager.current.select_single(entity)
	if entity is Node2D:
		var camera := get_viewport().get_camera_2d()
		if camera is RtsCamera2D:
			camera.pan_to(entity.global_position)
	Fx.ui_click()
