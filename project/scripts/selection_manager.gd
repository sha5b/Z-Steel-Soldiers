extends Node
## Autoload: owns unit selection, drag-rectangle state and order dispatch (2D).

signal selection_changed(units: Array)
signal order_issued(world_position: Vector2)

var selected: Array[Node] = []
var drag_start := Vector2.ZERO
var drag_current := Vector2.ZERO
var is_dragging := false


func toggle_select(unit: Node, additive: bool) -> void:
	if additive:
		if unit in selected:
			selected.erase(unit)
		else:
			selected.append(unit)
	elif unit not in selected:
		clear_selection()
		selected.append(unit)
	_cleanup()
	selection_changed.emit(selected)


func clear_selection() -> void:
	for u in selected:
		u.set_selected(false)
	selected.clear()
	selection_changed.emit(selected)


func drop_from_selection(unit: Node) -> void:
	if unit in selected:
		selected.erase(unit)
		selection_changed.emit(selected)


func select_area(world_rect: Rect2) -> void:
	if not Input.is_key_pressed(KEY_SHIFT):
		clear_selection()
	for unit in get_tree().get_nodes_in_group("selectable"):
		if world_rect.has_point(unit.global_position):
			selected.append(unit)
	_cleanup()
	selection_changed.emit(selected)


func issue_order(world_position: Vector2) -> void:
	order_issued.emit(world_position)


func get_drag_rect() -> Rect2:
	return Rect2(drag_start, drag_current - drag_start).abs()


func screen_to_world(screen_pos: Vector2) -> Vector2:
	var canvas: Transform2D = Engine.get_main_loop().root.get_canvas_transform()
	return canvas.affine_inverse() * screen_pos


func screen_to_world_rect(screen_rect: Rect2) -> Rect2:
	var canvas: Transform2D = Engine.get_main_loop().root.get_canvas_transform()
	var inv: Transform2D = canvas.affine_inverse()
	var a := inv * screen_rect.position
	var b := inv * (screen_rect.position + screen_rect.size)
	return Rect2(a, b - a).abs()


func _cleanup() -> void:
	selected = selected.filter(func(u): return is_instance_valid(u))
	for u in selected:
		u.set_selected(true)
