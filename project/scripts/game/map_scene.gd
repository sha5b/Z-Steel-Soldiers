class_name ZMap
extends Node2D
## A map as an editable Godot scene. Open it in the editor to see and
## change everything: paint the Terrain TileMapLayer with the planet
## tileset (assets/tilesets/<planet>.tres), move or add Zone / building /
## unit / scenery nodes. Navigation derives from the painted tiles via
## the tileinfo tables, so edited terrain updates passability and water
## automatically. Press F6 (Play Scene) to fight the map.
##
## Generated from the converted JSON maps by tools/build_map_resources.gd
## — regenerate with:
##   godot --headless --path project -s res://tools/build_map_resources.gd

@export var planet := "desert"
@export var map_size := Vector2i(64, 86)  # tiles, for editor reference


func _ready() -> void:
	y_sort_enabled = true
	if Engine.is_editor_hint():
		return
	# running the scene directly (F6) boots a full match on this map
	if get_tree().current_scene == self:
		GameState.reset_for_new_map()
		GameState.next_map = scene_file_path
		get_tree().change_scene_to_file("res://scenes/main.tscn")
