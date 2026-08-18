extends Control
## Map select: lists every converted map with size/planet, starts on click.
## Entries carry the original world art as their icon.

const PLANETS := "res://assets/z/ui/planets"
const TERRAIN_TO_PLANET := {"arctic": "artic", "volcanic": "volcan"}

@onready var list: ItemList = %MapList


func _ready() -> void:
	UiTheme.apply(self)
	list.add_theme_constant_override("icon_maximum_width", 56)
	var entries := []  # [file, dir, tag]
	for f in DirAccess.get_files_at("res://assets/maps"):
		if String(f).ends_with(".json"):
			entries.append([String(f), "res://assets/maps", "json"])
	for f in DirAccess.get_files_at("res://assets/maps_scenes"):
		if String(f).ends_with(".tscn"):
			entries.append([String(f), "res://assets/maps_scenes", "scene"])
	entries.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
	for entry in entries:
		var f: String = entry[0]
		var data: Dictionary = {}
		if entry[2] == "json":
			var parsed = JSON.parse_string(
				FileAccess.get_file_as_string(entry[1] + "/" + f))
			data = parsed if parsed is Dictionary else {}
		var terrain := String(data.get("terrain", ""))
		var label := "[%s] %s  -  %s %dx%d" % [
			entry[2], f.get_basename(), terrain,
			int(data.get("width", 0)), int(data.get("height", 0))]
		list.add_item(label)
		var icon := _planet_icon(terrain)
		if icon != null:
			list.set_item_icon(list.item_count - 1, icon)
		list.set_item_metadata(list.item_count - 1, entry[1] + "/" + f)
	if list.item_count > 0:
		list.select(0)
	await SelfTests.maybe_screenshot(self, "screenshot_mapselect.png")


static func _planet_icon(terrain: String) -> Texture2D:
	var planet: String = TERRAIN_TO_PLANET.get(terrain, terrain)
	if planet == "":
		return null
	var path := "%s/%s.png" % [PLANETS, planet]
	return load(path) if ResourceLoader.exists(path) else null


func _on_start_pressed() -> void:
	var selected := list.get_selected_items()
	if selected.is_empty():
		return
	Campaign.active = false  # a hand-picked map is a one-off match
	GameState.reset_for_new_map()
	GameState.next_map = list.get_item_metadata(selected[0])
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/title.tscn")
