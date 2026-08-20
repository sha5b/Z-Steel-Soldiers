class_name ArtTests
extends Object
## Art & placement contract audit: every def's art EXISTS, its size is
## tile-aligned, its solid/open/span extents FIT the art, and robots
## ship per-team stand frames. The recurring texture bugs (2x decals,
## the fort rect a row high, bridge art vs walkable span) were all
## def-vs-art disagreements nobody validated.

const TILE := 16
const PLANETS := ["desert", "arctic", "city", "jungle", "volcanic"]


static func run(ctx: Node, rig: TestRig) -> void:
	_audit_buildings(rig)
	_audit_units(rig)
	_audit_projectiles(rig)
	_audit_world_scale(rig)
	_audit_robot_anims(rig)
	_audit_wired_art(ctx, rig)
	_audit_bridges(ctx, rig)
	_audit_ground_split(ctx, rig)
	rig.finish()


## BRIDGES: one sheet per planet holding TWO 4x8-tile frames (intact on
## top, wrecked below), the horizontal bridge being the vertical one
## rotated. The sprite must show ONE frame — the whole sheet was being
## drawn, so every bridge appeared as itself with its own wreck stacked
## on the end — and the def's walkable span must match the frame.
static func _audit_bridges(ctx: Node, rig: TestRig) -> void:
	for planet in PLANETS:
		var path := "res://assets/z/planets/bridge_%s.png" % planet
		rig.check(ResourceLoader.exists(path), "%s: no bridge art" % planet)
		if not ResourceLoader.exists(path):
			continue
		var size: Vector2 = (load(path) as Texture2D).get_size()
		rig.check(size == Building2D.BRIDGE_FRAME * Vector2(1.0, 2.0),
			"%s: bridge sheet %s, want two %s frames" % [planet, size,
				Building2D.BRIDGE_FRAME])
	for spec in [[6, Vector2i(4, 8)], [7, Vector2i(8, 4)]]:
		var id: int = spec[0]
		var span: Vector2i = spec[1]
		var def := ContentDB.building_def(id)
		rig.check(def.bridge_span == span,
			"%s span %s want %s" % [def.bname, def.bridge_span, span])
		var b: Building2D = def.behaviour.new()
		b.setup(id, 0, "desert")
		b.position = Vector2(2000, 2000)
		ctx.add_child(b)
		rig.check(b.get_node_or_null("GroundLayer") == null,
			"%s split a ground layer: a bridge's art IS the road" % def.bname)
		var art := b.art_world_rect()
		rig.check(art.size == Vector2(span) * TILE,
			"%s art rect %s want %s" % [def.bname, art.size, Vector2(span) * TILE])
		rig.check(b._sprite.region_enabled,
			"%s draws the whole two-frame sheet" % def.bname)
		rig.check(b._sprite.region_rect == Building2D.bridge_region(false),
			"%s starts on %s, want the intact frame" % [def.bname,
				b._sprite.region_rect])
		# wreck and repair swap frames, not tints
		b.take_damage(b.max_hp + 1)
		rig.check(b._sprite.region_rect == Building2D.bridge_region(true),
			"%s wrecked but still shows the intact frame" % def.bname)
		b.repair_by(b.max_hp)
		rig.check(b._sprite.region_rect == Building2D.bridge_region(false),
			"%s repaired but still shows the wreck frame" % def.bname)
		b.queue_free()
		# A PER-BRIDGE SPAN (the retail campaign gives one): the art must
		# cover exactly the bridge's own tiles, never the neighbour's
		# water, and the footprint must follow the span
		for length in [3, 6, 12]:
			var sized: Building2D = def.behaviour.new()
			sized.setup(id, 0, "desert")
			sized.bridge_span_override = Vector2i(4, length) if id == 6 \
					else Vector2i(length, 4)
			sized.position = Vector2(2400, 2400)
			ctx.add_child(sized)
			var want_rows: int = mini(length, 8)
			rig.check(sized.bridge_span() == sized.bridge_span_override,
				"%s ignored its span override" % def.bname)
			rig.check(is_equal_approx(sized._sprite.region_rect.size.y,
					want_rows * TILE),
				"%s len %d shows %d px of frame, want %d" % [def.bname, length,
					sized._sprite.region_rect.size.y, want_rows * TILE])
			# the FOOTPRINT is the true span (the bridge really carries
			# that much road, and clicks/targeting must agree), while the
			# ART is capped at the 8-tile frame
			var art2 := sized.art_world_rect()
			var along: float = art2.size.y if id == 6 else art2.size.x
			var across: float = art2.size.x if id == 6 else art2.size.y
			rig.check(is_equal_approx(along, length * TILE),
				"%s len %d footprint measures %s" % [def.bname, length, art2.size])
			rig.check(is_equal_approx(across, 4 * TILE),
				"%s is %.0f px across, want 64" % [def.bname, across])
			sized.queue_free()


## The art that WAS in the pack with nothing referencing it. Each check
## is the seam the feature reads through, so a missing copy fails here
## instead of silently taking a fallback branch in play.
static func _audit_wired_art(ctx: Node, rig: TestRig) -> void:
	# per-planet rubble: rocks and bridges no longer share one grey puff
	for planet in PLANETS:
		var rock := 0
		for size in Fx.ROCK_DEBRIS_SIZES:
			if DirAccess.dir_exists_absolute(
					"res://assets/z/effects/rock_debris_%s_%s" % [planet, size]):
				rock += 1
		rig.check(rock >= 4, "%s: %d rock debris sets, want 4+" % [planet, rock])
		rig.check(DirAccess.dir_exists_absolute(
				"res://assets/z/effects/bridge_debris_%s" % planet),
			"%s: no bridge debris set" % planet)
	# order-confirmation markers: one per order kind, all NEUTRAL art
	for marker in ["placed", "attacked", "entered", "cannoned", "repaired",
			"grabbed", "grenaded", "exited"]:
		rig.check(ResourceLoader.exists(
				"res://assets/z/ui/cursor/%s_n00.png" % marker),
			"confirmation marker '%s' not converted" % marker)
	for spec in [[Order.Type.MOVE, "placed"], [Order.Type.ATTACK, "attacked"],
			[Order.Type.BOARD_APC, "entered"], [Order.Type.GARRISON, "entered"],
			[Order.Type.REPAIR_BUILDING, "repaired"],
			[Order.Type.CRANE_REPAIR, "repaired"]]:
		var o := Order.new()
		o.type = spec[0]
		rig.check(o.confirm_marker() == String(spec[1]),
			"order %d confirms with %s, want %s" % [spec[0],
				o.confirm_marker(), spec[1]])
	# announcement plaques for the events that ship one
	for event in ["fort_under_attack", "robot_manufactured",
			"vehicle_manufactured", "gun_manufactured"]:
		rig.check(AnnouncePlaque.plaque_path(event) != "",
			"no announcement plaque for '%s'" % event)
	var plaque: AnnouncePlaque = ctx.get_node_or_null(
		"CanvasLayer/HUD/AnnouncePlaque")
	rig.check(plaque != null, "HUD carries no AnnouncePlaque")
	if plaque != null:
		rig.check(plaque.show_event("fort_under_attack"),
			"plaque refused a shipped event")
		rig.check(not plaque.show_event("no_such_event"),
			"plaque accepted an event with no art")
	# selected-object panel: a name plate for EVERY buildable type
	for kind in ["robot", "vehicle", "cannon"]:
		for type_name in ContentDB.buildable(kind):
			rig.check(SelectedObject.plate_path(String(type_name), 1) != "",
				"%s '%s' has no name plate" % [kind, type_name])
	# ambient birds, per planet
	for planet in PLANETS:
		rig.check(Bird.art_exists(planet), "%s ships no bird art" % planet)
	# the unlabelled voice bank
	var barks := 0
	for n in range(Fx.CHATTER_FIRST, Fx.CHATTER_LAST + 1):
		if ResourceLoader.exists("res://assets/z/sounds/bark_%02d.wav" % n):
			barks += 1
	rig.check(barks == Fx.CHATTER_LAST - Fx.CHATTER_FIRST + 1,
		"%d of %d chatter barks converted" % [barks,
			Fx.CHATTER_LAST - Fx.CHATTER_FIRST + 1])
	# a falling building throws pieces of itself (84 frames the pack
	# shipped and nothing referenced)
	for spec in [["fort_", 5], ["", 2]]:
		for i in int(spec[1]):
			var frames := AnimLibrary.effect_frames(Fx.DEBRIS_DIR,
				"%spiece%d" % [spec[0], i], 10.0)
			rig.check(frames != null and frames.has_animation("fx")
					and frames.get_frame_count("fx") > 0,
				"debris piece %spiece%d has no frames" % [spec[0], i])
	rig.check(Fx.building_debris(Vector2(4000, 4000), true) > 0,
		"a falling fort threw no debris")
	rig.check(Fx.building_debris(Vector2(4000, 4000), false) > 0,
		"a falling building threw no debris")
	# debris count follows the FOOTPRINT: a fort scatters more pieces
	# than a one-tile hut (they all used to leave the same single pixel,
	# in the same quantity, whatever the structure's size)
	var small_wreck := Fx.building_debris(Vector2(4000, 4000), false, 40.0,
		Rect2(0.0, 0.0, 32.0, 32.0))
	var large_wreck := Fx.building_debris(Vector2(4000, 4000), true, 40.0,
		Rect2(0.0, 0.0, 128.0, 128.0))
	rig.check(large_wreck > small_wreck,
		"debris count ignored footprint size (%d vs %d)"
			% [large_wreck, small_wreck])
	# a HURT STRUCTURE BURNS. The pack's whole burn set was vehicle-only:
	# buildings never smoked at any damage level and their ruins never
	# smouldered (docs/HANDOFF.md open item 2).
	var burn_sets: Array = Fx.STRUCTURE_SMOKE + Fx.STRUCTURE_FIRE
	for burn_name in burn_sets:
		var burn: SpriteFrames = AnimLibrary.effect_frames(
			"res://assets/z/effects/%s" % burn_name, String(burn_name), 8.0)
		rig.check(burn != null and burn.has_animation("fx")
				and burn.get_frame_count("fx") > 0,
			"burn set '%s' has no frames" % burn_name)
	for severity in [0.0, 0.5, 1.0]:
		rig.check(Fx.structure_smoke(Vector2(4000, 4000), severity, true),
			"structure smoke at severity %.1f resolved no art" % severity)
	var burner: Building2D = ContentDB.building_def(0).behaviour.new()
	burner.setup(0, 1, "desert", 1)
	ctx.add_child(burner)
	burner.hp = int(burner.max_hp * 0.1)
	var puffs := Fx.get_child_count()
	burner._damage_fx(1.0)
	rig.check(Fx.get_child_count() > puffs, "a burning fort emitted no smoke")
	# and the ruin it leaves keeps burning, like a tank husk does
	burner.alive = false
	burner._ruin_burn = Building2D.RUIN_BURN
	burner._smoke_timer = 0.0
	puffs = Fx.get_child_count()
	burner._ruin_fx(1.0)
	rig.check(Fx.get_child_count() > puffs, "a fort's ruin did not smoulder")
	burner.queue_free()
	# the building LEVEL digit, on every producer
	for id in [0, 4, 5]:
		var bdef := ContentDB.building_def(id)
		var b: Building2D = bdef.behaviour.new()
		b.setup(id, 1, "desert", 3)
		ctx.add_child(b)
		rig.check(b.get_node_or_null("LevelPlate") != null,
			"%s shows no level digit" % bdef.bname)
		b.queue_free()


## Every animation the code ASKS FOR must be in the frame set — a name
## the art does not carry is a silent no-op (176 frames of escape_tank /
## tank_fire / jump-* sat in the pack referenced by nothing).
static func _audit_robot_anims(rig: TestRig) -> void:
	var frames := AnimLibrary.robot_frames("grunt", 1)
	for gesture in AnimLibrary.GESTURES:
		var found := false
		for d in AnimLibrary.DIRECTIONS:
			if frames.has_animation("%s_%d" % [gesture, d]) \
					and frames.get_frame_count("%s_%d" % [gesture, d]) > 0:
				found = true
				break
		rig.check(found, "gesture '%s' has no frames" % gesture)
	# the dodge picks its leap by direction — every branch must resolve
	for spec in [[Vector2(0, 20), "jump-down"], [Vector2(0, -20), "jump-up"],
			[Vector2(20, 0), "jump-right"], [Vector2(-20, 0), "jump-left"],
			[Vector2.ZERO, "dodge"]]:
		rig.check(Unit2D._leap_gesture(spec[0]) == String(spec[1]),
			"leap for %s = %s want %s" % [spec[0],
				Unit2D._leap_gesture(spec[0]), spec[1]])
	# the visible crew in the open hatch: 8 directions, per team
	for team in [1, 2, 3, 4]:
		var crew := AnimLibrary.crew_frames(team)
		var dirs := 0
		for d in AnimLibrary.DIRECTIONS:
			if crew.has_animation("tank_fire_%d" % d) \
					and crew.get_frame_count("tank_fire_%d" % d) > 0:
				dirs += 1
		rig.check(dirs == AnimLibrary.DIRECTIONS,
			"team %d crew art covers %d of %d directions"
			% [team, dirs, AnimLibrary.DIRECTIONS])


## SCALE CONTRACT: world-space art renders at NATIVE size — no unit
## scene may override sprite_scale away from 1.0 (the 2x era is dead;
## a stray override doubles that unit against the 1:1 world).
static func _audit_world_scale(rig: TestRig) -> void:
	for folder in ["res://scenes/units", "res://scenes/vehicles",
			"res://scenes/cannons"]:
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		for f in dir.get_files():
			if not f.ends_with(".tscn"):
				continue
			var text := FileAccess.open("%s/%s" % [folder, f], FileAccess.READ).get_as_text()
			for line in text.split("\n"):
				if line.contains("sprite_scale") \
						and not line.contains("sprite_scale = 1.0"):
					rig.check(false, "%s: %s" % [f, line.strip_edges()])


static func _audit_buildings(rig: TestRig) -> void:
	for id in range(0, 8):
		var def := ContentDB.building_def(id)
		if def == null:
			rig.check(false, "building id %d has no def" % id)
			continue
		# EVERY planet ships intact AND destroyed art for every kind (the
		# ruin swap loads it sight-unseen — a missing file = invisible ruin)
		for planet in PLANETS:
			var intact := ContentDB.building_art_path(def.tex, planet, false)
			rig.check(intact != "" and ResourceLoader.exists(intact),
				"%s: %s art missing at %s" % [def.bname, planet, intact])
			var ruin := ContentDB.building_art_path(def.tex, planet, true)
			rig.check(ResourceLoader.exists(ruin),
				"%s: %s DESTROYED art missing at %s" % [def.bname, planet, ruin])
			# the ruin swap keeps the sprite's REGIONS (the ground/
			# structure split, and the bridge frame), so the two images
			# must be the same size or the ruin renders sheared
			if ResourceLoader.exists(intact) and ResourceLoader.exists(ruin):
				var a: Vector2 = (load(intact) as Texture2D).get_size()
				var b: Vector2 = (load(ruin) as Texture2D).get_size()
				rig.check(a == b,
					"%s: %s ruin art %s != intact %s" % [def.bname, planet, b, a])
		var path := ContentDB.building_art_path(def.tex, "desert", false)
		if path == "" or not ResourceLoader.exists(path):
			continue
		var size: Vector2 = (load(path) as Texture2D).get_size()
		var tiles := Vector2i(int(size.x) / TILE, int(size.y) / TILE)
		rig.check(int(size.x) % TILE == 0 and int(size.y) % TILE == 0,
			"%s: art %dx%d not tile-aligned" % [def.bname, size.x, size.y])
		if def.solid_tiles != Rect2i():
			# the fort's art is 10x12 tiles with a solid 10x9 — the bottom
			# apron rows are deliberately open walkway, not a mismatch
			rig.check(def.solid_tiles.position.x + def.solid_tiles.size.x <= tiles.x
					and def.solid_tiles.position.y + def.solid_tiles.size.y <= tiles.y,
				"%s: solid_tiles exceed art (%s vs %s)" % [def.bname, def.solid_tiles, tiles])
		for t in def.open_tiles:
			rig.check(t.x < tiles.x and t.y < tiles.y,
				"%s: open tile %s outside art %s" % [def.bname, t, tiles])
		if def.bridge_span != Vector2i.ZERO:
			# the bridge sheet is TWO stacked 4x8-tile frames (intact +
			# wrecked), so the span compares against ONE FRAME, not the
			# sheet. The horizontal bridge is the vertical one rotated,
			# so a wide span (x>y) compares against the rotated frame.
			var frame := Vector2i((Building2D.BRIDGE_FRAME / TILE).floor())
			var span_tiles := Vector2i(frame.y, frame.x) \
					if def.bridge_span.x > def.bridge_span.y else frame
			rig.check(def.bridge_span.x <= span_tiles.x and def.bridge_span.y <= span_tiles.y,
				"%s: bridge_span %s exceeds art %s" % [def.bname, def.bridge_span, span_tiles])


## GROUND/STRUCTURE SPLIT: the two sprites must partition the art
## exactly — before AND after the ruin swap, on every planet. A drifted
## region is how a building ends up cutting units in half again.
static func _audit_ground_split(ctx: Node, rig: TestRig) -> void:
	for id in [2, 3, 4, 5]:
		for planet in PLANETS:
			var def := ContentDB.building_def(id)
			var b: Building2D = def.behaviour.new()
			b.setup(id, 1, planet)
			b.position = Vector2(3000, 3000)
			ctx.add_child(b)
			var ground: Sprite2D = b.get_node_or_null("GroundLayer")
			if ground == null:
				continue  # this building's art carries no ground band
			for stage in ["intact", "ruined"]:
				if stage == "ruined":
					b.take_damage(b.max_hp + 1)
				var top: Rect2 = b._sprite.region_rect
				var bottom: Rect2 = ground.region_rect
				rig.check(top.position == Vector2.ZERO,
					"%s/%s %s: structure region starts at %s"
					% [def.bname, planet, stage, top.position])
				rig.check(is_equal_approx(top.end.y, bottom.position.y),
					"%s/%s %s: gap between structure (%s) and ground (%s)"
					% [def.bname, planet, stage, top, bottom])
				rig.check(is_equal_approx(top.size.x, bottom.size.x),
					"%s/%s %s: layers differ in width (%s vs %s)"
					% [def.bname, planet, stage, top.size, bottom.size])
				rig.check(ground.z_index < 0,
					"%s/%s %s: ground layer not below units (z %d)"
					% [def.bname, planet, stage, ground.z_index])
				rig.check(ground.texture == b._sprite.texture,
					"%s/%s %s: ground and structure show different images"
					% [def.bname, planet, stage])
			b.queue_free()


## Projectiles reference a texture and an impact effect by name — both
## must actually exist (a dangling reference is a silent tracer
## fallback).
static func _audit_projectiles(rig: TestRig) -> void:
	var dir := DirAccess.open("res://content/projectiles")
	if dir == null:
		rig.check(false, "no content/projectiles dir")
		return
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var def: ProjectileDef = load("res://content/projectiles/" + f) as ProjectileDef
		if def == null:
			continue
		rig.check(def.texture != null,
			"%s: no projectile texture" % f.get_basename())
		rig.check(DirAccess.dir_exists_absolute("res://assets/z/effects/%s" % def.impact),
			"%s: impact effect folder '%s' missing" % [f.get_basename(), def.impact])


static func _audit_units(rig: TestRig) -> void:
	for spec in [["robot", "res://content/units"],
			["vehicle", "res://content/vehicles"],
			["cannon", "res://content/cannons"]]:
		var dir := DirAccess.open(String(spec[1]))
		if dir == null:
			continue
		for f in dir.get_files():
			if not f.ends_with(".tres"):
				continue
			var def: UnitDef = load("%s/%s" % [spec[1], f]) as UnitDef
			if def == null:
				continue
			var art := DirAccess.open(def.asset_dir)
			rig.check(art != null and not art.get_files().is_empty(),
				"%s: asset_dir empty (%s)" % [def.id, def.asset_dir])
	# stand/walk art is SHARED across robot types (robots/ folder) —
	# every team palette must ship its stand set there
	for team in [1, 2, 3, 4]:
		rig.check(ResourceLoader.exists("%s/stand_%s_r000.png"
				% [AnimLibrary.ROBOTS_DIR, AnimLibrary.team_name(team)]),
			"shared robots: no team-%d stand art" % team)
