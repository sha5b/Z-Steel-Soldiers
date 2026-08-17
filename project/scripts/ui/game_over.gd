extends Control
## End-of-match overlay: victory/defeat, play again, map select, and the
## campaign's next-mission button when a campaign match was won. Instanced
## by the match scene on GameState.game_over.

@onready var label: Label = %ResultLabel
@onready var again: Button = %AgainButton
@onready var maps: Button = %MapsButton
@onready var next_mission: Button = %NextMissionButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OriginalPanel.attach($Box)
	again.pressed.connect(func():
		GameState.reset_for_new_map()
		get_tree().change_scene_to_file("res://scenes/main.tscn"))
	maps.pressed.connect(func():
		GameState.reset_for_new_map()
		get_tree().change_scene_to_file("res://scenes/map_select.tscn"))
	next_mission.pressed.connect(func():
		GameState.reset_for_new_map()
		if not Campaign.advance():
			Campaign.active = false
			get_tree().change_scene_to_file("res://scenes/title.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/campaign_brief.tscn"))
	get_tree().paused = true


func show_for(winning_team: int) -> void:
	MusicPlayer.play_stinger(winning_team == GameState.player_team)
	label.text = "VICTORY!" if winning_team == GameState.player_team else "DEFEAT"
	next_mission.visible = Campaign.active and winning_team == GameState.player_team
	visible = true
