extends Control
## Pause overlay (ESC): resume, restart map, map select, title.
## process_mode ALWAYS so it works while the tree is paused.

signal closed


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	UiTheme.apply(self)
	OriginalPanel.attach(get_node("Panel"), true)


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


func _on_save_pressed() -> void:
	if GameState.save_game():
		var note: Label = get_node_or_null("Panel/Margin/Menu/SaveNote")
		if note == null:
			note = Label.new()
			note.name = "SaveNote"
			note.text = "Saved!"
			note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			get_node("Panel/Margin/Menu").add_child(note)
		else:
			note.text = "Saved!"


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
