class_name MapCatalog
extends Object
## ONE map enumeration for everything: map select, campaign, the dev
## map cycler and test overrides. The sandbox/test maps are excluded from
## the campaign. Metadata (size, terrain) is read once and cached.
##
## JSON WINS by default. Every map ships as both a `.json` and a
## generated `.tscn` twin under assets/maps_scenes/, and the JSON list is
## what play has always exercised; the scene loader derives passability
## from painted terrain instead of the stored mask, so the two are not
## byte-identical. The docstring here used to claim scenes replaced their
## JSON twins, while the code below did the exact opposite — the same 58
## basenames exist in both directories, so NO scene ever registered. The
## precedence is now one explicit switch instead of an accident. Editing
## a scene in the editor and pressing F6 is unaffected either way.
const PREFER_SCENES := false

static var _entries: Array = []  # [{name, path, json, sandbox}]
static var _meta := {}  # name -> {width, height, terrain}


static func entries() -> Array:
	if not _entries.is_empty():
		return _entries
	# the PREFERRED format is registered first and claims the basename;
	# the other only fills in names the preferred pass did not cover
	var taken := {}
	for pass_scenes in ([true, false] if PREFER_SCENES else [false, true]):
		# PackFiles: an export packs `.tscn` as `.scn`, so this scan
		# found no map SCENES in a build and every map silently fell
		# back to its JSON (or to nothing)
		var folder := "assets/maps_scenes" if pass_scenes else "assets/maps"
		for f in PackFiles.with_ext("res://" + folder,
				"tscn" if pass_scenes else "json"):
			if not taken.has(f.get_basename()):
				taken[f.get_basename()] = true
				_register(f.get_basename(), "res://%s/%s" % [folder, f],
					not pass_scenes)
	_entries.sort_custom(func(a, b): return String(a.name) < String(b.name))
	return _entries


static func _register(map_name: String, path: String, is_json: bool) -> void:
	_entries.append({
		"name": map_name,
		"path": path,
		"json": is_json,
		"sandbox": map_name.begins_with("sandbox"),
	})


## The ORIGINAL CAMPAIGN. `zc01_..zc20_` are the 20 Bitmap Brothers
## levels converted from the retail data (tools/gog/level_to_json.py),
## named after the levels themselves and numbered in the game's own
## order; `zs26_..zs31_` are its skirmish maps.
const CAMPAIGN_PREFIX := "zc"


## Campaign missions IN THE ORIGINAL ORDER. This used to be every
## non-sandbox map in alphabetical FILENAME order — 57 zod multiplayer
## clone maps with no planet progression — because the retail campaign
## had no converter. The retail chain wins when it is installed; the zod
## pack is the fallback, since `assets_original/` is a gitignored
## per-contributor copy and a contributor without the retail data must
## still get a campaign.
static func campaign_missions() -> PackedStringArray:
	var out := PackedStringArray()
	for e in entries():
		if not e.sandbox and String(e.name).begins_with(CAMPAIGN_PREFIX):
			out.append(String(e.name))  # entries() is sorted: zc01..zc20
	if not out.is_empty():
		return out
	for e in entries():
		if not e.sandbox:
			out.append(String(e.name))
	return out


## Map titles for menus ("p02_bb_orig07" -> "P02 BB Orig07"). A retail
## level shows its OWN name: "zc01_virgin_soldiers" -> "VIRGIN SOLDIERS".
static func display_title(map_name: String) -> String:
	var parts := map_name.split("_")
	if parts.size() > 1 and (parts[0].begins_with(CAMPAIGN_PREFIX)
			or parts[0].begins_with("zs")) and parts[0].length() == 4:
		parts.remove_at(0)
	return " ".join(parts).to_upper()


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
	return fort_team_ids(parsed).size()


## The team ids that own a fort half on this map, sorted — the
## multiplayer lobby's seat list. Same fort-half test as the count.
static func fort_team_ids(parsed: Dictionary) -> Array:
	var teams := {}
	for o in parsed.get("objects", []):
		if String(o.get("type", "")) == "building" \
				and (int(o.get("id", -1)) == 0 or int(o.get("id", -1)) == 1) \
				and int(o.get("owner", 0)) != 0:
			teams[int(o.owner)] = true
	var out := teams.keys()
	out.sort()
	return out


## Fort teams by map NAME (every scene map has a JSON twin).
static func fort_teams(map_name: String) -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/maps/%s.json" % map_name))
	return fort_team_ids(parsed) if parsed is Dictionary else [1, 2]
