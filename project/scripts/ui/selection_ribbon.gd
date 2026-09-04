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
const ICON_CANVAS := Vector2i(36, 36)
const ICON_CONTENT := 30.0

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
	button.expand_icon = false
	button.icon = _icon(entity)
	button.tooltip_text = _name(entity)
	button.add_theme_stylebox_override("normal", _medallion(false))
	button.add_theme_stylebox_override("hover", _medallion(true))
	button.add_theme_stylebox_override("pressed", _medallion(true))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(_choose.bind(entity))
	return button


func _medallion(bright: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.25, 0.16, 0.96)
	style.border_color = Color(0.78, 0.79, 0.73) if bright \
		else Color(0.31, 0.43, 0.33)
	style.set_border_width_all(3 if bright else 2)
	style.set_corner_radius_all(22)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _icon(entity: Node) -> Texture2D:
	if entity is Unit2D:
		return _world_unit_icon(entity)
	if entity is Building2D:
		var def := ContentDB.building_def(entity.building_id)
		if def != null:
			var path := ContentDB.building_art_path(def.tex, entity.planet, false)
			if ResourceLoader.exists(path):
				return UiTheme.trimmed(path)
	return null


## Selection medallions in the original show the actual top-down unit art,
## not the `icon_*` HUD sheets (those are side-view production/equipment
## pictures; `icon_grunt`, for example, is only a rifle). Flatten the live
## hull + wheels + turret layers into a small nearest-neighbour thumbnail.
static func _world_unit_icon(entity: Unit2D) -> Texture2D:
	var layers: Array[Dictionary] = []
	var bounds := Rect2()
	var first := true
	for child in entity.get_children():
		if not (child is AnimatedSprite2D) or not child.visible:
			continue
		var spr := child as AnimatedSprite2D
		if spr.sprite_frames == null or not spr.sprite_frames.has_animation(spr.animation):
			continue
		var tex := spr.sprite_frames.get_frame_texture(spr.animation, spr.frame)
		if tex == null:
			continue
		var size := tex.get_size() * spr.scale.abs()
		var pos := spr.position + spr.offset * spr.scale
		var rect := Rect2(pos - size * 0.5 if spr.centered else pos, size)
		layers.append({"sprite": spr, "texture": tex, "rect": rect})
		bounds = rect if first else bounds.merge(rect)
		first = false
	if layers.is_empty() or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return ProductionPanel.icon_for(entity.kind, entity.unit_name, entity.team)
	var scale := minf(2.0, ICON_CONTENT / maxf(bounds.size.x, bounds.size.y))
	var out := Image.create_empty(ICON_CANVAS.x, ICON_CANVAS.y, false,
		Image.FORMAT_RGBA8)
	var centre := Vector2(ICON_CANVAS) * 0.5
	for layer in layers:
		var spr: AnimatedSprite2D = layer.sprite
		var img: Image = (layer.texture as Texture2D).get_image()
		if spr.flip_h:
			img.flip_x()
		if spr.flip_v:
			img.flip_y()
		var want := Vector2i((Vector2(img.get_size()) * spr.scale.abs() * scale).round())
		want = want.max(Vector2i.ONE)
		if img.get_size() != want:
			img.resize(want.x, want.y, Image.INTERPOLATE_NEAREST)
		var rect: Rect2 = layer.rect
		var dst := Vector2i((centre + (rect.position - bounds.get_center()) * scale).round())
		out.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), dst)
	return ImageTexture.create_from_image(out)


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
