extends Node2D
## Team-colored selection ellipse under a 16x16 unit sprite.

var color := Color(0.4, 1.0, 0.4)


func _draw() -> void:
	draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 24, color, 1.5)
