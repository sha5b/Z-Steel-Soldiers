extends Control
## Skirmish setup: pick how many players (the chips filter the catalogue
## — maps ship with a fixed fort per team), pick a map from real
## thumbnails rendered from each map's own terrain art, START (or
## double-click) launches a one-off match. Sandbox/test maps stay hidden.
##
## The first list row is GENERATED: a fresh random map built by MapGen.
## Selecting it swaps the info line for a settings row (players, start
## money, size, theme) and the preview shows the ACTUAL map the current
## seed produces — REROLL draws a new one, and START plays exactly the
## map being previewed.

const GENERATED_META := "::generated"
const MONEY_STEPS := [0, 500, 1000, 2000, 5000]  # 0 = rules default

@onready var list: ItemList = %MapList
@onready var preview: TextureRect = %Preview
@onready var map_name_label: Label = %MapName
@onready var map_info_label: Label = %MapInfo

var _gen_panel: GridContainer = null
var _gen_players: OptionButton
var _gen_money: OptionButton
var _gen_size: OptionButton
var _gen_theme: OptionButton
var _gen_seed := -1
var _gen_data: Dictionary = {}


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
	_build_gen_panel()
	_rebuild()
	await SelfTests.maybe_screenshot(self, "screenshot_skirmish.png")


func _rebuild() -> void:
	MapListUI.populate(list, _filter())
	# the generated entry leads the list whatever the chips filter says —
	# its player count is a setting, not a property of a file
	list.add_item("RANDOM MAP  (GENERATED)")
	var gen_idx := list.item_count - 1
	list.set_item_metadata(gen_idx, GENERATED_META)
	list.move_item(gen_idx, 0)
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
	var generated := path == GENERATED_META
	if _gen_panel:
		_gen_panel.visible = generated
	map_info_label.visible = not generated
	if generated:
		map_name_label.text = "GENERATED MAP"
		_refresh_generated()
		return
	var map_name := path.get_file().get_basename()
	preview.texture = MapPreview.texture(map_name)
	map_name_label.text = MapCatalog.display_title(map_name)
	map_info_label.text = MapListUI.info_line(path)


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
	var meta: String = list.get_item_metadata(selected[0])
	if meta == GENERATED_META:
		if _gen_data.is_empty():
			_refresh_generated()
		var cfg := MatchConfig.make("skirmish", MapGen.write(_gen_data))
		cfg.starting_money = int(MONEY_STEPS[_gen_money.selected])
		GameState.prepare_match(cfg)
	else:
		GameState.prepare_match(MatchConfig.make("skirmish", meta))
	get_tree().change_scene_to_file("res://scenes/main.tscn")


# ---- generated-map settings --------------------------------------------

func _build_gen_panel() -> void:
	# This row used to be an HBoxContainer. Its five controls need over
	# 500px, while the preview column is only about 300px at the supported
	# 640x480 viewport; the HBox minimum therefore enlarged the whole
	# Columns container past the screen and clipped both edges. Two compact
	# columns keep every setting reachable without imposing that width.
	_gen_panel = GridContainer.new()
	_gen_panel.columns = 2
	_gen_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gen_panel.add_theme_constant_override("h_separation", 6)
	_gen_panel.add_theme_constant_override("v_separation", 6)
	_gen_panel.visible = false
	_gen_players = _option(["2 PLAYERS", "3 PLAYERS", "4 PLAYERS", "6 PLAYERS",
		"8 PLAYERS"], 0)
	_gen_money = _option(["DEFAULT $", "$500", "$1000", "$2000", "$5000"], 0)
	_gen_size = _option(["SMALL", "MEDIUM", "LARGE"], 1)
	_gen_theme = _option(["RANDOM", "DESERT", "VOLCANIC", "ARCTIC", "JUNGLE",
		"CITY"], 0)
	var reroll := Button.new()
	reroll.text = "REROLL"
	reroll.custom_minimum_size.y = 30.0
	reroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reroll.add_theme_font_size_override("font_size", 12)
	reroll.pressed.connect(func():
		Fx.ui_click()
		_gen_seed = -1
		_refresh_generated())
	_gen_panel.add_child(reroll)
	# the settings row sits where the info line does, under the preview
	map_info_label.get_parent().add_child(_gen_panel)
	_gen_panel.get_parent().move_child(_gen_panel,
		map_info_label.get_index() + 1)


func _option(items: Array, default_idx: int) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(130, 30)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.add_theme_font_size_override("font_size", 12)
	o.fit_to_longest_item = false
	o.clip_text = true
	for item in items:
		o.add_item(String(item))
	o.selected = default_idx
	o.item_selected.connect(func(_i):
		Fx.ui_click()
		_gen_seed = -1  # new settings, new roll
		_refresh_generated())
	_gen_panel.add_child(o)
	return o


func _gen_settings() -> Dictionary:
	return {
		"players": int([2, 3, 4, 6, 8][_gen_players.selected]),
		"size": ["small", "medium", "large"][_gen_size.selected],
		"theme": ["random", "desert", "volcanic", "arctic", "jungle",
			"city"][_gen_theme.selected],
	}


## Build (or rebuild) the previewed map from the current settings and
## seed, and render the REAL thing — what you see is what START plays.
func _refresh_generated() -> void:
	if _gen_seed < 0:
		_gen_seed = randi()
	var s := _gen_settings()
	_gen_data = MapGen.generate(int(s.players), String(s.size),
		String(s.theme), _gen_seed)
	preview.texture = MapPreview.texture_for_data(_gen_data)
	map_name_label.text = "GENERATED — %s\n%d × %d  ·  %d PLAYERS" % [
		String(_gen_data.terrain).to_upper(), int(_gen_data.width),
		int(_gen_data.height), int(s.players)]
