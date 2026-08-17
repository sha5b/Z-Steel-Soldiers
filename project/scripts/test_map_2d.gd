extends Node2D
## Z test map: repeated desert tileset ground, robot squad, drag-select and
## right-click orders. Placeholder flag/fort props from original sprites.

const UNIT := preload("res://scenes/unit.tscn")

@onready var camera: RtsCamera2D = $RtsCamera2D


func _ready() -> void:
	SelectionManager.order_issued.connect(_on_order)
	var tex := load("res://assets/z/planets/desert.png")
	if tex:
		$Ground.texture = tex
	for i in 8:
		var u := UNIT.instantiate()
		u.unit_name = "grunt"
		u.team = 1
		u.position = Vector2(200.0 + (i % 4) * 24.0, 180.0 + (i / 4) * 24.0)
		add_child(u)
	for i in 4:
		var u := UNIT.instantiate()
		u.unit_name = "grunt"
		u.team = 2
		u.position = Vector2(900.0 + (i % 2) * 24.0, 900.0 + (i / 2) * 24.0)
		add_child(u)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				SelectionManager.drag_start = event.position
				SelectionManager.drag_current = event.position
				SelectionManager.is_dragging = true
			else:
				SelectionManager.is_dragging = false
				var rect := SelectionManager.get_drag_rect()
				if rect.size.length() < 6.0:
					_pick_select(event.position)
				else:
					var a := SelectionManager.screen_to_world(rect.position)
					var b := SelectionManager.screen_to_world(rect.position + rect.size)
					SelectionManager.select_area(Rect2(a, b - a).abs())
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			SelectionManager.issue_order(SelectionManager.screen_to_world(event.position))
	elif event is InputEventMouseMotion and SelectionManager.is_dragging:
		SelectionManager.drag_current = event.position


func _pick_select(screen_pos: Vector2) -> void:
	var world := SelectionManager.screen_to_world(screen_pos)
	for unit in get_tree().get_nodes_in_group("selectable"):
		if unit.global_position.distance_to(world) < 12.0:
			SelectionManager.toggle_select(unit, Input.is_key_pressed(KEY_SHIFT))
			return
	SelectionManager.clear_selection()


func _on_order(world_position: Vector2) -> void:
	var units := SelectionManager.selected.duplicate()
	units.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	for i in units.size():
		var u: Node2D = units[i]
		var ring := int(sqrt(float(units.size())))
		var offset := Vector2((i % ring) - (ring - 1) * 0.5, (i / ring) - (ring - 1) * 0.5) * 20.0
		u.move_to(world_position + offset)
