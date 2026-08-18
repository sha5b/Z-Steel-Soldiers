extends Node
## Autoload: owns unit selection, drag-rectangle state and order dispatch (2D).

signal selection_changed(units: Array)
signal order_issued(world_position: Vector2)
signal drag_started
signal drag_moved
signal drag_ended

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
		if is_instance_valid(u):
			u.set_selected(false)
	selected.clear()
	selection_changed.emit(selected)


func drop_from_selection(unit: Node) -> void:
	if unit in selected:
		selected.erase(unit)
		selection_changed.emit(selected)


## One click, one unit — the old clear-then-add dance in one place.
func select_single(unit: Node) -> void:
	clear_selection()
	if unit is Unit2D and unit.alive:
		selected.append(unit)
	_cleanup()
	selection_changed.emit(selected)


## Units report their own deaths now; the selection follows.
func listen(unit: Unit2D) -> void:
	if not unit.died.is_connected(_on_unit_died):
		unit.died.connect(_on_unit_died)


func _on_unit_died(unit: Node) -> void:
	drop_from_selection(unit)


func select_area(world_rect: Rect2) -> void:
	if not Input.is_key_pressed(KEY_SHIFT):
		clear_selection()
	for unit in get_tree().get_nodes_in_group("selectable"):
		# own units only — enemy hardware is never selectable/orderable
		if not (unit is Unit2D) or not unit.alive or unit.carried \
				or unit.team != GameState.player_team:
			continue
		if world_rect.has_point(unit.global_position) and unit not in selected:
			selected.append(unit)
	_cleanup()
	selection_changed.emit(selected)


func issue_order(world_position: Vector2) -> void:
	order_issued.emit(world_position)


## Drag state flows through here so the rectangle view can follow the
## signals instead of polling every frame.
func begin_drag(screen_pos: Vector2) -> void:
	drag_start = screen_pos
	drag_current = screen_pos
	is_dragging = true
	drag_started.emit()


func move_drag(screen_pos: Vector2) -> void:
	drag_current = screen_pos
	drag_moved.emit()


func end_drag() -> void:
	is_dragging = false
	drag_ended.emit()


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
