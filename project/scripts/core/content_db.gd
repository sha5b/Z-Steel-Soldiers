extends Node
## Autoload: the content registry. Authorable content lives as Resource
## .tres files under content/ (units, vehicles, cannons, buildings,
## effects, pickups, projectiles) — edit them in the inspector, or copy
## one next to its siblings to add a type. Sprite folders under assets/z/
## without a .tres are auto-discovered with default stats: dropping a new
## folder of correctly named PNGs on disk is enough to get playable
## content. Query from anywhere: ContentDB.def_for("robot", "psycho").

const ASSET_ROOT := "res://assets/z"
const CONTENT_ROOT := "res://content"

## Defaults for auto-discovered sprite folders (no .tres needed).
const UNIT_DEFAULTS := {
	"robot": {"hp": 42, "damage": 4, "range": 58.0, "cooldown": 0.75,
		"speed": 60.0, "cost": 40, "pop": 1},
	"vehicle": {"hp": 90, "damage": 8, "range": 78.0, "cooldown": 1.00,
		"speed": 70.0, "cost": 100, "pop": 2},
	"cannon": {"hp": 70, "damage": 8, "range": 110.0, "cooldown": 1.00,
		"speed": 0.0, "cost": 0, "pop": 2},
}

var _units := {"robot": {}, "vehicle": {}, "cannon": {}}  # name -> UnitDef
var _buildings := {}  # zod map id -> BuildingDef
var _effects := {}  # name -> EffectDef
var _pickups := {}  # name -> PickupDef


func _ready() -> void:
	_scan_dir(CONTENT_ROOT)
	_discover_unit_folders()
	_discover_effects()


func _scan_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := path + "/" + entry
		if dir.current_is_dir():
			_scan_dir(full)
		elif entry.ends_with(".tres"):
			_register(load(full))
		entry = dir.get_next()
	dir.list_dir_end()


func _register(res: Resource) -> void:
	if res is UnitDef:
		var unit := res as UnitDef
		if _units.has(unit.kind):
			_units[unit.kind][unit.id] = unit
	elif res is BuildingDef:
		var building := res as BuildingDef
		_buildings[building.id] = building
	elif res is EffectDef:
		var effect := res as EffectDef
		_effects[effect.id] = effect
	elif res is PickupDef:
		var pickup := res as PickupDef
		_pickups[pickup.id] = pickup


# ------------------------- units -------------------------

## Merged def (stats + art + projectile) for a unit kind/name; falls
## back to the kind's staple unit so callers never see null.
func def_for(kind: String, name: String) -> UnitDef:
	var table: Dictionary = _units.get(kind, {})
	if table.has(name):
		return table[name]
	var fallback: UnitDef = table.get(_fallback_name(kind), null)
	if fallback != null:
		return fallback
	return _synthesized(kind, name)


## Alias kept for the entity scripts' stat load.
func stats_for(kind: String, name: String) -> UnitDef:
	return def_for(kind, name)


func has_unit(kind: String, name: String) -> bool:
	return _units.get(kind, {}).has(name)


## All registered defs of a kind ("robot" | "vehicle" | "cannon").
func defs_of(kind: String) -> Array:
	return _units.get(kind, {}).keys()


func has_sprites(kind: String, name: String) -> bool:
	return _dir_has_art(def_for(kind, name).asset_dir)


## Per-type scene when one exists (convention: scenes/<kind-plural>/
## <name>.tscn, or UnitDef.scene), else the shared base scene.
func scene_for(kind: String, name: String) -> PackedScene:
	var def := def_for(kind, name)
	if def.scene != null:
		return def.scene
	var plural: String = {"robot": "units", "vehicle": "vehicles",
		"cannon": "cannons"}.get(kind, "")
	if plural != "":
		var path := "res://scenes/%s/%s.tscn" % [plural, name]
		if ResourceLoader.exists(path):
			return load(path)
	match kind:
		"robot": return load("res://scenes/unit.tscn")
		"vehicle", "cannon": return load("res://scenes/vehicle.tscn")
	return null


## zod map object id -> type name (empty when out of range).
func map_unit_name(kind: String, id: int) -> String:
	return ZodIds.unit_name(kind, id)


## A folder already referenced by another def's asset_dir needs no
## discovery entry (cannons_missile belongs to the missile_cannon def).
func _folder_covered(kind: String, folder_path: String) -> bool:
	for name in _units.get(kind, {}):
		if _units[kind][name].asset_dir == folder_path:
			return true
	return false


func _fallback_name(kind: String) -> String:
	match kind:
		"vehicle": return "jeep"
		"cannon": return "gatling"
	return "grunt"


func _synthesized(kind: String, name: String) -> UnitDef:
	var def := UnitDef.new()
	def.id = name
	def.kind = kind
	var defaults: Dictionary = UNIT_DEFAULTS.get(kind, UNIT_DEFAULTS.robot)
	def.hp = int(defaults.hp)
	def.damage = int(defaults.damage)
	def.range_px = float(defaults.range)
	def.cooldown = float(defaults.cooldown)
	def.speed = float(defaults.speed)
	def.cost = int(defaults.cost)
	def.pop = int(defaults.pop)
	def.asset_dir = AnimLibrary.asset_dir_for(kind, name)
	return def


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
			if prefix != "" and folder != "robots":
				var type_name := folder.substr(folder.find("_") + 1)
				if not _units[prefix].has(type_name) \
						and not _folder_covered(prefix, ASSET_ROOT + "/" + folder) \
						and _dir_has_art(ASSET_ROOT + "/" + folder):
					var def := _synthesized(prefix, type_name)
					_units[prefix][type_name] = def
		folder = dir.get_next()
	dir.list_dir_end()


# ------------------------- buildings / pickups / effects -------------------------

func building_def(id: int) -> BuildingDef:
	return _buildings.get(id, null)


func building_def_by_name(bname: String) -> BuildingDef:
	for id in _buildings:
		if _buildings[id].bname == bname:
			return _buildings[id]
	return null


## The BuildingDef that owns a producer key ("fort" covers both fort
## ids); its build_lists hold the level rosters.
func producer_def(key: String) -> BuildingDef:
	for id in _buildings:
		var def: BuildingDef = _buildings[id]
		var prod: String = def.producer if def.producer != "" else def.bname
		if def.produces and prod == key:
			return def
	return null


func pickup_def(type_name: String) -> PickupDef:
	return _pickups.get(type_name, _pickups.get("grenades", PickupDef.new()))


func effect_def(name: String) -> EffectDef:
	var def: EffectDef = _effects.get(name, null)
	if def == null:
		def = EffectDef.new()
		def.id = name
		_effects[name] = def
	return def


func effect_names() -> Array:
	return _effects.keys()


## Production panel ordering: registered order first, discovered after.
func buildable(kind: String) -> Array:
	var out: Array = []
	for name in _units.get(kind, {}):
		var def: UnitDef = _units[kind][name]
		if def.cost > 0 and has_sprites(kind, name):
			out.append(name)
	return out


## Every folder under assets/z/effects/ becomes an effect def named after
## the folder (frames follow `<folder>/<name>_n00.png`).
func _discover_effects() -> void:
	var dir := DirAccess.open(ASSET_ROOT + "/effects")
	if dir == null:
		return
	dir.list_dir_begin()
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir() and not _effects.has(folder):
			var def := EffectDef.new()
			def.id = folder
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
