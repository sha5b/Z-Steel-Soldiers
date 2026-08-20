extends Control
## Mission briefing: the MISSION MAP above the campaign text. Launches
## the map.
##
## The hero image used to be `ui/planets/<terrain>.png`, which is not
## planet art at all — it is the GOG release's 320x200 terrain SAMPLE
## MOSAIC (a patchwork of tiles showing what the ground looks like), so
## the briefing screen led with what read as a raw tileset dump. The real
## map thumbnail was already being generated, as a small corner icon.
## Now the map IS the briefing image and the mosaic is gone: beside a
## real map of the mission it told the player nothing.

@onready var label: Label = %BriefLabel
@onready var map_view: TextureRect = %MapView


func _ready() -> void:
	UiTheme.apply(self)
	label.text = "%s\n\nCapture territory, build your army,\ndestroy the enemy fort." \
		% Campaign.current_title()
	# the ACTUAL mission map: terrain + roads + every building's real
	# footprint in its team colour
	var map_name := Campaign.current_map_path().get_file().get_basename()
	map_view.texture = MapPreview.texture(map_name)
	await SelfTests.maybe_screenshot(self, "screenshot_brief.png")


func _on_start_pressed() -> void:
	GameState.prepare_match(MatchConfig.make("campaign",
			Campaign.current_map_path()))
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_abort_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/title.tscn")
