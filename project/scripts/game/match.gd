extends Node2D
## Match coordinator: loads a map, wires the camera/HUD/input, applies
## saves and ends the game. Orders are dispatched by Commands, the test
## harness lives in SelfTests, the end screen in scenes/game_over.tscn.

@export var map_json := "res://assets/maps/p08_bb_p08m01.json"

var _map_list: PackedStringArray = []
var _map_index := 0

@onready var camera: RtsCamera2D = $RtsCamera2D


func _ready() -> void:
	Engine.time_scale = GameSettings.game_speed()  # options-screen speed
	# the ORIGINAL's animated, context-swapping team cursor, drawn in the
	# stretched canvas so it scales with the window (a 16px OS cursor
	# reads as a speck on a maximized window); the OS pointer hides for
	# the match and comes back when the scene exits
	GameCursor.install($CanvasLayer)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	UiTheme.apply($CanvasLayer/HUD)
	SelectionManager.order_issued.connect(_on_order)
	var chosen: String = GameState.next_map if GameState.next_map != "" else map_json
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if String(arg).begins_with("--map="):  # test override: --map=res://assets/maps/x.json
			chosen = String(arg).substr(6)
	_map_list = PackedStringArray()
	for e in MapCatalog.entries():
		_map_list.append(String(e.name) + (".json" if e.json else ".tscn"))
	_map_index = _map_list.find(chosen.get_file())
	GameState.current_map = chosen
	var data: Dictionary = MapLoader.load_map(self, chosen)
	if data.is_empty():
		push_error("empty map")
		return
	MatchState.planet = String(data.get("terrain", "desert"))
	_spawn_ambient_life()
	if not GameState.pending_load.is_empty():
		_apply_load()
	camera.position = Vector2(int(data.width), int(data.height)) * 8.0
	# start on the player's fort when the map has one (group scan: scene
	# maps nest everything one level deeper, under the ZMap instance)
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is FortBuilding and b.team == MatchState.player_team:
			camera.position = b.visual_center()
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
			MatchState.zones.size(),
			get_tree().get_nodes_in_group("units").size()])
		await SelfTests.run(self)
		# the suite is value-driven and fast — don't idle the match out
		# to --quit-after once it's done (that linger ate minutes per run)
		if "--screenshot" not in shot_args:
			get_tree().quit()
	if "--screenshot" in shot_args:
		await _screenshot(shot_args[shot_args.find("--screenshot") + 1] if shot_args.size() > shot_args.find("--screenshot") + 1 else "2.0")


## Restore producer state (rally/queue) onto matched buildings —
## matched by building id + team, consumed from the saved list.
func _apply_facility_save(child: Node, facilities: Array) -> void:
	if not (child is Building2D):
		return
	var b := child as Building2D
	if not b.produces_anything() or b.owner_team == 0:
		return
	for i in facilities.size():
		var d: Dictionary = facilities[i]
		if int(d.get("id", -1)) == b.building_id \
				and int(d.get("team", 0)) == b.owner_team:
			b.apply_dict(d)
			facilities.remove_at(i)
			return


## Test helper: capture the viewport after N seconds and quit.
func _screenshot(delay_text: String) -> void:
	var delay := float(delay_text)
	Input.warp_mouse(DisplayServer.window_get_size() * 0.5)
	await get_tree().create_timer(delay).timeout
	if "--dump-visible" in (OS.get_cmdline_args() + OS.get_cmdline_user_args()):
		_dump_ground_nodes()
	var image := get_viewport().get_texture().get_image()
	var out_path := ProjectSettings.globalize_path("res://") + "screenshot_tmp.png"
	image.save_png(out_path)
	print("SCREENSHOT: saved ", out_path, " ", image.get_size())
	get_tree().quit()


## TEMP diagnostic: ground-layer nodes (decals, wrecks, building art)
## in the current view with their textures — pins screenshots to nodes.
func _dump_ground_nodes() -> void:
	var xform: Transform2D = get_canvas_transform()
	var view := Rect2(xform.affine_inverse() * Vector2.ZERO,
		get_viewport().get_visible_rect().size / xform.get_scale().abs()).grow(64)
	for node in get_tree().get_nodes_in_group("craters") \
			+ get_tree().get_nodes_in_group("tracks") \
			+ get_tree().get_nodes_in_group("all_buildings"):
		if node is not CanvasItem or not (node as CanvasItem).is_visible_in_tree():
			continue
		var wpos: Vector2 = (node as CanvasItem).get_global_transform() * Vector2()
		if not view.has_point(wpos):
			continue
		var tex := ""
		var sprite: Node = node.get_node_or_null("Sprite2D") if node.get_child_count() > 0 else null
		if sprite and sprite.get("texture") is Texture2D:
			tex = String((sprite.get("texture") as Texture2D).resource_path)
		print("DUMP ", node.name, " pos=", wpos.round(), " alive=", node.get("alive"), " ", tex)


## A few ambient critters wander every map (original hut animals).
func _spawn_ambient_life() -> void:
	for i in Animal.COUNT_PER_MAP:
		var species := Animal.random_species(MatchState.planet)
		if species == "":
			return
		var pos := Vector2(
			randf_range(32.0, NavWorld.map_rect.size.x - 32.0),
			randf_range(32.0, NavWorld.map_rect.size.y - 32.0))
		if NavWorld.walkable(Vector2i(pos / 16.0), false):
			var critter := Animal.new()
			critter.species = species
			critter.position = pos
			add_child(critter)


## Restore a saved match: money, upgrades, zone owners, and units are
## replayed over the freshly spawned map.
func _apply_load() -> void:
	var save: Dictionary = GameState.pending_load
	GameState.pending_load = {}
	MatchState.money.clear()
	for team in save.get("money", {}):
		MatchState.set_money(int(team), int(save.money[team]))
	for team in save.get("upgrades", {}):
		MatchState.upgrades[int(team)] = save.upgrades[team]
	var owners: Array = save.get("zone_owners", [])
	if not owners.is_empty() and owners[0] is Dictionary:
		# zone rects are stable map data — match by rect, never by order
		for zone in MatchState.zones:
			for entry in owners:
				if int(entry.get("x", -1)) == zone.zone_rect.position.x \
						and int(entry.get("y", -1)) == zone.zone_rect.position.y \
						and int(entry.get("w", -1)) == zone.zone_rect.size.x \
						and int(entry.get("h", -1)) == zone.zone_rect.size.y:
					zone.set_owner_team(int(entry.get("team", 0)))
					break
	else:
		# legacy saves stored a positional int array
		for i in mini(owners.size(), MatchState.zones.size()):
			MatchState.zones[i].set_owner_team(int(owners[i]))
	# replace spawned units with the saved roster
	for u in get_tree().get_nodes_in_group("units"):
		u.queue_free()
	var facilities: Array = save.get("facilities", [])
	for child in get_children():
		if child is ZMap:
			for map_child in child.get_children():
				_apply_facility_save(map_child, facilities)
		else:
			_apply_facility_save(child, facilities)
	for su in save.get("units", []):
		# saved coordinates can predate geometry changes (the fort solid
		# row moved a tile) — validate every restore against today's nav
		var pos := Vector2(float(su.x), float(su.y))
		var spot := NavWorld.find_free_spot(pos, String(su.kind))
		if spot != Vector2.INF:
			pos = spot
		var unit := Spawner.spawn(self, String(su.kind), String(su.type),
			int(su.team), pos, bool(su.get("manned", false)))
		if unit:
			unit.apply_dict(su)


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


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_M:
		_cycle_map()
		return
	# stance hotkeys: Q attack-move, E defend, R plain move, T toggles
	# smart idle (auto-man) — reflected by the stance bar next to the
	# minimap
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				SelectionManager.order_stance = SelectionManager.OrderStance.ATTACK_MOVE
				Fx.ui_click()
				return
			KEY_E:
				SelectionManager.order_stance = SelectionManager.OrderStance.DEFEND
				Fx.ui_click()
				return
			KEY_R:
				SelectionManager.order_stance = SelectionManager.OrderStance.MOVE
				Fx.ui_click()
				return
			KEY_T:
				GameSettings.auto_idle = not GameSettings.auto_idle
				Fx.ui_click()
				return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		var pause := get_node_or_null("CanvasLayer/PauseMenu")
		if pause and not GameState.over:
			pause.toggle()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				SelectionManager.begin_drag(event.position)
			else:
				SelectionManager.end_drag()
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
		SelectionManager.move_drag(event.position)


func _pick_select(screen_pos: Vector2) -> void:
	var world := SelectionManager.screen_to_world(screen_pos)
	# player factories and fort first (selecting opens the production
	# panel) — group scans, so scene maps (nested under ZMap) work too
	for c in get_tree().get_nodes_in_group("facilities"):
		if (c is RobotFactory or c is VehicleFactory) and c.owner_team == MatchState.player_team \
				and c.art_world_rect().has_point(world):
			SelectionManager.toggle_select(c, Input.is_key_pressed(KEY_SHIFT))
			return
	for c in get_tree().get_nodes_in_group("buildings"):
		if c is FortBuilding and c.team == MatchState.player_team \
				and c.art_world_rect().has_point(world):
			SelectionManager.toggle_select(c, Input.is_key_pressed(KEY_SHIFT))
			return
	var best: Node2D = null
	for unit in get_tree().get_nodes_in_group("selectable"):
		if unit is Unit2D and unit.alive and not unit.carried \
				and unit.team == MatchState.player_team \
				and unit.global_position.distance_to(world) < 8.0:
			if best == null or unit.global_position.distance_squared_to(world) < best.global_position.distance_squared_to(world):
				best = unit
	if best:
		SelectionManager.toggle_select(best, Input.is_key_pressed(KEY_SHIFT))
	else:
		SelectionManager.clear_selection()


func _on_order(world_position: Vector2) -> void:
	Commands.dispatch(world_position)
