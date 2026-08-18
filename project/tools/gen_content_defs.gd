extends SceneTree
## ONE-SHOT migration (Phase 3): converts the legacy GDScript dict tables
## (UnitDefs/BuildingDefs/EffectDefs/PickupDefs) into Resource .tres files
## under content/. Run once:  godot --headless --script tools/gen_content_defs.gd
## After the migration the .tres files are the source of truth and the
## legacy table scripts are deleted — keep this script for its record of
## the mapping only.

func _init() -> void:
	_migrate_units()
	_migrate_buildings()
	_migrate_effects()
	_migrate_pickups()
	quit()


func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("save failed %s (%d)" % [path, err])
	else:
		print("saved ", path)


func _proj_from(dict: Dictionary) -> ProjectileDef:
	var p := ProjectileDef.new()
	p.speed = float(dict.get("speed", 240.0))
	p.impact = String(dict.get("impact", "impact"))
	p.texture = load(String(dict.get("texture", "")))
	return p


func _migrate_units() -> void:
	for kind in ["robot", "vehicle", "cannon"]:
		var table: Dictionary = UnitDefs.table_for(kind)
		var folder: String = {"robot": "units", "vehicle": "vehicles",
			"cannon": "cannons"}[kind]
		for unit_name in table:
			var d: Dictionary = table[unit_name]
			var u := UnitDef.new()
			u.id = String(unit_name)
			u.kind = String(kind)
			u.asset_dir = String(d.get("dir", ""))
			u.sound = String(d.get("sound", ""))
			u.hp = int(d.get("hp", 42))
			u.damage = int(d.get("damage", 4))
			u.range_px = float(d.get("range", 58.0))
			u.cooldown = float(d.get("cooldown", 0.75))
			u.speed = float(d.get("speed", 60.0))
			u.cost = int(d.get("cost", 40))
			u.pop = int(d.get("pop", 1))
			u.hit_chance = float(d.get("hit", 1.0))
			u.snipe_chance = float(d.get("snipe", 0.0))
			u.splash_radius = float(d.get("radius", 0.0))
			if d.has("projectile"):
				u.projectile = _proj_from(d.projectile)
			_save(u, "res://content/%s/%s.tres" % [folder, unit_name])
	# standalone projectile defs used by code (robot grenades)
	var grenade := ProjectileDef.new()
	grenade.speed = 150.0
	grenade.impact = "explosion"
	grenade.texture = load("res://assets/z/effects/grenade/grenade_n00.png")
	_save(grenade, "res://content/projectiles/grenade.tres")


func _migrate_buildings() -> void:
	for id in BuildingDefs.BY_ID:
		var d: Dictionary = BuildingDefs.BY_ID[id]
		var b := BuildingDef.new()
		b.id = int(id)
		b.bname = String(d.get("name", ""))
		b.size = d.get("size", Vector2i(2, 2))
		b.behaviour = d.get("script", null)
		b.tex = String(d.get("tex", ""))
		b.is_fort = bool(d.get("fort", false))
		b.solid = bool(d.get("solid", true))
		b.produces = bool(d.get("produces", false))
		b.bridge_span = d.get("bridge_span", Vector2i.ZERO)
		for a in d.get("anims", []):
			var ba := BuildingAnim.new()
			ba.prefix = String(a.get("prefix", ""))
			ba.fps = float(a.get("fps", 6.0))
			ba.offset = a.get("offset", Vector2.ZERO)
			b.anims.append(ba)
		# producer rosters: fort keys map onto both fort ids (0 front, 1 back)
		var lists: Dictionary = BuildingDefs.BUILD_LISTS.get(
			"fort" if b.is_fort else b.bname, {})
		if not lists.is_empty():
			b.produces = true
			b.build_lists = lists.duplicate(true)
		_save(b, "res://content/buildings/%s.tres" % b.bname)


func _migrate_effects() -> void:
	for fx_name in EffectDefs.BY_NAME:
		var d: Dictionary = EffectDefs.BY_NAME[fx_name]
		var e := EffectDef.new()
		e.id = String(fx_name)
		e.art_name = String(d.get("art", ""))
		e.fps = float(d.get("fps", 10.0))
		e.scale = float(d.get("scale", 1.0))
		e.sound_set = String(d.get("sound", ""))
		e.grounded = bool(d.get("grounded", false))
		e.fallback_color = d.get("color", Color(1.0, 0.8, 0.4))
		_save(e, "res://content/effects/%s.tres" % fx_name)


func _migrate_pickups() -> void:
	for pk in PickupDefs.TYPES:
		var d: Dictionary = PickupDefs.TYPES[pk]
		var p := PickupDef.new()
		p.id = String(pk)
		p.texture = load(String(d.get("texture", "")))
		p.sound_set = String(d.get("sound", ""))
		p.upgrade_key = String(d.get("grants", ""))
		p.grenades = 4 if String(pk) == "grenades" else 0
		_save(p, "res://content/pickups/%s.tres" % pk)
