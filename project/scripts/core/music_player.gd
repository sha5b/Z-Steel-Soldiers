extends Node
## Autoload: original GOG soundtrack. Menu loop on the title, one of the
## battle loops in a match, win/lose jingles on game over. Tracks come
## from tools/gog/convert_assets.py (assets_original/gog/*.ogg); when a
## GOG track is absent, the PURE-GODOT zod MIDI renders (tools/
## render_midi.tscn, assets/z/music/zod_*.wav) stand in — no external
## synth dependency anywhere.

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

## GOG track -> its pure-Godot zod render counterpart.
const ZOD_FALLBACK := {
	"res://assets/z/music/AA16.ogg": "res://assets/z/music/zod_aa1.wav",
	"res://assets/z/music/aC16.ogg": "res://assets/z/music/zod_ac1.wav",
	"res://assets/z/music/aJ16.ogg": "res://assets/z/music/zod_aj1.wav",
	"res://assets/z/music/music_desert.ogg": "res://assets/z/music/zod_ad1.wav",
	"res://assets/z/music/music_volcanic.ogg": "res://assets/z/music/zod_av1.wav",
	"res://assets/z/music/ipBATTLE16.ogg": "res://assets/z/music/zod_abattle.wav",
	"res://assets/z/music/ipOPTIONS16.ogg": "res://assets/z/music/zod_aoptions.wav",
	"res://assets/z/music/ipWIN.ogg": "res://assets/z/music/zod_awin.wav",
	"res://assets/z/music/ipLOSE.ogg": "res://assets/z/music/zod_alose.wav",
}

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
	# missing GOG track -> the pure-Godot zod render of the same theme
	if not ResourceLoader.exists(path):
		path = ZOD_FALLBACK.get(path, "")
		_mode = path
		if path == "" or not ResourceLoader.exists(path):
			_mode = ""
			return
	else:
		_mode = path
	var stream = load(path)
	if stream == null:
		return
	# load() returns the SHARED cached resource — flip loop mode on a
	# duplicate so two users never fight over the cached stream's flags
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		var own: AudioStream = stream.duplicate()
		own.loop = loop
		stream = own
	elif stream is AudioStreamWAV:
		var own_wav: AudioStreamWAV = stream.duplicate()
		own_wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop \
				else AudioStreamWAV.LOOP_DISABLED
		own_wav.loop_end = own_wav.data.size() / 2  # 16-bit mono frames
		stream = own_wav
	_player.stream = stream
	_player.play()
