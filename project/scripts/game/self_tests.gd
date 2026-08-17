class_name SelfTests
extends Object
## Headless regression harness behind command-line flags (no test
## framework dependency). Run, e.g.:
##   godot --headless --path . res://scenes/main.tscn --combat-test --quit-after 600
## Each flag prints one TESTNAME: line; zero SCRIPT ERROR lines is a pass.
## A runtime error aborts the whole run — later flags stay silent, so fix
## the first error you see.


static func should_run() -> bool:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for flag in ["capture", "combat", "factory", "ai", "path", "dir", "near", "flag",
			"pickup", "prod", "fortprod", "cancel", "vehpath", "apc", "save",
			"campaign", "win", "fx", "mount"]:
		if "--%s-test" % flag in args:
			return true
	return false


static func run(ctx: Node) -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var tree := ctx.get_tree()
	if "--capture-test" in args:
		var u: Unit2D = null
		for unit in tree.get_nodes_in_group("units"):
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
		var f := RobotFactory.new()
		var z2: Node2D = GameState.zones[1]
		f.position = z2.position + z2.world_rect().get_center() - Vector2(24, 24)
		ctx.add_child(f)
		z2.owner_team = GameState.player_team
		var before := tree.get_nodes_in_group("units").size()
		var money_before := GameState.player_money()
		for i in 30:
			f._process(0.5)
		print("FACTORY: units %d -> %d money %d -> %d" % [
			before, tree.get_nodes_in_group("units").size(),
			money_before, GameState.player_money()])
	if "--ai-test" in args:
		var ai := ctx.get_node_or_null("CpuAi_T2")
		if ai:
			var moved := 0
			for u2 in tree.get_nodes_in_group("units"):
				if u2 is Node2D and u2.team == 2 and u2.move_target != Vector2.ZERO:
					moved += 1
			ai._think()
			var moved_after := 0
			for u2 in tree.get_nodes_in_group("units"):
				if u2 is Node2D and u2.team == 2 and u2.move_target != Vector2.ZERO:
					moved_after += 1
			print("AI: enemy robots with orders %d -> %d" % [moved, moved_after])
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
				ctx.add_child(u4)
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
		walker.move_to(jeep3.global_position)
		walker.enter_target = jeep3
		var instant: bool = jeep3.manned  # must NOT be manned before walking
		for i in 400:
			walker._process(0.05)
			if jeep3.manned or not is_instance_valid(walker):
				break
		print("NEAR: instant=%s manned_after_walk=%s selection_left=%d" % [
			instant, jeep3.manned, SelectionManager.selected.size()])
	if "--flag-test" in args:
		var radar: Building2D = Building2D.new()
		radar.setup(2, 0, "desert")
		var zr: Node2D = GameState.zones[0]
		radar.position = zr.position + zr.world_rect().get_center()
		ctx.add_child(radar)
		zr.owner_team = GameState.player_team
		radar._process(0.0)
		print("FLAG: radar team=%d (want %d)" % [radar.team, GameState.player_team])
	if "--pickup-test" in args:
		var pk := Pickup.new()
		pk.pickup_type = "grenades"
		pk.position = Vector2(400, 400)
		ctx.add_child(pk)
		var collector: Unit2D = load("res://scenes/unit.tscn").instantiate()
		collector.team = 1
		collector.position = Vector2(370, 400)
		ctx.add_child(collector)
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
	if "--prod-test" in args:
		var f2: RobotFactory = null
		for c in ctx.get_children():
			if c is RobotFactory:
				f2 = c
				break
		if f2:
			var zone_hit: Node2D = null
			for z3 in GameState.zones:
				if z3.world_rect().has_point(f2.world_footprint().get_center()):
					zone_hit = z3
					break
			if zone_hit:
				zone_hit.owner_team = GameState.player_team
				GameState.money[GameState.player_team] = 500
				f2._process(0.1)  # sync owner from zone before queueing
				var ok: bool = f2.queue_unit("psycho")
				var count_before := tree.get_nodes_in_group("units").size()
				for i in 40:
					f2._process(0.5)
				var psychos := 0
				for u3 in tree.get_nodes_in_group("units"):
					if u3 is Unit2D and u3.unit_name == "psycho" and u3.team == GameState.player_team:
						psychos += 1
				print("PROD: queued=%s units %d -> %d psychos=%d queue_left=%d" % [
					ok, count_before, tree.get_nodes_in_group("units").size(),
					psychos, f2.queue.items.size()])
	if "--fortprod-test" in args:
		var fort2: FortBuilding = null
		for c in ctx.get_children():
			if c is FortBuilding and c.team == GameState.player_team:
				fort2 = c
				break
		if fort2:
			GameState.money[1] = 500
			var ok2: bool = fort2.queue_unit("psycho")
			var count0 := tree.get_nodes_in_group("units").size()
			for i in 40:
				fort2._process(0.5)
			var psychos2 := 0
			for u5 in tree.get_nodes_in_group("units"):
				if u5 is Unit2D and u5.unit_name == "psycho" and u5.team == 1:
					psychos2 += 1
			print("FORTPROD: queued=%s units %d -> %d psychos=%d" % [
				ok2, count0, tree.get_nodes_in_group("units").size(), psychos2])
	if "--cancel-test" in args:
		var fort3: FortBuilding = null
		for c in ctx.get_children():
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
				fort3.queue.items, money_mid, GameState.money[1], 80])
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
			var start := GameState._open_cell(Vector2i(((water_px + Vector2(200, 0)) / 16.0).floor()), rg)
			var rpath := GameState.request_path(water_px + Vector2(200, 0), water_px, "robot")
			var vpath := GameState.request_path(water_px + Vector2(200, 0), water_px, "vehicle")
			var vehicle_refused: bool = vpath.is_empty()
			var vends_on_water: bool = not vehicle_refused \
				and vg.is_point_solid(Vector2i((vpath[vpath.size() - 1] / 16.0).floor()))
			print("VEHPATH: water=%s start_open=%s robot_got_path=%s vehicle_refused=%s vehicle_ends_water=%s" % [
				water_cell, start.x >= 0, not rpath.is_empty(), vehicle_refused, vends_on_water])
		# bridges must be walkable for wheels: no bridge SPAN cell solid in vgrid
		var blocked_bridges := 0
		var total_bridge_cells := 0
		for b in ctx.get_children():
			if b is Building2D and (b.building_id == 6 or b.building_id == 7):
				var tile := Vector2i(((b.global_position - Vector2(8, 8)) / 16.0).floor())
				var span := Vector2i(2, 8) if b.building_id == 6 else Vector2i(8, 2)
				for bx2 in span.x:
					for by2 in span.y:
						var cell := tile + Vector2i(bx2 - span.x / 2, by2 - span.y / 2)
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
			if apc2.move_target == Vector2.ZERO:
				break
		var unloaded_near: bool = robot1.visible and not robot1.carried \
			and robot1.global_position.distance_to(apc2.global_position) < 60.0
		print("APC: loaded=%s hidden=%s arrived=%s unloaded_near=%s" % [
			loaded, hidden, apc2.move_target == Vector2.ZERO, unloaded_near])
	if "--save-test" in args:
		GameState.money[1] = 321
		GameState.zones[0].set_owner_team(1)
		var saved: bool = GameState.save_game()
		var snapshot: Dictionary = GameState.read_save()
		GameState.money[1] = 0
		GameState.zones[0].set_owner_team(0)
		GameState.pending_load = snapshot
		ctx._apply_load()
		print("SAVE: saved=%s money_restored=%d zone_owner=%d units=%d" % [
			saved, GameState.money[1], GameState.zones[0].owner_team,
			snapshot.get("units", []).size()])
	if "--campaign-test" in args:
		Campaign.start(false)
		var first: String = Campaign.current_map_path()
		var advanced: bool = Campaign.advance()
		Campaign.load_progress()
		print("CAMPAIGN: missions=%d first=%s advanced=%s resumed_mission=%d" % [
			Campaign.missions.size(), first.get_file(), advanced, Campaign.mission])
		Campaign.active = false
	if "--win-test" in args:
		var fort: FortBuilding = null
		for c in ctx.get_children():
			if c is FortBuilding and c.team == 2:
				fort = c
		if fort:
			GameState.game_over.connect(func(winner): print("WINNER: %d" % winner))
			fort.take_damage(fort.hp)
			print("WIN: fort_alive=%s game_over=%s" % [fort.alive, GameState.over])
	if "--mount-test" in args:
		# every spawnable vehicle/cannon must have a visible manned look
		# (base art, equiped art, or the fire cycle aliased in)
		var no_manned := []
		for kind in ["vehicle", "cannon"]:
			for type_name in ContentDB.defs_of(kind):
				if not ContentDB.has_sprites(kind, String(type_name)):
					continue
				var dir := String(ContentDB.def_for(kind, String(type_name)).get("dir", ""))
				var frames := AnimLibrary.vehicle_frames(dir, 1)
				if not frames.has_animation("base_0") or frames.get_frame_count("base_0") == 0:
					no_manned.append(String(type_name))
		print("MOUNT: types_without_manned_art=%s" % [no_manned])
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
		Fx.shell(Vector2(600, 100), Vector2(700, 100), {"speed": 500.0, "impact": "impact"},
			func(): hits[0] += 1)
		var spawned: int = fx_root.get_child_count() - before
		for i in 120:
			await Engine.get_main_loop().process_frame
		print("FX: spawned=%d shell_hits=%d remaining=%d" % [
			spawned, hits[0], fx_root.get_child_count() - before])
		tree2.paused = was_paused
