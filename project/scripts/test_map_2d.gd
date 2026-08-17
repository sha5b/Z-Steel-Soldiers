extends Node2D
## Z test map: loads a converted Zod map (terrain, zones, objects), wires
## drag-select, right-click orders, and the money HUD.

@export var map_json := "res://assets/maps/p02_bb_orig01.json"

@onready var camera: RtsCamera2D = $RtsCamera2D
@onready var money_label: Label = $CanvasLayer/HUD/MoneyLabel


func _ready() -> void:
	SelectionManager.order_issued.connect(_on_order)
	var data: Dictionary = MapLoader.load_map(self, map_json)
	if data.is_empty():
		push_error("empty map")
		return
	camera.position = Vector2(int(data.width), int(data.height)) * 8.0
	camera.bounds = Rect2(0.0, 0.0, float(data.width) * 16.0, float(data.height) * 16.0)
	GameState.money_changed.connect(_update_money)
	_update_money(GameState.player_team, GameState.player_money())
	if "--capture-test" in OS.get_cmdline_args() or "--capture-test" in OS.get_cmdline_user_args():
		print("MAP OK: %dx%d terrain-cells=%d zones=%d units=%d" % [
			data.width, data.height,
			$Terrain.get_used_cells().size() if has_node("Terrain") else -1,
			GameState.zones.size(),
			get_tree().get_nodes_in_group("units").size()])
		await _run_flag_tests()


func _run_flag_tests() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if "--capture-test" in args:
		var u: Unit2D = null
		for unit in get_tree().get_nodes_in_group("units"):
			if unit.team == GameState.player_team:
				u = unit
				break
		var z: Node2D = GameState.zones[0]
		u.position = z.position + z.world_rect().get_center()
		for i in 30:
			z._process(0.1)
			GameState._process(1.0)
		print("CAPTURE: owner=%d money=%d" % [z.owner_team, GameState.player_money()])
	if "--combat-test" in args:
		var a: Unit2D = load("res://scenes/unit.tscn").instantiate()
		a.unit_name = "grunt"
		a.team = 1
		a.position = Vector2(400, 400)
		add_child(a)
		var b: Unit2D = load("res://scenes/unit.tscn").instantiate()
		b.unit_name = "grunt"
		b.team = 2
		b.position = Vector2(430, 400)
		add_child(b)
		for i in 400:
			a._process(0.05)
			b._process(0.05)
		print("COMBAT: a_alive=%s b_alive=%s hp_a=%d hp_b=%d" % [a.alive, b.alive, a.hp, b.hp])
	if "--factory-test" in args:
		var f := RobotFactory.new()
		var z2: Node2D = GameState.zones[1]
		f.position = z2.position + z2.world_rect().get_center() - Vector2(24, 24)
		f.size = Vector2(48, 48)
		add_child(f)
		z2.owner_team = GameState.player_team
		var before := get_tree().get_nodes_in_group("units").size()
		var money_before := GameState.player_money()
		for i in 30:
			f._process(0.5)
		print("FACTORY: units %d -> %d money %d -> %d" % [
			before, get_tree().get_nodes_in_group("units").size(),
			money_before, GameState.player_money()])


func _update_money(_team: int, amount: int) -> void:
	if money_label:
		money_label.text = "$ %d" % amount


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
	var best: Node2D = null
	for unit in get_tree().get_nodes_in_group("selectable"):
		if unit is Node2D and unit.global_position.distance_to(world) < 14.0:
			if best == null or unit.global_position.distance_squared_to(world) < best.global_position.distance_squared_to(world):
				best = unit
	if best:
		SelectionManager.toggle_select(best, Input.is_key_pressed(KEY_SHIFT))
	else:
		SelectionManager.clear_selection()


func _on_order(world_position: Vector2) -> void:
	# ordering a robot onto an empty vehicle/cannon mans it (Z mechanic)
	var empty_vehicle: Node2D = _find_empty_vehicle(world_position)
	var units := SelectionManager.selected.duplicate()
	units.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	for i in units.size():
		var u: Node2D = units[i]
		if empty_vehicle and u is Unit2D and u.kind == "robot":
			empty_vehicle.enter(u)
			u.queue_free()
			SelectionManager.clear_selection()
			return
		var ring := int(sqrt(float(units.size())))
		var offset := Vector2((i % ring) - (ring - 1) * 0.5, (i / ring) - (ring - 1) * 0.5) * 20.0
		u.move_to(world_position + offset)


func _find_empty_vehicle(world_position: Vector2) -> Node2D:
	for v in get_tree().get_nodes_in_group("units"):
		if v is Vehicle2D and not v.manned and v.alive \
				and v.global_position.distance_to(world_position) < 24.0:
			return v
	return null
