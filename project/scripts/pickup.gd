class_name Pickup
extends Node2D
## Grenade/rocket crate: collected by walking a unit over it. Grants the
## collector's team a permanent weapon upgrade (Z mechanic).

const TYPES := {
	"grenades": {"path": "res://assets/z/map_items/grenades.png",
		"sound": "res://assets/z/sounds/GRENADE.wav"},
	"rockets": {"path": "res://assets/z/map_items/rockets.png", "sound": ""},
}

@export var pickup_type := "grenades"

var _taken := false


func _ready() -> void:
	add_to_group("pickups")
	var sprite := Sprite2D.new()
	var info: Dictionary = TYPES.get(pickup_type, TYPES.grenades)
	if ResourceLoader.exists(info.path):
		sprite.texture = load(info.path)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(2, 2)
	add_child(sprite)


func _process(_delta: float) -> void:
	if _taken:
		return
	for u in get_tree().get_nodes_in_group("units"):
		if u is Node2D and u.alive and u.team != 0 \
				and u.global_position.distance_to(global_position) < 12.0:
			_collect(u.team)
			break


func _collect(team: int) -> void:
	_taken = true
	GameState.grant_upgrade(team, pickup_type)
	var info: Dictionary = TYPES.get(pickup_type, TYPES.grenades)
	if info.sound != "" and ResourceLoader.exists(info.sound):
		var player := AudioStreamPlayer.new()
		player.stream = load(info.sound)
		add_child(player)
		player.play()
		player.finished.connect(player.queue_free)
		await player.finished
	queue_free()
