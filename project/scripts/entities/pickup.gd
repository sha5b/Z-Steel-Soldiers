class_name Pickup
extends Node2D
## Grenade/rocket crate: collected by walking a unit over it. Grants the
## collector's team the upgrade named by the def's `grants` key (Z
## mechanic). Crate types live in PickupDefs — add art + an entry to make
## a new drop.

@export var pickup_type := "grenades"

var _taken := false


func _ready() -> void:
	add_to_group("pickups")
	var sprite := Sprite2D.new()
	var info: Dictionary = ContentDB.pickup_def(pickup_type)
	if ResourceLoader.exists(String(info.get("texture", ""))):
		sprite.texture = load(String(info.texture))
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
				if pickup_type == "grenades" and u.kind == "robot":
					u.grenades += 4
			_collect(u.team)
			break


func _collect(team: int) -> void:
	_taken = true
	var info: Dictionary = ContentDB.pickup_def(pickup_type)
	GameState.grant_upgrade(team, String(info.get("grants", pickup_type)))
	Fx._play_set("pickup")
	queue_free()
