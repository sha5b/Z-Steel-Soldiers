extends Control
## Pause overlay (ESC): resume, restart map, map select, title.
## process_mode ALWAYS so it works while the tree is paused.

signal closed


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func open() -> void:
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _on_resume_pressed() -> void:
	close()


func _on_restart_pressed() -> void:
	get_tree().paused = false
	GameState.reset_for_new_map()
	get_tree().reload_current_scene()


func _on_maps_pressed() -> void:
	get_tree().paused = false
	GameState.reset_for_new_map()
	get_tree().change_scene_to_file("res://scenes/map_select.tscn")


func _on_title_pressed() -> void:
	get_tree().paused = false
	GameState.reset_for_new_map()
	get_tree().change_scene_to_file("res://scenes/title.tscn")
