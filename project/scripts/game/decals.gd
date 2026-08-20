class_name Decals
extends Object
## Ground decals from the original art: tank/jeep track marks and blast
## craters. Decals attach to the map root (MatchState.current.map_root) and sort
## at their top edge, so units standing on them draw over them. Tracks
## fade after a while; craters persist under a cap.

const TRACK_MARKS_DIR := "res://assets/z/effects/track_marks"
const CRATERS_DIR := "res://assets/z/effects/craters"
const MAX_TRACKS := 60
const MAX_CRATERS := 40
const TRACK_FADE_SECONDS := 18.0
const TRACK_SPACING := 7.0  # world px of travel between marks (stamps are 8px at native scale)


## Drop a track mark for a vehicle facing `dir` on `planet`. Jeep tracks
## only shipped for desert; tanks have per-planet sheets (city and
## everything else fall back to the shared one).
static func track(dir: int, pos: Vector2, jeep: bool) -> void:
	var map := MatchState.current.map_root
	if map == null:
		return
	var planet := MatchState.current.planet
	var prefix := ""
	if jeep:
		prefix = "jeep_track_desert"
	else:
		for probe in ["tank_track_%s" % planet, "tank_track"]:
			if ResourceLoader.exists("%s/%s_r000_n00.png" % [TRACK_MARKS_DIR, probe]):
				prefix = probe
				break
	if prefix == "":
		return
	# the original ships only {E, NE, N, SE} track art — W/NW/SW/S are
	# mirrors of their partners. Probing the raw path meant HALF of all
	# headings (r180..r315) silently laid no tracks at all.
	var tex := AnimLibrary.dir_texture(
		"%s/%s_r%%03d_n%02d.png" % [TRACK_MARKS_DIR, prefix, randi() % 3],
		dir * 45)
	if tex == null:
		return
	_spawn(map, tex, pos, TRACK_FADE_SECONDS, "tracks", MAX_TRACKS)


## Blast crater at an explosion site — random variant of the planet's
## art, static (no fade, just the cap).
static func crater(pos: Vector2, big := true) -> void:
	var map := MatchState.current.map_root
	if map == null:
		return
	var size := "large" if big else "small"
	var variants := []
	for t in 4:
		var prefix := "crater_%s_%s_t%02d" % [size, MatchState.current.planet, t]
		if ResourceLoader.exists("%s/%s_n00.png" % [CRATERS_DIR, prefix]):
			variants.append(prefix)
	if variants.is_empty():
		return
	var prefix: String = variants.pick_random()
	_spawn(map, load("%s/%s_n00.png" % [CRATERS_DIR, prefix]), pos,
		0.0, "craters", MAX_CRATERS)


static func _spawn(map: Node2D, tex: Texture2D, pos: Vector2,
		fade_after: float, group: String, cap: int) -> void:
	if tex == null:
		return
	_enforce_cap(map, group, cap)
	# craters/track marks are GROUND: over the terrain (z -2), under
	# every unit and building — the original stamps them into the map,
	# they never paint over structures (the 'weird grey overlay on the
	# fort' was craters y-sorting above it)
	var layer := map.get_node_or_null("GroundDecals") as Node2D
	if layer == null:
		layer = Node2D.new()
		layer.name = "GroundDecals"
		layer.z_index = -1
		map.add_child(layer)
	map = layer
	var decal := Sprite2D.new()
	decal.texture = tex
	decal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	decal.centered = false
	# GROUND art renders at tile scale (like terrain) — 2x made the
	# marks giant smears; centred on the track point, and the layer's
	# z_index (-1) keeps them under every unit and building
	decal.position = pos - tex.get_size() * 0.5
	decal.add_to_group(group)
	map.add_child(decal)
	if fade_after > 0.0:
		var tween := decal.create_tween()
		tween.tween_interval(fade_after)
		tween.tween_property(decal, "modulate:a", 0.0, 4.0)
		tween.tween_callback(decal.queue_free)


static func _enforce_cap(map: Node2D, group: String, cap: int) -> void:
	var decals: Array = map.get_tree().get_nodes_in_group(group)
	if decals.size() < cap:
		return
	decals = decals.filter(func(d): return is_instance_valid(d))
	decals.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	for i in mini(decals.size() - cap + 1, decals.size()):
		decals[i].queue_free()
