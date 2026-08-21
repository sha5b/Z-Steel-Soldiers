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
	UiTheme.apply(self)
	OriginalPanel.attach($Box)
	again.pressed.connect(func(): _leave("res://scenes/main.tscn"))
	maps.pressed.connect(func(): _leave("res://scenes/skirmish.tscn"))
	next_mission.pressed.connect(func():
		if not Campaign.advance():
			Campaign.active = false
			_leave("res://scenes/title.tscn")
		else:
			_leave("res://scenes/campaign_brief.tscn"))
	get_tree().paused = true


## EVERY WAY OUT OF THIS OVERLAY MUST UNPAUSE THE TREE. `paused` belongs
## to the SceneTree, not to a scene, so it outlives
## change_scene_to_file: the overlay used to leave it set, and the next
## screen came up with every button dead (PROCESS_MODE_INHERIT stops
## processing while paused). That is the "I won a skirmish and then Back
## did nothing" bug — the menu was drawn, it just could not be clicked.
## The pause menu already did this on each of its own three exits, so
## the unpause now lives with the rest of the leave-a-match state
## (GameState.leave_match) instead of being repeated per button.
func _leave(scene_path: String) -> void:
	GameState.leave_match(scene_path)


## Belt and braces for any future exit path (and for the overlay simply
## being freed): whatever removes this node lifts the pause with it.
func _exit_tree() -> void:
	if is_inside_tree() and get_tree() != null:
		get_tree().paused = false


func show_for(winning_team: int) -> void:
	MusicPlayer.play_stinger(winning_team == MatchState.current.player_team)
	label.text = "VICTORY!" if winning_team == MatchState.current.player_team else "DEFEAT"
	next_mission.visible = Campaign.active and winning_team == MatchState.current.player_team
	visible = true
