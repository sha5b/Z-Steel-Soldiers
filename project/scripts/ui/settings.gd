extends Control
## Options screen: AI difficulty, game speed (applied at match kickoff
## via Engine.time_scale), music/effects volume (runtime buses), smart
## idle. Every change applies immediately and persists to user://.

@onready var name_field: LineEdit = %Name
@onready var difficulty: OptionButton = %Difficulty
@onready var speed: OptionButton = %Speed
@onready var idle: OptionButton = %Idle
@onready var music: HSlider = %Music
@onready var effects: HSlider = %Effects
@onready var music_value: Label = %MusicValue
@onready var effects_value: Label = %EffectsValue
@onready var options_plaque: TextureRect = %OptionsPlaque
@onready var audio_plaque: TextureRect = %AudioPlaque


func _ready() -> void:
	UiTheme.apply(self)
	MusicPlayer.play_menu()
	$Background.texture = UiTheme.trimmed("res://assets/z/ui/Background.png")
	# the edge plaques need room beside the option rows — drop them on
	# narrow windows instead of overlapping the rows
	resized.connect(_layout_plaques)
	_layout_plaques()
	for label in GameSettings.SPEED_LABELS:
		speed.add_item(label)
	difficulty.selected = GameSettings.difficulty
	name_field.text = GameSettings.player_name
	speed.selected = GameSettings.speed_index
	idle.selected = 1 if GameSettings.auto_idle else 0
	music.set_value_no_signal(GameSettings.music_volume)
	effects.set_value_no_signal(GameSettings.sfx_volume)
	music_value.text = _pct(music.value)
	effects_value.text = _pct(effects.value)
	await SelfTests.maybe_screenshot(self, "screenshot_settings.png")


func _pct(v: float) -> String:
	return str(roundi(v * 100.0))


func _layout_plaques() -> void:
	var wide := size.x > 760.0
	options_plaque.visible = wide
	audio_plaque.visible = wide


func _on_name_changed(text: String) -> void:
	GameSettings.player_name = text.to_upper()
	GameSettings.save()


func _on_difficulty_selected(index: int) -> void:
	GameSettings.difficulty = index
	GameSettings.apply()
	GameSettings.save()


func _on_speed_selected(index: int) -> void:
	GameSettings.speed_index = index
	GameSettings.save()


func _on_idle_selected(index: int) -> void:
	GameSettings.auto_idle = index == 1
	GameSettings.apply()
	GameSettings.save()


func _on_music_changed(value: float) -> void:
	GameSettings.music_volume = value
	GameSettings.apply()
	GameSettings.save()
	music_value.text = _pct(value)


func _on_effects_changed(value: float) -> void:
	GameSettings.sfx_volume = value
	GameSettings.apply()
	GameSettings.save()
	effects_value.text = _pct(value)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/title.tscn")
