extends Node
## Autoload: looping battle music.

var _player: AudioStreamPlayer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)
	_pick_random_track()


func _pick_random_track() -> void:
	# anything in the music folder: shipped mp3 + oggs rendered by
	# tools/zod/render_midi.sh once fluidsynth is available
	var candidates: PackedStringArray = []
	for f in DirAccess.get_files_at("res://assets/z/music"):
		if String(f).ends_with(".mp3") or String(f).ends_with(".ogg"):
			candidates.append(f)
	if candidates.is_empty():
		return
	var pick: String = candidates[randi() % candidates.size()]
	var stream = load("res://assets/z/music/" + pick)
	if stream == null:
		return
	if stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamOggVorbis:
		stream.loop = true
	_player.stream = stream
	_player.volume_db = -8.0
	_player.play()
