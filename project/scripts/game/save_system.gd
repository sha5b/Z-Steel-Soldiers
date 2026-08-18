extends Node
## Autoload (SaveSystem): match save/load. Every entity serializes itself through the
## to_dict/apply_dict contract — adding a field to an entity and to its
## to_dict is all it takes to persist it (the old central dict silently
## dropped grenades, cargo, driver types, rally points and queues).

const SAVE_PATH := "user://z_save.json"


## ---- per-entity contract (implemented by Unit2D/Building2D) ----

# func to_dict() -> Dictionary: everything needed to restore this entity
# on a freshly spawned map
# func apply_dict(d: Dictionary) -> void: restore (spawn defaults first)


## ---- capture ----

func capture_save() -> Dictionary:
	var units := []
	for u in Engine.get_main_loop().root.get_tree().get_nodes_in_group("units"):
		if u is Unit2D and u.alive:
			units.append(u.to_dict())
	var facilities := []
	for b in Engine.get_main_loop().root.get_tree().get_nodes_in_group("facilities"):
		if b is Building2D and b.alive and b.owner_team != 0:
			var d: Dictionary = b.to_dict()
			if not d.is_empty():
				facilities.append(d)
	var zone_owners := []
	for z in MatchState.zones:
		zone_owners.append(z.owner_team)
	return {
		"map": GameState.current_map, "money": MatchState.money,
		"upgrades": MatchState.upgrades, "zone_owners": zone_owners,
		"units": units, "facilities": facilities,
	}


func save_game() -> bool:
	if GameState.current_map == "" or GameState.over:
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(capture_save()))
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func read_save() -> Dictionary:
	if not has_save():
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return parsed if parsed is Dictionary else {}
