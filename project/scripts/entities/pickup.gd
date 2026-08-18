class_name Pickup
extends Node2D
## Grenade/rocket crate: collected by walking a unit over it. What a
## crate does is DATA on its PickupDef (content/pickups/): the upgrade it
## grants and the grenades it arms the collector with (Z mechanic).

@export var pickup_type := "grenades"

var _taken := false
var _def: PickupDef = null


func _ready() -> void:
	add_to_group("pickups")
	_def = ContentDB.pickup_def(pickup_type)
	var sprite := Sprite2D.new()
	if _def.texture != null:
		sprite.texture = _def.texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(2, 2)
	add_child(sprite)


func _process(_delta: float) -> void:
	if _taken:
		return
	for u in get_tree().get_nodes_in_group("units"):
		if u is Node2D and u.alive and u.team != 0 \
				and u.global_position.distance_to(global_position) < 12.0:
			if u is Unit2D:
				u.play_gesture("pickup-up")
				# grenade crates arm the collector with throwables
				# (original: SetGrenadeAmount on the robot)
				if _def.grenades > 0 and u.kind == "robot":
					u.grenades += _def.grenades
			_collect(u.team)
			break


func _collect(team: int) -> void:
	_taken = true
	if _def == null:
		_def = ContentDB.pickup_def(pickup_type)
	if _def.upgrade_key != "":
		GameState.grant_upgrade(team, _def.upgrade_key)
	Fx._play_set(_def.sound_set if _def.sound_set != "" else "pickup")
	queue_free()
