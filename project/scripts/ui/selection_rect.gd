extends Control
## Draws the drag-selection rectangle; lives in a CanvasLayer in main.tscn.
## Redraws only while a drag is active (drag signals, no polling).

func _ready() -> void:
	SelectionManager.current.drag_started.connect(queue_redraw)
	SelectionManager.current.drag_moved.connect(queue_redraw)
	SelectionManager.current.drag_ended.connect(queue_redraw)


func _draw() -> void:
	if SelectionManager.current.is_dragging:
		var r := SelectionManager.current.get_drag_rect()
		draw_rect(r, Color(0.4, 1.0, 0.4, 0.15))
		draw_rect(r, Color(0.4, 1.0, 0.4, 0.9), false, 2.0)
