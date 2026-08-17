extends Node2D
## Z test map: loads a converted Zod map (terrain, zones, objects), wires
## drag-select, right-click orders, and the money HUD.

@export var map_json := "res://assets/maps/p08_bb_p08m01.json"

var _map_list: PackedStringArray = []
var _map_index := 0

@onready var camera: RtsCamera2D = $RtsCamera2D


func _ready() -> void:
	SelectionManager.order_issued.connect(_on_order)
	var chosen: String = GameState.next_map if GameState.next_map != "" else map_json
	var all_maps := DirAccess.get_files_at("res://assets/maps")
	_map_list = PackedStringArray()
	for f in all_maps:
		if String(f).ends_with(".json"):
			_map_list.append(f)
	_map_list.sort()
	_map_index = _map_list.find(chosen.get_file())
	var data: Dictionary = MapLoader.load_map(self, chosen)
	if data.is_empty():
		push_error("empty map")
		return
	camera.position = Vector2(int(data.width), int(data.height)) * 8.0
	# start on the player's fort when the map has one
	for child in get_children():
		if child is FortBuilding and child.team == GameState.player_team:
			camera.position = child.visual_center()
			break
	camera.bounds = Rect2(0.0, 0.0, float(data.width) * 16.0, float(data.height) * 16.0)
	GameState.game_over.connect(_on_game_over)
	var minimap := get_node_or_null("CanvasLayer/HUD/MiniMap")
	if minimap:
		var tileset: Texture2D = load(MapLoader.PLANET_TILESETS.get(String(data.terrain), MapLoader.PLANET_TILESETS.desert))
		minimap.build(data, tileset)
		minimap.move_order.connect(func(world: Vector2): SelectionManager.issue_order(world))
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
	if "--ai-test" in args:
		var ai := get_node_or_null("CpuAi_T2")
		if ai:
			var moved := 0
			for u in get_tree().get_nodes_in_group("units"):
				if u is Node2D and u.team == 2 and u.move_target != Vector2.ZERO:
					moved += 1
			ai._think()
			var moved_after := 0
			for u in get_tree().get_nodes_in_group("units"):
				if u is Node2D and u.team == 2 and u.move_target != Vector2.ZERO:
					moved_after += 1
			print("AI: enemy robots with orders %d -> %d" % [moved, moved_after])
	if "--prod-test" in args:
		# simulate: capture a factory zone for the player, queue a psycho,
		# run the factory until it spawns
		var f2: RobotFactory = null
		for c in get_children():
			if c is RobotFactory:
				f2 = c
				break
		if f2:
			var zone_hit: Node2D = null
			for z3 in GameState.zones:
				if z3.world_rect().has_point(f2.world_footprint().get_center()):
					zone_hit = z3
					break
			zone_hit.owner_team = GameState.player_team
			GameState.money[GameState.player_team] = 500
			f2._process(0.1)  # sync owner from zone before queueing
			var ok: bool = f2.queue_unit("psycho")
			var count_before := get_tree().get_nodes_in_group("units").size()
			for i in 40:
				f2._process(0.5)
			var psychos := 0
			for u3 in get_tree().get_nodes_in_group("units"):
				if u3 is Unit2D and u3.unit_name == "psycho" and u3.team == GameState.player_team:
					psychos += 1
			print("PROD: queued=%s units %d -> %d psychos=%d queue_left=%d" % [
				ok, count_before, get_tree().get_nodes_in_group("units").size(),
				psychos, f2.queue.size()])
	if "--path-test" in args:
		var grid: AStarGrid2D = GameState.nav_grid
		if grid == null:
			print("PATH: no grid")
		else:
			var solid := 0
			var open_cells := PackedVector2Array()
			for y in grid.region.size.y:
				for x in grid.region.size.x:
					if not grid.is_point_solid(Vector2i(x, y)):
						open_cells.append(Vector2(x, y))
					else:
						solid += 1
			# pick a routable pair (maps can have disconnected landmasses)
			var start_px := Vector2.ZERO
			var goal := Vector2.ZERO
			var rng := RandomNumberGenerator.new()
			rng.seed = 42
			for attempt in 200:
				var a2: Vector2 = open_cells[rng.randi_range(0, open_cells.size() - 1)]
				var b2: Vector2 = open_cells[rng.randi_range(0, open_cells.size() - 1)]
				if a2.distance_to(b2) < 60.0:
					continue
				var probe := GameState.request_path(a2 * 16.0 + Vector2(8, 8), b2 * 16.0 + Vector2(8, 8), "robot")
				if not probe.is_empty():
					start_px = a2 * 16.0 + Vector2(8, 8)
					goal = b2 * 16.0 + Vector2(8, 8)
					break
			if goal == Vector2.ZERO:
				print("PATH: no routable pair found")
			else:
				var u4: Unit2D = load("res://scenes/unit.tscn").instantiate()
				u4.team = 1
				u4.position = start_px
				add_child(u4)
				u4.move_to(goal)
				var crossed_solid := 0
				var total := 0
				for i in 6000:
					u4._process(0.05)
					if i % 5 == 0:
						var cell := Vector2i((u4.position / 16.0).floor())
						if grid.is_point_solid(cell):
							crossed_solid += 1
						total += 1
					if u4.move_target == Vector2.ZERO:
						break
				var dist: float = u4.position.distance_to(goal)
				print("PATH: solid_cells=%d waypoints=%d crossed_solid=%d/%d arrived=%s dist=%.1f" % [
					solid, u4.waypoints.size(), crossed_solid, total,
					u4.move_target == Vector2.ZERO, dist])
	if "--dir-test" in args:
		# zod convention: r000 faces +X (right), r090 down, r180 left, r270 up
		var dirs := {
			0.0: 0, PI / 2.0: 6, PI: 4, -PI / 2.0: 2,
			PI / 4.0: 7, -PI / 4.0: 1, 3.0 * PI / 4.0: 5, -3.0 * PI / 4.0: 3,
		}
		var bad := 0
		for ang in dirs:
			var got: int = Unit2D._angle_to_dir(ang)
			if got != dirs[ang]:
				bad += 1
		print("DIR: mismatches=%d of 8" % bad)
	if "--near-test" in args:
		var jeep3: Vehicle2D = load("res://scenes/vehicle.tscn").instantiate()
		jeep3.setup_vehicle("vehicle", "jeep", 0)
		jeep3.position = Vector2(700, 700)
		add_child(jeep3)
		var walker: Unit2D = load("res://scenes/unit.tscn").instantiate()
		walker.team = 1
		walker.position = Vector2(500, 700)
		add_child(walker)
		walker.enter_target = jeep3
		walker.move_to(jeep3.global_position)
		var instant: bool = jeep3.manned  # must NOT be manned before walking
		for i in 400:
			walker._process(0.05)
			if jeep3.manned or not is_instance_valid(walker):
				break
		print("NEAR: instant=%s manned_after_walk=%s" % [instant, jeep3.manned])
	if "--flag-test" in args:
		var radar: Building2D = Building2D.new()
		radar.setup(2, 0, "desert")
		var zr: Node2D = GameState.zones[0]
		radar.position = zr.position + zr.world_rect().get_center()
		add_child(radar)
		zr.owner_team = GameState.player_team
		radar._process(0.0)
		print("FLAG: radar team=%d (want %d)" % [radar.team, GameState.player_team])
	if "--pickup-test" in args:
		var pk := Pickup.new()
		pk.pickup_type = "grenades"
		pk.position = Vector2(400, 400)
		add_child(pk)
		var collector: Unit2D = load("res://scenes/unit.tscn").instantiate()
		collector.team = 1
		collector.position = Vector2(370, 400)
		add_child(collector)
		var mult_before: float = GameState.robot_damage_mult(1)
		collector.move_to(Vector2(400, 400))
		for i in 100:
			collector._process(0.05)
			pk._process(0.05)
			if not is_instance_valid(pk):
				break
		print("PICKUP: granted=%s mult %.1f -> %.1f" % [
			GameState.has_upgrade(1, "grenades"), mult_before,
			GameState.robot_damage_mult(1)])
	if "--fortprod-test" in args:
		var fort2: FortBuilding = null
		for c in get_children():
			if c is FortBuilding and c.team == GameState.player_team:
				fort2 = c
				break
		if fort2:
			GameState.money[1] = 500
			var ok2: bool = fort2.queue_unit("psycho")
			var count0 := get_tree().get_nodes_in_group("units").size()
			for i in 40:
				fort2._process(0.5)
			var psychos2 := 0
			for u5 in get_tree().get_nodes_in_group("units"):
				if u5 is Unit2D and u5.unit_name == "psycho" and u5.team == 1:
					psychos2 += 1
			print("FORTPROD: queued=%s units %d -> %d psychos=%d" % [
				ok2, count0, get_tree().get_nodes_in_group("units").size(), psychos2])
	if "--cancel-test" in args:
		var fort3: FortBuilding = null
		for c in get_children():
			if c is FortBuilding and c.team == GameState.player_team:
				fort3 = c
				break
		if fort3:
			GameState.money[1] = 500
			fort3.queue_unit("grunt")
			fort3.queue_unit("sniper")
			var money_mid: int = GameState.money[1]
			fort3.cancel_at(1)  # refund the sniper ($80)
			print("CANCEL: queue=%s money %d -> %d (sniper refund %d)" % [
				fort3.queue, money_mid, GameState.money[1], 80])
	if "--vehpath-test" in args:
		var rg: AStarGrid2D = GameState.nav_grid
		var vg: AStarGrid2D = GameState.vehicle_grid
		var water_cell := Vector2i(-1, -1)
		for y in rg.region.size.y:
			for x in rg.region.size.x:
				var c2 := Vector2i(x, y)
				if not rg.is_point_solid(c2) and vg.is_point_solid(c2):
					water_cell = c2
					break
			if water_cell.x >= 0:
				break
		if water_cell.x < 0:
			print("VEHPATH: no water cells on map")
		else:
			var water_px := Vector2(water_cell) * 16.0 + Vector2(8, 8)
			var rpath := GameState.request_path(water_px + Vector2(200, 0), water_px, "robot")
			var vpath := GameState.request_path(water_px + Vector2(200, 0), water_px, "vehicle")
			var vehicle_refused: bool = vpath.is_empty()
			var vends_on_water: bool = not vehicle_refused \
				and vg.is_point_solid(Vector2i((vpath[vpath.size() - 1] / 16.0).floor()))
			print("VEHPATH: water=%s robot_got_path=%s vehicle_refused=%s vehicle_ends_water=%s" % [
				water_cell, not rpath.is_empty(), vehicle_refused, vends_on_water])
	if "--apc-test" in args:
		var apc2: Vehicle2D = load("res://scenes/vehicle.tscn").instantiate()
		apc2.setup_vehicle("vehicle", "apc", 1)
		apc2.position = Vector2(300, 300)
		add_child(apc2)
		var robot1: Unit2D = load("res://scenes/unit.tscn").instantiate()
		robot1.team = 1
		robot1.position = Vector2(300, 300)
		add_child(robot1)
		var loaded: bool = apc2.load_robot(robot1)
		var hidden: bool = not robot1.visible and robot1.carried
		apc2.move_to(Vector2(500, 500))
		for i in 400:
			apc2._process(0.05)
			if apc2.move_target == Vector2.ZERO:
				break
		var unloaded_near: bool = robot1.visible and not robot1.carried \
			and robot1.global_position.distance_to(apc2.global_position) < 60.0
		print("APC: loaded=%s hidden=%s arrived=%s unloaded_near=%s" % [
			loaded, hidden, apc2.move_target == Vector2.ZERO, unloaded_near])
	if "--win-test" in args:
		var fort: FortBuilding = null
		for c in get_children():
			if c is FortBuilding and c.team == 2:
				fort = c
		if fort:
			GameState.game_over.connect(func(winner): print("WINNER: %d" % winner))
			fort.take_damage(fort.hp)
			print("WIN: fort_alive=%s game_over=%s" % [fort.alive, GameState.over])



func _cycle_map() -> void:
	if _map_list.is_empty():
		return
	_map_index = wrapi(_map_index + 1, 0, _map_list.size())
	GameState.next_map = "res://assets/maps/" + _map_list[_map_index]
	print("MAP SWITCH -> ", _map_list[_map_index])
	GameState.reset_for_new_map()
	get_tree().reload_current_scene()


func _on_game_over(winning_team: int) -> void:
	var overlay := Control.new()
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 14)
	overlay.add_child(box)
	var label := Label.new()
	label.text = "VICTORY!" if winning_team == GameState.player_team else "DEFEAT"
	label.add_theme_font_size_override("font_size", 64)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var again := Button.new()
	again.text = "Play Again"
	again.custom_minimum_size = Vector2(200, 40)
	again.pressed.connect(func():
		GameState.reset_for_new_map()
		get_tree().change_scene_to_file("res://scenes/main.tscn"))
	box.add_child(again)
	var maps := Button.new()
	maps.text = "Map Select"
	maps.custom_minimum_size = Vector2(200, 40)
	maps.pressed.connect(func():
		GameState.reset_for_new_map()
		get_tree().change_scene_to_file("res://scenes/map_select.tscn"))
	box.add_child(maps)
	$CanvasLayer.add_child(overlay)
	get_tree().paused = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_M:
		_cycle_map()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		var pause := get_node_or_null("CanvasLayer/PauseMenu")
		if pause and not GameState.over:
			pause.toggle()
		return
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
	# player factories and fort first (selecting opens the production panel)
	for c in get_children():
		if (c is RobotFactory or c is VehicleFactory) and c.owner_team == GameState.player_team \
				and c.world_footprint().has_point(world):
			SelectionManager.toggle_select(c, Input.is_key_pressed(KEY_SHIFT))
			return
		if c is FortBuilding and c.team == GameState.player_team \
				and c.world_footprint().has_point(world):
			SelectionManager.toggle_select(c, Input.is_key_pressed(KEY_SHIFT))
			return
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
	# ordering robots toward an empty vehicle/cannon mans it once they walk
	# up to it; toward a friendly manned APC loads them as passengers
	var empty_vehicle: Node2D = _find_empty_vehicle(world_position)
	var apc := _find_apc(world_position)
	var units := SelectionManager.selected.duplicate()
	units.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	for i in units.size():
		var u: Node2D = units[i]
		if u is Unit2D and u.kind == "robot":
			if empty_vehicle:
				u.enter_target = empty_vehicle
				u.move_to(empty_vehicle.global_position)
				continue
			if apc and u.team == apc.team:
				u.enter_target = apc
				u.move_to(apc.global_position)
				continue
		var ring := int(sqrt(float(units.size())))
		var offset := Vector2((i % ring) - (ring - 1) * 0.5, (i / ring) - (ring - 1) * 0.5) * 20.0
		u.move_to(world_position + offset)


func _find_apc(world_position: Vector2) -> Vehicle2D:
	for v in get_tree().get_nodes_in_group("units"):
		if v is Vehicle2D and v.is_apc() and v.manned and v.alive and v.team != 0 \
				and v.global_position.distance_to(world_position) < 24.0:
			return v
	return null


func _find_empty_vehicle(world_position: Vector2) -> Node2D:
	for v in get_tree().get_nodes_in_group("units"):
		if v is Vehicle2D and not v.manned and v.alive \
				and v.global_position.distance_to(world_position) < 24.0:
			return v
	return null
