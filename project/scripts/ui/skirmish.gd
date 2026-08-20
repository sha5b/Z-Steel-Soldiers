extends Control
## Skirmish setup: pick how many players (the chips filter the catalogue
## — maps ship with a fixed fort per team), pick a map from real
## thumbnails rendered from each map's own terrain art, START (or
## double-click) launches a one-off match. Sandbox/test maps stay hidden.

@onready var list: ItemList = %MapList
@onready var preview: TextureRect = %Preview
@onready var map_name_label: Label = %MapName
@onready var map_info_label: Label = %MapInfo


func _ready() -> void:
	UiTheme.apply(self)
	MusicPlayer.play_menu()
	$Background.texture = UiTheme.trimmed("res://assets/z/ui/Background.png")
	# clicking the selected row again must still fire item_selected — the
	# old selector ignored reselect and clicks looked dead
	list.allow_reselect = true
	list.add_theme_constant_override("icon_maximum_width", 40)
	for chip in %Chips.get_children():
		chip.pressed.connect(_on_chip_pressed.bind(chip))
	_rebuild()
	await SelfTests.maybe_screenshot(self, "screenshot_skirmish.png")


func _rebuild() -> void:
	list.clear()
	for e in MapCatalog.entries():
		if e.sandbox:
			continue
		var map_name := String(e.name)
		var m := MapCatalog.meta(map_name)
		if _filter() > 0 and m.players != _filter():
			continue
		list.add_item("%s  %dP  %dx%d" % [
			MapCatalog.display_title(map_name), m.players, m.width, m.height])
		list.set_item_icon(list.item_count - 1, MapPreview.texture(map_name))
		list.set_item_metadata(list.item_count - 1, String(e.path))
	if list.item_count > 0:
		list.select(0)
		_show(list.get_selected_items()[0])


func _filter() -> int:
	for chip in %Chips.get_children():
		if chip.button_pressed:
			return int(chip.text) if chip.text.is_valid_int() else 0
	return 0


func _show(index: int) -> void:
	var path: String = list.get_item_metadata(index)
	var map_name := path.get_file().get_basename()
	var m := MapCatalog.meta(map_name)
	preview.texture = MapPreview.texture(map_name)
	map_name_label.text = MapCatalog.display_title(map_name)
	map_info_label.text = "%s   %dx%d   %d PLAYERS" % [
		m.terrain.to_upper(), m.width, m.height, m.players]


func _on_chip_pressed(_chip: Button) -> void:
	_rebuild()


func _on_map_selected(index: int) -> void:
	_show(index)


func _on_map_activated(_index: int) -> void:
	_start()


func _on_start_pressed() -> void:
	_start()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/title.tscn")


func _start() -> void:
	var selected := list.get_selected_items()
	if selected.is_empty():
		return
	GameState.prepare_match(MatchConfig.make("skirmish",
			list.get_item_metadata(selected[0])))
	get_tree().change_scene_to_file("res://scenes/main.tscn")
