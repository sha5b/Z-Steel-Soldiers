extends Node
## Autoload: looping battle music.

var _player: AudioStreamPlayer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)
	var path := "res://assets/z/music/ABATTLE.mp3"
	if ResourceLoader.exists(path):
		var stream: AudioStreamMP3 = load(path)
		stream.loop = true
		_player.stream = stream
		_player.volume_db = -6.0
		_player.play()
