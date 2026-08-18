extends Node
## Autoload: the content registry. Def tables (scripts/content/*.gd) hold
## hand-tuned entries; sprite folders under assets/z/ that have no entry
## are auto-discovered with default stats, so dropping a new folder of
## correctly named PNGs on disk is enough to get playable content. Query
## from anywhere: ContentDB.def_for("robot", "psycho").

const ASSET_ROOT := "res://assets/z"

var _units := {"robot": {}, "vehicle": {}, "cannon": {}}  # name -> def
var _effects := {}  # name -> def (frames resolved lazily by Fx)


func _ready() -> void:
	for kind in ["robot", "vehicle", "cannon"]:
		for name in UnitDefs.table_for(kind):
			_units[kind][name] = UnitDefs.table_for(kind)[name]
	_discover_unit_folders()
	_discover_effects()


## Merged def (stats + dir + projectile) for a unit kind/name.
func def_for(kind: String, name: String) -> Dictionary:
	var table: Dictionary = _units.get(kind, {})
	return table.get(name, table.get(_fallback_name(kind), UnitDefs.defaults_for(kind)))


func stats_for(kind: String, name: String) -> Dictionary:
	return def_for(kind, name)


func has_unit(kind: String, name: String) -> bool:
	return _units.get(kind, {}).has(name)


## All registered defs of a kind ("robot" | "vehicle" | "cannon").
func defs_of(kind: String) -> Array:
	return _units.get(kind, {}).keys()


func has_sprites(kind: String, name: String) -> bool:
	return _dir_has_art(String(def_for(kind, name).get("dir", "")))


## zod map object id -> type name (empty when out of range).
func map_unit_name(kind: String, id: int) -> String:
	var ids: Array = UnitDefs.MAP_ROBOT_IDS if kind == "robot" \
			else UnitDefs.MAP_VEHICLE_IDS if kind == "vehicle" \
			else UnitDefs.MAP_CANNON_IDS
	return ids[id] if id >= 0 and id < ids.size() else ""


func building_def(id: int) -> Dictionary:
	return BuildingDefs.for_id(id)


func pickup_def(type_name: String) -> Dictionary:
	return PickupDefs.TYPES.get(type_name, PickupDefs.TYPES.grenades)


func effect_def(name: String) -> Dictionary:
	return _effects.get(name, EffectDefs.FALLBACK)


func effect_names() -> Array:
	return _effects.keys()


## Production panel ordering: registered order first, discovered after.
func buildable(kind: String) -> Array:
	var out: Array = []
	for name in _units.get(kind, {}):
		var def: Dictionary = _units[kind][name]
		if int(def.get("cost", 0)) > 0 and has_sprites(kind, name):
			out.append(name)
	return out


func _fallback_name(kind: String) -> String:
	match kind:
		"vehicle": return "jeep"
		"cannon": return "gatling"
	return "grunt"


## Any `robots_<type>` / `vehicles_<type>` / `cannons_<type>` folder with
## art in it becomes a unit def (defaults + dir). The shared `robots`
## folder (no type suffix) is skipped.
func _discover_unit_folders() -> void:
	var dir := DirAccess.open(ASSET_ROOT)
	if dir == null:
		return
	dir.list_dir_begin()
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir():
			var prefix := ""
			if folder.begins_with("robots_"):
				prefix = "robot"
			elif folder.begins_with("vehicles_"):
				prefix = "vehicle"
			elif folder.begins_with("cannons_") and folder != "cannons_common":
				prefix = "cannon"  # cannons_common = shared install art, not a unit
			if prefix != "" and not folder == "robots":
				var type_name := folder.substr(folder.find("_") + 1)
				if not _units[prefix].has(type_name) and _dir_has_art(ASSET_ROOT + "/" + folder):
					var def := UnitDefs.defaults_for(prefix).duplicate()
					def["dir"] = "%s/%s" % [ASSET_ROOT, folder]
					def["discovered"] = true
					_units[prefix][type_name] = def
		folder = dir.get_next()
	dir.list_dir_end()


## Every folder under assets/z/effects/ becomes an effect def named after
## the folder (frames follow `<folder>/<name>_n00.png`).
func _discover_effects() -> void:
	for name in EffectDefs.BY_NAME:
		_effects[name] = EffectDefs.BY_NAME[name].duplicate()
		# `art` overrides the folder (impact plays the spark art, the
		# fire0/fire1 wreck flames live in the shared fire folder);
		# frames are named after the FOLDER, not the def
		var art_folder: String = String(EffectDefs.BY_NAME[name].get("art", name))
		_effects[name]["art_name"] = art_folder
		_effects[name]["dir"] = "%s/effects/%s" % [ASSET_ROOT, art_folder]
	var dir := DirAccess.open(ASSET_ROOT + "/effects")
	if dir == null:
		return
	dir.list_dir_begin()
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir() and not _effects.has(folder):
			var def := EffectDefs.FALLBACK.duplicate()
			def["dir"] = "%s/effects/%s" % [ASSET_ROOT, folder]
			_effects[folder] = def
		folder = dir.get_next()
	dir.list_dir_end()


func _dir_has_art(path: String) -> bool:
	if path == "":
		return false
	if ResourceLoader.exists(path + "/empty_r000.png") \
			or ResourceLoader.exists(path + "/empty_r180.png") \
			or ResourceLoader.exists(path + "/fire_r000_n00.png") \
			or ResourceLoader.exists(path + "/empty.png"):
		return true
	var dir := DirAccess.open(path)
	if dir == null:
		return false
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.get_extension() == "png":
			dir.list_dir_end()
			return true
		f = dir.get_next()
	dir.list_dir_end()
	return false
