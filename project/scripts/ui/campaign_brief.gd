extends Control
## Mission briefing: shows the campaign mission, launches the map.

@onready var label: Label = %BriefLabel


func _ready() -> void:
	UiTheme.apply(self)
	label.text = "%s\n\nCapture territory, build your army,\ndestroy the enemy fort." \
		% Campaign.current_title()


func _on_start_pressed() -> void:
	GameState.reset_for_new_map()
	GameState.next_map = Campaign.current_map_path()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_abort_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/title.tscn")
