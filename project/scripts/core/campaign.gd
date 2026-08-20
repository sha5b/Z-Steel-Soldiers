extends Node
## Campaign state: an ordered chain through the converted maps with
## persistent progress. Victory advances the mission; defeat retries.

const PROGRESS_PATH := "user://z_campaign.dat"

var active := false
var mission := 0
var missions: PackedStringArray = []


func _ready() -> void:
	missions = MapCatalog.campaign_missions()


func start(from_save: bool = true) -> void:
	active = true
	if from_save:
		load_progress()
	else:
		mission = 0
		save_progress()


func current_map_path() -> String:
	if missions.is_empty():
		return ""
	return "res://assets/maps/%s.json" % missions[clampi(mission, 0, missions.size() - 1)]


func current_title() -> String:
	if missions.is_empty():
		return "Mission"
	return "Mission %d / %d — %s" % [mission + 1, missions.size(),
		MapCatalog.display_title(missions[clampi(mission, 0, missions.size() - 1)])]


## Returns true if there is a next mission.
func advance() -> bool:
	mission += 1
	save_progress()
	return mission < missions.size()


func load_progress() -> void:
	if not FileAccess.file_exists(PROGRESS_PATH):
		mission = 0
		return
	mission = int(FileAccess.get_file_as_string(PROGRESS_PATH).to_int())


func save_progress() -> void:
	var f := FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(str(mission))
