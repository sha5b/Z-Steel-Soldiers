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
	# match-scoped subsystems (NavWorld, UnitRegistry, SelectionManager,
	# MatchState) are SCENE CHILDREN above — they ready before the HUD
	# connects and die with the scene (state per match; two matches can
	# coexist in one tree)
	if GameState.pending_config:
		MatchState.current.player_team = GameState.pending_config.player_team
	MatchState.current.ai_difficulty = GameSettings.difficulty
	# the ORIGINAL's animated, context-swapping team cursor, drawn in the
	# stretched canvas so it scales with the window (a 16px OS cursor
	# reads as a speck on a maximized window); the OS pointer hides for
	# the match and comes back when the scene exits
	GameCursor.install($CanvasLayer)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	UiTheme.apply($CanvasLayer/HUD)
	SelectionManager.current.order_issued.connect(_on_order)
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
	MatchState.current.planet = String(data.get("terrain", "desert"))
	_spawn_ambient_life()
	if not GameState.pending_load.is_empty():
		_apply_load()
	camera.position = Vector2(int(data.width), int(data.height)) * 8.0
	# start on the player's fort when the map has one (group scan: scene
	# maps nest everything one level deeper, under the ZMap instance)
	for b in get_tree().get_nodes_in_group(Groups.BUILDINGS):
		if b is FortBuilding and b.team == MatchState.current.player_team:
			camera.position = b.visual_center()
			break
	camera.bounds = Rect2(0.0, 0.0, float(data.width) * 16.0, float(data.height) * 16.0)
	GameState.game_over.connect(_on_game_over)
	var minimap := get_node_or_null("CanvasLayer/HUD/MiniMap")
	if minimap:
		var tileset: Texture2D = load(MapLoader.PLANET_TILESETS.get(String(data.terrain), MapLoader.PLANET_TILESETS.desert))
		minimap.build(data, tileset)
		minimap.move_order.connect(func(world: Vector2): SelectionManager.current.issue_order(world))
	MusicPlayer.play_battle(MatchState.current.planet)
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
			MatchState.current.zones.size(),
			get_tree().get_nodes_in_group(Groups.UNITS).size()])
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
## `--select-first` picks one of the player's units on the way, so a
## screenshot can show the sidebar's portrait/name/weapon/health readouts
## instead of the empty frame they sit in.
func _screenshot(delay_text: String) -> void:
	var delay := float(delay_text)
	Input.warp_mouse(DisplayServer.window_get_size() * 0.5)
	await get_tree().create_timer(delay).timeout
	var shot_all := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if "--select-first" in shot_all:
		_select_first_unit()
		await get_tree().process_frame
		await get_tree().process_frame
	if "--select-factory" in shot_all:
		_select_first_factory()
		await get_tree().process_frame
		await get_tree().process_frame
	if "--dump-visible" in (OS.get_cmdline_args() + OS.get_cmdline_user_args()):
		_dump_ground_nodes()
	var image := get_viewport().get_texture().get_image()
	var out_path := ProjectSettings.globalize_path("res://") + "screenshot_tmp.png"
	image.save_png(out_path)
	print("SCREENSHOT: saved ", out_path, " ", image.get_size())
	get_tree().quit()


func _select_first_unit() -> void:
	for u in UnitRegistry.current.world_units():
		if u.alive and u.team == MatchState.current.player_team and u.kind == "robot":
			SelectionManager.current.select_single(u)
			camera.pan_to(u.global_position)
			return


## Screenshot aid: a producer of the player's, so the build menu is up.
func _select_first_factory() -> void:
	for b in get_tree().get_nodes_in_group(Groups.FACILITIES):
		if b is Building2D and b.alive and b.produces_anything() \
				and b.owner_team == MatchState.current.player_team:
			SelectionManager.current.toggle_select(b, false)
			b.queue_unit("robot:grunt", true)
			camera.pan_to((b as Node2D).global_position)
			return


## TEMP diagnostic: ground-layer nodes (decals, wrecks, building art)
## in the current view with their textures — pins screenshots to nodes.
func _dump_ground_nodes() -> void:
	var xform: Transform2D = get_canvas_transform()
	var view := Rect2(xform.affine_inverse() * Vector2.ZERO,
		get_viewport().get_visible_rect().size / xform.get_scale().abs()).grow(64)
	for node in get_tree().get_nodes_in_group(Groups.CRATERS) \
			+ get_tree().get_nodes_in_group(Groups.TRACKS) \
			+ get_tree().get_nodes_in_group(Groups.ALL_BUILDINGS):
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


## Birds fly ACROSS and leave, so the sky is topped up on a timer
## instead of spawning three at match start and never again.
const BIRD_RESPAWN_SECONDS := 14.0


func _top_up_birds() -> void:
	var flying := 0
	for c in get_children():
		if c is Bird:
			flying += 1
	if flying < Bird.COUNT_PER_MAP:
		Bird.spawn(self, MatchState.current.planet)


## A few ambient critters wander every map (original hut animals).
func _spawn_ambient_life() -> void:
	if Bird.art_exists(MatchState.current.planet):
		for i in Bird.COUNT_PER_MAP:
			Bird.spawn(self, MatchState.current.planet)
		var flock := Timer.new()
		flock.name = "BirdTimer"
		flock.wait_time = BIRD_RESPAWN_SECONDS
		flock.autostart = true
		flock.timeout.connect(_top_up_birds)
		add_child(flock)
	for i in Animal.COUNT_PER_MAP:
		var species := Animal.random_species(MatchState.current.planet)
		if species == "":
			return
		var pos := Vector2(
			randf_range(32.0, NavWorld.current.map_rect.size.x - 32.0),
			randf_range(32.0, NavWorld.current.map_rect.size.y - 32.0))
		if NavWorld.current.walkable(Vector2i(pos / 16.0), false):
			var critter := Animal.new()
			critter.species = species
			critter.position = pos
			add_child(critter)


## Restore a saved match: money, upgrades, zone owners, and units are
## replayed over the freshly spawned map.
func _apply_load() -> void:
	var save: Dictionary = GameState.pending_load
	GameState.pending_load = {}
	MatchState.current.money.clear()
	for team in save.get("money", {}):
		MatchState.current.set_money(int(team), int(save.money[team]))
	for team in save.get("upgrades", {}):
		MatchState.current.upgrades[int(team)] = save.upgrades[team]
	var owners: Array = save.get("zone_owners", [])
	if not owners.is_empty() and owners[0] is Dictionary:
		# zone rects are stable map data — match by rect, never by order
		for zone in MatchState.current.zones:
			for entry in owners:
				if int(entry.get("x", -1)) == zone.zone_rect.position.x \
						and int(entry.get("y", -1)) == zone.zone_rect.position.y \
						and int(entry.get("w", -1)) == zone.zone_rect.size.x \
						and int(entry.get("h", -1)) == zone.zone_rect.size.y:
					zone.set_owner_team(int(entry.get("team", 0)))
					break
	else:
		# legacy saves stored a positional int array
		for i in mini(owners.size(), MatchState.current.zones.size()):
			MatchState.current.zones[i].set_owner_team(int(owners[i]))
	# replace spawned units with the saved roster
	for u in get_tree().get_nodes_in_group(Groups.UNITS):
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
		var spot := NavWorld.current.find_free_spot(pos, String(su.kind))
		if spot != Vector2.INF:
			pos = spot
		var unit := Spawner.spawn(self, String(su.kind), String(su.type),
			int(su.team), pos, bool(su.get("manned", false)))
		if unit:
			unit.apply_dict(su)
			# a LATE JOINER restores the host's roster: keep the host's
			# net ids or every later intent would address the wrong unit
			var net_id := int(su.get("net", 0))
			if net_id > 0 and UnitRegistry.current != null:
				UnitRegistry.current.adopt(unit as Unit2D, net_id)


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
	# dev-only: M reloads the scene on the next map. In an exported build
	# a stray M threw the running match away with no confirmation.
	if OS.is_debug_build() and event is InputEventKey and event.pressed \
			and event.keycode == KEY_M:
		_cycle_map()
		return
	# HOTKEYS = THE HUD'S OWN LETTERS. They used to be Q/E/R for the
	# stances, which no button in the original's frame is labelled with;
	# now every key is the letter printed on the plate it presses, so the
	# HUD teaches its own keyboard: T/D/Z down the sidebar, R/V/B/G along
	# the bottom bar.
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_T:
				GameSettings.set_auto_idle(not GameSettings.auto_idle)
				Fx.ui_click()
				return
			KEY_D:
				_toggle_stance(SelectionManager.OrderStance.DEFEND)
				return
			KEY_Z:
				_toggle_stance(SelectionManager.OrderStance.ATTACK_MOVE)
				return
			KEY_R:
				SelectionFilters.activate("robot")
				return
			KEY_V:
				SelectionFilters.activate("vehicle")
				return
			KEY_B:
				SelectionFilters.activate("building")
				return
			KEY_G:
				SelectionFilters.activate("group")
				return
			KEY_X:
				Commands.eject()  # get garrisoned/crewed units back out
				return
		# CONTROL GROUPS: Ctrl+digit assigns the selection to a slot,
		# digit recalls it, and a second recall inside GROUP_JUMP_SECONDS
		# jumps the camera to the squad. 1-9 then 0 = ten slots.
		var slot := _group_slot(event.keycode)
		if slot >= 0:
			_control_group(slot, event.ctrl_pressed)
			return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		var pause := get_node_or_null("CanvasLayer/PauseMenu")
		if pause and not GameState.over:
			pause.toggle()
		return
	if event is InputEventMouseButton:
		# the chrome is not the battlefield: a press that starts on the
		# sidebar or the bottom bar is never a world click (the panels eat
		# their own clicks, but a release can still land here)
		if event.pressed and not HudFrame.view_rect().has_point(event.position):
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				SelectionManager.current.begin_drag(event.position)
			else:
				SelectionManager.current.end_drag()
				var rect := SelectionManager.current.get_drag_rect()
				if rect.size.length() < 6.0:
					_pick_select(event.position)
				else:
					var a := SelectionManager.current.screen_to_world(rect.position)
					var b := SelectionManager.current.screen_to_world(rect.position + rect.size)
					SelectionManager.current.select_area(Rect2(a, b - a).abs())
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			SelectionManager.current.issue_order(SelectionManager.current.screen_to_world(event.position))
	elif event is InputEventMouseMotion and SelectionManager.current.is_dragging:
		SelectionManager.current.move_drag(event.position)


## D and Z are TOGGLES, like the plates they press: pressing the active
## one drops back to the plain move stance, which is the state the frame
## art draws with neither button lit.
func _toggle_stance(stance: SelectionManager.OrderStance) -> void:
	var sel := SelectionManager.current
	sel.set_stance(SelectionManager.OrderStance.MOVE \
			if sel.order_stance == stance else stance)
	Fx.ui_click()


## Digit keys to control-group slots: 1-9 -> 0-8, 0 -> 9. Anything else
## is -1 (not a group key).
static func _group_slot(keycode: int) -> int:
	if keycode >= KEY_1 and keycode <= KEY_9:
		return keycode - KEY_1
	if keycode == KEY_0:
		return 9
	return -1


## Second press of the same slot inside this window centres the camera.
const GROUP_JUMP_SECONDS := 0.45
var _last_group_slot := -1
var _last_group_time := 0.0


func _control_group(slot: int, assign: bool) -> void:
	var sel := SelectionManager.current
	if assign:
		var stored := sel.assign_group(slot)
		print("GROUP %d: assigned %d unit(s)" % [slot + 1, stored])
		Fx.ui_click()
		return
	var recalled := sel.select_group(slot)
	var now := float(Time.get_ticks_msec()) / 1000.0
	var double_tap := _last_group_slot == slot \
			and now - _last_group_time < GROUP_JUMP_SECONDS
	_last_group_slot = slot
	_last_group_time = now
	if recalled > 0:
		Fx.ui_click()
		if double_tap:
			var centre := sel.group_center(slot)
			if centre != Vector2.INF:
				camera.position = centre


func _pick_select(screen_pos: Vector2) -> void:
	var world := SelectionManager.current.screen_to_world(screen_pos)
	# selection priority lives in ONE place (see Pick) — the cursor's
	# hover and this click can no longer disagree
	var hit := Pick.selectable_at(world, MatchState.current.player_team)
	if hit:
		var additive := Input.is_key_pressed(KEY_SHIFT)
		SelectionManager.current.toggle_select(hit, additive)
		# THE ORIGINAL CENTRES THE CAMERA ON A UNIT YOU CLICK. It reads
		# oddly at first and then becomes the thing that makes the game
		# playable at this zoom: the unit you just picked is always the
		# one in the middle of the screen. Shift-adding to a squad does
		# NOT move the camera — that would yank the view around mid-drag.
		if GameSettings.centre_on_select and not additive and hit is Node2D \
				and hit in SelectionManager.current.selected:
			camera.pan_to((hit as Node2D).global_position)
		if hit is Unit2D:
			Fx.selected_bark()  # the unit reports in, and its portrait talks
	else:
		SelectionManager.current.clear_selection()


func _on_order(world_position: Vector2) -> void:
	Commands.dispatch(world_position)
	# AND THE ORIGINAL DROPS THE SELECTION once the order is away. That is
	# deliberate in Z — it is what makes the game reward decisive clicking
	# and punish dithering — and it is why the original never needed a
	# "stop giving my squad new orders" affordance.
	if GameSettings.auto_deselect:
		SelectionManager.current.clear_selection()
