class_name ProductionQueue
extends RefCounted
## Shared production state for every producer (fort, robot factory,
## vehicle factory): a FIFO of type names and one elapsed timer. Payment
## and spawning stay with the producer; this class only tracks time and
## order. `changed` fires on every enqueue/cancel/completion so the UI
## can stop polling.

signal changed

const MAX_ITEMS := 5

var items: Array[String] = []
var elapsed := 0.0


func enqueue(type_name: String) -> bool:
	if items.size() >= MAX_ITEMS:
		return false
	items.append(type_name)
	changed.emit()
	return true


## Removes and returns the entry at `index` ("" when out of range) — the
## caller decides about refunds.
func cancel_at(index: int) -> String:
	if index < 0 or index >= items.size():
		return ""
	var item: String = items.pop_at(index)
	if item != "":
		changed.emit()
	return item


func clear() -> void:
	items.clear()
	elapsed = 0.0


## Advances the timer; returns the finished type name (and pops it) or "".
func tick(delta: float, seconds: float) -> String:
	# an IDLE queue must not accumulate time — the first item after any
	# idle period used to complete on its very first tick
	if items.is_empty():
		elapsed = 0.0
		return ""
	elapsed += delta
	if elapsed < seconds:
		return ""
	elapsed = 0.0
	var done: String = items.pop_front()
	changed.emit()
	return done


## 0..1 progress of the item currently building.
func progress(seconds: float) -> float:
	if items.is_empty():
		return 0.0
	return clampf(elapsed / seconds, 0.0, 1.0)
