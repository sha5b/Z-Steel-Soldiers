class_name MapListUI
extends Object
## Shared map-list and map-info formatting for the skirmish screen and
## the MP lobby (they had two drifted copies of the same
## MapCatalog/MapPreview formatting).


## Fill `list` with every shipped (non-sandbox) map: original-title
## label, preview icon, path metadata. `players_filter` 0 = all.
## Selects `current_path` when given; returns whether it was found.
static func populate(list: ItemList, players_filter := 0,
		current_path := "") -> bool:
	list.clear()
	var found := false
	for e in MapCatalog.entries():
		if e.sandbox:
			continue
		var map_name := String(e.name)
		var m := MapCatalog.meta(map_name)
		if players_filter > 0 and m.players != players_filter:
			continue
		list.add_item("%s  %dP  %dx%d" % [
			MapCatalog.display_title(map_name), m.players, m.width, m.height])
		list.set_item_icon(list.item_count - 1, MapPreview.texture(map_name))
		list.set_item_metadata(list.item_count - 1, String(e.path))
		if current_path != "" and String(e.path) == current_path:
			list.select(list.item_count - 1)
			found = true
	return found


## The one-line "TERRAIN  WxH  N PLAYERS" info string under the preview.
static func info_line(map_path: String) -> String:
	var m: Dictionary = MapCatalog.meta(map_path.get_file().get_basename())
	return "%s   %dx%d   %d PLAYERS" % [
		m.terrain.to_upper(), m.width, m.height, m.players]
