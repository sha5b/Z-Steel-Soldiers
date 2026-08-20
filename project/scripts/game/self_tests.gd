class_name SelfTests
extends Object
## Headless regression harness behind command-line flags (no test
## framework dependency). Run, e.g.:
##   godot --headless --path . res://scenes/main.tscn --combat-test --quit-after 600
## Each flag prints one TESTNAME: line; zero SCRIPT ERROR lines is a pass.
## A runtime error aborts the whole run — later flags stay silent, so fix
## the first error you see.


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
			"mp"]:
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
	MatchState.direct_step = true
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
			print("UI: %s" % (",".join(fails) if fails.size() > 0 else "all original-art kit present"))
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
			print("MP: %s" % (",".join(fails) if fails.size() > 0
					else "discovery + room + start + host-lost all ok"))
	if "--capture-test" in args:
		var u: Unit2D = null
		for unit in tree.get_nodes_in_group("units"):
			if unit.team == MatchState.player_team:
				u = unit
				break
		var z: Node2D = MatchState.zones[0]
		u.position = z.position + z.world_rect().get_center()
		for i in 30:
			z._process(0.1)
			MatchState._process(1.0)
			print("CAPTURE: owner=%d money=%d" % [z.owner_team, MatchState.player_money()])
			# a zone with a LIVE enemy fort never flips — the fort is the
			# win objective, its garrison holds the ground
			var enemy_fort: Building2D = null
			for b in tree.get_nodes_in_group("buildings"):
				if b is FortBuilding and b.alive \
						and b.team != 0 and b.team != MatchState.player_team:
					enemy_fort = b
					break
			var fort_holds := true
			if enemy_fort != null:
				var held: Node2D = null
				for zh in MatchState.zones:
					if enemy_fort.art_world_rect().intersection(
							zh.world_rect()).get_area() > 0:
						held = zh
						break
				if held != null and held.owner_team == enemy_fort.team:
					u.position = held.world_rect().get_center()
					for ci in 30:
						held._process(0.1)
					fort_holds = held.owner_team == enemy_fort.team
			print("CAPTURE: fort_zone_holds=%s" % ("n/a" if enemy_fort == null
				else ("yes" if fort_holds else "NO")))
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
		for i in 400:
			a._process(0.05)
			b._process(0.05)
		print("COMBAT: a_alive=%s b_alive=%s hp_a=%d hp_b=%d" % [a.alive, b.alive, a.hp, b.hp])
	if "--factory-test" in args:
		MatchState.fast_build = true  # real build times are 72-373s
		var f := RobotFactory.new()
		var z2: Node2D = MatchState.zones[1]
		f.position = z2.position + z2.world_rect().get_center() - Vector2(24, 24)
		ctx.add_child(f)
		z2.owner_team = MatchState.player_team
		# pretend the factory was already ours — otherwise the first
		# _process treats the zone capture as new and scraps the queue
		f.owner_team = MatchState.player_team
		f.team = MatchState.player_team
		var before := tree.get_nodes_in_group("units").size()
		var money_before := MatchState.player_money()
		MatchState.money[MatchState.player_team] = 500
		for i in 3:
			f.queue_unit("robot:grunt")
		for i in 30:
			f._process(0.5)
		# a destroyed factory is a RUIN: nothing crawls out of the
		# rubble (the alive-guard in _process is load-bearing)
		var units_at_death := tree.get_nodes_in_group("units").size()
		f.take_damage(f.hp + 9999)
		for fi in 20:
			f._process(0.5)
		var ruin_spawned := tree.get_nodes_in_group("units").size() - units_at_death
		print("FACTORY: units %d -> %d money %d -> %d queue=%d ruin_spawned=%d" % [
			before, tree.get_nodes_in_group("units").size(),
			money_before, MatchState.player_money(), f.queue.items.size(), ruin_spawned])
	if "--ai-test" in args:
		MatchState.fast_build = true  # real build times are 72-373s
		var ai := ctx.get_node_or_null("CpuAi_T2")
		if ai:
			var moved := 0
			var roster := {"robots": 0, "idle": 0, "vehicles": 0, "facilities": 0}
			for u2 in tree.get_nodes_in_group("units"):
				if u2 is Node2D and u2.team == 2 and u2.move_target != Vector2.ZERO:
					moved += 1
			for u2 in UnitRegistry.world_units():
				if u2 is Unit2D and u2.alive and not u2.carried and u2.team == 2:
					if u2.kind == "robot":
						roster.robots += 1
						if u2.is_idle():
							roster.idle += 1
					elif u2.kind == "vehicle":
						roster.vehicles += 1
			for f in tree.get_nodes_in_group("facilities"):
				if f.team == 2:
					roster.facilities += 1
			print("AI ROSTER: robots=%d idle=%d vehicles=%d facilities=%d money=%d zones_owned=%d" % [
				roster.robots, roster.idle, roster.vehicles, roster.facilities,
				int(MatchState.money.get(2, 0)),
				MatchState.zones.filter(func(z): return z.owner_team == 2).size()])
			ai._think()
			var moved_after := 0
			for u2 in tree.get_nodes_in_group("units"):
				if u2 is Node2D and u2.team == 2 and u2.move_target != Vector2.ZERO:
					moved_after += 1
			print("AI: enemy robots with orders %d -> %d" % [moved, moved_after])
			# sustained observation: the full loop (income -> production ->
			# expansion -> push) must all come alive on its own
			ai.set_process(true)  # back to live thinking (isolated above)
			for step in 6:
				await ctx.get_tree().create_timer(20.0).timeout
				var r2 := 0
				var v2 := 0
				var q2 := 0
				var unmanned2 := 0
				for u3 in UnitRegistry.world_units():
					if u3 is Unit2D and u3.alive and u3.team == 2:
						if u3.kind == "robot":
							r2 += 1
						elif u3 is Vehicle2D and u3.manned:
							v2 += 1
						elif u3 is Vehicle2D:
							unmanned2 += 1
				var f2 := 0
				for b2 in tree.get_nodes_in_group("facilities"):
					if b2 is Building2D and b2.alive and b2.team == 2:
						f2 += 1
						q2 += b2.queue.items.size()
				print("AI SIM t+%ds: robots=%d vehicles=%d unmanned=%d zones=%d money=%d facilities=%d queued=%d attacking=%s" % [
					(step + 1) * 20, r2, v2, unmanned2,
					MatchState.zones.filter(func(z): return z.owner_team == 2).size(),
					int(MatchState.money.get(2, 0)), f2, q2, ai._attack_mode])
			ctx.get_tree().quit()
	if "--path-test" in args:
		var grid: AStarGrid2D = NavWorld.nav_grid
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
				var probe := NavWorld.request_path(a2 * 16.0 + Vector2(8, 8), b2 * 16.0 + Vector2(8, 8), "robot")
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
				ctx.add_child(u4)
				u4.move_to(goal)
				var crossed_solid := 0
				var total := 0
				for i in 6000:
					u4._process(0.05)
					u4._physics_process(0.05)
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
		print("DIR: mismatches=%d of 8" % bad)
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
		print("LAYER: problems=%d %s" % [problems.size(),
			", ".join(problems) if not problems.is_empty() else "(all layers ok)"])
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
			if c is FortBuilding and c.team == MatchState.player_team:
				pfort = c
				break
		await tree.process_frame
		SelectionManager.select_single(mine3)
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
		SelectionManager.clear_selection()
		var got_plain: String = gcur._determine(foe.global_position)
		if got_plain != "cursor":
			cproblems.append("plain got %s" % got_plain)
		for fam in ["cursor", "place", "attack", "grab", "enter", "repair", "nono", "cannon"]:
			var team := AnimLibrary.team_name(MatchState.player_team)
			if not ResourceLoader.exists("res://assets/z/ui/cursor/%s_%s_n00.png" % [fam, team]) \
					and fam != "cursor":
				cproblems.append("art %s_%s" % [fam, team])
		print("CURSOR: problems=%d %s" % [cproblems.size(),
			", ".join(cproblems) if not cproblems.is_empty() else "(all contexts ok)"])
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
			MatchState.auto_idle = false  # deterministic order sequence
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
			MatchState.auto_idle = true  # ...and back on for the grab test
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
		print("ORDERS: problems=%d %s" % [oproblems.size(),
			", ".join(oproblems) if not oproblems.is_empty() else "(all orders ok)"])
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
		var map_root := MatchState.map_root
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
		print("SCENES: problems=%d %s" % [sproblems.size(),
			", ".join(sproblems) if not sproblems.is_empty() else "(all scenes ok)"])
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
		print("DEFS: problems=%d %s" % [dproblems.size(),
			", ".join(dproblems) if not dproblems.is_empty() else "(all defs ok)"])
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
		for b in tree.get_nodes_in_group("buildings"):
			if b is FortBuilding and b.alive and b.team != 0:
				fort_teams[b.team] = true
		for t in fort_teams:
			var owned := 0
			for z in MatchState.zones:
				if z.owner_team == t:
					owned += 1
			if owned < 1:
				bproblems.append("team %d starts with no home zone" % t)
		print("BALANCE: problems=%d %s" % [bproblems.size(),
			", ".join(bproblems) if not bproblems.is_empty() else "(original balance holds)"])
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
		print("VFX: problems=%d %s" % [vproblems.size(),
			", ".join(vproblems) if not vproblems.is_empty() else "(all vfx ok)"])
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
				v9.remove_from_group("units")  # deferred frees must not eat pop cap
				v9.queue_free()
		var pose_missing := 0
		for line in lines:
			if "NONE" in String(line):
				pose_missing += 1
			print("POSE ", line)
		print("POSESUM: lines=%d missing_layers=%d %s" % [lines.size(),
			pose_missing, "OK" if pose_missing == 0 else "FAIL"])
	if "--level-test" in args:
		MatchState.fast_build = true  # real build times are 72-373s
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
		fort_l0.team = MatchState.player_team
		fort_l0.owner_team = fort_l0.team
		fort_l0.hp = fort_l0.max_hp
		var zones_owned_l := 0
		for z6 in MatchState.zones:
			if z6.owner_team == fort_l0.team:
				zones_owned_l += 1
		var want_mult := 1.0 - 0.5 * float(zones_owned_l) / float(maxi(MatchState.zones.size(), 1))
		if not is_equal_approx(fort_l0.build_time_mult(), want_mult):
			lproblems.append("build time mult wrong")
		fort_l0.queue_free()
		vf.queue_free()
		rf.queue_free()
		# end to end: a fort building a jeep delivers it UNMANNED, a
		# gatling spawns as an unmanned cannon
		var fort_lv: FortBuilding = null
		for c4 in ctx.get_children():
			if c4 is FortBuilding and c4.team == MatchState.player_team:
				fort_lv = c4
				break
		if fort_lv:
			fort_lv.level = 5
			MatchState.money[MatchState.player_team] = 9999
			# the sandbox roster can start above the base cap — hand the
			# player some zones for headroom before producing
			for z5 in MatchState.zones:
				z5.owner_team = MatchState.player_team
			var units_before := tree.get_nodes_in_group("units").size()
			if not fort_lv.queue_unit("vehicle:jeep"):
				lproblems.append("fort refused to build a jeep")
			if not fort_lv.queue_unit("cannon:gatling"):
				lproblems.append("fort refused to build a gatling")
			for i in 120:
				fort_lv._process(0.5)
			var new_units := tree.get_nodes_in_group("units").size() - units_before
			var unmanned := 0
			for u9 in tree.get_nodes_in_group("units"):
				if u9 is Vehicle2D and not u9.manned:
					unmanned += 1
			if new_units < 2:
				lproblems.append("fort produced %d/2 items" % new_units)
			elif unmanned < 2:
				lproblems.append("fort hardware spawned manned (want unmanned)")
		else:
			lproblems.append("no player fort on this map")
		print("LEVEL: problems=%d %s" % [lproblems.size(),
			", ".join(lproblems) if not lproblems.is_empty() else "(levels ok)"])
	if "--repair-test" in args:
		# repair shop heals a damaged vehicle; a crane rebuilds a
		# damaged building; a blown bridge becomes impassable and is
		# restored by the crane
		var rproblems: Array[String] = []
		var shop: Building2D = Building2D.new()
		shop.setup(3, MatchState.player_team, "desert", 0)
		shop.position = Vector2(600, 600)
		ctx.add_child(shop)
		# the shop must be discoverable through the order pipeline —
		# the old group scans never found it (dead repair bay)
		if Commands._find_interactable_building(
				shop.art_world_rect().get_center()) != shop:
			rproblems.append("repair shop not discoverable by commands")
		for z in MatchState.zones:
			if z.world_rect().has_point(Vector2(632, 624)) \
					or z.world_rect().has_point(Vector2(732, 624)):
				z.set_owner_team(MatchState.player_team)
		var wrecked_jeep: Vehicle2D = load("res://scenes/vehicle.tscn").instantiate()
		wrecked_jeep.setup_vehicle("vehicle", "jeep", MatchState.player_team)
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
		if not wrecked_jeep.visible or not wrecked_jeep.is_in_group("units"):
			rproblems.append("jeep never left the shop")
		# crane repairs a damaged radar
		var radar2: Building2D = Building2D.new()
		radar2.setup(2, MatchState.player_team, "desert", 0)
		radar2.position = Vector2(700, 600)
		ctx.add_child(radar2)
		radar2.max_hp = 500
		radar2.hp = 200
		var crane2: Vehicle2D = load("res://scenes/vehicle.tscn").instantiate()
		crane2.setup_vehicle("vehicle", "crane", MatchState.player_team)
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
				if NavWorld.nav_grid and not NavWorld.nav_grid.is_point_solid(cell):
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
				if NavWorld.nav_grid and NavWorld.nav_grid.is_point_solid(cell):
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
		print("REPAIR: problems=%d %s" % [rproblems.size(),
			", ".join(rproblems) if not rproblems.is_empty() else "(repair ok)"])
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
		for u10 in tree.get_nodes_in_group("units"):
			if u10 is Unit2D and u10.alive and u10.team == 2 \
					and u10 != target_tank and u10.global_position.distance_to(gren.position) < 300.0:
				u10.alive = false
				u10.remove_from_group("units")
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
		var rocks := tree.get_nodes_in_group("rocks")
		if not rocks.is_empty():
			rock_found = true
			var rock: Node2D = rocks[0]
			var cell := Vector2i(((rock.global_position - Vector2(8, 8)) / 16.0).floor())
			Combat.area_damage(rock.global_position, 40.0, 99, 0)
			await Engine.get_main_loop().process_frame
			rock_cleared = not is_instance_valid(rock) and \
				(not NavWorld.nav_grid or not NavWorld.nav_grid.is_point_solid(cell))
			if not rock_cleared:
				cproblems.append("rock not destroyed/cleared by blast")
		# --- garrison: robots inside make the fort shoot missiles ---
		var fort_g: FortBuilding = null
		for c6 in ctx.get_children():
			if c6 is FortBuilding and c6.team == MatchState.player_team:
				fort_g = c6
				break
		if fort_g:
			var rb: Unit2D = load("res://scenes/unit.tscn").instantiate()
			rb.unit_name = "grunt"
			rb.team = MatchState.player_team
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
		print("COMBAT2: problems=%d %s" % [cproblems.size(),
			", ".join(cproblems) if not cproblems.is_empty() else "OK"])
	if "--tactics-test" in args:
		MatchState.fast_build = true  # real build times are 72-373s
		# the tactical AI, end to end: with funds and hardware on the
		# map it must produce units, man empty vehicles/cannons and
		# take zones — not just charge the enemy fort
		var ai2: CpuAi = null
		for c2 in ctx.get_children():
			if c2 is CpuAi and c2.team != MatchState.player_team:
				ai2 = c2
				break
		if ai2 == null:
			print("TACTICS: no cpu ai found")
		else:
			MatchState.money[ai2.team] = 2000
			var t := ai2.team
			var count := func() -> Dictionary:
				var robots2 := 0
				var manned2 := 0
				var zones2 := 0
				for u3 in tree.get_nodes_in_group("units"):
					if u3 is Unit2D and u3.alive and u3.team == t:
						if u3 is Vehicle2D:
							if u3.manned:
								manned2 += 1
						elif u3.kind == "robot":
							robots2 += 1
				for z3 in MatchState.zones:
					if z3.owner_team == t:
						zones2 += 1
				return {"robots": robots2, "manned": manned2, "zones": zones2}
			var before_t: Dictionary = count.call()
			var manned_peak := 0
			var empty_start := 0
			for u4 in tree.get_nodes_in_group("units"):
				if u4 is Vehicle2D and not u4.manned:
					empty_start += 1
			# simulate a few minutes: think cycles + factory, unit and
			# zone time (units must walk, capture zones, board hardware)
			for i in 40:
				MatchState.money[t] = 2000
				ai2._think()
				for c3 in ctx.get_children():
					if c3 is RobotFactory or c3 is VehicleFactory or c3 is FortBuilding:
						for j in 8:
							c3._process(0.5)
				for u6 in tree.get_nodes_in_group("units"):
					if u6 is Unit2D and u6.alive:
						for j in 8:
							u6._process(0.5)
							u6._physics_process(0.5)
				for z4 in MatchState.zones:
					for j in 8:
						z4._process(0.2)
				manned_peak = maxi(manned_peak, int(count.call().manned))
			var after_t: Dictionary = count.call()
			var man_orders := 0
			var dbg := ""
			for u5 in tree.get_nodes_in_group("units"):
				if u5 is Unit2D and u5.team == t and u5.kind == "robot" \
						and u5.enter_target != null:
					man_orders += 1

			print("TACTICS: robots %d->%d manned %d->%d zones %d->%d man_orders=%d empty_start=%d manned_peak=%d%s (want production>0, manning>0, zones>0)" % [
				before_t.robots, after_t.robots, before_t.manned, after_t.manned,
				before_t.zones, after_t.zones, man_orders, empty_start, manned_peak, dbg])
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
		SelectionManager.clear_selection()
		SelectionManager.toggle_select(walker, false)
		walker.issue_order(Order.for_target(jeep3))
		var instant: bool = jeep3.manned  # must NOT be manned before walking
		for i in 400:
			walker._process(0.05)
			walker._physics_process(0.05)
			if jeep3.manned or not is_instance_valid(walker):
				break
		print("NEAR: instant=%s manned_after_walk=%s selection_left=%d" % [
			instant, jeep3.manned, SelectionManager.selected.size()])
	if "--flag-test" in args:
		var radar: Building2D = Building2D.new()
		radar.setup(2, 0, "desert")
		var zr: Node2D = MatchState.zones[0]
		radar.position = zr.position + zr.world_rect().get_center()
		ctx.add_child(radar)
		zr.owner_team = MatchState.player_team
		radar._process(0.0)
		print("FLAG: radar team=%d (want %d)" % [radar.team, MatchState.player_team])
	if "--pickup-test" in args:
		# quiet corner + overkill HP: the live map's wanderers must not
		# steal the crate or kill the collector before the check runs
		var pk := Pickup.new()
		pk.pickup_type = "grenades"
		pk.position = Vector2(2400, 3080)
		ctx.add_child(pk)
		var collector: Unit2D = load("res://scenes/unit.tscn").instantiate()
		collector.team = 1
		collector.position = Vector2(2370, 3080)
		collector.hp = 10000000
		collector.max_hp = 10000000
		ctx.add_child(collector)
		var grenades_before: int = collector.grenades
		collector.move_to(Vector2(2400, 3080))
		for i in 100:
			collector._process(0.05)
			collector._physics_process(0.05)
			pk._process(0.05)
			if not is_instance_valid(pk):
				break
		print("PICKUP: granted=%s grenades %d -> %d" % [
			grenades_before < collector.grenades, grenades_before,
			collector.grenades])
		# rockets crates carry the same 20 grenades (zod
		# grenades_per_box) — pin the grant so a def edit can't
		# silently zero it
		var rk := Pickup.new()
		rk.pickup_type = "rockets"
		rk.position = Vector2(2440, 3080)
		ctx.add_child(rk)
		var gren_before: int = collector.grenades
		collector.move_to(Vector2(2440, 3080))
		for i in 100:
			collector._process(0.05)
			collector._physics_process(0.05)
			rk._process(0.05)
			if not is_instance_valid(rk):
				break
		print("PICKUP: rockets crate grenades %d -> %d (want +20)" % [
			gren_before, collector.grenades])
	if "--prod-test" in args:
		MatchState.fast_build = true  # real build times are 72-373s
		var f2: RobotFactory = null
		for c in ctx.get_children():
			if c is RobotFactory:
				f2 = c
				break
		if f2:
			var zone_hit: Node2D = null
			for z3 in MatchState.zones:
				if z3.world_rect().has_point(f2.world_footprint().get_center()):
					zone_hit = z3
					break
			if zone_hit:
				zone_hit.owner_team = MatchState.player_team
				MatchState.money[MatchState.player_team] = 500
				f2._process(0.1)  # sync owner from zone before queueing
				var ok: bool = f2.queue_unit("robot:psycho")
				var count_before := tree.get_nodes_in_group("units").size()
				for i in 40:
					f2._process(0.5)
				var psychos := 0
				for u3 in tree.get_nodes_in_group("units"):
					if u3 is Unit2D and u3.unit_name == "psycho" and u3.team == MatchState.player_team:
						psychos += 1
				print("PROD: queued=%s units %d -> %d psychos=%d queue_left=%d" % [
					ok, count_before, tree.get_nodes_in_group("units").size(),
					psychos, f2.queue.items.size()])
	if "--fortprod-test" in args:
		MatchState.fast_build = true  # real build times are 72-373s
		var fort2: FortBuilding = null
		for c in ctx.get_children():
			if c is FortBuilding and c.team == MatchState.player_team:
				fort2 = c
				break
		if fort2:
			MatchState.money[1] = 500
			var ok2: bool = fort2.queue_unit("robot:psycho")
			for i in 8:
				fort2.queue_unit("robot:grunt")
			print("QUEUECAP: size=%d (want 5)" % fort2.queue.items.size())
			for i in 4:  # cancel only the grunts, keep the psycho
				fort2.cancel_at(fort2.queue.items.size() - 1)
			var count0 := tree.get_nodes_in_group("units").size()
			for i in 40:
				fort2._process(0.5)
			var psychos2 := 0
			for u5 in tree.get_nodes_in_group("units"):
				if u5 is Unit2D and u5.unit_name == "psycho" and u5.team == 1:
					psychos2 += 1
			print("FORTPROD: queued=%s units %d -> %d psychos=%d" % [
				ok2, count0, tree.get_nodes_in_group("units").size(), psychos2])
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
			for u6 in tree.get_nodes_in_group("units"):
				if u6 is Vehicle2D and u6.kind == "cannon" and u6.team == 1:
					mounted_guns += 1
					for s in fort_slots:
						if u6.global_position.distance_to(s) < 4.0:
							on_slot += 1
							break
			print("FORTSLOT: accepted=%d/4 mounted=%d on_slot=%d/%d free_after=%d" % [
				accepted, mounted_guns, on_slot, mounted_guns,
				fort2.free_cannon_slots()])
	if "--cancel-test" in args:
		var fort3: FortBuilding = null
		for c in ctx.get_children():
			if c is FortBuilding and c.team == MatchState.player_team:
				fort3 = c
				break
		if fort3:
			MatchState.money[1] = 500
			fort3.queue_unit("robot:grunt")
			fort3.queue_unit("robot:sniper")
			var money_mid: int = MatchState.money[1]
			fort3.cancel_at(1)  # refund the sniper ($80)
			print("CANCEL: queue=%s money %d -> %d (sniper refund %d)" % [
				fort3.queue.items, money_mid, MatchState.money[1], 80])
	if "--vehpath-test" in args:
		var rg: AStarGrid2D = NavWorld.nav_grid
		var vg: AStarGrid2D = NavWorld.vehicle_grid
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
			var start: Vector2i = NavWorld._open_cell(Vector2i(((water_px + Vector2(200, 0)) / 16.0).floor()), rg)
			var rpath := NavWorld.request_path(water_px + Vector2(200, 0), water_px, "robot")
			var vpath := NavWorld.request_path(water_px + Vector2(200, 0), water_px, "vehicle")
			var vehicle_refused: bool = vpath.is_empty()
			var vends_on_water: bool = not vehicle_refused \
				and vg.is_point_solid(Vector2i((vpath[vpath.size() - 1] / 16.0).floor()))
			print("VEHPATH: water=%s start_open=%s robot_got_path=%s vehicle_refused=%s vehicle_ends_water=%s" % [
				water_cell, start.x >= 0, not rpath.is_empty(), vehicle_refused, vends_on_water])
		# bridges must be walkable for wheels: no bridge SPAN cell solid in vgrid
		var blocked_bridges := 0
		var total_bridge_cells := 0
		for b in _all_nodes(ctx):
			if b is Building2D and (b.building_id == 6 or b.building_id == 7):
				var tile := Vector2i(((b.global_position - Vector2(8, 8)) / 16.0).floor())
				var span := Vector2i(2, 8) if b.building_id == 6 else Vector2i(8, 2)
				# the object tile is the span's TOP-LEFT (map anchor
				# contract) — the span grows right/down, no centring
				for bx2 in span.x:
					for by2 in span.y:
						var cell := tile + Vector2i(bx2, by2)
						total_bridge_cells += 1
						if vg.is_point_solid(cell):
							blocked_bridges += 1
		print("BRIDGE: solid_vehicle_cells=%d of %d bridge cells" % [blocked_bridges, total_bridge_cells])
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
			if apc2.move_target == Vector2.ZERO:
				break
		var unloaded_near: bool = robot1.visible and not robot1.carried \
			and robot1.global_position.distance_to(apc2.global_position) < 60.0
		print("APC: loaded=%s hidden=%s arrived=%s unloaded_near=%s" % [
			loaded, hidden, apc2.move_target == Vector2.ZERO, unloaded_near])
	if "--save-test" in args:
		MatchState.money[1] = 321
		MatchState.zones[0].set_owner_team(1)
		var saved: bool = GameState.save_game()
		var snapshot: Dictionary = GameState.read_save()
		MatchState.money[1] = 0
		MatchState.zones[0].set_owner_team(0)
		GameState.pending_load = snapshot
		ctx._apply_load()
		print("SAVE: saved=%s money_restored=%d zone_owner=%d units=%d" % [
			saved, MatchState.money[1], MatchState.zones[0].owner_team,
			snapshot.get("units", []).size()])
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
		print("CAMPAIGN: missions=%d first=%s advanced=%s resumed_mission=%d" % [
			Campaign.missions.size(), first.get_file(), advanced, Campaign.mission])
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
			for b2 in ctx.get_tree().get_nodes_in_group("all_buildings"):
				if b2 is Building2D and b2.owner_team == 2 and b2.alive:
					wproblems.append("cascade left a team-2 building")
					break
			if not UnitRegistry.of_team(2).is_empty():
				wproblems.append("cascade left team-2 units alive")
			for z in MatchState.zones:
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
				for u in UnitRegistry.of_team(3).duplicate():
					u.die()
				if fort3.alive:
					wproblems.append("no-units rule did not destroy team 3's fort")
			# eliminating every remaining enemy team ends the match in a
			# player win — symmetric for all teams
			for c in ctx.get_children().duplicate():
				if c is FortBuilding and c.alive \
						and c.team not in [0, MatchState.player_team]:
					c.take_damage(c.hp)
			if not GameState.over:
				wproblems.append("all enemies eliminated but no game over")
		print("WIN: %s" % (", ".join(wproblems) if not wproblems.is_empty()
			else "symmetric elimination + cascade + no-units OK"))
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
		print("MOUNT: types_without_manned_art=%s team_colored_empty=%s turret_issues=%s" % [
			no_manned, team_colored, no_turret])
	if "--cap-test" in args:
		MatchState.fast_build = true  # real build times are 72-373s
		# unit cap: base 25 + zone bonuses; production refuses beyond it
		var fort: FortBuilding = null
		for c in ctx.get_children():
			if c is FortBuilding and c.team == MatchState.player_team:
				fort = c
				break
		if fort:
			MatchState.money[1] = 99999
			# drive production until the cap refuses everything
			for i in 200:
				fort.queue_unit("robot:grunt")
				fort._process(0.6)
			var cap := MatchState.unit_cap(1)
			var used := MatchState.unit_pop(1)
			# note: with live CPU opponents the cap moves as zones flip;
			# the invariant is that the queue went full (production
			# refused) — pop may sit above a freshly shrunken cap
			print("CAP: cap=%d pop_used=%d queue=%d (queue full = cap enforced)" % [
				cap, used, fort.queue.items.size()])
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
		print("BUILDING: missing_destroyed=%s no_overlay=%s" % [
			missing_destroyed, no_overlay])
		# building geometry: the art is ONE full sprite anchored on the
		# node, the node y-sorts at the art's vertical MIDDLE (the wall
		# base — units in front draw over it, units behind under it) and
		# the footprint equals the def's solid cell rect
		var geo_fails: PackedStringArray = []
		for spec in [[0, "fort_front"], [2, "radar"], [3, "repair"]]:
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
		print("BUILDINGGEO: %s" % ("OK" if geo_fails.is_empty()
			else "FAIL %s" % geo_fails))
		# nav solidity: every placed fort blocks its def's cells on BOTH
		# grids, its open platform cells stay walkable, and a robot path
		# across the fort must detour around the solid cells
		var nav_fails: PackedStringArray = []
		var fort: Building2D = null
		for b in ctx.get_tree().get_nodes_in_group("buildings"):
			if b is Building2D and b.alive and b.is_fort:
				fort = b
				break
		if fort == null:
			nav_fails.append("no fort on map")
		else:
			for cell in fort.footprint_cells():
				if NavWorld.nav_grid.region.has_point(cell) \
						and not NavWorld.nav_grid.is_point_solid(cell):
					nav_fails.append("nav open %s" % cell)
				if NavWorld.vehicle_grid.region.has_point(cell) \
						and not NavWorld.vehicle_grid.is_point_solid(cell):
					nav_fails.append("vgrid open %s" % cell)
			var fdef := ContentDB.building_def(fort.building_id)
			var origin := Vector2i((fort.art_world_rect().position / 16.0).floor())
			var open_walked := 0
			for t in fdef.open_tiles:
				var c := origin + Vector2i(t)
				if NavWorld.nav_grid.region.has_point(c) \
						and not NavWorld.nav_grid.is_point_solid(c):
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
				var across: PackedVector2Array = NavWorld.request_path(
					probe[0], probe[1], "robot")
				for p in across:
					var cell := Vector2i((p / 16.0).floor())
					if NavWorld.nav_grid.region.has_point(cell) \
							and NavWorld.nav_grid.is_point_solid(cell) \
							and fort.footprint_cells().has(cell):
						nav_fails.append("path crosses fort at %s" % cell)
						break
		print("NAVSOLID: %s" % ("OK" if nav_fails.is_empty()
			else "FAIL %s" % nav_fails))
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
			v.add_to_group("parade")
			ctx.add_child(v)
			x += 1
		var empty: Vehicle2D = load("res://scenes/vehicle.tscn").instantiate()
		empty.setup_vehicle("vehicle", "jeep", 0)
		empty.position = origin + Vector2(-240, 0)
		empty.add_to_group("parade")
		ctx.add_child(empty)
		# direction matrix: medium tanks facing all 8 directions
		for i in 8:
			var dt: Vehicle2D = load("res://scenes/vehicle.tscn").instantiate()
			dt.setup_vehicle("vehicle", "medium", 1)
			dt.position = origin + Vector2(-280 + i * 74, -170)
			dt.add_to_group("parade")
			ctx.add_child(dt)
			dt._last_dir = i
			dt._play("base", i)
			if dt._layer:
				dt._layer_dir = i
				dt._update_layer_transform()
		for c in ctx.get_children():
			if c is RobotFactory:
				# capture it for the player so the panel shows
				for z in MatchState.zones:
					if z.world_rect().has_point(c.world_footprint().get_center()):
						z.owner_team = MatchState.player_team
						break
				c.owner_team = MatchState.player_team
				SelectionManager.clear_selection()
				SelectionManager.toggle_select(c, false)
				MatchState.money[MatchState.player_team] = 600
				c.queue_unit("robot:grunt")
				c.queue_unit("robot:psycho")
				c.queue_unit("robot:tough")
				break
		await Engine.get_main_loop().process_frame
		var spawned := 0
		var missing_turret := 0
		# count the parade's OWN hardware — earlier flags leave their
		# manned vehicles all over the map
		for c in tree.get_nodes_in_group("parade"):
			if c is Vehicle2D and c.manned:
				spawned += 1
				if c.unit_name in ["light", "medium", "heavy"] \
						and (c._layer == null or c._layer.sprite_frames == null):
					missing_turret += 1
		# 8 parade vehicles + 8 direction tanks, all manned (the extra
		# jeep is deliberately empty hardware)
		print("PARADE: hardware=%d (want 16) turret_issues=%d %s" % [
			spawned, missing_turret,
			"OK" if spawned == 16 and missing_turret == 0 else "FAIL"])
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
		Fx.shell(Vector2(600, 100), Vector2(700, 100), test_proj,
			func(): hits[0] += 1)
		var spawned: int = fx_root.get_child_count() - before
		for i in 30:  # time_scale 4: the 0.2s shell flight lands in ~3
			await Engine.get_main_loop().process_frame
		print("FX: spawned=%d shell_hits=%d remaining=%d" % [
			spawned, hits[0], fx_root.get_child_count() - before])
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
		print("TEAMS: %s (parity checked %d red art files)" % [
			"OK" if fails.is_empty() else "FAIL %s" % fails, checked])
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
		for u in ctx.get_tree().get_nodes_in_group("units"):
			if u is Unit2D and u.team in [2, 3, 4]:
				var path := String(u.sprite.sprite_frames \
					.get_frame_texture("stand_0", 0).resource_path)
				if not ("_%s_" % Teams.display_name(u.team)) in path:
					wrong_team_art.append("%s t%d" % [u.unit_name, u.team])
		print("TEAMART: %s" % ("OK" if wrong_team_art.is_empty()
			else "WRONG %s" % wrong_team_art))



