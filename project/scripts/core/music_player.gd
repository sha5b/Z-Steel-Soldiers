extends Node
## Autoload: original GOG soundtrack. Menu loop on the title, one of the
## battle loops in a match, win/lose jingles on game over. Tracks come
## from tools/gog/convert_assets.py (assets_original/gog/*.ogg).

const MENU_TRACK := "res://assets/z/music/ipOPTIONS16.ogg"
const BATTLE_TRACKS := [
	"res://assets/z/music/ipBATTLE16.ogg",
	"res://assets/z/music/AA16.ogg",
	"res://assets/z/music/aC16.ogg",
	"res://assets/z/music/aJ16.ogg",
]
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
	_player.bus = "Master"
	_player.volume_db = -8.0
	add_child(_player)


func play_menu() -> void:
	_play(MENU_TRACK, true)


func play_battle() -> void:
	_play(BATTLE_TRACKS[randi() % BATTLE_TRACKS.size()], true)


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
