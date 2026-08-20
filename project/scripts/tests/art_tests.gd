class_name ArtTests
extends Object
## Art & placement contract audit: every def's art EXISTS, its size is
## tile-aligned, its solid/open/span extents FIT the art, and robots
## ship per-team stand frames. The recurring texture bugs (2x decals,
## the fort rect a row high, bridge art vs walkable span) were all
## def-vs-art disagreements nobody validated.

const TILE := 16
const PLANETS := ["desert", "arctic", "city", "jungle", "volcanic"]


static func run(_ctx: Node, rig: TestRig) -> void:
	_audit_buildings(rig)
	_audit_units(rig)
	_audit_projectiles(rig)
	_audit_world_scale(rig)
	rig.finish()


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
			# bridges ship ONE vertical art strip (4x16 tiles); the
			# horizontal bridge rotates it at runtime, so a wide span
			# (x>y) compares against the ROTATED frame. Outer art halves
			# are decorative bank — the span must fit, not fill.
			var span_tiles := Vector2i(tiles.y, tiles.x) \
					if def.bridge_span.x > def.bridge_span.y else tiles
			rig.check(def.bridge_span.x <= span_tiles.x and def.bridge_span.y <= span_tiles.y,
				"%s: bridge_span %s exceeds art %s" % [def.bname, def.bridge_span, span_tiles])


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
