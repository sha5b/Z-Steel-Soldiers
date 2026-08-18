extends Node2D
## Match coordinator: loads a map, wires the camera/HUD/input, applies
## saves and ends the game. Orders are dispatched by Commands, the test
## harness lives in SelfTests, the end screen in scenes/game_over.tscn.

@export var map_json := "res://assets/maps/p08_bb_p08m01.json"

var _map_list: PackedStringArray = []
var _map_index := 0

@onready var camera: RtsCamera2D = $RtsCamera2D


func _ready() -> void:
	var cursor_path := "res://assets/z/ui/cursor/cursor_blue_n00.png"
	if ResourceLoader.exists(cursor_path):
		Input.set_custom_mouse_cursor(load(cursor_path), Input.CURSOR_ARROW,
			Vector2(6, 3))  # original in-game pointer
	UiTheme.apply($CanvasLayer/HUD)
	SelectionManager.order_issued.connect(_on_order)
	var chosen: String = GameState.next_map if GameState.next_map != "" else map_json
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if String(arg).begins_with("--map="):  # test override: --map=res://assets/maps/x.json
			chosen = String(arg).substr(6)
	_map_list = PackedStringArray()
	for f in DirAccess.get_files_at("res://assets/maps"):
		if String(f).ends_with(".json"):
			_map_list.append(String(f))
	for f in DirAccess.get_files_at("res://assets/maps_scenes"):
		if String(f).ends_with(".tscn"):
			_map_list.append(String(f))
	_map_list.sort()
	_map_index = _map_list.find(chosen.get_file())
	GameState.current_map = chosen
	var data: Dictionary = MapLoader.load_map(self, chosen)
	if data.is_empty():
		push_error("empty map")
		return
	if not GameState.pending_load.is_empty():
		_apply_load()
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
	MusicPlayer.play_battle()
	var shot_args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if SelfTests.should_run():
		var terrain_cells := -1
		if has_node("Terrain"):
			terrain_cells = $Terrain.get_used_cells().size()
		else:
			for child in get_children():
				if child is ZMap and child.has_node("Terrain"):
					terrain_cells = child.get_node("Terrain").get_used_cells().size()
		print("MAP OK: %dx%d terrain-cells=%d zones=%d units=%d" % [
			data.width, data.height, terrain_cells,
			GameState.zones.size(),
			get_tree().get_nodes_in_group("units").size()])
		await SelfTests.run(self)
	if "--screenshot" in shot_args:
		await _screenshot(shot_args[shot_args.find("--screenshot") + 1] if shot_args.size() > shot_args.find("--screenshot") + 1 else "2.0")


## Test helper: capture the viewport after N seconds and quit.
func _screenshot(delay_text: String) -> void:
	var delay := float(delay_text)
	Input.warp_mouse(DisplayServer.window_get_size() * 0.5)
	await get_tree().create_timer(delay).timeout
	var image := get_viewport().get_texture().get_image()
	var out_path := ProjectSettings.globalize_path("res://") + "screenshot_tmp.png"
	image.save_png(out_path)
	print("SCREENSHOT: saved ", out_path, " ", image.get_size())
	get_tree().quit()


## Restore a saved match: money, upgrades, zone owners, and units are
## replayed over the freshly spawned map.
func _apply_load() -> void:
	var save: Dictionary = GameState.pending_load
	GameState.pending_load = {}
	GameState.money.clear()
	for team in save.get("money", {}):
		GameState.money[int(team)] = int(save.money[team])
	for team in save.get("upgrades", {}):
		GameState.upgrades[int(team)] = save.upgrades[team]
	var owners: Array = save.get("zone_owners", [])
	for i in mini(owners.size(), GameState.zones.size()):
		GameState.zones[i].set_owner_team(int(owners[i]))
	# replace spawned units with the saved roster
	for u in get_tree().get_nodes_in_group("units"):
		u.queue_free()
	for su in save.get("units", []):
		var unit: Node2D
		if String(su.kind) == "robot":
			unit = load("res://scenes/unit.tscn").instantiate()
			unit.unit_name = String(su.type)
		else:
			unit = load("res://scenes/vehicle.tscn").instantiate()
			unit.setup_vehicle(String(su.kind), String(su.type), int(su.team) if bool(su.manned) else 0)
		unit.team = int(su.team)
		unit.position = Vector2(float(su.x), float(su.y))
		add_child(unit)
		unit.hp = int(su.hp)


func _cycle_map() -> void:
	if _map_list.is_empty():
		return
	_map_index = wrapi(_map_index + 1, 0, _map_list.size())
	var dir := "res://assets/maps_scenes/" if _map_list[_map_index].ends_with(".tscn") \
			else "res://assets/maps/"
	GameState.next_map = dir + _map_list[_map_index]
	print("MAP SWITCH -> ", _map_list[_map_index])
	GameState.reset_for_new_map()
	get_tree().reload_current_scene()


func _on_game_over(winning_team: int) -> void:
	var overlay: Control = preload("res://scenes/game_over.tscn").instantiate()
	$CanvasLayer.add_child(overlay)
	overlay.show_for(winning_team)


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
		if unit is Unit2D and unit.alive and not unit.carried \
				and unit.team == GameState.player_team \
				and unit.global_position.distance_to(world) < 14.0:
			if best == null or unit.global_position.distance_squared_to(world) < best.global_position.distance_squared_to(world):
				best = unit
	if best:
		SelectionManager.toggle_select(best, Input.is_key_pressed(KEY_SHIFT))
	else:
		SelectionManager.clear_selection()


func _on_order(world_position: Vector2) -> void:
	Commands.dispatch(world_position)
