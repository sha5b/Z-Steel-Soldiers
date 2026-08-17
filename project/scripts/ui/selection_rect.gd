extends Control
## Draws the drag-selection rectangle; lives in a CanvasLayer in main.tscn.

func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var sm := SelectionManager
	if sm.is_dragging:
		var r := sm.get_drag_rect()
		draw_rect(r, Color(0.4, 1.0, 0.4, 0.15))
		draw_rect(r, Color(0.4, 1.0, 0.4, 0.9), false, 2.0)
