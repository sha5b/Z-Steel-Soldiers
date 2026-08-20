extends Control
## Title screen: splash art, continue, campaign, skirmish, settings, quit.

@onready var splash: TextureRect = %Splash
@onready var continue_btn: Button = %Continue


func _ready() -> void:
	UiTheme.apply(self)
	MusicPlayer.play_menu()
	Engine.time_scale = 1.0  # a 2x match must not speed the menus up
	# the zod menu art ships on 512x512 canvases with transparent padding
	# — trim it or the padding renders as clear-colour bands
	$Background.texture = UiTheme.trimmed("res://assets/z/ui/Background.png")
	splash.texture = UiTheme.trimmed("res://assets/z/ui/splash.png")
	continue_btn.visible = GameState.has_save()
	Net.leave()  # backing out of the menus ends any session
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


func _on_skirmish_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/skirmish.tscn")


func _on_multiplayer_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/multiplayer.tscn")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/settings.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
