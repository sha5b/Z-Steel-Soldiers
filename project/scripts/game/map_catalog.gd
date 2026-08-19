class_name MapCatalog
extends Object
## ONE map enumeration for everything: map select, campaign, the dev
## map cycler and test overrides. Scene versions replace their JSON
## twins (same basename, editable in the editor); the sandbox/test maps
## are excluded from the campaign. Metadata (size, terrain) is read once
## and cached.

static var _entries: Array = []  # [{name, path, json, sandbox}]
static var _meta := {}  # name -> {width, height, terrain}


static func entries() -> Array:
	if not _entries.is_empty():
		return _entries
	var json_names := {}
	var dir := DirAccess.open("res://assets/maps")
	if dir:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.ends_with(".json"):
				json_names[f.get_basename()] = true
				_register(f.get_basename(), "res://assets/maps/%s" % f, true)
			f = dir.get_next()
		dir.list_dir_end()
	dir = DirAccess.open("res://assets/maps_scenes")
	if dir:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.ends_with(".tscn") and not json_names.has(f.get_basename()):
				_register(f.get_basename(),
					"res://assets/maps_scenes/%s" % f, false)
			f = dir.get_next()
		dir.list_dir_end()
	_entries.sort_custom(func(a, b): return String(a.name) < String(b.name))
	return _entries


static func _register(map_name: String, path: String, is_json: bool) -> void:
	_entries.append({
		"name": map_name,
		"path": path,
		"json": is_json,
		"sandbox": map_name.begins_with("sandbox"),
	})


## Campaign missions: everything except sandbox/test maps, alphabetical.
static func campaign_missions() -> PackedStringArray:
	var out := PackedStringArray()
	for e in entries():
		if not e.sandbox:
			out.append(String(e.name))
	return out


## Map titles for menus ("p02_bb_orig07" -> "P02 BB Orig07").
static func display_title(map_name: String) -> String:
	return " ".join(map_name.split("_")).to_upper()


## Size + terrain + player count, read from the JSON once and cached.
static func meta(map_name: String) -> Dictionary:
	if _meta.has(map_name):
		return _meta[map_name]
	var out := {"width": 0, "height": 0, "terrain": "desert", "players": 0}
	# every map has a JSON twin (scenes are generated from them) — the
	# metadata always comes from the JSON
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/maps/%s.json" % map_name))
	if parsed is Dictionary:
		out.width = int(parsed.width)
		out.height = int(parsed.height)
		out.terrain = String(parsed.get("terrain", "desert"))
		out.players = _fort_teams(parsed)
	_meta[map_name] = out
	return out


## The JSON "player_count" field is unreliable (always 2 in the
## converter, even on 8-fort maps) — the real count is how many distinct
## teams own a fort half. p02/p03/p04/p08 names match this by design.
static func _fort_teams(parsed: Dictionary) -> int:
	var teams := {}
	for o in parsed.get("objects", []):
		if String(o.get("type", "")) == "building" \
				and (int(o.get("id", -1)) == 0 or int(o.get("id", -1)) == 1) \
				and int(o.get("owner", 0)) != 0:
			teams[int(o.owner)] = true
	return teams.size()
