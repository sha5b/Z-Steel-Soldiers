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
	# AN EXPORTED BUILD MUST BE TESTABLE. `main_scene` is this title
	# screen, and a release binary refuses a scene override on the command
	# line ("compiled without support for path overrides"), so every test
	# flag was unreachable once the game was packaged — the 47 lanes only
	# ever ran the editor's copy of the project, and nothing could tell
	# whether an EXPORT loaded its art. Hand straight over to the match
	# scene when a test flag is present; the flags then behave in the
	# build exactly as they do in the editor.
	if SelfTests.should_run():
		# DEFERRED: swapping the scene from inside _ready leaves the tree
		# mid-add, and main.tscn then wires its HUD against a half-built
		# node list (--ui-test caught exactly that: "panel/facility
		# missing for queue-wiring check")
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
		return
	await SelfTests.maybe_screenshot(self, "screenshot_title.png")


func _on_continue_pressed() -> void:
	var save := GameState.read_save()
	if save.is_empty():
		return
	GameState.prepare_match(MatchConfig.make("continue",
			String(save.get("map", "")), 1, save))
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_campaign_pressed() -> void:
	Campaign.start(true)
	get_tree().change_scene_to_file("res://scenes/campaign_brief.tscn")


func _on_skirmish_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/skirmish.tscn")


func _on_multiplayer_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/multiplayer.tscn")


func _on_how_to_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/tutorial.tscn")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/settings.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
