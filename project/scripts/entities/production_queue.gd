class_name ProductionQueue
extends RefCounted
## Shared production state for every producer (fort, robot factory,
## vehicle factory): a FIFO of type names and one elapsed timer. Payment
## and spawning stay with the producer; this class only tracks time and
## order.

var items: Array[String] = []
var elapsed := 0.0


func enqueue(type_name: String) -> void:
	items.append(type_name)


## Removes and returns the entry at `index` ("" when out of range) — the
## caller decides about refunds.
func cancel_at(index: int) -> String:
	if index < 0 or index >= items.size():
		return ""
	return items.pop_at(index)


func clear() -> void:
	items.clear()
	elapsed = 0.0


## Advances the timer; returns the finished type name (and pops it) or "".
func tick(delta: float, seconds: float) -> String:
	elapsed += delta
	if elapsed < seconds or items.is_empty():
		return ""
	elapsed = 0.0
	return items.pop_front()


## 0..1 progress of the item currently building.
func progress(seconds: float) -> float:
	if items.is_empty():
		return 0.0
	return clampf(elapsed / seconds, 0.0, 1.0)
