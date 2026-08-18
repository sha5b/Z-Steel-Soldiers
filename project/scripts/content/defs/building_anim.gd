class_name BuildingAnim
extends Resource
## One animated overlay layer on a building (radar dish, factory spinner,
## repair smoke stack): numbered frames `<prefix>_<i>.png` from the
## building's art folder, played as a loop at `offset` over the base.

@export var prefix := "spin"
@export var fps := 6.0
@export var offset := Vector2.ZERO
