class_name SelfTests
extends Object
## Headless regression harness behind command-line flags (no test
## framework dependency). Run, e.g.:
##   godot --headless --path . res://scenes/main.tscn --combat-test --quit-after 600
## Each flag prints one TESTNAME: line; a pass is zero SCRIPT ERROR and
## zero `CHECK FAILED:` lines (TestRig). A runtime error aborts the whole
## run — later flags stay silent, so fix the first error you see.
## Domain modules live beside this file (path_tests.gd is the pattern):
## one class_name per domain, static funcs taking (ctx, rig), flags
## routed from run() so the CLI surface stays one list.


static func _all_nodes(root: Node) -> Array:
	var out := [root]
	for child in root.get_children():
		out.append_array(_all_nodes(child))
	return out


static func should_run() -> bool:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for flag in ["capture", "combat", "factory", "ai", "path", "dir", "near", "flag",
			"pickup", "prod", "fortprod", "cancel", "vehpath", "apc", "save",
			"campaign", "win", "fx", "mount", "building", "parade", "cap",
			"layer", "vfx", "tactics", "pose", "level", "repair", "combat2",
			"ui", "teams", "defs", "scenes", "orders", "balance", "cursor",
			"mp", "rally", "placement", "fortkill", "parity", "art", "mpmatch",
			"garrison", "terrain", "group", "veteran", "retail"]:
		if "--%s-test" % flag in args:
			return true
	return false


## Test helper: `--screenshot [delay]` captures the viewport and quits —
## run windowed (not --headless), scene path picks the screen.
static func maybe_screenshot(ctx: Node, out := "screenshot_tmp.png") -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if "--screenshot" not in args:
		return
	var i := args.find("--screenshot")
	var delay := 1.0
	Input.warp_mouse(DisplayServer.window_get_size() * 0.5)
	if i + 1 < args.size() and String(args[i + 1]).is_valid_float():
		delay = float(args[i + 1])
	await ctx.get_tree().create_timer(delay).timeout
	var image := ctx.get_viewport().get_texture().get_image()
	var out_path := ProjectSettings.globalize_path("res://") + out
	image.save_png(out_path)
	print("SCREENSHOT: saved ", out_path, " ", image.get_size())
	ctx.get_tree().quit()


static func run(ctx: Node) -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var tree := ctx.get_tree()
	# movement is physics-driven (move_and_slide) in the real game; the
	# harness steps units directly for speed — logic-only, the physics
	# path is exercised by playing (and by --path-test's solid audit)
	TestLevers.direct_step = true
	Engine.time_scale = 4.0  # awaited-frame sims run 4x faster; manual loops pass fixed deltas

	# isolate the micro-tests from the live CPU brain: the AI now really
	# expands and fights, and its roaming units used to intercept test
	# walkers spawned at fixed coordinates. ai-test re-enables its brain
	# for the sustained simulation; tactics-test drives _think() by hand.
	for c in ctx.get_children():
		if c is CpuAi:
			c.set_process(false)

	if "--ui-test" in args:
			# the original-art UI kit: gold menu font, GOG button plates, planets
			var fails: PackedStringArray = []
			var menu_font := UiTheme.font()
			if menu_font == null:
				fails.append("menu font missing")
			else:
				for c in "ContinueCampaignSkirmishSettings0123456789:-!%VICTORY":
					if not menu_font.has_char(c.unicode_at(0)):
						fails.append("font char %s" % c)
			var plate := UiTheme.button("normal")
			if plate == null or plate.texture == null \
					or plate.texture.get_size() != Vector2(32, 32):
				fails.append("button plate")
			for kind in ["normal", "hover", "pressed"]:
				if UiTheme.button(kind) == UiTheme.button("normal") and kind != "normal":
					fails.append("plate state %s not distinct" % kind)
			for planet in ["artic", "city", "desert", "jungle", "volcan"]:
				if not ResourceLoader.exists(
						"res://assets/z/ui/planets/%s.png" % planet):
					fails.append("planet %s" % planet)
			for art in ["res://assets/z/ui/Buttons.png",
					"res://assets/z/ui/PMHSprites.png",
					"res://assets/z/ui/plaques/options.png",
					"res://assets/z/ui/plaques/audio.png"]:
				if not ResourceLoader.exists(art):
					fails.append(art)
			# skirmish plumbing: real player counts (the JSON player_count
			# field lies — always 2), previews rendered from each map's own
			# terrain art, and the GameSettings round-trip
			for spec in [["p02_bb_orig01", 2], ["p03_bb_p03m01", 3],
					["p04_bb_p04m01", 4], ["p08_bb_p08m01", 8]]:
				if not MapCatalog.entries().any(
						func(e): return String(e.name) == String(spec[0])):
					continue  # map not shipped in this build
				var pm: Dictionary = MapCatalog.meta(String(spec[0]))
				if pm.players != spec[1]:
					fails.append("%s players %d want %d" % [spec[0], pm.players, spec[1]])
			var terrains_seen := {}
			for e in MapCatalog.entries():
				var m2: Dictionary = MapCatalog.meta(String(e.name))
				if terrains_seen.has(m2.terrain) or e.sandbox:
					continue
				terrains_seen[m2.terrain] = true
				var tex := MapPreview.texture(String(e.name))
				if tex == null or tex.get_width() != m2.width or tex.get_height() != m2.height:
					fails.append("preview %s" % String(e.name))
			if terrains_seen.size() < 5:
				fails.append("previews covered %d/5 terrains" % terrains_seen.size())
			# THE IN-GAME HUD FRAME. Every piece here shipped in the pack
			# and had no consumer until the frame was built, so a missing
			# conversion used to show up as an invisible ResourceLoader
			# false branch — an empty slot in the sidebar and no error.
			for piece in ["main_hud_side_red", "main_hud_bottom_left",
					"main_hud_bottom_center", "main_hud_bottom_right",
					"side_filler", "bottom_filler", "grenade",
					"health_full", "health_lost", "health_empty"]:
				if not ResourceLoader.exists(
						"res://assets/z/ui/hud/%s.png" % piece):
					fails.append("hud piece %s" % piece)
			for letter in ["a", "t", "d", "z", "r", "v", "b", "g", "menu"]:
				for state in ["active", "inactive", "pressed"]:
					if not ResourceLoader.exists(
							"res://assets/z/ui/hud/btn_%s_%s.png" % [letter, state]):
						fails.append("hud button %s_%s" % [letter, state])
			# the 74px health strips ARE the original's HP scale — one
			# pixel per hit point, so the width is load-bearing
			for strip in ["health_full", "health_lost", "health_empty"]:
				var tex: Texture2D = load("res://assets/z/ui/hud/%s.png" % strip)
				if tex != null and tex.get_width() != int(HudFrame.HEALTH.size.x):
					fails.append("%s is %dpx, frame slot is %d"
						% [strip, tex.get_width(), int(HudFrame.HEALTH.size.x)])
			# equipment art + ANIMATED PORTRAITS for every robot, per team
			for type_name in ["grunt", "psycho", "sniper", "tough", "pyro", "laser"]:
				if not ResourceLoader.exists(
						"res://assets/z/ui/hud/weapon_%s.png" % type_name):
					fails.append("equipment art %s" % type_name)
				for tn in ["red", "blue", "green", "yellow"]:
					var dir := "res://assets/z/ui/portraits/%s_%s" % [type_name, tn]
					for frame_name in ["base.png", "hurt.png", "blink_n00.png",
							"talk_n00.png"]:
						if not ResourceLoader.exists("%s/%s" % [dir, frame_name]):
							fails.append("portrait %s_%s/%s" % [type_name, tn, frame_name])
			# the live frame: its widgets exist and the world view really
			# is inset by the chrome (the camera and the click handler
			# both trust view_rect)
			var frame: HudFrame = ctx.get_node_or_null("CanvasLayer/HUD/HudFrame")
			if frame == null:
				fails.append("HudFrame missing from the match scene")
			else:
				var vp: Vector2 = Vector2(ctx.get_viewport().get_visible_rect().size)
				var view: Rect2 = HudFrame.view_rect()
				if absf(view.size.x - (vp.x - HudFrame.SIDE_W)) > 0.5 \
						or absf(view.size.y - (vp.y - HudFrame.BAR_H)) > 0.5:
					fails.append("view_rect %s does not exclude the chrome" % view)
				if view.has_point(Vector2(vp.x - 4.0, vp.y * 0.5)):
					fails.append("view_rect includes the sidebar")
				if view.has_point(Vector2(vp.x * 0.25, vp.y - 2.0)):
					fails.append("view_rect includes the bottom bar")
			# the build menu's own chrome (the window, its Ok/Cancel pair
			# and the status plates the time readout sits beside)
			for art in ["base_image", "ok_button", "cancel_button",
					"building_label", "buildingless_label", "paused_label",
					"object_button"]:
				if not ResourceLoader.exists(
						"res://assets/z/ui/production/%s.png" % art):
					fails.append("build menu art %s" % art)
			# the release's own TUTORIAL pages, and the viewer that shows
			# them (they shipped unconverted and unreachable)
			var pages: Array = TutorialScreen.load_pages()
			if pages.size() != 7:
				fails.append("tutorial pages converted: %d of 7" % pages.size())
			var tut: TutorialScreen = (load("res://scenes/tutorial.tscn")
				as PackedScene).instantiate()
			ctx.add_child(tut)
			await Engine.get_main_loop().process_frame
			if tut.turn(-1) != 0:
				fails.append("tutorial paged back off the first page")
			if tut.turn(1) != 1:
				fails.append("tutorial did not advance")
			for i in 20:
				tut.turn(1)
			if tut.page != pages.size() - 1:
				fails.append("tutorial ran past the last page (%d of %d)"
					% [tut.page, pages.size()])
			tut.queue_free()
			var g_diff := GameSettings.difficulty
			var g_speed := GameSettings.speed_index
			var g_idle := GameSettings.auto_idle
			var g_music := GameSettings.music_volume
			var g_sfx := GameSettings.sfx_volume
			GameSettings.difficulty = 2
			GameSettings.speed_index = 0
			GameSettings.auto_idle = false
			GameSettings.music_volume = 0.25
			GameSettings.sfx_volume = 0.5
			GameSettings.save()
			GameSettings.difficulty = 0
			GameSettings.speed_index = 4
			GameSettings.auto_idle = true
			GameSettings.music_volume = 1.0
			GameSettings.sfx_volume = 1.0
			GameSettings.read()
			if GameSettings.difficulty != 2 or GameSettings.speed_index != 0 \
					or GameSettings.auto_idle != false \
					or absf(GameSettings.music_volume - 0.25) > 0.001 \
					or absf(GameSettings.sfx_volume - 0.5) > 0.001:
				fails.append("settings round-trip")
			if absf(GameSettings.game_speed() - 0.5) > 0.001:
				fails.append("game_speed lookup")
			GameSettings.difficulty = g_diff
			GameSettings.speed_index = g_speed
			GameSettings.auto_idle = g_idle
			GameSettings.music_volume = g_music
			GameSettings.sfx_volume = g_sfx
			GameSettings.apply()
			GameSettings.save()
			# production panel wiring regression: enqueuing WITHOUT
			# reselecting must refresh the window's readouts (they used
			# to miss pure enqueues until the player reselected)
			var panel: ProductionPanel = ctx.get_node_or_null(
				"CanvasLayer/HUD/ProductionPanel")
			var any_facility = null
			for b2 in ctx.get_tree().get_nodes_in_group(Groups.FACILITIES):
				if b2 is Building2D and b2.alive \
						and b2.owner_team == MatchState.current.player_team:
					any_facility = b2
					break
			if panel == null or any_facility == null:
				fails.append("panel/facility missing for queue-wiring check")
			else:
				SelectionManager.current.clear_selection()
				SelectionManager.current.toggle_select(any_facility, false)
				await tree.process_frame
				MatchState.current.set_money(MatchState.current.player_team, 500)
				var before: String = panel._time.text
				any_facility.queue_unit("robot:grunt", true)
				await tree.process_frame
				await tree.process_frame
				var after: String = panel._time.text
				if after == before or after == "":
					fails.append("panel readout did not refresh on enqueue (reselect bug)")
				if panel._object.texture == null:
					fails.append("panel object window empty while building")
				SelectionManager.current.clear_selection()
			# SIGNAL ARITY AUDIT. A 0-arg method connected to a 1-arg
			# signal is not a parse error — it throws
			# "Method expected 0 argument(s), but called with 1" at EMIT
			# time and the handler simply never runs. That is how the
			# minimap's ownership overlay silently stopped refreshing on
			# every zone capture. Reflective, so it covers all present
			# and future HUD wiring instead of the one case found.
			for emitter in [MatchState.current, SelectionManager.current,
					UnitRegistry.current, GameState]:
				if emitter == null:
					continue
				for sig in emitter.get_signal_list():
					var want: int = (sig["args"] as Array).size()
					for conn in emitter.get_signal_connection_list(String(sig["name"])):
						var cb: Callable = conn["callable"]
						var got: int = cb.get_argument_count()
						if got != want:
							fails.append("%s.%s -> %s takes %d args, signal sends %d"
								% [emitter.get_class(), sig["name"], cb, got, want])
			# ASSERTED (this block used to only print its problem list)
			var uir := TestRig.start("UI")
			uir.check(fails.is_empty(), ", ".join(fails))
			uir.finish("original-art kit + signal arity")
	if "--mp-test" in args:
			# multiplayer milestone 1: LAN discovery over loopback, and the
			# full room protocol over a REAL ENet loopback — a second Net
			# script instance under its own SceneMultiplayer is a genuine
			# client (same RPC node paths; the custom api is polled by hand).
			# A PRIVATE port + loopback-only assertions keep this stable
			# while real games run on the LAN.
			var fails: PackedStringArray = []
			var test_port := 45678
			var host_disc := LanDiscovery.new(PackedStringArray(["127.0.0.1"]))
			var browse_disc := LanDiscovery.new()
			if not browse_disc.listen():
				fails.append("discovery bind")
			else:
				var my_key := "127.0.0.1:%d" % test_port
				host_disc.start_broadcast(
					{"name": "TEST GAME", "map": "P02", "cur": 1, "max": 2}, test_port)
				host_disc.poll()
				for i in 5:
					await tree.process_frame
				browse_disc.poll()
				var g: Dictionary = browse_disc.game_info(my_key)
				if g.is_empty():
					fails.append("loopback announce not found")
				elif str(g.get("name", "")) != "TEST GAME" \
						or int(g.get("port", 0)) != test_port:
					fails.append("discovery payload %s" % g)
				host_disc.stop_broadcast()
				browse_disc.ttl = 1  # deterministic expiry, no wall-clock wait
				await tree.process_frame
				await tree.process_frame
				browse_disc.poll()
				if not browse_disc.game_info(my_key).is_empty():
					fails.append("discovery ttl expiry")
				browse_disc.stop_listen()
			if not Net.host_game("TEST ROOM", test_port, false):
				fails.append("host_game: %s" % Net.last_error)
			else:
				var map_path := str(Net.room.get("map", ""))
				if map_path == "":
					fails.append("no default map")
				var slot_teams: Array = []
				for slot in Net.room.get("slots", []):
					slot_teams.append(int(slot.get("team", 0)))
				if slot_teams != MapCatalog.fort_teams(map_path.get_file().get_basename()):
					fails.append("slots %s != map fort teams" % [slot_teams])
				var dummy := Node.new()
				dummy.name = "MpTestClient"
				tree.root.add_child(dummy)
				var client_api := SceneMultiplayer.new()
				tree.set_multiplayer(client_api, dummy.get_path())
				var client: Node = load("res://scripts/net/net.gd").new()
				client.name = "Net"
				dummy.add_child(client)
				if not client.join_game("127.0.0.1", test_port):
					fails.append("client join start")
				for i in 60:
					client_api.poll()
					await tree.process_frame
					if not client.room.is_empty():
						break
				if client.room.is_empty():
					fails.append("client never synced a room")
				else:
					var cid: int = client.my_id()
					if not Net.room.players.has(cid):
						fails.append("hello did not register the client")
					var open_team := 0
					for slot in client.room.get("slots", []):
						if str(slot.get("controller", "")) == "open":
							open_team = int(slot.get("team", 0))
							break
					if open_team == 0:
						fails.append("no open seat to claim")
					else:
						client.request_seat(open_team)
					client.set_ready(true)
					client.send_chat("HELLO ROOM")
					for i in 40:
						client_api.poll()
						await tree.process_frame
						var seated: Dictionary = Net.room.players.get(cid, {})
						if int(seated.get("team", 0)) == open_team \
								and bool(seated.get("ready", false)) \
								and client.room.chat.size() >= 2:
							break
					var seated2: Dictionary = Net.room.players.get(cid, {})
					if int(seated2.get("team", 0)) != open_team \
							or not bool(seated2.get("ready", false)):
						fails.append("client seat/ready did not stick")
					if str(seated2.get("name", "")) \
							!= GameSettings.player_name.to_upper().substr(0, 14):
						fails.append("client name %s" % seated2.get("name", ""))
					var heard := false
					for e in client.room.get("chat", []):
						if String(e.get("text", "")) == "HELLO ROOM":
							heard = true
					if not heard:
						fails.append("chat round trip")
					if not Net.host_start():
						fails.append("host_start blocked: %s" % Net.start_blocker())
					else:
						if not Net.in_match or Net.match_team <= 0:
							fails.append("host match_team %d" % Net.match_team)
						for i in 40:
							client_api.poll()
							await tree.process_frame
							if client.in_match:
								break
						if not client.in_match:
							fails.append("client never received the start")
						elif client.match_team != open_team:
							fails.append("client match_team %d want %d" % [
								client.match_team, open_team])
						if not bool(client.room.get("started", false)):
							fails.append("room.started flag missing")
				var lost := [false]
				client.host_lost.connect(func(_reason: String) -> void:
					lost[0] = true)
				Net.leave()
				for i in 40:
					client_api.poll()
					await tree.process_frame
					if lost[0]:
						break
				if not lost[0]:
					fails.append("host_lost not delivered")
				client.leave()
				dummy.queue_free()
				Net.leave()
			var mp_rig := TestRig.start("MP")
			for problem in fails:
				mp_rig.check(false, String(problem))
			mp_rig.finish()
	if "--mpmatch-test" in args:
		# multiplayer milestone 2: IN-MATCH intent replication over a real
		# ENet loopback — a client's order/rally/queue intents reach the
		# host, get validated against the sender's seat and applied through
		# the single intakes; an unowned team is dropped.
		var mm := TestRig.start("MPMATCH")
		var test_port := 45679
		if not Net.host_game("INTENT ROOM", test_port, false):
			mm.check(false, "host_game: %s" % Net.last_error)
		else:
			await tree.process_frame  # root is busy during _ready — dummy.add_child needs the tree settled
			var dummy := Node.new()
			dummy.name = "MpMatchClient"
			tree.root.add_child(dummy)
			var client_api := SceneMultiplayer.new()
			tree.set_multiplayer(client_api, dummy.get_path())
			var client: Node = load("res://scripts/net/net.gd").new()
			client.name = "Net"
			dummy.add_child(client)
			mm.check(client.join_game("127.0.0.1", test_port), "client join start")
			for i in 60:
				client_api.poll()
				await tree.process_frame
				if not client.room.is_empty():
					break
			var cid: int = client.my_id()
			var open_team := 0
			for slot in client.room.get("slots", []):
				if str(slot.get("controller", "")) == "open":
					open_team = int(slot.get("team", 0))
					break
			mm.check(open_team != 0, "no open seat")
			if open_team != 0:
				client.request_seat(open_team)
				client.set_ready(true)
				for i in 40:
					client_api.poll()
					await tree.process_frame
					if int(Net.room.players.get(cid, {}).get("team", 0)) == open_team:
						break
				mm.check(Net.host_start(), "host_start blocked: %s" % Net.start_blocker())
				for i in 40:
					client_api.poll()
					await tree.process_frame
					if client.in_match:
						break
				mm.check(client.in_match, "client never received the start")
				if client.in_match:
					# ORDER round trip: the client's robot must move
					var robot: Unit2D = Spawner.spawn(ctx, "robot", "grunt",
						client.match_team, Vector2(600, 480))
					client.relay_order(robot, Order.move(Vector2(760, 480)))
					var moved := false
					for i in 60:
						client_api.poll()
						await tree.process_frame
						if robot.has_move_target():
							moved = true
							break
					mm.check(moved, "order intent never applied")
					# VALIDATION: a team the sender does not own is dropped
					var other: Unit2D = Spawner.spawn(ctx, "robot", "grunt",
						client.match_team % 8 + 1, Vector2(600, 500))
					Net._validate_intent(1, {"kind": "order", "team": 999,
						"unit": other.net_id, "otype": 0, "x": 900.0, "y": 500.0,
						"run": false, "target": 0})
					for i in 10:
						await tree.process_frame
					mm.check(not other.has_move_target(),
						"unowned team intent was applied")
					# RALLY round trip on the client's own fort
					var fort: FortBuilding = null
					for b in tree.get_nodes_in_group(Groups.BUILDINGS):
						if b is FortBuilding and b.team == client.match_team:
							fort = b
							break
					if fort == null:
						mm.check(false, "no fort for team %d" % client.match_team)
					else:
						var rally := fort.visual_center() + Vector2(60, 0)
						client.relay_rally(fort, rally)
						var rallied := false
						for i in 40:
							client_api.poll()
							await tree.process_frame
							if fort.rally_point == rally:
								rallied = true
								break
						mm.check(rallied, "rally intent never applied")
					# QUEUE round trip (funded)
					if fort != null:
						MatchState.current.set_money(client.match_team, 500)
						fort.queue.cancel_at(0)  # drop anything queued earlier
						client.relay_queue(fort, "robot:grunt")
						var queued := false
						for i in 40:
							client_api.poll()
							await tree.process_frame
							if fort.queue_items().size() >= 1:
								queued = true
								break
						mm.check(queued, "queue intent never applied")
				# STATE snapshot: host pushes economy; zone ownership
				# converges through the save-contract shape
				MatchState.current.set_money(client.match_team, 777)
				var zone: Zone = MatchState.current.zones[0]
				var snap := MatchState.current.economy_snapshot()
				snap.zones[0]["team"] = 1 if zone.owner_team != 1 else 2
				Net._apply_state(snap)
				for i in 10:
					await tree.process_frame
				mm.check(int(MatchState.current.money.get(client.match_team, 0)) >= 777,
					"snapshot money did not apply")
				mm.check(MatchState.current.zones[0].owner_team == int(snap.zones[0]["team"]),
					"snapshot zone owner did not apply")
				# FULL-ENTITY RESYNC: peers run their own float physics, so
				# the host corrects the roster by net id. Three cases, all
				# driven through the real apply path:
				#   drifted  -> snapped back (only past SNAP_DISTANCE)
				#   missing  -> spawned with the HOST's net id
				#   stale    -> killed (it died on the host)
				var drifter: Unit2D = Spawner.spawn(ctx, "robot", "grunt",
					client.match_team, Vector2(700, 700))
				var doomed: Unit2D = Spawner.spawn(ctx, "robot", "grunt",
					client.match_team, Vector2(740, 700))
				var truth := MatchRelay.entity_snapshot()
				mm.check(truth.units.size() > 0, "entity snapshot is empty")
				# the host's picture: drifter is elsewhere, doomed is gone,
				# and one unit exists that this peer has never seen
				var ghost_id := 0
				for u3 in UnitRegistry.current.all_units():
					ghost_id = maxi(ghost_id, u3.net_id)
				ghost_id += 50
				var authority := {"units": [], "buildings": truth.buildings}
				for entry in truth.units:
					if int(entry.get("net", 0)) == doomed.net_id:
						continue  # died on the host
					if int(entry.get("net", 0)) == drifter.net_id:
						entry = entry.duplicate()
						entry["x"] = 700.0 + MatchRelay.SNAP_DISTANCE * 4.0
					authority.units.append(entry)
				authority.units.append({"net": ghost_id, "kind": "robot",
					"type": "grunt", "team": client.match_team,
					"x": 660.0, "y": 760.0, "hp": 50, "dir": 0, "grenades": 0})
				var far := drifter.global_position.x + MatchRelay.SNAP_DISTANCE * 4.0
				var report: Dictionary = MatchRelay.apply_entities(authority)
				mm.check(absf(drifter.global_position.x - far) < 1.0,
					"drifted unit not corrected (at %s)" % drifter.global_position)
				mm.check(not doomed.alive, "unit missing from the host survived")
				mm.check(UnitRegistry.current.by_net_id(ghost_id) != null,
					"host-only unit was not spawned on the peer")
				mm.check(int(report.get("buildings", 0)) > 0,
					"no buildings reconciled")
				# and a NEW spawn cannot collide with an adopted id
				var later: Unit2D = Spawner.spawn(ctx, "robot", "grunt",
					client.match_team, Vector2(680, 780))
				mm.check(later.net_id > ghost_id,
					"net id %d reused after adopting %d" % [later.net_id, ghost_id])
				# LATE JOIN: the host hands a mid-match peer the map plus a
				# save-contract snapshot, and seats it on an open team
				var joiner := 4242
				Net.late_join(joiner)
				mm.check(Net.room.players.has(joiner), "late joiner not seated")
				var snapshot: Dictionary = SaveSystem.capture_save()
				mm.check(not snapshot.get("units", []).is_empty(),
					"late-join snapshot carries no units")
				mm.check(int(snapshot.units[0].get("net", 0)) > 0,
					"late-join snapshot units carry no net id")
				Net.room.players.erase(joiner)
				Net.leave()
				client.leave()
		mm.finish()
	if "--capture-test" in args:
		var u: Unit2D = null
		for unit in tree.get_nodes_in_group(Groups.UNITS):
			if unit.team == MatchState.current.player_team:
				u = unit
				break
		var cap_rig := TestRig.start("CAPTURE")
		cap_rig.check(u != null, "no player unit on the map")
		var z: Node2D = MatchState.current.zones[0]
		u.position = z.position + z.world_rect().get_center()
		var money_at_start := MatchState.current.player_money()
		for i in 30:
			z._process(0.1)
			MatchState.current._process(1.0)
		cap_rig.check(z.owner_team == MatchState.current.player_team,
			"zone never flipped to the player (owner %d after 3s of presence)"
			% z.owner_team)
		cap_rig.check(MatchState.current.player_money() > money_at_start,
			"captured territory paid nothing (%d -> %d)"
			% [money_at_start, MatchState.current.player_money()])
		# a zone with a LIVE enemy fort never flips — the fort is the
		# win objective, its garrison holds the ground
		var enemy_fort: Building2D = null
		for b in tree.get_nodes_in_group(Groups.BUILDINGS):
			if b is FortBuilding and b.alive \
					and b.team != 0 and b.team != MatchState.current.player_team:
				enemy_fort = b
				break
		var fort_holds := true
		if enemy_fort != null:
			var held: Node2D = null
			for zh in MatchState.current.zones:
				if enemy_fort.art_world_rect().intersection(
						zh.world_rect()).get_area() > 0:
					held = zh
					break
			if held != null and held.owner_team == enemy_fort.team:
				u.position = held.world_rect().get_center()
				for ci in 30:
					held._process(0.1)
				fort_holds = held.owner_team == enemy_fort.team
		cap_rig.check(fort_holds,
			"a zone with a LIVE enemy fort flipped on presence")
		# TAKING A SECTOR TAKES THE UNIT ON ITS LINE. Timing the assault
		# to land just before a factory's clock runs out is one of the
		# original's real tactical hooks; we used to scrap the whole
		# queue on capture, which made the timing worth nothing.
		var prod: Building2D = null
		for b in tree.get_nodes_in_group(Groups.FACILITIES):
			if b is Building2D and b.alive and b.produces_anything() \
					and b.owner_team != 0:
				prod = b
				break
		if prod == null:
			cap_rig.check(true, "")  # no producer on this map to test with
		else:
			var loser: int = prod.owner_team
			prod.queue.clear()
			prod.queue_unit("robot:grunt", true)
			prod.queue_unit("robot:grunt", true)
			prod.queue.elapsed = 12.0
			var queued_before: int = prod.queue_items().size()
			prod.producer.scrap_queue()
			cap_rig.check(prod.queue_items().size() == 1,
				"capture left %d queued, want just the item on the line"
				% prod.queue_items().size())
			cap_rig.check(absf(prod.queue.elapsed - 12.0) < 0.01,
				"capture reset the build clock to %.1f, want the 12.0s already served"
				% prod.queue.elapsed)
			cap_rig.check(queued_before == 2 and loser != 0, "")
		cap_rig.finish()
	if "--combat-test" in args:
		var a: Unit2D = load("res://scenes/unit.tscn").instantiate()
		a.unit_name = "grunt"
		a.team = 1
		a.position = Vector2(400, 400)
		ctx.add_child(a)
		var b: Unit2D = load("res://scenes/unit.tscn").instantiate()
		b.unit_name = "grunt"
		b.team = 2
		b.position = Vector2(430, 400)
		ctx.add_child(b)
		var combat_rig := TestRig.start("COMBAT")
		var hp_a := a.hp
		var hp_b := b.hp
		for i in 400:
			a._process(0.05)
			b._process(0.05)
		combat_rig.check(a.hp < hp_a and b.hp < hp_b,
			"20s in weapon range and nobody was hit (a %d->%d, b %d->%d)"
			% [hp_a, a.hp, hp_b, b.hp])
		combat_rig.check(a.alive and b.alive,
			"a grunt duel ended in 20s (a alive=%s b alive=%s) — TTK too fast"
			% [a.alive, b.alive])
		combat_rig.finish("hp %d/%d" % [a.hp, b.hp])
	if "--factory-test" in args:
		TestLevers.fast_build = true  # real build times are 72-373s
		var f := RobotFactory.new()
		var z2: Node2D = MatchState.current.zones[1]
		f.position = z2.position + z2.world_rect().get_center() - Vector2(24, 24)
		ctx.add_child(f)
		z2.owner_team = MatchState.current.player_team
		# pretend the factory was already ours — otherwise the first
		# _process treats the zone capture as new and scraps the queue
		f.owner_team = MatchState.current.player_team
		f.team = MatchState.current.player_team
		var before := tree.get_nodes_in_group(Groups.UNITS).size()
		var money_before := MatchState.current.player_money()
		MatchState.current.set_money(MatchState.current.player_team, 500)
		for i in 3:
			f.queue_unit("robot:grunt")
		for i in 30:
			f._process(0.5)
		# a destroyed factory is a RUIN: nothing crawls out of the
		# rubble (the alive-guard in _process is load-bearing)
		var units_at_death := tree.get_nodes_in_group(Groups.UNITS).size()
		f.take_damage(f.hp + 9999)
		for fi in 20:
			f._process(0.5)
		var ruin_spawned := tree.get_nodes_in_group(Groups.UNITS).size() - units_at_death
		var fac_rig := TestRig.start("FACTORY")
		var after := tree.get_nodes_in_group(Groups.UNITS).size()
		fac_rig.check(after > before,
			"factory produced nothing (units %d -> %d)" % [before, after])
		fac_rig.check(f.queue.items.is_empty(),
			"queue never drained (%d left)" % f.queue.items.size())
		fac_rig.check(MatchState.current.player_money() < 500,
			"production was free (money still %d)" % MatchState.current.player_money())
		fac_rig.check(ruin_spawned == 0,
			"%d units crawled out of a DESTROYED factory" % ruin_spawned)
		fac_rig.finish("%d units, %d money" % [after, MatchState.current.player_money()])
	if "--ai-test" in args:
		TestLevers.fast_build = true  # real build times are 72-373s
		var ai := ctx.get_node_or_null("CpuAi_T2")
		if ai:
			var moved := 0
			var roster := {"robots": 0, "idle": 0, "vehicles": 0, "facilities": 0}
			for u2 in tree.get_nodes_in_group(Groups.UNITS):
				if u2 is Node2D and u2.team == 2 and u2.has_move_target():
					moved += 1
			for u2 in UnitRegistry.current.world_units():
				if u2 is Unit2D and u2.alive and not u2.carried and u2.team == 2:
					if u2.kind == "robot":
						roster.robots += 1
						if u2.is_idle():
							roster.idle += 1
					elif u2.kind == "vehicle":
						roster.vehicles += 1
			for f in tree.get_nodes_in_group(Groups.FACILITIES):
				if f.team == 2:
					roster.facilities += 1
			print("AI ROSTER: robots=%d idle=%d vehicles=%d facilities=%d money=%d zones_owned=%d" % [
				roster.robots, roster.idle, roster.vehicles, roster.facilities,
				int(MatchState.current.money.get(2, 0)),
				MatchState.current.zones.filter(func(z): return z.owner_team == 2).size()])
			ai._think()
			var moved_after := 0
			for u2 in tree.get_nodes_in_group(Groups.UNITS):
				if u2 is Node2D and u2.team == 2 and u2.has_move_target():
					moved_after += 1
			print("AI: enemy robots with orders %d -> %d" % [moved, moved_after])
			# sustained observation: the full loop (income -> production ->
			# expansion -> push) must all come alive on its own
			ai.set_process(true)  # back to live thinking (isolated above)
			var ai_rig := TestRig.start("AI")
			ai_rig.check(moved_after >= moved,
				"a _think() cycle took orders AWAY (%d -> %d)" % [moved, moved_after])
			for step in 6:
				await ctx.get_tree().create_timer(20.0).timeout
				var r2 := 0
				var v2 := 0
				var q2 := 0
				var unmanned2 := 0
				for u3 in UnitRegistry.current.world_units():
					if u3 is Unit2D and u3.alive and u3.team == 2:
						if u3.kind == "robot":
							r2 += 1
						elif u3 is Vehicle2D and u3.manned:
							v2 += 1
						elif u3 is Vehicle2D:
							unmanned2 += 1
				var f2 := 0
				for b2 in tree.get_nodes_in_group(Groups.FACILITIES):
					if b2 is Building2D and b2.alive and b2.team == 2:
						f2 += 1
						q2 += b2.queue.items.size()
				print("AI SIM t+%ds: robots=%d vehicles=%d unmanned=%d zones=%d money=%d facilities=%d queued=%d attacking=%s" % [
					(step + 1) * 20, r2, v2, unmanned2,
					MatchState.current.zones.filter(func(z): return z.owner_team == 2).size(),
					int(MatchState.current.money.get(2, 0)), f2, q2, ai._attack_mode])
				if step == 5:
					# after two live minutes the brain must still be
					# PLAYING: an army on the field, facilities standing
					# and territory held (the whole loop, unsupervised)
					ai_rig.check(r2 + v2 > 0,
						"the AI has no units left after 2 minutes")
					ai_rig.check(f2 > 0, "the AI holds no facilities")
					ai_rig.check(MatchState.current.zones.filter(
							func(z): return z.owner_team == 2).size() > 0,
						"the AI holds no territory")
			ai_rig.finish()
			ctx.get_tree().quit()
	if "--path-test" in args:
		PathTests.walk_a_pair(ctx, TestRig.start("PATH"))
		PathTests.walkers_arrive(ctx, TestRig.start("ARRIVE"))
	if "--fortkill-test" in args:
		# forts must actually die: small arms scale with the target
		# (original zsettings fractions — flat integers made a laser need
		# 23 minutes) and cranes no longer out-heal any assault
		var fk := TestRig.start("FORTKILL")
		var fk_fort := FortBuilding.new()
		fk_fort.setup(0, 2, "desert")
		fk_fort.position = Vector2(650, 700)
		ctx.add_child(fk_fort)
		await ctx.get_tree().process_frame
		# crane contract: repair_by is a no-op on forts (used to heal
		# 1,750 HP/s with an AI crane parked on the pad)
		var hp_before: int = fk_fort.hp
		fk_fort.repair_by(700)
		fk.check(fk_fort.hp == hp_before, "crane repair healed the fort")
		# damage TRUTH audit: building HP and the small-arms-vs-building
		# fractions must match the zsettings reference table (docs/
		# RESEARCH.md — the x3.33 rescale once skipped small arms and
		# forts became unkillable)
		fk.check(fk_fort.max_hp == 33333,
			"fort HP %d want 33333 (10000/240 zsettings, x0.08... x3.33)" % fk_fort.max_hp)
		var shop: Building2D = ContentDB.building_def(3).behaviour.new()
		shop.setup(3, 1, "desert")
		fk.check(shop.max_hp == 6667,
			"building HP %d want 6667 (2000/240 zsettings)" % shop.max_hp)
		for spec in [["grunt", 0.0011], ["psycho", 0.0026], ["sniper", 0.007],
				["pyro", 0.0105], ["laser", 0.0178], ["jeep", 0.0027]]:
			var def := ContentDB.def_for("robot" if spec[0] != "jeep" else "vehicle",
				String(spec[0]))
			fk.check(is_equal_approx(def.building_frac, float(spec[1])),
				"%s building_frac %.4f want %.4f" % [spec[0], def.building_frac, spec[1]])
		# small-arms TTK: a laser (0.0178 of max HP per hit, 0.7 chance,
		# ~0.4s cooldown) burns a full fort in original-order minutes,
		# not hours
		var gunner: Unit2D = Spawner.spawn(ctx, "robot", "laser", 1,
			fk_fort.visual_center() + Vector2(0, 150)) as Unit2D
		gunner.attack_move = true
		gunner.move_to(fk_fort.visual_center() + Vector2(0, 110))
		var ticks := 0
		for i in 3000:  # 150 simulated seconds
			gunner._process(0.05)
			gunner._physics_process(0.05)
			ticks = i
			if not fk_fort.alive:
				break
		fk.check(not fk_fort.alive, "laser never burned the fort down (hp=%d/%d after %ds)"
			% [fk_fort.hp, fk_fort.max_hp, int(ticks * 0.05)])
		if gunner:
			gunner.queue_free()
		fk.finish()
	if "--art-test" in args:
		ArtTests.run(ctx, TestRig.start("ART"))
	if "--terrain-test" in args:
		TerrainTests.run(ctx, TestRig.start("TERRAIN"))
	if "--retail-test" in args:
		# THE ORIGINAL CAMPAIGN, converted from the retail data
		# (tools/gog/level_to_json.py). Every level must load and be
		# PLAYABLE: two fort halves on opposing teams, a territory grid,
		# tiles inside the sheet, units on walkable ground, and — since
		# the release ships no `preset*.wal` starting armies — a squad
		# handed to each fort team so the first lost robot cannot end the
		# mission (MapLoader._grant_starting_squads).
		var rt := TestRig.start("RETAIL")
		var levels := PackedStringArray()
		for entry in MapCatalog.entries():
			if String(entry.name).begins_with(MapCatalog.CAMPAIGN_PREFIX):
				levels.append(String(entry.name))
		rt.check(levels.size() == 20,
			"%d retail campaign levels installed, want 20" % levels.size())
		for name in levels:
			var path := "res://assets/maps/%s.json" % name
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not (parsed is Dictionary):
				rt.check(false, "%s: unreadable" % name)
				continue
			var data: Dictionary = parsed
			var w := int(data.width)
			var h := int(data.height)
			rt.check(w > 0 and h > 0 and data.tiles.size() == w * h,
				"%s: %dx%d with %d tiles" % [name, w, h, data.tiles.size()])
			var worst := 0
			for t in data.tiles:
				worst = maxi(worst, int(t))
			rt.check(worst < 480, "%s: tile index %d outside the sheet" % [name, worst])
			rt.check(data.zones.size() > 0, "%s: no territory zones" % name)
			var fort_teams: Array = MapCatalog.fort_team_ids(data)
			rt.check(fort_teams.size() == 2,
				"%s: %d fort teams, want 2" % [name, fort_teams.size()])
			var misplaced := 0
			for o in data.objects:
				var kind := String(o.type)
				if kind != "robot" and kind != "vehicle" and kind != "cannon":
					continue
				var i := int(o.y) * w + int(o.x)
				if i < 0 or i >= data.tiles.size():
					continue
				if int(data.water[i]) != 0 or int(data.passable[i]) == 0:
					misplaced += 1
			rt.check(misplaced == 0,
				"%s: %d units start in water or in a wall" % [name, misplaced])
		# the loaded map in front of us: if it is a retail level, both
		# fort teams must have a crew (the preset stopgap)
		var current := String(GameState.current_map)
		if current.get_file().begins_with(MapCatalog.CAMPAIGN_PREFIX):
			for b in BuildingRegistry.all():
				if b is Building2D and b.is_fort and b.team != 0:
					rt.check(not UnitRegistry.current.alive_of_team(b.team).is_empty(),
						"team %d holds a fort with no units at all" % b.team)
		rt.finish("%d levels" % levels.size())
	if "--veteran-test" in args:
		# VETERANCY: kills buy rank, rank buys damage and accuracy, the
		# killing shot is credited to whoever fired it, and a veteran
		# survives a save (there was no rank or XP field anywhere)
		var vt := TestRig.start("VETERAN")
		var steps: Array = ContentDB.rules.veteran_kill_steps
		vt.check(steps.size() > 0, "no veteran kill steps configured")
		var vet: Unit2D = Spawner.spawn(ctx, "robot", "grunt",
			MatchState.current.player_team,
			NavWorld.current.find_free_spot(Vector2(820, 820), "robot")) as Unit2D
		vt.check(vet.rank() == 0, "a fresh unit starts at rank %d" % vet.rank())
		vt.check(is_equal_approx(vet.veteran_damage_scale(), 1.0),
			"a rookie already carries a damage bonus")
		for i in int(steps[steps.size() - 1]):
			vet.credit_kill()
		vt.check(vet.rank() == steps.size(),
			"%d kills bought rank %d of %d" % [vet.kills, vet.rank(), steps.size()])
		var want_scale: float = 1.0 + steps.size() * ContentDB.rules.veteran_damage_bonus
		vt.check(is_equal_approx(vet.veteran_damage_scale(), want_scale),
			"damage scale %.3f, want %.3f" % [vet.veteran_damage_scale(), want_scale])
		vt.check(is_equal_approx(vet.veteran_hit_bonus(),
				steps.size() * ContentDB.rules.veteran_hit_bonus),
			"hit bonus %.3f" % vet.veteran_hit_bonus())
		# the save contract carries the rank
		var vdict: Dictionary = vet.to_dict()
		vt.check(int(vdict.get("kills", -1)) == vet.kills,
			"kills missing from the save contract")
		var rookie: Unit2D = Spawner.spawn(ctx, "robot", "grunt",
			MatchState.current.player_team,
			NavWorld.current.find_free_spot(Vector2(860, 820), "robot")) as Unit2D
		rookie.apply_dict(vdict)
		vt.check(rookie.rank() == vet.rank(),
			"a restored veteran came back at rank %d" % rookie.rank())
		# CREDIT: the killing shot promotes the shooter, and a dead
		# shooter (a shell that outlives its gun) credits nobody
		var killer: Unit2D = Spawner.spawn(ctx, "robot", "laser", 1,
			NavWorld.current.find_free_spot(Vector2(900, 860), "robot")) as Unit2D
		var victim: Unit2D = Spawner.spawn(ctx, "robot", "grunt", 2,
			NavWorld.current.find_free_spot(Vector2(940, 860), "robot")) as Unit2D
		var kills_before := killer.kills
		victim.hp = 1
		Combat._land(victim, 9999, victim.global_position, killer.get_instance_id())
		vt.check(not victim.alive, "the victim survived a lethal hit")
		vt.check(killer.kills == kills_before + 1,
			"the killing shot credited %d kills" % (killer.kills - kills_before))
		var bystander: Unit2D = Spawner.spawn(ctx, "robot", "grunt", 2,
			NavWorld.current.find_free_spot(Vector2(980, 860), "robot")) as Unit2D
		bystander.hp = 1
		Combat._land(bystander, 9999, bystander.global_position, 0)
		vt.check(killer.kills == kills_before + 1,
			"an unattributed kill was credited anyway")
		for u in [vet, rookie, killer, victim, bystander]:
			if is_instance_valid(u):
				u.queue_free()
		vt.finish("ranks=%d" % steps.size())
	if "--group-test" in args:
		# CONTROL GROUPS: Ctrl+digit assigns, digit recalls, dead members
		# drop out on recall (there was no digit binding at all)
		var gr := TestRig.start("GROUP")
		for spec in [[KEY_1, 0], [KEY_9, 8], [KEY_0, 9], [KEY_A, -1],
				[KEY_SHIFT, -1]]:
			gr.check(ctx._group_slot(int(spec[0])) == int(spec[1]),
				"keycode %d -> slot %d want %d" % [spec[0],
					ctx._group_slot(int(spec[0])), spec[1]])
		var team: int = MatchState.current.player_team
		var squad: Array[Unit2D] = []
		var anchor := NavWorld.current.find_free_spot(Vector2(700, 700), "robot")
		for i in 3:
			var u: Unit2D = Spawner.spawn(ctx, "robot", "grunt", team,
				NavWorld.current.find_free_spot(
					anchor + Vector2(24 * i, 0), "robot")) as Unit2D
			squad.append(u)
		var sel := SelectionManager.current
		sel.clear_selection()
		for u in squad:
			sel.toggle_select(u, true)
		gr.check(sel.assign_group(0) == 3,
			"assigned %d of 3" % sel.assign_group(0))
		sel.clear_selection()
		gr.check(sel.selected.is_empty(), "selection not cleared")
		gr.check(sel.select_group(0) == 3,
			"recalled %d of 3" % sel.selected.size())
		gr.check(sel.group_center(0).distance_to(anchor) < 64.0,
			"group centre %s far from the squad at %s" % [
				sel.group_center(0), anchor])
		# a dead member must not come back
		squad[0].die()
		gr.check(sel.select_group(0) == 2,
			"recalled %d after a death, want 2" % sel.selected.size())
		# out-of-range slots are ignored, not stored
		gr.check(sel.assign_group(SelectionManager.GROUP_COUNT) == 0,
			"slot %d accepted" % SelectionManager.GROUP_COUNT)
		# assigning nothing clears the slot
		sel.clear_selection()
		sel.assign_group(0)
		gr.check(sel.select_group(0) == 0, "empty assign kept the old group")
		for u in squad:
			if is_instance_valid(u):
				u.queue_free()
		gr.finish()
	if "--parity-test" in args:
		# ONE movement engine: robot and vehicle must arrive the SAME way
		# — order cleared, state IDLE, DEFEND post armed (vehicle arrivals
		# used to skip all of that bookkeeping; the copies had drifted)
		var pr := TestRig.start("PARITY")
		var anchor := NavWorld.current.find_free_spot(Vector2(700, 520), "robot")
		for spec in [["robot", "grunt"], ["vehicle", "jeep"]]:
			var u: Unit2D = Spawner.spawn(ctx, spec[0], spec[1], 1,
				anchor, spec[0] == "vehicle") as Unit2D
			u.issue_order(Order.move_defend(
				NavWorld.current.find_free_spot(anchor + Vector2(160, 0), spec[0])))
			for i in 600:
				u._process(0.05)
				u._physics_process(0.05)
				if not u.has_move_target():
					break
			pr.check(not u.has_move_target(),
				"%s never arrived (at %s)" % [spec[1], u.global_position])
			pr.check(u.defend_post != Vector2.INF,
				"%s arrival did not arm the defend post" % spec[1])
			pr.check(u.state == Unit2D.State.IDLE,
				"%s not idle after arrival (state %d)" % [spec[1], u.state])
			pr.check(u.order == null, "%s kept a finished order" % spec[1])
			u.queue_free()
		pr.finish()
	if "--placement-test" in args:
		await PlacementTests.run(ctx, TestRig.start("PLACEMENT"))
	if "--garrison-test" in args:
		await GarrisonTests.run(ctx, TestRig.start("GARRISON"))
	if "--rally-test" in args:
		# unmanned hardware must not take rally orders — the AI rallies
		# every facility at an enemy fort, and empty vehicles used to
		# drive there themselves; a crewed vehicle honors orders again
		TestLevers.fast_build = true
		GameSettings.auto_idle = false  # deterministic: no ambient grabs
		var rr := TestRig.start("RALLY")
		var vf := VehicleFactory.new()
		var vz: Node2D = MatchState.current.zones[1]
		vf.position = vz.position + vz.world_rect().get_center() - Vector2(24, 24)
		ctx.add_child(vf)
		vz.owner_team = MatchState.current.player_team
		vf.owner_team = MatchState.current.player_team
		vf.team = MatchState.current.player_team
		MatchState.current.set_money(MatchState.current.player_team, 500)
		var rally := vf.global_position + Vector2(500, 0)
		vf.set_rally(rally)
		vf.queue_unit("vehicle:jeep", true)
		var product: Vehicle2D = null
		for i in 600:
			vf._process(0.05)
			if product == null:
				for c in ctx.get_children():
					if c is Vehicle2D and c.unit_name == "jeep":
						product = c
						break
			if product != null:
				break
		rr.check(product != null, "no vehicle produced")
		if product != null:
			rr.check(not product.manned, "product spawned crewed")
			rr.check(not product.has_move_target(),
				"unmanned product took the rally order")
			rr.check(product.global_position.distance_to(rally) > 300.0,
				"unmanned product drove itself toward the rally")
			var driver: Unit2D = Spawner.spawn(ctx, "robot", "grunt",
				MatchState.current.player_team,
				product.global_position + Vector2(0, -24)) as Unit2D
			driver.issue_order(Order.for_target(product))
			for i in 300:
				driver._process(0.05)
				driver._physics_process(0.05)
				if product.manned:
					break
			rr.check(product.manned, "driver never boarded")
			product.move_to(rally)
			for i in 400:
				product._process(0.05)
				product._physics_process(0.05)
				if not product.has_move_target():
					break
			rr.check(product.global_position.distance_to(rally) < 60.0,
				"manned vehicle ignored the move order")
		rr.finish()
	if "--dir-test" in args:
		# zod convention: r000 faces +X (right), r090 up, r180 left, r270
		# down — the numbering runs counter-clockwise, so facing down
		# (angle PI/2 on the y-down screen) uses the r270 sprite
		var dirs := {
			0.0: 0, PI / 2.0: 6, PI: 4, -PI / 2.0: 2,
			PI / 4.0: 7, -PI / 4.0: 1, 3.0 * PI / 4.0: 5, -3.0 * PI / 4.0: 3,
		}
		var bad := 0
		for ang in dirs:
			var got: int = Unit2D._angle_to_dir(ang)
			if got != dirs[ang]:
				bad += 1
		var dir_rig := TestRig.start("DIR")
		dir_rig.check(bad == 0, "%d of 8 headings map to the wrong sprite" % bad)
		dir_rig.finish()
	if "--layer-test" in args:
		# layered rendering: turrets (with the original offset tables),
		# the medium tank's topf turret art, jeep wheel coverage, the
		# crane arm's inverted numbering and team wreck sprites
		var problems: Array[String] = []
		for vname in ["light", "medium", "heavy", "apc", "missile_launcher", "jeep"]:
			var lset: Dictionary = AnimLibrary.turret_set(vname,
				ContentDB.def_for("vehicle", vname).asset_dir, 1)
			if lset.is_empty():
				problems.append("%s: no turret/gun layer" % vname)
				continue
			var lframes: SpriteFrames = lset.frames
			if not lframes.has_animation("turret_0") or not lframes.has_animation("turret_7"):
				problems.append("%s: turret idle anims incomplete" % vname)
			# hull offsets ride on the per-type scene root now
			var inst := ContentDB.scene_for("vehicle", vname).instantiate()
			var hull_ok: bool = inst is Vehicle2D and (inst as Vehicle2D) \
					.turret_hull_off.size() == AnimLibrary.DIRECTIONS
			# mirrored hull facings need x-mirrored turret offsets — the
			# tables once copied dirs 0-3 verbatim into 4-7 and every
			# west/south-facing turret hung off its mounting ring
			if hull_ok and vname in ["light", "medium", "heavy"]:
				var tbl: PackedVector2Array = (inst as Vehicle2D).turret_hull_off
				var pair_ok := func(i: int, j: int) -> bool:
					return is_equal_approx(tbl[i].x, -tbl[j].x) \
						and is_equal_approx(tbl[i].y, tbl[j].y)
				if not (pair_ok.call(3, 1) and pair_ok.call(4, 0)
						and pair_ok.call(5, 7) and pair_ok.call(6, 2)):
					problems.append("%s: mirrored turret offsets not mirrored" % vname)
			inst.free()
			if not hull_ok:
				problems.append("%s: hull offsets missing" % vname)
		var med: SpriteFrames = AnimLibrary.turret_set("medium",
			ContentDB.def_for("vehicle", "medium").asset_dir, 1).frames
		if med.get_frame_texture("turret_0", 0) \
				!= load("res://assets/z/vehicles_medium/topf_r000.png"):
			problems.append("medium: idle turret not the topf art")
		var wheels: Dictionary = AnimLibrary.jeep_wheel_set(
			"res://assets/z/vehicles_jeep", 1, true)
		var wframes: SpriteFrames = wheels.frames
		for d in [0, 1, 3, 4, 5, 7]:
			if not wframes.has_animation("wheels_%d" % d):
				problems.append("jeep: wheels_%d missing" % d)
		for d in [2, 6]:
			if wframes.has_animation("wheels_%d" % d):
				problems.append("jeep: wheels_%d should not exist (hidden)" % d)
		var crane: Dictionary = AnimLibrary.crane_set("res://assets/z/vehicles_crane")
		if crane.is_empty() or not crane.frames.has_animation("arm_0") \
				or not crane.frames.has_animation("hook"):
			problems.append("crane: arm/hook layers missing")
		else:
			# inverted numbering: arm facing E (dir 0) is the r180 file
			if crane.frames.get_frame_texture("arm_0", 0) \
					!= load("res://assets/z/vehicles_crane/crane_r180.png"):
				problems.append("crane: arm_0 is not the r180 (inverted) art")
		for vname in ["apc", "missile_launcher", "jeep"]:
			var vframes: SpriteFrames = AnimLibrary.vehicle_frames(
				ContentDB.def_for("vehicle", vname).asset_dir, 1)
			if not vframes.has_animation("wasted"):
				problems.append("%s: no wreck sprite" % vname)
		# the jeep's `fire_*` art is the gunner OVERLAY (16x14 on a
		# 32x31 hull): the hull must NOT play it (the body strobed away
		# on every shot) — the turret layer owns aim (n00) and flash (n01)
		var jeep_hull: SpriteFrames = AnimLibrary.vehicle_frames(
			ContentDB.def_for("vehicle", "jeep").asset_dir, 1)
		if jeep_hull.has_animation("fire_0"):
			problems.append("jeep: hull fire anim exists (overlay art!)")
		var jeep_gun: Dictionary = AnimLibrary.turret_set("jeep",
			ContentDB.def_for("vehicle", "jeep").asset_dir, 1)
		if jeep_gun.is_empty() or not jeep_gun.frames.has_animation("turretfire_0"):
			problems.append("jeep: gunner flash layer missing")
		# full-canvas fire art (gatling) keeps its legitimate hull flash
		if not AnimLibrary.vehicle_frames(
				ContentDB.def_for("cannon", "gatling").asset_dir, 1) \
				.has_animation("fire_0"):
			problems.append("gatling: hull fire flash missing")
		for tname in ["light", "medium", "heavy"]:
			if AnimLibrary.plain_empty_path(
					ContentDB.def_for("vehicle", tname).asset_dir, "red") == "":
				problems.append("%s: no plain empty art" % tname)
		var install := AnimLibrary.cannon_install_frames()
		if install.size() != 3:
			problems.append("cannons: shared init-place frames missing")
		for cname in ["gatling", "howitzer"]:
			var cframes: SpriteFrames = AnimLibrary.vehicle_frames(
				ContentDB.def_for("cannon", cname).asset_dir, 1)
			# manned idle holds the seated-gunner frame (last install
			# frame); fire is only a flash
			if not cframes.has_animation("base_0") or not cframes.has_animation("install_0"):
				problems.append("%s: no manned idle/install art" % cname)
			elif cframes.get_frame_texture("base_0", 0) != cframes.get_frame_texture(
					"install_0", cframes.get_frame_count("install_0") - 1):
				problems.append("%s: manned idle should hold the seated gunner" % cname)
			if cframes.get_animation_loop("fire_0"):
				problems.append("%s: fire flash must not loop" % cname)
		var layer_rig := TestRig.start("LAYER")
		for problem in problems:
			layer_rig.check(false, String(problem))
		layer_rig.finish()
	if "--cursor-test" in args:
		# the contextual cursor: every zod DetermineCursor branch this
		# remake implements, plus the art families actually shipping
		var cproblems: Array[String] = []
		var hud := CanvasLayer.new()
		ctx.add_child(hud)
		var gcur := GameCursor.install(hud)
		# quiet corner, overkill HP: the map's live war must not kill or
		# walk off with the test fixtures before the checks run
		var corner := Vector2(2400, 3080)
		var foe := Spawner.spawn(ctx, "robot", "grunt", 2, corner, true)
		var free_jeep := Spawner.spawn(ctx, "vehicle", "jeep", 0, corner + Vector2(100, 0), false)
		var mine3 := Spawner.spawn(ctx, "robot", "grunt", 1, corner + Vector2(200, 0), true)
		for u3 in [foe, free_jeep, mine3]:
			if u3:
				u3.hp = 10000000
				u3.max_hp = 10000000
		var crate := Pickup.new()
		crate.pickup_type = "grenades"
		crate.position = corner + Vector2(300, 0)
		ctx.add_child(crate)
		var pfort: FortBuilding = null
		for c in ctx.get_children():
			if c is FortBuilding and c.team == MatchState.current.player_team:
				pfort = c
				break
		await tree.process_frame
		SelectionManager.current.select_single(mine3)
		# _determine takes VIEWPORT coords — push the world points
		# through the camera's canvas transform first
		var xform: Transform2D = tree.root.get_canvas_transform()
		for spec in [["attack", foe.global_position], ["enter", free_jeep.global_position],
				["grab", crate.global_position], ["place", corner + Vector2(400, 0)]]:
			var got: String = gcur._determine(xform * Vector2(spec[1]))
			if got != String(spec[0]):
				cproblems.append("%s got %s" % [spec[0], got])
		if pfort:
			var got_fort: String = gcur._determine(xform * pfort.visual_center())
			if got_fort != "place":
				cproblems.append("garrison got %s" % got_fort)
		SelectionManager.current.clear_selection()
		var got_plain: String = gcur._determine(foe.global_position)
		if got_plain != "cursor":
			cproblems.append("plain got %s" % got_plain)
		# EXIT: a selected fort holding a garrison, hovered. The exit_*
		# art shipped with no code path able to return it, and there was
		# no dismount action at all to attach it to.
		if pfort:
			var stowaway: Unit2D = Spawner.spawn(ctx, "robot", "grunt",
				pfort.team, pfort.world_footprint().get_center()) as Unit2D
			if stowaway and pfort.garrison_robot(stowaway):
				SelectionManager.current.select_single(pfort)
				SelectionManager.current.selected = [pfort]
				var got_exit: String = gcur._determine(
					xform * pfort.visual_center())
				if got_exit != "exit":
					cproblems.append("exit got %s" % got_exit)
				# and the action must actually hand the robot back
				var released := Commands.eject()
				if released < 1:
					cproblems.append("eject released %d" % released)
				elif stowaway.carried or not stowaway.visible:
					cproblems.append("released robot still carried/hidden")
			SelectionManager.current.clear_selection()
			if is_instance_valid(stowaway):
				stowaway.queue_free()
		for fam in ["cursor", "place", "attack", "grab", "enter", "repair",
				"nono", "cannon", "exit"]:
			var team := AnimLibrary.team_name(MatchState.current.player_team)
			if not ResourceLoader.exists("res://assets/z/ui/cursor/%s_%s_n00.png" % [fam, team]) \
					and fam != "cursor":
				cproblems.append("art %s_%s" % [fam, team])
		# ASSERTED (this block used to only print its problem list)
		var cur := TestRig.start("CURSOR")
		cur.check(cproblems.is_empty(), ", ".join(cproblems))
		cur.finish("contexts=%d" % 9)
		hud.queue_free()
		for u in [foe, free_jeep, mine3]:
			if is_instance_valid(u):
				u.queue_free()
		crate.queue_free()
	if "--orders-test" in args:
		# the single order intake: state, targets and flags come out of
		# the Order, never from field writes
		var oproblems: Array[String] = []
		var bot: Unit2D = Spawner.spawn(ctx, "robot", "grunt", 1,
			Vector2(600, 600))
		if bot == null:
			oproblems.append("spawn failed")
		else:
			bot.hp = 100000  # walks across a live 8-team battlefield
			# the map's own 8-team war rages during this test — its
			# elimination cascade would die() our bot mid-order; over=
			# true blocks report_fort_destroyed for the test's duration
			GameState.over = true
			GameSettings.auto_idle = false  # deterministic order sequence
			bot.issue_order(Order.move(Vector2(700, 600)))
			if bot.state != Unit2D.State.MOVING or bot.attack_move \
					or bot.enter_target != null:
				oproblems.append("MOVE state")
			bot.issue_order(Order.move_attack(Vector2(650, 600)))
			if not bot.attack_move:
				oproblems.append("MOVE_ATTACK flag")
			var jeep4: Vehicle2D = Spawner.spawn(ctx, "vehicle", "jeep", 0,
				Vector2(760, 610))
			bot.issue_order(Order.for_target(jeep4))
			if bot.state != Unit2D.State.ENTERING or bot.enter_target != jeep4 \
					or bot.attack_move:
				oproblems.append("MAN_VEHICLE order")
			var fort2 := FortBuilding.new()
			fort2.setup(0, 1, "desert")
			fort2.position = Vector2(650, 700)
			ctx.add_child(fort2)
			bot.issue_order(Order.for_target(fort2))
			if bot.order.type != Order.Type.GARRISON:
				oproblems.append("garrison resolve")
			bot._order_done()
			if not bot.is_idle() or bot.state != Unit2D.State.IDLE:
				oproblems.append("order_done")
			# ATTACK order: the unit must FOLLOW its target, not walk to
			# where the target stood when the order was given. Right-click
			# on an enemy used to fall through to a plain move.
			var runner: Unit2D = Spawner.spawn(ctx, "robot", "grunt", 2,
				Vector2(1100, 600))
			var hunter: Unit2D = Spawner.spawn(ctx, "robot", "grunt", 1,
				Vector2(700, 600))
			if runner != null and hunter != null:
				runner.hp = 100000000
				runner.max_hp = 100000000
				hunter.hp = 100000000
				hunter.max_hp = 100000000
				hunter.damage = 0  # never actually kill it: we want the chase
				hunter.issue_order(Order.attack(runner))
				if hunter.attack_target != runner:
					oproblems.append("ATTACK order did not take the target")
				var first_goal := hunter.move_target
				# the quarry runs; the hunter must re-route after it
				runner.global_position = Vector2(1100, 1000)
				for i in 30:
					hunter._process(0.05)
					hunter._physics_process(0.05)
				if hunter.attack_target != runner:
					oproblems.append("ATTACK order dropped a live target")
				elif hunter.move_target == first_goal \
						and hunter.has_move_target():
					oproblems.append("ATTACK kept routing to the stale position")
				# and it ends when the target dies
				runner.hp = 1
				runner.die()
				for i in 10:
					hunter._process(0.05)
				if hunter.attack_target != null:
					oproblems.append("ATTACK order outlived its dead target")
				hunter.queue_free()
				if is_instance_valid(runner):
					runner.queue_free()
			if bot.attack_move:
				oproblems.append("order_done kept attack_move")
			# a robot ordered onto a NON-garrisonable building walks up
			# first, then must land IDLE (used to stick in ENTERING
			# forever — invisible to the AI's idle scan)
			var radar: Building2D = ContentDB.building_def(2).behaviour.new()
			radar.setup(2, 1, "desert")
			radar.position = Vector2(660, 620)
			ctx.add_child(radar)
			bot.issue_order(Order.for_target(radar))
			for i in 300:
				bot._process(0.05)
				bot._physics_process(0.05)
				if bot.is_idle():
					break
			if not bot.is_idle():
				oproblems.append("radar order stuck in ENTERING")
			# MAN target destroyed mid-walk: back to idle, retaskable
			var jeep5: Vehicle2D = Spawner.spawn(ctx, "vehicle", "jeep", 0,
				Vector2(900, 700))
			bot.issue_order(Order.for_target(jeep5))
			jeep5.take_damage(1000000000)  # dies NOW: queue_free needs real frames
			for i in 10:
				bot._process(0.05)
				bot._physics_process(0.05)
			if not bot.is_idle():
				oproblems.append("freed MAN target stuck")
			# DEFEND stance: arrival arms the post, displacement re-holds it
			bot.issue_order(Order.move_defend(Vector2(700, 620)))
			for i in 240:
				bot._process(0.05)
				bot._physics_process(0.05)
				if bot.is_idle():
					break
			if bot.defend_post == Vector2.INF:
				oproblems.append("defend post not armed")
			else:
				bot.global_position += Vector2(80, 0)  # shoved off the post
				for i in 240:
					bot._process(0.05)
					bot._physics_process(0.05)
					if bot.is_idle() \
							and bot.global_position.distance_to(bot.defend_post) < 40.0:
						break
				if bot.global_position.distance_to(bot.defend_post) > 40.0:
					oproblems.append("defend post not re-held")
			# smart idle: empty hardware within the auto-grab radius
			# (AUTO_RADIUS, playtested to 110) gets a crew without any
			# order — a FRESH robot (defenders hold their post and never
			# auto-grab by design). Plant the jeep INSIDE the radius.
			GameSettings.auto_idle = true  # ...and back on for the grab test
			var idle_bot: Unit2D = Spawner.spawn(ctx, "robot", "grunt", 1,
				Vector2(560, 520))
			idle_bot.hp = 100000
			var grab_jeep: Vehicle2D = Spawner.spawn(ctx, "vehicle", "jeep", 0,
				Vector2(560 + 90, 520))
			# success = the robot boarded SOMETHING (the nearest empty
			# hardware wins, not necessarily our planted jeep)
			var manned := false
			for i in 300:
				idle_bot._process(0.05)
				idle_bot._physics_process(0.05)
				if not is_instance_valid(idle_bot) or grab_jeep.manned \
						or idle_bot.state == Unit2D.State.ENTERING:
					manned = true
					break
			if not manned:
				oproblems.append("smart idle did not man nearby vehicle")
			# ...and it must NOT hijack a unit that is executing an order,
			# nor one that just ARRIVED where the player sent it. Auto-grab
			# used to fire the instant move_target cleared, so reaching your
			# destination handed the unit straight to the nearest hull or
			# zone centre and the order looked cancelled.
			var parked: Unit2D = Spawner.spawn(ctx, "robot", "grunt", 1,
				Vector2(560, 520))
			parked.hp = 100000
			var bait: Vehicle2D = Spawner.spawn(ctx, "vehicle", "jeep", 0,
				Vector2(560 + 60, 520))
			parked.move_to(Vector2(566, 520))  # a short, quickly-finished order
			var hijacked := false
			for i in 40:  # ~2s of sim: inside AUTO_IDLE_DELAY
				parked._process(0.05)
				parked._physics_process(0.05)
				if parked.enter_target != null or parked.state == Unit2D.State.ENTERING \
						or bait.manned:
					hijacked = true
					break
			if hijacked:
				oproblems.append("auto-grab hijacked a unit inside the idle delay")
			if is_instance_valid(parked):
				parked.queue_free()
			if is_instance_valid(bait):
				bait.queue_free()
			radar.queue_free()
			GameState.over = false
			if is_instance_valid(bot):
				bot.die()
				if bot.state != Unit2D.State.DEAD:
					oproblems.append("DEAD state")
				bot.issue_order(Order.move(Vector2(0, 0)))
				if bot.state != Unit2D.State.DEAD:
					oproblems.append("dead units take no orders")
			jeep4.queue_free()
			fort2.queue_free()
		var orders_rig := TestRig.start("ORDERS")
		# DISPATCH ON EVERY PICK TARGET. Pick.at answers with units,
		# CRATES and buildings, and Commands._find_enemy read `team` off
		# whatever came back — a crate has none, and `int(null)` is a hard
		# crash, so right-clicking a crate with anything selected killed
		# the match ("Nonexistent 'int' constructor"). Running the real
		# dispatch over each target IS the assertion: a runtime error
		# aborts the flag.
		var crate := Pickup.new()
		crate.pickup_type = "grenades"
		crate.position = NavWorld.current.find_free_spot(Vector2(1020, 620), "robot")
		ctx.add_child(crate)
		await Engine.get_main_loop().process_frame
		var pickers: Array[Unit2D] = []
		for spec in [["robot", "grunt"], ["vehicle", "jeep"], ["cannon", "gatling"]]:
			var picker: Unit2D = Spawner.spawn(ctx, spec[0], spec[1],
				MatchState.current.player_team,
				NavWorld.current.find_free_spot(
					Vector2(1020, 700) + Vector2(40 * pickers.size(), 0), spec[0]),
				spec[0] != "robot") as Unit2D
			if picker == null:
				continue
			pickers.append(picker)
			SelectionManager.current.clear_selection()
			SelectionManager.current.toggle_select(picker, false)
			for target in [crate.global_position, crate.global_position + Vector2(400, 0)]:
				Commands.dispatch(target)
			orders_rig.check(picker.order != null or picker.has_move_target(),
				"%s took no order at all from a crate click" % spec[1])
			if picker.order != null:
				orders_rig.check(picker.order.type != Order.Type.ATTACK,
					"%s treated a CRATE as an enemy" % spec[1])
		SelectionManager.current.clear_selection()
		for picker in pickers:
			picker.queue_free()
		crate.queue_free()
		for problem in oproblems:
			orders_rig.check(false, String(problem))
		orders_rig.finish()
	if "--scenes-test" in args:
		# every per-type scene instantiates with the right identity and
		# rig nodes; buildings resolve scenes; a generated map loads
		var sproblems: Array[String] = []
		for kind in ["robot", "vehicle", "cannon"]:
			for name in ContentDB.defs_of(kind):
				var scene := ContentDB.scene_for(kind, String(name))
				if scene == null:
					sproblems.append("%s:%s no scene" % [kind, name])
					continue
				var inst := scene.instantiate()
				if inst is Vehicle2D:
					var veh := inst as Vehicle2D
					if veh.kind != kind or veh.unit_name != String(name):
						sproblems.append("%s:%s identity" % [kind, name])
				elif inst is Unit2D:
					var rob := inst as Unit2D
					if rob.unit_name != String(name):
						sproblems.append("robot:%s identity" % name)
				else:
					sproblems.append("%s:%s wrong root" % [kind, name])
				inst.free()
		var expect_nodes := {
			"vehicle:jeep": ["Wheels", "Turret"],
			"vehicle:light": ["Turret"],
			"vehicle:medium": ["Turret"],
			"vehicle:heavy": ["Turret"],
			"vehicle:apc": ["Turret", "Doors"],
			"vehicle:missile_launcher": ["Turret"],
			"vehicle:crane": ["Turret", "Hook", "Cones"],
		}
		for key in expect_nodes:
			var parts: PackedStringArray = String(key).split(":")
			var inst2 := ContentDB.scene_for(parts[0], parts[1]).instantiate()
			for node_name in expect_nodes[key]:
				if inst2.get_node_or_null(String(node_name)) == null:
					sproblems.append("%s missing %s" % [key, node_name])
			# turret tables ride on the scene root
			if parts[0] == "vehicle" and parts[1] != "crane":
				var veh2 := inst2 as Vehicle2D
				if veh2.turret_hull_off.size() != AnimLibrary.DIRECTIONS:
					sproblems.append("%s hull offsets missing" % key)
			inst2.free()
		for id in 8:
			var bdef := ContentDB.building_def(id)
			if bdef == null:
				continue
			var bpath := "res://scenes/buildings/%s.tscn" % bdef.bname
			if not ResourceLoader.exists(bpath):
				sproblems.append("building scene %s missing" % bdef.bname)
				continue
			var binst := (load(bpath) as PackedScene).instantiate()
			if binst is Building2D:
				if (binst as Building2D).building_id != id:
					sproblems.append("%s wrong id" % bdef.bname)
			else:
				sproblems.append("%s wrong root" % bdef.bname)
			binst.free()
		# scenery draws at NATIVE art size, bottom edge on its object tile
		# (zod OMapObject::DoRender) — 2x turned clutter into giant smears;
		# zone marker stamps are texture-sized (team 8x4, neutral 4x4) and
		# the draw must stay texture-driven or the neutral one smears
		var map_root := MatchState.current.map_root
		if map_root != null:
			for sc in map_root.get_children():
				if not String(sc.name).begins_with("Scenery_"):
					continue
				var parts := String(sc.name).split("_")
				var tex: Texture2D = sc.get("texture")
				if tex == null:
					continue
				if sc.scale != Vector2.ONE:
					sproblems.append("scenery %s scaled" % sc.name)
				var want := Vector2(int(parts[1]) * 16 + 8, int(parts[2]) * 16 + 8) \
					+ Vector2(tex.get_size().x - 16, 16 - tex.get_size().y) * 0.5
				if (Vector2(sc.position) - want).length() > 0.5:
					sproblems.append("scenery %s anchor" % sc.name)
		for team in ["null", "red", "blue", "green", "yellow"]:
			var mtex: Texture2D = load(
				"res://assets/z/planets/zone_marker_%s.png" % team)
			var want_size := Vector2(4, 4) if team == "null" else Vector2(8, 4)
			if mtex == null or mtex.get_size() != want_size:
				sproblems.append("marker art %s" % team)
		# SCENE vs JSON PARITY: the generated .tscn must carry everything
		# the JSON loader spawns. The zone FLAG MARKERS (map_item 0) were
		# dropped by the scene builder, so every scene map opened fully
		# neutral with its flags at derived centre spots while the same
		# map as JSON started with its authored owners — the exact bug
		# that was already fixed once on the JSON path.
		var sc_rig := TestRig.start("SCENES")
		for problem in sproblems:
			sc_rig.check(false, problem)
		var audited := 0
		for entry in MapCatalog.entries():
			var mname := String(entry.name)
			var scene_path := "res://assets/maps_scenes/%s.tscn" % mname
			var json_path := "res://assets/maps/%s.json" % mname
			if not ResourceLoader.exists(scene_path) or not ResourceLoader.exists(json_path):
				continue
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(json_path))
			if not (parsed is Dictionary):
				continue
			var jdata: Dictionary = parsed
			# what the JSON says: zones, authored flags, authored owners
			var want_zones: int = jdata.zones.size()
			var want_flags := 0
			var want_owned := 0
			var flagged_zones := {}
			var owned_zones := {}
			var want_buildings := 0
			var want_robots := 0
			for o in jdata.objects:
				var otype := String(o.type)
				if otype == "building":
					want_buildings += 1
				elif otype == "robot":
					want_robots += 1
				elif otype == "map_item" and int(o.id) == MapLoader.ZONE_FLAG_ID:
					var cell := Vector2i(int(o.x), int(o.y))
					for zi in jdata.zones.size():
						var z = jdata.zones[zi]
						if Rect2i(int(z.x), int(z.y), int(z.w), int(z.h)).has_point(cell):
							# count ZONES that get a flag, not markers: a
							# retail level can drop several markers in one
							# zone, and a Zone node holds ONE flag tile
							if not flagged_zones.has(zi):
								flagged_zones[zi] = true
								want_flags += 1
							if int(o.get("owner", 0)) != 0 and not owned_zones.has(zi):
								owned_zones[zi] = true
								want_owned += 1
							break
			# what the SCENE carries (instantiated, never added to the
			# tree — no _ready, no match state touched)
			var inst: Node = (load(scene_path) as PackedScene).instantiate()
			var got_zones := 0
			var got_flags := 0
			var got_owned := 0
			var got_buildings := 0
			var got_robots := 0
			for child in inst.get_children():
				if child is Zone:
					got_zones += 1
					if (child as Zone).flag_tile != Vector2i.MAX:
						got_flags += 1
					if (child as Zone).owner_team != 0:
						got_owned += 1
				elif child is Building2D:
					got_buildings += 1
				elif child is Unit2D and String(child.get("kind")) == "robot":
					got_robots += 1
			inst.free()
			audited += 1
			sc_rig.check(got_zones == want_zones,
				"%s: %d zones in the scene, %d in the JSON" % [mname, got_zones, want_zones])
			sc_rig.check(got_flags == want_flags,
				"%s: %d authored flag tiles kept of %d" % [mname, got_flags, want_flags])
			sc_rig.check(got_owned == want_owned,
				"%s: %d pre-owned zones kept of %d" % [mname, got_owned, want_owned])
			sc_rig.check(got_buildings == want_buildings,
				"%s: %d buildings in the scene, %d in the JSON" % [mname, got_buildings, want_buildings])
			sc_rig.check(got_robots == want_robots,
				"%s: %d robots in the scene, %d in the JSON" % [mname, got_robots, want_robots])
		sc_rig.check(audited > 0, "no map scenes to audit")
		sc_rig.finish("%d map scenes vs their JSON" % audited)
	if "--defs-test" in args:
		# the .tres registry: every def resolvable and sane, rosters point
		# at real units, discovery still catches unregistered folders
		var dproblems: Array[String] = []
		for kind in ["robot", "vehicle", "cannon"]:
			for name in ContentDB.defs_of(kind):
				var d := ContentDB.def_for(kind, String(name))
				if d.asset_dir == "" or not DirAccess.dir_exists_absolute(d.asset_dir):
					dproblems.append("%s:%s asset_dir" % [kind, name])
				if d.hp <= 0 or d.pop <= 0 or d.cost < 0:
					dproblems.append("%s:%s stats" % [kind, name])
				if d.projectile != null and d.projectile.texture == null:
					dproblems.append("%s:%s projectile texture" % [kind, name])
		if not ContentDB.has_unit("vehicle", "crane"):
			dproblems.append("folder discovery (crane)")
		for id in 8:
			var b := ContentDB.building_def(id)
			if b == null:
				dproblems.append("building def %d missing" % id)
				continue
			if b.behaviour == null:
				dproblems.append("%s behaviour" % b.bname)
			for level in b.build_lists:
				for item in b.build_lists[level]:
					var parts: PackedStringArray = String(item).split(":")
					if not ContentDB.has_unit(parts[0], parts[1]):
						dproblems.append("%s roster %s" % [b.bname, item])
		for pk in ["grenades", "rockets"]:
			var pd := ContentDB.pickup_def(pk)
			if pd == null or pd.texture == null:
				dproblems.append("pickup %s" % pk)
		var defs_rig := TestRig.start("DEFS")
		for problem in dproblems:
			defs_rig.check(false, String(problem))
		defs_rig.finish()
	if "--balance-test" in args:
		# BALANCE SWEEP vs the ORIGINAL game, transcribed from zod engine
		# sources: build lists from zbuildlist.cpp LoadDefaults, unit stats
		# from zsettings.cpp SetDefaults at the project's x0.08 integer
		# scale (see content/*.tres). Any drift fails here.
		var bproblems: Array[String] = []
		var want_lists := {
			"fort": {
				0: ["robot:grunt", "vehicle:jeep", "vehicle:crane", "cannon:gatling"],
				1: ["robot:grunt", "robot:psycho", "vehicle:jeep", "vehicle:light", "vehicle:crane", "cannon:gatling", "cannon:gun"],
				2: ["robot:grunt", "robot:psycho", "robot:sniper", "robot:tough", "vehicle:jeep", "vehicle:light", "vehicle:medium", "vehicle:crane", "cannon:gatling", "cannon:gun", "cannon:howitzer"],
				3: ["robot:grunt", "robot:psycho", "robot:sniper", "robot:tough", "robot:pyro", "vehicle:jeep", "vehicle:light", "vehicle:medium", "vehicle:apc", "vehicle:crane", "cannon:gatling", "cannon:gun", "cannon:howitzer"],
				4: ["robot:grunt", "robot:psycho", "robot:sniper", "robot:tough", "robot:pyro", "robot:laser", "vehicle:jeep", "vehicle:light", "vehicle:medium", "vehicle:heavy", "vehicle:apc", "vehicle:crane", "cannon:gatling", "cannon:gun", "cannon:howitzer", "cannon:missile_cannon"],
				5: ["robot:grunt", "robot:psycho", "robot:sniper", "robot:tough", "robot:pyro", "robot:laser", "vehicle:jeep", "vehicle:light", "vehicle:medium", "vehicle:heavy", "vehicle:apc", "vehicle:missile_launcher", "vehicle:crane", "cannon:gatling", "cannon:gun", "cannon:howitzer", "cannon:missile_cannon"],
			},
			"robot_factory": {
				0: ["robot:grunt", "cannon:gatling"],
				1: ["robot:grunt", "robot:psycho", "cannon:gatling"],
				2: ["robot:grunt", "robot:psycho", "robot:sniper", "robot:tough", "cannon:gatling", "cannon:gun"],
				3: ["robot:grunt", "robot:psycho", "robot:sniper", "robot:tough", "robot:pyro", "cannon:gatling", "cannon:gun", "cannon:howitzer"],
				4: ["robot:grunt", "robot:psycho", "robot:sniper", "robot:tough", "robot:pyro", "robot:laser", "cannon:gatling", "cannon:gun", "cannon:howitzer"],
				5: ["robot:grunt", "robot:psycho", "robot:sniper", "robot:tough", "robot:pyro", "robot:laser", "cannon:gatling", "cannon:gun", "cannon:howitzer", "cannon:missile_cannon"],
			},
			"vehicle_factory": {
				0: ["vehicle:jeep", "cannon:gatling"],
				1: ["vehicle:jeep", "vehicle:light", "cannon:gatling", "cannon:gun"],
				2: ["vehicle:jeep", "vehicle:light", "vehicle:medium", "cannon:gatling", "cannon:gun"],
				3: ["vehicle:jeep", "vehicle:light", "vehicle:medium", "vehicle:apc", "cannon:gatling", "cannon:gun", "cannon:howitzer"],
				4: ["vehicle:jeep", "vehicle:light", "vehicle:medium", "vehicle:heavy", "vehicle:apc", "cannon:gatling", "cannon:gun", "cannon:howitzer"],
				5: ["vehicle:jeep", "vehicle:light", "vehicle:medium", "vehicle:heavy", "vehicle:apc", "vehicle:missile_launcher", "cannon:gatling", "cannon:gun", "cannon:howitzer", "cannon:missile_cannon"],
			},
		}
		for producer in want_lists:
			var pdef := ContentDB.producer_def(producer)
			if pdef == null:
				bproblems.append("producer %s missing" % producer)
				continue
			for level in range(6):
				var want: Array = want_lists[producer][level]
				var got: Array = pdef.build_lists.get(level, [])
				if got != want:
					bproblems.append("%s L%d roster drift" % [producer, level])
		# zsettings.cpp stats at x0.08 (hp/damage/cooldown/range/speed/
		# hit chance/splash/build seconds/cost). cost is our money overlay.
		# ranges are zod's native attack_radius values (the world renders
		# 1:1 — the halved values were a 2x-era transcription error that
		# left every weapon shorter than the fort's gate-to-centre reach)
		var want_stats := {
			"robot:grunt": [86, 1, 0.5, 120.0, 60.0, 0.7, 0.0, 72.0],
			"robot:psycho": [141, 2, 0.1, 120.0, 51.0, 0.65, 0.0, 98.0],
			"robot:sniper": [141, 6, 0.4, 144.0, 60.0, 0.8, 0.0, 148.0],
			"robot:tough": [270, 133, 1.442, 120.0, 51.0, 1.0, 40.0, 116.0],
			"robot:pyro": [216, 8, 0.1, 120.0, 51.0, 0.7, 0.0, 161.0],
			"robot:laser": [162, 14, 0.4, 136.0, 60.0, 0.7, 0.0, 179.0],
			"vehicle:jeep": [141, 2, 0.1, 120.0, 73.0, 0.65, 0.0, 81.0],
			"vehicle:light": [270, 167, 1.128, 120.0, 60.0, 1.0, 40.0, 137.0],
			"vehicle:medium": [541, 267, 2.336, 128.0, 51.0, 1.0, 45.0, 225.0],
			"vehicle:heavy": [670, 400, 4.088, 144.0, 39.0, 1.0, 50.0, 309.0],
			"vehicle:apc": [541, 0, 9.9, 0.0, 60.0, 0.0, 0.0, 118.0],
			"vehicle:missile_launcher": [541, 670, 4.454, 160.0, 26.0, 1.0, 80.0, 373.0],
			"vehicle:crane": [800, 0, 9.9, 0.0, 60.0, 0.0, 0.0, 97.0],
			"cannon:gatling": [141, 3, 0.1, 120.0, 0.0, 0.65, 0.0, 96.0],
			"cannon:gun": [270, 250, 2.254, 128.0, 0.0, 1.0, 40.0, 125.0],
			"cannon:howitzer": [270, 333, 4.86, 200.0, 0.0, 1.0, 40.0, 179.0],
			"cannon:missile_cannon": [270, 667, 1.124, 144.0, 0.0, 1.0, 50.0, 182.0],
		}
		for key in want_stats:
			var parts: PackedStringArray = String(key).split(":")
			var d := ContentDB.def_for(parts[0], parts[1])
			var w: Array = want_stats[key]
			if [d.hp, d.damage, snappedf(d.cooldown, 0.001), d.range_px, d.speed,
					d.hit_chance, d.splash_radius, d.build_time] != [w[0], w[1], snappedf(w[2], 0.001), w[3], w[4], w[5], w[6], w[7]]:
				bproblems.append("%s stat drift (hp %d dmg %d cd %.3f rng %.0f spd %.0f hit %.2f splash %.0f build %.0f)"
					% [key, d.hp, d.damage, d.cooldown, d.range_px, d.speed, d.hit_chance, d.splash_radius, d.build_time])
		# no free producers: everything buildable costs money
		for kind in ["robot", "vehicle", "cannon"]:
			for name in ContentDB.buildable(kind):
				if ContentDB.def_for(kind, String(name)).cost <= 0:
					bproblems.append("%s:%s costs nothing" % [kind, name])
		# InitZones: every fort claims its home zone — nobody starts broke
		var fort_teams := {}
		for b in tree.get_nodes_in_group(Groups.BUILDINGS):
			if b is FortBuilding and b.alive and b.team != 0:
				fort_teams[b.team] = true
		for t in fort_teams:
			var owned := 0
			for z in MatchState.current.zones:
				if z.owner_team == t:
					owned += 1
			if owned < 1:
				bproblems.append("team %d starts with no home zone" % t)
		var balance_rig := TestRig.start("BALANCE")
		for problem in bproblems:
			balance_rig.check(false, String(problem))
		balance_rig.finish()
	if "--vfx-test" in args:
		# damage smoke (per-direction track_dust), oil stains, wreck
		# smoke variants and the grenade projectile sprite resolve
		var vproblems: Array[String] = []
		for d in 8:
			var dust: SpriteFrames = AnimLibrary.dir_effect_frames(
				"res://assets/z/effects/track_dust", "track_dust", d, 8.0)
			if not dust.has_animation("fx"):
				vproblems.append("track_dust dir %d missing" % d)
		for fx_name in ["tank_oil", "smoke", "little_smoke", "small_fire_smoke",
				"spark", "ground_spark", "explosion_missile2", "grenade"]:
			var frames: SpriteFrames = AnimLibrary.effect_frames(
				"res://assets/z/effects/%s" % fx_name, fx_name, 8.0)
			if not frames.has_animation("fx"):
				vproblems.append("%s frames missing" % fx_name)
		Fx.vehicle_smoke(Vector2(100, 100), 3, true)
		Fx.laser(Vector2(0, 0), Vector2(50, 50))
		# a demo row in front of the camera for screenshot verification
		var fx_cam: Camera2D = ctx.get_viewport().get_camera_2d()
		if fx_cam:
			Fx.explosion(fx_cam.position + Vector2(-90, 0))
			Fx.explosion(fx_cam.position + Vector2(0, -10), true)
			Fx.impact(fx_cam.position + Vector2(60, 0))
			Fx.play("muzzle", fx_cam.position + Vector2(110, 0))

		# muzzle and impact must resolve REAL sprite art (particle
		# fallbacks were the old bug); wreck flame variants resolve too
		for fx_name in ["muzzle", "impact", "fire0", "fire1"]:
			var def := ContentDB.effect_def(fx_name)
			var art := def.art_name if def.art_name != "" else def.id
			var frames_check: SpriteFrames = AnimLibrary.effect_frames(
				"res://assets/z/effects/%s" % art, art, def.fps)
			if not frames_check.has_animation("fx"):
				vproblems.append("%s has no sprite art (fallback)" % fx_name)
		# effect scales are relative to the 2x unit baseline — no giants
		for fx_name in ContentDB.effect_names():
			var scale_v := ContentDB.effect_def(fx_name).scale
			if scale_v > 1.5:
				vproblems.append("%s scale %.2f oversized" % [fx_name, scale_v])
		# fire animations are ONE-SHOT everywhere (muzzle flash policy:
		# never loop, never hold the flash frame)
		var rf: SpriteFrames = AnimLibrary.robot_frames("grunt", 1)
		for d in 8:
			if rf.has_animation("fire_%d" % d) \
					and rf.get_animation_loop("fire_%d" % d):
				vproblems.append("robot fire_%d loops" % d)
		var medium_dir := ContentDB.def_for("vehicle", "medium").asset_dir
		var vf: SpriteFrames = AnimLibrary.vehicle_frames(medium_dir, 1)
		for d in 8:
			if vf.has_animation("fire_%d" % d) \
					and vf.get_animation_loop("fire_%d" % d):
				vproblems.append("vehicle fire_%d loops" % d)
		var vfx_rig := TestRig.start("VFX")
		for problem in vproblems:
			vfx_rig.check(false, String(problem))
		vfx_rig.finish()
	if "--pose-test" in args:
		# dump the exact layer positioning the engine computes per type
		# and facing: turret art file, canvas sizes, final position
		var lines: Array[String] = []
		for vname in ["light", "medium", "heavy", "apc", "missile_launcher", "jeep", "crane"]:
			for state in [0, 1]:
				var v9: Vehicle2D = load("res://scenes/vehicle.tscn").instantiate()
				v9.setup_vehicle("vehicle", vname, state)
				ctx.add_child(v9)
				v9._build_frames()
				for d in 8:
					v9._last_dir = d
					v9._layer_dir = d
					v9._update_layer_transform()
					var hull_tex: Texture2D = null
					if v9.sprite.sprite_frames and v9.sprite.sprite_frames.has_animation(("base" if state == 1 else "empty") + "_%d" % d):
						hull_tex = v9.sprite.sprite_frames.get_frame_texture(("base" if state == 1 else "empty") + "_%d" % d, 0)
					var layer_tex: Texture2D = null
					if v9._layer and v9._layer.sprite_frames:
						var lname := "arm_%d" % d if vname == "crane" else "turret_%d" % d
						if v9._layer.sprite_frames.has_animation(lname):
							layer_tex = v9._layer.sprite_frames.get_frame_texture(lname, 0)
					lines.append("%s state=%d d=%d hull=%s layer=%s layer_pos=%s" % [
						vname, state, d,
						"%dx%d" % [hull_tex.get_width(), hull_tex.get_height()] if hull_tex else "NONE",
						"%dx%d" % [layer_tex.get_width(), layer_tex.get_height()] if layer_tex else "NONE",
						v9._layer.position if v9._layer else Vector2.INF])
				v9.remove_from_group(Groups.UNITS)  # deferred frees must not eat pop cap
				v9.queue_free()
		var pose_missing := 0
		for line in lines:
			if "NONE" in String(line):
				pose_missing += 1
			print("POSE ", line)
		# ASSERTED: this printed the word FAIL, which is NOT the
		# `CHECK FAILED:` string the documented pass criterion greps for,
		# so a real regression here read as a passing run.
		var po := TestRig.start("POSESUM")
		po.check(pose_missing == 0,
			"%d of %d hardware poses have no turret/arm layer art" % [
				pose_missing, lines.size()])
		po.finish("lines=%d" % lines.size())
	if "--level-test" in args:
		TestLevers.fast_build = true  # real build times are 72-373s
		# building levels gate the build roster (original zbuildlist) and
		# speed up production; forts build robots AND vehicles AND cannons
		var lproblems: Array[String] = []
		var fort_l0: FortBuilding = FortBuilding.new()
		fort_l0.level = 0
		if fort_l0.build_options() != ["robot:grunt", "vehicle:jeep",
				"vehicle:crane", "cannon:gatling"]:
			lproblems.append("fort L0 roster wrong: %s" % fort_l0.build_options())
		fort_l0.level = 4
		var opts4: Array = fort_l0.build_options()
		if not "vehicle:heavy" in opts4 or not "cannon:missile_cannon" in opts4:
			lproblems.append("fort L4 missing heavy/missile_cannon")
		if "vehicle:missile_launcher" in opts4:
			lproblems.append("fort L4 must not have missile_launcher yet")
		var vf := VehicleFactory.new()
		vf.level = 5
		var vopts: Array = vf.build_options()
		if not "vehicle:missile_launcher" in vopts or not "cannon:missile_cannon" in vopts:
			lproblems.append("vehicle factory L5 roster wrong")
		var rf := RobotFactory.new()
		rf.level = 0
		if rf.build_options() != ["robot:grunt", "cannon:gatling"]:
			lproblems.append("robot factory L0 roster wrong")
		# original BuildTimeModified: -50% at full zone control, +125% at
		# near-death, LEVEL never speeds builds up
		fort_l0.team = MatchState.current.player_team
		fort_l0.owner_team = fort_l0.team
		fort_l0.hp = fort_l0.max_hp
		var zones_owned_l := 0
		for z6 in MatchState.current.zones:
			if z6.owner_team == fort_l0.team:
				zones_owned_l += 1
		var want_mult := 1.0 - 0.5 * float(zones_owned_l) / float(maxi(MatchState.current.zones.size(), 1))
		if not is_equal_approx(fort_l0.build_time_mult(), want_mult):
			lproblems.append("build time mult wrong")
		fort_l0.queue_free()
		vf.queue_free()
		rf.queue_free()
		# end to end: a fort building a jeep delivers it UNMANNED, a
		# gatling spawns as an unmanned cannon
		var fort_lv: FortBuilding = null
		for c4 in ctx.get_children():
			if c4 is FortBuilding and c4.team == MatchState.current.player_team:
				fort_lv = c4
				break
		if fort_lv:
			fort_lv.level = 5
			MatchState.current.set_money(MatchState.current.player_team, 9999)
			# the sandbox roster can start above the base cap — hand the
			# player some zones for headroom before producing
			for z5 in MatchState.current.zones:
				z5.owner_team = MatchState.current.player_team
			var units_before := tree.get_nodes_in_group(Groups.UNITS).size()
			if not fort_lv.queue_unit("vehicle:jeep"):
				lproblems.append("fort refused to build a jeep")
			if not fort_lv.queue_unit("cannon:gatling"):
				lproblems.append("fort refused to build a gatling")
			for i in 120:
				fort_lv._process(0.5)
			var new_units := tree.get_nodes_in_group(Groups.UNITS).size() - units_before
			var unmanned := 0
			for u9 in tree.get_nodes_in_group(Groups.UNITS):
				if u9 is Vehicle2D and not u9.manned:
					unmanned += 1
			if new_units < 2:
				lproblems.append("fort produced %d/2 items" % new_units)
			elif unmanned < 2:
				lproblems.append("fort hardware spawned manned (want unmanned)")
		else:
			lproblems.append("no player fort on this map")
		var level_rig := TestRig.start("LEVEL")
		for problem in lproblems:
			level_rig.check(false, String(problem))
		level_rig.finish()
	if "--repair-test" in args:
		# repair shop heals a damaged vehicle; a crane rebuilds a
		# damaged building; a blown bridge becomes impassable and is
		# restored by the crane
		var rproblems: Array[String] = []
		var shop: Building2D = Building2D.new()
		shop.setup(3, MatchState.current.player_team, "desert", 0)
		shop.position = Vector2(600, 600)
		ctx.add_child(shop)
		# the shop must be discoverable through the order pipeline —
		# the old group scans never found it (dead repair bay)
		if Commands._find_interactable_building(
				shop.art_world_rect().get_center()) != shop:
			rproblems.append("repair shop not discoverable by commands")
		for z in MatchState.current.zones:
			if z.world_rect().has_point(Vector2(632, 624)) \
					or z.world_rect().has_point(Vector2(732, 624)):
				z.set_owner_team(MatchState.current.player_team)
		var wrecked_jeep: Vehicle2D = load("res://scenes/vehicle.tscn").instantiate()
		wrecked_jeep.setup_vehicle("vehicle", "jeep", MatchState.current.player_team)
		wrecked_jeep.position = Vector2(630, 640)
		ctx.add_child(wrecked_jeep)
		wrecked_jeep.take_damage(50)
		wrecked_jeep.issue_order(Order.for_target(shop))
		for i in 60:
			wrecked_jeep._process(0.1)
			wrecked_jeep._physics_process(0.1)
			shop._process(0.1)
		if wrecked_jeep.hp < wrecked_jeep.max_hp:
			rproblems.append("jeep not repaired: %d/%d" % [wrecked_jeep.hp, wrecked_jeep.max_hp])
		if not wrecked_jeep.visible or not wrecked_jeep.is_in_group(Groups.UNITS):
			rproblems.append("jeep never left the shop")
		# crane repairs a damaged radar
		var radar2: Building2D = Building2D.new()
		radar2.setup(2, MatchState.current.player_team, "desert", 0)
		radar2.position = Vector2(700, 600)
		ctx.add_child(radar2)
		radar2.max_hp = 500
		radar2.hp = 200
		var crane2: Vehicle2D = load("res://scenes/vehicle.tscn").instantiate()
		crane2.setup_vehicle("vehicle", "crane", MatchState.current.player_team)
		crane2.position = Vector2(700, 640)
		ctx.add_child(crane2)
		crane2.issue_order(Order.for_target(radar2))
		for i in 80:
			crane2._process(0.1)
			crane2._physics_process(0.1)
			radar2._process(0.1)
		if radar2.hp < radar2.max_hp:
			rproblems.append("radar not rebuilt: %d/%d" % [radar2.hp, radar2.max_hp])
		# bridge: blow it up -> cells solid; crane restores
		var bridge: Building2D = null
		for c5 in ctx.get_children():
			if c5 is Building2D and c5.is_bridge():
				bridge = c5
				break
		if bridge and not bridge.bridge_cells.is_empty():
			bridge.take_damage(9999)
			var solid_after := true
			for cell in bridge.bridge_cells:
				if NavWorld.current.nav_grid and not NavWorld.current.nav_grid.is_point_solid(cell):
					solid_after = false
			if not solid_after:
				rproblems.append("destroyed bridge still passable")
			crane2._start_crane_repair(bridge)
			for i in 200:
				crane2._process(0.1)
				crane2._physics_process(0.1)
			if bridge.hp < bridge.max_hp:
				rproblems.append("bridge not rebuilt: %d/%d" % [bridge.hp, bridge.max_hp])
			var open_after := true
			for cell in bridge.bridge_cells:
				if NavWorld.current.nav_grid and NavWorld.current.nav_grid.is_point_solid(cell):
					open_after = false
			if not open_after:
				rproblems.append("repaired bridge still impassable")
			# the rubble physics wall must be gone with the nav solids —
			# grids saying walkable while move_and_slide still collides
			# jams every unit sent across
			if bridge._body != null:
				rproblems.append("repaired bridge keeps its rubble wall")
		else:
			rproblems.append("no bridge on this map")
		var repair_rig := TestRig.start("REPAIR")
		for problem in rproblems:
			repair_rig.check(false, String(problem))
		repair_rig.finish()
	if "--combat2-test" in args:
		# sniping ejects drivers, grenade crates arm throwers, splash
		# crumbles rocks and cracks bridges, garrisoned forts fire
		var cproblems: Array[String] = []
		# --- sniping: a sniper vs a freshly-fired tank ---
		var tank3: Vehicle2D = load("res://scenes/vehicle.tscn").instantiate()
		tank3.setup_vehicle("vehicle", "light", 2)
		tank3.position = Vector2(500, 700)
		ctx.add_child(tank3)
		var sniper3: Unit2D = load("res://scenes/unit.tscn").instantiate()
		sniper3.unit_name = "sniper"
		sniper3.team = 1
		sniper3.position = Vector2(540, 700)
		ctx.add_child(sniper3)
		tank3._lid_timer = 1.0  # hatch open: snipe window
		var ejected := false
		for i in 200:
			sniper3._process(0.1)
			if not is_instance_valid(tank3):
				break  # sniper chose to destroy it outright instead
			tank3._process(0.1)
			if not tank3.alive:
				break
			if not tank3.manned:
				ejected = true
				break
		if ejected and is_instance_valid(tank3) and tank3.driver_type != "":
			cproblems.append("driver type not cleared on eject")
		# --- grenades: armed robot throws at a vehicle ---
		var target_tank: Vehicle2D = load("res://scenes/vehicle.tscn").instantiate()
		target_tank.setup_vehicle("cannon", "missile_cannon", 2)  # stationary: the AI can't drive it off
		target_tank.position = Vector2(830, 700)
		ctx.add_child(target_tank)
		var gren: Unit2D = load("res://scenes/unit.tscn").instantiate()
		gren.unit_name = "grunt"
		gren.team = 1
		gren.position = Vector2(800, 700)
		ctx.add_child(gren)
		gren.grenades = 2
		# isolate: earlier tests leave enemy units roaming that would
		# steal the grenade target — clear the neighbourhood
		for u10 in tree.get_nodes_in_group(Groups.UNITS):
			if u10 is Unit2D and u10.alive and u10.team == 2 \
					and u10 != target_tank and u10.global_position.distance_to(gren.position) < 300.0:
				u10.alive = false
				u10.remove_from_group(Groups.UNITS)
				u10.queue_free()
		var hp_before := target_tank.hp
		var gren_threw := false
		var tank_hurt := false
		for i in 200:
			# live combat: either side may die (the cannon's missiles
			# one-shot a grunt) — never drive a freed instance
			if is_instance_valid(gren) and gren.alive:
				gren._process(0.1)
				gren_threw = gren_threw or gren.grenades < 2
			if is_instance_valid(target_tank):
				if target_tank.alive:
					target_tank._process(0.1)
					tank_hurt = tank_hurt or target_tank.hp < hp_before
				else:
					tank_hurt = true
			if not is_instance_valid(gren) or not gren.alive:
				break
			if i % 4 == 0:
				await Engine.get_main_loop().process_frame  # grenade in flight
		# let in-flight shells land before judging (live combat may kill
		# the thrower first — the grenade keeps flying regardless)
		for w in 90:
			await Engine.get_main_loop().process_frame
			if is_instance_valid(target_tank) and target_tank.alive \
					and target_tank.hp < hp_before:
				tank_hurt = true
		if not gren_threw:
			cproblems.append("grenade never thrown")
		if not tank_hurt:
			cproblems.append("grenade did no damage")
		# --- area damage crumbles a rock ---
		var rock_found := false
		var rock_cleared := false
		var rocks := tree.get_nodes_in_group(Groups.ROCKS)
		if not rocks.is_empty():
			rock_found = true
			var rock: Node2D = rocks[0]
			var cell := Vector2i(((rock.global_position - Vector2(8, 8)) / 16.0).floor())
			Combat.area_damage(rock.global_position, 40.0, 99, 0)
			await Engine.get_main_loop().process_frame
			rock_cleared = not is_instance_valid(rock) and \
				(not NavWorld.current.nav_grid or not NavWorld.current.nav_grid.is_point_solid(cell))
			if not rock_cleared:
				cproblems.append("rock not destroyed/cleared by blast")
		# --- garrison: robots inside make the fort shoot missiles ---
		var fort_g: FortBuilding = null
		for c6 in ctx.get_children():
			if c6 is FortBuilding and c6.team == MatchState.current.player_team:
				fort_g = c6
				break
		if fort_g:
			var rb: Unit2D = load("res://scenes/unit.tscn").instantiate()
			rb.unit_name = "grunt"
			rb.team = MatchState.current.player_team
			rb.position = fort_g.visual_center()
			ctx.add_child(rb)
			if not fort_g.garrison_robot(rb):
				cproblems.append("garrison refused a robot")
			var enemy_g: Unit2D = load("res://scenes/unit.tscn").instantiate()
			enemy_g.unit_name = "grunt"
			enemy_g.team = 2
			enemy_g.position = fort_g.visual_center() + Vector2(90, 0)
			ctx.add_child(enemy_g)
			var ehp := enemy_g.hp
			for i in 240:
				fort_g._process(0.1)
				await Engine.get_main_loop().process_frame  # let the missile fly
			# freed/dead means the missile killed it — that IS the fort firing
			if is_instance_valid(enemy_g) and enemy_g.alive and enemy_g.hp >= ehp:
				cproblems.append("garrisoned fort never fired")
		else:
			cproblems.append("no player fort")
		if not rock_found:
			cproblems.append("no rocks on this map")
		var combat2_rig := TestRig.start("COMBAT2")
		for problem in cproblems:
			combat2_rig.check(false, String(problem))
		combat2_rig.finish()
	if "--tactics-test" in args:
		TestLevers.fast_build = true  # real build times are 72-373s
		# the tactical AI, end to end: with funds and hardware on the
		# map it must produce units, man empty vehicles/cannons and
		# take zones — not just charge the enemy fort
		var ai2: CpuAi = null
		for c2 in ctx.get_children():
			if c2 is CpuAi and c2.team != MatchState.current.player_team:
				ai2 = c2
				break
		if ai2 == null:
			print("TACTICS: no cpu ai found")
		else:
			MatchState.current.set_money(ai2.team, 2000)
			var t := ai2.team
			var count := func() -> Dictionary:
				var robots2 := 0
				var manned2 := 0
				var zones2 := 0
				for u3 in tree.get_nodes_in_group(Groups.UNITS):
					if u3 is Unit2D and u3.alive and u3.team == t:
						if u3 is Vehicle2D:
							if u3.manned:
								manned2 += 1
						elif u3.kind == "robot":
							robots2 += 1
				for z3 in MatchState.current.zones:
					if z3.owner_team == t:
						zones2 += 1
				return {"robots": robots2, "manned": manned2, "zones": zones2}
			var before_t: Dictionary = count.call()
			var manned_peak := 0
			var empty_start := 0
			for u4 in tree.get_nodes_in_group(Groups.UNITS):
				if u4 is Vehicle2D and not u4.manned:
					empty_start += 1
			# simulate a few minutes: think cycles + factory, unit and
			# zone time (units must walk, capture zones, board hardware)
			for i in 40:
				MatchState.current.set_money(t, 2000)
				ai2._think()
				for c3 in ctx.get_children():
					if c3 is RobotFactory or c3 is VehicleFactory or c3 is FortBuilding:
						for j in 8:
							c3._process(0.5)
				for u6 in tree.get_nodes_in_group(Groups.UNITS):
					if u6 is Unit2D and u6.alive:
						for j in 8:
							u6._process(0.5)
							u6._physics_process(0.5)
				for z4 in MatchState.current.zones:
					for j in 8:
						z4._process(0.2)
				manned_peak = maxi(manned_peak, int(count.call().manned))
			var after_t: Dictionary = count.call()
			var man_orders := 0
			var dbg := ""
			for u5 in tree.get_nodes_in_group(Groups.UNITS):
				if u5 is Unit2D and u5.team == t and u5.kind == "robot" \
						and u5.enter_target != null:
					man_orders += 1

			# the three legs of the tactical loop, each asserted: it must
			# PRODUCE, it must CREW the hardware lying around, and it must
			# hold territory. (A brain that only charges the enemy fort
			# passes none of these.)
			var tac_rig := TestRig.start("TACTICS")
			tac_rig.check(int(after_t.robots) > int(before_t.robots),
				"the AI produced no robots in ~3 simulated minutes (%d -> %d)"
				% [int(before_t.robots), int(after_t.robots)])
			if empty_start > 0:
				tac_rig.check(manned_peak > int(before_t.manned) or man_orders > 0,
					"%d empty hulls on the map and the AI never crewed or "
					% empty_start + "even ordered a robot onto one")
			tac_rig.check(int(after_t.zones) > 0,
				"the AI holds no territory after the sim")
			tac_rig.finish("robots %d->%d manned_peak=%d zones=%d%s" % [
				int(before_t.robots), int(after_t.robots), manned_peak,
				int(after_t.zones), dbg])
	if "--near-test" in args:
		var jeep3: Vehicle2D = load("res://scenes/vehicle.tscn").instantiate()
		jeep3.setup_vehicle("vehicle", "jeep", 0)
		jeep3.position = Vector2(700, 700)
		ctx.add_child(jeep3)
		var walker: Unit2D = load("res://scenes/unit.tscn").instantiate()
		walker.team = 1
		walker.position = Vector2(500, 700)
		ctx.add_child(walker)
		# the player's unit stays selected while it walks in to man the
		# vehicle — it must leave the selection when consumed (regression:
		# freed robot lingered in the selection bar)
		SelectionManager.current.clear_selection()
		SelectionManager.current.toggle_select(walker, false)
		walker.issue_order(Order.for_target(jeep3))
		var instant: bool = jeep3.manned  # must NOT be manned before walking
		for i in 400:
			walker._process(0.05)
			walker._physics_process(0.05)
			if jeep3.manned or not is_instance_valid(walker):
				break
		var near_rig := TestRig.start("NEAR")
		near_rig.check(not instant, "hardware was manned from 200px away")
		near_rig.check(jeep3.manned, "the robot never crewed the jeep it walked to")
		near_rig.check(SelectionManager.current.selected.is_empty(),
			"the consumed robot is still selected (%d entries)"
			% SelectionManager.current.selected.size())
		near_rig.finish()
	if "--flag-test" in args:
		var fl := TestRig.start("FLAG")
		var radar: Building2D = Building2D.new()
		radar.setup(2, 0, "desert")
		var zr: Node2D = MatchState.current.zones[0]
		radar.position = zr.position + zr.world_rect().get_center()
		ctx.add_child(radar)
		zr.owner_team = MatchState.current.player_team
		radar._process(0.0)
		fl.check(radar.team == MatchState.current.player_team,
			"a building in an owned zone did not follow its owner (%d, want %d)" % [
				radar.team, MatchState.current.player_team])
		radar.queue_free()
		# ZONE FLAG DATA (map_item id 0): the loader used to drop all 956
		# of these markers, so every flag stood at a derived centre spot
		# and every map opened fully neutral. Every non-fort zone carries
		# exactly one, and the owner byte is authored per map.
		var forts := 0
		for b in ctx.get_tree().get_nodes_in_group(Groups.BUILDINGS):
			if b is FortBuilding and b.alive:
				forts += 1
		var authored := 0
		var pre_owned := 0
		for z in MatchState.current.zones:
			if z.flag_tile != Vector2i.MAX:
				authored += 1
				fl.check(z.zone_rect.has_point(z.flag_tile),
					"zone flag tile %s sits outside its own zone %s" % [
						z.flag_tile, z.zone_rect])
			if z.owner_team != 0:
				pre_owned += 1
		var expect := MatchState.current.zones.size() - forts
		# 57 of the 58 shipped maps carry one id-0 marker per non-fort
		# zone; the hand-authored sandbox map carries none at all. So the
		# rule is all-or-nothing: if a map ships markers, EVERY non-fort
		# zone must have got one (a partial count means the loader dropped
		# some again).
		fl.check(authored == 0 or authored >= expect,
			"only %d of %d non-fort zones got their authored flag tile" % [
				authored, expect])
		fl.finish("authored_flags=%d pre_owned_zones=%d forts=%d" % [
			authored, pre_owned, forts])
	if "--pickup-test" in args:
		# quiet corner + overkill HP: the live map's wanderers must not
		# steal the crate or kill the collector before the check runs.
		# ASSERTED (this block used to only print): crate effects were
		# dead data — `upgrade_key` was unset on both defs, so no upgrade
		# was ever granted and no damage multiplier existed at all.
		var pu := TestRig.start("PICKUP")
		var team: int = 1
		MatchState.current.upgrades.erase(team)
		var robot_mult_before: float = MatchState.current.damage_multiplier(team, "robot")
		var hw_mult_before: float = MatchState.current.damage_multiplier(team, "vehicle")
		pu.check(is_equal_approx(robot_mult_before, 1.0)
				and is_equal_approx(hw_mult_before, 1.0),
			"a team with no crates already has a damage bonus (%.2f/%.2f)" % [
				robot_mult_before, hw_mult_before])

		# 1. a ROBOT opens a grenade crate: throwables + the team upgrade.
		# The collector is PLACED on the crate rather than walked to it —
		# this block checks crate SEMANTICS, and every other block in this
		# file mutates the same world, so a walk here depended on which
		# flags ran first (the cursor block uses the same corner).
		# ...and the spot must be clear of OTHER units: whichever unit the
		# group scan reaches first opens the crate, and earlier blocks in
		# this file park fixtures on shared coordinates (the cursor block
		# leaves a team-2 robot on this very corner), so a stray neighbour
		# would collect it for the wrong team.
		var crate_spot := Vector2.INF
		for probe in [Vector2(2400, 3080), Vector2(2000, 2600),
				Vector2(1600, 3400), Vector2(2800, 2200), Vector2(1200, 2000)]:
			var cand := NavWorld.current.find_free_spot(probe, "robot")
			if cand == Vector2.INF:
				continue
			var crowded := false
			for other in UnitRegistry.current.world_units():
				if other.global_position.distance_to(cand) < 48.0:
					crowded = true
					break
			if not crowded:
				crate_spot = cand
				break
		pu.check(crate_spot != Vector2.INF, "no clear, unoccupied crate spot on this map")
		if crate_spot == Vector2.INF:
			crate_spot = Vector2(2400, 3080)
		var pk := Pickup.new()
		pk.pickup_type = "grenades"
		pk.position = crate_spot
		ctx.add_child(pk)
		var collector: Unit2D = load("res://scenes/unit.tscn").instantiate()
		collector.team = team
		collector.position = crate_spot
		collector.hp = 10000000
		collector.max_hp = 10000000
		ctx.add_child(collector)
		var grenades_before: int = collector.grenades
		for i in 20:
			collector._process(0.05)
			if not pk._taken:
				pk._process(0.05)
			else:
				break
		pu.check(collector.grenades > grenades_before,
			"grenade crate armed no throwables (%d -> %d)" % [
				grenades_before, collector.grenades])
		pu.check(MatchState.current.has_upgrade(team, "grenades"),
			"grenade crate granted no team upgrade")
		pu.check(is_equal_approx(MatchState.current.damage_multiplier(team, "robot"),
				1.0 + ContentDB.rules.grenade_damage_bonus),
			"robot damage multiplier did not follow the grenade upgrade (%.2f)"
				% MatchState.current.damage_multiplier(team, "robot"))

		# 2. a ROCKET crate is HARDWARE-only: a robot must walk over it
		var rk := Pickup.new()
		rk.pickup_type = "rockets"
		rk.position = collector.global_position
		ctx.add_child(rk)
		for i in 20:
			collector._process(0.05)
			if not rk._taken:
				rk._process(0.05)
			else:
				break
		pu.check(not rk._taken,
			"a robot consumed a rockets crate (hardware-only) and wasted it")
		pu.check(not MatchState.current.has_upgrade(team, "rockets"),
			"a robot granted the team the ROCKET upgrade")

		# 3. hardware opens it: the upgrade lands, no grenades are given.
		# Placed ON the crate rather than driven to it — this checks crate
		# SEMANTICS, and the surrounding terrain is not guaranteed to be
		# drivable (a jeep needs the vehicle grid).
		var truck_spot := NavWorld.current.find_free_spot(rk.position, "vehicle")
		if truck_spot == Vector2.INF:
			truck_spot = rk.position
		rk.position = truck_spot
		var truck: Vehicle2D = Spawner.spawn(ctx, "vehicle", "jeep", team,
			truck_spot, true) as Vehicle2D
		if truck == null:
			pu.check(false, "could not spawn a manned jeep for the rockets crate")
		else:
			truck.hp = 10000000
			truck.max_hp = 10000000
			for i in 20:
				truck._process(0.05)
				if is_instance_valid(rk):
					rk._process(0.05)
				else:
					break
			pu.check(rk._taken, "hardware never collected the rockets crate")
			pu.check(MatchState.current.has_upgrade(team, "rockets"),
				"rockets crate granted no team upgrade to hardware")
			pu.check(is_equal_approx(
					MatchState.current.damage_multiplier(team, "vehicle"),
					1.0 + ContentDB.rules.rocket_damage_bonus),
				"vehicle damage multiplier did not follow the rocket upgrade (%.2f)"
					% MatchState.current.damage_multiplier(team, "vehicle"))
			truck.queue_free()
		collector.queue_free()
		if is_instance_valid(rk):
			rk.queue_free()
		MatchState.current.upgrades.erase(team)
		pu.finish()
	if "--prod-test" in args:
		TestLevers.fast_build = true  # real build times are 72-373s
		var f2: RobotFactory = null
		for c in ctx.get_children():
			if c is RobotFactory:
				f2 = c
				break
		if f2:
			var zone_hit: Node2D = null
			for z3 in MatchState.current.zones:
				if z3.world_rect().has_point(f2.world_footprint().get_center()):
					zone_hit = z3
					break
			if zone_hit:
				zone_hit.owner_team = MatchState.current.player_team
				MatchState.current.set_money(MatchState.current.player_team, 500)
				f2._process(0.1)  # sync owner from zone before queueing
				var ok: bool = f2.queue_unit("robot:psycho")
				var count_before := tree.get_nodes_in_group(Groups.UNITS).size()
				for i in 40:
					f2._process(0.5)
				var psychos := 0
				for u3 in tree.get_nodes_in_group(Groups.UNITS):
					if u3 is Unit2D and u3.unit_name == "psycho" and u3.team == MatchState.current.player_team:
						psychos += 1
				var prod_rig := TestRig.start("PROD")
				prod_rig.check(ok, "the factory refused a funded order")
				prod_rig.check(psychos > 0, "no psycho rolled out of the factory")
				prod_rig.check(tree.get_nodes_in_group(Groups.UNITS).size() > count_before,
					"unit count did not grow (%d)" % count_before)
				prod_rig.check(f2.queue.items.is_empty(),
					"queue still holds %d item(s)" % f2.queue.items.size())
				prod_rig.finish("psychos=%d" % psychos)
	if "--fortprod-test" in args:
		TestLevers.fast_build = true  # real build times are 72-373s
		var fort2: FortBuilding = null
		for c in ctx.get_children():
			if c is FortBuilding and c.team == MatchState.current.player_team:
				fort2 = c
				break
		if fort2:
			MatchState.current.set_money(1, 500)
			var ok2: bool = fort2.queue_unit("robot:psycho")
			for i in 8:
				fort2.queue_unit("robot:grunt")
			var fp_rig := TestRig.start("FORTPROD")
			fp_rig.check(fort2.queue.items.size() == 5,
				"queue holds %d, the cap is 5" % fort2.queue.items.size())
			for i in 4:  # cancel only the grunts, keep the psycho
				fort2.cancel_at(fort2.queue.items.size() - 1)
			var count0 := tree.get_nodes_in_group(Groups.UNITS).size()
			for i in 40:
				fort2._process(0.5)
			var psychos2 := 0
			for u5 in tree.get_nodes_in_group(Groups.UNITS):
				if u5 is Unit2D and u5.unit_name == "psycho" and u5.team == 1:
					psychos2 += 1
			fp_rig.check(ok2, "the fort refused a funded order")
			fp_rig.check(psychos2 > 0, "the fort produced no psycho")
			# fort cannon SLOTS: guns mount on the tower points, capped by
			# the slot count (no unlimited turret spam)
			var accepted := 0
			for i in 6:
				if fort2.queue_unit("cannon:gatling", true):
					accepted += 1
			for i in 40:
				fort2._process(0.5)
			var mounted_guns := 0
			var on_slot := 0
			var fort_slots: Array = fort2.cannon_slots()
			for u6 in tree.get_nodes_in_group(Groups.UNITS):
				if u6 is Vehicle2D and u6.kind == "cannon" and u6.team == 1:
					mounted_guns += 1
					for s in fort_slots:
						if u6.global_position.distance_to(s) < 4.0:
							on_slot += 1
							break
			fp_rig.check(accepted == fort_slots.size(),
				"fort took %d gun orders for %d tower slots"
				% [accepted, fort_slots.size()])
			fp_rig.check(mounted_guns > 0, "no tower gun was mounted")
			fp_rig.check(on_slot == mounted_guns,
				"%d of %d tower guns stand off their slot" % [
					mounted_guns - on_slot, mounted_guns])
			fp_rig.check(fort2.free_cannon_slots() == 0,
				"%d slots still free after filling them" % fort2.free_cannon_slots())
			fp_rig.finish("guns=%d" % mounted_guns)
	if "--cancel-test" in args:
		var fort3: FortBuilding = null
		for c in ctx.get_children():
			if c is FortBuilding and c.team == MatchState.current.player_team:
				fort3 = c
				break
		if fort3:
			MatchState.current.set_money(1, 500)
			fort3.queue_unit("robot:grunt")
			fort3.queue_unit("robot:sniper")
			var money_mid: int = MatchState.current.money[1]
			fort3.cancel_at(1)  # refund the sniper ($80)
			var cancel_rig := TestRig.start("CANCEL")
			var refund: int = int(MatchState.current.money[1]) - money_mid
			cancel_rig.check(refund > 0,
				"cancelling refunded nothing (money %d -> %d)"
				% [money_mid, int(MatchState.current.money[1])])
			cancel_rig.check(fort3.queue.items.size() == 1,
				"cancel left %d items, want 1" % fort3.queue.items.size())
			cancel_rig.check(String(fort3.queue.items[0]) == "robot:grunt",
				"cancel removed the wrong item (%s left)" % fort3.queue.items[0])
			cancel_rig.finish("refund=%d" % refund)
	if "--vehpath-test" in args:
		var rg: AStarGrid2D = NavWorld.current.nav_grid
		var vg: AStarGrid2D = NavWorld.current.vehicle_grid
		var water_cell := Vector2i(-1, -1)
		for y in rg.region.size.y:
			for x in rg.region.size.x:
				var c2 := Vector2i(x, y)
				if not rg.is_point_solid(c2) and vg.is_point_solid(c2):
					water_cell = c2
					break
			if water_cell.x >= 0:
				break
		var vp_rig := TestRig.start("VEHPATH")
		if water_cell.x < 0:
			print("VEHPATH: no water cells on this map")
		else:
			var water_px := Vector2(water_cell) * 16.0 + Vector2(8, 8)
			var start: Vector2i = NavWorld.current._open_cell(Vector2i(((water_px + Vector2(200, 0)) / 16.0).floor()), rg)
			var rpath := NavWorld.current.request_path(water_px + Vector2(200, 0), water_px, "robot")
			var vpath := NavWorld.current.request_path(water_px + Vector2(200, 0), water_px, "vehicle")
			var vehicle_refused: bool = vpath.is_empty()
			var vends_on_water: bool = not vehicle_refused \
				and vg.is_point_solid(Vector2i((vpath[vpath.size() - 1] / 16.0).floor()))
			vp_rig.check(start.x >= 0, "no open start cell beside the water")
			# a robot may legitimately fail to reach a given water cell
			# (walls, an island, the probe start inside a building), so
			# THE contract asserted here is the wheels one: a vehicle
			# route must never end in the water
			vp_rig.check(not vends_on_water,
				"a VEHICLE route ended on a water cell")
			print("VEHPATH: robot_route=%s vehicle_refused=%s"
				% [not rpath.is_empty(), vehicle_refused])
		# bridges must be walkable for wheels: no bridge SPAN cell solid in vgrid
		var blocked_bridges := 0
		var total_bridge_cells := 0
		for b in _all_nodes(ctx):
			if b is Building2D and (b.building_id == 6 or b.building_id == 7):
				var tile := Vector2i(((b.global_position - Vector2(8, 8)) / 16.0).floor())
				var span: Vector2i = ContentDB.building_def(b.building_id).bridge_span
				# the object tile is the span's TOP-LEFT (map anchor
				# contract) — the span grows right/down, no centring
				for bx2 in span.x:
					for by2 in span.y:
						var cell := tile + Vector2i(bx2, by2)
						total_bridge_cells += 1
						if vg.is_point_solid(cell):
							blocked_bridges += 1
		vp_rig.check(total_bridge_cells > 0, "no bridge cells on this map")
		vp_rig.check(blocked_bridges == 0,
			"%d of %d bridge cells are solid on the VEHICLE grid — wheels "
			% [blocked_bridges, total_bridge_cells]
			+ "cannot cross their own road")
		vp_rig.finish("bridge cells=%d" % total_bridge_cells)
	if "--apc-test" in args:
		var apc2: Vehicle2D = load("res://scenes/vehicle.tscn").instantiate()
		apc2.setup_vehicle("vehicle", "apc", 1)
		apc2.position = Vector2(300, 300)
		ctx.add_child(apc2)
		var robot1: Unit2D = load("res://scenes/unit.tscn").instantiate()
		robot1.team = 1
		robot1.position = Vector2(300, 300)
		ctx.add_child(robot1)
		var loaded: bool = apc2.load_robot(robot1)
		var hidden: bool = not robot1.visible and robot1.carried
		apc2.move_to(Vector2(500, 500))
		for i in 400:
			apc2._process(0.05)
			apc2._physics_process(0.05)
			if not apc2.has_move_target():
				break
		var unloaded_near: bool = robot1.visible and not robot1.carried \
			and robot1.global_position.distance_to(apc2.global_position) < 60.0
		var apc_rig := TestRig.start("APC")
		apc_rig.check(loaded, "the APC refused a passenger")
		apc_rig.check(hidden, "a boarded robot is still visible in the world")
		apc_rig.check(not apc2.has_move_target(), "the APC never arrived")
		apc_rig.check(unloaded_near,
			"the squad did not step out at the destination")
		apc_rig.finish()
	if "--save-test" in args:
		MatchState.current.set_money(1, 321)
		MatchState.current.zones[0].set_owner_team(1)
		var saved: bool = GameState.save_game()
		var snapshot: Dictionary = GameState.read_save()
		MatchState.current.set_money(1, 0)
		MatchState.current.zones[0].set_owner_team(0)
		GameState.pending_load = snapshot
		ctx._apply_load()
		var save_rig := TestRig.start("SAVE")
		save_rig.check(saved, "save_game() refused to write")
		save_rig.check(int(MatchState.current.money[1]) == 321,
			"money restored as %d, saved 321" % int(MatchState.current.money[1]))
		save_rig.check(MatchState.current.zones[0].owner_team == 1,
			"zone owner restored as %d, saved 1"
			% MatchState.current.zones[0].owner_team)
		save_rig.check(not snapshot.get("units", []).is_empty(),
			"the save carries no units")
		save_rig.finish("units=%d" % snapshot.get("units", []).size())
	if "--campaign-test" in args:
		# snapshot the player's real progress first — advance() PERSISTS,
		# and a test run must never leave the campaign stuck on a later
		# mission (the 'we never start with the first mission' bug)
		var progress_backup := PackedByteArray()
		if FileAccess.file_exists(Campaign.PROGRESS_PATH):
			progress_backup = FileAccess.get_file_as_bytes(Campaign.PROGRESS_PATH)
		Campaign.start(false)
		var first: String = Campaign.current_map_path()
		var advanced: bool = Campaign.advance()
		Campaign.load_progress()
		var camp_rig := TestRig.start("CAMPAIGN")
		camp_rig.check(Campaign.missions.size() > 0, "the campaign has no missions")
		camp_rig.check(first != "", "no first mission map")
		camp_rig.check(ResourceLoader.exists(first) or FileAccess.file_exists(first),
			"first mission map does not exist: %s" % first)
		camp_rig.check(advanced, "advance() did not move to the next mission")
		camp_rig.check(Campaign.mission == 1,
			"resumed on mission %d after one advance" % Campaign.mission)
		# THE ORIGINAL CHAIN: when the retail levels are installed the
		# campaign must be those 20, in the game's own order — not 57 zod
		# multiplayer maps in alphabetical filename order.
		var retail := 0
		for m in Campaign.missions:
			if String(m).begins_with(MapCatalog.CAMPAIGN_PREFIX):
				retail += 1
		if retail > 0:
			camp_rig.check(retail == Campaign.missions.size(),
				"%d of %d missions are retail levels — the chain is mixed"
				% [retail, Campaign.missions.size()])
			camp_rig.check(Campaign.missions.size() == 20,
				"retail campaign has %d missions, want 20" % Campaign.missions.size())
			var last := 0
			for m in Campaign.missions:
				var num := int(String(m).substr(2, 2))
				camp_rig.check(num > last,
					"mission order breaks at %s (after %02d)" % [m, last])
				last = num
			camp_rig.check(String(Campaign.missions[0]).begins_with("zc01"),
				"the campaign opens on %s" % Campaign.missions[0])
			camp_rig.check(MapCatalog.display_title("zc01_virgin_soldiers")
					== "VIRGIN SOLDIERS",
				"level title reads '%s'" % MapCatalog.display_title(
					"zc01_virgin_soldiers"))
		camp_rig.finish("%d missions (%d retail)" % [
			Campaign.missions.size(), retail])
		Campaign.active = false
		if not progress_backup.is_empty():
			var rf := FileAccess.open(Campaign.PROGRESS_PATH, FileAccess.WRITE)
			if rf:
				rf.store_buffer(progress_backup)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Campaign.PROGRESS_PATH))
	if "--win-test" in args:
		var wproblems: Array[String] = []
		GameState.game_over.connect(func(winner): print("WINNER: %d" % winner))
		# ONE fallen half eliminates the whole team (original
		# CheckDestroyedFort): sibling buildings, every unit, every zone
		# (this map carries 8 single-half teams, so the match continues)
		var fort: FortBuilding = null
		for c in ctx.get_children():
			if c is FortBuilding and c.team == 2:
				fort = c
		if fort == null:
			wproblems.append("no team-2 fort on map")
		else:
			fort.take_damage(fort.hp)
			if fort.alive:
				wproblems.append("half-kill left the fort alive")
			for b2 in ctx.get_tree().get_nodes_in_group(Groups.ALL_BUILDINGS):
				if b2 is Building2D and b2.owner_team == 2 and b2.alive:
					wproblems.append("cascade left a team-2 building")
					break
			if not UnitRegistry.current.of_team(2).is_empty():
				wproblems.append("cascade left team-2 units alive")
			for z in MatchState.current.zones:
				if z.owner_team == 2:
					wproblems.append("cascade left a team-2 zone")
					break
			if GameState.over:
				wproblems.append("match ended with 6 enemy teams alive")
			# no-units rule (original CheckNoUnitsDestroyFort), via the
			# real death hook: team 3's LAST unit falling must take its
			# still-standing fort down with it
			var fort3: FortBuilding = null
			for c in ctx.get_children():
				if c is FortBuilding and c.alive and c.team == 3:
					fort3 = c
			if fort3 == null:
				wproblems.append("no team-3 fort")
			else:
				for u in UnitRegistry.current.of_team(3).duplicate():
					u.die()
				if fort3.alive:
					wproblems.append("no-units rule did not destroy team 3's fort")
			# eliminating every remaining enemy team ends the match in a
			# player win — symmetric for all teams
			for c in ctx.get_children().duplicate():
				if c is FortBuilding and c.alive \
						and c.team not in [0, MatchState.current.player_team]:
					c.take_damage(c.hp)
			if not GameState.over:
				wproblems.append("all enemies eliminated but no game over")
		var win_rig := TestRig.start("WIN")
		for problem in wproblems:
			win_rig.check(false, String(problem))
		win_rig.finish()
	if "--mount-test" in args:
		# every spawnable vehicle/cannon must have a visible manned look
		# (base art, equiped art, or the fire cycle aliased in), neutral
		# art while unmanned (never a team colour), and turrets on tanks
		var no_manned := []
		var team_colored := []
		var no_turret := []
		for kind in ["vehicle", "cannon"]:
			for type_name in ContentDB.defs_of(kind):
				if not ContentDB.has_sprites(kind, String(type_name)):
					continue
				var dir := ContentDB.def_for(kind, String(type_name)).asset_dir
				var frames := AnimLibrary.vehicle_frames(dir, 1)
				if not frames.has_animation("base_0") or frames.get_frame_count("base_0") == 0:
					no_manned.append(String(type_name))
				# unmanned build must resolve neutral empty art
				var empty := AnimLibrary.vehicle_frames(dir, 0)
				if empty.has_animation("empty_0"):
					var path := String(empty.get_frame_texture("empty_0", 0).resource_path)
					for color in ["_red.", "_blue.", "_green.", "_yellow."]:
						if path.ends_with(color):
							team_colored.append("%s (%s)" % [type_name, path.get_file()])
				else:
					team_colored.append("%s (no empty art)" % type_name)
				# tanks carry a turret layer; the jeep gets its gun layer
				var turret: Dictionary = AnimLibrary.turret_set(String(type_name), dir, 1)
				var expect_turret := String(type_name) in ["light", "medium", "heavy", "apc"]
				if expect_turret and (turret.is_empty() or not turret.frames.has_animation("turret_0")):
					no_turret.append(String(type_name))
				if String(type_name) == "jeep":
					if turret.is_empty():
						no_turret.append("jeep (no gun layer)")
					var wheels: Dictionary = AnimLibrary.jeep_wheel_set(dir, 1, true)
					if wheels.is_empty() or not wheels.frames.has_animation("wheels_0"):
						no_turret.append("jeep (no wheel frames)")
		var mount_rig := TestRig.start("MOUNT")
		for entry in no_manned:
			mount_rig.check(false, "no manned art: %s" % entry)
		for entry in team_colored:
			mount_rig.check(false, "unmanned hull wears a team colour: %s" % entry)
		for entry in no_turret:
			mount_rig.check(false, "turret/wheel layer missing: %s" % entry)
		mount_rig.finish()
	if "--cap-test" in args:
		TestLevers.fast_build = true  # real build times are 72-373s
		# unit cap: base 25 + zone bonuses; production refuses beyond it
		var fort: FortBuilding = null
		for c in ctx.get_children():
			if c is FortBuilding and c.team == MatchState.current.player_team:
				fort = c
				break
		if fort:
			MatchState.current.set_money(1, 99999)
			# drive production until the cap refuses everything
			for i in 200:
				fort.queue_unit("robot:grunt")
				fort._process(0.6)
			var cap := MatchState.current.unit_cap(1)
			var used := MatchState.current.unit_pop(1)
			# note: with live CPU opponents the cap moves as zones flip;
			# the invariant is that the queue went full (production
			# refused) — pop may sit above a freshly shrunken cap
			var cap_rig2 := TestRig.start("CAP")
			cap_rig2.check(cap > 0, "unit cap is %d" % cap)
			# AT the cap the fort must REFUSE the order outright (that is
			# what stops the queue growing forever), and population must
			# never overshoot
			cap_rig2.check(not fort.queue_unit("robot:grunt"),
				"the fort accepted an order at pop %d of cap %d" % [used, cap])
			cap_rig2.check(used <= cap,
				"population %d overshot the cap %d" % [used, cap])
			cap_rig2.finish("cap=%d pop=%d" % [cap, used])
	if "--building-test" in args:
		# every building kind: destroyed art resolves and animation
		# overlays (radar dish, factory spinner, smoke stack) exist
		var missing_destroyed := []
		var no_overlay := []
		for id in [2, 3, 4, 5, 0, 1]:
			var def := ContentDB.building_def(id)
			for planet in ["desert", "volcanic", "arctic", "city", "jungle"]:
				var b: Building2D = def.behaviour.new()
				b.setup(id, 0 if id in [6, 7] else 1, planet)
				ctx.add_child(b)
				if not ResourceLoader.exists(b._texture_path(true)):
					missing_destroyed.append("%d/%s" % [id, planet])
				if not def.anims.is_empty() and b.get_node_or_null(
						"Overlay_%s" % def.anims[0].prefix) == null:
					no_overlay.append("%d (%s)" % [id, planet])
				b.queue_free()
		var bld_rig := TestRig.start("BUILDING")
		for entry in missing_destroyed:
			bld_rig.check(false, "no destroyed art: %s" % entry)
		for entry in no_overlay:
			bld_rig.check(false, "animation overlay missing: %s" % entry)
		bld_rig.finish()
		# building geometry: the art is ONE full sprite anchored on the
		# node, the node y-sorts at the art's vertical MIDDLE (the wall
		# base — units in front draw over it, units behind under it) and
		# the footprint equals the def's solid cell rect
		var geo_fails: PackedStringArray = []
		# every non-bridge type declares its solid cells: an empty table
		# means "the whole art rect", and a building's art carries ground,
		# cast shadow and entrances that are not walls (the factories and
		# the repair shop shipped with no table at all)
		for id in [0, 1, 2, 3, 4, 5]:
			var sdef := ContentDB.building_def(id)
			if sdef.solid_tiles.size.x <= 0 or sdef.solid_tiles.size.y <= 0:
				geo_fails.append("%s declares no solid_tiles" % sdef.bname)
		for spec in [[0, "fort_front"], [1, "fort_back"], [2, "radar"],
				[3, "repair"], [4, "robot_factory"], [5, "vehicle_factory"]]:
			var bdef := ContentDB.building_def(spec[0])
			var gb: Building2D = bdef.behaviour.new()
			gb.setup(spec[0], 1, "desert")
			gb.position = Vector2(400.0 + spec[0] * 200.0, 300.0)
			ctx.add_child(gb)
			for i in 3:
				await Engine.get_main_loop().process_frame
			var ts := gb._art_size
			var art := gb.art_world_rect()
			if gb._sprite.texture is AtlasTexture:
				geo_fails.append("%s sprite cropped" % spec[1])
			# sort line: forts sit at their art TOP (zod ground-stamps
			# fort bases — nothing is ever occluded by a fort), every
			# other building at its vertical middle
			var want_sort: float = (art.position.y if gb.is_fort
					else art.get_center().y)
			if absf(want_sort - gb.position.y) > 0.5:
				geo_fails.append("%s sort line %.1f vs want %.1f" % [
					spec[1], gb.position.y, want_sort])
			var want_rect: Rect2i = bdef.solid_tiles \
				if bdef.solid_tiles.size.x > 0 and bdef.solid_tiles.size.y > 0 \
				else Rect2i(Vector2i.ZERO, Vector2i((ts / 16.0).ceil()))
			# the solid rect must sit INSIDE the art (a table that runs
			# past the sprite blocks open ground nothing stands on)
			var art_tiles := Vector2i((ts / 16.0).ceil())
			if want_rect.position.x < 0 or want_rect.position.y < 0 \
					or want_rect.end.x > art_tiles.x or want_rect.end.y > art_tiles.y:
				geo_fails.append("%s solid rect %s outside art %s" % [
					spec[1], want_rect, art_tiles])
			for t in bdef.open_tiles:
				if not want_rect.has_point(Vector2i(t)):  # open cells are art-relative
					geo_fails.append("%s open cell %s outside solid rect" % [
						spec[1], t])
			var cells := gb.footprint_cells()
			var fp := gb.world_footprint()
			if cells.size() != want_rect.get_area() - bdef.open_tiles.size():
				geo_fails.append("%s solid cells %d want %d" % [spec[1], cells.size,
					want_rect.get_area() - bdef.open_tiles.size()])
			if absf(fp.size.x - want_rect.size.x * 16.0) > 0.5 \
					or absf(fp.size.y - want_rect.size.y * 16.0) > 0.5:
				geo_fails.append("%s footprint %s want %s" % [spec[1], fp.size,
					Vector2(want_rect.size) * 16.0])
			if spec[0] == 0:
				# destroyed swap: full art back on the same anchor
				var top_before: float = gb._sprite.global_position.y
				gb.take_damage(gb.hp + 9999)
				if gb._sprite.texture is AtlasTexture:
					geo_fails.append("destroyed fort keeps cropped art")
				elif absf(gb._sprite.global_position.y - top_before) > 0.5:
					geo_fails.append("destroyed fort shifted")
			gb.queue_free()
			var geo_rig := TestRig.start("BUILDINGGEO")
			for gf in geo_fails:
				geo_rig.check(false, String(gf))
			geo_rig.finish(spec[1])
			geo_fails.clear()
		# nav solidity: every placed fort blocks its def's cells on BOTH
		# grids, its open platform cells stay walkable, and a robot path
		# across the fort must detour around the solid cells
		var nav_fails: PackedStringArray = []
		var fort: Building2D = null
		for b in ctx.get_tree().get_nodes_in_group(Groups.BUILDINGS):
			if b is Building2D and b.alive and b.is_fort:
				fort = b
				break
		if fort == null:
			nav_fails.append("no fort on map")
		else:
			for cell in fort.footprint_cells():
				if NavWorld.current.nav_grid.region.has_point(cell) \
						and not NavWorld.current.nav_grid.is_point_solid(cell):
					nav_fails.append("nav open %s" % cell)
				if NavWorld.current.vehicle_grid.region.has_point(cell) \
						and not NavWorld.current.vehicle_grid.is_point_solid(cell):
					nav_fails.append("vgrid open %s" % cell)
			var fdef := ContentDB.building_def(fort.building_id)
			var origin := Vector2i((fort.art_world_rect().position / 16.0).floor())
			var open_walked := 0
			for t in fdef.open_tiles:
				var c := origin + Vector2i(t)
				if NavWorld.current.nav_grid.region.has_point(c) \
						and not NavWorld.current.nav_grid.is_point_solid(c):
					open_walked += 1
			if open_walked == 0:
				nav_fails.append("no open platform cells walkable")
			var art := fort.art_world_rect()
			# whichever way around the fort the map allows, the path must
			# never step inside the fort's solid cells (A* respects them
			# by construction — this proves it end to end)
			for probe in [
				[Vector2(art.get_center().x, art.end.y + 40.0),
					Vector2(art.get_center().x, art.position.y - 40.0)],
				[Vector2(art.position.x - 40.0, art.get_center().y),
					Vector2(art.end.x + 40.0, art.get_center().y)]]:
				var across: PackedVector2Array = NavWorld.current.request_path(
					probe[0], probe[1], "robot")
				for p in across:
					var cell := Vector2i((p / 16.0).floor())
					if NavWorld.current.nav_grid.region.has_point(cell) \
							and NavWorld.current.nav_grid.is_point_solid(cell) \
							and fort.footprint_cells().has(cell):
						nav_fails.append("path crosses fort at %s" % cell)
						break
			if nav_fails.is_empty():
				print("NAVSOLID: OK")
			else:
				for nf in nav_fails:
					print("CHECK FAILED: NAVSOLID: %s" % nf)
	if "--parade-test" in args:
		# line up manned hardware + an empty jeep for visual inspection
		var camera := ctx.get_node("RtsCamera2D")
		var origin: Vector2 = camera.global_position
		var x := 0
		for spec in [["vehicle", "jeep", 1], ["vehicle", "light", 1], ["vehicle", "medium", 1],
				["vehicle", "heavy", 1], ["vehicle", "apc", 1], ["cannon", "gatling", 1],
				["cannon", "gun", 1], ["cannon", "howitzer", 1]]:
			var v: Vehicle2D = load("res://scenes/vehicle.tscn").instantiate()
			v.setup_vehicle(spec[0], spec[1], spec[2])
			v.position = origin + Vector2(-240 + x * 70, -80)
			v.add_to_group(Groups.PARADE)
			ctx.add_child(v)
			x += 1
		var empty: Vehicle2D = load("res://scenes/vehicle.tscn").instantiate()
		empty.setup_vehicle("vehicle", "jeep", 0)
		empty.position = origin + Vector2(-240, 0)
		empty.add_to_group(Groups.PARADE)
		ctx.add_child(empty)
		# direction matrix: medium tanks facing all 8 directions
		for i in 8:
			var dt: Vehicle2D = load("res://scenes/vehicle.tscn").instantiate()
			dt.setup_vehicle("vehicle", "medium", 1)
			dt.position = origin + Vector2(-280 + i * 74, -170)
			dt.add_to_group(Groups.PARADE)
			ctx.add_child(dt)
			dt._last_dir = i
			dt._play("base", i)
			if dt._layer:
				dt._layer_dir = i
				dt._update_layer_transform()
		for c in ctx.get_children():
			if c is RobotFactory:
				# capture it for the player so the panel shows
				for z in MatchState.current.zones:
					if z.world_rect().has_point(c.world_footprint().get_center()):
						z.owner_team = MatchState.current.player_team
						break
				c.owner_team = MatchState.current.player_team
				SelectionManager.current.clear_selection()
				SelectionManager.current.toggle_select(c, false)
				MatchState.current.set_money(MatchState.current.player_team, 600)
				c.queue_unit("robot:grunt")
				c.queue_unit("robot:psycho")
				c.queue_unit("robot:tough")
				break
		await Engine.get_main_loop().process_frame
		var spawned := 0
		var missing_turret := 0
		# count the parade's OWN hardware — earlier flags leave their
		# manned vehicles all over the map
		for c in tree.get_nodes_in_group(Groups.PARADE):
			if c is Vehicle2D and c.manned:
				spawned += 1
				if c.unit_name in ["light", "medium", "heavy"] \
						and (c._layer == null or c._layer.sprite_frames == null):
					missing_turret += 1
		# 8 parade vehicles + 8 direction tanks, all manned (the extra
		# jeep is deliberately empty hardware)
		# ASSERTED (printed "FAIL" before, which nothing greps for)
		var pa := TestRig.start("PARADE")
		pa.check(spawned == 16, "parade put out %d manned hardware (want 16)" % spawned)
		pa.check(missing_turret == 0,
			"%d parade tanks have no turret layer" % missing_turret)
		pa.finish("hardware=%d" % spawned)
	if "--fx-test" in args:
		# effects/projectiles must spawn and clean up on their own
		# (earlier flags may have paused the tree via game over)
		var tree2 := ctx.get_tree()
		var was_paused := tree2.paused
		tree2.paused = false
		var fx_root: Node = Engine.get_main_loop().root.get_node("Fx")
		var before: int = fx_root.get_child_count()
		Fx.explosion(Vector2(100, 100))
		Fx.explosion(Vector2(200, 100), true)
		Fx.impact(Vector2(300, 100))
		Fx.bullet(Vector2(400, 100), Vector2(500, 100))
		var hits := [0]  # boxed: lambdas capture locals by value
		var test_proj := ProjectileDef.new()
		test_proj.speed = 500.0
		test_proj.impact = "impact"
		ShellSolver.deliver(ctx, Vector2(600, 100), Vector2(700, 100),
			test_proj, func(): hits[0] += 1)
		var spawned: int = fx_root.get_child_count() - before
		for i in 30:  # time_scale 4: the 0.2s shell flight lands in ~3
			await Engine.get_main_loop().process_frame
		var fx_rig := TestRig.start("FX")
		fx_rig.check(spawned > 0, "no effect nodes spawned")
		fx_rig.check(hits[0] == 1, "the shell landed %d times, want 1" % hits[0])
		fx_rig.check(fx_root.get_child_count() - before < spawned,
			"effects never cleaned themselves up (%d of %d still alive)"
			% [fx_root.get_child_count() - before, spawned])
		fx_rig.finish("spawned=%d" % spawned)
		tree2.paused = was_paused
	if "--teams-test" in args:
		# native team art: the original engine shipped its own recoloured
		# variant of every team-painted sprite, each team loads its own
		# files and NOTHING recolours at runtime — so the mapping, the
		# loaded frames, full art parity and neutral art must all hold
		var fails: PackedStringArray = []
		# 1. team token mapping (teams 1-4 their variant, 0/unknown null)
		# 8-team maps cycle through the four shipped palettes
		var mapping := {1: "red", 2: "blue", 3: "green", 4: "yellow",
			0: "null", 5: "red", 6: "blue", 8: "yellow", 9: "red"}
		for team in mapping:
			if AnimLibrary.team_name(team) != mapping[team]:
				fails.append("team_name %d -> %s" % [team, AnimLibrary.team_name(team)])
		# 2. frames load the team's OWN files (east-facing art never flips,
		# so the frame texture is exactly the on-disk file)
		var rf_blue: SpriteFrames = AnimLibrary.robot_frames("grunt", 2)
		if not String(rf_blue.get_frame_texture("stand_0", 0).resource_path) \
				.ends_with("stand_blue_r000.png"):
			fails.append("grunt blue stand art")
		var rf_yellow: SpriteFrames = AnimLibrary.robot_frames("grunt", 4)
		if not String(rf_yellow.get_frame_texture("fire_0", 0).resource_path) \
				.ends_with("fire_yellow_r000_n00.png"):
			fails.append("grunt yellow fire art")
		var heavy_dir := ContentDB.def_for("vehicle", "heavy").asset_dir
		var hv: SpriteFrames = AnimLibrary.vehicle_frames(heavy_dir, 3)
		if not String(hv.get_frame_texture("base_0", 0).resource_path) \
				.ends_with("base_green_r000_n00.png"):
			fails.append("heavy green base art")
		var tur: Dictionary = AnimLibrary.turret_set("heavy", heavy_dir, 2)
		if tur.is_empty() or not String(
				tur.frames.get_frame_texture("turret_0", 0).resource_path) \
				.ends_with("top_blue_r000.png"):
			fails.append("heavy blue turret art")
		# 3. flags: every team waves its own frames; neutral differs
		var flag_by_team := {}
		for team in [0, 1, 2, 3, 4]:
			var ff: SpriteFrames = AnimLibrary.flag_frames(team)
			if ff.get_frame_count("wave") == 0:
				fails.append("flag frames team %d" % team)
			flag_by_team[team] = ff.get_frame_texture("wave", 0)
		for a in flag_by_team:
			for b in flag_by_team:
				if a < b and flag_by_team[a] == flag_by_team[b]:
					fails.append("flag art shared %d/%d" % [a, b])
		# 4. HP bars: the original per-team HUD bar set (null = neutral)
		for tn in ["red", "blue", "green", "yellow", "null"]:
			if not ResourceLoader.exists(
					"res://assets/z/ui/hud/unit_amount_bar_%s.png" % tn):
				fails.append("hp bar %s" % tn)
		# 5. PARITY AUDIT: every red-painted art file must have blue/green/
		# yellow siblings — a missing variant would silently drop that
		# anim for the whole team (invisible unit), so fail loudly here
		var scan_dirs := ["res://assets/z/robots", "res://assets/z/flags",
			"res://assets/z/buildings/fort", "res://assets/z/ui/hud"]
		for d in DirAccess.get_directories_at("res://assets/z"):
			if d.begins_with("robots_") or d.begins_with("vehicles_") \
					or d.begins_with("cannons_"):
				scan_dirs.append("res://assets/z/%s" % d)
		var checked := 0
		for dir in scan_dirs:
			for f in DirAccess.get_files_at(dir):
				if f.get_extension() != "png" \
						or not ("_red_" in f or f.get_basename().ends_with("_red")):
					continue
				checked += 1
				for tn in ["blue", "green", "yellow"]:
					var sibling := "%s/%s" % [dir, f.replace("_red", "_%s" % tn)]
					if not ResourceLoader.exists(sibling):
						fails.append("%s: no %s variant" % [f, tn])
		if checked == 0:
			fails.append("parity audit scanned nothing")
		# ASSERTED (printed "FAIL <list>" before, which nothing greps for)
		var te := TestRig.start("TEAMS")
		te.check(fails.is_empty(), ", ".join(fails))
		te.finish("parity checked %d red art files" % checked)
		# live check: spawned units render their own team's files, and a
		# mixed-team squad lands in front of the camera for screenshots
		var cam: Camera2D = ctx.get_viewport().get_camera_2d()
		if cam:
			for i in 3:
				var demo: Unit2D = load("res://scenes/unit.tscn").instantiate()
				demo.unit_name = "grunt"
				demo.team = 2 + i
				demo.position = cam.position + Vector2(i * 28.0 - 28.0, -8.0)
				ctx.add_child(demo)
		await Engine.get_main_loop().process_frame
		await Engine.get_main_loop().process_frame
		var wrong_team_art: PackedStringArray = []
		for u in ctx.get_tree().get_nodes_in_group(Groups.UNITS):
			if u is Unit2D and u.team in [2, 3, 4]:
				var path := String(u.sprite.sprite_frames \
					.get_frame_texture("stand_0", 0).resource_path)
				if not ("_%s_" % Teams.display_name(u.team)) in path:
					wrong_team_art.append("%s t%d" % [u.unit_name, u.team])
		print("TEAMART: %s" % ("OK" if wrong_team_art.is_empty()
			else "WRONG %s" % wrong_team_art))



