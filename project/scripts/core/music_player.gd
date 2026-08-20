extends Node
## Autoload: original GOG soundtrack. Menu loop on the title, one of the
## battle loops in a match, win/lose jingles on game over. Tracks come
## from tools/gog/convert_assets.py (assets_original/gog/*.ogg).

const MENU_TRACK := "res://assets/z/music/ipOPTIONS16.ogg"
## One battle theme PER PLANET, like the original. The GOG release ships
## arctic/city/jungle (AA16/aC16/aJ16); desert and volcanic exist only in
## the zod pack and reach us through tools/zod/copy_art.py. play_battle()
## used to pick at random from the four it knew, so two planets never
## heard their own theme and every other match played the wrong one.
const PLANET_TRACKS := {
	"arctic": "res://assets/z/music/AA16.ogg",
	"city": "res://assets/z/music/aC16.ogg",
	"jungle": "res://assets/z/music/aJ16.ogg",
	"desert": "res://assets/z/music/music_desert.ogg",
	"volcanic": "res://assets/z/music/music_volcanic.ogg",
}
const BATTLE_FALLBACK := "res://assets/z/music/ipBATTLE16.ogg"
const WIN_STINGER := "res://assets/z/music/ipWIN.ogg"
const LOSE_STINGER := "res://assets/z/music/ipLOSE.ogg"

var _player: AudioStreamPlayer
var _mode := ""


func _exit_tree() -> void:
	# quitting mid-track otherwise leaks the playing stream + its packet
	# sequence (they keep each other referenced outside the tree)
	if _player:
		_player.stop()
		_player.stream = null


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = GameSettings.MUSIC_BUS  # volume slider lives on the bus
	_player.volume_db = -8.0
	add_child(_player)


func play_menu() -> void:
	_play(MENU_TRACK, true)


## `planet` picks the theme; anything unknown or unconverted falls back
## to the generic battle loop.
func play_battle(planet := "") -> void:
	var track: String = PLANET_TRACKS.get(planet, "")
	if track == "" or not ResourceLoader.exists(track):
		track = BATTLE_FALLBACK
	_play(track, true)


func play_stinger(won: bool) -> void:
	_play(WIN_STINGER if won else LOSE_STINGER, false)


func stop() -> void:
	_player.stop()
	_mode = ""


func _play(path: String, loop: bool) -> void:
	if _mode == path:
		return
	_mode = path
	if not ResourceLoader.exists(path):
		return
	var stream = load(path)
	if stream == null:
		return
	# load() returns the SHARED cached resource — flip loop mode on a
	# duplicate so two users never fight over the cached stream's flags
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		var own: AudioStream = stream.duplicate()
		own.loop = loop
		stream = own
	_player.stream = stream
	_player.play()
