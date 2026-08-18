extends Control
## Title screen: splash art, continue, campaign, start, map select,
## difficulty, quit.

@onready var splash: TextureRect = %Splash
@onready var continue_btn: Button = %Continue


func _ready() -> void:
	UiTheme.apply(self)
	MusicPlayer.play_menu()
	var path := "res://assets/z/ui/splash.png"
	if ResourceLoader.exists(path):
		splash.texture = load(path)
	continue_btn.visible = GameState.has_save()
	await SelfTests.maybe_screenshot(self, "screenshot_title.png")


func _on_continue_pressed() -> void:
	var save := GameState.read_save()
	if save.is_empty():
		return
	GameState.reset_for_new_map()
	GameState.next_map = String(save.get("map", ""))
	GameState.pending_load = save
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_campaign_pressed() -> void:
	Campaign.start(true)
	get_tree().change_scene_to_file("res://scenes/campaign_brief.tscn")


func _on_start_pressed() -> void:
	Campaign.active = false  # quick start is a one-off match
	GameState.reset_for_new_map()
	GameState.next_map = ""
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_maps_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map_select.tscn")


func _on_difficulty_selected(index: int) -> void:
	GameState.ai_difficulty = index


func _on_quit_pressed() -> void:
	get_tree().quit()
