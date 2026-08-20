extends Control
## Mission briefing: the target world's original planet art above the
## campaign mission text, launches the map.

const PLANETS := "res://assets/z/ui/planets"
const TERRAIN_TO_PLANET := {"arctic": "artic", "volcanic": "volcan"}

@onready var label: Label = %BriefLabel
@onready var planet: TextureRect = %Planet
@onready var map_view: TextureRect = %MapView


func _ready() -> void:
	UiTheme.apply(self)
	label.text = "%s\n\nCapture territory, build your army,\ndestroy the enemy fort." \
		% Campaign.current_title()
	var path := "%s/%s.png" % [PLANETS, _terrain()]
	if ResourceLoader.exists(path):
		planet.texture = load(path)
	# the ACTUAL mission map thumbnail (terrain + roads + buildings), not
	# just planet flavour art
	var map_name := Campaign.current_map_path().get_file().get_basename()
	var preview := MapPreview.texture(map_name)
	if preview:
		map_view.texture = preview
	await SelfTests.maybe_screenshot(self, "screenshot_brief.png")


func _terrain() -> String:
	var map := Campaign.current_map_path()
	if map == "" or not map.begins_with("res://"):
		return "desert"
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(map))
	var terrain := String(parsed.get("terrain", "desert")) if parsed is Dictionary else "desert"
	terrain = TERRAIN_TO_PLANET.get(terrain, terrain)
	return terrain if FileAccess.file_exists("%s/%s.png" % [PLANETS, terrain]) else "desert"


func _on_start_pressed() -> void:
	GameState.prepare_match(MatchConfig.make("campaign",
			Campaign.current_map_path()))
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_abort_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/title.tscn")
