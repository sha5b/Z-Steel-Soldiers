extends Control
## Title screen: splash art, start / map select / quit.

@onready var splash: TextureRect = %Splash


func _ready() -> void:
	var path := "res://assets/z/ui/splash.png"
	if ResourceLoader.exists(path):
		splash.texture = load(path)


func _on_start_pressed() -> void:
	GameState.reset_for_new_map()
	GameState.next_map = ""
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_maps_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map_select.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
