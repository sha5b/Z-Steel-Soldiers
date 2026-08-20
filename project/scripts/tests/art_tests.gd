class_name ArtTests
extends Object
## Art & placement contract audit: every def's art EXISTS, its size is
## tile-aligned, its solid/open/span extents FIT the art, and robots
## ship per-team stand frames. The recurring texture bugs (2x decals,
## the fort rect a row high, bridge art vs walkable span) were all
## def-vs-art disagreements nobody validated.

const TILE := 16


static func run(_ctx: Node, rig: TestRig) -> void:
	_audit_buildings(rig)
	_audit_units(rig)
	rig.finish()


static func _audit_buildings(rig: TestRig) -> void:
	for id in range(0, 8):
		var def := ContentDB.building_def(id)
		if def == null:
			rig.check(false, "building id %d has no def" % id)
			continue
		var path := ContentDB.building_art_path(def.tex, "desert", false)
		if path == "" or not ResourceLoader.exists(path):
			rig.check(false, "%s: art missing at %s" % [def.bname, path])
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
			# bridges ship ONE vertical art strip (4x16 tiles); the
			# horizontal bridge rotates it at runtime, so a wide span
			# (x>y) compares against the ROTATED frame. Outer art halves
			# are decorative bank — the span must fit, not fill.
			var span_tiles := Vector2i(tiles.y, tiles.x) \
					if def.bridge_span.x > def.bridge_span.y else tiles
			rig.check(def.bridge_span.x <= span_tiles.x and def.bridge_span.y <= span_tiles.y,
				"%s: bridge_span %s exceeds art %s" % [def.bname, def.bridge_span, span_tiles])


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
