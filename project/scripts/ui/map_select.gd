extends Control
## Map select: lists every converted map with size/planet, starts on click.

@onready var list: ItemList = %MapList


func _ready() -> void:
	var maps := DirAccess.get_files_at("res://assets/maps")
	maps.sort()
	for f in maps:
		if not String(f).ends_with(".json"):
			continue
		var parsed = JSON.parse_string(
			FileAccess.get_file_as_string("res://assets/maps/" + f))
		var data: Dictionary = parsed if parsed is Dictionary else {}
		var label := "%s  —  %s %dx%d" % [
			String(f).get_basename(), String(data.get("terrain", "?")),
			int(data.get("width", 0)), int(data.get("height", 0))]
		list.add_item(label)
		list.set_item_metadata(list.item_count - 1, "res://assets/maps/" + f)
	if list.item_count > 0:
		list.select(0)


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
