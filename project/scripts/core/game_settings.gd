extends Node
## Autoload (GameSettings): player options that persist between runs —
## AI difficulty, game speed, music/effects volume, smart idle. The
## settings screen writes them (applying immediately), ConfigFile keeps
## them in user://settings.cfg, and the match reads them at kickoff.
## Audio routes through runtime-created Music/SFX buses so the two
## volume sliders work independently.

const SPEEDS := [0.5, 0.75, 1.0, 1.5, 2.0]
const SPEED_LABELS := ["50%", "75%", "100%", "150%", "200%"]
const PATH := "user://settings.cfg"
const MUSIC_BUS := "ZMusic"
const SFX_BUS := "ZSfx"

var difficulty := 1      # 0 easy, 1 normal, 2 hard -> MatchState.ai_difficulty
var speed_index := 2     # SPEEDS index; 2 = original speed
var music_volume := 0.8  # linear 0..1
var sfx_volume := 0.8
var auto_idle := true    # idle robots auto-grab hardware -> MatchState.auto_idle


func _ready() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	read()
	apply()


## Buses are made at runtime (no bus layout file to keep in sync).
func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"Master")


func read() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	difficulty = clampi(int(cfg.get_value("game", "difficulty", difficulty)), 0, 2)
	speed_index = clampi(int(cfg.get_value("game", "speed_index", speed_index)), 0, SPEEDS.size() - 1)
	auto_idle = bool(cfg.get_value("game", "auto_idle", auto_idle))
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "difficulty", difficulty)
	cfg.set_value("game", "speed_index", speed_index)
	cfg.set_value("game", "auto_idle", auto_idle)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.save(PATH)


## Push every option to wherever it is consumed. Safe to call repeatedly.
func apply() -> void:
	MatchState.ai_difficulty = difficulty
	MatchState.auto_idle = auto_idle
	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index(MUSIC_BUS), linear_to_db(music_volume))
	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index(SFX_BUS), linear_to_db(sfx_volume))


func game_speed() -> float:
	return SPEEDS[speed_index]
